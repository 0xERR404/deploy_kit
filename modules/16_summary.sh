#!/bin/bash
# =============================================================================
# 16_summary.sh — итоговая сводка по всем установленным модулям, короткая
# версия. Не модуль пайплайна в обычном смысле — нет своих шагов и
# STATEFILE, ничего не устанавливает и не меняет, только читает уже
# сохранённые файлы каждого модуля и печатает сжато. Безопасно запускать
# в любой момент, сколько угодно раз.
#
# Домен, IP, SSH — печатаются один раз в самом верху (в отличие от вывода
# каждого модуля по отдельности, где это подразумевается в каждом URL).
# Пароли — как и везде в проекте — никогда не печатаются (их и не
# существует в хранимом виде), только логины/адреса/пути к файлам с
# токенами.
#
# Модуль считается установленным, если у него запущен контейнер (docker ps)
# — не установленные пропускаются целиком, а не показываются как "не
# настроено", чтобы не захламлять вывод тем, чего ещё нет.
# =============================================================================

echo "${BOLD}${CYAN}==========================================================================="
echo "  ИТОГОВАЯ СВОДКА ПО ВСЕМ МОДУЛЯМ"
echo "===========================================================================${NC}"
echo ""

dk_installed() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$1"
}

REPORT_SERVER_NAME=$(read_or_default "$SERVERNAMEFILE" "$(hostname 2>/dev/null || echo "-")")
REPORT_USER=$(read_or_default "$USERFILE" "")
REPORT_PORT=$(read_or_default "$PORTFILE" "22")
REPORT_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
REPORT_DOMAIN=$(read_or_default "$DOMAINFILE" "")

echo "  $(pad_field "Название:" "$FIELD_WIDTH")$REPORT_SERVER_NAME"
if [ -n "$REPORT_USER" ]; then
    echo "  $(pad_field "Сервер:" "$FIELD_WIDTH")${REPORT_IP:-?}"
    echo "  $(pad_field "Порт:" "$FIELD_WIDTH")$REPORT_PORT"
    echo "  $(pad_field "Пользователь:" "$FIELD_WIDTH")$REPORT_USER"
    if [ -n "$REPORT_DOMAIN" ]; then
        echo "  $(pad_field "Домен:" "$FIELD_WIDTH")$REPORT_DOMAIN"
    fi
    echo "  $(pad_field "Команда на подключение:" "$FIELD_WIDTH")ssh -p ${REPORT_PORT} ${REPORT_USER}@${REPORT_IP:-?}"
else
    echo "${YELLOW}[?]${NC} Модуль 1 (базовая настройка) ещё не пройден"
    if [ -n "$REPORT_DOMAIN" ]; then
        echo "  $(pad_field "Домен:" "$FIELD_WIDTH")$REPORT_DOMAIN"
    fi
fi
echo ""
echo "${CYAN}---------------------------------------------------------------------------${NC}"
echo ""

FOUND_ANY=0

if dk_installed dk_authelia; then
    FOUND_ANY=1
    AUTH_PORTAL_SAVED=$(read_or_default "$APPS_DIR/authelia/portal_url" "-")
    AUTH_USER_SAVED=$(read_or_default "$APPS_DIR/authelia/admin_user" "-")
    echo "  $(pad_field "Authelia:" "$FIELD_WIDTH")${AUTH_PORTAL_SAVED}"
    echo "  $(pad_field "" "$FIELD_WIDTH")логин: ${AUTH_USER_SAVED}"
    echo ""
fi

if dk_installed dk_ntfy; then
    FOUND_ANY=1
    NTFY_SUB_SAVED=$(read_or_default "$APPS_DIR/ntfy/subdomain" "")
    NTFY_DEV_SAVED=$(read_or_default "$APPS_DIR/ntfy/device_path" "")
    NTFY_USER_SAVED=$(read_or_default "$APPS_DIR/ntfy/admin_user" "-")
    NTFY_TOPIC_SAVED="-"
    [ -f "$NTFY_CONF" ] && NTFY_TOPIC_SAVED=$(grep -oP '^NTFY_TOPIC="\K[^"]+' "$NTFY_CONF" 2>/dev/null)
    if [ -n "$NTFY_SUB_SAVED" ] && NTFY_HOST_SAVED=$(dk_hostname "$NTFY_SUB_SAVED" 2>/dev/null); then
        echo "  $(pad_field "ntfy:" "$FIELD_WIDTH")https://${NTFY_HOST_SAVED}"
        [ -n "$NTFY_DEV_SAVED" ] && echo "  $(pad_field "" "$FIELD_WIDTH")приложение: /${NTFY_DEV_SAVED}"
        echo "  $(pad_field "" "$FIELD_WIDTH")логин: ${NTFY_USER_SAVED}, топик: ${NTFY_TOPIC_SAVED:-?}"
    else
        echo "  $(pad_field "ntfy:" "$FIELD_WIDTH")http://127.0.0.1:2586 (домен не настроен)"
        echo "  $(pad_field "" "$FIELD_WIDTH")логин: ${NTFY_USER_SAVED}"
    fi
    echo ""
fi

if dk_installed dk_beszel; then
    FOUND_ANY=1
    BESZEL_SUB_SAVED=$(read_or_default "$APPS_DIR/beszel/subdomain" "")
    BESZEL_EMAIL_SAVED=$(read_or_default "$APPS_DIR/beszel/admin_email" "-")
    if [ -n "$BESZEL_SUB_SAVED" ] && BESZEL_HOST_SAVED=$(dk_hostname "$BESZEL_SUB_SAVED" 2>/dev/null); then
        echo "  $(pad_field "Beszel:" "$FIELD_WIDTH")https://${BESZEL_HOST_SAVED}"
        echo "  $(pad_field "" "$FIELD_WIDTH")логин: ${BESZEL_EMAIL_SAVED}"
    else
        echo "  $(pad_field "Beszel:" "$FIELD_WIDTH")http://127.0.0.1:8090 (домен не настроен)"
        echo "  $(pad_field "" "$FIELD_WIDTH")логин: ${BESZEL_EMAIL_SAVED}"
    fi
    echo ""
fi

if dk_installed dk_homer; then
    FOUND_ANY=1
    HOMER_MODE_SAVED=$(read_or_default "$APPS_DIR/homer/domain_mode" "subdomain")
    if [ "$HOMER_MODE_SAVED" = "root" ]; then
        HOMER_HOST_SAVED=$(dk_hostname "" 2>/dev/null)
    else
        HOMER_SUB_SAVED=$(read_or_default "$APPS_DIR/homer/subdomain" "home")
        HOMER_HOST_SAVED=$(dk_hostname "$HOMER_SUB_SAVED" 2>/dev/null)
    fi
    if [ -n "$HOMER_HOST_SAVED" ]; then
        echo "  $(pad_field "Homer:" "$FIELD_WIDTH")https://${HOMER_HOST_SAVED}"
    else
        echo "  $(pad_field "Homer:" "$FIELD_WIDTH")http://127.0.0.1:8082 (домен не настроен)"
    fi
    echo ""
fi

if dk_installed dk_vaultwarden; then
    FOUND_ANY=1
    VAULT_SUB_SAVED=$(read_or_default "$APPS_DIR/vaultwarden/subdomain" "")
    VAULT_DEV_SAVED=$(read_or_default "$APPS_DIR/vaultwarden/device_path" "")
    VAULT_LOGIN_NOTE="вход: email+мастер-пароль"
    grep -q 'SSO_ENABLED: "true"' "$APPS_DIR/vaultwarden/docker-compose.yml" 2>/dev/null && VAULT_LOGIN_NOTE="вход: только SSO (Authelia)"
    if [ -n "$VAULT_SUB_SAVED" ] && VAULT_HOST_SAVED=$(dk_hostname "$VAULT_SUB_SAVED" 2>/dev/null); then
        echo "  $(pad_field "Vaultwarden:" "$FIELD_WIDTH")https://${VAULT_HOST_SAVED}"
        [ -n "$VAULT_DEV_SAVED" ] && echo "  $(pad_field "" "$FIELD_WIDTH")приложение: /${VAULT_DEV_SAVED}"
        echo "  $(pad_field "" "$FIELD_WIDTH")${VAULT_LOGIN_NOTE}"
    else
        echo "  $(pad_field "Vaultwarden:" "$FIELD_WIDTH")http://127.0.0.1:8222 (домен не настроен)"
        echo "  $(pad_field "" "$FIELD_WIDTH")${VAULT_LOGIN_NOTE}"
    fi
    echo ""
fi

if dk_installed dk_forgejo; then
    FOUND_ANY=1
    FORGEJO_SUB_SAVED=$(read_or_default "$APPS_DIR/forgejo/subdomain" "")
    FORGEJO_SSH_PORT_SAVED=$(read_or_default "$APPS_DIR/forgejo/ssh_port" "-")
    FORGEJO_ADMIN_SAVED=$(read_or_default "$APPS_DIR/forgejo/admin_user" "-")
    if [ -n "$FORGEJO_SUB_SAVED" ] && FORGEJO_HOST_SAVED=$(dk_hostname "$FORGEJO_SUB_SAVED" 2>/dev/null); then
        echo "  $(pad_field "Forgejo:" "$FIELD_WIDTH")https://${FORGEJO_HOST_SAVED}"
    else
        echo "  $(pad_field "Forgejo:" "$FIELD_WIDTH")http://127.0.0.1:3080 (домен не настроен)"
    fi
    echo "  $(pad_field "" "$FIELD_WIDTH")SSH-порт: ${FORGEJO_SSH_PORT_SAVED}, логин: ${FORGEJO_ADMIN_SAVED}"
    echo ""
fi

if [ "$FOUND_ANY" -eq 0 ]; then
    echo "${CYAN}[*]${NC} Ни один сервис-модуль ещё не установлен — сводка"
    echo "    появится по мере установки"
    echo ""
fi
