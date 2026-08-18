#!/bin/bash
# =============================================================================
# ntfy — push-уведомления. (позиция в меню — 5-я)
#
# ХОСТ — свой ntfy-сервер на этом сервере (docker), ПОЛНОСТЬЮ ВНУТРЕННИЙ.
# КЛИЕНТ — свой ntfy не ставим, шлём на существующий (ntfy.sh с секретным
# топиком, либо другой self-hosted сервер) — тут ничего не изменилось.
#
# ВАЖНОЕ ИЗМЕНЕНИЕ АРХИТЕКТУРЫ (см. историю обсуждения): раньше ntfy был
# доступен снаружи через Caddy — отдельный поддомен, браузерный адрес за
# общим шлюзом входа (Authelia) с трюком автоподстановки токена, плюс
# секретный путь для приложения на телефоне. ВСЁ ЭТО УБРАНО. Причина: решили,
# что нативное приложение ntfy на телефоне не нужно — уведомления читаются
# через NEXUS404 Hub (виджет в хабе, который сам подписывается на
# топик изнутри docker-сети), а push на телефон идёт через Web Push самого
# хаба (PWA), не через ntfy-приложение. Значит ntfy не нужно видеть снаружи
# вообще — ни браузеру, ни телефону, только двум внутренним потребителям:
# notify_send() (публикует) и будущему виджету хаба (читает). Ни поддомен,
# ни секретный путь, ни dk_sso_web-трюк больше не нужны — соответствующий
# код ниже удалён, а не "временно отключён".
#
# Хуки (SSH, fail2ban, автообновления, автоочистка, перезагрузка, health-check)
# одинаковы для обоих режимов — вызывают notify_send(), которая не знает,
# локальный ntfy или удалённый.
#
# STATEFILE: "step5_N".
# unattended-upgrades.log (шаг 5_7): формат строк сверен с исходниками
# пакета (github.com/mvo5/unattended-upgrades, logging.basicConfig format=
# '%(asctime)s %(levelname)s %(message)s'), поэтому:
#  - дата в начале строки всегда "YYYY-MM-DD HH:MM:SS,mmm" → grep "^${TODAY}"
#    (TODAY=date +%Y-%m-%d) корректен как якорь.
#  - "Packages that will be upgraded:" / "Packages that were upgraded:" —
#    точные строки из кода пакета, эвристика grep 'Packages that\|upgraded'
#    не даёт ложных срабатываний.
#  - слово "error" встречается в логе только через logging.error(...) →
#    уровень ERROR в тексте строки; в INFO/WARNING строках пакета слово
#    "error" не встречается, так что grep -ci 'error' не даёт ложных
#    срабатываний. Подтверждено статически по исходникам; проверка на
#    живом сервере всё ещё не заменена, но формат больше не гадание.
# ntfy user/token add уже подтверждены реальным прогоном (см. шаг 5_3).
# =============================================================================

enable_full_logging

echo "${BOLD}${CYAN}==========================================================================="
echo "  НАСТРОЙКА ПУШ-УВЕДОМЛЕНИЙ (NTFY)"
echo "===========================================================================${NC}"

TOTAL_STEPS=11
DONE_COUNT=$(grep -c '^step5_' "$STATEFILE" 2>/dev/null || true)
DONE_COUNT="${DONE_COUNT:-0}"
if [ "$DONE_COUNT" -gt 0 ] && [ "$DONE_COUNT" -lt "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Найден файл состояния: пройдено $DONE_COUNT из $TOTAL_STEPS шагов модуля, продолжаем"
elif [ "$DONE_COUNT" -ge "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Модуль уже был выполнен ранее (все $TOTAL_STEPS шагов пройдены)"
fi
echo ""

NTFY_DIR="$APPS_DIR/ntfy"
NTFY_LOCAL_PORT=2586
NTFY_MODE_FILE="$DK_DIR/deploy_kit.ntfy_mode"

# читает режим (host/client), выбранный на шаге 1; используется всеми
# последующими шагами, чтобы решить, нужен ли им локальный сервер
dk_ntfy_mode() {
    read_or_default "$NTFY_MODE_FILE" "host"
}

# Подстраховка (тот же приём, что forgejo_retrofit_compose): если ntfy уже
# был установлен ДО того, как виджету понадобилось удаление (раньше токен
# был read-only), права нужно обновить даже если шаг 3 уже отмечен
# пройденным — иначе для уже установленных серверов это не применится
# само. Безопасно вызывать всегда — если пользователя/контейнера ещё нет,
# просто ничего не делает.
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx dk_ntfy && \
   docker exec dk_ntfy ntfy user list 2>/dev/null | grep -q "^dk_hub_reader\b"; then
    docker exec dk_ntfy ntfy access dk_hub_reader "$(read_or_default "$NTFY_DIR/topic_name" "")" read-write >/dev/null 2>>"$LOGFILE" || true
fi

# ================== ШАГ 5_1 ==================
if is_done "step5_1"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 1: Имя сервера и режим работы"
    echo "===========================================================================${NC}"

    DK_DEFAULT_LABEL=$(hostname 2>/dev/null || echo "server")
    echo "${CYAN}[*]${NC} Это имя будет подписью в каждом уведомлении"
    read -rp "${YELLOW}[?]${NC} Имя сервера (Enter — '$DK_DEFAULT_LABEL'): " DK_LABEL_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
    echo "${DK_LABEL_INPUT:-$DK_DEFAULT_LABEL}" > "$SERVERNAMEFILE"
    echo "${GREEN}[✓]${NC} Имя сервера: $(cat "$SERVERNAMEFILE") — так будет подписано каждое уведомление"
    echo ""
    echo "  1) Хост — свой ntfy-сервер здесь (обычный сценарий)"
    echo "  2) Клиент — слать на уже существующий ntfy (свой или ntfy.sh)"
    echo ""

    NTFY_MODE=""
    while [ -z "$NTFY_MODE" ]; do
        if ! read -rp "${YELLOW}[?]${NC} Выберите вариант (1 или 2): " MODE_CHOICE; then
            echo "${RED}[!]${NC} Не удалось прочитать ввод"
            exit 1
        fi
        case "$MODE_CHOICE" in
            1) NTFY_MODE="host" ;;
            2) NTFY_MODE="client" ;;
            *) echo "${RED}[!]${NC} Введите 1 или 2" ;;
        esac
    done

    mkdir -p "$NTFY_DIR"
    echo "$NTFY_MODE" > "$NTFY_MODE_FILE"

    if [ "$NTFY_MODE" = "host" ]; then
        echo "${GREEN}[✓]${NC} Режим: хост"
    else
        echo "${GREEN}[✓]${NC} Режим: клиент"
        echo ""
        echo "  1) ntfy.sh с секретным топиком — без пароля, приватность за счёт того,"
        echo "     что имя топика никому не известно"
        echo "  2) свой существующий ntfy-сервер (URL, топик, при необходимости токен)"
        echo ""

        TARGET_CHOICE=""
        while [ -z "$TARGET_CHOICE" ]; do
            if ! read -rp "${YELLOW}[?]${NC} Выберите вариант (1 или 2): " TC; then
                echo "${RED}[!]${NC} Не удалось прочитать ввод"
                exit 1
            fi
            case "$TC" in
                1) TARGET_CHOICE="public" ;;
                2) TARGET_CHOICE="custom" ;;
                *) echo "${RED}[!]${NC} Введите 1 или 2" ;;
            esac
        done

        NTFY_URL_INPUT=""
        NTFY_TOPIC_INPUT=""
        NTFY_TOKEN_INPUT=""

        if [ "$TARGET_CHOICE" = "public" ]; then
            NTFY_URL_INPUT="https://ntfy.sh"
            NTFY_TOPIC_INPUT="dk_$(tr -dc 'a-z0-9' < /dev/urandom | head -c 32)"
            echo ""
            echo "${GREEN}[✓]${NC} Секретный топик: $NTFY_TOPIC_INPUT"
            echo "${YELLOW}[?]${NC} Топик не защищён паролем — держите имя в секрете"
            echo "${CYAN}[*]${NC} Подпишитесь: https://ntfy.sh/${NTFY_TOPIC_INPUT}"
        else
            while [ -z "$NTFY_URL_INPUT" ]; do
                read -rp "${YELLOW}[?]${NC} Базовый URL сервера (например https://ntfy.example.com): " NTFY_URL_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
            done
            while [ -z "$NTFY_TOPIC_INPUT" ]; do
                read -rp "${YELLOW}[?]${NC} Топик: " NTFY_TOPIC_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
            done
            read -rsp "${YELLOW}[?]${NC} Токен доступа (Bearer, Enter — если авторизация не нужна): " NTFY_TOKEN_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
            echo ""
        fi

        cat > "$NTFY_CONF" << EOF
NTFY_URL="${NTFY_URL_INPUT}"
NTFY_TOPIC="${NTFY_TOPIC_INPUT}"
NTFY_TOKEN="${NTFY_TOKEN_INPUT}"
EOF
        chmod 600 "$NTFY_CONF"
        touch "$NTFYLOG"
        chmod 644 "$NTFYLOG"
        echo "${GREEN}[✓]${NC} Конфиг notify_send сохранён: $NTFY_CONF (права 600)"
    fi

    echo "${GREEN}[✓]${NC} Шаг 1 завершён успешно"
    mark_done "step5_1"
fi

# ================== ШАГ 5_2 ==================
if is_done "step5_2"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 2: Сервер ntfy"
    echo "===========================================================================${NC}"

    if [ "$(dk_ntfy_mode)" != "host" ]; then
        echo "${CYAN}[*]${NC} Режим клиента — свой сервер не нужен, пропускаю"
    else
        if ! check_disk_space 256; then
            echo "${RED}[!]${NC} Меньше 256 MB свободного места на диске — недостаточно для ntfy"
            exit 1
        fi

        retry_apt "Установка jq (нужен для notify_send — JSON publish в ntfy)" "apt-get install -y jq"

        mkdir -p "$NTFY_DIR/data"

        # base-url — ВНУТРЕННИЙ адрес контейнера, не внешний домен. ntfy
        # больше не публикуется наружу вообще (см. заголовок файла) — этот
        # URL встречается только внутри текста уведомлений (кнопки действий,
        # ссылки отписки), которые открывать снаружи никто не будет, раз
        # единственный потребитель — виджет хаба изнутри той же docker-сети.
        NTFY_BASE_URL="http://dk_ntfy"

        if [ ! -f "$NTFY_DIR/server.yml" ]; then
            cat > "$NTFY_DIR/server.yml" << EOF
base-url: "${NTFY_BASE_URL}"
listen-http: ":80"
auth-file: "/var/lib/ntfy/auth.db"
auth-default-access: "deny-all"
behind-proxy: false
cache-file: "/var/lib/ntfy/cache.db"
attachment-cache-dir: "/var/lib/ntfy/attachments"
EOF
            echo "${GREEN}[✓]${NC} server.yml создан (base-url: ${NTFY_BASE_URL},"
            echo "    auth-default-access: deny-all, полностью внутренний сервис)"
        else
            echo "${CYAN}[*]${NC} server.yml уже существует, не трогаю (возможны ручные правки)"
        fi

        cat > "$NTFY_DIR/docker-compose.yml" << EOF
services:
  ntfy:
    image: binwiederhier/ntfy:latest
    container_name: dk_ntfy
    restart: unless-stopped
    command: serve
    volumes:
      - ./data:/var/lib/ntfy
      - ./server.yml:/etc/ntfy/server.yml:ro
    ports:
      - "127.0.0.1:${NTFY_LOCAL_PORT}:80"
    networks:
      - ${DK_NETWORK}

networks:
  ${DK_NETWORK}:
    external: true
EOF
        echo "${GREEN}[✓]${NC} docker-compose.yml создан: $NTFY_DIR/docker-compose.yml"
        echo "${CYAN}[*]${NC} Порт слушает только 127.0.0.1 (сам хост) — снаружи сервера"
        echo "    недоступен ни при каких обстоятельствах. Остальные контейнеры"
        echo "    (виджет хаба) обращаются по имени dk_ntfy:80 внутри docker-сети."

        run_spinner "Запуск ntfy" "dk_compose_up '$NTFY_DIR'"
        (cd "$NTFY_DIR" && docker compose up -d --force-recreate >/dev/null 2>>"$LOGFILE") || true

        echo "${CYAN}[*]${NC} Жду готовности ntfy..."
        NTFY_READY=0
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            if curl -fsS -m 3 "http://127.0.0.1:${NTFY_LOCAL_PORT}/v1/health" >/dev/null 2>>"$LOGFILE"; then
                NTFY_READY=1
                break
            fi
            sleep 2
        done

        if [ "$NTFY_READY" -eq 1 ]; then
            echo "${GREEN}[✓]${NC} ntfy отвечает на http://127.0.0.1:${NTFY_LOCAL_PORT}"
        else
            echo "${RED}[!]${NC} ntfy не ответил за 20 секунд — проверьте контейнер: docker logs dk_ntfy"
            exit 1
        fi
    fi

    echo "${GREEN}[✓]${NC} Шаг 2 завершён успешно"
    mark_done "step5_2"
fi

# ================== ШАГ 5_3 ==================
if is_done "step5_3"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 3: Администратор, топик и сервисный токен"
    echo "===========================================================================${NC}"

    if [ "$(dk_ntfy_mode)" != "host" ]; then
        echo "${CYAN}[*]${NC} Режим клиента — конфиг notify_send уже задан на шаге 1, пропускаю"
    else
        echo "${CYAN}[*]${NC} Создадим: администратора (для ручного управления через docker exec)"
        echo "    и служебный токен для notify_send"
        echo ""

        NTFY_ADMIN_USER_DEFAULT=$(read_or_default "$DK_SHARED_LOGIN_FILE" "admin")
        read -rp "${YELLOW}[?]${NC} Логин администратора ntfy (Enter — '$NTFY_ADMIN_USER_DEFAULT'): " NTFY_ADMIN_USER_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
        NTFY_ADMIN_USER="${NTFY_ADMIN_USER_INPUT:-$NTFY_ADMIN_USER_DEFAULT}"
        echo "$NTFY_ADMIN_USER" > "$DK_SHARED_LOGIN_FILE"

        NTFY_ADMIN_PASS=""
        while true; do
            read -rsp "${YELLOW}[?]${NC} Пароль администратора ntfy (минимум 8 символов): " NTFY_ADMIN_PASS || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
            echo ""
            if [ "${#NTFY_ADMIN_PASS}" -lt 8 ]; then
                echo "${RED}[!]${NC} Слишком короткий пароль (минимум 8 символов), попробуйте снова"
                continue
            fi
            read -rsp "${YELLOW}[?]${NC} Повторите пароль: " NTFY_ADMIN_PASS_CONFIRM || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
            echo ""
            if [ "$NTFY_ADMIN_PASS" == "$NTFY_ADMIN_PASS_CONFIRM" ]; then
                break
            else
                echo "${RED}[!]${NC} Пароли не совпадают, попробуйте снова"
            fi
        done

        # Подтверждено реальным прогоном: `ntfy user add` принимает пароль
        # дважды через stdin (ввод + подтверждение) без проблем.
        if ! docker exec dk_ntfy ntfy user list 2>>"$LOGFILE" | grep -q "^${NTFY_ADMIN_USER}\b"; then
            if { printf '%s\n%s\n' "$NTFY_ADMIN_PASS" "$NTFY_ADMIN_PASS"; } | docker exec -i dk_ntfy ntfy user add --role=admin "$NTFY_ADMIN_USER" >>"$LOGFILE" 2>&1; then
                echo "${GREEN}[✓]${NC} Администратор '$NTFY_ADMIN_USER' создан (роль admin)"
            else
                echo "${RED}[!]${NC} Не удалось создать администратора —"
                echo "    смотрите $LOGFILE"
                exit 1
            fi
        else
            echo "${CYAN}[*]${NC} Пользователь '$NTFY_ADMIN_USER' уже существует, пропускаю"
        fi

        NTFY_TOPIC="dk_alerts_$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)"
        echo "$NTFY_TOPIC" > "$NTFY_DIR/topic_name"
        chmod 644 "$NTFY_DIR/topic_name"
        echo "${GREEN}[✓]${NC} Топик для уведомлений: $NTFY_TOPIC"

        NTFY_SVC_USER="dk_notifier"
        NTFY_SVC_PASS="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 24)"
        if ! docker exec dk_ntfy ntfy user list 2>>"$LOGFILE" | grep -q "^${NTFY_SVC_USER}\b"; then
            if { printf '%s\n%s\n' "$NTFY_SVC_PASS" "$NTFY_SVC_PASS"; } | docker exec -i dk_ntfy ntfy user add --role=user "$NTFY_SVC_USER" >>"$LOGFILE" 2>&1; then
                echo "${GREEN}[✓]${NC} Служебный пользователь '$NTFY_SVC_USER' создан"
            else
                echo "${RED}[!]${NC} Не удалось создать служебного пользователя —"
                echo "    смотрите $LOGFILE"
                exit 1
            fi
        else
            echo "${CYAN}[*]${NC} Служебный пользователь '$NTFY_SVC_USER' уже существует, пропускаю"
        fi

        check_or_fail "ограничение доступа '$NTFY_SVC_USER' только записью в '$NTFY_TOPIC'" \
            docker exec dk_ntfy ntfy access "$NTFY_SVC_USER" "$NTFY_TOPIC" write-only

        # Подтверждено реальным прогоном: `ntfy token add <user>` печатает
        # токен в stdout, grep находит его корректно.
        NTFY_TOKEN=$(docker exec dk_ntfy ntfy token add "$NTFY_SVC_USER" 2>>"$LOGFILE" | grep -oE 'tk_[A-Za-z0-9]+' | tail -n1)
        if [ -z "$NTFY_TOKEN" ]; then
            echo "${RED}[!]${NC} Не удалось получить токен для '$NTFY_SVC_USER' —"
            echo "    смотрите $LOGFILE"
            echo "    Проверьте вручную: docker exec dk_ntfy ntfy token add $NTFY_SVC_USER"
            exit 1
        fi
        echo "${GREEN}[✓]${NC} Токен для внутренних уведомлений получен"

        # Токен для будущего виджета хаба (NEXUS404 Hub) — читает
        # уведомления из топика для отображения в карточке ntfy. Отдельный
        # от NTFY_TOKEN выше (тот — только на запись, этот — теперь на
        # чтение И запись: нужно для удаления уведомлений из виджета хаба,
        # см. common.sh — DELETE публикует событие message_delete).
        NTFY_HUB_USER="dk_hub_reader"
        NTFY_HUB_TOKEN_FILE="$NTFY_DIR/hub_reader_token"
        if ! docker exec dk_ntfy ntfy user list 2>>"$LOGFILE" | grep -q "^${NTFY_HUB_USER}\b"; then
            NTFY_HUB_PASS="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 24)"
            if { printf '%s\n%s\n' "$NTFY_HUB_PASS" "$NTFY_HUB_PASS"; } | docker exec -i dk_ntfy ntfy user add --role=user "$NTFY_HUB_USER" >>"$LOGFILE" 2>&1; then
                echo "${GREEN}[✓]${NC} Служебный пользователь '$NTFY_HUB_USER' создан (для виджета хаба)"
            else
                echo "${RED}[!]${NC} Не удалось создать '$NTFY_HUB_USER' —"
                echo "    смотрите $LOGFILE"
                exit 1
            fi
        else
            echo "${CYAN}[*]${NC} Служебный пользователь '$NTFY_HUB_USER' уже существует, пропускаю"
        fi

        check_or_fail "доступ '$NTFY_HUB_USER' на чтение-запись '$NTFY_TOPIC' (нужно для удаления)" \
            docker exec dk_ntfy ntfy access "$NTFY_HUB_USER" "$NTFY_TOPIC" read-write

        if [ ! -s "$NTFY_HUB_TOKEN_FILE" ]; then
            NTFY_HUB_TOKEN=$(docker exec dk_ntfy ntfy token add "$NTFY_HUB_USER" 2>>"$LOGFILE" | grep -oE 'tk_[A-Za-z0-9]+' | tail -n1)
            if [ -z "$NTFY_HUB_TOKEN" ]; then
                echo "${RED}[!]${NC} Не удалось получить токен для '$NTFY_HUB_USER' —"
                echo "    смотрите $LOGFILE"
                echo "    Проверьте вручную: docker exec dk_ntfy ntfy token add $NTFY_HUB_USER"
                exit 1
            fi
            echo "$NTFY_HUB_TOKEN" > "$NTFY_HUB_TOKEN_FILE"
            chmod 600 "$NTFY_HUB_TOKEN_FILE"
            echo "${GREEN}[✓]${NC} Токен для виджета хаба сохранён ($NTFY_HUB_TOKEN_FILE, права 600)"
            echo "${CYAN}[*]${NC} Виджет ещё не написан — токен просто ждёт своего часа,"
            echo "    ничего не сломается, если он пока не используется"
        else
            echo "${CYAN}[*]${NC} Токен для виджета хаба уже существует, пропускаю"
        fi

        cat > "$NTFY_CONF" << EOF
NTFY_URL="http://127.0.0.1:${NTFY_LOCAL_PORT}"
NTFY_TOPIC="${NTFY_TOPIC}"
NTFY_TOKEN="${NTFY_TOKEN}"
EOF
        chmod 600 "$NTFY_CONF"
        touch "$NTFYLOG"
        chmod 644 "$NTFYLOG"
        echo "$NTFY_ADMIN_USER" > "$NTFY_DIR/admin_user"
        echo "${GREEN}[✓]${NC} Конфиг notify_send сохранён: $NTFY_CONF (права 600)"
        echo "${CYAN}[*]${NC} Топик '$NTFY_TOPIC' используется только внутри сервера —"
        echo "    notify_send публикует, виджет хаба (когда будет готов) читает"
    fi

    echo "${GREEN}[✓]${NC} Шаг 3 завершён успешно"
    mark_done "step5_3"
fi

# ================== ШАГ 5_4 ==================
if is_done "step5_4"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 4: Карточка в хабе (NEXUS404 Hub)"
    echo "===========================================================================${NC}"

    # Раньше здесь была публикация ntfy через Caddy (поддомен + секретный
    # путь для приложения) — убрана целиком, см. заголовок файла: ntfy
    # больше не имеет внешнего адреса вообще, ни для браузера, ни для
    # телефона. Вместо этого — карточка в хабе (add_hub_card из common.sh),
    # mode=widget: своя вёрстка по данным API, а не встраивание чужой
    # веб-морды (встраивать в iframe уже нечего — снаружи её не существует).
    # Безопасно вызывать, даже если хаб (NEXUS404 Hub) ещё не
    # установлен — карточка просто накопится и появится сама, когда он
    # будет развёрнут (см. common.sh:add_hub_card).
    if [ "$(dk_ntfy_mode)" = "host" ]; then
        # Подстраховка: если шаг 3 прошёл ДО того, как здесь появилось
        # сохранение topic_name (см. историю) — досоздаём файл из NTFY_CONF,
        # иначе будущему виджету-читателю нечем будет узнать имя топика.
        if [ ! -s "$NTFY_DIR/topic_name" ] && [ -f "$NTFY_CONF" ]; then
            (
                # shellcheck disable=SC1090
                source "$NTFY_CONF"
                [ -n "${NTFY_TOPIC:-}" ] && echo "$NTFY_TOPIC" > "$NTFY_DIR/topic_name"
            )
            [ -s "$NTFY_DIR/topic_name" ] && chmod 644 "$NTFY_DIR/topic_name"
        fi

        add_hub_card "ntfy" "Push-уведомления" "" "fas fa-bell" "Сервисы" "widget" "ntfy-feed"
        echo "${GREEN}[✓]${NC} Карточка ntfy зарегистрирована в хабе (mode=widget)"
    else
        echo "${CYAN}[*]${NC} Режим клиента (внешний ntfy) — своей карточки в хабе не будет,"
        echo "    показывать через виджет нечего (сервер не наш)"
    fi

    echo "${GREEN}[✓]${NC} Шаг 4 завершён успешно"
    mark_done "step5_4"
fi

# ================== ШАГ 5_5 ==================
if is_done "step5_5"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 5: Наблюдатель за успешными входами по SSH"
    echo "===========================================================================${NC}"

    cat > /usr/local/bin/deploy_kit_ssh_watch.sh << 'EOF'
#!/bin/bash
# deploy_kit: следит за журналом SSH-службы и шлёт уведомление на каждый
# УСПЕШНЫЙ вход (логин, адрес, способ). Не трогает сам процесс аутентификации
# (в отличие от PAM-хуков) — если этот скрипт упадёт, SSH продолжит работать
# как ни в чём не бывало.
source /var/lib/deploy_kit/common.sh

SSH_UNIT="ssh"
systemctl is-active --quiet ssh || SSH_UNIT="sshd"

journalctl -f -u "$SSH_UNIT" -o cat --no-pager | while IFS= read -r line; do
    if [[ "$line" =~ Accepted\ (password|publickey)\ for\ ([a-zA-Z0-9_.-]+)\ from\ ([0-9a-fA-F:.]+) ]]; then
        method="${BASH_REMATCH[1]}"
        user="${BASH_REMATCH[2]}"
        addr="${BASH_REMATCH[3]}"
        notify_send "ssh_login_ok" "Вход на сервер" "${user} · ${addr} · ${method}" 4 "unlock"
    fi
done
EOF
    chmod +x /usr/local/bin/deploy_kit_ssh_watch.sh
    echo "${GREEN}[✓]${NC} Скрипт-наблюдатель создан: /usr/local/bin/deploy_kit_ssh_watch.sh"

    cat > /etc/systemd/system/deploy_kit_ssh_watch.service << 'EOF'
[Unit]
Description=deploy_kit: уведомления об успешных входах по SSH (ntfy)
After=network.target

[Service]
ExecStart=/usr/local/bin/deploy_kit_ssh_watch.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    check_or_fail "перечитывание systemd-юнитов" systemctl daemon-reload
    run_spinner "Запуск наблюдателя за SSH-входами" "systemctl enable --now deploy_kit_ssh_watch.service"

    echo "${GREEN}[✓]${NC} Шаг 5 завершён успешно"
    mark_done "step5_5"
fi

# ================== ШАГ 5_6 ==================
if is_done "step5_6"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 6: Уведомление о бане fail2ban (попытки входа)"
    echo "===========================================================================${NC}"

    cat > /usr/local/bin/deploy_kit_notify_ban.sh << 'EOF'
#!/bin/bash
# Вызывается fail2ban при бане IP (см. /etc/fail2ban/action.d/deploy_kit_notify.conf)
source /var/lib/deploy_kit/common.sh
IP="${1:-?}"
JAIL="${2:-?}"
FAILURES="${3:-?}"
notify_send "ssh_ban" "Адрес заблокирован" "${IP} · ${JAIL} · попыток: ${FAILURES}" 4 "warning"
EOF
    chmod +x /usr/local/bin/deploy_kit_notify_ban.sh
    echo "${GREEN}[✓]${NC} Скрипт уведомления о бане создан:"
    echo "    /usr/local/bin/deploy_kit_notify_ban.sh"

    mkdir -p /etc/fail2ban/action.d
    cat > /etc/fail2ban/action.d/deploy_kit_notify.conf << 'EOF'
[Definition]
actionban = /usr/local/bin/deploy_kit_notify_ban.sh <ip> <name> <failures>
actionunban =
EOF
    echo "${GREEN}[✓]${NC} Action fail2ban создан: /etc/fail2ban/action.d/deploy_kit_notify.conf"

    JAIL_LOCAL="/etc/fail2ban/jail.local"
    if [ -f "$JAIL_LOCAL" ] && grep -q '^\[sshd\]' "$JAIL_LOCAL"; then
        if grep -q 'deploy_kit_notify' "$JAIL_LOCAL"; then
            echo "${CYAN}[*]${NC} Хук уведомления уже подключён в jail.local, пропускаю"
        else
            sed -i '/^\[sshd\]/a action = %(action_)s\n         deploy_kit_notify[name=%(__name__)s]' "$JAIL_LOCAL"
            run_spinner "Перезапуск fail2ban с хуком уведомлений" "systemctl restart fail2ban"
            echo "${GREEN}[✓]${NC} jail.local дополнен хуком (секция [sshd]), fail2ban перезапущен"
        fi
    else
        echo "${YELLOW}[?]${NC} $JAIL_LOCAL не найден или нет секции [sshd] — сначала выполните"
        echo "    модуль 1, шаг 8 (Fail2ban), затем запустите этот шаг заново"
    fi

    echo "${GREEN}[✓]${NC} Шаг 6 завершён успешно"
    mark_done "step5_6"
fi

# ================== ШАГ 5_7 ==================
if is_done "step5_7"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 7: Уведомление об автообновлениях"
    echo "===========================================================================${NC}"

    # Формат строк сверен статически с upstream-исходниками пакета (см.
    # комментарий в шапке файла) — эвристика по ключевым словам, не строгий
    # парсинг, но больше не непроверенное предположение. Живой прогон логов
    # реального сервера всё ещё стоит сделать при первой возможности.
    cat > /usr/local/bin/deploy_kit_notify_updates.sh << 'EOF'
#!/bin/bash
source /var/lib/deploy_kit/common.sh
LOG="/var/log/unattended-upgrades/unattended-upgrades.log"
[ -f "$LOG" ] || exit 0

TODAY="$(date '+%Y-%m-%d')"
BLOCK="$(grep "^${TODAY}" "$LOG" || true)"
[ -n "$BLOCK" ] || exit 0

UPGRADED_LINE="$(echo "$BLOCK" | grep -i 'Packages that\|upgraded' | tail -n1 || true)"
ERR_COUNT="$(echo "$BLOCK" | grep -ci 'error' || true)"
ERR_COUNT="${ERR_COUNT:-0}"

REBOOT_REQ="нет"
[ -f /var/run/reboot-required ] && REBOOT_REQ="да"

if [ "$ERR_COUNT" -gt 0 ]; then
    notify_send "update_fail" "Обновление: есть ошибки" "Ошибок: ${ERR_COUNT} · перезагрузка: ${REBOOT_REQ}" 5 "warning"
else
    UPGRADED_SHORT="${UPGRADED_LINE:-Изменений не найдено}"
    UPGRADED_SHORT="${UPGRADED_SHORT:0:80}"
    notify_send "update_ok" "Сервер обновился" "${UPGRADED_SHORT} · перезагрузка: ${REBOOT_REQ}" 3 "white_check_mark"
fi
EOF
    chmod +x /usr/local/bin/deploy_kit_notify_updates.sh
    echo "${GREEN}[✓]${NC} Скрипт уведомления об обновлениях создан"

    mkdir -p /etc/systemd/system/apt-daily-upgrade.service.d
    cat > /etc/systemd/system/apt-daily-upgrade.service.d/deploy_kit_notify.conf << 'EOF'
[Service]
ExecStopPost=/usr/local/bin/deploy_kit_notify_updates.sh
EOF
    check_or_fail "перечитывание systemd-юнитов" systemctl daemon-reload
    echo "${GREEN}[✓]${NC} Хук подключён:"
    echo "    /etc/systemd/system/apt-daily-upgrade.service.d/deploy_kit_notify.conf"

    echo "${GREEN}[✓]${NC} Шаг 7 завершён успешно"
    mark_done "step5_7"
fi

# ================== ШАГ 5_8 ==================
if is_done "step5_8"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 8: Уведомление об автоочистке"
    echo "===========================================================================${NC}"

    cat > /usr/local/bin/deploy_kit_notify_cleanup.sh << 'EOF'
#!/bin/bash
source /var/lib/deploy_kit/common.sh
BEFORE_MB=$(df -Pm / | awk 'NR==2{print $4}')
BEFORE_MB="${BEFORE_MB:-0}"
/usr/local/bin/deploy_kit_cleanup.sh
AFTER_MB=$(df -Pm / | awk 'NR==2{print $4}')
AFTER_MB="${AFTER_MB:-0}"
FREED=$(( AFTER_MB - BEFORE_MB ))
[ "$FREED" -lt 0 ] && FREED=0
notify_send "cleanup_ok" "Сервер очищен" "Освобождено: ${FREED} МБ" 3 "wastebasket"
EOF
    chmod +x /usr/local/bin/deploy_kit_notify_cleanup.sh
    echo "${GREEN}[✓]${NC} Скрипт-обёртка создан: /usr/local/bin/deploy_kit_notify_cleanup.sh"

    CLEANUP_CRON="/etc/cron.d/deploy_kit_cleanup"
    if [ -f "$CLEANUP_CRON" ]; then
        if grep -q 'deploy_kit_notify_cleanup' "$CLEANUP_CRON"; then
            echo "${CYAN}[*]${NC} cron уже указывает на обёртку с уведомлением, пропускаю"
        else
            SCHEDULE=$(awk '{print $1, $2, $3, $4, $5}' "$CLEANUP_CRON" | head -n1)
            if [ -n "$SCHEDULE" ]; then
                echo "$SCHEDULE root /usr/local/bin/deploy_kit_notify_cleanup.sh" > "$CLEANUP_CRON"
                echo "${GREEN}[✓]${NC} $CLEANUP_CRON переключён на обёртку (расписание сохранено: $SCHEDULE)"
            else
                echo "${RED}[!]${NC} Не удалось прочитать расписание из $CLEANUP_CRON"
                exit 1
            fi
        fi
    else
        echo "${YELLOW}[?]${NC} $CLEANUP_CRON не найден — сначала выполните модуль 1, шаг 12"
        echo "    (Автообновления, автоочистка, автоперезагрузка), затем"
        echo "    повторите этот шаг"
    fi

    echo "${GREEN}[✓]${NC} Шаг 8 завершён успешно"
    mark_done "step5_8"
fi

# ================== ШАГ 5_9 ==================
if is_done "step5_9"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 9: Уведомление о перезагрузке"
    echo "===========================================================================${NC}"

    cat > /usr/local/bin/deploy_kit_notify_boot.sh << 'EOF'
#!/bin/bash
source /var/lib/deploy_kit/common.sh
for _ in 1 2 3 4 5 6; do
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qx dk_ntfy && break
    sleep 5
done
BOOT_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
notify_send "reboot" "Сервер перезагружен" "Загрузка: ${BOOT_TIME}" 4 "arrows_counterclockwise"
EOF
    chmod +x /usr/local/bin/deploy_kit_notify_boot.sh
    echo "${GREEN}[✓]${NC} Скрипт уведомления о перезагрузке создан"

    cat > /etc/systemd/system/deploy_kit_notify_boot.service << 'EOF'
[Unit]
Description=deploy_kit: уведомление о перезагрузке сервера (ntfy)
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/deploy_kit_notify_boot.sh

[Install]
WantedBy=multi-user.target
EOF

    check_or_fail "перечитывание systemd-юнитов" systemctl daemon-reload
    check_or_fail "включение уведомления о перезагрузке" systemctl enable deploy_kit_notify_boot.service
    echo "${GREEN}[✓]${NC} Уведомление о перезагрузке включено (сработает при следующей загрузке)"

    echo "${GREEN}[✓]${NC} Шаг 9 завершён успешно"
    mark_done "step5_9"
fi

# ================== ШАГ 5_10 ==================
if is_done "step5_10"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 10: Уведомление о health-check"
    echo "===========================================================================${NC}"

    cat > /usr/local/bin/deploy_kit_notify_healthcheck.sh << 'EOF'
#!/bin/bash
source /var/lib/deploy_kit/common.sh
LOG="$HEALTHLOG"
[ -f "$LOG" ] || exit 0

LAST_LINE_NO=$(grep -n '^===== ' "$LOG" | tail -n1 | cut -d: -f1)
[ -n "$LAST_LINE_NO" ] || exit 0
BLOCK="$(tail -n +"$LAST_LINE_NO" "$LOG")"

if echo "$BLOCK" | grep -q '\[ВНИМАНИЕ\]'; then
    ISSUES_COUNT="$(echo "$BLOCK" | grep -c '\[ВНИМАНИЕ\]')"
    ISSUES="$(echo "$BLOCK" | grep '\[ВНИМАНИЕ\]' | sed 's/\[ВНИМАНИЕ\] *//' | head -n3 | tr '\n' ';' | sed 's/;/; /g')"
    ISSUES="${ISSUES%; }"
    ISSUES="${ISSUES:0:120}"
    if [ "$ISSUES_COUNT" -gt 3 ]; then
        ISSUES="${ISSUES} (и ещё $((ISSUES_COUNT - 3)))"
    fi
    notify_send "healthcheck_fail" "Проверка: есть замечания" "${ISSUES}" 4 "warning"
else
    notify_send "healthcheck_ok" "Проверка сервера" "Всё в норме" 3 "white_check_mark"
fi
EOF
    chmod +x /usr/local/bin/deploy_kit_notify_healthcheck.sh
    echo "${GREEN}[✓]${NC} Скрипт уведомления о health-check создан"

    HC_CRON="/etc/cron.d/deploy_kit_healthcheck"
    NOTIFY_HC_CRON="/etc/cron.d/deploy_kit_notify_healthcheck"
    if [ -f "$HC_CRON" ]; then
        HC_MIN=$(awk '{print $1}' "$HC_CRON" | head -n1)
        HC_HOUR=$(awk '{print $2}' "$HC_CRON" | head -n1)
        if [[ "$HC_MIN" =~ ^[0-9]+$ ]] && [[ "$HC_HOUR" =~ ^[0-9]+$ ]]; then
            TOTAL_MIN=$(( HC_HOUR * 60 + HC_MIN + 5 ))
            NOTIFY_HOUR=$(( (TOTAL_MIN / 60) % 24 ))
            NOTIFY_MIN=$(( TOTAL_MIN % 60 ))
            cat > "$NOTIFY_HC_CRON" << EOF
$NOTIFY_MIN $NOTIFY_HOUR * * * root /usr/local/bin/deploy_kit_notify_healthcheck.sh
EOF
            printf "${GREEN}[✓]${NC} Уведомление о health-check настроено: через 5 минут после самой проверки (%02d:%02d)\n" "$NOTIFY_HOUR" "$NOTIFY_MIN"
        else
            echo "${RED}[!]${NC} Не удалось прочитать расписание из $HC_CRON"
            exit 1
        fi
    else
        echo "${YELLOW}[?]${NC} $HC_CRON не найден — сначала выполните модуль 1, шаг 13 (Health-checker),"
        echo "    затем повторите этот шаг"
    fi

    echo "${GREEN}[✓]${NC} Шаг 10 завершён успешно"
    mark_done "step5_10"
fi

# ================== ШАГ 5_11 ==================
if is_done "step5_11"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 11: Тестовое уведомление и финальная проверка"
    echo "===========================================================================${NC}"

    echo "${CYAN}[*]${NC} Отправляю тестовое уведомление..."
    notify_send "test" "deploy_kit: ntfy настроен" "Push-уведомления работают" 3 "tada"

    CHECK_FAILED=0
    echo "===== Результаты финальной проверки модуля ntfy ($(date '+%Y-%m-%d %H:%M:%S')) =====" >> "$LOGFILE"

    if [ "$(dk_ntfy_mode)" = "host" ]; then
        check_item "Контейнер ntfy запущен" bash -c "docker ps --format '{{.Names}}' | grep -qx dk_ntfy"
        check_item "ntfy отвечает локально" curl -fsS -m 3 "http://127.0.0.1:${NTFY_LOCAL_PORT}/v1/health"
        check_item "Хук автообновлений подключён" test -f /etc/systemd/system/apt-daily-upgrade.service.d/deploy_kit_notify.conf
        check_item "Карточка ntfy зарегистрирована в хабе" hub_card_exists "ntfy"
    else
        echo "${CYAN}[*]${NC} Режим клиента — проверки локального сервера пропущены"
    fi
    check_item "Конфиг notify_send существует" test -f "$NTFY_CONF"
    check_item "Отдельный лог уведомлений существует" test -f "$NTFYLOG"
    check_item "Наблюдатель за SSH-входами запущен" systemctl is-active --quiet deploy_kit_ssh_watch.service
    check_item "Хук уведомления о перезагрузке включён" systemctl is-enabled --quiet deploy_kit_notify_boot.service

    echo ""
    if tail -n1 "$NTFYLOG" 2>/dev/null | grep -q 'доставлено=да'; then
        echo "${GREEN}[✓]${NC} Тестовое уведомление доставлено (см. $NTFYLOG)"
    else
        echo "${YELLOW}[?]${NC} Не вижу подтверждения доставки тестового уведомления — проверьте,"
        echo "    подписаны ли вы на топик, и посмотрите $NTFYLOG"
    fi

    if [ "$CHECK_FAILED" -eq 0 ]; then
        echo "${GREEN}[✓]${NC} Все проверки пройдены успешно"
    else
        echo "${RED}[!]${NC} Проверок с ошибкой: $CHECK_FAILED — просмотрите список выше"
    fi

    echo "${GREEN}[✓]${NC} Шаг 11 завершён успешно"
    mark_done "step5_11"
fi

echo ""
echo "${BOLD}${CYAN}==========================================================================="
echo "  ntfy настроен — сохраните эту информацию."
echo "===========================================================================${NC}"

NTFY_MODE_NOW=$(dk_ntfy_mode)
echo "$(pad_field "Имя сервера:" "$FIELD_WIDTH")$(read_or_default "$SERVERNAMEFILE" "$(hostname 2>/dev/null || echo server)")"
echo "$(pad_field "Режим:" "$FIELD_WIDTH")$NTFY_MODE_NOW"

NTFY_URL=""
NTFY_TOPIC=""
NTFY_TOKEN=""
if [ -f "$NTFY_CONF" ]; then
    # shellcheck disable=SC1090
    source "$NTFY_CONF"
fi

if [ "$NTFY_MODE_NOW" = "host" ]; then
    NTFY_ADMIN_USER_SAVED=$(read_or_default "$NTFY_DIR/admin_user" "(не найден)")

    echo "$(pad_field "Топик уведомлений:" "$FIELD_WIDTH")${NTFY_TOPIC:-(не найден)}"
    echo "$(pad_field "Внутренний адрес:" "$FIELD_WIDTH")http://dk_ntfy:80 (только docker-сеть)"
    echo "$(pad_field "Локально с хоста:" "$FIELD_WIDTH")http://127.0.0.1:${NTFY_LOCAL_PORT}"
    echo "$(pad_field "Внешнего адреса нет:" "$FIELD_WIDTH")осознанно — см. заголовок файла"
    echo "$(pad_field "Админ (docker exec):" "$FIELD_WIDTH")${NTFY_ADMIN_USER_SAVED}"
    echo "    (пароль не хранится нигде — вводился вручную на шаге 3)"
    echo "$(pad_field "Карточка в хабе:" "$FIELD_WIDTH")widget 'ntfy-feed' (см. NEXUS404 Hub)"
else
    echo "$(pad_field "Целевой сервер:" "$FIELD_WIDTH")${NTFY_URL:-(не найден)}"
    echo "$(pad_field "Топик:" "$FIELD_WIDTH")${NTFY_TOPIC:-(не найден)}"
    echo "$(pad_field "Подписка в приложении:" "$FIELD_WIDTH")${NTFY_URL}/${NTFY_TOPIC}"
    if [ "$NTFY_URL" = "https://ntfy.sh" ]; then
        echo "${YELLOW}[?]${NC} Секретный топик на ntfy.sh — не теряйте это имя,"
        echo "    это единственная защита (без пароля)"
    elif [ -n "$NTFY_TOKEN" ]; then
        echo "$(pad_field "Токен доступа:" "$FIELD_WIDTH")задан (хранится в $NTFY_CONF, не выводится сюда)"
    else
        echo "$(pad_field "Токен доступа:" "$FIELD_WIDTH")не задан (публикация без авторизации)"
    fi
fi

echo ""
echo "$(pad_field "Лог всех уведомлений:" "$FIELD_WIDTH")$NTFYLOG"
echo "$(pad_field "Конфиг notify_send:" "$FIELD_WIDTH")$NTFY_CONF"
echo ""
