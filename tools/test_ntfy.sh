#!/bin/bash
# =============================================================================
# tools/test_ntfy.sh — сквозная проверка всех хуков ntfy без ожидания
# реальных событий. Не модуль пайплайна, не добавлен в меню — запускается
# вручную, когда нужно проверить, что push реально доходит по каждому каналу.
#
# Запуск: sudo bash /var/lib/deploy_kit/tools/test_ntfy.sh
# =============================================================================

DK_DIR="/var/lib/deploy_kit"
# shellcheck source=/dev/null
source "$DK_DIR/common.sh"

if [ "$(id -u)" -ne 0 ]; then
    echo "${RED}[!]${NC} Запускать нужно от root (sudo)"
    exit 1
fi

echo "${BOLD}${CYAN}==========================================================================="
echo "  ПРОВЕРКА NTFY — ВСЕ ХУКИ ПОДРЯД"
echo "===========================================================================${NC}"
echo "${CYAN}[*]${NC} Отправит несколько тестовых уведомлений одно за другим."
echo "${CYAN}[*]${NC} SSH-вход не подделать — зайдите на сервер новой сессией отдельно."
echo ""

run_check() {
    local desc="$1"
    shift
    if [ ! -x "$1" ] && ! command -v "$1" >/dev/null 2>&1; then
        echo "${YELLOW}[?]${NC} $desc — пропущено, скрипт не найден (модуль 4 ntfy не завершён?)"
        echo ""
        return
    fi
    echo "${CYAN}[*]${NC} $desc..."
    if "$@"; then
        echo "${GREEN}[✓]${NC} $desc — выполнено"
    else
        echo "${YELLOW}[?]${NC} $desc — вернул ошибку, см. $NTFYLOG"
    fi
    echo ""
}

run_check "Базовая проверка notify_send" \
    notify_send "manual_test" "Тест: notify_send" "Ручной вызов, всё работает" 3 "tada"

run_check "Имитация бана fail2ban" \
    /usr/local/bin/deploy_kit_notify_ban.sh "203.0.113.99" "sshd" "5"

run_check "Уведомление об автообновлениях (тихо, если сегодня апдейтов не было)" \
    /usr/local/bin/deploy_kit_notify_updates.sh

run_check "Автоочистка (реальная — apt autoremove/autoclean)" \
    /usr/local/bin/deploy_kit_notify_cleanup.sh

run_check "Уведомление о перезагрузке (без реальной перезагрузки)" \
    /usr/local/bin/deploy_kit_notify_boot.sh

run_check "Health-check + уведомление" \
    bash -c '/usr/local/bin/deploy_kit_healthcheck.sh && /usr/local/bin/deploy_kit_notify_healthcheck.sh'

echo "${BOLD}${CYAN}=== Последние строки лога уведомлений ($NTFYLOG) ===${NC}"
tail -n 10 "$NTFYLOG" 2>/dev/null || echo "${YELLOW}[?]${NC} Лог пуст или не найден"
