#!/bin/bash
# =============================================================================
# Vaultwarden — менеджер паролей (self-hosted совместимый с Bitwarden).
#
# ВАЖНОЕ ИЗМЕНЕНИЕ АРХИТЕКТУРЫ (см. историю обсуждения) — переписано целиком
# под три решения, принятые позже исходной версии модуля:
#
#   1. НЕТ ПОДДОМЕНА, СЕКРЕТНЫЙ ПУТЬ ПОД КОРНЕВЫМ ДОМЕНОМ. Раньше был
#      "vault.<домен>". Теперь — "<корневой_домен>/<секретный_путь>",
#      зарегистрированный через claim_root_domain (common.sh). Работает,
#      потому что клиенты Bitwarden (приложение/расширение) просто хранят
#      "адрес сервера" целиком одной строкой — путь внутри для них ничем не
#      отличается от домена (в отличие от Pocket ID, который технически не
#      может так же, см. common.sh:POCKETID_URL_REF).
#
#   2. WEB_VAULT_ENABLED=false ПО УМОЛЧАНИЮ (пока SSO не включён) — веб-
#      морда выключена ПОЛНОСТЬЮ, не спрятана, а физически не поднимается.
#      Доступ — только через официальные клиенты (приложение/расширение
#      Bitwarden), которым веб-страница логина не нужна — они ходят
#      напрямую в API. Значит и прятать отдельно "браузерный адрес" от
#      "адреса для приложения" (как раньше) больше не нужно — путь один,
#      никакого forward_auth-гейта поверх (Pocket ID его не умеет, см.
#      common.sh) он и не получил бы.
#
#      ВАЖНАЯ ОГОВОРКА (проверено на живом сервере, см. историю): при
#      включении SSO (шаг 3) WEB_VAULT_ENABLED переключается на "true"
#      автоматически. Сам SSO-флоу (что в браузерном расширении, что в
#      приложении, что на телефоне) идёт через Angular-роут веб-морды
#      "/#/sso" — это часть той же статики web-vault, а не отдельный
#      лёгкий слой поверх API. Без неё Rocket отдаёт голый 404 вместо
#      этого роута, и SSO не работает вообще ни у одного клиента.
#      Zero-knowledge и блокировка входа по паролю (SSO_ONLY=true) при
#      этом не страдают — веб-морда физически доступна, но реальный вход
#      по email+паролю на ней политика организации всё равно не пустит.
#
#   3. SSO — ЧЕРЕЗ POCKET ID, не Authelia. Vaultwarden как был, так и
#      остаётся единственным сервисом, который сам умеет быть клиентом
#      OpenID Connect (src/config.rs: sso_enabled и т.д.) — просто
#      OIDC-провайдер теперь другой. Регистрация клиента — не ручная правка
#      YAML (как было с Authelia), а вызов common.sh:dk_pocketid_oidc_register_client
#      (REST API Pocket ID) — сильно короче и без риска сломать чужой
#      identity_providers вручную.
#
# ВАЖНЫЙ НЮАНС (сообщите об этом, если спросят "почему всё равно два
# пароля"): мастер-пароль Vaultwarden НЕ исчезает и не может исчезнуть — он
# не логin, а ключ шифрования хранилища на стороне клиента (zero-knowledge).
# SSO снимает необходимость ОТДЕЛЬНОЙ учётки/пароля Vaultwarden для входа —
# после единого входа через Pocket ID останется задать (один раз) мастер-
# пароль для расшифровки. Итого: один пароль для входа (Pocket ID passkey)
# + один мастер-пароль для расшифровки (у него и не было альтернативы).
#
# Раз веб-морды нет, "войти через SSO" и "зарегистрироваться" происходит
# ВНУТРИ клиентского приложения (не в браузере) — см. шаг 4.
#
# ADMIN_TOKEN хранится ЧИСТЫМ ТЕКСТОМ, а не как Argon2 PHC-хеш (хотя это
# рекомендованный Vaultwarden способ). Причина технически подтверждена —
# `vaultwarden hash` использует rpassword, которая открывает /dev/tty
# НАПРЯМУЮ (не читает stdin), а `docker exec -i` (без `-t`) не выделяет
# псевдотерминал — автоматизировать эту команду через пайп невозможно.
# Vaultwarden при чистом токене просто пишет безобидное предупреждение в
# лог ("в пользу Argon2") — функционально всё работает. Admin-панель
# доступна по тому же секретному пути + "/admin" — отдельно наружу не
# публикуется.
#
# STATEFILE: "step7_N".
# =============================================================================

enable_full_logging

echo "${BOLD}${CYAN}==========================================================================="
echo "  НАСТРОЙКА МЕНЕДЖЕРА ПАРОЛЕЙ (VAULTWARDEN)"
echo "===========================================================================${NC}"

TOTAL_STEPS=5
DONE_COUNT=$(grep -c '^step7_' "$STATEFILE" 2>/dev/null || true)
DONE_COUNT="${DONE_COUNT:-0}"
if [ "$DONE_COUNT" -gt 0 ] && [ "$DONE_COUNT" -lt "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Найден файл состояния: пройдено $DONE_COUNT из $TOTAL_STEPS шагов модуля, продолжаем"
elif [ "$DONE_COUNT" -ge "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Модуль уже был выполнен ранее (все $TOTAL_STEPS шагов пройдены)"
fi
echo ""

VAULT_DIR="$APPS_DIR/vaultwarden"
VAULT_LOCAL_PORT=8222
VAULT_SECRET_PATH_FILE="$VAULT_DIR/secret_path"
VAULT_ADMIN_TOKEN_FILE="$VAULT_DIR/admin_token"
VAULT_SSO_CLIENT_SECRET_FILE="$VAULT_DIR/sso_client_secret"

# vault_alive_url — печатает адрес живой проверки С УЧЁТОМ секретного пути.
# ВАЖНО (проверено по исходникам Vaultwarden, src/main.rs): basepath берётся
# из CONFIG.domain_path() (то есть из пути внутри DOMAIN) и монтируется
# ПЕРЕД всеми маршрутами без исключения — .mount([basepath, "/"].concat(),
# api::web_routes()) — /alive объявлен именно в web_routes() (src/api/web.rs)
# и НЕ гейтится WEB_VAULT_ENABLED (эти два факта разные — маршрут жив, но
# путь всё равно с префиксом). Значит голый "http://127.0.0.1:PORT/alive"
# всегда вернёт 404 — нужен путь целиком, как у настоящих внешних запросов.
vault_alive_url() {
    local secret_path
    secret_path=$(read_or_default "$VAULT_SECRET_PATH_FILE" "")
    echo "http://127.0.0.1:${VAULT_LOCAL_PORT}/${secret_path}/alive"
}

# ================== ШАГ 7_1 ==================
if is_done "step7_1"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 1: Установка Vaultwarden"
    echo "===========================================================================${NC}"

    if ! check_disk_space 512; then
        echo "${RED}[!]${NC} Меньше 512 MB свободного места на диске — недостаточно для Vaultwarden"
        exit 1
    fi

    mkdir -p "$VAULT_DIR/data"

    DK_ROOT_DOMAIN=$(read_or_default "$DOMAINFILE" "")
    if [ -z "$DK_ROOT_DOMAIN" ]; then
        echo "${RED}[!]${NC} Базовый домен не настроен (модуль 2, шаг 5) — без него"
        echo "    Vaultwarden работать не сможет (нужен настоящий домен и HTTPS —"
        echo "    OIDC/WebAuthn origin привязывается к домену). Настройте домен"
        echo "    и запустите этот шаг заново."
        exit 1
    fi

    # Секретный путь под корневым доменом — НЕ поддомен. Генерируется
    # автоматически (не то, что нужно произносить/запоминать, копируется в
    # настройки клиента Bitwarden один раз). См. заголовок файла, пункт 1.
    VAULT_SECRET_PATH=$(read_or_default "$VAULT_SECRET_PATH_FILE" "")
    if [ -z "$VAULT_SECRET_PATH" ]; then
        VAULT_SECRET_PATH="$(tr -dc 'a-z0-9' < /dev/urandom | head -c 24)"
        echo "$VAULT_SECRET_PATH" > "$VAULT_SECRET_PATH_FILE"
        chmod 600 "$VAULT_SECRET_PATH_FILE"
    fi

    # DOMAIN — этот же секретный путь под корневым доменом. Используется
    # и как origin для OIDC redirect_uri (шаг 3), и Vaultwarden сам знает,
    # что работает из-под подпути (официально поддерживаемый режим —
    # см. Vaultwarden wiki, "Running behind a subpath").
    VAULT_DOMAIN_URL="https://${DK_ROOT_DOMAIN}/${VAULT_SECRET_PATH}"

    if [ ! -s "$VAULT_ADMIN_TOKEN_FILE" ]; then
        VAULT_ADMIN_TOKEN="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 48)"
        echo "$VAULT_ADMIN_TOKEN" > "$VAULT_ADMIN_TOKEN_FILE"
        chmod 600 "$VAULT_ADMIN_TOKEN_FILE"
        echo "${GREEN}[✓]${NC} Токен admin-панели сгенерирован"
        echo "    ($VAULT_ADMIN_TOKEN_FILE, права 600)"
    else
        VAULT_ADMIN_TOKEN=$(cat "$VAULT_ADMIN_TOKEN_FILE")
        echo "${CYAN}[*]${NC} Токен admin-панели уже существует, пропускаю"
    fi

    if [ ! -f "$VAULT_DIR/docker-compose.yml" ]; then
        # SSO_* блок ниже — заглушка (SSO_ENABLED: "false"). Шаг 3 сам
        # допишет реальные значения через sed по месту (если решите включить
        # единый вход), не трогая остальной файл. Регистрация (SIGNUPS_ALLOWED)
        # открыта только до шага 4 (создание единственного пользователя).
        # WEB_VAULT_ENABLED: "false" — веб-морда не поднимается вообще, см.
        # заголовок файла, пункт 2. Порт наружу НЕ публикуется — единственный
        # путь снаружи идёт через Caddy (шаг 2) на секретный путь.
        cat > "$VAULT_DIR/docker-compose.yml" << EOF
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: dk_vaultwarden
    restart: unless-stopped
    environment:
      DOMAIN: "${VAULT_DOMAIN_URL}"
      ADMIN_TOKEN: "${VAULT_ADMIN_TOKEN}"
      ENABLE_WEBSOCKET: "true"
      WEB_VAULT_ENABLED: "false"
      SIGNUPS_ALLOWED: "true"
      SIGNUPS_VERIFY: "false"
      SSO_ENABLED: "false"
      SSO_ONLY: "false"
      SSO_AUTHORITY: ""
      SSO_SCOPES: "profile email offline_access"
      SSO_PKCE: "true"
      SSO_CLIENT_ID: "vaultwarden"
      SSO_CLIENT_SECRET: ""
    ports:
      - "127.0.0.1:${VAULT_LOCAL_PORT}:80"
    volumes:
      - ./data:/data
    networks:
      - ${DK_NETWORK}

networks:
  ${DK_NETWORK}:
    external: true
EOF
        echo "${GREEN}[✓]${NC} docker-compose.yml создан:"
        echo "    $VAULT_DIR/docker-compose.yml"
    else
        echo "${CYAN}[*]${NC} docker-compose.yml уже существует, не трогаю"
    fi

    run_spinner "Запуск Vaultwarden" "dk_compose_up '$VAULT_DIR'"

    echo "${CYAN}[*]${NC} Жду готовности Vaultwarden..."
    VAULT_READY=0
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if curl -fsS -m 3 "$(vault_alive_url)" >/dev/null 2>>"$LOGFILE"; then
            VAULT_READY=1
            break
        fi
        sleep 2
    done

    if [ "$VAULT_READY" -eq 1 ]; then
        echo "${GREEN}[✓]${NC} Vaultwarden отвечает на http://127.0.0.1:${VAULT_LOCAL_PORT}"
    else
        echo "${RED}[!]${NC} Vaultwarden не ответил за 20 секунд — проверьте контейнер:"
        echo "    docker logs dk_vaultwarden"
        exit 1
    fi

    echo "${GREEN}[✓]${NC} Шаг 1 завершён успешно"
    mark_done "step7_1"
fi

# ================== ШАГ 7_2 ==================
if is_done "step7_2"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 2: Caddy (секретный путь под корневым доменом)"
    echo "===========================================================================${NC}"

    VAULT_SECRET_PATH=$(read_or_default "$VAULT_SECRET_PATH_FILE" "")
    if [ -z "$VAULT_SECRET_PATH" ]; then
        echo "${RED}[!]${NC} Не найден секретный путь — что-то пошло не так на шаге 1, повторите его"
        exit 1
    fi

    # Один путь на всё — веб-морды нет (WEB_VAULT_ENABLED=false), значит
    # нет и разделения "браузер vs приложение", как было раньше у ntfy/
    # старого Vaultwarden. И forward_auth-гейта здесь тоже нет и не может
    # быть (Pocket ID его не умеет, см. common.sh) — секретность самого
    # пути и есть единственный барьер снаружи, а дальше уже свои механизмы
    # Vaultwarden (мастер-пароль, SSO).
    claim_root_domain "vault" "/${VAULT_SECRET_PATH}*" "reverse_proxy dk_vaultwarden:80"
    echo "${GREEN}[✓]${NC} Caddy настроен: https://<домен>/${VAULT_SECRET_PATH} -> dk_vaultwarden:80"

    echo "${GREEN}[✓]${NC} Шаг 2 завершён успешно"
    mark_done "step7_2"
fi

# ================== ШАГ 7_3 ==================
if is_done "step7_3"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 3: Единый вход через Pocket ID (OIDC SSO)"
    echo "===========================================================================${NC}"

    POCKETID_URL_FILE_REF="$POCKETID_DIR_REF/public_url"

    if ! dk_pocketid_available; then
        echo "${CYAN}[*]${NC} Pocket ID не установлена (или ещё не завершила установку) — пропускаю."
        echo "    Останется классический вход по email+мастер-пароль (через клиент,"
        echo "    веб-морды нет). Если позже поставите Pocket ID — сотрите строку"
        echo "    'step7_3' из $STATEFILE и зайдите в этот пункт меню снова."
    elif grep -q 'SSO_ENABLED: "true"' "$VAULT_DIR/docker-compose.yml" 2>/dev/null; then
        # Автопочинка: старая версия модуля оставляла SSO_CLIENT_ID
        # литералом-заглушкой "vaultwarden" вместо реального ID из Pocket ID
        # ("The requested OAuth 2.0 Client does not exist"). Чиним на месте.
        if grep -q 'SSO_CLIENT_ID: "vaultwarden"' "$VAULT_DIR/docker-compose.yml" 2>/dev/null; then
            echo "${YELLOW}[?]${NC} SSO включён, но SSO_CLIENT_ID — старый литерал-заглушка"
            echo "    вместо настоящего ID из Pocket ID. Чиню на месте."
            if [ -s "${VAULT_SSO_CLIENT_SECRET_FILE}.id" ]; then
                VAULT_SSO_CLIENT_ID_FIX=$(cat "${VAULT_SSO_CLIENT_SECRET_FILE}.id")
                sed -i "s#SSO_CLIENT_ID: \"vaultwarden\"#SSO_CLIENT_ID: \"${VAULT_SSO_CLIENT_ID_FIX}\"#" "$VAULT_DIR/docker-compose.yml"
                run_spinner "Применяю исправленный SSO_CLIENT_ID" "dk_compose_up '$VAULT_DIR'"
                echo "${GREEN}[✓]${NC} SSO_CLIENT_ID исправлен на настоящий ID из Pocket ID"
            else
                echo "${RED}[!]${NC} Не нашёл сохранённый client_id"
                echo "    (${VAULT_SSO_CLIENT_SECRET_FILE}.id) — почините вручную:"
                echo "    посмотрите настоящий client_id в панели Pocket ID"
                echo "    (клиент 'Vaultwarden') и подставьте его в SSO_CLIENT_ID"
                echo "    в $VAULT_DIR/docker-compose.yml"
            fi
        else
            echo "${CYAN}[*]${NC} SSO уже включён ранее, пропускаю"
        fi
    elif ! [ -s "$POCKETID_URL_FILE_REF" ]; then
        echo "${YELLOW}[?]${NC} Pocket ID установлена, но не нашёл её адрес ($POCKETID_URL_FILE_REF) —"
        echo "    похоже, модуль Pocket ID не был доведён до конца. Пропускаю."
    elif echo "${CYAN}[*]${NC} Pocket ID найдена (портал: $(cat "$POCKETID_URL_FILE_REF"))." && ! confirm_yn "Включить через неё единый вход в Vaultwarden?"; then
        echo "${CYAN}[*]${NC} Пропущено по вашему выбору — классический вход по"
        echo "    email+мастер-пароль остаётся"
    else
        VAULT_SECRET_PATH=$(read_or_default "$VAULT_SECRET_PATH_FILE" "")
        VAULT_DOMAIN_URL="https://$(read_or_default "$DOMAINFILE" "")/${VAULT_SECRET_PATH}"
        POCKETID_URL=$(cat "$POCKETID_URL_FILE_REF")
        REDIRECT_URI="${VAULT_DOMAIN_URL}/identity/connect/oidc-signin"

        # Вся ручная работа с YAML (была нужна для Authelia) заменяется
        # одним вызовом — Pocket ID настраивается через свой REST API, не
        # редактированием чужого конфига. См. common.sh для деталей.
        if ! dk_pocketid_oidc_register_client "Vaultwarden" "$REDIRECT_URI" "$VAULT_SSO_CLIENT_SECRET_FILE"; then
            echo "${RED}[!]${NC} Не удалось зарегистрировать клиента в Pocket ID —"
            echo "    смотрите вывод выше и $LOGFILE"
            exit 1
        fi
        VAULT_SSO_CLIENT_SECRET=$(cat "$VAULT_SSO_CLIENT_SECRET_FILE")
        # Реальный client_id из Pocket ID (dk_pocketid_oidc_register_client
        # кладёт его в "${secret_file}.id") — без него SSO_CLIENT_ID остался
        # бы литералом-заглушкой, и Pocket ID отвечал бы "Client does not exist".
        VAULT_SSO_CLIENT_ID=$(cat "${VAULT_SSO_CLIENT_SECRET_FILE}.id")
        if [ -z "$VAULT_SSO_CLIENT_ID" ]; then
            echo "${RED}[!]${NC} Не нашёл сохранённый client_id Pocket ID"
            echo "    (${VAULT_SSO_CLIENT_SECRET_FILE}.id) — регистрация клиента,"
            echo "    похоже, не завершилась. Повторите шаг."
            exit 1
        fi

        # Vaultwarden сам (его бэкенд, не браузер) ходит за OIDC discovery-
        # документом (${POCKETID_URL}/.well-known/openid-configuration) по
        # НАСТОЯЩЕМУ HTTPS, с полной проверкой сертификата — библиотека
        # rustls-native-certs (подтверждено по исходникам) в норме читает
        # системное хранилище доверенных сертификатов контейнера. Если Caddy
        # по какой-то причине выдаёт сертификат, которому эта система не
        # доверяет (например ещё не выпустился боевой Let's Encrypt, или
        # используется свой CA), запрос упадёт с ошибкой на уровне TLS ДО
        # того, как дело дойдёт до самого OIDC — снаружи это выглядит как
        # "Failed to discover OpenID provider: Request failed".
        #
        # Чиним универсально, без привязки к конкретному CA (работает для
        # production-сертификата, любого другого CA, если такой появится),
        # которому вдруг не доверяют): вытаскиваем сертификат ПРЯМО у живого
        # Caddy (openssl s_client) и добавляем к системным корням контейнера
        # (не заменяем — rustls-native-certs при заданном SSL_CERT_FILE
        # использует ТОЛЬКО его, поэтому собираем полный бандл сами, а не
        # только наш сертификат — иначе сломался бы, например, показ иконок
        # сайтов в самом Vaultwarden, который тоже ходит по HTTPS наружу).
        POCKETID_HOSTNAME=$(echo "$POCKETID_URL" | sed -E 's#^https?://##; s#/.*$##')
        if command -v openssl >/dev/null 2>&1; then
            VAULT_CA_BUNDLE="$VAULT_DIR/combined-ca.pem"
            VAULT_EXTRACTED_CHAIN=$(echo | timeout 10 openssl s_client -connect "${POCKETID_HOSTNAME}:443" -servername "${POCKETID_HOSTNAME}" -showcerts 2>>"$LOGFILE" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p')
            if [ -n "$VAULT_EXTRACTED_CHAIN" ]; then
                VAULT_SYSTEM_CA=$(docker exec dk_vaultwarden cat /etc/ssl/certs/ca-certificates.crt 2>>"$LOGFILE")
                {
                    [ -n "$VAULT_SYSTEM_CA" ] && printf '%s\n' "$VAULT_SYSTEM_CA"
                    printf '%s\n' "$VAULT_EXTRACTED_CHAIN"
                } > "$VAULT_CA_BUNDLE"
                echo "${GREEN}[✓]${NC} Сертификат Pocket ID (${POCKETID_HOSTNAME})"
                echo "    добавлен к доверенным для Vaultwarden"

                # Тот же приём "заглушка -> дописать при старой версии", что
                # и для SSO_* переменных — если docker-compose.yml от версии
                # модуля ещё без этого монтирования, дописываем сами.
                if ! grep -q 'SSL_CERT_FILE' "$VAULT_DIR/docker-compose.yml"; then
                    awk '
                        /^      SSO_CLIENT_SECRET:/ && !done { print; print "      SSL_CERT_FILE: \"/etc/ssl/certs/dk-combined-ca.pem\""; done=1; next }
                        { print }
                    ' "$VAULT_DIR/docker-compose.yml" > "$VAULT_DIR/docker-compose.yml.dk_tmp"
                    cat "$VAULT_DIR/docker-compose.yml.dk_tmp" > "$VAULT_DIR/docker-compose.yml"
                    rm -f "$VAULT_DIR/docker-compose.yml.dk_tmp"
                fi
                if ! grep -q 'combined-ca.pem:/etc/ssl/certs/dk-combined-ca.pem' "$VAULT_DIR/docker-compose.yml"; then
                    awk '
                        /^      - \.\/data:\/data/ && !done { print; print "      - ./combined-ca.pem:/etc/ssl/certs/dk-combined-ca.pem:ro"; done=1; next }
                        { print }
                    ' "$VAULT_DIR/docker-compose.yml" > "$VAULT_DIR/docker-compose.yml.dk_tmp"
                    cat "$VAULT_DIR/docker-compose.yml.dk_tmp" > "$VAULT_DIR/docker-compose.yml"
                    rm -f "$VAULT_DIR/docker-compose.yml.dk_tmp"
                fi
            else
                echo "${YELLOW}[?]${NC} Не удалось получить сертификат ${POCKETID_HOSTNAME}:443"
                echo "    (openssl s_client не вернул ничего)."
                echo "    Если у Pocket ID ещё нет валидного сертификата (домен пока не"
                echo "    резолвится или Let's Encrypt ещё не выпустил) — OIDC discovery,"
                echo "    скорее всего, упадёт с ошибкой TLS."
            fi
        else
            echo "${YELLOW}[?]${NC} openssl не найден на сервере — пропускаю"
            echo "    проверку/добавление сертификата Pocket ID в доверенные для"
            echo "    Vaultwarden. Если используется staging-сертификат —"
            echo "    OIDC discovery, скорее всего, упадёт с ошибкой TLS"
            echo "    ('Failed to discover OpenID provider')."
        fi

        # Подставляем реальные значения SSO_* в docker-compose.yml (были
        # заглушками с шага 1) — точечно через sed, остальной файл не трогаем.
        #
        # ЗАЩИТА ОТ СТАРЫХ УСТАНОВОК: если Vaultwarden ставился ЕЩЁ ДО того,
        # как в модуле появился SSO, в docker-compose.yml нет и не может
        # быть строк-заглушек SSO_ENABLED/SSO_ONLY/... — sed ниже нашёл бы
        # НЕЧЕГО заменять и молча завершился бы успешно (exit 0), ничего не
        # изменив. Подтверждено тестом: `sed` не считает "0 замен" ошибкой.
        # Результат — модуль бодро написал бы "SSO включён", а по факту
        # Vaultwarden продолжил бы работать без единого входа вообще.
        # Поэтому сначала проверяем, есть ли ключ SSO_ENABLED в файле —
        # если нет, дописываем весь блок SSO_* заглушек перед основным
        # sed (дальше он их найдёт и подставит как обычно).
        if ! grep -q 'SSO_ENABLED:' "$VAULT_DIR/docker-compose.yml"; then
            echo "${CYAN}[*]${NC} docker-compose.yml от более старой версии модуля"
            echo "    (без SSO) — дописываю недостающие ключи"
            awk '
                /^      SIGNUPS_VERIFY:/ && !done {
                    print
                    print "      SSO_ENABLED: \"false\""
                    print "      SSO_ONLY: \"false\""
                    print "      SSO_AUTHORITY: \"\""
                    print "      SSO_SCOPES: \"profile email offline_access\""
                    print "      SSO_PKCE: \"true\""
                    print "      SSO_CLIENT_ID: \"vaultwarden\""
                    print "      SSO_CLIENT_SECRET: \"\""
                    done=1
                    next
                }
                { print }
            ' "$VAULT_DIR/docker-compose.yml" > "$VAULT_DIR/docker-compose.yml.dk_tmp"
            cat "$VAULT_DIR/docker-compose.yml.dk_tmp" > "$VAULT_DIR/docker-compose.yml"
            rm -f "$VAULT_DIR/docker-compose.yml.dk_tmp"
        fi

        sed -i \
            -e 's/SSO_ENABLED: "false"/SSO_ENABLED: "true"/' \
            -e "s#SSO_ONLY: \"false\"#SSO_ONLY: \"true\"#" \
            -e "s#SSO_AUTHORITY: \"\"#SSO_AUTHORITY: \"${POCKETID_URL}\"#" \
            -e "s#SSO_CLIENT_ID: \"vaultwarden\"#SSO_CLIENT_ID: \"${VAULT_SSO_CLIENT_ID}\"#" \
            -e "s#SSO_CLIENT_SECRET: \"\"#SSO_CLIENT_SECRET: \"${VAULT_SSO_CLIENT_SECRET}\"#" \
            "$VAULT_DIR/docker-compose.yml"

        # WEB_VAULT_ENABLED обязательно вместе с SSO — сам вход идёт через
        # Angular-роут веб-морды "/#/sso", без неё Rocket отдаёт 404 и SSO
        # не работает ни у одного клиента. SSO_ONLY по-прежнему блокирует
        # вход по email+паролю, так что заходить с этого не начнёшь.
        sed -i 's/WEB_VAULT_ENABLED: "false"/WEB_VAULT_ENABLED: "true"/' "$VAULT_DIR/docker-compose.yml"

        # Подтверждаем, что подстановка реально сработала (а не тихо
        # промахнулась мимо несуществующих строк) — иначе явная ошибка,
        # а не бодрый "успех" при фактически невключённом SSO.
        if ! grep -q 'SSO_ENABLED: "true"' "$VAULT_DIR/docker-compose.yml"; then
            echo "${RED}[!]${NC} Не удалось подставить SSO-настройки в"
            echo "    docker-compose.yml — смотрите файл вручную:"
            echo "    $VAULT_DIR/docker-compose.yml"
            exit 1
        fi
        if ! grep -q 'WEB_VAULT_ENABLED: "true"' "$VAULT_DIR/docker-compose.yml"; then
            echo "${RED}[!]${NC} Не удалось включить WEB_VAULT_ENABLED —"
            echo "    без него SSO не заработает ни у одного клиента."
            echo "    Смотрите файл вручную: $VAULT_DIR/docker-compose.yml"
            exit 1
        fi

        run_spinner "Применяю SSO-настройки" "dk_compose_up '$VAULT_DIR'"

        echo "${CYAN}[*]${NC} Жду перезапуска..."
        VAULT_READY=0
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            if curl -fsS -m 3 "$(vault_alive_url)" >/dev/null 2>>"$LOGFILE"; then
                VAULT_READY=1
                break
            fi
            sleep 2
        done

        if [ "$VAULT_READY" -eq 1 ]; then
            echo "${GREEN}[✓]${NC} SSO включён (SSO_ONLY — вход теперь только через"
            echo "    Pocket ID, без email+пароль). Веб-морда (WEB_VAULT_ENABLED)"
            echo "    тоже включена — без неё SSO-флоу не проходит ни в одном"
            echo "    клиенте (браузер/приложение/телефон), но вход по паролю"
            echo "    на ней всё равно заблокирован политикой SSO_ONLY."
        else
            echo "${RED}[!]${NC} Vaultwarden не ответил за 20 секунд после"
            echo "    перезапуска — проверьте: docker logs dk_vaultwarden"
            exit 1
        fi
    fi

    echo "${GREEN}[✓]${NC} Шаг 3 завершён успешно"
    mark_done "step7_3"
fi

# ================== ШАГ 7_4 ==================
if is_done "step7_4"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 4: Первый пользователь"
    echo "===========================================================================${NC}"

    VAULT_SECRET_PATH=$(read_or_default "$VAULT_SECRET_PATH_FILE" "")
    DK_ROOT_DOMAIN_S4=$(read_or_default "$DOMAINFILE" "")
    if [ -n "$DK_ROOT_DOMAIN_S4" ] && [ -n "$VAULT_SECRET_PATH" ]; then
        VAULT_REG_URL="https://${DK_ROOT_DOMAIN_S4}/${VAULT_SECRET_PATH}"
    else
        VAULT_REG_URL="http://127.0.0.1:${VAULT_LOCAL_PORT}"
    fi

    # Веб-морды нет (WEB_VAULT_ENABLED=false) — регистрация и вход
    # происходят ВНУТРИ клиентского приложения/расширения, не в браузере.
    if grep -q 'SSO_ENABLED: "true"' "$VAULT_DIR/docker-compose.yml" 2>/dev/null; then
        echo "${CYAN}[*]${NC} SSO включён — регистрация не нужна, происходит"
        echo "    автоматически при первом входе."
        echo "    В приложении/расширении Bitwarden: 'Настройки' -> 'Self-hosted' ->"
        echo "    Server URL: ${BOLD}${VAULT_REG_URL}${NC}"
        echo "    Дальше: любой email -> 'Продолжить' -> на экране мастер-пароля"
        echo "    нажмите кнопку SSO (не вводите пароль в поле — кнопка появится"
        echo "    не сразу, а на 2-м экране)."
        echo "${YELLOW}[?]${NC} При первом входе Vaultwarden попросит задать"
        echo "    мастер-пароль — это ключ шифрования, не логин. Скрипт его"
        echo "    не видит и не хранит. Восстановления без него нет."
        confirm_or_exit "Вход через SSO прошли, мастер-пароль задали?" "Прервано пользователем."
    else
        echo "${CYAN}[*]${NC} Регистрация сейчас ОТКРЫТА (временно) — зарегистрируйте"
        echo "    единственного пользователя сами, через приложение/расширение"
        echo "    Bitwarden: 'Настройки' -> 'Self-hosted' -> Server URL:"
        echo "    ${BOLD}${VAULT_REG_URL}${NC}, дальше 'Создать аккаунт' прямо там же."
        echo "${YELLOW}[?]${NC} Мастер-пароль этот скрипт никогда не видит и не"
        echo "    хранит — введите его сами."
        echo "    Не теряйте его: восстановления без него нет (zero-knowledge"
        echo "    шифрование)."

        confirm_or_exit "Регистрацию прошли, аккаунт создан?" "Прервано. Регистрация остаётся открытой."

        # Выключаем регистрацию — правим .env через docker-compose (переменная
        # окружения перезапишет то, что было в исходном файле при следующем
        # up). docker-compose.yml НЕ трогаем целиком (сам файл может быть
        # отредактирован вручную) — только эту одну строку через sed по месту.
        sed -i 's/SIGNUPS_ALLOWED: "true"/SIGNUPS_ALLOWED: "false"/' "$VAULT_DIR/docker-compose.yml"

        run_spinner "Применяю: регистрация закрыта" "dk_compose_up '$VAULT_DIR'"

        echo "${CYAN}[*]${NC} Жду перезапуска..."
        VAULT_READY=0
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            if curl -fsS -m 3 "$(vault_alive_url)" >/dev/null 2>>"$LOGFILE"; then
                VAULT_READY=1
                break
            fi
            sleep 2
        done

        if [ "$VAULT_READY" -eq 1 ]; then
            echo "${GREEN}[✓]${NC} Регистрация закрыта, Vaultwarden снова отвечает"
        else
            echo "${RED}[!]${NC} Vaultwarden не ответил за 20 секунд после"
            echo "    перезапуска — проверьте: docker logs dk_vaultwarden"
            exit 1
        fi
    fi

    echo "${GREEN}[✓]${NC} Шаг 4 завершён успешно"
    mark_done "step7_4"
fi

# ================== ШАГ 7_5 ==================
if is_done "step7_5"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 5: Карточка в хабе и финальная проверка"
    echo "===========================================================================${NC}"

    # mode=widget, не iframe — весь хаб принципиально не встраивает чужие
    # веб-интерфейсы, только свой собственный UI через API (см. архитектуру
    # проекта целиком). Карточка показывает метаданные (сколько записей) —
    # реальная работа с паролями идёт через Bitwarden-приложение/расширение
    # напрямую по секретному пути, это отдельный канал, не через хаб.
    add_hub_card "Vaultwarden" "Пароли" "" "fas fa-key" "Сервисы" "widget" "vaultwarden-meta"
    echo "${GREEN}[✓]${NC} Карточка Vaultwarden зарегистрирована в хабе (mode=widget)"

    CHECK_FAILED=0
    echo "===== Результаты финальной проверки модуля Vaultwarden ($(date '+%Y-%m-%d %H:%M:%S')) =====" >> "$LOGFILE"

    check_item "Контейнер Vaultwarden запущен" bash -c "docker ps --format '{{.Names}}' | grep -qx dk_vaultwarden"
    check_item "Vaultwarden отвечает локально" curl -fsS -m 3 "$(vault_alive_url)"
    check_item "Токен admin-панели существует" test -s "$VAULT_ADMIN_TOKEN_FILE"
    check_item "Карточка зарегистрирована в хабе" hub_card_exists "Vaultwarden"

    echo ""
    if [ "$CHECK_FAILED" -eq 0 ]; then
        echo "${GREEN}[✓]${NC} Все проверки пройдены успешно"
    else
        echo "${RED}[!]${NC} Проверок с ошибкой: $CHECK_FAILED — просмотрите список выше"
    fi

    echo "${GREEN}[✓]${NC} Шаг 5 завершён успешно"
    mark_done "step7_5"
fi

echo ""
echo "${BOLD}${CYAN}==========================================================================="
echo "  Vaultwarden настроен — сохраните эту информацию."
echo "===========================================================================${NC}"

VAULT_SECRET_PATH_NOW=$(read_or_default "$VAULT_SECRET_PATH_FILE" "")
DK_ROOT_DOMAIN_NOW=$(read_or_default "$DOMAINFILE" "")
SSO_IS_ON=0
grep -q 'SSO_ENABLED: "true"' "$VAULT_DIR/docker-compose.yml" 2>/dev/null && SSO_IS_ON=1

echo "$(pad_field "Локальный адрес:" "$FIELD_WIDTH")http://127.0.0.1:${VAULT_LOCAL_PORT}"
if [ -n "$DK_ROOT_DOMAIN_NOW" ] && [ -n "$VAULT_SECRET_PATH_NOW" ]; then
    echo "$(pad_field "Адрес для клиентов:" "$FIELD_WIDTH")https://${DK_ROOT_DOMAIN_NOW}/${VAULT_SECRET_PATH_NOW}"
    echo "    (укажите как Server URL в приложении/расширении Bitwarden —"
    echo "    веб-морды нет, WEB_VAULT_ENABLED=false)"
else
    echo "$(pad_field "Внешний адрес:" "$FIELD_WIDTH")не настроен (нет базового домена, см. модуль 2, шаг 5)"
fi
if [ "$SSO_IS_ON" -eq 1 ]; then
    echo "$(pad_field "Единый вход:" "$FIELD_WIDTH")включён через Pocket ID"
    echo "    (email+пароль отключён, только SSO)"
    echo "$(pad_field "Как войти:" "$FIELD_WIDTH")в приложении: любой email -> 'Продолжить' -> на экране"
    echo "    мастер-пароля нажмите кнопку SSO (не вводите пароль в поле)"
else
    echo "$(pad_field "Единый вход:" "$FIELD_WIDTH")не включён — обычный вход по email+мастер-пароль (в приложении)"
fi
echo "$(pad_field "Карточка в хабе:" "$FIELD_WIDTH")widget 'vaultwarden-meta' (см. NEXUS404 Interface)"
echo "$(pad_field "Токен admin-панели:" "$FIELD_WIDTH")$VAULT_ADMIN_TOKEN_FILE"
echo "    (не выводится сюда, права 600)"
echo "$(pad_field "Примечание:" "$FIELD_WIDTH")в логах будет предупреждение про ADMIN_TOKEN"
echo "    (не-Argon2 — это ожидаемо, не мешает работе)"
echo ""
