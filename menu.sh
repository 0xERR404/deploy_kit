#!/bin/bash
# =============================================================================
# menu.sh — главное меню.
#
# Как это работает:
#   1. Здесь подключается common.sh — общие переменные, цвета, проверки
#      root/OS и все хелпер-функции (is_done, run_spinner и т.д.) —
#      раньше они были в начале setup.sh. Теперь они в одном месте и
#      доступны любому модулю.
#   2. Модули лежат в ./modules/ и просто подключаются через `source`,
#      поэтому используют общие функции/переменные напрямую, без повторного
#      объявления и без запуска в отдельном процессе.
#   3. После завершения модуля управление возвращается в меню.
#
# Чтобы добавить пункт меню:
#   - положить новый скрипт в modules/NN_name.sh (используя переменные и
#     функции из common.sh — можно смотреть на 01_base_setup.sh как на пример)
#   - добавить строку в массив MENU_ITEMS ниже
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# -----------------------------------------------------------------------
# Синхронизация репозитория в основную рабочую папку ($DK_DIR, создаётся
# в common.sh — сейчас это /var/lib/deploy_kit). Так все скрипты (меню,
# common.sh, модули) оседают в одном постоянном месте на сервере, вне
# зависимости от того, откуда именно был запущен menu.sh.
# -----------------------------------------------------------------------
sync_self_to_dk_dir() {
    local dst="$DK_DIR"
    [ "$SCRIPT_DIR" = "$dst" ] && return 0

    mkdir -p "$dst/modules" "$dst/tools"
    cp -f "$SCRIPT_DIR/menu.sh" "$dst/menu.sh"
    cp -f "$SCRIPT_DIR/common.sh" "$dst/common.sh"
    cp -f "$MODULES_DIR"/*.sh "$dst/modules/" 2>/dev/null || true
    cp -f "$SCRIPT_DIR/tools"/*.sh "$dst/tools/" 2>/dev/null || true
    chmod +x "$dst/menu.sh" "$dst/common.sh" "$dst"/modules/*.sh "$dst"/tools/*.sh 2>/dev/null || true
}
sync_self_to_dk_dir

# -----------------------------------------------------------------------
# Реестр пунктов меню: "Название|путь_к_файлу_модуля"
# Порядок в массиве = порядок в меню.
# -----------------------------------------------------------------------
MENU_ITEMS=(
    "Базовая настройка сервера|$MODULES_DIR/01_base_setup.sh"
    "Docker + Docker Compose + Caddy|$MODULES_DIR/02_docker_caddy.sh"
    "Pocket ID (аутентификация, единый вход)|$MODULES_DIR/03_pocketid.sh"
    "NEXUS404 Hub (хаб)|$MODULES_DIR/04_nexus404.sh"
    "ntfy (пуш-уведомления)|$MODULES_DIR/05_ntfy.sh"
    "Beszel (мониторинг ресурсов)|$MODULES_DIR/06_beszel.sh"
    "Vaultwarden (менеджер паролей)|$MODULES_DIR/07_vaultwarden.sh"
    "Forgejo (git-сервер)|$MODULES_DIR/08_forgejo.sh"
    "Vikunja (задачи) — в разработке|$MODULES_DIR/_planned.sh"
    "Navidrome (музыка) — в разработке|$MODULES_DIR/_planned.sh"
    "Syncthing (синхронизация файлов) — в разработке|$MODULES_DIR/_planned.sh"
    "Remnawave (VPN-панель) — в разработке|$MODULES_DIR/_planned.sh"
    "Cheevoscope (игровая статистика)|$MODULES_DIR/13_cheevoscope.sh"
    "WalletScope (учёт финансов)|$MODULES_DIR/14_walletscope.sh"
    "MemoScope (заметки)|$MODULES_DIR/15_memoscope.sh"
    "Итоговая сводка по всем модулям|$MODULES_DIR/16_summary.sh"
)

print_menu() {
    clear
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  DEPLOY KIT"
    echo "===========================================================================${NC}"
    local i=1
    for item in "${MENU_ITEMS[@]}"; do
        local title="${item%%|*}"
        echo "  ${GREEN}${i})${NC} $title"
        i=$((i + 1))
    done
    echo "  ${YELLOW}u)${NC} Обновить (сбросить прогресс — применить новую версию deploy_kit"
    echo "     к уже установленному серверу, без переустановки с нуля)"
    echo "  ${YELLOW}0)${NC} Выход"
    echo "${BOLD}${CYAN}===========================================================================${NC}"
}

# Сбрасывает STATEFILE (с бэкапом рядом) — все шаги всех модулей снова
# считаются НЕ пройденными, поэтому при следующем заходе в любой пункт
# меню он пройдёт заново. Это НЕ переустановка с нуля: почти каждый шаг
# уже проверяет реальное состояние на диске/в контейнере (существует ли
# секрет/токен/файл), а не только отметку в STATEFILE — так что заново
# создавать пароли/токены/данные он не станет, просто перезапишет
# статичный контент (docker-compose.yml, код хаба и т.п.) под актуальную
# версию скрипта и досоздаст то, чего раньше не было (новые шаги/модули).
dk_reset_progress() {
    if [ ! -s "$STATEFILE" ]; then
        echo "${CYAN}[*]${NC} STATEFILE пуст или не существует — сбрасывать нечего"
        return 0
    fi
    local backup="${STATEFILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$STATEFILE" "$backup"
    : > "$STATEFILE"
    echo "${GREEN}[✓]${NC} Прогресс сброшен (бэкап: $backup)"
    echo "${CYAN}[*]${NC} Пройдите нужные пункты меню заново — большинство шагов не будут"
    echo "    пересоздавать то, что уже есть (проверяют реальное состояние на"
    echo "    диске), просто обновят код/конфиги под текущую версию скрипта."
}

run_module() {
    local module_path="$1"
    local module_title="${2:-}"
    if [ ! -f "$module_path" ]; then
        echo "${RED}[!]${NC} Файл модуля не найден: $module_path"
        pause_step
        return 1
    fi

    echo ""
    # Выполняем в субшелле: модуль получает уже загруженные переменные и
    # функции из common.sh (source), но "set -e" и exit-ы внутри модуля
    # не затрагивают сам процесс меню — при ошибке вернёмся в меню, а не
    # закроем терминал.
    # "set +u" отключает строгую проверку необъявленных переменных именно
    # для модуля: в оригинальном скрипте её не было, и модули читают
    # переменные окружения (SSH_CONNECTION, SUDO_USER и т.п.), которые
    # не всегда заданы — без "+u" это ломало бы модуль ложной ошибкой.
    #
    # PLANNED_NAME — только для общей заглушки _planned.sh (см. файл):
    # у неё нет своего названия внутри, читает его отсюда, из заголовка
    # пункта меню. Для обычных модулей просто не используется никем.
    (
        set +u
        set -e
        PLANNED_NAME="${module_title% — в разработке}"
        source "$module_path"
    )
    local status=$?

    echo ""
    if [ "$status" -eq 0 ]; then
        echo "${GREEN}[✓]${NC} Модуль завершён, возвращаюсь в меню"
    else
        echo "${RED}[!]${NC} Модуль завершился с ошибкой (код $status)"
    fi
    pause_step
}

main() {
    while true; do
        print_menu
        if ! read -rp "Выберите пункт меню: " choice; then
            echo ""
            echo "${RED}[!]${NC} Не удалось прочитать ввод (нет доступа к терминалу/stdin)."
            echo "    Запускайте скрипт напрямую в интерактивном терминале, не через"
            echo "    пайп без TTY."
            exit 1
        fi

        if [ "$choice" == "0" ]; then
            echo "${CYAN}[*]${NC} Выход."
            exit 0
        fi

        if [ "$choice" == "u" ] || [ "$choice" == "U" ]; then
            echo ""
            echo "${YELLOW}[?]${NC} Это сбросит отметки о пройденных шагах у ВСЕХ модулей (с бэкапом"
            echo "    STATEFILE рядом) — при следующем заходе в пункт меню он пройдёт"
            echo "    заново. Существующие секреты/пароли/данные почти всегда НЕ"
            echo "    пересоздаются (шаги проверяют реальное состояние на диске), но"
            echo "    точечных отличий по каждому конкретному модулю гарантировать нельзя."
            if confirm_yn "Продолжить?"; then
                dk_reset_progress
            else
                echo "${CYAN}[*]${NC} Отменено"
            fi
            pause_step
            continue
        fi

        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#MENU_ITEMS[@]}" ]; then
            echo "${RED}[!]${NC} Некорректный выбор"
            pause_step
            continue
        fi

        local selected="${MENU_ITEMS[$((choice - 1))]}"
        local module_title="${selected%%|*}"
        local module_path="${selected#*|}"
        run_module "$module_path" "$module_title"
    done
}

main
