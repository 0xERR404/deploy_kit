#!/bin/bash
# =============================================================================
# Модуль: Pocket ID — OIDC-провайдер, замена Authelia.
#
# Ставится ПОСЛЕ Docker+Caddy и ДО NEXUS404 Interface/остальных сервисов —
# третьим пунктом меню. Имя файла (03_pocketid.sh) заменяет старый
# 03_auth.sh (Authelia) целиком — это другая программа, не апгрейд той же.
# STATEFILE: "step3_N".
#
# ЧЕМ ЭТО ОТЛИЧАЕТСЯ ОТ Authelia (важно понимать, прежде чем трогать):
#
#   1. НЕТ forward_auth. Pocket ID — чистый OIDC-провайдер: выдаёт токены
#      только тем, кто сам умеет ходить по OIDC-протоколу (Vaultwarden,
#      Forgejo). Он НЕ умеет "закрыть логином произвольный путь произвольного
#      сервиса" — того, на чём был построен весь auth_gate у Authelia. Здесь
#      этого сниппета нет и не будет. Единственная внешняя точка входа для
#      человека — сам хаб (NEXUS404 Interface), и логин перед ним реализован
#      в самом хабе, а не здесь.
#
#   2. НУЖЕН ОТДЕЛЬНЫЙ ПОДДОМЕН, не путь. Проверено по исходникам
#      (github.com/pocket-id/pocket-id, backend/internal/common/env_config.go,
#      validateURLWithoutPath) — APP_URL у Pocket ID жёстко не может
#      содержать путь, иначе контейнер откажется стартовать. У Authelia было
#      наоборот (server.address поддерживал путь) — у Pocket ID такой
#      возможности просто нет. Поэтому, в порядке исключения из общего
#      правила "всё на одном корневом домене", у Pocket ID СВОЙ поддомен
#      (спрашивается на шаге 1, по умолчанию "id"). Это не проблема
#      приватности — Pocket ID сам требует passkey для входа, факт его
#      обнаружения в CT-логах ничего не даёт атакующему.
#
#   3. НЕТ ПАРОЛЕЙ ВООБЩЕ. Pocket ID — passkey-only (WebAuthn): биометрия
#      телефона, Yubikey и т.п., пароля как класса не существует. Значит
#      первого администратора нельзя создать полностью автоматически одной
#      командой (как раньше делал скрипт с Authelia, генерируя bcrypt-хеш) —
#      WebAuthn-церемония регистрации требует реального браузера на реальном
#      устройстве. У Pocket ID есть встроенный веб-flow именно под это: при
#      первом заходе на пустой инстанс интерфейс сам предлагает
#      зарегистрировать первого администратора. Шаг 3 ниже приостанавливает
#      выполнение и просит сделать это руками — это неизбежно, не костыль.
#
#   4. Регистрация OIDC-клиентов — через REST API Pocket ID
#      (POST /api/oidc/clients + POST /api/oidc/clients/{id}/secrets,
#      заголовок X-API-Key), см. common.sh:dk_pocketid_oidc_register_client.
#      Admin API-ключ создаётся один раз вручную в веб-интерфейсе
#      (Settings -> API Keys) — тоже требует человека, автоматизировать
#      нечем: ключ существует только в момент создания, забрать его снаружи
#      после — нельзя.
# =============================================================================

enable_full_logging

echo "${BOLD}${CYAN}==========================================================================="
echo "  НАСТРОЙКА POCKET ID (OIDC ДЛЯ VAULTWARDEN/FORGEJO)"
echo "===========================================================================${NC}"

TOTAL_STEPS=4
DONE_COUNT=$(grep -c '^step3_' "$STATEFILE" 2>/dev/null || true)
DONE_COUNT="${DONE_COUNT:-0}"
if [ "$DONE_COUNT" -gt 0 ] && [ "$DONE_COUNT" -lt "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Найден файл состояния: пройдено $DONE_COUNT из $TOTAL_STEPS шагов модуля, продолжаем"
elif [ "$DONE_COUNT" -ge "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Модуль уже был выполнен ранее (все $TOTAL_STEPS шага пройдены)"
fi
echo ""

POCKETID_SUBDOMAIN_FILE="$POCKETID_DIR_REF/subdomain"
POCKETID_URL_FILE="$POCKETID_DIR_REF/public_url"

# Автопочинка старых установок (вне is_done — иначе не сработает, если
# шаг 1 уже пройден): более ранняя версия писала INTERNAL_APP_URL как
# внутренний docker-хост, который Vaultwarden отклоняет при SSO (см.
# 07_vaultwarden.sh). Правим точечно, не трогая остальной .env.
if [ -s "$POCKETID_DIR_REF/.env" ] && grep -q '^INTERNAL_APP_URL=http://dk_pocketid:' "$POCKETID_DIR_REF/.env"; then
    echo "${YELLOW}[?]${NC} Обнаружен старый INTERNAL_APP_URL (внутренний docker-хост"
    echo "    с подчёркиванием) — Vaultwarden и подобные клиенты отклоняют его"
    echo "    при SSO. Меняю на публичный адрес и перезапускаю Pocket ID."
    POCKETID_PUBLIC_URL_FOR_FIX=$(read_or_default "$POCKETID_URL_FILE" "")
    if [ -n "$POCKETID_PUBLIC_URL_FOR_FIX" ]; then
        sed -i "s#^INTERNAL_APP_URL=http://dk_pocketid:.*#INTERNAL_APP_URL=${POCKETID_PUBLIC_URL_FOR_FIX}#" "$POCKETID_DIR_REF/.env"
        if dk_compose_up "$POCKETID_DIR_REF" >>"$LOGFILE" 2>&1; then
            echo "${GREEN}[✓]${NC} INTERNAL_APP_URL исправлен, Pocket ID перезапущен"
        else
            echo "${RED}[!]${NC} Не удалось перезапустить Pocket ID — смотрите $LOGFILE"
            echo "    ($POCKETID_DIR_REF/.env уже исправлен, перезапустите контейнер вручную)"
        fi
    else
        echo "${RED}[!]${NC} Не нашёл публичный адрес Pocket ID ($POCKETID_URL_FILE) —"
        echo "    поправьте INTERNAL_APP_URL в $POCKETID_DIR_REF/.env вручную."
    fi
fi

# ================== ШАГ 1 ==================
if is_done "step3_1"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 1: Установка Pocket ID"
    echo "===========================================================================${NC}"

    if ! check_disk_space 512; then
        echo "${RED}[!]${NC} Меньше 512 MB свободного места на диске — недостаточно для Pocket ID"
        exit 1
    fi

    DK_ROOT_DOMAIN=$(read_or_default "$DOMAINFILE" "")
    if [ -z "$DK_ROOT_DOMAIN" ]; then
        echo "${RED}[!]${NC} Базовый домен не настроен (модуль 2, шаг 5) — без него Pocket ID"
        echo "    работать не может (APP_URL требует настоящий домен). Настройте домен"
        echo "    и запустите этот шаг заново."
        exit 1
    fi

    mkdir -p "$POCKETID_DIR_REF/data"

    POCKETID_SUB=$(read_or_default "$POCKETID_SUBDOMAIN_FILE" "")
    if [ -z "$POCKETID_SUB" ]; then
        SUB_RE='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'
        echo "${CYAN}[*]${NC} Pocket ID нужен СВОЙ поддомен (не путь — ограничение самого"
        echo "    Pocket ID, см. заголовок файла). По умолчанию 'id' — итог: id.${DK_ROOT_DOMAIN}"
        while true; do
            read -rp "${YELLOW}[?]${NC} Поддомен для Pocket ID (Enter — 'id'): " POCKETID_SUB_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
            POCKETID_SUB="${POCKETID_SUB_INPUT:-id}"
            if [[ "$POCKETID_SUB" =~ $SUB_RE ]]; then
                break
            fi
            echo "${RED}[!]${NC} Только буквы/цифры/дефис, пример: id"
        done
        echo "$POCKETID_SUB" > "$POCKETID_SUBDOMAIN_FILE"
    else
        echo "${CYAN}[*]${NC} Поддомен уже выбран ранее: ${POCKETID_SUB}.${DK_ROOT_DOMAIN}"
    fi

    POCKETID_HOST="${POCKETID_SUB}.${DK_ROOT_DOMAIN}"
    POCKETID_URL="https://${POCKETID_HOST}"
    echo "$POCKETID_URL" > "$POCKETID_URL_FILE"

    if [ ! -f "$POCKETID_DIR_REF/.env" ]; then
        POCKETID_ENC_KEY=$(openssl rand -base64 32 2>/dev/null || tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 44)
        # INTERNAL_APP_URL = APP_URL (не внутренний docker-хост) — Vaultwarden
        # строго валидирует синтаксис хоста при SSO-discovery и отклоняет
        # подчёркивание в "dk_pocketid" (RFC 952/1123), хотя Docker DNS его
        # резолвит нормально. Публичный адрес — безопасный выбор для любых
        # OIDC-клиентов, ценой лишнего прыжка через Caddy.
        cat > "$POCKETID_DIR_REF/.env" << EOF
APP_URL=${POCKETID_URL}
INTERNAL_APP_URL=${POCKETID_URL}
ENCRYPTION_KEY=${POCKETID_ENC_KEY}
TRUST_PROXY=true
PUID=1000
PGID=1000
EOF
        chmod 600 "$POCKETID_DIR_REF/.env"
        echo "${GREEN}[✓]${NC} .env создан: $POCKETID_DIR_REF/.env"
    else
        echo "${CYAN}[*]${NC} .env уже существует, не трогаю (возможны ручные правки)"
    fi

    if [ ! -f "$POCKETID_DIR_REF/docker-compose.yml" ]; then
        cat > "$POCKETID_DIR_REF/docker-compose.yml" << EOF
services:
  pocket-id:
    image: pocketid/pocket-id:v2
    container_name: dk_pocketid
    restart: unless-stopped
    env_file: .env
    ports:
      - "127.0.0.1:1411:1411"
    volumes:
      - ./data:/app/data
    networks:
      - ${DK_NETWORK}
    healthcheck:
      test: ["CMD", "/app/pocket-id", "healthcheck"]
      interval: 1m30s
      timeout: 5s
      retries: 2
      start_period: 10s

networks:
  ${DK_NETWORK}:
    external: true
EOF
        echo "${GREEN}[✓]${NC} docker-compose.yml создан: $POCKETID_DIR_REF/docker-compose.yml"
    else
        echo "${CYAN}[*]${NC} docker-compose.yml уже существует, не трогаю"
    fi

    # Порт публикуется ТОЛЬКО на 127.0.0.1 (сам хост, не интернет) — нужен
    # для хостовых curl-вызовов самого deploy_kit (POCKETID_API_BASE_REF в
    # common.sh; тот же приём, что у ntfy/Beszel/Vaultwarden/Forgejo).
    # Наружу (из интернета) единственный путь — через Caddy (шаг 2).
    # Другие контейнеры (Caddy и т.п.) обращаются по имени dk_pocketid:1411
    # (POCKETID_URL_REF в common.sh) — это отдельный, docker-сетевой адрес,
    # не связанный с портом на 127.0.0.1 выше.
    run_spinner "Запуск Pocket ID" "dk_compose_up '$POCKETID_DIR_REF'"

    echo "${CYAN}[*]${NC} Жду готовности Pocket ID..."
    POCKETID_READY=0
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if docker exec dk_pocketid /app/pocket-id healthcheck >/dev/null 2>>"$LOGFILE"; then
            POCKETID_READY=1
            break
        fi
        sleep 2
    done

    if [ "$POCKETID_READY" -eq 1 ]; then
        echo "${GREEN}[✓]${NC} Pocket ID запущен и отвечает"
    else
        echo "${RED}[!]${NC} Pocket ID не ответил за 20 секунд — проверьте контейнер:"
        echo "    docker logs dk_pocketid"
        exit 1
    fi

    echo "${GREEN}[✓]${NC} Шаг 1 завершён успешно"
    mark_done "step3_1"
fi

# ================== ШАГ 2 ==================
if is_done "step3_2"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 2: Caddy (отдельный поддомен Pocket ID)"
    echo "===========================================================================${NC}"

    POCKETID_HOST_S2=$(read_or_default "$POCKETID_URL_FILE" "")
    POCKETID_HOST_S2="${POCKETID_HOST_S2#https://}"
    if [ -z "$POCKETID_HOST_S2" ]; then
        echo "${RED}[!]${NC} Не найден адрес Pocket ID — что-то пошло не так на шаге 1, повторите его"
        exit 1
    fi

    # Единственное исключение из "всё через claim_root_domain на корневом
    # домене" — см. заголовок файла, пункт 2 (APP_URL Pocket ID не может
    # содержать путь). Обычный отдельный site-блок Caddy под свой хост,
    # без общего шлюза (гейта — его больше не существует, см. common.sh).
    mkdir -p "$APPS_DIR/caddy/conf.d"
    cat > "$APPS_DIR/caddy/conf.d/pocketid.caddy" << EOF
${POCKETID_HOST_S2} {
    reverse_proxy dk_pocketid:1411
}
EOF
    dk_caddy_reload
    echo "${GREEN}[✓]${NC} Caddy настроен: https://${POCKETID_HOST_S2} -> dk_pocketid:1411"

    echo "${GREEN}[✓]${NC} Шаг 2 завершён успешно"
    mark_done "step3_2"
fi

# ================== ШАГ 3 ==================
if is_done "step3_3"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 3: Первый администратор (passkey) + admin API-ключ"
    echo "===========================================================================${NC}"

    POCKETID_HOST_S3=$(read_or_default "$POCKETID_URL_FILE" "")

    echo "${YELLOW}[?]${NC} Pocket ID — passkey-only, паролей не существует (см. заголовок"
    echo "    файла). Дальше два действия руками, автоматизировать нечем:"
    echo ""
    echo "    1) Откройте в браузере (с телефона или компьютера, но обязательно"
    echo "       устройство с поддержкой passkey — биометрия/Yubikey):"
    echo ""
    echo "         ${POCKETID_HOST_S3}"
    echo ""
    echo "       Интерфейс сам предложит зарегистрировать первого администратора —"
    echo "       следуйте подсказкам (создание passkey)."
    echo ""
    echo "    2) После входа: Settings -> API Keys -> создать новый ключ с правами"
    echo "       администратора. Значение показывается ОДИН раз — скопируйте сразу."
    echo ""

    POCKETID_API_KEY=""
    while [ -z "$POCKETID_API_KEY" ]; do
        read -rsp "${YELLOW}[?]${NC} Вставьте admin API-ключ сюда: " POCKETID_API_KEY_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
        echo ""
        if [ -n "$POCKETID_API_KEY_INPUT" ]; then
            POCKETID_API_KEY="$POCKETID_API_KEY_INPUT"
        else
            echo "${RED}[!]${NC} Пусто, попробуйте снова"
        fi
    done

    echo "${CYAN}[*]${NC} Проверяю ключ..."
    if curl -fsS -m 10 -H "X-API-Key: ${POCKETID_API_KEY}" \
        "${POCKETID_API_BASE_REF}/api/oidc/clients" >/dev/null 2>>"$LOGFILE"; then
        echo "$POCKETID_API_KEY" > "$POCKETID_API_KEY_FILE"
        chmod 600 "$POCKETID_API_KEY_FILE"
        echo "${GREEN}[✓]${NC} Ключ рабочий, сохранён в $POCKETID_API_KEY_FILE"
    else
        echo "${RED}[!]${NC} Ключ не сработал (запрос к API вернул ошибку) — смотрите $LOGFILE"
        echo "    Проверьте, что ключ скопирован полностью и у него есть права"
        echo "    администратора, затем запустите этот шаг заново."
        exit 1
    fi

    echo "${GREEN}[✓]${NC} Шаг 3 завершён успешно"
    mark_done "step3_3"
fi

# ================== ШАГ 4 ==================
if is_done "step3_4"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 4: Финальная проверка"
    echo "===========================================================================${NC}"

    CHECK_FAILED=0
    echo "===== Результаты финальной проверки модуля Pocket ID ($(date '+%Y-%m-%d %H:%M:%S')) =====" >> "$LOGFILE"

    check_item "Контейнер Pocket ID запущен" bash -c "docker ps --format '{{.Names}}' | grep -qx dk_pocketid"
    check_item "Pocket ID отвечает на healthcheck" bash -c "docker exec dk_pocketid /app/pocket-id healthcheck"
    check_item "Caddy-конфиг Pocket ID создан" test -f "$APPS_DIR/caddy/conf.d/pocketid.caddy"
    check_item "Admin API-ключ сохранён" dk_pocketid_available

    echo ""
    if [ "$CHECK_FAILED" -eq 0 ]; then
        echo "${GREEN}[✓]${NC} Все проверки пройдены успешно"
    else
        echo "${RED}[!]${NC} Проверок с ошибкой: $CHECK_FAILED — просмотрите список выше"
    fi

    echo "${GREEN}[✓]${NC} Шаг 4 завершён успешно"
    mark_done "step3_4"
fi

echo ""
echo "${BOLD}${CYAN}==========================================================================="
echo "  Pocket ID настроен — сохраните эту информацию."
echo "===========================================================================${NC}"
echo "$(pad_field "Адрес Pocket ID:" "$FIELD_WIDTH")$(read_or_default "$POCKETID_URL_FILE" "не настроено")"
echo "$(pad_field "Admin API-ключ:" "$FIELD_WIDTH")$POCKETID_API_KEY_FILE"
echo ""
echo "${CYAN}[*]${NC} SSO для Vaultwarden/Forgejo настраивается в их собственных модулях"
echo "    (dk_pocketid_oidc_register_client из common.sh) — этот модуль сам"
echo "    клиентов не создаёт, только готовит провайдера."
echo ""
