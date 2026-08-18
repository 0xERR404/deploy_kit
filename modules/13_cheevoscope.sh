#!/bin/bash
# =============================================================================
# Cheevoscope — статистика игровой библиотеки (Steam + RetroAchievements).
# Раньше был отдельным контейнером (клон github.com/0xERR404/cheevoscope,
# requests/python-dotenv), теперь перенесён прямо в хаб на чистом stdlib —
# тот же принцип, что WalletScope/MemoScope (см. 04_nexus404.sh: cheevo_*
# функции). Этот модуль — только сбор ключей Steam/RA и карточка в хабе,
# без единого docker-compose/git clone.
#
# STATEFILE: "step13_N".
# =============================================================================

enable_full_logging

echo "${BOLD}${CYAN}==========================================================================="
echo "  НАСТРОЙКА ИГРОВОЙ СТАТИСТИКИ (CHEEVOSCOPE)"
echo "===========================================================================${NC}"

TOTAL_STEPS=2
DONE_COUNT=$(grep -c '^step13_' "$STATEFILE" 2>/dev/null || true)
DONE_COUNT="${DONE_COUNT:-0}"
if [ "$DONE_COUNT" -gt 0 ] && [ "$DONE_COUNT" -lt "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Найден файл состояния: пройдено $DONE_COUNT из $TOTAL_STEPS шагов модуля, продолжаем"
elif [ "$DONE_COUNT" -ge "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Модуль уже был выполнен ранее (все $TOTAL_STEPS шага пройдены)"
fi
echo ""

if ! [ -d "$HUB_DIR" ]; then
    echo "${RED}[!]${NC} Хаб (NEXUS404 Interface) не установлен — сначала пройдите пункт 4 меню"
    exit 1
fi

# Хаб сам читает эти файлы (см. CHEEVO_STEAM_API_KEY_FILE и т.п. в
# 04_nexus404.sh) — путь совпадает с volume хаба "./data:/app/data"
# (см. docker-compose.yml хаба), поэтому пишем прямо в $HUB_DIR/data.
CHEEVO_DATA_DIR="$HUB_DIR/data"
CHEEVO_STEAM_KEY_FILE="$CHEEVO_DATA_DIR/cheevoscope_steam_api_key.txt"
CHEEVO_STEAM_ID_FILE="$CHEEVO_DATA_DIR/cheevoscope_steam_id.txt"
CHEEVO_RA_USER_FILE="$CHEEVO_DATA_DIR/cheevoscope_ra_username.txt"
CHEEVO_RA_KEY_FILE="$CHEEVO_DATA_DIR/cheevoscope_ra_api_key.txt"

mkdir -p "$CHEEVO_DATA_DIR"

# ================== ШАГ 1 ==================
if is_done "step13_1"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 1: Учётные данные Steam / RetroAchievements"
    echo "===========================================================================${NC}"

    if [ -s "$CHEEVO_STEAM_KEY_FILE" ] && [ -s "$CHEEVO_STEAM_ID_FILE" ]; then
        echo "${CYAN}[*]${NC} Steam API key/SteamID уже заданы ранее, пропускаю"
    else
        echo "${CYAN}[*]${NC} Steam API key — https://steamcommunity.com/dev/apikey"
        read -rp "${YELLOW}[?]${NC} STEAM_API_KEY: " CHEEVO_STEAM_KEY_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
        if [ -z "$CHEEVO_STEAM_KEY_INPUT" ]; then
            echo "${RED}[!]${NC} STEAM_API_KEY не может быть пустым — без него виджет не работает."
            exit 1
        fi
        echo "$CHEEVO_STEAM_KEY_INPUT" > "$CHEEVO_STEAM_KEY_FILE"
        chmod 600 "$CHEEVO_STEAM_KEY_FILE"

        echo "${CYAN}[*]${NC} SteamID64 (17 цифр) — https://steamid.io/"
        read -rp "${YELLOW}[?]${NC} STEAM_ID: " CHEEVO_STEAM_ID_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
        if ! [[ "$CHEEVO_STEAM_ID_INPUT" =~ ^[0-9]{17}$ ]]; then
            echo "${RED}[!]${NC} SteamID64 должен состоять ровно из 17 цифр — проверьте на steamid.io"
            exit 1
        fi
        echo "$CHEEVO_STEAM_ID_INPUT" > "$CHEEVO_STEAM_ID_FILE"
        chmod 600 "$CHEEVO_STEAM_ID_FILE"
        echo "${GREEN}[✓]${NC} Steam API key/SteamID сохранены"
    fi

    if [ -s "$CHEEVO_RA_USER_FILE" ] && [ -s "$CHEEVO_RA_KEY_FILE" ]; then
        echo "${CYAN}[*]${NC} RetroAchievements уже настроен ранее, пропускаю"
    elif confirm_yn "Настроить вкладку RetroAchievements? (необязательно — без неё виджет работает, вкладка просто пустая)"; then
        read -rp "${YELLOW}[?]${NC} RA_USERNAME (логин на retroachievements.org): " CHEEVO_RA_USER_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
        read -rp "${YELLOW}[?]${NC} RA_API_KEY (retroachievements.org → Settings → Keys): " CHEEVO_RA_KEY_INPUT || { echo "${RED}[!]${NC} Не удалось прочитать ввод"; exit 1; }
        if [ -z "$CHEEVO_RA_USER_INPUT" ] || [ -z "$CHEEVO_RA_KEY_INPUT" ]; then
            echo "${YELLOW}[?]${NC} Одно из полей пустое — RetroAchievements пропущен, вкладка будет пустой."
        else
            echo "$CHEEVO_RA_USER_INPUT" > "$CHEEVO_RA_USER_FILE"
            chmod 600 "$CHEEVO_RA_USER_FILE"
            echo "$CHEEVO_RA_KEY_INPUT" > "$CHEEVO_RA_KEY_FILE"
            chmod 600 "$CHEEVO_RA_KEY_FILE"
            echo "${GREEN}[✓]${NC} RetroAchievements сохранён"
        fi
    else
        echo "${CYAN}[*]${NC} Пропущено — вкладка RetroAchievements будет пустой. Добавить позже:"
        echo "    запустите этот пункт меню заново после удаления строки 'step13_1'"
        echo "    из $STATEFILE."
    fi

    echo "${GREEN}[✓]${NC} Шаг 1 завершён успешно"
    mark_done "step13_1"
fi

# ================== ШАГ 2 ==================
if is_done "step13_2"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 2: Карточка в хабе"
    echo "===========================================================================${NC}"

    add_hub_card "Cheevoscope" "Игровая статистика" "" "fas fa-trophy" "Сервисы" "widget" "cheevoscope-stats"
    echo "${GREEN}[✓]${NC} Карточка в хабе добавлена"

    echo "${CYAN}[*]${NC} Перезапускаю хаб, чтобы подхватить новые ключи..."
    if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -qx dk_nexus404; then
        docker restart dk_nexus404 >/dev/null 2>>"$LOGFILE" || echo "${YELLOW}[?]${NC} Не удалось перезапустить dk_nexus404 автоматически — перезапустите вручную: docker restart dk_nexus404"
    fi

    echo ""
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  CHEEVOSCOPE НАСТРОЕН"
    echo "===========================================================================${NC}"
    echo "Откройте хаб → карточка Cheevoscope → «обновить всё» — подтянет"
    echo "список игр, достижения, картинки и цены. Дальше — раз в час хаб сам"
    echo "тихо проверяет новые достижения в фоне (без цен/отзывов/картинок —"
    echo "для этого по-прежнему нужна кнопка «обновить всё» вручную)."

    echo "${GREEN}[✓]${NC} Шаг 2 завершён успешно"
    mark_done "step13_2"
fi
