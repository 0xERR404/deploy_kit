#!/bin/bash
# =============================================================================
# Beszel — мониторинг ресурсов. (позиция в меню — 6-я)
#
# ХАБ   — веб-интерфейс + БД (PocketBase) + локальный агент, слушает :8090.
# АГЕНТ — режим для дополнительных серверов: локального хаба здесь нет,
#         агент подключается к хабу, поднятому на ДРУГОМ сервере (тоже через
#         deploy_kit, режим "хаб"). Выбор — шаг 1.
#
# Архитектура (актуальная, WebSocket, НЕ старая SSH-схема): агент САМ
# подключается к хабу (BESZEL_HUB_URL_FILE) по WebSocket и представляется
# парой KEY (публичный ключ хаба) + TOKEN. В режиме "хаб" агент и хаб — в
# одной сети dk_net, друг для друга обычные контейнеры (адрес = имя
# контейнера). В режиме "агент" адрес — реальный внешний адрес удалённого
# хаба (другой сервер, вводится вручную на шаге 1 — это НЕ поддомен нашего
# домена, так что общего правила "без поддоменов" тут не касается).
#
# Автоподключение агента — через "постоянный universal-токен" (см. шаг 2):
# любой агент, стартовавший с этим токеном и правильным KEY, сам создаёт
# свою запись в хабе при первом подключении — ручное добавление системы
# через веб-интерфейс не требуется. В режиме "агент" шаг 2 получает эти
# данные у УДАЛЁННОГО хаба (через тот же API, просто с другим адресом) —
# копировать ключ/токен из веб-интерфейса руками не нужно.
#
# ВАЖНОЕ ИЗМЕНЕНИЕ АРХИТЕКТУРЫ (см. историю обсуждения): раньше хаб Beszel
# публиковался наружу через Caddy на своём поддомене (полный веб-интерфейс,
# плюс автовход через TRUSTED_AUTH_HEADER от Authelia). ВСЁ ЭТО УБРАНО —
# хаб Beszel полностью внутренний (адрес только для API изнутри docker-сети,
# см. шаг 1). Вместо веб-интерфейса — карточка в NEXUS404 Interface
# (add_hub_card, mode=widget, см. шаг 4): показываются только 4 метрики
# (CPU/RAM/сеть/диск), не весь веб-интерфейс. Раньше в аналогичном месте
# была пометка "Homer-карточку не добавляем" — она устарела вместе со
# старым Homer, теперь карточка есть, просто виджет, а не iframe.
#
# STATEFILE: "step6_N".
# =============================================================================

enable_full_logging

echo "${BOLD}${CYAN}==========================================================================="
echo "  НАСТРОЙКА МОНИТОРИНГА (BESZEL)"
echo "===========================================================================${NC}"

TOTAL_STEPS=5
DONE_COUNT=$(grep -c '^step6_' "$STATEFILE" 2>/dev/null || true)
DONE_COUNT="${DONE_COUNT:-0}"
if [ "$DONE_COUNT" -gt 0 ] && [ "$DONE_COUNT" -lt "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Найден файл состояния: пройдено $DONE_COUNT из $TOTAL_STEPS шагов модуля, продолжаем"
elif [ "$DONE_COUNT" -ge "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Модуль уже был выполнен ранее (все $TOTAL_STEPS шагов пройдены)"
fi
echo ""

BESZEL_DIR="$APPS_DIR/beszel"
BESZEL_HUB_DIR="$BESZEL_DIR/hub"
AGENT_DIR="$BESZEL_DIR/agent"
BESZEL_LOCAL_PORT=8090
BESZEL_MODE_FILE="$BESZEL_DIR/mode"
BESZEL_HUB_URL_FILE="$BESZEL_DIR/hub_url"
BESZEL_ADMIN_EMAIL_FILE="$BESZEL_DIR/admin_email"
BESZEL_KEY_FILE="$BESZEL_DIR/hub_pubkey"
BESZEL_UTOKEN_FILE="$BESZEL_DIR/agent_token"
BESZEL_AUTH_FILE="$BESZEL_DIR/admin_authtoken"
BESZEL_SYSTEM_NAME_FILE="$BESZEL_DIR/system_name"

mkdir -p "$BESZEL_DIR"

# dk_beszel_mode — печатает режим ("hub"/"agent"), выбранный на шаге 1
dk_beszel_mode() {
    read_or_default "$BESZEL_MODE_FILE" "hub"
}

# beszel_admin_api_base — куда слать административные запросы (создание
# пользователя, логин, получение ключа/токена, список систем): в режиме
# "хаб" это локальный адрес (скрипт выполняется на той же машине, что и
# хаб), в режиме "агент" — адрес удалённого хаба, сохранённый на шаге 1.
beszel_admin_api_base() {
    if [ "$(dk_beszel_mode)" = "hub" ]; then
        echo "http://127.0.0.1:${BESZEL_LOCAL_PORT}"
    else
        read_or_default "$BESZEL_HUB_URL_FILE" ""
    fi
}

# beszel_request <метод> <url> [токен_авторизации] [json_тело]
# Печатает тело ответа, а последней строкой — HTTP-код (curl -w). Никогда
# не падает сама по себе (сетевые ошибки гасятся вызывающим кодом через
# "|| true" на команде подстановки) — set -e безопасен.
beszel_request() {
    local method="$1" url="$2" token="${3:-}" body="${4:-}"
    local -a hdrs=(-H "Content-Type: application/json")
    [ -n "$token" ] && hdrs+=(-H "Authorization: ${token}")
    if [ -n "$body" ]; then
        curl -sS -m 10 -w '\n%{http_code}' -X "$method" "${hdrs[@]}" -d "$body" "$url" 2>>"$LOGFILE"
    else
        curl -sS -m 10 -w '\n%{http_code}' -X "$method" "${hdrs[@]}" "$url" 2>>"$LOGFILE"
    fi
}

# do_login <api_base> <email> <пароль> — печатает токен авторизации в
# stdout, вернёт 1 при неверных данных или недоступности хаба.
do_login() {
    local api_base="$1" email="$2" password="$3" resp code body token
    resp=$(beszel_request POST "${api_base}/api/collections/users/auth-with-password" "" \
        "$(jq -n --arg identity "$email" --arg password "$password" '{identity:$identity,password:$password}')") || true
    code=$(printf '%s' "$resp" | tail -n1)
    body=$(printf '%s' "$resp" | sed '$d')
    [ "$code" = "200" ] || return 1
    token=$(printf '%s' "$body" | jq -r '.token // empty' 2>/dev/null)
    [ -n "$token" ] || return 1
    printf '%s' "$token"
}

# ================== ШАГ 6_1 ==================
if is_done "step6_1"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 1: Режим и хаб"
    echo "===========================================================================${NC}"

    if ! check_disk_space 512; then
        echo "${RED}[!]${NC} Меньше 512 MB свободного места на диске — недостаточно для Beszel"
        exit 1
    fi

    retry_apt "Установка jq (нужен для работы с API Beszel)" "apt-get install -y jq"

    if [ ! -f "$BESZEL_MODE_FILE" ]; then
        echo ""
        echo "  1) Хаб — веб-интерфейс и БД здесь же (обычный сценарий,"
        echo "     если это первый сервер)"
        echo "  2) Только агент — хаб уже поднят на другом сервере, этот"
        echo "     сервер просто мониторим"
        echo ""

        BESZEL_MODE=""
        while [ -z "$BESZEL_MODE" ]; do
            if ! read -rp "${YELLOW}[?]${NC} Выберите вариант (1 или 2): " MODE_CHOICE; then
                echo "${RED}[!]${NC} Не удалось прочитать ввод"
                exit 1
            fi
            case "$MODE_CHOICE" in
                1) BESZEL_MODE="hub" ;;
                2) BESZEL_MODE="agent" ;;
                *) echo "${RED}[!]${NC} Введите 1 или 2" ;;
            esac
        done
        echo "$BESZEL_MODE" > "$BESZEL_MODE_FILE"
    else
        echo "${CYAN}[*]${NC} Режим уже выбран ранее: $(dk_beszel_mode)"
    fi

    if [ "$(dk_beszel_mode)" = "agent" ]; then
        echo "${GREEN}[✓]${NC} Режим: только агент"
        echo ""

        if [ -f "$BESZEL_HUB_URL_FILE" ]; then
            echo "${CYAN}[*]${NC} Адрес хаба уже сохранён: $(cat "$BESZEL_HUB_URL_FILE")"
        else
            HUB_URL_RE='^https?://[^[:space:]]+$'
            BESZEL_REMOTE_URL=""
            echo "${CYAN}[*]${NC} Например: https://beszel.example.com"
            while [ -z "$BESZEL_REMOTE_URL" ]; do
                read -rp "${YELLOW}[?]${NC} Адрес удалённого хаба Beszel: " URL_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
                URL_INPUT="${URL_INPUT%/}"
                if [[ "$URL_INPUT" =~ $HUB_URL_RE ]]; then
                    BESZEL_REMOTE_URL="$URL_INPUT"
                else
                    echo "${RED}[!]${NC} Адрес должен начинаться с http:// или https://,"
                    echo "    пример: https://beszel.example.com"
                fi
            done

            echo "${CYAN}[*]${NC} Проверяю доступность хаба..."
            if curl -fsS -m 5 "${BESZEL_REMOTE_URL}/api/health" >/dev/null 2>>"$LOGFILE"; then
                echo "${GREEN}[✓]${NC} Хаб отвечает"
            else
                echo "${YELLOW}[?]${NC} Хаб не ответил за 5 секунд — проверьте адрес и"
                echo "    доступность сети между серверами"
                if ! confirm_yn "Всё равно продолжить с этим адресом?"; then
                    echo "${RED}[!]${NC} Прервано пользователем"
                    exit 1
                fi
            fi
            echo "$BESZEL_REMOTE_URL" > "$BESZEL_HUB_URL_FILE"
        fi
    else
        echo "${GREEN}[✓]${NC} Режим: хаб"
        echo ""

        mkdir -p "$BESZEL_HUB_DIR/data"

        # APP_URL — ВНУТРЕННИЙ адрес контейнера, не внешний домен. Хаб
        # Beszel больше не публикуется наружу вообще (см. заголовок файла —
        # решили показывать в NEXUS404 Interface только 4 метрики через
        # API, mode=widget, а не встраивать весь веб-интерфейс в iframe) —
        # значит и поддомен, и HTTPS через Caddy ему не нужны, только адрес
        # для API-запросов изнутри той же docker-сети.
        BESZEL_APP_URL="http://dk_beszel:8090"

        if [ ! -f "$BESZEL_HUB_DIR/docker-compose.yml" ]; then
            cat > "$BESZEL_HUB_DIR/docker-compose.yml" << EOF
services:
  beszel:
    image: henrygd/beszel:latest
    container_name: dk_beszel
    restart: unless-stopped
    environment:
      APP_URL: "${BESZEL_APP_URL}"
    ports:
      - "127.0.0.1:${BESZEL_LOCAL_PORT}:8090"
    volumes:
      - ./data:/beszel_data
    networks:
      - ${DK_NETWORK}

networks:
  ${DK_NETWORK}:
    external: true
EOF
            echo "${GREEN}[✓]${NC} docker-compose.yml создан: $BESZEL_HUB_DIR/docker-compose.yml"
        else
            echo "${CYAN}[*]${NC} docker-compose.yml уже существует, не трогаю"
        fi

        run_spinner "Запуск хаба Beszel" "dk_compose_up '$BESZEL_HUB_DIR'"

        echo "${CYAN}[*]${NC} Жду готовности хаба..."
        BESZEL_READY=0
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            if curl -fsS -m 3 "http://127.0.0.1:${BESZEL_LOCAL_PORT}/api/health" >/dev/null 2>>"$LOGFILE"; then
                BESZEL_READY=1
                break
            fi
            sleep 2
        done

        if [ "$BESZEL_READY" -eq 1 ]; then
            echo "${GREEN}[✓]${NC} Хаб отвечает на http://127.0.0.1:${BESZEL_LOCAL_PORT}"
        else
            echo "${RED}[!]${NC} Хаб не ответил за 20 секунд — проверьте контейнер:"
            echo "    docker logs dk_beszel"
            exit 1
        fi

        # HUB_URL для локального агента (тот же сервер, в docker-сети — по имени контейнера)
        echo "http://dk_beszel:8090" > "$BESZEL_HUB_URL_FILE"
    fi

    echo "${GREEN}[✓]${NC} Шаг 1 завершён успешно"
    mark_done "step6_1"
fi

# ================== ШАГ 6_2 ==================
if is_done "step6_2"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 2: Администратор и токены для агента"
    echo "===========================================================================${NC}"

    API_BASE=$(beszel_admin_api_base)
    if [ -z "$API_BASE" ]; then
        echo "${RED}[!]${NC} Не найден адрес хаба — сначала пройдите шаг 1"
        exit 1
    fi
    if [ "$(dk_beszel_mode)" = "agent" ]; then
        echo "${CYAN}[*]${NC} Хаб удалённый: $API_BASE"
    fi

    BESZEL_TOKEN=""

    if [ -f "$BESZEL_ADMIN_EMAIL_FILE" ]; then
        BESZEL_EMAIL=$(cat "$BESZEL_ADMIN_EMAIL_FILE")
        echo "${CYAN}[*]${NC} Администратор уже создан ранее: $BESZEL_EMAIL"
        while [ -z "$BESZEL_TOKEN" ]; do
            read -rsp "${YELLOW}[?]${NC} Пароль администратора Beszel ($BESZEL_EMAIL): " BESZEL_PASS || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
            echo ""
            if BESZEL_TOKEN=$(do_login "$API_BASE" "$BESZEL_EMAIL" "$BESZEL_PASS"); then
                :
            else
                echo "${RED}[!]${NC} Не удалось войти — неверный пароль или хаб недоступен, попробуйте снова"
            fi
        done
    else
        echo "${CYAN}[*]${NC} Создадим администратора веб-интерфейса Beszel"
        echo "    (используется только для API-запросов хаба NEXUS404 Interface —"
        echo "    сам веб-интерфейс Beszel наружу не публикуется)"
        echo ""

        EMAIL_RE='^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
        BESZEL_EMAIL_DEFAULT=$(read_or_default "$DK_SHARED_EMAIL_FILE" "")
        BESZEL_EMAIL=""
        while [ -z "$BESZEL_EMAIL" ]; do
            if [ -n "$BESZEL_EMAIL_DEFAULT" ]; then
                read -rp "${YELLOW}[?]${NC} Email администратора Beszel (Enter — '$BESZEL_EMAIL_DEFAULT'): " EMAIL_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
                EMAIL_INPUT="${EMAIL_INPUT:-$BESZEL_EMAIL_DEFAULT}"
            else
                read -rp "${YELLOW}[?]${NC} Email администратора Beszel: " EMAIL_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
            fi
            if [[ "$EMAIL_INPUT" =~ $EMAIL_RE ]]; then
                BESZEL_EMAIL="$EMAIL_INPUT"
                echo "$BESZEL_EMAIL" > "$DK_SHARED_EMAIL_FILE"
            else
                echo "${RED}[!]${NC} Некорректный email, попробуйте снова"
            fi
        done

        BESZEL_PASS=""
        while true; do
            read -rsp "${YELLOW}[?]${NC} Пароль администратора (минимум 8 символов): " BESZEL_PASS || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
            echo ""
            if [ "${#BESZEL_PASS}" -lt 8 ]; then
                echo "${RED}[!]${NC} Слишком короткий пароль (минимум 8 символов), попробуйте снова"
                continue
            fi
            read -rsp "${YELLOW}[?]${NC} Повторите пароль: " BESZEL_PASS_CONFIRM || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
            echo ""
            if [ "$BESZEL_PASS" == "$BESZEL_PASS_CONFIRM" ]; then
                break
            else
                echo "${RED}[!]${NC} Пароли не совпадают, попробуйте снова"
            fi
        done

        CREATE_RESP=$(beszel_request POST "${API_BASE}/api/beszel/create-user" "" \
            "$(jq -n --arg email "$BESZEL_EMAIL" --arg password "$BESZEL_PASS" '{email:$email,password:$password}')") || true
        CREATE_CODE=$(printf '%s' "$CREATE_RESP" | tail -n1)

        if [ "$CREATE_CODE" = "200" ]; then
            echo "${GREEN}[✓]${NC} Администратор '$BESZEL_EMAIL' создан"
        elif [ "$CREATE_CODE" = "403" ]; then
            echo "${CYAN}[*]${NC} В Beszel уже есть пользователи (созданы не этим"
            echo "    модулем) — пробую войти с указанными данными"
        else
            echo "${RED}[!]${NC} Не удалось создать администратора (HTTP ${CREATE_CODE:-?}) —"
            echo "    смотрите $LOGFILE"
            echo "    Если хаб удалённый — убедитесь, что адрес и сетевая доступность верны"
            exit 1
        fi

        if ! BESZEL_TOKEN=$(do_login "$API_BASE" "$BESZEL_EMAIL" "$BESZEL_PASS"); then
            echo "${RED}[!]${NC} Не удалось войти под '$BESZEL_EMAIL' сразу после"
            echo "    создания — проверьте $LOGFILE и повторите шаг"
            exit 1
        fi
        echo "$BESZEL_EMAIL" > "$BESZEL_ADMIN_EMAIL_FILE"
    fi

    echo "${GREEN}[✓]${NC} Авторизация выполнена"

    INFO_RESP=$(beszel_request GET "${API_BASE}/api/beszel/info" "$BESZEL_TOKEN") || true
    INFO_CODE=$(printf '%s' "$INFO_RESP" | tail -n1)
    INFO_BODY=$(printf '%s' "$INFO_RESP" | sed '$d')
    if [ "$INFO_CODE" != "200" ]; then
        echo "${RED}[!]${NC} Не удалось получить публичный ключ хаба (HTTP ${INFO_CODE:-?}) —"
        echo "    смотрите $LOGFILE"
        exit 1
    fi
    BESZEL_KEY=$(printf '%s' "$INFO_BODY" | jq -r '.key // empty')
    if [ -z "$BESZEL_KEY" ]; then
        echo "${RED}[!]${NC} Хаб не вернул публичный ключ —"
        echo "    смотрите $LOGFILE"
        exit 1
    fi
    echo "$BESZEL_KEY" > "$BESZEL_KEY_FILE"
    echo "${GREEN}[✓]${NC} Публичный ключ хаба получен"

    # Постоянный universal-токен — идемпотентно: если уже есть сохранённый
    # токен, передаём его же обратно, чтобы не отвязать уже подключённых
    # агентов при повторном прогоне этого шага.
    BESZEL_EXISTING_UTOKEN=$(read_or_default "$BESZEL_UTOKEN_FILE" "")
    UTOKEN_URL="${API_BASE}/api/beszel/universal-token?enable=1&permanent=1"
    [ -n "$BESZEL_EXISTING_UTOKEN" ] && UTOKEN_URL="${UTOKEN_URL}&token=${BESZEL_EXISTING_UTOKEN}"

    UTOKEN_RESP=$(beszel_request GET "$UTOKEN_URL" "$BESZEL_TOKEN") || true
    UTOKEN_CODE=$(printf '%s' "$UTOKEN_RESP" | tail -n1)
    UTOKEN_BODY=$(printf '%s' "$UTOKEN_RESP" | sed '$d')
    if [ "$UTOKEN_CODE" != "200" ]; then
        echo "${RED}[!]${NC} Не удалось получить токен для агентов (HTTP ${UTOKEN_CODE:-?}) —"
        echo "    смотрите $LOGFILE"
        exit 1
    fi
    BESZEL_UTOKEN=$(printf '%s' "$UTOKEN_BODY" | jq -r '.token // empty')
    if [ -z "$BESZEL_UTOKEN" ]; then
        echo "${RED}[!]${NC} Хаб не вернул токен для агентов —"
        echo "    смотрите $LOGFILE"
        exit 1
    fi
    echo "$BESZEL_UTOKEN" > "$BESZEL_UTOKEN_FILE"
    chmod 600 "$BESZEL_UTOKEN_FILE"
    echo "${GREEN}[✓]${NC} Постоянный токен для подключения агентов готов"
    echo "${YELLOW}[?]${NC} Токен даёт право самозарегистрироваться агентом от"
    echo "    имени '$BESZEL_EMAIL'"
    echo "    Не публикуйте файл: $BESZEL_UTOKEN_FILE"

    echo "$BESZEL_TOKEN" > "$BESZEL_AUTH_FILE"
    chmod 600 "$BESZEL_AUTH_FILE"

    echo "${GREEN}[✓]${NC} Шаг 2 завершён успешно"
    mark_done "step6_2"
fi

# ================== ШАГ 6_3 ==================
if is_done "step6_3"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 3: Агент Beszel"
    echo "===========================================================================${NC}"

    BESZEL_HUB_KEY=$(read_or_default "$BESZEL_KEY_FILE" "")
    BESZEL_AGENT_TOKEN=$(read_or_default "$BESZEL_UTOKEN_FILE" "")
    BESZEL_HUB_URL=$(read_or_default "$BESZEL_HUB_URL_FILE" "")
    if [ -z "$BESZEL_HUB_KEY" ] || [ -z "$BESZEL_AGENT_TOKEN" ] || [ -z "$BESZEL_HUB_URL" ]; then
        echo "${RED}[!]${NC} Не найден публичный ключ хаба, токен агента или адрес"
        echo "    хаба — сначала пройдите шаги 1-2"
        exit 1
    fi

    # Имя, под которым система будет показана в хабе. По умолчанию — общее
    # имя сервера (SERVERNAMEFILE, задаётся модулем 4 ntfy либо здесь, если
    # ntfy ещё не устанавливали — тогда сохраняем его сюда же, чтобы
    # последующие модули тоже подхватили его как разумный дефолт).
    BESZEL_SYSTEM_NAME=$(read_or_default "$BESZEL_SYSTEM_NAME_FILE" "")
    if [ -z "$BESZEL_SYSTEM_NAME" ]; then
        DK_DEFAULT_NAME=$(read_or_default "$SERVERNAMEFILE" "$(hostname 2>/dev/null || echo server)")
        read -rp "${YELLOW}[?]${NC} Имя этого сервера в Beszel (Enter — '$DK_DEFAULT_NAME'): " NAME_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
        BESZEL_SYSTEM_NAME="${NAME_INPUT:-$DK_DEFAULT_NAME}"
        echo "$BESZEL_SYSTEM_NAME" > "$BESZEL_SYSTEM_NAME_FILE"
        [ -f "$SERVERNAMEFILE" ] || echo "$BESZEL_SYSTEM_NAME" > "$SERVERNAMEFILE"
    else
        echo "${CYAN}[*]${NC} Имя системы уже задано ранее: $BESZEL_SYSTEM_NAME"
    fi

    mkdir -p "$AGENT_DIR/data"

    if [ ! -f "$AGENT_DIR/docker-compose.yml" ]; then
        cat > "$AGENT_DIR/docker-compose.yml" << EOF
services:
  beszel-agent:
    image: henrygd/beszel-agent:latest
    container_name: dk_beszel_agent
    restart: unless-stopped
    volumes:
      - ./data:/var/lib/beszel-agent
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      HUB_URL: "${BESZEL_HUB_URL}"
      KEY: "${BESZEL_HUB_KEY}"
      TOKEN: "${BESZEL_AGENT_TOKEN}"
      SYSTEM_NAME: "${BESZEL_SYSTEM_NAME}"
    networks:
      - ${DK_NETWORK}

networks:
  ${DK_NETWORK}:
    external: true
EOF
        echo "${GREEN}[✓]${NC} docker-compose.yml создан: $AGENT_DIR/docker-compose.yml"
    else
        echo "${CYAN}[*]${NC} docker-compose.yml уже существует, не трогаю"
    fi

    run_spinner "Запуск агента Beszel" "dk_compose_up '$AGENT_DIR'"

    echo "${CYAN}[*]${NC} Жду регистрации агента в хабе..."
    API_BASE=$(beszel_admin_api_base)
    BESZEL_AUTH_NOW=$(read_or_default "$BESZEL_AUTH_FILE" "")
    AGENT_SEEN=0
    if [ -n "$BESZEL_AUTH_NOW" ] && [ -n "$API_BASE" ]; then
        for _ in 1 2 3 4 5 6; do
            SYSTEMS_RESP=$(beszel_request GET "${API_BASE}/api/collections/systems/records?perPage=50" "$BESZEL_AUTH_NOW") || true
            SYSTEMS_CODE=$(printf '%s' "$SYSTEMS_RESP" | tail -n1)
            if [ "$SYSTEMS_CODE" = "200" ]; then
                SYSTEMS_BODY=$(printf '%s' "$SYSTEMS_RESP" | sed '$d')
                if [ "$(printf '%s' "$SYSTEMS_BODY" | jq -r '.items | length' 2>/dev/null)" -gt 0 ] 2>/dev/null; then
                    AGENT_SEEN=1
                    break
                fi
            fi
            sleep 3
        done
    fi

    if [ "$AGENT_SEEN" -eq 1 ]; then
        echo "${GREEN}[✓]${NC} Агент подключился и виден в хабе"
    else
        echo "${YELLOW}[?]${NC} Пока не вижу подключённого агента через API — это не"
        echo "    обязательно ошибка, первое подключение иногда занимает больше"
        echo "    времени. Проверю ещё раз на шаге 5,"
        echo "    а сейчас можно посмотреть логи: docker logs dk_beszel_agent"
    fi

    echo "${GREEN}[✓]${NC} Шаг 3 завершён успешно"
    mark_done "step6_3"
fi

# ================== ШАГ 6_4 ==================
if is_done "step6_4"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 4: Карточка в хабе (NEXUS404 Interface)"
    echo "===========================================================================${NC}"

    # Раньше здесь была публикация хаба Beszel через Caddy (свой поддомен,
    # полный веб-интерфейс) — убрана целиком. Решили показывать в NEXUS404
    # Interface только 4 метрики (CPU/RAM/сеть/диск) через API, а не весь
    # веб-интерфейс Beszel — значит и внешний адрес ему не нужен, только
    # карточка-виджет. Безопасно вызывать, даже если хаб ещё не установлен —
    # карточка появится сама, когда он будет развёрнут (см.
    # common.sh:add_hub_card).
    if [ "$(dk_beszel_mode)" = "hub" ]; then
        add_hub_card "Beszel" "Мониторинг ресурсов" "" "fas fa-chart-line" "Сервисы" "widget" "beszel-metrics"
        echo "${GREEN}[✓]${NC} Карточка Beszel зарегистрирована в хабе (mode=widget)"
    else
        echo "${CYAN}[*]${NC} Режим агента — веб-интерфейса хаба здесь нет, своей"
        echo "    карточки не будет (метрики показывает карточка НА ТОМ сервере,"
        echo "    где стоит хаб Beszel)"
    fi

    echo "${GREEN}[✓]${NC} Шаг 4 завершён успешно"
    mark_done "step6_4"
fi

# ================== ШАГ 6_5 ==================
if is_done "step6_5"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 5: Финальная проверка"
    echo "===========================================================================${NC}"

    CHECK_FAILED=0
    echo "===== Результаты финальной проверки модуля Beszel ($(date '+%Y-%m-%d %H:%M:%S')) =====" >> "$LOGFILE"

    if [ "$(dk_beszel_mode)" = "hub" ]; then
        check_item "Контейнер хаба запущен" bash -c "docker ps --format '{{.Names}}' | grep -qx dk_beszel"
        check_item "Хаб отвечает на /api/health" curl -fsS -m 3 "http://127.0.0.1:${BESZEL_LOCAL_PORT}/api/health"
        check_item "Карточка Beszel зарегистрирована в хабе" hub_card_exists "Beszel"
    else
        echo "${CYAN}[*]${NC} Режим агента — локального хаба нет, проверки хаба пропущены"
    fi
    check_item "Контейнер агента запущен" bash -c "docker ps --format '{{.Names}}' | grep -qx dk_beszel_agent"
    check_item "Публичный ключ хаба сохранён" test -s "$BESZEL_KEY_FILE"
    check_item "Токен для агентов сохранён" test -s "$BESZEL_UTOKEN_FILE"

    API_BASE=$(beszel_admin_api_base)
    BESZEL_AUTH_NOW=$(read_or_default "$BESZEL_AUTH_FILE" "")
    if [ -n "$BESZEL_AUTH_NOW" ] && [ -n "$API_BASE" ]; then
        SYSTEMS_RESP=$(beszel_request GET "${API_BASE}/api/collections/systems/records?perPage=50" "$BESZEL_AUTH_NOW") || true
        SYSTEMS_CODE=$(printf '%s' "$SYSTEMS_RESP" | tail -n1)
        if [ "$SYSTEMS_CODE" = "200" ]; then
            SYSTEMS_BODY=$(printf '%s' "$SYSTEMS_RESP" | sed '$d')
            SYSTEMS_COUNT=$(printf '%s' "$SYSTEMS_BODY" | jq -r '.items | length' 2>/dev/null)
            if [ -n "$SYSTEMS_COUNT" ] && [ "$SYSTEMS_COUNT" -gt 0 ] 2>/dev/null; then
                echo "${GREEN}[✓]${NC}    Агент зарегистрирован в хабе как система (всего систем: $SYSTEMS_COUNT)"
            else
                echo "${YELLOW}[?]${NC}  Ни одной системы в хабе пока не видно —"
                echo "    проверьте docker logs dk_beszel_agent"
                CHECK_FAILED=$((CHECK_FAILED + 1))
            fi
        else
            echo "${YELLOW}[?]${NC}  Не удалось проверить список систем (сессия авторизации истекла"
            echo "    или хаб недоступен) — посмотрите в веб-интерфейсе вручную"
        fi
    else
        echo "${YELLOW}[?]${NC}  Сохранённый токен авторизации не найден — проверьте список"
        echo "    систем в веб-интерфейсе вручную"
    fi

    echo ""
    if [ "$CHECK_FAILED" -eq 0 ]; then
        echo "${GREEN}[✓]${NC} Все проверки пройдены успешно"
    else
        echo "${RED}[!]${NC} Проверок с ошибкой/замечанием: $CHECK_FAILED — просмотрите список выше"
    fi

    echo "${GREEN}[✓]${NC} Шаг 5 завершён успешно"
    mark_done "step6_5"
fi

echo ""
echo "${BOLD}${CYAN}==========================================================================="
echo "  Beszel настроен — сохраните эту информацию."
echo "===========================================================================${NC}"

BESZEL_MODE_NOW=$(dk_beszel_mode)
echo "$(pad_field "Режим:" "$FIELD_WIDTH")$BESZEL_MODE_NOW"
echo "$(pad_field "Имя системы:" "$FIELD_WIDTH")$(read_or_default "$BESZEL_SYSTEM_NAME_FILE" "(не задано)")"
BESZEL_EMAIL_NOW=$(read_or_default "$BESZEL_ADMIN_EMAIL_FILE" "(не найден)")
echo "$(pad_field "Администратор:" "$FIELD_WIDTH")$BESZEL_EMAIL_NOW"
echo "    (пароль не хранится нигде — вводился вручную на шаге 2)"

if [ "$BESZEL_MODE_NOW" = "hub" ]; then
    echo "$(pad_field "Внутренний адрес:" "$FIELD_WIDTH")http://dk_beszel:8090 (только docker-сеть)"
    echo "$(pad_field "Локально с хоста:" "$FIELD_WIDTH")http://127.0.0.1:${BESZEL_LOCAL_PORT}"
    echo "$(pad_field "Внешнего адреса нет:" "$FIELD_WIDTH")осознанно — см. заголовок файла"
    echo "$(pad_field "Карточка в хабе:" "$FIELD_WIDTH")widget 'beszel-metrics' (см. NEXUS404 Interface)"
else
    echo "$(pad_field "Хаб (удалённый):" "$FIELD_WIDTH")$(read_or_default "$BESZEL_HUB_URL_FILE" "(не найден)")"
fi

echo ""
echo "$(pad_field "Публичный ключ хаба:" "$FIELD_WIDTH")$BESZEL_KEY_FILE"
echo "$(pad_field "Токен для новых агентов:" "$FIELD_WIDTH")$BESZEL_UTOKEN_FILE"
echo "    (права 600, держите в секрете)"
echo ""
