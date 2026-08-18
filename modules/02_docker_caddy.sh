#!/bin/bash
# =============================================================================
# Модуль 2: Docker + Docker Compose + Caddy
# (официальный репозиторий Docker, Docker Engine + Compose-плагин, лимит
#  логов контейнеров, добавление sudo-пользователя в группу docker, общая
#  docker-сеть dk_net, установка и запуск Caddy как реверс-прокси для всех
#  последующих сервисов)
#
# Подключается из menu.sh через `source`, common.sh уже загружен.
#
# Именование шагов в STATEFILE: STATEFILE общий на все модули, поэтому
# шаги этого модуля помечаются как "step2_N" (а не "stepN"), чтобы не
# столкнуться с "step1".."step15" из модуля 1. Все последующие модули
# должны придерживаться той же схемы: "step<номер_модуля>_<номер_шага>".
# =============================================================================

enable_full_logging

echo "${BOLD}${CYAN}==========================================================================="
echo "  УСТАНОВКА DOCKER И CADDY"
echo "===========================================================================${NC}"

TOTAL_STEPS=6
DONE_COUNT=$(grep -c '^step2_' "$STATEFILE" 2>/dev/null || true)
DONE_COUNT="${DONE_COUNT:-0}"
if [ "$DONE_COUNT" -gt 0 ] && [ "$DONE_COUNT" -lt "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Найден файл состояния: пройдено $DONE_COUNT из $TOTAL_STEPS шагов модуля, продолжаем"
elif [ "$DONE_COUNT" -ge "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Модуль уже был выполнен ранее (все $TOTAL_STEPS шагов пройдены)"
fi
echo ""

if ! ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 && ! ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
    echo "${YELLOW}[?]${NC} Не вижу интернета — скачивание Docker и образов может не сработать."
    echo "    Проверьте сеть, если следующие шаги начнут падать."
    echo ""
fi

# ================== ШАГ 2_1 ==================
if is_done "step2_1"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 1: Репозиторий Docker"
    echo "===========================================================================${NC}"

    if ! check_disk_space 512; then
        echo "${RED}[!]${NC} Меньше 512 MB свободного места на диске — недостаточно"
        echo "    для установки Docker"
        exit 1
    fi

    retry_apt "Обновление списка пакетов" "apt-get update -y"
    retry_apt "Установка зависимостей (ca-certificates, curl, gnupg)" \
        "apt-get install -y ca-certificates curl gnupg"

    install -m 0755 -d /etc/apt/keyrings

    # Кандидаты на источник Docker apt-репозитория. Первый — официальный,
    # остальные — известные зеркала полного дерева (используются, если
    # download.docker.com отдаёт geo-block через CloudFront — подтверждено
    # на практике: HTTP 403, "CloudFront distribution is configured to
    # block access from your country"). Порядок = порядок перебора.
    DOCKER_MIRRORS=(
        "https://download.docker.com/linux/ubuntu"
        "https://mirror.yandex.ru/mirrors/docker-ce/linux/ubuntu"
        "https://mirror.yandex.ru/mirrors/docker/linux/ubuntu"
        "https://mirrors.aliyun.com/docker-ce/linux/ubuntu"
        "https://mirror.sjtu.edu.cn/docker-ce/linux/ubuntu"
    )

    if [ ! -f /etc/apt/keyrings/docker.asc ]; then
        echo "${CYAN}[*]${NC} Ищу доступный источник Docker apt-репозитория..."
        if DOCKER_APT_BASE=$(pick_working_mirror "/gpg" "${DOCKER_MIRRORS[@]}"); then
            echo "${GREEN}[✓]${NC} Источник доступен: $DOCKER_APT_BASE"
            check_or_fail "загрузка GPG-ключа Docker" \
                curl -fsSL "$DOCKER_APT_BASE/gpg" -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc
            echo "${GREEN}[✓]${NC} GPG-ключ Docker сохранён в /etc/apt/keyrings/docker.asc"
            echo "$DOCKER_APT_BASE" > "$DK_DIR/deploy_kit.dockermirror"
        else
            echo "${RED}[!]${NC} Ни один из ${#DOCKER_MIRRORS[@]} источников Docker"
            echo "    apt-репозитория не отвечает:"
            printf '    %s\n' "${DOCKER_MIRRORS[@]}"
            echo "    Проверьте вручную: curl -v https://download.docker.com/linux/ubuntu/gpg"
            echo "    Если знаете рабочее зеркало для вашего региона —"
            echo "    пришлите, добавлю в список."
            exit 1
        fi
    else
        echo "${CYAN}[*]${NC} GPG-ключ Docker уже присутствует, пропускаю загрузку"
        DOCKER_APT_BASE=$(read_or_default "$DK_DIR/deploy_kit.dockermirror" "${DOCKER_MIRRORS[0]}")
    fi

    ARCH="$(dpkg --print-architecture)"
    CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
    DOCKER_LIST_LINE="deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] ${DOCKER_APT_BASE} ${CODENAME} stable"

    if [ ! -f /etc/apt/sources.list.d/docker.list ] || ! grep -qF "$DOCKER_LIST_LINE" /etc/apt/sources.list.d/docker.list; then
        echo "$DOCKER_LIST_LINE" > /etc/apt/sources.list.d/docker.list
        echo "${GREEN}[✓]${NC} Репозиторий Docker добавлен (${CODENAME}, ${ARCH}, источник: ${DOCKER_APT_BASE})"
    else
        echo "${CYAN}[*]${NC} Репозиторий Docker уже настроен, пропускаю"
    fi

    retry_apt "Обновление списка пакетов после добавления репозитория Docker" "apt-get update -y"

    echo "${GREEN}[✓]${NC} Шаг 1 завершён успешно"
    mark_done "step2_1"
fi

# ================== ШАГ 2_2 ==================
if is_done "step2_2"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 2: Установка Docker Engine и Compose"
    echo "===========================================================================${NC}"

    if ! check_disk_space 1024; then
        echo "${RED}[!]${NC} Меньше 1024 MB свободного места на диске — установка"
        echo "    Docker Engine может не поместиться"
        exit 1
    fi

    retry_apt "Установка Docker Engine, CLI и плагинов" \
        "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

    check_or_fail "включение автозапуска Docker" systemctl enable docker
    run_spinner "Запуск службы Docker" "systemctl restart docker"

    check_or_fail "проверка Docker Engine (docker info)" docker info
    check_or_fail "проверка Docker Compose (плагин)" docker compose version

    DOCKER_V=$(docker --version 2>/dev/null)
    COMPOSE_V=$(docker compose version --short 2>/dev/null)
    echo "${GREEN}[✓]${NC} $DOCKER_V"
    echo "${GREEN}[✓]${NC} Docker Compose (плагин): ${COMPOSE_V}"

    echo "${GREEN}[✓]${NC} Шаг 2 завершён успешно"
    mark_done "step2_2"
fi

# ================== ШАГ 2_3 ==================
if is_done "step2_3"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 3: Настройка Docker (логи, права)"
    echo "===========================================================================${NC}"

    DAEMON_JSON="/etc/docker/daemon.json"
    DAEMON_JSON_CONTENT='{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}'

    mkdir -p /etc/docker

    if [ -f "$DAEMON_JSON" ] && [ "$(cat "$DAEMON_JSON")" != "$DAEMON_JSON_CONTENT" ]; then
        cp "$DAEMON_JSON" "${DAEMON_JSON}.bak.$(date +%s)"
        echo "${CYAN}[*]${NC} Существующий $DAEMON_JSON отличается — сделан бэкап перед перезаписью"
    fi

    if [ ! -f "$DAEMON_JSON" ] || [ "$(cat "$DAEMON_JSON")" != "$DAEMON_JSON_CONTENT" ]; then
        echo "$DAEMON_JSON_CONTENT" > "$DAEMON_JSON"
        run_spinner "Перезапуск Docker с новыми настройками логирования" "systemctl restart docker"
        echo "${GREEN}[✓]${NC} Лимит логов контейнеров настроен: max-size=10m, max-file=3"
    else
        echo "${CYAN}[*]${NC} Настройки логирования Docker уже применены, пропускаю"
    fi

    DK_USER=$(read_or_default "$USERFILE" "")
    if [ -n "$DK_USER" ] && id "$DK_USER" >/dev/null 2>&1; then
        if id -nG "$DK_USER" | grep -qw docker; then
            echo "${CYAN}[*]${NC} Пользователь '$DK_USER' уже в группе docker"
        else
            check_or_fail "добавление '$DK_USER' в группу docker" usermod -aG docker "$DK_USER"
            echo "${GREEN}[✓]${NC} Пользователь '$DK_USER' добавлен в группу docker"
            echo "${YELLOW}[?]${NC} Изменение группы применится после нового логина этого пользователя"
        fi
    else
        echo "${YELLOW}[?]${NC} Sudo-пользователь не найден (файл $USERFILE) —"
        echo "    пропускаю добавление в группу docker"
        echo "    Команды docker без sudo будут доступны только root, пока"
        echo "    пользователь не будет добавлен вручную:"
        echo "    sudo usermod -aG docker <имя_пользователя>"
    fi

    echo "${GREEN}[✓]${NC} Шаг 3 завершён успешно"
    mark_done "step2_3"
fi

# ================== ШАГ 2_4 ==================
if is_done "step2_4"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 4: Общая docker-сеть и базовая структура каталогов"
    echo "===========================================================================${NC}"

    mkdir -p "$APPS_DIR"
    chmod 755 "$APPS_DIR"
    echo "${GREEN}[✓]${NC} Каталог данных сервисов: $APPS_DIR"

    check_or_fail "создание общей docker-сети '$DK_NETWORK'" ensure_dk_network
    echo "${GREEN}[✓]${NC} Docker-сеть '$DK_NETWORK' готова (все сервисы будут подключаться к ней)"

    echo "${GREEN}[✓]${NC} Шаг 4 завершён успешно"
    mark_done "step2_4"
fi

# ================== ШАГ 2_5 ==================
if is_done "step2_5"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 5: Установка и запуск Caddy"
    echo "===========================================================================${NC}"

    CADDY_DIR="$APPS_DIR/caddy"
    mkdir -p "$CADDY_DIR/data" "$CADDY_DIR/config" "$CADDY_DIR/conf.d"

    # Caddyfile не перезаписываем, если уже есть — пользователь мог
    # внести правки (глобальные опции, email для ACME и т.д.)
    if [ ! -f "$CADDY_DIR/Caddyfile" ]; then
        # ВРЕМЕННО (для частых тестовых переустановок на один и тот же
        # домен) — предлагаем staging-сертификаты Let's Encrypt вместо
        # боевых. У staging НЕТ практического лимита (в отличие от
        # боевого — 5 сертификатов на ТОЧНО ТАКОЙ ЖЕ набор доменов за
        # 168 часов, а не "50 в неделю", как ошибочно говорилось раньше в
        # этом же сообщении ниже — see тот же rate-limit, что уже ловили).
        # ВАЖНО: staging-сертификаты НЕ являются доверенными ни для одного
        # настоящего браузера/приложения — у Let's Encrypt staging
        # отдельный тестовый корневой CA специально untrusted. Сайт будет
        # технически поднят и отвечать по HTTPS, но клиенты будут ругаться
        # на сертификат ("не защищено"/"недоверенный ЦС") — это ожидаемо
        # и не баг. Перед реальным использованием переключите обратно на
        # боевые (см. подсказку ниже после выбора).
        CADDY_ACME_CA_LINE=""
        if confirm_yn "Использовать ТЕСТОВЫЕ (staging) сертификаты Let's Encrypt вместо боевых? Полезно при частых переустановках на один домен — у staging нет строгого лимита, но браузеры будут ругаться на сертификат как на недоверенный (это нормально для теста, не для финальной версии)"; then
            CADDY_ACME_CA_LINE="	acme_ca https://acme-staging-v02.api.letsencrypt.org/directory"
            echo "${YELLOW}[?]${NC} Staging-режим включён — сертификат браузеры будут считать"
            echo "    недоверенным, это ожидаемо для теста. Чтобы переключиться на"
            echo "    боевые сертификаты позже: уберите строку 'acme_ca ...' из"
            echo "    $CADDY_DIR/Caddyfile, удалите $CADDY_DIR/data/caddy/certificates"
            echo "    и перезапустите контейнер Caddy (docker compose up -d --force-recreate)."
        fi
        cat > "$CADDY_DIR/Caddyfile" << EOF
{
	# Глобальные опции Caddy. При необходимости добавьте, например:
	# email you@example.com
${CADDY_ACME_CA_LINE}
}

# Единственный внешний вход — хаб NEXUS404 Interface на этом корневом
# домене. У сервисов больше НЕТ своих поддоменов/хостов — все они живут
# только во внутренней docker-сети (dk_net), наружу не видны. Всё, что
# осознанно публикуется под этим доменом (сам хаб, секретный путь
# Vaultwarden, deploy-ссылка, raw-ссылки Forgejo) регистрируется через
# common.sh:claim_root_domain — она сама пересобирает единый файл
# conf.d/_root.caddy. Сюда руками ничего дописывать не нужно.
import conf.d/*.caddy
EOF
        echo "${GREEN}[✓]${NC} Caddyfile создан: $CADDY_DIR/Caddyfile"
        if [ -z "$CADDY_ACME_CA_LINE" ]; then
            echo "${CYAN}[*]${NC} Боевые сертификаты Let's Encrypt (не staging) — учтите лимит"
            echo "    5 сертификатов на ТОЧНО ТАКОЙ ЖЕ набор доменов за 168 часов (неделю)"
            echo "    при частых переустановках на один и тот же домен."
        fi
    else
        echo "${CYAN}[*]${NC} Caddyfile уже существует, не трогаю (возможны ручные правки)"
    fi

    # заглушка, чтобы `import conf.d/*.caddy` не падал на пустом каталоге
    touch "$CADDY_DIR/conf.d/.gitkeep"

    # Caddy существует именно для того, чтобы отдавать HTTPS-сайты — 80 и 443
    # нужны ему всегда (80 — HTTP-01 challenge Let's Encrypt и редирект,
    # 443 — сам HTTPS). Без этого сертификат не выпустится и снаружи
    # ничего не достучится, хотя локально всё выглядит рабочим.
    if command -v ufw >/dev/null 2>&1; then
        check_or_fail "открытие портов 80/443 в ufw" bash -c "ufw allow 80/tcp comment 'Caddy HTTP' && ufw allow 443/tcp comment 'Caddy HTTPS' && ufw allow 443/udp comment 'Caddy HTTP/3'"
        echo "${GREEN}[✓]${NC} Порты 80/443 открыты в ufw"
    else
        echo "${YELLOW}[?]${NC} ufw не найден — откройте 80/443 в своём файрволе вручную"
    fi

    if [ ! -f "$CADDY_DIR/docker-compose.yml" ]; then
        cat > "$CADDY_DIR/docker-compose.yml" << EOF
services:
  caddy:
    image: caddy:2-alpine
    container_name: dk_caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./conf.d:/etc/caddy/conf.d
      - ./data:/data
      - ./config:/config
    networks:
      - ${DK_NETWORK}

networks:
  ${DK_NETWORK}:
    external: true
EOF
        echo "${GREEN}[✓]${NC} docker-compose.yml создан: $CADDY_DIR/docker-compose.yml"
    else
        echo "${CYAN}[*]${NC} docker-compose.yml уже существует, не трогаю"
    fi

    # -----------------------------------------------------------------------
    # Базовый (корневой) домен. NEXUS404 Interface рассчитан на домен (без
    # него нет HTTPS через Let's Encrypt и телефон не достучится откуда
    # угодно) — но выбор оставлен: можно продолжить и без домена, если
    # план — работать только по IP (например хаб не должен быть доступен
    # из открытого интернета вообще). Если домена нет — DOMAINFILE не
    # создаётся, дальнейшие модули должны сами решать вопрос адресации
    # через dk_hostname (вернёт 1, если домена нет).
    # -----------------------------------------------------------------------
    EXISTING_DOMAIN=$(read_or_default "$DOMAINFILE" "")
    if [ -n "$EXISTING_DOMAIN" ]; then
        echo "${CYAN}[*]${NC} Домен уже настроен: $EXISTING_DOMAIN"
    else
        DK_HAS_DOMAIN=""
        while true; do
            if ! read -rp "${YELLOW}[?]${NC} Есть домен, который можно направить на этот сервер (y/n): " DK_HAS_DOMAIN_ANS; then
                echo ""
                echo "${RED}[!]${NC} Не удалось прочитать ввод (нет доступа к терминалу/stdin)."
                exit 1
            fi
            case "$DK_HAS_DOMAIN_ANS" in
                y|Y) DK_HAS_DOMAIN="yes"; break ;;
                n|N) DK_HAS_DOMAIN="no"; break ;;
                *) echo "${RED}[!]${NC} Введите 'y' или 'n'" ;;
            esac
        done

        if [ "$DK_HAS_DOMAIN" = "no" ]; then
            echo "${CYAN}[*]${NC} Домен не настраиваю, пропускаю (при необходимости —"
            echo "    запустите этот шаг заново после подключения домена)"
            echo "${YELLOW}[?]${NC} Без домена у NEXUS404 Interface не будет HTTPS-адреса,"
            echo "    доступного откуда угодно — хаб будет виден только по IP:порту"
            echo "    внутри вашей сети (или через VPN)."
        else
            # Простая проверка формата (буквы/цифры/дефис, минимум одна точка,
            # без протокола и без завершающего слэша) — защита от опечаток
            # вроде "https://example.com/" до того, как это попадёт в Caddy.
            DOMAIN_RE='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$'
            while true; do
                if ! read -rp "Введите домен (например nexus404.com, без http:// и слэшей): " DK_DOMAIN_INPUT; then
                    echo ""
                    echo "${RED}[!]${NC} Не удалось прочитать ввод (нет доступа к терминалу/stdin)."
                    exit 1
                fi
                if [[ "$DK_DOMAIN_INPUT" =~ $DOMAIN_RE ]]; then
                    break
                fi
                echo "${RED}[!]${NC} Похоже на некорректный домен, попробуйте ещё раз (пример: example.com)"
            done

            echo "$DK_DOMAIN_INPUT" > "$DOMAINFILE"
            chmod 644 "$DOMAINFILE"
            echo "${GREEN}[✓]${NC} Домен сохранён: $DK_DOMAIN_INPUT (файл $DOMAINFILE)"
        fi
    fi

    run_spinner "Запуск Caddy" "dk_compose_up '$CADDY_DIR'"

    echo "${GREEN}[✓]${NC} Шаг 5 завершён успешно"
    mark_done "step2_5"
fi

# ================== ШАГ 2_6 ==================
if is_done "step2_6"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 6: Финальная проверка"
    echo "===========================================================================${NC}"
    echo "${CYAN}[*]${NC} Проверяю, что все предыдущие шаги реально применились..."
    echo ""

    CHECK_FAILED=0
    echo "===== Результаты финальной проверки модуля 2 ($(date '+%Y-%m-%d %H:%M:%S')) =====" >> "$LOGFILE"

    check_item "Docker Engine запущен" systemctl is-active --quiet docker
    check_item "Docker включён в автозагрузку" systemctl is-enabled --quiet docker
    check_item "Docker Compose (плагин) доступен" docker compose version
    check_item "Лимит логов контейнеров настроен" test -f /etc/docker/daemon.json
    check_item "Docker-сеть '$DK_NETWORK' создана" docker network inspect "$DK_NETWORK"
    check_item "Контейнер Caddy запущен" bash -c "docker ps --format '{{.Names}}' | grep -qx dk_caddy"
    check_item "Порт 80 слушает" bash -c "ss -tln | grep -q ':80 '"
    check_item "Порт 443 (TCP) слушает" bash -c "ss -tln | grep -q ':443 '"
    if command -v ufw >/dev/null 2>&1; then
        check_item "Порты 80/443 разрешены в ufw" bash -c "ufw status | grep -q '^80.*ALLOW' && ufw status | grep -q '^443.*ALLOW'"
    fi

    echo ""
    if [ "$CHECK_FAILED" -eq 0 ]; then
        echo "${GREEN}[✓]${NC} Все проверки пройдены успешно"
    else
        echo "${RED}[!]${NC} Проверок с ошибкой: $CHECK_FAILED — просмотрите список"
        echo "    выше, что-то могло не примениться"
    fi

    echo "${GREEN}[✓]${NC} Шаг 6 завершён успешно"
    mark_done "step2_6"
fi

echo ""
echo "${BOLD}${CYAN}==========================================================================="
echo "  Docker + Docker Compose + Caddy настроены — сохраните эту информацию."
echo "===========================================================================${NC}"
echo "$(pad_field "Каталог Caddy:" "$FIELD_WIDTH")$APPS_DIR/caddy"
echo "$(pad_field "Конфиги сервисов:" "$FIELD_WIDTH")$APPS_DIR/caddy/conf.d/*.caddy"
echo "$(pad_field "Общая docker-сеть:" "$FIELD_WIDTH")$DK_NETWORK"
echo "$(pad_field "Базовый домен:" "$FIELD_WIDTH")$(read_or_default "$DOMAINFILE" "не настроен")"
echo ""
