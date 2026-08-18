#!/bin/bash
# =============================================================================
# Forgejo — самостоятельный git-сервер (форк Gitea).
#
# ВАЖНОЕ ИЗМЕНЕНИЕ АРХИТЕКТУРЫ (см. историю обсуждения) — переписано под три
# решения, принятые позже исходной версии модуля:
#
#   1. НЕТ ПОДДОМЕНА, ПУТЬ ПОД КОРНЕВЫМ ДОМЕНОМ ("<домен>/<путь>/", по
#      умолчанию "git"). НЕ секретный (в отличие от Vaultwarden) — путь
#      предназначен для реального использования (git clone, ссылки на
#      скачивание), прятать его смысла нет. Forgejo/Gitea официально
#      поддерживает работу из-под подпути через ROOT_URL с этим путём —
#      тот же принцип, что и у DOMAIN с путём у Vaultwarden.
#
#   2. НЕТ ТОЧЕЧНОГО ГЕЙТА НА "/". Раньше здесь была НЕТРИВИАЛЬНАЯ логика:
#      Caddy-гейт (forward_auth Authelia) ставился ТОЛЬКО на корневую
#      страницу "/", а не на весь домен — иначе сломался бы git clone/push
#      и REST API (у них нет браузера для входа). Это исчезло целиком,
#      потому что forward_auth-гейта в проекте больше нет вообще НИГДЕ —
#      Pocket ID (замена Authelia) его не умеет (см. common.sh). Значит и
#      "защищать только один путь, а остальное пропускать мимо гейта" —
#      больше не задача. Caddy теперь просто пробрасывает всё на Forgejo
#      одним правилом, без всякого гейта — единственная защита браузерного
#      входа снова целиком на самом Forgejo (REQUIRE_SIGNIN_VIEW + свой
#      логин/SSO), как и было для git-протокола.
#
#   3. ПРИВАТНОСТЬ — теперь ДВА независимых уровня, не три (пункт "гейт
#      Caddy на /" из старой схемы упразднён вместе с самим гейтом):
#      - REQUIRE_SIGNIN_VIEW (Forgejo) — закрывает браузер/веб-интерфейс
#        (репозитории, /explore и т.д.), включая корневую страницу
#        (LANDING_PAGE=login).
#      - Public/Private конкретного репозитория — закрывает git-ПРОТОКОЛ
#        (git clone/push по HTTP и SSH), НЕЗАВИСИМО от REQUIRE_SIGNIN_VIEW.
#        Проверено вживую: PUBLIC-репозиторий анонимно клонируется по git
#        вообще без токена/ключа. Поэтому DEFAULT_PRIVATE=private ниже —
#        новые репозитории по умолчанию требуют токен/ключ и для git тоже.
#
#   4. SSO — ЧЕРЕЗ POCKET ID, не Authelia. Регистрация OIDC-клиента — не
#      ручная правка YAML, а common.sh:dk_pocketid_oidc_register_client
#      (REST API). Дальше Forgejo сам добавляет источник входа
#      ('forgejo admin auth add-oauth') — этот шаг не менялся, он и раньше
#      не зависел от того, какой именно OIDC-провайдер на другом конце.
#
# GIT ПО SSH — без изменений, отдельный TCP-порт (не HTTP, Caddy тут не
# помощник, домены/пути его не касаются вообще): Forgejo запускает свой
# встроенный SSH-сервер внутри контейнера на ФИКСИРОВАННОМ непривилегированном
# порту (см. FORGEJO_SSH_INTERNAL_PORT ниже, сейчас 2222; НЕ 22 — Forgejo
# фатально отказывается слушать порт <1024, см. комментарий у переменной).
# Наружу — порт, выбранный пользователем на шаге 1 (проброс делает Docker),
# публикуется напрямую через ufw, в обход Caddy — ssh-клиент так же не
# может пройти интерактивный веб-вход, свою аутентификацию делает сам
# (ключи).
#
# ПОРЯДОК ШАГОВ ВАЖЕН: администратор создаётся ДО настройки OIDC (шаг 3
# перед шагом 4), с логином, СОВПАДАЮЩИМ с логином, который будет
# использоваться при первом входе через Pocket ID. Тогда при первом входе
# через SSO (ACCOUNT_LINKING: auto, USERNAME: preferred_username) Forgejo
# свяжет вход именно с этим — уже админским — локальным аккаунтом, а не
# создаст рядом второй, обычный.
#
# OIDC discovery (Forgejo сам, его бэкенд на Go) идёт по HTTPS с проверкой
# сертификата — та же ситуация, что и у Vaultwarden: недоверенный
# сертификат (домен ещё не резолвится, Let's Encrypt ещё не выпустил и
# т.п.) — discovery упадёт. Чинится так же — переменной окружения
# SSL_CERT_FILE (Go на Linux уважает её так же, как rustls-native-certs у
# Vaultwarden, см. crypto/x509 в стандартной библиотеке Go) с полным
# бандлом сертификатов
# (системные + сертификат Pocket ID), а не только своим — иначе сломался бы
# любой другой исходящий HTTPS от Forgejo (миграции репозиториев по
# https:// и т.п.).
#
# STATEFILE: "step8_N".
# =============================================================================

enable_full_logging

echo "${BOLD}${CYAN}==========================================================================="
echo "  НАСТРОЙКА GIT-СЕРВЕРА (FORGEJO)"
echo "===========================================================================${NC}"

TOTAL_STEPS=8
DONE_COUNT=$(grep -c '^step8_' "$STATEFILE" 2>/dev/null || true)
DONE_COUNT="${DONE_COUNT:-0}"
if [ "$DONE_COUNT" -gt 0 ] && [ "$DONE_COUNT" -lt "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Найден файл состояния: пройдено $DONE_COUNT из $TOTAL_STEPS шагов модуля, продолжаем"
elif [ "$DONE_COUNT" -ge "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Модуль уже был выполнен ранее (все $TOTAL_STEPS шагов пройдены)"
fi
echo ""

FORGEJO_DIR="$APPS_DIR/forgejo"
FORGEJO_LOCAL_PORT=3080
# Внутренний (внутри контейнера) порт SSH-сервера Forgejo — ФИКСИРОВАННЫЙ,
# НЕ то же самое, что FORGEJO_SSH_PORT (внешний, выбирается пользователем
# на шаге 1). Обязательно НЕПРИВИЛЕГИРОВАННЫЙ (>=1024): Forgejo при загрузке
# конфига категорически отказывается слушать порт <1024 (например 22) —
# фатальная ошибка "Forgejo is not supposed to be run as root" при ЛЮБОМ
# запуске бинарника (и у самого сервера, и у любой CLI-команды 'forgejo
# admin ...', обе грузят один и тот же app.ini) — проверка НЕ про то, кем
# запущена команда (docker exec -u git тут не помогает), а про сам номер
# порта в конфиге. Наружу это не видно: клиенты видят внешний
# FORGEJO_SSH_PORT (проброс портов Docker делает остальное).
FORGEJO_SSH_INTERNAL_PORT=2222
# Путь к app.ini ВНУТРИ контейнера — стандартный для официального образа
# (том ./data:/data, Gitea/Forgejo кладёт конфиг в <APP_DATA_PATH>/gitea/conf).
# Передаём явно во ВСЕ вызовы 'forgejo admin ...' через docker exec: без
# него бинарник иногда не может определить путь к уже установленному
# конфигу сам (увидено вживую: "Unable to load config file for a installed
# Forgejo instance") — видимо, поиск по умолчанию зависит от рабочей
# директории/окружения, которые "docker exec" не гарантирует так же, как
# у основного процесса контейнера (тот запускается через свой entrypoint).
FORGEJO_APP_INI="/data/gitea/conf/app.ini"
FORGEJO_PATH_FILE="$FORGEJO_DIR/path_prefix"
FORGEJO_SSH_PORT_FILE="$FORGEJO_DIR/ssh_port"
FORGEJO_ADMIN_USER_FILE="$FORGEJO_DIR/admin_user"
FORGEJO_ADMIN_PASSWORD_FILE="$FORGEJO_DIR/admin_password"
FORGEJO_API_TOKEN_FILE="$FORGEJO_DIR/api_token"
FORGEJO_OIDC_SECRET_FILE="$FORGEJO_DIR/oidc_client_secret"
FORGEJO_CA_BUNDLE="$FORGEJO_DIR/combined-ca.pem"
FORGEJO_DOWNLOADS_MARKER="$FORGEJO_DIR/downloads_enabled"
FORGEJO_DOWNLOADS_DIR="$APPS_DIR/downloads"

# forgejo_root_url — печатает ROOT_URL (со слэшем на конце, как требует
# Forgejo) на основе текущего пути под корневым доменом, либо IP:порт, если
# базовый домен ещё не настроен (модуль 2, шаг 5).
forgejo_root_url() {
    local path domain
    path=$(read_or_default "$FORGEJO_PATH_FILE" "git")
    if domain=$(dk_hostname); then
        echo "https://${domain}/${path}/"
    else
        local ip
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
        [ -z "$ip" ] && ip="127.0.0.1"
        echo "http://${ip}:${FORGEJO_LOCAL_PORT}/"
    fi
}

# forgejo_write_caddy_claims — регистрирует путь Forgejo и (опционально)
# путь /downloads/ через claim_root_domain (common.sh) — НЕ через целый
# кастомный файл conf.d/forgejo.caddy, как было раньше. Раньше нужен был
# отдельный файл из-за точечного гейта на "/" (см. историю в шапке файла) —
# гейта больше нет, значит и держать сайт отдельным файлом с ручной
# сборкой не нужно, обычная заявка на путь через общий механизм подходит.
#
# /downloads/* — НЕЗАВИСИМАЯ заявка (Caddy отдаёт файлы САМ, Forgejo о
# запросе даже не узнаёт; единственный способ дать кому-то ссылку без
# входа — REQUIRE_SIGNIN_VIEW у Forgejo блокирует абсолютно любой
# браузерный просмотр без исключений, ни Public-репозиторий, ни Releases,
# ни /raw/ не помогают, проверено вживую). "uri strip_prefix /downloads"
# нужен, потому что claim_root_domain (в отличие от старого handle_path)
# НЕ срезает путь-маску сам — Caddy передаёт файловому серверу путь как
# есть, без этой строки он искал бы файл по /srv/downloads/downloads/...
# Печатает 0/возвращает успех, если базовый домен настроен, иначе 1 (сайт
# не публикуется — вызывающий код сам решает, что сказать пользователю).
forgejo_write_caddy_claims() {
    local path domain
    path=$(read_or_default "$FORGEJO_PATH_FILE" "git")
    domain=$(dk_hostname) || return 1

    # Миграция: раньше был один claim с именем "forgejo" (без гейта на
    # веб-часть вообще). Если он ещё существует — убираем, иначе он
    # продолжит пускать все запросы в обход новых forgejo_1gitprotocol/
    # forgejo_2web claim'ов (Caddy не разрешает два разных совпадающих
    # определения, но раз имя файла изменилось, старый не заменится сам).
    if [ -f "$APPS_DIR/caddy/.root_claims/forgejo" ]; then
        rm -f "$APPS_DIR/caddy/.root_claims/forgejo"
    fi

    # Git-протокол по HTTPS (clone/push/fetch) — БЕЗ гейта. git-клиент не
    # умеет проходить браузерный редирект на Pocket ID, поставить сюда
    # forward_auth — значит сломать сам git. Пути сверены по исходникам
    # Forgejo (routers/web/githttp.go) — ".git" в адресе не обязателен,
    # Forgejo сам обрезает суффикс, если он есть.
    claim_root_domain "forgejo_1gitprotocol" \
        "/${path}/*/*/info/refs /${path}/*/*/git-upload-pack /${path}/*/*/git-receive-pack /${path}/*/*/git-upload-archive /${path}/*/*/HEAD /${path}/*/*/objects/*" \
        "reverse_proxy dk_forgejo:3000"

    # Всё остальное под /${path} — веб-морда Forgejo. Раньше была
    # осознанно не защищена (у Pocket ID нет forward_auth) — теперь гейтим
    # через собственный хаб: тот уже проверяет сессию Pocket ID сам (см.
    # 04_nexus404.sh, /api/auth-check), а Caddy просто спрашивает у него
    # разрешения перед тем, как пустить запрос дальше.
    claim_root_domain "forgejo_2web" "/${path}*" \
        "forward_auth dk_nexus404:80 {
    uri /api/auth-check
}
reverse_proxy dk_forgejo:3000"

    if [ -f "$FORGEJO_DOWNLOADS_MARKER" ]; then
        claim_root_domain "forgejo_downloads" "/downloads*" \
            "uri strip_prefix /downloads
root * /srv/downloads
file_server browse"
    fi
    return 0
}

# dk_registry_tags <хост> <репозиторий> — печатает "сырое" JSON-тело ответа
# "GET /v2/<репозиторий>/tags/list" (Docker Registry HTTP API v2). Сначала
# пробует анонимно; если реестр отвечает 401 (обычная практика — анонимный
# pull для публичных образов всё равно требует токен по протоколу, просто
# без пароля), проходит стандартный "token dance": берёт realm/service/scope
# из заголовка WWW-Authenticate, получает токен, повторяет запрос с ним.
# Возвращает 1, если ни один из вариантов не сработал (сеть, реестр лежит,
# протокол изменился) — вызывающий код сам решает, что делать (запасной тег).
dk_registry_tags() {
    local host="$1" repo="$2"
    local url="https://${host}/v2/${repo}/tags/list"
    local tmp code www_auth realm service scope token

    tmp=$(mktemp)
    code=$(curl -s -o "$tmp" -w '%{http_code}' --max-time 15 "$url" 2>>"$LOGFILE") || true
    if [ "$code" = "200" ]; then
        cat "$tmp"
        rm -f "$tmp"
        return 0
    fi
    rm -f "$tmp"

    if [ "$code" = "401" ]; then
        www_auth=$(curl -sI --max-time 15 "$url" 2>>"$LOGFILE" | grep -i '^www-authenticate:' | tr -d '\r')
        realm=$(printf '%s' "$www_auth" | grep -oP 'realm="\K[^"]+')
        service=$(printf '%s' "$www_auth" | grep -oP 'service="\K[^"]+')
        scope=$(printf '%s' "$www_auth" | grep -oP 'scope="\K[^"]+')
        if [ -n "$realm" ]; then
            token=$(curl -fsS --max-time 15 "${realm}?service=${service}&scope=${scope}" 2>>"$LOGFILE" | grep -oP '"token"\s*:\s*"\K[^"]+')
            if [ -n "$token" ]; then
                curl -fsS --max-time 15 -H "Authorization: Bearer ${token}" "$url" 2>>"$LOGFILE"
                return $?
            fi
        fi
    fi
    return 1
}

# forgejo_pick_image — печатает "codeberg.org/forgejo/forgejo:<тег>" с
# актуальным СТАБИЛЬНЫМ МАЖОРНЫМ тегом (например "11") — именно такие
# "катящиеся" мажорные теги Forgejo обновляет сам при выходе патчей внутри
# той же ветки. У образа НЕТ тега ":latest" — это осознанное решение
# проекта Forgejo (не Docker Hub, а свой реестр на Codeberg), увидено
# вживую: "docker compose up" с ним падает "not found". Отсюда и вся эта
# функция — раньше модуль был написан по аналогии с остальными образами
# в проекте (Vaultwarden/Authelia — у НИХ ":latest" есть), это и было
# ошибкой. Возвращает 1, если ни один "чистый" числовой тег не нашёлся —
# вызывающий код сам подставляет запасной вариант.
forgejo_pick_image() {
    local raw major
    raw=$(dk_registry_tags "codeberg.org" "forgejo/forgejo") || return 1
    major=$(grep -oP '"[0-9]+"' <<< "$raw" | tr -d '"' | sort -n -u | tail -1)
    [ -n "$major" ] || return 1
    echo "codeberg.org/forgejo/forgejo:${major}"
}

# forgejo_wait_ready — ждёт до 36 секунд ответа от локального healthz.
# Возвращает 0, если дождались, 1 — если нет. Используется везде, где нужно
# дождаться Forgejo после (пере)запуска контейнера (шаг 1, шаг 4 после смены
# сертификата, forgejo_retrofit_compose) — раньше был скопирован один и тот
# же 12-строчный цикл в три места, что легко было забыть обновить синхронно.
forgejo_wait_ready() {
    local _
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
        curl -fsS -m 3 "http://127.0.0.1:${FORGEJO_LOCAL_PORT}/api/healthz" >/dev/null 2>>"$LOGFILE" && return 0
        sleep 3
    done
    return 1
}

# forgejo_retrofit_compose — правит УЖЕ СУЩЕСТВУЮЩИЙ docker-compose.yml,
# если он создан более старой версией этого модуля с одной из известных
# проблем: тег ":latest" (не существует у Codeberg), привилегированный
# внутренний SSH-порт 22 (Forgejo фатально откажется запускаться), и/или
# отсутствие FORGEJO__security__INSTALL_LOCK — без него Forgejo, поднятый
# только переменными окружения (без веб-визарда установки), считает себя
# "не установленным" и блокирует ЛЮБЫЕ 'forgejo admin ...' команды с
# MustInstalled() ("...or run 'forgejo web' command to install Forgejo"),
# даже если веб-интерфейс и так прекрасно работает. Вызывается БЕЗУСЛОВНО
# при каждом заходе в модуль (аналогичный приём когда-то использовался и
# для гейта Authelia, ныне не актуально) — а не только внутри шага 1,
# потому что у уже развёрнутых серверов шаг 1 отмечен
# пройденным и его блок просто не выполнится повторно. Если что-то поправили
# и контейнер уже существует — пересоздаём его, чтобы изменения применились
# сразу же, не заставляя человека тереть STATEFILE руками.
forgejo_retrofit_compose() {
    local compose="$FORGEJO_DIR/docker-compose.yml"
    [ -f "$compose" ] || return 0
    local changed=0 ssh_port image

    if grep -q 'forgejo/forgejo:latest' "$compose"; then
        if ! image=$(forgejo_pick_image); then
            image="codeberg.org/forgejo/forgejo:11"
        fi
        sed -i "s#codeberg.org/forgejo/forgejo:latest#${image}#" "$compose"
        echo "${GREEN}[✓]${NC} Исправлен несуществующий тег образа ':latest' на ${image}"
        changed=1
    fi

    if grep -q 'FORGEJO__server__SSH_LISTEN_PORT: "22"' "$compose"; then
        ssh_port=$(read_or_default "$FORGEJO_SSH_PORT_FILE" "")
        sed -i "s#FORGEJO__server__SSH_LISTEN_PORT: \"22\"#FORGEJO__server__SSH_LISTEN_PORT: \"${FORGEJO_SSH_INTERNAL_PORT}\"#" "$compose"
        [ -n "$ssh_port" ] && sed -i "s#:${ssh_port}:22\"#:${ssh_port}:${FORGEJO_SSH_INTERNAL_PORT}\"#" "$compose"
        echo "${GREEN}[✓]${NC} Исправлен привилегированный внутренний SSH-порт (22) на ${FORGEJO_SSH_INTERNAL_PORT}"
        changed=1
    fi

    if ! grep -q 'FORGEJO__security__INSTALL_LOCK' "$compose"; then
        awk '
            /FORGEJO__database__DB_TYPE:/ && !done {
                print
                print "      FORGEJO__security__INSTALL_LOCK: \"true\""
                done=1
                next
            }
            { print }
        ' "$compose" > "${compose}.dk_tmp"
        cat "${compose}.dk_tmp" > "$compose"
        rm -f "${compose}.dk_tmp"
        echo "${GREEN}[✓]${NC} Добавлен FORGEJO__security__INSTALL_LOCK=true (без"
        echo "    него 'forgejo admin ...' считает инстанс неустановленным)"
        changed=1
    fi

    if ! grep -q 'FORGEJO__service__LANDING_PAGE' "$compose"; then
        awk '
            /FORGEJO__service__REQUIRE_SIGNIN_VIEW:/ && !done {
                print
                print "      FORGEJO__service__LANDING_PAGE: \"login\""
                done=1
                next
            }
            { print }
        ' "$compose" > "${compose}.dk_tmp"
        cat "${compose}.dk_tmp" > "$compose"
        rm -f "${compose}.dk_tmp"
        echo "${GREEN}[✓]${NC} Добавлен FORGEJO__service__LANDING_PAGE=login (без него корневая"
        echo "    страница показывалась всем анонимно, минуя REQUIRE_SIGNIN_VIEW)"
        changed=1
    fi

    if ! grep -q 'FORGEJO__repository__DEFAULT_PRIVATE' "$compose"; then
        awk '
            /FORGEJO__database__DB_TYPE:/ && !done {
                print
                print "      FORGEJO__repository__DEFAULT_PRIVATE: \"private\""
                done=1
                next
            }
            { print }
        ' "$compose" > "${compose}.dk_tmp"
        cat "${compose}.dk_tmp" > "$compose"
        rm -f "${compose}.dk_tmp"
        echo "${GREEN}[✓]${NC} Добавлен FORGEJO__repository__DEFAULT_PRIVATE=private (новые"
        echo "    репозитории теперь приватны по умолчанию — см. примечание в шапке"
        echo "    файла про git-протокол и Public/Private)"
        changed=1
    fi

    if ! grep -q 'FORGEJO__attachment__MAX_SIZE' "$compose"; then
        awk '
            /FORGEJO__database__DB_TYPE:/ && !done {
                print
                print "      FORGEJO__attachment__MAX_SIZE: \"-1\""
                print "      FORGEJO__attachment__MAX_FILES: \"100\""
                print "      FORGEJO__repository.upload__FILE_MAX_SIZE: \"-1\""
                print "      FORGEJO__repository.upload__MAX_FILES: \"100\""
                print "      FORGEJO__repository.release__FILE_MAX_SIZE: \"-1\""
                print "      FORGEJO__repository.release__MAX_FILES: \"100\""
                done=1
                next
            }
            { print }
        ' "$compose" > "${compose}.dk_tmp"
        cat "${compose}.dk_tmp" > "$compose"
        rm -f "${compose}.dk_tmp"
        echo "${GREEN}[✓]${NC} Сняты лимиты загрузки (вложения issues/PR, загрузка файлов через"
        echo "    веб-морду, файлы релизов — раньше были ограничены дефолтами Forgejo)"
        changed=1
    fi

    if [ "$changed" = "1" ] && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx dk_forgejo; then
        echo "${CYAN}[*]${NC} Применяю исправления — пересоздаю контейнер Forgejo..."
        run_spinner "Перезапуск Forgejo" "dk_compose_up '$FORGEJO_DIR'"
        if forgejo_wait_ready; then
            echo "${GREEN}[✓]${NC} Forgejo перезапущен и отвечает"
        else
            echo "${YELLOW}[?]${NC} Forgejo не ответил за 36 секунд после перезапуска —"
            echo "    проверьте: docker logs dk_forgejo"
        fi
    fi
}
forgejo_retrofit_compose

# Безусловно пересобираем claim'ы Caddy при каждом заходе в модуль — не
# только внутри шага 2 (is_done "step8_2"). Иначе для уже установленных
# серверов (шаг 2 давно пройден) новый гейт на веб-часть (forward_auth
# через хаб) не применился бы сам, потребовалась бы ручная очистка
# STATEFILE. Безопасно вызывать всегда — claim_root_domain идемпотентен,
# домен ещё не настроен -> просто тихо пропускается (return 1).
if [ -f "$FORGEJO_DIR/docker-compose.yml" ] && dk_hostname >/dev/null 2>&1; then
    forgejo_write_caddy_claims || true
fi

# Старый conf.d/forgejo.caddy (отдельный файл-сайт с точечным гейтом на
# "/") больше не используется — начиная с этой версии модуля путь Forgejo
# регистрируется через claim_root_domain (пишет в _root.caddy). Если файл
# остался от старой установки — убираем его и один раз пересобираем
# заявки, иначе Caddy будет видеть Forgejo сразу по двум конфликтующим
# путям (свой домен по старому файлу + путь по новому механизму).
if [ -f "$APPS_DIR/caddy/conf.d/forgejo.caddy" ]; then
    rm -f "$APPS_DIR/caddy/conf.d/forgejo.caddy"
    echo "${CYAN}[*]${NC} Убран устаревший conf.d/forgejo.caddy (старая схема с поддоменом" >&2
    echo "    и точечным гейтом на '/') — путь теперь регистрируется через" >&2
    echo "    claim_root_domain, см. заголовок файла" >&2
    forgejo_write_caddy_claims || true
fi

# ================== ШАГ 8_1 ==================
if is_done "step8_1"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 1: Установка Forgejo"
    echo "===========================================================================${NC}"

    if ! check_disk_space 1024; then
        echo "${RED}[!]${NC} Меньше 1024 MB свободного места на диске — недостаточно для Forgejo"
        exit 1
    fi

    mkdir -p "$FORGEJO_DIR/data"

    FORGEJO_PATH=$(read_or_default "$FORGEJO_PATH_FILE" "")
    if [ -z "$FORGEJO_PATH" ]; then
        PATH_RE='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'
        FORGEJO_DOMAIN_HINT=$(read_or_default "$DOMAINFILE" "<ваш_домен>")
        echo "${CYAN}[*]${NC} По умолчанию 'git' — итог: ${FORGEJO_DOMAIN_HINT}/git"
        while true; do
            read -rp "${YELLOW}[?]${NC} Путь для Forgejo (Enter — 'git'): " FORGEJO_PATH_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
            FORGEJO_PATH="${FORGEJO_PATH_INPUT:-git}"
            if [[ "$FORGEJO_PATH" =~ $PATH_RE ]]; then
                break
            fi
            echo "${RED}[!]${NC} Только буквы/цифры/дефис, без точек и пробелов, пример: git"
        done
        echo "$FORGEJO_PATH" > "$FORGEJO_PATH_FILE"
    else
        echo "${CYAN}[*]${NC} Путь уже выбран ранее: /$FORGEJO_PATH"
    fi

    MAIN_SSH_PORT=$(read_or_default "$PORTFILE" "22")
    FORGEJO_SSH_PORT=$(read_or_default "$FORGEJO_SSH_PORT_FILE" "")
    if [ -z "$FORGEJO_SSH_PORT" ]; then
        echo "${CYAN}[*]${NC} Forgejo запускает СВОЙ SSH-сервер (для 'git clone ssh://...') —"
        echo "    ему нужен отдельный порт, не совпадающий с основным SSH-портом"
        echo "    сервера ($MAIN_SSH_PORT)."
        while true; do
            read -rp "${YELLOW}[?]${NC} Порт для git-SSH (Enter — по умолчанию 2222): " FORGEJO_SSH_PORT_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
            FORGEJO_SSH_PORT="${FORGEJO_SSH_PORT_INPUT:-2222}"
            if ! [[ "$FORGEJO_SSH_PORT" =~ ^[0-9]+$ ]] || [ "$FORGEJO_SSH_PORT" -lt 1024 ] || [ "$FORGEJO_SSH_PORT" -gt 65535 ]; then
                echo "${RED}[!]${NC} Порт должен быть числом от 1024 до 65535"
                continue
            fi
            if [ "$FORGEJO_SSH_PORT" = "$MAIN_SSH_PORT" ]; then
                echo "${RED}[!]${NC} Совпадает с основным SSH-портом сервера ($MAIN_SSH_PORT), выберите другой"
                continue
            fi
            if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${FORGEJO_SSH_PORT}\$"; then
                echo "${RED}[!]${NC} Порт $FORGEJO_SSH_PORT уже занят другой службой на этом сервере, выберите другой"
                continue
            fi
            break
        done
        echo "$FORGEJO_SSH_PORT" > "$FORGEJO_SSH_PORT_FILE"
    else
        echo "${CYAN}[*]${NC} Порт для git-SSH уже выбран ранее: $FORGEJO_SSH_PORT"
    fi

    FORGEJO_ROOT_URL=$(forgejo_root_url)
    FORGEJO_SSH_DOMAIN=$(dk_hostname 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$FORGEJO_SSH_DOMAIN" ] && FORGEJO_SSH_DOMAIN="127.0.0.1"
    FORGEJO_SERVER_DOMAIN="$FORGEJO_SSH_DOMAIN"

    FORGEJO_IMAGE=""
    if FORGEJO_IMAGE=$(forgejo_pick_image); then
        echo "${GREEN}[✓]${NC} Тег образа: ${FORGEJO_IMAGE##*:} (текущий стабильный мажор)"
    else
        FORGEJO_IMAGE="codeberg.org/forgejo/forgejo:11"
        echo "${YELLOW}[?]${NC} Не удалось определить тег образа автоматически — беру"
        echo "    запасной вариант: ${FORGEJO_IMAGE}"
        echo "    Если он не найдётся при запуске, поправьте строку 'image:' в"
        echo "    $FORGEJO_DIR/docker-compose.yml и перезапустите шаг."
    fi

    # Codeberg (реестр Forgejo, не Docker Hub) осознанно НЕ публикует тег
    # ":latest" — для НОВОГО файла (никакого docker-compose.yml ещё нет)
    # подбираем реальный тег сразу. Починка уже СУЩЕСТВУЮЩЕГО файла со
    # старым ":latest"/привилегированным SSH-портом — в forgejo_retrofit_compose
    # выше, вызывается безусловно ещё до этого шага.

    # LANDING_PAGE=login — НЕ решает полностью задачу закрыть "/" от
    # анонимного просмотра: анонимный заход всё равно отдаёт 200 с публичной
    # страницей, проверено вживую. Раньше (см. историю в шапке файла) это
    # докрывалось точечным гейтом Caddy именно на "/" — теперь гейта нет
    # нигде вообще (Pocket ID не форвард-прокси), значит корневая страница
    # ОСОЗНАННО остаётся видна анонимно, как и было решено при переходе на
    # новую архитектуру (приватность репозиториев обеспечивают два уровня
    # ниже, не гейт). Ставим LANDING_PAGE ради полноты — вдруг в будущей
    # версии Forgejo это исправят на своей стороне.
    #
    # DEFAULT_PRIVATE=private — новые репозитории приватны по умолчанию.
    # ВАЖНО (см. также "ПРИВАТНОСТЬ" в шапке файла): REQUIRE_SIGNIN_VIEW
    # закрывает только БРАУЗЕР — git-протокол проверяет флаг Public/Private
    # репозитория отдельно, своим кодом. Publicный репозиторий клонируется
    # анонимно по git вообще без токена/ключа, что бы ни было выставлено
    # в REQUIRE_SIGNIN_VIEW — отсюда и этот дефолт.
    if [ ! -f "$FORGEJO_DIR/docker-compose.yml" ]; then
        # combined-ca.pem подкладывается ПУСТЫМ файлом системных сертификатов
        # контейнера уже сейчас (см. шапку файла) — заполняется реальными
        # системными CA сразу после первого запуска ниже, чтобы SSL_CERT_FILE
        # никогда не указывал на пустой/отсутствующий файл (это обнулило бы
        # доверенные CA у Forgejo целиком, а не оставило бы их системными).
        # Сертификат портала входа добавляется туда же на шаге 4 (SSO).
        touch "$FORGEJO_CA_BUNDLE"

        cat > "$FORGEJO_DIR/docker-compose.yml" << EOF
services:
  forgejo:
    image: ${FORGEJO_IMAGE}
    container_name: dk_forgejo
    restart: unless-stopped
    environment:
      USER_UID: "1000"
      USER_GID: "1000"
      FORGEJO__database__DB_TYPE: "sqlite3"
      FORGEJO__security__INSTALL_LOCK: "true"
      FORGEJO__server__DOMAIN: "${FORGEJO_SERVER_DOMAIN}"
      FORGEJO__server__ROOT_URL: "${FORGEJO_ROOT_URL}"
      FORGEJO__server__SSH_DOMAIN: "${FORGEJO_SSH_DOMAIN}"
      FORGEJO__server__SSH_PORT: "${FORGEJO_SSH_PORT}"
      FORGEJO__server__SSH_LISTEN_PORT: "${FORGEJO_SSH_INTERNAL_PORT}"
      FORGEJO__server__START_SSH_SERVER: "true"
      FORGEJO__server__DISABLE_SSH: "false"
      FORGEJO__service__DISABLE_REGISTRATION: "true"
      FORGEJO__service__REQUIRE_SIGNIN_VIEW: "true"
      FORGEJO__service__LANDING_PAGE: "login"
      FORGEJO__repository__DEFAULT_PRIVATE: "private"
      FORGEJO__oauth2_client__ENABLE_AUTO_REGISTRATION: "true"
      FORGEJO__oauth2_client__ACCOUNT_LINKING: "auto"
      FORGEJO__oauth2_client__USERNAME: "preferred_username"
      # Снимаем лимиты загрузки — по умолчанию Forgejo режет: вложения к
      # issues/PR (100 МБ/файл, 5 файлов), загрузку файлов через веб-морду
      # (50 МБ/файл, 5 файлов), файлы релизов (2048 МБ/файл, 5 файлов).
      # MAX_SIZE=-1 отключает проверку размера целиком (проверено по
      # исходникам Forgejo, services/attachment/attachment.go — условие
      # "maxFileSize >= 0 && size > maxFileSize" при -1 никогда не сработает).
      # На git clone/push (обычная работа с репозиторием) эти лимиты и так
      # не влияют — они только про вложения/загрузку файлов через веб.
      # Общего лимита на "вес всего проекта" у Forgejo просто нет как
      # понятия (проверено — ничего похожего в исходниках нет), единственный
      # реальный предел — свободное место на диске сервера.
      FORGEJO__attachment__MAX_SIZE: "-1"
      FORGEJO__attachment__MAX_FILES: "100"
      FORGEJO__repository.upload__FILE_MAX_SIZE: "-1"
      FORGEJO__repository.upload__MAX_FILES: "100"
      FORGEJO__repository.release__FILE_MAX_SIZE: "-1"
      FORGEJO__repository.release__MAX_FILES: "100"
      SSL_CERT_FILE: "/etc/ssl/certs/dk-combined-ca.pem"
    ports:
      - "127.0.0.1:${FORGEJO_LOCAL_PORT}:3000"
      - "0.0.0.0:${FORGEJO_SSH_PORT}:${FORGEJO_SSH_INTERNAL_PORT}"
    volumes:
      - ./data:/data
      - ./combined-ca.pem:/etc/ssl/certs/dk-combined-ca.pem:ro
    networks:
      - ${DK_NETWORK}

networks:
  ${DK_NETWORK}:
    external: true
EOF
        echo "${GREEN}[✓]${NC} docker-compose.yml создан: $FORGEJO_DIR/docker-compose.yml"
    else
        echo "${CYAN}[*]${NC} docker-compose.yml уже существует, не трогаю"
    fi

    if command -v ufw >/dev/null 2>&1; then
        check_or_fail "открытие git-SSH порта $FORGEJO_SSH_PORT в ufw" \
            ufw allow "${FORGEJO_SSH_PORT}/tcp" comment "Forgejo SSH"
        echo "${GREEN}[✓]${NC} Порт $FORGEJO_SSH_PORT/tcp открыт в ufw"
    else
        echo "${YELLOW}[?]${NC} ufw не найден — откройте порт $FORGEJO_SSH_PORT/tcp в своём файрволе вручную"
    fi

    run_spinner "Запуск Forgejo" "dk_compose_up '$FORGEJO_DIR'"

    echo "${CYAN}[*]${NC} Жду готовности Forgejo..."
    if forgejo_wait_ready; then
        echo "${GREEN}[✓]${NC} Forgejo отвечает на http://127.0.0.1:${FORGEJO_LOCAL_PORT}"
    else
        echo "${RED}[!]${NC} Forgejo не ответил за 36 секунд — проверьте: docker logs dk_forgejo"
        exit 1
    fi

    # Реальные системные CA контейнера — заполняем бандл, чтобы SSL_CERT_FILE
    # с самого начала указывал не в пустоту (см. комментарий выше).
    if docker exec dk_forgejo cat /etc/ssl/certs/ca-certificates.crt > "$FORGEJO_CA_BUNDLE" 2>>"$LOGFILE"; then
        echo "${GREEN}[✓]${NC} Системные сертификаты контейнера сохранены в:"
        echo "    $FORGEJO_CA_BUNDLE"
    else
        echo "${YELLOW}[?]${NC} Не удалось прочитать системные сертификаты контейнера —"
        echo "    $FORGEJO_CA_BUNDLE остался пустым."
        echo "    Обычные HTTPS-запросы Forgejo наружу могут не работать."
    fi

    echo "${GREEN}[✓]${NC} Шаг 1 завершён успешно"
    mark_done "step8_1"
fi

# ================== ШАГ 8_2 ==================
if is_done "step8_2"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 2: Caddy"
    echo "===========================================================================${NC}"

    FORGEJO_PATH=$(read_or_default "$FORGEJO_PATH_FILE" "git")

    if FORGEJO_DOMAIN_NOW=$(dk_hostname); then
        forgejo_write_caddy_claims
        echo "${GREEN}[✓]${NC} Caddy настроен: https://${FORGEJO_DOMAIN_NOW}/${FORGEJO_PATH} -> dk_forgejo:3000"
    else
        echo "${YELLOW}[?]${NC} Базовый домен не настроен — пропускаю публикацию через Caddy."
        echo "    Forgejo доступен только локально: http://127.0.0.1:${FORGEJO_LOCAL_PORT}"
        echo "    Настройте домен (модуль 2, шаг 5), затем перезапустите этот шаг."
    fi

    echo "${GREEN}[✓]${NC} Шаг 2 завершён успешно"
    mark_done "step8_2"
fi

# ================== ШАГ 8_3 ==================
if is_done "step8_3"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 3: Администратор"
    echo "===========================================================================${NC}"

    FORGEJO_ADMIN_USER=$(read_or_default "$USERFILE" "admin")

    # Если Pocket ID установлена — подставляем почту администратора оттуда
    # (GET /api/users с admin-ключом, поле email — проверено по исходникам
    # Pocket ID, dto.UserDto). Не "подсматриваем чужое" — это твоя же учётка
    # администратора, которую ты сам заводил в Pocket ID; здесь просто не
    # заставляем вводить её второй раз руками, достаточно подтвердить Enter.
    FORGEJO_EMAIL_DEFAULT=""
    if dk_pocketid_available; then
        POCKETID_API_KEY_S3=$(cat "$POCKETID_API_KEY_FILE")
        POCKETID_USERS_RESP=$(curl -fsS -m 10 -H "X-API-Key: ${POCKETID_API_KEY_S3}" \
            "${POCKETID_API_BASE_REF}/api/users?pagination[limit]=5" 2>>"$LOGFILE") || true
        if [ -n "$POCKETID_USERS_RESP" ]; then
            FORGEJO_EMAIL_DEFAULT=$(printf '%s' "$POCKETID_USERS_RESP" | jq -r '.data[]? | select(.isAdmin==true) | .email // empty' 2>/dev/null | head -n1)
        fi
    fi

    FORGEJO_ADMIN_EMAIL=""
    while true; do
        if [ -n "$FORGEJO_EMAIL_DEFAULT" ]; then
            read -rp "${YELLOW}[?]${NC} Email для администратора Forgejo (Enter — '$FORGEJO_EMAIL_DEFAULT'): " EMAIL_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
            EMAIL_INPUT="${EMAIL_INPUT:-$FORGEJO_EMAIL_DEFAULT}"
        else
            read -rp "${YELLOW}[?]${NC} Email для администратора Forgejo: " EMAIL_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
        fi
        if [[ "$EMAIL_INPUT" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
            FORGEJO_ADMIN_EMAIL="$EMAIL_INPUT"
            break
        fi
        echo "${RED}[!]${NC} Похоже, это не email — попробуйте снова"
    done

    # ВАЖНО: везде ниже "docker exec -u git dk_forgejo forgejo ..." — НЕ
    # опечатка и не лишняя предосторожность. Сам процесс Forgejo внутри
    # контейнера запущен от пользователя 'git' (не root — образ на это
    # специально проверяет и падает: "Forgejo is not supposed to be run as
    # root", увидено вживую при "docker exec" без -u, который по умолчанию
    # заходит как root). CLI-команды 'forgejo admin ...' — тот же самый
    # бинарник, значит и им нужен тот же пользователь.
    if docker exec -u git dk_forgejo forgejo admin user list --config "$FORGEJO_APP_INI" --admin 2>>"$LOGFILE" | awk '{print $2}' | grep -qx "$FORGEJO_ADMIN_USER"; then
        echo "${CYAN}[*]${NC} Администратор '$FORGEJO_ADMIN_USER' уже существует, пропускаю создание"
    else
        FORGEJO_ADMIN_PASSWORD="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32)"
        if docker exec -u git dk_forgejo forgejo admin user create \
            --config "$FORGEJO_APP_INI" \
            --admin --username "$FORGEJO_ADMIN_USER" --email "$FORGEJO_ADMIN_EMAIL" \
            --password "$FORGEJO_ADMIN_PASSWORD" --must-change-password=false >>"$LOGFILE" 2>&1; then
            echo "$FORGEJO_ADMIN_PASSWORD" > "$FORGEJO_ADMIN_PASSWORD_FILE"
            chmod 600 "$FORGEJO_ADMIN_PASSWORD_FILE"
            echo "$FORGEJO_ADMIN_USER" > "$FORGEJO_ADMIN_USER_FILE"
            echo "${GREEN}[✓]${NC} Администратор '$FORGEJO_ADMIN_USER' создан, пароль сохранён"
            echo "    в $FORGEJO_ADMIN_PASSWORD_FILE (права 600)"
        else
            echo "${RED}[!]${NC} Не удалось создать администратора —"
            echo "    смотрите $LOGFILE"
            exit 1
        fi
    fi

    echo "${GREEN}[✓]${NC} Шаг 3 завершён успешно"
    mark_done "step8_3"
fi

# ================== ШАГ 8_4 ==================
if is_done "step8_4"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 4: Единый вход через Pocket ID (OIDC SSO)"
    echo "===========================================================================${NC}"

    POCKETID_URL_FILE_REF="$POCKETID_DIR_REF/public_url"

    if ! dk_pocketid_available; then
        echo "${CYAN}[*]${NC} Pocket ID не установлена (или ещё не завершила установку) — пропускаю."
        echo "    Останется классический вход по логину+паролю. Если позже поставите"
        echo "    Pocket ID — сотрите строку 'step8_4' из:"
        echo "    $STATEFILE"
        echo "    и зайдите в этот пункт меню снова."
    elif docker exec -u git dk_forgejo forgejo admin auth list --config "$FORGEJO_APP_INI" 2>>"$LOGFILE" | awk '{print $2}' | grep -qx "pocketid"; then
        echo "${CYAN}[*]${NC} Источник входа 'pocketid' уже настроен в Forgejo, пропускаю"
    elif ! [ -s "$POCKETID_URL_FILE_REF" ]; then
        echo "${YELLOW}[?]${NC} Pocket ID установлена, но не нашёл её адрес ($POCKETID_URL_FILE_REF) —"
        echo "    похоже, модуль Pocket ID не был доведён до конца. Пропускаю."
    elif echo "${CYAN}[*]${NC} Pocket ID найдена (портал: $(cat "$POCKETID_URL_FILE_REF"))." && ! confirm_yn "Включить через неё единый вход в Forgejo?"; then
        echo "${CYAN}[*]${NC} Пропущено по выбору — классический вход по логину+паролю остаётся"
    else
        FORGEJO_ROOT_URL_NOW=$(forgejo_root_url)
        POCKETID_URL_NOW=$(cat "$POCKETID_URL_FILE_REF")
        REDIRECT_URI="${FORGEJO_ROOT_URL_NOW}user/oauth2/pocketid/callback"

        if dk_pocketid_oidc_register_client "Forgejo" "$REDIRECT_URI" "$FORGEJO_OIDC_SECRET_FILE"; then
            FORGEJO_OIDC_SECRET=$(cat "$FORGEJO_OIDC_SECRET_FILE")

            # Сертификат Pocket ID — в доверенные Forgejo ДО попытки
            # add-oauth (а не после): 'forgejo admin auth add-oauth' сам
            # делает OIDC discovery по HTTPS СРАЗУ при добавлении источника,
            # а не позже при первом входе — если сертификат не в доверенных,
            # эта самая первая попытка уже падает на TLS ("certificate
            # signed by unknown authority"), увидено вживую. Тот же приём,
            # что и у Vaultwarden.
            POCKETID_HOSTNAME=$(echo "$POCKETID_URL_NOW" | sed -E 's#^https?://##; s#/.*$##')
            if command -v openssl >/dev/null 2>&1; then
                EXTRACTED_CHAIN=$(echo | timeout 10 openssl s_client -connect "${POCKETID_HOSTNAME}:443" -servername "${POCKETID_HOSTNAME}" -showcerts 2>>"$LOGFILE" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p')
                if [ -n "$EXTRACTED_CHAIN" ]; then
                    SYSTEM_CA=$(docker exec dk_forgejo cat /etc/ssl/certs/ca-certificates.crt 2>>"$LOGFILE")
                    {
                        [ -n "$SYSTEM_CA" ] && printf '%s\n' "$SYSTEM_CA"
                        printf '%s\n' "$EXTRACTED_CHAIN"
                    } > "$FORGEJO_CA_BUNDLE"
                    docker restart dk_forgejo >>"$LOGFILE" 2>&1 || true
                    echo "${CYAN}[*]${NC} Жду готовности Forgejo после перезапуска..."
                    if forgejo_wait_ready; then
                        echo "${GREEN}[✓]${NC} Сертификат Pocket ID (${POCKETID_HOSTNAME}) добавлен к доверенным"
                    else
                        echo "${RED}[!]${NC} Forgejo не ответил за 36 секунд после перезапуска — проверьте:"
                        echo "    docker logs dk_forgejo"
                        exit 1
                    fi
                else
                    echo "${YELLOW}[?]${NC} Не удалось получить сертификат"
                    echo "    ${POCKETID_HOSTNAME}:443 — если у Pocket ID ещё нет"
                    echo "    валидного сертификата (домен не резолвится или Let's"
                    echo "    Encrypt ещё не выпустил), OIDC discovery, скорее всего,"
                    echo "    упадёт с ошибкой TLS."
                fi
            else
                echo "${YELLOW}[?]${NC} openssl не найден — пропускаю добавление сертификата Pocket ID"
                echo "    в доверенные. OIDC discovery, скорее всего, упадёт с ошибкой TLS."
            fi

            if docker exec -u git dk_forgejo forgejo admin auth add-oauth \
                --config "$FORGEJO_APP_INI" \
                --name "pocketid" \
                --provider "openidConnect" \
                --key "$(cat "${FORGEJO_OIDC_SECRET_FILE}.id")" \
                --secret "$FORGEJO_OIDC_SECRET" \
                --auto-discover-url "${POCKETID_URL_NOW%/}/.well-known/openid-configuration" \
                --scopes "openid profile email" >>"$LOGFILE" 2>&1; then
                echo "${GREEN}[✓]${NC} Источник входа 'pocketid' добавлен в Forgejo"
            else
                echo "${RED}[!]${NC} Не удалось добавить источник входа в Forgejo —"
                echo "    смотрите $LOGFILE"
                echo "    (клиент уже зарегистрирован в Pocket ID и секрет сохранён в"
                echo "    $FORGEJO_OIDC_SECRET_FILE —"
                echo "    добавить источник вручную можно командой"
                echo "    'forgejo admin auth add-oauth' в контейнере)"
                exit 1
            fi

            echo "${GREEN}[✓]${NC} SSO включён — на странице входа Forgejo появится кнопка 'pocketid'"
        else
            echo "${YELLOW}[?]${NC} Не удалось зарегистрировать клиента в Pocket ID — см. вывод выше."
            echo "    Классический вход по логину+паролю остаётся, шаг не отмечен пройденным."
            exit 1
        fi
    fi

    echo "${GREEN}[✓]${NC} Шаг 4 завершён успешно"
    mark_done "step8_4"
fi

# ================== ШАГ 8_5 ==================
if is_done "step8_5"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 5: Карточка в хабе и финальная проверка"
    echo "===========================================================================${NC}"

    FORGEJO_PATH_NOW=$(read_or_default "$FORGEJO_PATH_FILE" "git")
    if FORGEJO_DOMAIN_NOW=$(dk_hostname); then
        add_hub_card "Forgejo" "Git" "" "fas fa-code-branch" "Сервисы" "widget" "forgejo-repos"
        echo "${GREEN}[✓]${NC} Карточка Forgejo зарегистрирована в хабе (mode=widget)"
    fi

    CHECK_FAILED=0
    echo "===== Результаты финальной проверки модуля Forgejo ($(date '+%Y-%m-%d %H:%M:%S')) =====" >> "$LOGFILE"

    check_item "Контейнер Forgejo запущен" bash -c "docker ps --format '{{.Names}}' | grep -qx dk_forgejo"
    check_item "Forgejo отвечает локально" curl -fsS -m 3 "http://127.0.0.1:${FORGEJO_LOCAL_PORT}/api/healthz"
    check_item "Администратор создан" test -s "$FORGEJO_ADMIN_USER_FILE"
    check_item "Карточка зарегистрирована в хабе" hub_card_exists "Forgejo"

    echo ""
    if [ "$CHECK_FAILED" -eq 0 ]; then
        echo "${GREEN}[✓]${NC} Все проверки пройдены успешно"
    else
        echo "${RED}[!]${NC} Проверок с ошибкой: $CHECK_FAILED — просмотрите список выше"
    fi

    echo "${GREEN}[✓]${NC} Шаг 5 завершён успешно"
    mark_done "step8_5"
fi

# ================== ШАГ 8_6 ==================
if is_done "step8_6"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 6: Приватность существующих репозиториев"
    echo "===========================================================================${NC}"

    FORGEJO_ADMIN_USER_NOW=$(read_or_default "$FORGEJO_ADMIN_USER_FILE" "")
    if [ -z "$FORGEJO_ADMIN_USER_NOW" ] || [ ! -s "$FORGEJO_ADMIN_PASSWORD_FILE" ]; then
        echo "${CYAN}[*]${NC} Администратор ещё не создан (шаг 3) — зайдите в этот пункт меню"
        echo "    снова после того, как шаг 3 пройдёт."
    else
        # DEFAULT_PRIVATE=private (шаг 1) действует ТОЛЬКО на новые репозитории —
        # созданные до появления этой настройки (или вручную сделанные Public)
        # остаются публичными и клонируются по git БЕЗ токена/ключа вообще (см.
        # шапку файла про три независимых уровня приватности). Проверяем это
        # здесь через API Forgejo с Basic-авторизацией паролем администратора —
        # не через CLI (генерация токена через 'forgejo admin user
        # generate-access-token' синтаксически может отличаться между версиями,
        # а пароль администратора у нас и так уже надёжно сохранён с шага 3).
        FORGEJO_ADMIN_PASSWORD_NOW=$(cat "$FORGEJO_ADMIN_PASSWORD_FILE")
        REPOS_JSON=$(curl -fsS -u "${FORGEJO_ADMIN_USER_NOW}:${FORGEJO_ADMIN_PASSWORD_NOW}" \
            "http://127.0.0.1:${FORGEJO_LOCAL_PORT}/api/v1/users/${FORGEJO_ADMIN_USER_NOW}/repos?limit=50" 2>>"$LOGFILE")

        PUBLIC_REPOS=$(printf '%s' "$REPOS_JSON" | python3 -c "
import json, sys
try:
    for r in json.load(sys.stdin):
        if not r.get('private'):
            print(r['full_name'])
except Exception:
    pass
" 2>>"$LOGFILE")

        if [ -z "$PUBLIC_REPOS" ]; then
            echo "${GREEN}[✓]${NC} Публичных репозиториев не найдено — всё уже приватно"
        else
            echo "${YELLOW}[?]${NC} Найдены публичные репозитории (клонируются по git без токена/ключа):"
            printf '%s\n' "$PUBLIC_REPOS" | sed 's/^/    - /'
            if confirm_yn "Сделать их все приватными?"; then
                while IFS= read -r full_name; do
                    [ -z "$full_name" ] && continue
                    if curl -fsS -X PATCH -u "${FORGEJO_ADMIN_USER_NOW}:${FORGEJO_ADMIN_PASSWORD_NOW}" \
                        -H "Content-Type: application/json" -d '{"private": true}' \
                        "http://127.0.0.1:${FORGEJO_LOCAL_PORT}/api/v1/repos/${full_name}" >>"$LOGFILE" 2>&1; then
                        echo "${GREEN}[✓]${NC}    $full_name теперь приватный"
                    else
                        echo "${RED}[✗]${NC}  $full_name — не удалось, смотрите $LOGFILE"
                    fi
                done <<< "$PUBLIC_REPOS"
            else
                echo "${CYAN}[*]${NC} Пропущено по выбору — репозитории остались публичными"
            fi
        fi
    fi

    echo "${GREEN}[✓]${NC} Шаг 6 завершён успешно"
    mark_done "step8_6"
fi

# ================== ШАГ 8_7 ==================
if is_done "step8_7"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 7: Публичная папка для скачивания (опционально)"
    echo "===========================================================================${NC}"

    if [ -f "$FORGEJO_DOWNLOADS_MARKER" ]; then
        echo "${CYAN}[*]${NC} Уже настроено ранее, пропускаю"
    else
        echo "${CYAN}[*]${NC} Публичный путь '/downloads/' на этом же домене — файлы без"
        echo "    пароля, минуя Forgejo вообще (единственный способ дать ссылку без"
        echo "    входа — Public/Releases/raw у Forgejo этого не дают, проверено)."
        if confirm_yn "Настроить?"; then
            mkdir -p "$FORGEJO_DOWNLOADS_DIR"
            touch "$FORGEJO_DOWNLOADS_MARKER"

            # Владелец папки — sudo-пользователь (тот же, что и везде в
            # проекте, из USERFILE), а не root — чтобы класть файлы можно
            # было обычным scp/cp без sudo на каждый файл. Если модуль 1
            # (базовая настройка) ещё не пройден, USERFILE пуст — тогда
            # просто оставляем root (chown пропускаем), без этого ниже
            # получилась бы фраза "принадлежит пользователю " с пустым
            # именем.
            DK_SUDO_USER=$(read_or_default "$USERFILE" "")
            DK_OWNER_NOTE=""
            if [ -n "$DK_SUDO_USER" ] && id "$DK_SUDO_USER" >/dev/null 2>&1; then
                chown -R "$DK_SUDO_USER":"$DK_SUDO_USER" "$FORGEJO_DOWNLOADS_DIR"
                DK_OWNER_NOTE=" (без sudo, папка принадлежит пользователю $DK_SUDO_USER)"
            fi

            if ! grep -q "${FORGEJO_DOWNLOADS_DIR}:/srv/downloads" "$APPS_DIR/caddy/docker-compose.yml" 2>/dev/null; then
                sed -i "/volumes:/a\\      - ${FORGEJO_DOWNLOADS_DIR}:/srv/downloads:ro" "$APPS_DIR/caddy/docker-compose.yml"
            fi

            # Новый volume-маунт (/srv/downloads) требует ПЕРЕСОЗДАНИЯ
            # контейнера Caddy — просто reload конфига (что делает сам
            # claim_root_domain) том не подхватит, нужен полный dk_compose_up.
            run_spinner "Применяю volume /srv/downloads (пересоздание Caddy)" "dk_compose_up '$APPS_DIR/caddy'"

            if forgejo_write_caddy_claims; then
                echo "${GREEN}[✓]${NC} Готово: кладите файлы в $FORGEJO_DOWNLOADS_DIR/"
                if [ -n "$DK_OWNER_NOTE" ]; then
                    echo "    (без sudo, папка принадлежит пользователю $DK_SUDO_USER)"
                fi
                echo "    Ссылка без пароля: https://<этот_домен>/downloads/<имя_файла>"
            else
                echo "${RED}[!]${NC} Не удалось применить (домен не настроен?) — зайдите в этот"
                echo "    шаг снова после настройки домена (модуль 2, шаг 5)."
                exit 1
            fi
        else
            echo "${CYAN}[*]${NC} Пропущено по выбору"
        fi
    fi

    echo "${GREEN}[✓]${NC} Шаг 7 завершён успешно"
    mark_done "step8_7"
fi

# ================== ШАГ 8 ==================
if is_done "step8_8"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 8: Токен для виджета хаба (чтение + запись репозиториев)"
    echo "===========================================================================${NC}"

    FORGEJO_HUB_TOKEN_FILE="$FORGEJO_DIR/hub_widget_token"
    FORGEJO_ADMIN_USER_S8=$(read_or_default "$FORGEJO_ADMIN_USER_FILE" "")

    FORGEJO_HUB_TOKEN_SCOPES="read:repository,write:repository,read:user,write:user"
    FORGEJO_HUB_TOKEN_SCOPE_FILE="${FORGEJO_HUB_TOKEN_FILE}.scopes"

    if [ -z "$FORGEJO_ADMIN_USER_S8" ]; then
        echo "${YELLOW}[?]${NC} Администратор ещё не создан (шаг 3) — пропускаю,"
        echo "    виджет хаба (список репозиториев) работать не будет."
    elif [ -s "$FORGEJO_HUB_TOKEN_FILE" ] \
        && [ -s "$FORGEJO_HUB_TOKEN_SCOPE_FILE" ] \
        && [ "$(cat "$FORGEJO_HUB_TOKEN_SCOPE_FILE")" = "$FORGEJO_HUB_TOKEN_SCOPES" ]; then
        echo "${CYAN}[*]${NC} Токен уже существует и с нужными правами, пропускаю"
    else
        # Токен либо не создавался, либо создавался раньше с другим
        # набором scope (в т.ч. до появления write:*/read:user в этом
        # скрипте — тогда файл со scope-отметкой либо отсутствует, либо
        # содержит старое значение). Пересоздаём с нуля, не пытаясь
        # угадать права реальным запросом к API — запрос на создание
        # репозитория имеет побочный эффект (реально создаёт репо), а
        # чтения списка недостаточно, чтобы проверить write-права.
        if [ -s "$FORGEJO_HUB_TOKEN_FILE" ]; then
            echo "${YELLOW}[?]${NC} Сохранённый токен создан со старым набором прав —"
            echo "    пересоздаю с scope: ${FORGEJO_HUB_TOKEN_SCOPES}"
            rm -f "$FORGEJO_HUB_TOKEN_FILE" "$FORGEJO_HUB_TOKEN_SCOPE_FILE"
        fi
        # Нужны read+write scope — виджет хаба не только читает список
        # репозиториев, но и создаёт репо из ZIP и заливает файлы (см.
        # widget_forgejo_upload_zip/upload_files в 04_nexus404.sh).
        # "read:user"/"write:user" обязательны отдельно от "repository" —
        # POST/GET /user/repos относятся к группе "user" в API Forgejo.
        # Имя токена с меткой времени — Forgejo не даёт дубли имён.
        FORGEJO_HUB_TOKEN=$(docker exec -u git dk_forgejo forgejo admin user generate-access-token \
            --config "$FORGEJO_APP_INI" \
            --username "$FORGEJO_ADMIN_USER_S8" \
            --token-name "nexus404-hub-$(date +%s)" \
            --scopes "$FORGEJO_HUB_TOKEN_SCOPES" \
            --raw 2>>"$LOGFILE")
        if [ -z "$FORGEJO_HUB_TOKEN" ]; then
            echo "${RED}[!]${NC} Не удалось создать токен — смотрите $LOGFILE"
            exit 1
        fi
        echo "$FORGEJO_HUB_TOKEN" > "$FORGEJO_HUB_TOKEN_FILE"
        chmod 600 "$FORGEJO_HUB_TOKEN_FILE"
        echo "$FORGEJO_HUB_TOKEN_SCOPES" > "$FORGEJO_HUB_TOKEN_SCOPE_FILE"
        chmod 600 "$FORGEJO_HUB_TOKEN_SCOPE_FILE"
        echo "${GREEN}[✓]${NC} Токен для виджета хаба создан (чтение + запись репозиториев)"
    fi

    echo "${GREEN}[✓]${NC} Шаг 8 завершён успешно"
    mark_done "step8_8"
fi

echo ""
echo "${BOLD}${CYAN}==========================================================================="
echo "  Forgejo настроен — сохраните эту информацию."
echo "===========================================================================${NC}"

FORGEJO_PATH_NOW=$(read_or_default "$FORGEJO_PATH_FILE" "git")
FORGEJO_SSH_PORT_NOW=$(read_or_default "$FORGEJO_SSH_PORT_FILE" "2222")
FORGEJO_ADMIN_USER_NOW=$(read_or_default "$FORGEJO_ADMIN_USER_FILE" "-")
SSO_IS_ON=0
docker exec -u git dk_forgejo forgejo admin auth list --config "$FORGEJO_APP_INI" 2>/dev/null | awk '{print $2}' | grep -qx "pocketid" && SSO_IS_ON=1

echo "$(pad_field "Локальный адрес:" "$FIELD_WIDTH")http://127.0.0.1:${FORGEJO_LOCAL_PORT}"
if FORGEJO_DOMAIN_NOW=$(dk_hostname 2>/dev/null); then
    echo "$(pad_field "Адрес (браузер):" "$FIELD_WIDTH")https://${FORGEJO_DOMAIN_NOW}/${FORGEJO_PATH_NOW}"
    echo "$(pad_field "Git по HTTPS:" "$FIELD_WIDTH")https://${FORGEJO_DOMAIN_NOW}/${FORGEJO_PATH_NOW}/<логин>/<репо>.git"
    if [ -f "$FORGEJO_DOWNLOADS_MARKER" ]; then
        echo "$(pad_field "Публичные файлы:" "$FIELD_WIDTH")https://${FORGEJO_DOMAIN_NOW}/downloads/<файл>"
        echo "    (без пароля; кладите файлы в $FORGEJO_DOWNLOADS_DIR/)"
    fi
else
    echo "$(pad_field "Внешний адрес:" "$FIELD_WIDTH")не настроен (нет базового домена, см. модуль 2, шаг 5)"
fi
FORGEJO_SSH_HOST=$(dk_hostname 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
echo "$(pad_field "Git по SSH:" "$FIELD_WIDTH")ssh://git@${FORGEJO_SSH_HOST}:${FORGEJO_SSH_PORT_NOW}/<логин>/<репо>.git"
echo "$(pad_field "Администратор:" "$FIELD_WIDTH")$FORGEJO_ADMIN_USER_NOW"
if [ "$SSO_IS_ON" -eq 1 ]; then
    echo "$(pad_field "Единый вход:" "$FIELD_WIDTH")включён через Pocket ID"
    echo "    (кнопка 'pocketid' на странице входа)"
else
    echo "$(pad_field "Единый вход:" "$FIELD_WIDTH")не включён — обычный вход по логину+паролю"
fi
echo "$(pad_field "Карточка в хабе:" "$FIELD_WIDTH")widget 'forgejo-repos' (см. NEXUS404 Interface)"
echo "$(pad_field "Пароль администратора:" "$FIELD_WIDTH")$FORGEJO_ADMIN_PASSWORD_FILE"
echo "    (не выводится сюда, права 600)"
echo ""
