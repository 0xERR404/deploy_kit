#!/bin/bash
# =============================================================================
# common.sh — общие переменные и функции для всех модулей меню.
# Не запускается напрямую, подключается через `source common.sh`.
# =============================================================================

# Защита от повторного подключения при последовательном вызове модулей
if [ -n "${DK_COMMON_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
DK_COMMON_LOADED=1

# КРИТИЧНО: закрепляем UTF-8-локаль явно, не полагаясь на настройки системы.
# Без этого на серверах без настроенной локали (частый случай на минимальных
# Ubuntu-установках — LC_ALL пуст, LC_CTYPE=POSIX) bash считает длину строки
# ${#text} в БАЙТАХ, а не в символах. Кириллица — 2 байта на символ, из-за
# этого pad_field (выравнивание колонок в финальных сводках) начинает
# занижать отступ или (для длинных меток) уходит в отрицательное значение
# и обрубается до нуля — колонки "плывут" или вообще пропадает отступ.
# Проверено вживую: без этой строки "Команда на подключение:" (23 символа,
# но 39+ байт) получала pad=0 вместо pad=3. C.UTF-8 выбрана как самая
# надёжная — встроена в glibc на Ubuntu/Debian по умолчанию, не требует
# предварительного locale-gen (в отличие от en_US.UTF-8 и т.п.).
export LC_ALL=C.UTF-8

# Примечание: "set -e" сюда намеренно не ставим — common.sh подключается
# в главном меню, а строгий режим там нежелателен (уронит весь цикл меню
# при любой мелкой ошибке). "set -e" включается точечно в menu.sh на время
# выполнения самого модуля — как это было в оригинальном setup.sh.

DK_DIR="/var/lib/deploy_kit"
LOGFILE="$DK_DIR/deploy_kit.log"
STATEFILE="$DK_DIR/deploy_kit.state"
SSHD_CONFIG="/etc/ssh/sshd_config"
USERFILE="$DK_DIR/deploy_kit.newuser"
PORTFILE="$DK_DIR/deploy_kit.sshport"
AUTHMETHODFILE="$DK_DIR/deploy_kit.authmethod"
DOMAINFILE="$DK_DIR/deploy_kit.domain"
HEALTHLOG="$DK_DIR/deploy_kit_health.log"
NTFY_CONF="$DK_DIR/deploy_kit.ntfy.conf"
NTFYLOG="$DK_DIR/deploy_kit_ntfy_events.log"
SERVERNAMEFILE="$DK_DIR/deploy_kit.server_name"
DK_VERSION="1.0"
FLAGFILE="/etc/.deploy_kit_installed"

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8 2>/dev/null || true

# цвета терминала (echo печатает без -e)
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

if [ "$(id -u)" -ne 0 ]; then
    echo "${RED}[!]${NC} Скрипт нужно запускать от root (или через sudo)"
    exit 1
fi

if ! grep -qiE 'ubuntu|debian' /etc/os-release 2>/dev/null; then
    echo "${RED}[!]${NC} Скрипт поддерживает только Ubuntu/Debian — обнаружена другая"
    echo "    ОС, прерываю."
    exit 1
fi

mkdir -p "$DK_DIR"
chmod 755 "$DK_DIR"
touch "$STATEFILE" "$LOGFILE"
chmod 644 "$STATEFILE" "$LOGFILE"

# PID фоновой команды (для Ctrl+C)
RUNNING_PID=""
on_interrupt() {
    echo ""
    if [ -n "$RUNNING_PID" ] && kill -0 "$RUNNING_PID" 2>/dev/null; then
        echo "${YELLOW}[*]${NC} Фоновый процесс (PID $RUNNING_PID) не останавливаю —"
        echo "    дайте apt/dpkg доработать самому."
        echo "    При следующем запуске скрипт сам подождёт освобождения блокировки apt."
    fi
    echo "${RED}[!]${NC} Скрипт прерван пользователем."
    exit 130
}
trap on_interrupt INT TERM

# пройден ли шаг
is_done() {
    grep -qx "$1" "$STATEFILE" 2>/dev/null
}

# отметить шаг пройденным
mark_done() {
    echo "$1" >> "$STATEFILE"
}

# файл или дефолт: read_or_default <файл> <дефолт>
read_or_default() {
    [ -f "$1" ] && cat "$1" || echo "$2"
}

# паддинг по символам, не байтам (важно для кириллицы)
pad_field() {
    local text="$1" width="$2" len pad
    len=${#text}
    pad=$((width - len))
    [ "$pad" -lt 0 ] && pad=0
    printf "%s%*s" "$text" "$pad" ""
}

# Единая ширина полей для всех финальных сводок модулей (pad_field) — раньше
# каждый модуль выбирал своё число (20/22/24/26), из-за чего отступы у
# одних и тех же по смыслу полей "плыли" от модуля к модулю при пролистывании
# вывода. 26 — под самую длинную метку из всех модулей ("Токен для новых
# агентов:", 24 символа) плюс небольшой запас.
FIELD_WIDTH=26

# check_item "описание" команда... — единая проверка для финального шага
# каждого модуля (было продублировано ЧЕМ БУКВАЛЬНО идентичным кодом в
# каждом из 7 модулей — перенесено сюда один раз, чтобы не расходились).
# Ожидает, что вызывающий модуль сам инициализировал CHECK_FAILED=0 до
# первого вызова и сам печатает итог после последнего.
check_item() {
    local desc="$1"
    shift
    if "$@" >> "$LOGFILE" 2>&1; then
        echo "${GREEN}[✓]${NC}    $desc"
    else
        echo "${RED}[✗]${NC}  $desc"
        CHECK_FAILED=$((CHECK_FAILED + 1))
    fi
    sleep 0.3
}

# тихий запуск с проверкой; при ошибке — хвост лога и exit
check_or_fail() {
    local desc="$1"
    shift
    if ! "$@" >> "$LOGFILE" 2>&1; then
        echo "${RED}[!]${NC} Ошибка: $desc"
        echo "--- последние строки лога ($LOGFILE) ---"
        tail -n 8 "$LOGFILE"
        exit 1
    fi
}

# check_disk_space <нужно_MB> [путь=/] — true, если свободного места достаточно
check_disk_space() {
    local required_mb="$1"
    local path="${2:-/}"
    local free_mb
    free_mb=$(df -Pm "$path" 2>/dev/null | awk 'NR==2{print $4}')
    [ -n "$free_mb" ] && [ "$free_mb" -ge "$required_mb" ]
}

# ждём освобождения dpkg/apt
wait_for_apt_lock() {
    local waited=0
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        [ "$waited" -eq 0 ] && printf "\r%s[*]%s apt/dpkg занят другим процессом, жду освобождения..." "$CYAN" "$NC"
        sleep 2
        waited=$((waited + 2))
        if [ "$waited" -ge 180 ]; then
            echo ""
            echo "${RED}[!]${NC} apt/dpkg занят дольше 180с — возможно, завис процесс."
            echo "    Проверьте: ps aux | grep apt"
            break
        fi
    done
    if [ "$waited" -gt 0 ]; then
        echo ""
    fi
    return 0
}

# retry_apt "текст" "apt-команда" — до 3 попыток с паузой, затем exit 1
retry_apt() {
    local msg="$1"
    local cmd="$2"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local attempt i pid start_ts status elapsed

    for attempt in 1 2 3; do
        wait_for_apt_lock
        start_ts=$(date +%s)
        i=0

        eval "$cmd" >> "$LOGFILE" 2>&1 &
        pid=$!
        RUNNING_PID="$pid"

        while kill -0 "$pid" 2>/dev/null; do
            i=$(( (i+1) % 10 ))
            { printf "\r\033[K${CYAN}[%s]${NC} %s (%dс)" "${spin:$i:1}" "$msg" "$(( $(date +%s) - start_ts ))" > /dev/tty; } 2>/dev/null
            sleep 0.1
        done

        if wait "$pid"; then status=0; else status=$?; fi
        RUNNING_PID=""
        elapsed=$(( $(date +%s) - start_ts ))

        if [ "$status" -eq 0 ]; then
            printf "\r\033[K${GREEN}[✓]${NC} %s (%dс)\n" "$msg" "$elapsed"
            return 0
        fi

        printf "\r\033[K${RED}[!]${NC} %s — ошибка (%dс)\n" "$msg" "$elapsed"
        if [ "$attempt" -lt 3 ]; then
            echo "${YELLOW}[*]${NC} повтор через 5с..."
            sleep 5
        fi
    done

    echo "${RED}[!]${NC} $msg — не удалось после 3 попыток"
    echo "--- последние строки лога ($LOGFILE) ---"
    tail -n 8 "$LOGFILE"
    exit 1
}

# enable_full_logging — весь дальнейший вывод (заголовки, echo, запросы,
# результаты) идёт одновременно и в терминал, и в $LOGFILE. Вызывать один
# раз в начале модуля, до первого echo.
#
# Кадры анимации спиннера (run_spinner/retry_apt) в лог НЕ попадают —
# они пишутся напрямую в /dev/tty, в обход этого редиректа, иначе на
# каждую apt-команду в лог улетали бы сотни строк с "\r" и кодами
# перерисовки. В лог идёт только финальная строка результата ([✓]/[!]).
enable_full_logging() {
    exec > >(tee -a "$LOGFILE") 2>&1
}

# спиннер: run_spinner "Текст" "команда"
run_spinner() {
    local msg="$1"
    shift
    local cmd="$*"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    local start_ts
    start_ts=$(date +%s)

    [[ "$cmd" == *apt-get* ]] && wait_for_apt_lock

    eval "$cmd" >> "$LOGFILE" 2>&1 &
    local pid=$!
    RUNNING_PID="$pid"

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        { printf "\r\033[K${CYAN}[%s]${NC} %s (%dс)" "${spin:$i:1}" "$msg" "$(( $(date +%s) - start_ts ))" > /dev/tty; } 2>/dev/null
        sleep 0.1
    done

    local status
    if wait "$pid"; then
        status=0
    else
        status=$?
    fi
    RUNNING_PID=""

    local elapsed=$(( $(date +%s) - start_ts ))
    if [ $status -eq 0 ]; then
        printf "\r\033[K${GREEN}[✓]${NC} %s (%dс)\n" "$msg" "$elapsed"
    else
        printf "\r\033[K${RED}[!]${NC} %s — ошибка (%dс)\n" "$msg" "$elapsed"
        echo "--- последние строки лога ($LOGFILE) ---"
        tail -n 8 "$LOGFILE"
        exit 1
    fi
}

# пауза: ожидание Enter
pause_step() {
    read -rp "[Enter] Нажмите Enter, чтобы продолжить..." _ || exit 1
    echo ""
}

# confirm_or_exit "Вопрос" "Сообщение при выходе" — y продолжает, n выходит
confirm_or_exit() {
    local question="$1"
    local exit_msg="$2"
    local confirm=""
    while true; do
        read -rp "${YELLOW}[?]${NC} $question (y/n): " confirm
        case "$confirm" in
            y|Y) return 0 ;;
            n|N) echo "${RED}[!]${NC} $exit_msg"; exit 1 ;;
            *) echo "${RED}[!]${NC} Введите 'y' или 'n'" ;;
        esac
    done
}

# confirm_yn "Вопрос" — как confirm_or_exit, но НЕ прерывает модуль на "n"
# (return 1), для опциональных шагов. Ввод недоступен (нет TTY) — тоже
# трактуется как "нет" (return 1), не как ошибка: опциональный шаг просто
# тихо пропускается вместо падения всего модуля.
confirm_yn() {
    local question="$1"
    local confirm=""
    while true; do
        read -rp "${YELLOW}[?]${NC} $question (y/n): " confirm || return 1
        case "$confirm" in
            y|Y) return 0 ;;
            n|N) return 1 ;;
            *) echo "${RED}[!]${NC} Введите 'y' или 'n'" ;;
        esac
    done
}

# =============================================================================
# Общее для Docker-стека (используется модулем 2 и всеми последующими
# сервис-модулями, отсюда и место — common.sh, а не отдельный модуль)
# =============================================================================

# Корневая директория данных всех сервисов. Каждый сервис держит свой volume
# на хосте в $APPS_DIR/<сервис>/data — так решено в архитектуре проекта.
APPS_DIR="/opt/deploy_kit"

# Имя общей docker-сети: все контейнеры сервисов подключаются к ней,
# чтобы Caddy мог проксировать их по имени контейнера.
DK_NETWORK="dk_net"

# Убедиться, что общая docker-сеть создана. Идемпотентно.
ensure_dk_network() {
    docker network inspect "$DK_NETWORK" >/dev/null 2>&1 && return 0
    docker network create "$DK_NETWORK" >> "$LOGFILE" 2>&1
}

# retry_download "текст" "команда" — до 3 попыток с паузой между ними,
# для curl/wget и прочих сетевых команд (НЕ apt — для apt использовать
# retry_apt, там ещё и ожидание apt-lock). В отличие от retry_apt, при
# неудаче после всех попыток НЕ делает exit — возвращает 1, чтобы вызывающий
# модуль сам решил, что делать (например, попробовать другой источник).
retry_download() {
    local msg="$1"
    local cmd="$2"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local attempt i pid start_ts status elapsed

    for attempt in 1 2 3; do
        start_ts=$(date +%s)
        i=0

        eval "$cmd" >> "$LOGFILE" 2>&1 &
        pid=$!
        RUNNING_PID="$pid"

        while kill -0 "$pid" 2>/dev/null; do
            i=$(( (i+1) % 10 ))
            { printf "\r\033[K${CYAN}[%s]${NC} %s (%dс)" "${spin:$i:1}" "$msg" "$(( $(date +%s) - start_ts ))" > /dev/tty; } 2>/dev/null
            sleep 0.1
        done

        if wait "$pid"; then status=0; else status=$?; fi
        RUNNING_PID=""
        elapsed=$(( $(date +%s) - start_ts ))

        if [ "$status" -eq 0 ]; then
            printf "\r\033[K${GREEN}[✓]${NC} %s (%dс)\n" "$msg" "$elapsed"
            return 0
        fi

        printf "\r\033[K${RED}[!]${NC} %s — ошибка (%dс)\n" "$msg" "$elapsed"
        if [ "$attempt" -lt 3 ]; then
            echo "${YELLOW}[*]${NC} повтор через 5с..."
            sleep 5
        fi
    done

    return 1
}

# pick_working_mirror <проверочный_путь> <база1> [база2] [база3] ...
# Пробует curl -fsSL "<база><проверочный_путь>" по порядку, пока одна не
# ответит 2xx. При успехе печатает рабочую базу в stdout (return 0).
# Если ни одна не ответила — ничего не печатает (return 1).
# Нужен для источников, которые могут быть заблокированы по региону/IP
# (например download.docker.com за geo-block CloudFront) — тогда вместо
# единственной точки отказа перебираем известные зеркала.
pick_working_mirror() {
    local check_path="$1"
    shift
    local base
    for base in "$@"; do
        if curl -fsSL --max-time 15 "${base}${check_path}" -o /dev/null 2>>"$LOGFILE"; then
            echo "$base"
            return 0
        fi
    done
    return 1
}

# dk_compose_up <каталог_с_docker-compose.yml>
# Запускает `docker compose up -d` с --progress plain. Без этого флага
# compose (v2) при живом TTY рисует прогресс-бар НАПРЯМУЮ в /dev/tty, в
# обход stdout/stderr — редирект в $LOGFILE (и run_spinner/enable_full_logging)
# его не перехватывает. --progress plain переключает на обычные построчные
# сообщения через stdout, которые редирект перехватывает как положено.
# Используется каждым сервис-модулем, который поднимает свой compose-стек.
dk_compose_up() {
    (cd "$1" && docker compose --progress plain up -d)
}

# dk_hostname — печатает корневой домен (из DOMAINFILE, заполняется в модуле
# 2, шаг 5). Если домен не настроен — return 1, ничего не печатает; вызывающий
# код сам решает, что делать (обычно — работать по IP:порту).
#
# ВАЖНО (архитектура с NEXUS404 Interface): поддоменов на отдельные сервисы
# больше нет вообще — наружу торчит только Caddy на ЕДИНОМ корневом домене,
# все сервисы живут только во внутренней docker-сети (dk_net) и снаружи не
# видны ни на каком порту/хосте. Раньше эта функция принимала [префикс] и
# строила "<префикс>.<домен>" под отдельный поддомен на каждый сервис
# (vault.example.com, git.example.com и т.д.) — этот режим убран целиком.
# Единственный путь наружу для чего угодно теперь — путь под корневым
# доменом через claim_root_domain() (см. ниже), не отдельный хост.
dk_hostname() {
    local domain
    domain=$(read_or_default "$DOMAINFILE" "")
    [ -n "$domain" ] || return 1
    echo "$domain"
}

# notify_send <event_key> <заголовок> <текст> [priority=1-5] [tags]
#
# Шлёт push через JSON-эндпоинт ntfy (не через заголовки Title/Message —
# они не гарантируют UTF-8, а у нас всё на русском). Требует jq.
# Всегда пишет строку в NTFYLOG (отдельно от $LOGFILE), даже если доставка
# не удалась. Если NTFY_CONF нет — просто "доставлено=нет", без ошибок.
#
# Заголовок автоматически помечается именем сервера ("[метка] заголовок") —
# из SERVERNAMEFILE (задаётся в модуле ntfy, шаг 1), иначе `hostname`.
# Важно, если серверов несколько и все шлют в один топик/чат — иначе не
# понять, с какого сервера пришло уведомление.
#
# NTFY_CONF (создаётся модулем ntfy):
#   NTFY_URL="..." NTFY_TOPIC="..." NTFY_TOKEN="..." (токен может быть пустым —
#   режим "клиент + секретный топик на ntfy.sh" без авторизации)
#
# Безопасна под "set -e" — сетевая часть в подшелле с "|| true" снаружи.
notify_send() {
    local event="$1" title="$2" message="$3" priority="${4:-3}" tags="${5:-}"
    local stamp delivered="нет" label
    stamp=$(date '+%Y-%m-%d %H:%M:%S')
    label=$(read_or_default "$SERVERNAMEFILE" "")
    [ -z "$label" ] && label=$(hostname 2>/dev/null || echo "server")
    title="[$label] $title"

    if [ -f "$NTFY_CONF" ] && command -v jq >/dev/null 2>&1; then
        if (
            # shellcheck disable=SC1090
            source "$NTFY_CONF"
            [ -n "${NTFY_URL:-}" ] && [ -n "${NTFY_TOPIC:-}" ] || exit 1
            json=$(jq -n \
                --arg topic "$NTFY_TOPIC" \
                --arg title "$title" \
                --arg message "$message" \
                --argjson priority "$priority" \
                --arg tags "$tags" \
                '{topic:$topic, title:$title, message:$message, priority:$priority}
                 + (if $tags == "" then {} else {tags:[$tags]} end)')
            hdrs=(-H "Content-Type: application/json")
            [ -n "${NTFY_TOKEN:-}" ] && hdrs+=(-H "Authorization: Bearer ${NTFY_TOKEN}")
            curl -fsS -m 10 "${hdrs[@]}" -d "$json" "${NTFY_URL%/}"
        ) >/dev/null 2>&1; then
            delivered="да"
        fi
    fi

    {
        printf '%s | %-18s | %s | доставлено=%s\n' \
            "$stamp" "$event" "${message//$'\n'/ · }" "$delivered"
    } >> "$NTFYLOG" 2>/dev/null || true
}

# dk_caddy_reload — единая точка перезагрузки конфига Caddy без даунтайма.
# Раньше каждое место само делало `docker exec dk_caddy caddy reload ... || true`
# — и при реальном сбое reload (например синтаксическая ошибка где-то в
# conf.d) ошибка МОЛЧА проглатывалась: файлы на диске уже правильные, а
# живой Caddy в памяти продолжает работать со СТАРЫМ конфигом (без только
# что добавленного гейта/сайта) — снаружи выглядит так, будто изменения
# вообще не подействовали, без единой строчки объяснения почему. Теперь
# ошибка reload видна явно, с подсказкой, что проверить.
#
# Если контейнер dk_caddy ещё не запущен (например самый первый вызов до
# того, как модуль 2 его поднял) — это НЕ ошибка, тихо ничего не делаем.
dk_caddy_reload() {
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx dk_caddy; then
        return 0
    fi
    if docker exec dk_caddy caddy reload --config /etc/caddy/Caddyfile >> "$LOGFILE" 2>&1; then
        return 0
    fi
    echo "${RED}[!]${NC} Caddy НЕ смог перезагрузить конфиг (caddy reload завершился ошибкой) —" >&2
    echo "    файлы на диске уже обновлены, но живой Caddy их не подхватил. Проверьте:" >&2
    echo "    docker exec dk_caddy caddy validate --config /etc/caddy/Caddyfile" >&2
    echo "    docker logs dk_caddy --tail 30" >&2
    return 1
}

# =============================================================================
# write_caddy_site() и retrofit_auth_gate() — УБРАНЫ ЦЕЛИКОМ.
#
# Обе были построены вокруг старой модели "у каждого сервиса свой поддомен,
# свой отдельный site-блок в Caddy, а общий вход (Authelia forward_auth)
# наклеивается на каждый такой блок отдельной директивой import auth_gate".
#
# В архитектуре NEXUS404 Interface этой модели больше нет:
#   - Наружу торчит ТОЛЬКО Caddy на одном корневом домене — у сервисов нет
#     ни своих поддоменов, ни отдельных site-блоков вообще (см. dk_hostname
#     выше). Значит нечего "наклеивать гейтом" — сервисы просто не имеют
#     собственной внешней точки входа, куда можно было бы прийти в обход.
#   - Pocket ID (замена Authelia) — НЕ реализует forward_auth. Это чистый
#     OIDC-провайдер: выдаёт токены только тем, кто сам ходит по OIDC-протоколу
#     (Vaultwarden, Forgejo). У него нет механизма "закрыть логином вход
#     на произвольный путь произвольного сервиса" — то, на чём держался
#     весь auth_gate.
#   - Единственная внешняя точка входа — сам хаб (NEXUS404 Interface), и
#     логин перед ним реализован в самом хабе (собственный сервис входа),
#     а не Caddy-сниппетом. Всё остальное закрыто самим фактом, что оно
#     не видно снаружи (внутренняя docker-сеть) — защищать нечего.
#
# Единственный оставшийся способ выставить что-то наружу под корневым
# доменом (deploy-ссылка, секретный путь Vaultwarden и т.п.) — это
# claim_root_domain()/rebuild_root_caddy() ниже, без понятия "гейт".
# =============================================================================

# =============================================================================
# claim_root_domain — единственный способ выставить что-либо наружу под
# корневым доменом. В архитектуре NEXUS404 Interface это НЕ "один из
# способов" (как было раньше, наравне с write_caddy_site) — это ЕДИНСТВЕННЫЙ
# способ вообще, потому что своих поддоменов/хостов у сервисов больше нет.
#
# Всё, что реально претендует на путь под корневым доменом — это НЕ сами
# сервисы (они во внутренней docker-сети, снаружи не видны), а конкретные
# осознанно публикуемые вещи:
#   - сам хаб NEXUS404 Interface — обработчик "по умолчанию" (path="")
#   - секретный путь Vaultwarden для клиентов (Bitwarden app/extension)
#   - deploy-эндпоинт (фиксированная секретная ссылка)
#   - raw-ссылки на файлы/релизы из Forgejo, которые нужно давать другим людям
#
# Больше нет понятия "гейт" (protect 0/1, import auth_gate) — Pocket ID не
# умеет forward_auth (см. пояснение выше), поэтому у claim_root_domain не
# осталось смысла что-либо "закрывать" на уровне Caddy: единственная вещь,
# которая по-настоящему нуждается в логине — сам хаб, и он реализует это
# сам, внутри своего кода, а не через Caddy-сниппет.
#
# Все "заявки" на корневой домен копятся в .root_claims/<имя> (первая
# строка — путь-маска для path-матчера ИЛИ пустая строка для "всё
# остальное"/default-обработчика, дальше — тело блока), а rebuild_root_caddy
# ниже каждый раз пересобирает ЕДИНЫЙ файл conf.d/_root.caddy из всех
# заявок (Caddy не разрешает два разных файла с одинаковым хостом в
# site-блоке — "ambiguous site definition").
#
# claim_root_domain <имя> <путь-маска или ""> <тело_блока>
#   <путь-маска>  — например "/x7f92kd83jsq0plz4*" (со звёздочкой на конце
#                   для path-матчера Caddy). Пустая строка "" — ЕДИНСТВЕННЫЙ
#                   default-обработчик ("всё, что не подошло другим путям") —
#                   на него претендует только сам хаб.
claim_root_domain() {
    local name="$1" path="$2" body="$3"
    local dir="$APPS_DIR/caddy/.root_claims"
    mkdir -p "$dir"
    {
        echo "$path"
        printf '%s\n' "$body"
    } > "$dir/${name}"
    rebuild_root_caddy
}

# rebuild_root_caddy — пересобирает conf.d/_root.caddy целиком из всех заявок
# в .root_claims/. Безопасно вызывать когда угодно — если заявок нет или
# домен не настроен, тихо ничего не делает.
rebuild_root_caddy() {
    local dir="$APPS_DIR/caddy/.root_claims"
    local domain
    domain=$(read_or_default "$DOMAINFILE" "")
    [ -n "$domain" ] || return 0
    [ -d "$dir" ] || return 0
    ls "$dir"/* >/dev/null 2>&1 || return 0

    local out="$APPS_DIR/caddy/conf.d/_root.caddy"
    local default_body=""
    local f name path body

    {
        echo "${domain} {"
        # HSTS — говорит браузеру НИКОГДА не пытаться зайти по обычному
        # http:// на этот домен, даже если кто-то подсунет такую ссылку
        # (защита от downgrade-атаки). Caddy сам не добавляет этот
        # заголовок по умолчанию, хотя TLS настраивает автоматически.
        echo "    header Strict-Transport-Security \"max-age=31536000; includeSubDomains\""
        echo "    header X-Content-Type-Options \"nosniff\""
        echo "    header Referrer-Policy \"same-origin\""
        for f in "$dir"/*; do
            [ -e "$f" ] || continue
            name=$(basename "$f")
            path=$(sed -n '1p' "$f")
            body=$(tail -n +2 "$f")
            if [ -z "$path" ]; then
                # default-обработчик откладываем — в Caddy "handle {}" без
                # матчера должен идти ПОСЛЕДНИМ, иначе он перехватит всё
                # и остальные handle-блоки после него не сработают.
                default_body="$body"
                continue
            fi
            echo "    @${name} path ${path}"
            echo "    handle @${name} {"
            printf '%s\n' "$body" | sed 's/^/        /'
            echo "    }"
        done
        if [ -n "$default_body" ]; then
            echo "    handle {"
            printf '%s\n' "$default_body" | sed 's/^/        /'
            echo "    }"
        fi
        echo "}"
    } > "${out}.tmp"
    cat "${out}.tmp" > "$out"
    rm -f "${out}.tmp"

    dk_caddy_reload
}

# =============================================================================
# Общее для OIDC-клиентов Pocket ID (замена Authelia — используется модулями
# Vaultwarden и Forgejo, единственными двумя сервисами, которым реально
# нужен OIDC: не для защиты "от улицы" — снаружи их и так не видно, они
# только во внутренней сети — а чтобы не логиниться в них второй раз
# отдельно от уже пройденного входа в сам хаб).
#
# В отличие от Authelia (правка YAML-файла конфига руками через awk), Pocket
# ID настраивается через свой REST API — проверено по исходникам
# (github.com/pocket-id/pocket-id): создание клиента и его секрета — это
# два обычных HTTP-запроса, авторизованных заголовком "X-API-Key" (ключ
# создаётся один раз вручную в веб-интерфейсе администратора Pocket ID при
# установке, модуль 3, и сохраняется в POCKETID_API_KEY_FILE).
#
# ВАЖНО, чего здесь НЕТ и почему: Pocket ID — чистый OIDC-провайдер, у него
# нет forward_auth (см. пояснение у claim_root_domain выше) — эти две
# функции регистрируют клиента для SSO конкретно Vaultwarden/Forgejo,
# не защищают вообще что-либо ещё.
# =============================================================================

POCKETID_DIR_REF="$APPS_DIR/pocketid"
# POCKETID_URL_REF — адрес контейнера ВНУТРИ docker-сети, видно только
# ДРУГИМ КОНТЕЙНЕРАМ (Caddy, будущий бэкенд хаба). Используется как
# INTERNAL_APP_URL в .env самого Pocket ID (см. 03_pocketid.sh) — это
# значение он сам подставляет в свой well-known/OIDC discovery документ
# как адрес для СЕРВЕР-СЕРВЕР вызовов от других контейнеров (Vaultwarden/
# Forgejo). НЕ ПОДХОДИТ для curl прямо из bash-скриптов deploy_kit — они
# выполняются НА ХОСТЕ, а не внутри контейнера, хостовый curl физически не
# может резолвить имена контейнеров docker-сети (найдено на практике —
# "Could not resolve host: dk_pocketid").
POCKETID_URL_REF="http://dk_pocketid:1411"
# POCKETID_API_BASE_REF — адрес ДЛЯ ХОСТОВЫХ curl-вызовов из самого
# deploy_kit (регистрация OIDC-клиентов и т.п.) — тот же приём, что и у
# beszel_admin_api_base()/notify_send() в остальных модулях: порт
# публикуется на 127.0.0.1 специально для таких проверок с хоста.
POCKETID_API_BASE_REF="http://127.0.0.1:1411"
POCKETID_API_KEY_FILE="$POCKETID_DIR_REF/admin_api_key"

# dk_pocketid_available — Pocket ID установлена и есть сохранённый
# admin-API-ключ (создаётся один раз вручную в модуле 3, шаг настройки).
dk_pocketid_available() {
    [ -s "$POCKETID_API_KEY_FILE" ] && \
        docker ps --format '{{.Names}}' 2>/dev/null | grep -qx dk_pocketid
}

# dk_pocketid_oidc_register_client <client_id_name> <callback_url> <secret_file>
#
# Регистрирует OIDC-клиента через API Pocket ID, либо (если уже
# зарегистрирован ранее — ID сохранён в <secret_file>.id) просто использует
# сохранённые id/секрет. Кладёт "сырой" секрет клиента в <secret_file>
# (chmod 600) — Pocket ID, как и Authelia, отдаёт значение секрета только
# один раз при создании, обратно его не достать.
#
# Требует jq и dk_pocketid_available (проверяется внутри).
# Возвращает 0 при успехе (id/секрет в <secret_file>.id/<secret_file> готовы
# к использованию), 1 — если нужно ручное вмешательство (пояснение уже
# напечатано).
dk_pocketid_oidc_register_client() {
    local client_name="$1" callback_url="$2" secret_file="$3"
    local id_file="${secret_file}.id"

    if ! dk_pocketid_available; then
        echo "${CYAN}[*]${NC} Pocket ID не установлена (или ещё не завершила установку) —"
        echo "    SSO для '$client_name' недоступно."
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        if ! retry_apt "Установка jq (нужен для регистрации OIDC-клиента в Pocket ID)" "apt-get install -y jq"; then
            echo "${RED}[!]${NC} Не удалось установить jq — регистрация OIDC-клиента невозможна."
            return 1
        fi
    fi

    local api_key
    api_key=$(cat "$POCKETID_API_KEY_FILE")

    # Уже зарегистрирован раньше (оба файла на месте) — просто используем
    # сохранённое, ничего не создаём заново.
    if [ -s "$id_file" ] && [ -s "$secret_file" ]; then
        echo "${CYAN}[*]${NC} Клиент '${client_name}' уже зарегистрирован в Pocket ID —"
        echo "    беру сохранённые id/секрет"
        return 0
    fi

    local client_id
    if [ -s "$id_file" ]; then
        # id_file уже есть, а secret_file — нет: клиент был создан раньше,
        # но именно создание СЕКРЕТА тогда сорвалось (например, из-за
        # неверного пути API — было исправлено). Переиспользуем тот же
        # client_id вместо создания дубликата клиента с тем же именем.
        client_id=$(cat "$id_file")
        echo "${CYAN}[*]${NC} Клиент '${client_name}' (id=${client_id}) уже существует в Pocket ID,"
        echo "    секрет не был создан в прошлый раз — пробую снова для этого же клиента"
    else
        local create_payload create_resp
        create_payload=$(jq -n \
            --arg name "$client_name" \
            --arg cb "$callback_url" \
            '{name:$name, callbackURLs:[$cb], isPublic:false, pkceEnabled:true}')

        create_resp=$(curl -fsS -m 15 \
            -H "X-API-Key: ${api_key}" \
            -H "Content-Type: application/json" \
            -d "$create_payload" \
            "${POCKETID_API_BASE_REF}/api/oidc/clients" 2>>"$LOGFILE") || {
            echo "${RED}[!]${NC} Не удалось создать OIDC-клиента '${client_name}' в Pocket ID —"
            echo "    смотрите $LOGFILE"
            return 1
        }
        client_id=$(printf '%s' "$create_resp" | jq -r '.id // empty')
        if [ -z "$client_id" ]; then
            echo "${RED}[!]${NC} Pocket ID не вернула id клиента '${client_name}' — ответ:"
            echo "$create_resp"
            return 1
        fi
        # Сохраняем ID СРАЗУ, не дожидаясь секрета — если секрет не
        # создастся (сеть, версия API и т.п.), при повторном запуске не
        # придётся вручную чистить дубликат в интерфейсе Pocket ID.
        echo "$client_id" > "$id_file"
        chmod 600 "$id_file"
    fi

    local secret_resp secret_value
    secret_resp=$(curl -fsS -m 15 \
        -H "X-API-Key: ${api_key}" \
        -H "Content-Type: application/json" \
        -d '{}' \
        "${POCKETID_API_BASE_REF}/api/oidc/clients/${client_id}/secret" 2>>"$LOGFILE") || {
        echo "${RED}[!]${NC} Клиент '${client_name}' существует (id=${client_id}), но не удалось"
        echo "    создать секрет — смотрите $LOGFILE. id сохранён, при повторном"
        echo "    запуске этого шага дубликат клиента создаваться не будет."
        return 1
    }
    secret_value=$(printf '%s' "$secret_resp" | jq -r '.secret // empty')
    if [ -z "$secret_value" ]; then
        echo "${RED}[!]${NC} Pocket ID не вернула значение секрета — ответ:"
        echo "$secret_resp"
        return 1
    fi

    echo "$secret_value" > "$secret_file"
    chmod 600 "$secret_file"

    echo "${GREEN}[✓]${NC} Клиент '${client_name}' зарегистрирован в Pocket ID (id=${client_id})"
    return 0
}

# =============================================================================
# Общее для NEXUS404 Interface — нашего хаба, замены Homer (используется
# модулем хаба и ВСЕМИ последующими сервис-модулями, у которых есть тайл в
# хабе — отсюда и место здесь, а не в самом модуле хаба).
#
# Тот же принцип, что был у Homer (карточки не хранятся напрямую в итоговом
# файле — он целиком перегенерируется из простого TSV поверх статической
# части), только вместо YAML/config.yml для чужого Homer — свой JSON,
# который читает фронтенд NEXUS404 Interface. add_hub_card не парсит и не
# редактирует JSON на месте — только перечитывает TSV и пишет cards.json
# заново целиком, что надёжно и идемпотентно. Если хаб ещё не установлен
# (HUB_DIR нет) — add_hub_card просто копит данные в TSV и тихо выходит:
# карточка появится сама при первой перегенерации.
#
# Формат карточки шире, чем был у Homer: помимо ссылки для iframe-режима,
# есть поле "mode" (iframe | widget) и "widget", т.к. часть сервисов
# встраивается своей вёрсткой через API (Beszel, Vaultwarden, ntfy), а не
# чужим iframe (см. обсуждение архитектуры).
# =============================================================================

HUB_DIR="$APPS_DIR/nexus404"
HUB_CARDS_FILE="$HUB_DIR/cards.tsv"
HUB_CONFIG_FILE="$HUB_DIR/data/cards.json"

# hub_card_exists <имя> — есть ли уже такая плитка (по ключу "имя")
hub_card_exists() {
    local name="$1"
    [ -f "$HUB_CARDS_FILE" ] || return 1
    awk -F'\t' -v n="$name" '$2==n{f=1} END{exit !f}' "$HUB_CARDS_FILE"
}

# hub_regenerate_config — перечитывает $HUB_CARDS_FILE и полностью
# перезаписывает $HUB_CONFIG_FILE (JSON-массив групп с карточками внутри).
# NEXUS404 Interface — своя статика/бэкенд, конфиг подхватывается при
# обновлении страницы (или через fetch(), если хаб на React/аналоге) — не
# требует перезапуска контейнера. Если хаб ещё не установлен (HUB_DIR
# отсутствует) — тихо выходит, ничего не генерируя.
#
# Требует jq (уже используется в notify_send/dk_pocketid_oidc_register_client,
# так что зависимость не новая для проекта).
hub_regenerate_config() {
    [ -d "$HUB_DIR" ] || return 0
    mkdir -p "$(dirname "$HUB_CONFIG_FILE")"
    local tmp="$HUB_CONFIG_FILE.tmp"

    if [ -s "$HUB_CARDS_FILE" ]; then
        # TSV -> JSON-массив строим руками через awk (не полагаемся на
        # 'jq -R -s' + inputs для построчного чтения — ненадёжная
        # комбинация: -s слурпит весь stdin в одну raw-строку, после чего
        # inputs не читает по строкам так, как можно ожидать). JSON здесь
        # получается уже валидный, jq ниже только группирует.
        local json_array
        json_array=$(awk -F'\t' '
            function esc(s) {
                gsub(/\\/, "\\\\", s)
                gsub(/"/, "\\\"", s)
                return s
            }
            BEGIN { printf "[" }
            {
                if (NR > 1) printf ","
                mode = ($6 == "") ? "iframe" : $6
                printf "{\"group\":\"%s\",\"name\":\"%s\",\"subtitle\":\"%s\",\"url\":\"%s\",\"icon\":\"%s\",\"mode\":\"%s\",\"widget\":\"%s\"}", \
                    esc($1), esc($2), esc($3), esc($4), esc($5), esc(mode), esc($7)
            }
            END { printf "]" }
        ' "$HUB_CARDS_FILE")

        if ! printf '%s' "$json_array" | jq '
            group_by(.group)
            | map({group: .[0].group,
                   items: map({name, subtitle, url, icon, mode, widget})})
        ' > "$tmp" 2>>"$LOGFILE"; then
            echo "${RED}[!]${NC} Не удалось собрать cards.json из $HUB_CARDS_FILE — смотрите $LOGFILE" >&2
            rm -f "$tmp"
            return 1
        fi
    else
        echo "[]" > "$tmp"
    fi
    mv "$tmp" "$HUB_CONFIG_FILE"
}

# add_hub_card <имя> <подзаголовок> <url> [иконка] [группа] [mode=iframe|widget] [widget]
# Идемпотентно: карточка с таким же <имя> (ключ) обновляется на месте (порядок
# сохраняется), новая — добавляется в конец своей группы. Группа по умолчанию —
# "Сервисы", режим по умолчанию — "iframe". Безопасна для вызова до установки
# хаба — данные просто накапливаются, конфиг сгенерируется при первой
# установке.
#
# [mode]   — "iframe" (сервис встраивается своей веб-мордой) или "widget"
#            (хаб рисует свою вёрстку по данным API — Beszel, Vaultwarden,
#            ntfy и оба самописных сервиса).
# [widget] — идентификатор виджета на фронтенде хаба, если mode=widget
#            (например "beszel-metrics", "vaultwarden-meta", "ntfy-feed").
#            Игнорируется при mode=iframe.
add_hub_card() {
    local name="$1" subtitle="$2" url="$3" icon="${4:-}" group="${5:-Сервисы}"
    local mode="${6:-iframe}" widget="${7:-}"

    # табы/переводы строк не ожидаются во входных данных, но не доверяем —
    # заменяем на пробел, чтобы не сломать формат TSV-файла
    name="${name//$'\t'/ }"; name="${name//$'\n'/ }"
    subtitle="${subtitle//$'\t'/ }"; subtitle="${subtitle//$'\n'/ }"
    url="${url//$'\t'/ }"; url="${url//$'\n'/ }"
    icon="${icon//$'\t'/ }"; icon="${icon//$'\n'/ }"
    group="${group//$'\t'/ }"; group="${group//$'\n'/ }"
    mode="${mode//$'\t'/ }"; mode="${mode//$'\n'/ }"
    widget="${widget//$'\t'/ }"; widget="${widget//$'\n'/ }"

    mkdir -p "$HUB_DIR"
    touch "$HUB_CARDS_FILE"

    local new_line tmp
    new_line=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$group" "$name" "$subtitle" "$url" "$icon" "$mode" "$widget")
    tmp="$HUB_CARDS_FILE.tmp"
    awk -F'\t' -v name="$name" -v newline="$new_line" \
        'BEGIN{OFS="\t"; found=0} { if ($2==name) { print newline; found=1 } else { print } } END { if (!found) print newline }' \
        "$HUB_CARDS_FILE" > "$tmp"
    mv "$tmp" "$HUB_CARDS_FILE"

    hub_regenerate_config
}
