#!/bin/bash
# =============================================================================
# Cheevoscope — статистика игровой библиотеки (Steam + RetroAchievements).
# Раньше был отдельным контейнером (клон github.com/0xERR404/cheevoscope,
# requests/python-dotenv), теперь перенесён прямо в хаб на чистом stdlib —
# тот же принцип, что WalletScope/MemoScope, отдельным файлом
# backend/cheevoscope.py (не одним большим app.py — см. общее обсуждение
# архитектуры в 04_nexus404.sh). Этот модуль — сбор ключей Steam/RA, код
# виджета и карточка в хабе, без единого docker-compose/git clone.
#
# STATEFILE: "step13_N".
# =============================================================================

enable_full_logging

echo "${BOLD}${CYAN}==========================================================================="
echo "  НАСТРОЙКА ИГРОВОЙ СТАТИСТИКИ (CHEEVOSCOPE)"
echo "===========================================================================${NC}"

TOTAL_STEPS=3
DONE_COUNT=$(grep -c '^step13_' "$STATEFILE" 2>/dev/null || true)
DONE_COUNT="${DONE_COUNT:-0}"
if [ "$DONE_COUNT" -gt 0 ] && [ "$DONE_COUNT" -lt "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Найден файл состояния: пройдено $DONE_COUNT из $TOTAL_STEPS шагов модуля, продолжаем"
elif [ "$DONE_COUNT" -ge "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Модуль уже был выполнен ранее (все $TOTAL_STEPS шага пройдены)"
fi
echo ""

if ! [ -d "$HUB_DIR" ]; then
    echo "${RED}[!]${NC} Хаб (NEXUS404 Hub) не установлен — сначала пройдите пункт 4 меню"
    exit 1
fi

# Хаб сам читает эти файлы (см. CHEEVO_STEAM_API_KEY_FILE и т.п. в
# backend/cheevoscope.py) — путь совпадает с volume хаба "./data:/app/data"
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
    echo "  ШАГ 2: Код виджета"
    echo "===========================================================================${NC}"

    mkdir -p "$HUB_DIR/backend"
    cat > "$HUB_DIR/backend/cheevoscope.py" << 'CHEEVOSCOPE_PYEOF'
"""cheevoscope.py — статистика игровой библиотеки (Steam + RetroAchievements).
Изначально отдельный проект (github.com/0xERR404/cheevoscope), перенесён
целиком в хаб на чистом stdlib (urllib вместо requests, файлы секретов
вместо .env) — тот же принцип, что WalletScope/MemoScope. Живёт в том же
процессе/контейнере, что и сам хаб (app.py), отдельным файлом для
читаемости — единственный тут действительно крупный модуль (это раньше
был целый отдельный проект, не просто "ещё один маленький виджет")."""
import json
import os
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone

from _shared import read_file

# ============================================================
# CHEEVOSCOPE — статистика игровой библиотеки (Steam + RetroAchievements).
# Раньше жил отдельным контейнером (клон github.com/0xERR404/cheevoscope,
# requests/python-dotenv), теперь перенесён прямо в хаб на чистом stdlib —
# тот же принцип, что WalletScope/MemoScope (см. заголовок файла). Вся
# бизнес-логика (Steam/RA API, кэш, подсчёт статистики) перенесена как
# есть, поменялся только транспорт (requests -> urllib) и конфигурация
# (.env -> файлы секретов, как у остальных сервисов).
CHEEVO_STEAM_API_KEY_FILE = "/app/data/cheevoscope_steam_api_key.txt"
CHEEVO_STEAM_ID_FILE = "/app/data/cheevoscope_steam_id.txt"
CHEEVO_RA_USERNAME_FILE = "/app/data/cheevoscope_ra_username.txt"
CHEEVO_RA_API_KEY_FILE = "/app/data/cheevoscope_ra_api_key.txt"

CHEEVO_CACHE_DIR = "/app/data/cheevoscope_cache"
CHEEVO_IMAGES_DIR = "/app/data/cheevoscope_images"

CHEEVO_GAMES_LIST_FILE = "/app/data/cheevoscope_games_list.json"
CHEEVO_IMAGES_FILE = "/app/data/cheevoscope_images.json"
CHEEVO_ACHIEVEMENTS_STATS_FILE = "/app/data/cheevoscope_achievements_stats.json"
CHEEVO_LIBRARY_COST_FILE = "/app/data/cheevoscope_library_cost.json"
CHEEVO_REVIEWS_FILE = "/app/data/cheevoscope_reviews.json"
CHEEVO_REPORT_JSON_FILE = "/app/data/cheevoscope_report.json"
CHEEVO_STATUS_FILE = "/app/data/cheevoscope_status.json"
CHEEVO_RETRO_REPORT_JSON_FILE = "/app/data/cheevoscope_retro_report.json"
CHEEVO_RETRO_STATUS_FILE = "/app/data/cheevoscope_retro_status.json"
CHEEVO_MANUAL_APPIDS_FILE = "/app/data/cheevoscope_manual_appids.json"

# Пауза между запросами к Steam API (сек) — общий throttle на весь процесс,
# соблюдается даже при параллельных запросах (см. CheevoRateLimiter).
# Разгонялось поэтапно: 0.25с/10 (оригинал) -> 0.05с/20 (спорно, откатили
# из осторожности) -> 0.1с/12 -> теперь по максимуму. Более ранняя проблема
# "обновление не проходит" оказалась НЕ в скорости запросов, а в двух
# отдельных багах (файлы не перезаписывались при переустановке, docker
# compose up не подхватывал изменения без force-recreate) — оба найдены
# и исправлены позже в той же сессии, так что бояться скорости запросов
# самой по себе больше не нужно. Retry с экспоненциальной паузой на
# 429/5xx (см. _cheevo_get_with_retry) страхует, если Steam всё же
# притормозит — просто чуть медленнее для конкретной игры, не падение
# всего обновления.
CHEEVO_REQUEST_DELAY = 0.02
CHEEVO_API_CONCURRENCY = 30
# Витрина store.steampowered.com — отдельный, гораздо более жёсткий лимит
# (~200 запросов/5 минут), поэтому темп и параллелизм ниже.
CHEEVO_STORE_REQUEST_DELAY = 0.8
CHEEVO_STORE_CONCURRENCY = 5

CHEEVO_CACHE_TTL_HOURS = 24 * 7
CHEEVO_NO_ACHIEVEMENTS_CACHE_TTL_HOURS = 24 * 30
CHEEVO_COMPLETED_ACHIEVEMENTS_CACHE_TTL_HOURS = 24 * 7
CHEEVO_ACHIEVEMENT_SCHEMA_CACHE_TTL_HOURS = 24 * 30
CHEEVO_RETRO_NO_PROGRESS_CACHE_TTL_HOURS = 24 * 30
CHEEVO_RETRO_MASTERED_CACHE_TTL_HOURS = 24 * 7

# RetroAchievements API — ускоряем умеренно (в 2 раза), не так агрессивно,
# как основной Steam API выше: у RA репутация более строгих лимитов в
# сообществе (вплоть до временных банов IP при злоупотреблении), и в
# отличие от Steam здесь нет официально задокументированного дневного
# бюджета запросов, на который можно было бы ориентироваться.
CHEEVO_RA_REQUEST_DELAY = 0.25
CHEEVO_RA_CONCURRENCY = 5


# ============================================================
# CHEEVOSCOPE — нативный перенос (requests -> urllib, .env -> файлы секретов).
# Бизнес-логика 1:1 с github.com/0xERR404/cheevoscope, поменялся только
# транспорт и способ конфигурации.
# ============================================================

def _cheevo_steam_api_key():
    return read_file(CHEEVO_STEAM_API_KEY_FILE) or ""


def _cheevo_steam_id():
    return read_file(CHEEVO_STEAM_ID_FILE) or ""


def _cheevo_ra_username():
    return read_file(CHEEVO_RA_USERNAME_FILE) or ""


def _cheevo_ra_api_key():
    return read_file(CHEEVO_RA_API_KEY_FILE) or ""


def cheevo_validate_config():
    missing = []
    if not _cheevo_steam_api_key():
        missing.append("STEAM_API_KEY")
    if not _cheevo_steam_id():
        missing.append("STEAM_ID")
    if missing:
        raise RuntimeError(f"Не заданы: {', '.join(missing)} — пройдите шаг 1 модуля Cheevoscope в меню.")


def cheevo_validate_retro_config():
    missing = []
    if not _cheevo_ra_username():
        missing.append("RA_USERNAME")
    if not _cheevo_ra_api_key():
        missing.append("RA_API_KEY")
    if missing:
        raise RuntimeError(f"Не заданы: {', '.join(missing)} — заполните RetroAchievements в модуле Cheevoscope.")


class CheevoRateLimiter:
    """До max_concurrency запросов "в полёте" одновременно, старты запросов
    разнесены не менее чем на min_interval секунд — тот же приём, что был в
    оригинале (steam_api.RateLimiter/retro_api.RateLimiter, идентичны,
    здесь один класс на оба случая использования)."""

    def __init__(self, min_interval, max_concurrency):
        self._lock = threading.Lock()
        self._next_slot = 0.0
        self._min_interval = min_interval
        self._sem = threading.Semaphore(max_concurrency)

    def __enter__(self):
        self._sem.acquire()
        with self._lock:
            now = time.time()
            start_at = max(now, self._next_slot)
            self._next_slot = start_at + self._min_interval
        wait = start_at - now
        if wait > 0:
            time.sleep(wait)
        return self

    def __exit__(self, exc_type, exc, tb):
        self._sem.release()
        return False


_cheevo_api_limiter = CheevoRateLimiter(CHEEVO_REQUEST_DELAY, CHEEVO_API_CONCURRENCY)
_cheevo_store_limiter = CheevoRateLimiter(CHEEVO_STORE_REQUEST_DELAY, CHEEVO_STORE_CONCURRENCY)
_cheevo_ra_limiter = CheevoRateLimiter(CHEEVO_RA_REQUEST_DELAY, CHEEVO_RA_CONCURRENCY)


def _cheevo_urlopen(url, params, headers, timeout):
    if params:
        url = url + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status, resp.read()


def _cheevo_get(url, params, timeout=15):
    """Аналог steam_api._get — обычный Web API-эндпоинт, throttle через
    _cheevo_api_limiter, без ретраев (вызывающий код ретраит сам, где нужно)."""
    with _cheevo_api_limiter:
        _, body = _cheevo_urlopen(url, params, None, timeout)
    return json.loads(body)


def _cheevo_get_with_retry(url, params, max_retries=3, timeout=15):
    """Обёртка над _cheevo_get с ретраем на 429/5xx (экспоненциальный backoff),
    как в GetGlobalAchievementPercentages/GetSchemaForGame/GetPlayerAchievements
    оригинала — три места с одинаковым паттерном, вынесены в одну функцию."""
    for attempt in range(max_retries):
        try:
            return _cheevo_get(url, params, timeout)
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < max_retries - 1:
                time.sleep(2 ** (attempt + 1))
                continue
            raise
        except urllib.error.URLError:
            if attempt < max_retries - 1:
                time.sleep(2 ** (attempt + 1))
                continue
            raise
    return {}


def _cheevo_get_store(url, params, timeout=15, max_retries=4):
    """Аналог steam_api._get_store — своя throttle-очередь и ретрай на 429
    с уважением Retry-After (витрина Steam гораздо строже основного API)."""
    last_error = None
    for attempt in range(max_retries):
        with _cheevo_store_limiter:
            try:
                if params:
                    full_url = url + "?" + urllib.parse.urlencode(params)
                else:
                    full_url = url
                req = urllib.request.Request(full_url)
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    return json.loads(resp.read())
            except urllib.error.HTTPError as e:
                last_error = e
                if e.code == 429:
                    retry_after = e.headers.get("Retry-After") if e.headers else None
                    wait = float(retry_after) if retry_after else (2 ** (attempt + 1))
                    time.sleep(wait)
                    continue
                raise
            except urllib.error.URLError as e:
                last_error = e
                if attempt < max_retries - 1:
                    time.sleep(2 ** (attempt + 1))
                    continue
                raise
    if last_error:
        raise last_error
    return {}


# ---------- Steam API (порт steam_api.py) ----------

def cheevo_get_owned_games():
    """IPlayerService/GetOwnedGames — список игр пользователя с playtime."""
    url = "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/"
    params = {
        "key": _cheevo_steam_api_key(), "steamid": _cheevo_steam_id(),
        "include_appinfo": 1, "include_played_free_games": 1, "format": "json",
    }
    data = _cheevo_get(url, params)
    return data.get("response", {}).get("games", [])


def cheevo_get_recently_played_games():
    """IPlayerService/GetRecentlyPlayedGames — резервный источник, тихо
    деградирует до пустого списка при сетевой ошибке (см. оригинал)."""
    url = "https://api.steampowered.com/IPlayerService/GetRecentlyPlayedGames/v1/"
    params = {"key": _cheevo_steam_api_key(), "steamid": _cheevo_steam_id(), "count": 0, "format": "json"}
    try:
        data = _cheevo_get(url, params)
        return data.get("response", {}).get("games", [])
    except (urllib.error.URLError, urllib.error.HTTPError):
        return []


def cheevo_resolve_steamid64(raw):
    """STEAM_ID может быть готовым SteamID64, ником или ссылкой на профиль —
    приводим к числовому SteamID64."""
    raw = raw.strip()
    if raw.isdigit() and len(raw) == 17:
        return raw

    vanity = raw
    for marker in ("/profiles/", "/id/"):
        if marker in raw:
            tail = raw.split(marker, 1)[1]
            vanity = tail.strip("/").split("/")[0]
            break

    if vanity.isdigit() and len(vanity) == 17:
        return vanity

    url = "https://api.steampowered.com/ISteamUser/ResolveVanityURL/v1/"
    data = _cheevo_get(url, {"key": _cheevo_steam_api_key(), "vanityurl": vanity, "format": "json"})
    response = data.get("response", {})
    if response.get("success") != 1:
        raise RuntimeError(f"Steam не смог найти профиль по имени «{vanity}».")
    return response["steamid"]


def cheevo_get_full_library(steamid64):
    """Публичный XML-фид страницы "Игры" профиля — ловит F2P/Family Sharing
    игры, которых GetOwnedGames не отдаёт. Требует публичных "Сведений об
    играх" в приватности профиля; иначе тихо возвращает []."""
    url = f"https://steamcommunity.com/profiles/{steamid64}/games?tab=all&xml=1"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=20) as resp:
            text = resp.read().decode("utf-8", errors="replace")
    except (urllib.error.URLError, urllib.error.HTTPError):
        return []

    if "<error>" in text:
        return []

    try:
        root = ET.fromstring(text)
    except ET.ParseError:
        return []

    games_node = root.find("games")
    if games_node is None:
        return []

    result = []
    for game in games_node.findall("game"):
        appid_el = game.find("appID")
        name_el = game.find("name")
        if appid_el is None or appid_el.text is None:
            continue
        try:
            appid = int(appid_el.text)
        except ValueError:
            continue
        result.append({"appid": appid, "name": (name_el.text or f"appid {appid}").strip()})
    return result


def cheevo_get_global_achievement_percentages(appid):
    """% игроков, открывших каждую ачивку игры — общая статистика, не
    личная. Ретраит 429/5xx; при окончательной неудаче — молча []."""
    url = "https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/"
    try:
        data = _cheevo_get_with_retry(url, {"gameid": appid, "format": "json"})
        return data.get("achievementpercentages", {}).get("achievements", [])
    except (urllib.error.URLError, urllib.error.HTTPError):
        return []


def cheevo_get_schema_for_game(appid):
    """Статичное описание ачивок игры (названия/описания/иконки), с русской
    локализацией, если доступна."""
    url = "https://api.steampowered.com/ISteamUserStats/GetSchemaForGame/v2/"
    params = {"key": _cheevo_steam_api_key(), "appid": appid, "l": "russian", "format": "json"}
    try:
        data = _cheevo_get_with_retry(url, params)
        return data.get("game", {}).get("availableGameStats", {}).get("achievements", [])
    except (urllib.error.URLError, urllib.error.HTTPError):
        return []


def cheevo_get_player_achievements(appid):
    """Личный прогресс по ачивкам. transient_error различает "точно нет
    достижений" (можно кэшировать) от "временная ошибка сети" (нельзя)."""
    url = "https://api.steampowered.com/ISteamUserStats/GetPlayerAchievements/v0001/"
    params = {"key": _cheevo_steam_api_key(), "steamid": _cheevo_steam_id(), "appid": appid, "format": "json"}
    max_retries = 3
    for attempt in range(max_retries):
        try:
            data = _cheevo_get(url, params)
            response = data.get("playerstats", {})
            if not response.get("success"):
                return {"achievements": [], "transient_error": False}
            response["transient_error"] = False
            return response
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < max_retries - 1:
                time.sleep(2 ** (attempt + 1))
                continue
            return {"achievements": [], "transient_error": True}
        except urllib.error.URLError:
            return {"achievements": [], "transient_error": True}
    return {"achievements": [], "transient_error": True}


def cheevo_download_image_bytes(url):
    """Скачивает картинку по прямой ссылке CDN — статика, без throttle."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.read()
    except (urllib.error.URLError, urllib.error.HTTPError):
        return None


CHEEVO_PRICE_FALLBACK_COUNTRIES = ["us"]

CHEEVO_REVIEW_SCORE_LABELS_RU = {
    9: "Крайне положительные", 8: "Очень положительные", 7: "Положительные",
    6: "Скорее положительные", 5: "Смешанные", 4: "Скорее отрицательные",
    3: "Отрицательные", 2: "Очень отрицательные", 1: "Крайне отрицательные",
    0: "Недостаточно отзывов",
}


def cheevo_get_app_price(appid):
    """Цена через store.steampowered.com/api/appdetails, строго в USD (см.
    обоснование в оригинале — чужая валюта без конвертации не смешивается
    с долларами). Заодно забирает header_image/capsule_image."""
    url = "https://store.steampowered.com/api/appdetails"
    image_urls = {}

    for cc in CHEEVO_PRICE_FALLBACK_COUNTRIES:
        params = {"appids": appid, "cc": cc, "l": "en"}
        try:
            data = _cheevo_get_store(url, params)
        except (urllib.error.URLError, urllib.error.HTTPError):
            if cc == CHEEVO_PRICE_FALLBACK_COUNTRIES[-1]:
                return {"price_found": False, "transient_error": True, **image_urls}
            continue

        entry = data.get(str(appid))
        if not entry or not entry.get("success"):
            continue

        app_data = entry.get("data", {})
        if not image_urls:
            if app_data.get("header_image"):
                image_urls["header_image"] = app_data["header_image"]
            if app_data.get("capsule_image"):
                image_urls["capsule_image"] = app_data["capsule_image"]
            if app_data.get("capsule_imagev5"):
                image_urls["capsule_imagev5"] = app_data["capsule_imagev5"]

        if app_data.get("is_free"):
            return {"price_found": True, "transient_error": False, "is_free": True,
                    "initial_price_usd": 0.0, "price_region": cc, **image_urls}

        price_overview = app_data.get("price_overview")
        if price_overview:
            currency = price_overview.get("currency", "USD")
            if currency != "USD":
                continue
            return {"price_found": True, "transient_error": False, "is_free": False,
                    "initial_price_usd": round(price_overview.get("initial", 0) / 100, 2),
                    "price_region": cc, **image_urls}

    return {"price_found": False, "transient_error": False, **image_urls}


def cheevo_get_app_reviews(appid):
    """Сводка отзывов (не текст) через тот же витринный API, что и цены."""
    url = f"https://store.steampowered.com/appreviews/{appid}"
    params = {"json": 1, "language": "all", "purchase_type": "all", "num_per_page": 0}
    try:
        data = _cheevo_get_store(url, params)
        if not data.get("success"):
            return {"reviews_found": False, "transient_error": False}
        summary = data.get("query_summary", {})
        total = summary.get("total_reviews", 0)
        if not total:
            return {"reviews_found": False, "transient_error": False}
        positive = summary.get("total_positive", 0)
        score = summary.get("review_score", 0)
        return {
            "reviews_found": True, "transient_error": False, "review_score": score,
            "review_desc": CHEEVO_REVIEW_SCORE_LABELS_RU.get(score, summary.get("review_score_desc", "")),
            "total_reviews": total, "positive_percent": round(100 * positive / total, 1),
        }
    except (urllib.error.URLError, urllib.error.HTTPError):
        return {"reviews_found": False, "transient_error": True}


# ---------- Кэш (порт cache.py) ----------

CHEEVO_CACHE_FORMAT_VERSION = 1


def _cheevo_cache_path(key):
    safe_key = key.replace("/", "_").replace(" ", "_")
    return os.path.join(CHEEVO_CACHE_DIR, f"{safe_key}.json")


def cheevo_cache_get_with_age(key):
    path = _cheevo_cache_path(key)
    if not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            payload = json.load(f)
    except (json.JSONDecodeError, OSError):
        return None
    if payload.get("_version") != CHEEVO_CACHE_FORMAT_VERSION:
        return None
    age_hours = (time.time() - payload.get("_cached_at", 0)) / 3600
    return payload.get("data"), age_hours


def cheevo_cache_get(key, ttl_hours=CHEEVO_CACHE_TTL_HOURS):
    cached = cheevo_cache_get_with_age(key)
    if cached is None:
        return None
    data, age_hours = cached
    if age_hours > ttl_hours:
        return None
    return data


def cheevo_cache_set(key, data):
    os.makedirs(CHEEVO_CACHE_DIR, exist_ok=True)
    path = _cheevo_cache_path(key)
    payload = {"_version": CHEEVO_CACHE_FORMAT_VERSION, "_cached_at": time.time(), "data": data}
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False)


def cheevo_cached_call(key, fetch_fn, ttl_hours=CHEEVO_CACHE_TTL_HOURS):
    cached = cheevo_cache_get(key, ttl_hours)
    if cached is not None:
        return cached
    fresh = fetch_fn()
    cheevo_cache_set(key, fresh)
    return fresh


def _cheevo_atomic_write_json(path, data):
    """Пишет во временный файл и атомарно переименовывает поверх
    оригинала — при падении процесса посреди записи исходный файл
    остаётся целым (см. io_utils.atomic_write_json оригинала)."""
    tmp_path = path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp_path, path)


def _cheevo_load_json_file(path, default):
    if not os.path.exists(path):
        return default
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return default


def _cheevo_now_iso():
    return datetime.now(timezone.utc).isoformat()


# ---------- Библиотека и время (порт stats.fetch_games_list) ----------

def _cheevo_load_manual_appids():
    return _cheevo_load_json_file(CHEEVO_MANUAL_APPIDS_FILE, []) or []


def cheevo_fetch_games_list():
    """Собирает ПОЛНЫЙ список игр из всех источников (GetOwnedGames +
    GetRecentlyPlayedGames + manual_appids + полный XML-фид библиотеки) —
    см. подробное обоснование каждого источника в оригинале stats.py."""
    owned = cheevo_get_owned_games()
    known_appids = {g["appid"] for g in owned}
    extra_games = []

    for g in cheevo_get_recently_played_games():
        appid = g["appid"]
        if appid in known_appids:
            continue
        extra_games.append({
            "appid": appid, "name": g.get("name") or f"appid {appid}",
            "playtime_forever": g.get("playtime_forever", 0), "_unverified": True,
        })
        known_appids.add(appid)

    for entry in _cheevo_load_manual_appids():
        appid = entry.get("appid")
        if appid is None or appid in known_appids:
            continue
        extra_games.append({"appid": appid, "name": entry.get("name") or f"appid {appid}",
                             "playtime_forever": 0, "_unverified": True})
        known_appids.add(appid)

    try:
        steamid64 = cheevo_resolve_steamid64(_cheevo_steam_id())
        full_library = cheevo_get_full_library(steamid64)
    except Exception:
        full_library = []

    for g in full_library:
        appid = g["appid"]
        if appid in known_appids:
            continue
        extra_games.append({"appid": appid, "name": g["name"], "playtime_forever": 0, "_unverified": True})
        known_appids.add(appid)

    games = owned + extra_games
    total_minutes = sum(g.get("playtime_forever", 0) for g in games)
    result = {
        "fetched_at": _cheevo_now_iso(),
        "games_count": len(games),
        "total_hours": round(total_minutes / 60, 1),
        "games": games,
    }
    _cheevo_atomic_write_json(CHEEVO_GAMES_LIST_FILE, result)
    return result


def _cheevo_run_parallel(games, worker, max_workers, id_key="appid"):
    """Прогоняет worker(game) по списку игр в пуле потоков, собирает
    результаты в словарь по ключу id_key (appid/GameID)."""
    results = {}

    def _wrapped(game):
        return game[id_key], worker(game)

    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        futures = [pool.submit(_wrapped, g) for g in games]
        for fut in as_completed(futures):
            key, res = fut.result()
            results[key] = res
    return results


# ---------- Достижения ----------

def _cheevo_achievements_cache_ttl_hours(cached_data):
    achievements = cached_data.get("achievements", [])
    total = len(achievements)
    if total == 0:
        return CHEEVO_NO_ACHIEVEMENTS_CACHE_TTL_HOURS
    unlocked = sum(1 for a in achievements if a.get("achieved") == 1)
    if unlocked == total:
        return CHEEVO_COMPLETED_ACHIEVEMENTS_CACHE_TTL_HOURS
    return 0.0


def _cheevo_fetch_one_game_achievements(game):
    appid = game["appid"]
    name = game.get("name", f"appid {appid}")

    global_pct = cheevo_cached_call(f"global_pct_{appid}", lambda a=appid: cheevo_get_global_achievement_percentages(a))

    skip_cache = bool(game.get("_unverified"))
    cache_key = f"player_ach_{appid}"
    player_data = None
    if not skip_cache:
        cached = cheevo_cache_get_with_age(cache_key)
        if cached is not None:
            cached_data, age_hours = cached
            if age_hours <= _cheevo_achievements_cache_ttl_hours(cached_data):
                player_data = cached_data

    if player_data is None:
        player_data = cheevo_get_player_achievements(appid)
        if not player_data.get("transient_error") and not skip_cache:
            cheevo_cache_set(cache_key, player_data)

    player_achievements = player_data.get("achievements", [])
    total_achievements = len(player_achievements)
    if total_achievements == 0:
        return None

    unlocked = [a for a in player_achievements if a.get("achieved") == 1]
    unlocked_count = len(unlocked)

    unlock_dates = []
    for a in unlocked:
        ts = a.get("unlocktime") or 0
        if ts > 0:
            unlock_dates.append(datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%d"))

    rarest_unlocked = None
    unlocked_rarities = []
    if unlocked and global_pct:
        pct_by_name = {}
        for a in global_pct:
            try:
                pct_by_name[a["name"]] = float(a["percent"])
            except (TypeError, ValueError):
                pass
        rarities = [(a["apiname"], pct_by_name.get(a["apiname"])) for a in unlocked if pct_by_name.get(a["apiname"]) is not None]
        if rarities:
            rarest_unlocked = min(rarities, key=lambda x: x[1])
            unlocked_rarities = [{"apiname": apiname, "global_percent": percent} for apiname, percent in rarities]

    return {
        "name": name, "unlocked": unlocked_count, "total": total_achievements,
        "percent_complete": round(100 * unlocked_count / total_achievements, 1),
        "rarest_unlocked": ({"apiname": rarest_unlocked[0], "global_percent": rarest_unlocked[1]} if rarest_unlocked else None),
        "unlocked_rarities": unlocked_rarities,
        "unlock_dates": unlock_dates,
    }


# Тиры "крутости" ачивки по мировой редкости — верхняя граница включительно.
CHEEVO_RARITY_TIERS = [
    ("gold", 1.0), ("purple", 3.0), ("blue", 8.0), ("green", 20.0), ("white", 50.0), ("gray", 101.0),
]


def _cheevo_rarity_tier_for(percent):
    for tier_id, ceiling in CHEEVO_RARITY_TIERS:
        if percent <= ceiling:
            return tier_id
    return "gray"


def cheevo_compute_rarity_tiers(candidates):
    """Распределение всех открытых ачивок по тирам gray/white/green/blue/
    purple/gold + coolness_score (100 - средний global_percent)."""
    counts = {tier_id: 0 for tier_id, _ in CHEEVO_RARITY_TIERS}
    total = 0
    percent_sum = 0.0
    for c in candidates:
        pct = c.get("global_percent")
        if pct is None:
            continue
        counts[_cheevo_rarity_tier_for(pct)] += 1
        percent_sum += pct
        total += 1
    coolness_score = round(100 - (percent_sum / total), 1) if total else 0.0
    return {"total_rated": total, "counts": counts, "coolness_score": coolness_score}


def _cheevo_collect_unlocked_rarity_candidates(achievements_data):
    candidates = []
    for appid_str, info in achievements_data.get("games", {}).items():
        for entry in info.get("unlocked_rarities", []):
            candidates.append({"appid": int(appid_str), "apiname": entry["apiname"], "global_percent": entry["global_percent"]})
    return candidates


def cheevo_compute_rarest_achievements(achievements_data, games, top_n=10):
    """Топ-N самых редких открытых ачивок по всей библиотеке разом."""
    name_by_appid = {g["appid"]: g.get("name", f"appid {g['appid']}") for g in games}
    candidates = _cheevo_collect_unlocked_rarity_candidates(achievements_data)
    candidates.sort(key=lambda c: c["global_percent"])
    top = candidates[:top_n]

    result = []
    schema_cache = {}
    for c in top:
        appid = c["appid"]
        if appid not in schema_cache:
            schema_cache[appid] = cheevo_cached_call(
                f"schema_ru_{appid}", lambda a=appid: cheevo_get_schema_for_game(a),
                ttl_hours=CHEEVO_ACHIEVEMENT_SCHEMA_CACHE_TTL_HOURS,
            )
        display_name = c["apiname"]
        for a in schema_cache[appid]:
            if a.get("name") == c["apiname"]:
                display_name = a.get("displayName", c["apiname"])
                break
        result.append({"appid": appid, "game": name_by_appid.get(appid, f"appid {appid}"),
                        "name": display_name, "global_percent": round(c["global_percent"], 1)})
    return result


def cheevo_compute_activity_heatmap(achievements_data):
    counts = {}
    for info in achievements_data.get("games", {}).values():
        for date_str in info.get("unlock_dates", []):
            counts[date_str] = counts.get(date_str, 0) + 1
    return counts


def cheevo_fetch_achievements_stats(games):
    raw = _cheevo_run_parallel(games, _cheevo_fetch_one_game_achievements, CHEEVO_API_CONCURRENCY)
    per_game = {str(appid): info for appid, info in raw.items() if info is not None}
    result = {"fetched_at": _cheevo_now_iso(), "games": per_game}
    result["rarest_achievements"] = cheevo_compute_rarest_achievements(result, games)
    result["rarity_tiers"] = cheevo_compute_rarity_tiers(_cheevo_collect_unlocked_rarity_candidates(result))
    result["activity_heatmap"] = cheevo_compute_activity_heatmap(result)
    _cheevo_atomic_write_json(CHEEVO_ACHIEVEMENTS_STATS_FILE, result)
    return result


# ---------- Картинки ----------

def _cheevo_best_image_url(info):
    return info.get("header_image") or info.get("capsule_imagev5") or info.get("capsule_image")


def cheevo_load_images():
    return _cheevo_load_json_file(CHEEVO_IMAGES_FILE, {"fetched_at": None, "games_with_images": 0, "games": {}})


def _cheevo_download_one_game_image(args):
    appid, info, existing_entry = args
    url = _cheevo_best_image_url(info)
    entry = {
        "header_image": info.get("header_image"), "capsule_image": info.get("capsule_image"),
        "capsule_imagev5": info.get("capsule_imagev5"),
        "local_image": existing_entry.get("local_image"), "source_url": existing_entry.get("source_url"),
    }
    if not url:
        entry["local_image"] = None
        entry["source_url"] = None
        return entry

    ext = url.split("?", 1)[0].rsplit(".", 1)[-1].lower()
    if ext not in ("jpg", "jpeg", "png", "webp"):
        ext = "jpg"
    local_filename = f"{appid}.{ext}"
    local_path = os.path.join(CHEEVO_IMAGES_DIR, local_filename)

    if existing_entry.get("source_url") == url and os.path.exists(local_path):
        return entry

    data = cheevo_download_image_bytes(url)
    if data is None:
        return entry

    old_local = existing_entry.get("local_image")
    if old_local and old_local != local_filename:
        old_path = os.path.join(CHEEVO_IMAGES_DIR, os.path.basename(old_local))
        if os.path.exists(old_path):
            try:
                os.remove(old_path)
            except OSError:
                pass

    try:
        os.makedirs(CHEEVO_IMAGES_DIR, exist_ok=True)
        with open(local_path, "wb") as f:
            f.write(data)
        entry["local_image"] = local_filename
        entry["source_url"] = url
    except OSError:
        pass

    return entry


def cheevo_fetch_game_images(games):
    """Реально скачивает картинки на диск хаба (не только запоминает URL) —
    при повторных заходах отдаются с самого хаба, не с CDN Steam каждый раз."""
    existing = cheevo_load_images().get("games", {})
    raw = _cheevo_run_parallel(games, _cheevo_fetch_one_game_price, CHEEVO_STORE_CONCURRENCY)

    download_args = [
        (game["appid"], raw.get(game["appid"], {}), existing.get(str(game["appid"]), {}))
        for game in games
    ]
    downloaded = {}
    with ThreadPoolExecutor(max_workers=10) as pool:
        futures = {pool.submit(_cheevo_download_one_game_image, args): args[0] for args in download_args}
        for fut in as_completed(futures):
            appid = futures[fut]
            downloaded[appid] = fut.result()

    per_game = dict(existing)
    for game in games:
        per_game[str(game["appid"])] = downloaded[game["appid"]]

    found = sum(1 for v in per_game.values() if v.get("local_image") or v.get("header_image") or v.get("capsule_image"))
    result = {"fetched_at": _cheevo_now_iso(), "games_with_images": found, "games": per_game}
    _cheevo_atomic_write_json(CHEEVO_IMAGES_FILE, result)
    return result


# ---------- Цены ----------

def cheevo_load_library_cost():
    return _cheevo_load_json_file(CHEEVO_LIBRARY_COST_FILE, {
        "fetched_at": None, "total_cost_usd": 0.0, "games_priced": 0,
        "games_price_not_found": 0, "games_price_rate_limited": 0, "games": {},
    })


def _cheevo_fetch_one_game_price(game):
    appid = game["appid"]
    cache_key = f"price_{appid}"
    price_info = cheevo_cache_get(cache_key, ttl_hours=24 * 7)
    if price_info is None:
        price_info = cheevo_get_app_price(appid)
        if not price_info.get("transient_error"):
            cheevo_cache_set(cache_key, price_info)
    return price_info


def cheevo_fetch_library_cost(games):
    raw = _cheevo_run_parallel(games, _cheevo_fetch_one_game_price, CHEEVO_STORE_CONCURRENCY)
    per_game = {}
    total_cost = 0.0
    not_found = 0
    rate_limited = 0

    for game in games:
        appid = game["appid"]
        name = game.get("name", f"appid {appid}")
        price_info = raw.get(appid, {})

        if price_info.get("price_found"):
            price = price_info.get("initial_price_usd", 0.0)
            per_game[str(appid)] = {"name": name, "price_usd": price,
                                     "header_image": price_info.get("header_image"),
                                     "capsule_image": price_info.get("capsule_image"),
                                     "capsule_imagev5": price_info.get("capsule_imagev5")}
            total_cost += price
        elif price_info.get("transient_error"):
            not_found += 1
            rate_limited += 1
            per_game[str(appid)] = {"name": name, "price_usd": None,
                                     "header_image": price_info.get("header_image"),
                                     "capsule_image": price_info.get("capsule_image"),
                                     "capsule_imagev5": price_info.get("capsule_imagev5")}
        else:
            per_game[str(appid)] = {"name": name, "price_usd": 0.0,
                                     "header_image": price_info.get("header_image"),
                                     "capsule_image": price_info.get("capsule_image"),
                                     "capsule_imagev5": price_info.get("capsule_imagev5")}

    result = {
        "fetched_at": _cheevo_now_iso(), "total_cost_usd": round(total_cost, 2),
        "games_priced": len(games) - not_found, "games_price_not_found": not_found,
        "games_price_rate_limited": rate_limited, "games": per_game,
    }
    _cheevo_atomic_write_json(CHEEVO_LIBRARY_COST_FILE, result)
    return result


# ---------- Отзывы ----------

def cheevo_load_reviews():
    return _cheevo_load_json_file(CHEEVO_REVIEWS_FILE, {"fetched_at": None, "games_with_reviews": 0, "games": {}})


def _cheevo_fetch_one_game_review(game):
    appid = game["appid"]
    cache_key = f"review_{appid}"
    review_info = cheevo_cache_get(cache_key, ttl_hours=24 * 7)
    if review_info is None:
        review_info = cheevo_get_app_reviews(appid)
        if not review_info.get("transient_error"):
            cheevo_cache_set(cache_key, review_info)
    return review_info


def cheevo_fetch_reviews(games):
    raw = _cheevo_run_parallel(games, _cheevo_fetch_one_game_review, CHEEVO_STORE_CONCURRENCY)
    per_game = {}
    found = 0
    for game in games:
        appid = game["appid"]
        name = game.get("name", f"appid {appid}")
        review_info = raw.get(appid, {})
        if review_info.get("reviews_found"):
            found += 1
            per_game[str(appid)] = {
                "name": name, "review_score": review_info.get("review_score", 0),
                "review_desc": review_info.get("review_desc", ""),
                "total_reviews": review_info.get("total_reviews", 0),
                "positive_percent": review_info.get("positive_percent", 0),
            }
        else:
            per_game[str(appid)] = None
    result = {"fetched_at": _cheevo_now_iso(), "games_with_reviews": found, "games": per_game}
    _cheevo_atomic_write_json(CHEEVO_REVIEWS_FILE, result)
    return result


# ---------- Загрузка уже посчитанного (для генерации отчёта частями) ----------

def cheevo_load_games_list():
    return _cheevo_load_json_file(CHEEVO_GAMES_LIST_FILE, None)


def cheevo_load_achievements_stats():
    return _cheevo_load_json_file(CHEEVO_ACHIEVEMENTS_STATS_FILE, {
        "fetched_at": None, "games": {}, "rarest_achievements": [],
        "rarity_tiers": {"total_rated": 0, "counts": {}, "coolness_score": 0.0}, "activity_heatmap": {},
    })


# ---------- Сборка единого отчёта ----------

def cheevo_generate_report(games_data, achievements_data, cost_data, reviews_data=None, images_data=None):
    achievements_by_appid = achievements_data.get("games", {})
    reviews_by_appid = (reviews_data or {}).get("games", {})
    cost_by_appid = cost_data.get("games", {})
    images_by_appid = (images_data or {}).get("games", {})

    games_grid = []
    for g in games_data["games"]:
        appid = g["appid"]
        info = achievements_by_appid.get(str(appid))
        review = reviews_by_appid.get(str(appid))
        cost_info = cost_by_appid.get(str(appid))
        image_info = images_by_appid.get(str(appid))
        games_grid.append({
            "appid": appid, "name": g.get("name", f"appid {appid}"),
            "hours": round(g.get("playtime_forever", 0) / 60, 1),
            "achievements_percent": info["percent_complete"] if info else None,
            "achievements_unlocked": info["unlocked"] if info else None,
            "achievements_total": info["total"] if info else None,
            "local_image": (image_info or {}).get("local_image"),
            "header_image": (image_info or {}).get("header_image") or (cost_info or {}).get("header_image"),
            "capsule_image": (image_info or {}).get("capsule_image") or (cost_info or {}).get("capsule_image"),
            "capsule_imagev5": (image_info or {}).get("capsule_imagev5") or (cost_info or {}).get("capsule_imagev5"),
            "review_desc": review["review_desc"] if review else None,
            "review_score": review["review_score"] if review else None,
            "review_positive_percent": review["positive_percent"] if review else None,
            "review_total": review["total_reviews"] if review else None,
        })

    with_ach = sorted([g for g in games_grid if g["achievements_percent"] is not None], key=lambda g: g["name"].lower())
    without_ach = sorted([g for g in games_grid if g["achievements_percent"] is None], key=lambda g: g["name"].lower())
    games_grid = with_ach + without_ach

    total_ach_unlocked = sum(info["unlocked"] for info in achievements_by_appid.values())
    total_ach_available = sum(info["total"] for info in achievements_by_appid.values())
    overall_percent = round(100 * total_ach_unlocked / total_ach_available, 1) if total_ach_available else 0.0
    games_completed_100 = sum(1 for info in achievements_by_appid.values() if info["percent_complete"] == 100.0)

    report = {
        "generated_at": _cheevo_now_iso(),
        "summary": {
            "games_count": games_data["games_count"], "total_hours": games_data["total_hours"],
            "library_cost_usd": cost_data["total_cost_usd"], "games_priced": cost_data["games_priced"],
            "games_price_not_found": cost_data["games_price_not_found"],
            "games_price_rate_limited": cost_data.get("games_price_rate_limited", 0),
            "achievements_unlocked_total": total_ach_unlocked, "achievements_available_total": total_ach_available,
            "achievements_overall_percent": overall_percent, "games_completed_100": games_completed_100,
            "games_with_achievements": len(with_ach), "games_without_achievements": len(without_ach),
        },
        "games_grid": games_grid,
        "rarest_achievements": achievements_data.get("rarest_achievements", []),
        "rarity_tiers": achievements_data.get("rarity_tiers", {"total_rated": 0, "counts": {}, "coolness_score": 0.0}),
        "activity_heatmap": achievements_data.get("activity_heatmap", {}),
    }
    _cheevo_atomic_write_json(CHEEVO_REPORT_JSON_FILE, report)
    return report


# ---------- Статус-трекер (порт status_tracker.py) ----------

_CHEEVO_IDLE_STATUS = {"state": "idle", "stage": None, "progress": None, "last_success_at": None, "error": None}


def _cheevo_read_status(status_file):
    if not os.path.exists(status_file):
        return dict(_CHEEVO_IDLE_STATUS)
    try:
        with open(status_file, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return dict(_CHEEVO_IDLE_STATUS)


def _cheevo_write_status(status_file, **kwargs):
    current = _cheevo_read_status(status_file)
    current.update(kwargs)
    current["updated_at"] = _cheevo_now_iso()
    _cheevo_atomic_write_json(status_file, current)


# ---------- Оркестрация обновления (порт pipeline.py) — Steam ----------

_cheevo_pipeline_lock = threading.Lock()
_cheevo_pipeline_running = False


def _cheevo_run_quick_pipeline():
    """"Обновить": список игр + достижения (умный кэш экономит запросы) +
    картинки ТОЛЬКО для новых игр. Цены/отзывы не трогает."""
    previous = cheevo_load_games_list()
    previous_appids = {g["appid"] for g in previous["games"]} if previous else set()

    _cheevo_write_status(CHEEVO_STATUS_FILE, state="running", stage="games_list", progress=None, error=None)
    games_data = cheevo_fetch_games_list()
    images_data = cheevo_load_images()
    cheevo_generate_report(games_data, cheevo_load_achievements_stats(), cheevo_load_library_cost(), cheevo_load_reviews(), images_data)

    new_games = [g for g in games_data["games"] if g["appid"] not in previous_appids]
    if new_games:
        _cheevo_write_status(CHEEVO_STATUS_FILE, state="running", stage="images", progress=None)
        images_data = cheevo_fetch_game_images(new_games)
        cheevo_generate_report(games_data, cheevo_load_achievements_stats(), cheevo_load_library_cost(), cheevo_load_reviews(), images_data)

    _cheevo_write_status(CHEEVO_STATUS_FILE, state="running", stage="achievements", progress=None)
    achievements_data = cheevo_fetch_achievements_stats(games_data["games"])

    _cheevo_write_status(CHEEVO_STATUS_FILE, state="running", stage="report", progress=None)
    cheevo_generate_report(games_data, achievements_data, cheevo_load_library_cost(), cheevo_load_reviews(), images_data)


def _cheevo_run_full_pipeline():
    """"Обновить всё": полный пересчёт с нуля (кэш личных данных чистится
    заранее, см. _cheevo_clear_all_cache)."""
    _cheevo_write_status(CHEEVO_STATUS_FILE, state="running", stage="games_list", progress=None, error=None)
    games_data = cheevo_fetch_games_list()
    cheevo_generate_report(games_data, cheevo_load_achievements_stats(), cheevo_load_library_cost(), cheevo_load_reviews(), cheevo_load_images())

    _cheevo_write_status(CHEEVO_STATUS_FILE, state="running", stage="images", progress=None)
    images_data = cheevo_fetch_game_images(games_data["games"])
    cheevo_generate_report(games_data, cheevo_load_achievements_stats(), cheevo_load_library_cost(), cheevo_load_reviews(), images_data)

    _cheevo_write_status(CHEEVO_STATUS_FILE, state="running", stage="achievements", progress=None)
    achievements_data = cheevo_fetch_achievements_stats(games_data["games"])
    cheevo_generate_report(games_data, achievements_data, cheevo_load_library_cost(), cheevo_load_reviews(), images_data)

    _cheevo_write_status(CHEEVO_STATUS_FILE, state="running", stage="reviews", progress=None)
    reviews_data = cheevo_fetch_reviews(games_data["games"])
    cheevo_generate_report(games_data, achievements_data, cheevo_load_library_cost(), reviews_data, images_data)

    _cheevo_write_status(CHEEVO_STATUS_FILE, state="running", stage="library_cost", progress=None)
    cost_data = cheevo_fetch_library_cost(games_data["games"])

    _cheevo_write_status(CHEEVO_STATUS_FILE, state="running", stage="report", progress=None)
    cheevo_generate_report(games_data, achievements_data, cost_data, reviews_data, images_data)


def _cheevo_clear_all_cache():
    """Чистит кэш ЛИЧНЫХ данных (цены/отзывы/личные ачивки) перед "Обновить
    всё" — общую статистику по игре (global_pct_*) не трогаем, она не
    зависит от вас лично и меняется очень медленно."""
    removed = 0
    if not os.path.isdir(CHEEVO_CACHE_DIR):
        return removed
    import fnmatch
    for pattern in ("price_*.json", "review_*.json", "player_ach_*.json"):
        for fname in os.listdir(CHEEVO_CACHE_DIR):
            if fnmatch.fnmatch(fname, pattern):
                try:
                    os.remove(os.path.join(CHEEVO_CACHE_DIR, fname))
                    removed += 1
                except OSError:
                    pass
    return removed


def _cheevo_run_pipeline(mode):
    global _cheevo_pipeline_running
    try:
        cheevo_validate_config()
        if mode == "full":
            _cheevo_clear_all_cache()
            _cheevo_run_full_pipeline()
        else:
            _cheevo_run_quick_pipeline()
        _cheevo_write_status(CHEEVO_STATUS_FILE, state="done", stage=None, progress=None, last_success_at=_cheevo_now_iso(), error=None)
        print(f"[cheevoscope] обновление (Steam, {mode}) завершено успешно", flush=True)
    except Exception as e:
        print(f"[cheevoscope] ошибка обновления (Steam, {mode}): {e}", flush=True)
        _cheevo_write_status(CHEEVO_STATUS_FILE, state="error", error=str(e))
    finally:
        with _cheevo_pipeline_lock:
            _cheevo_pipeline_running = False


def cheevo_start_refresh(mode="quick"):
    if mode not in ("quick", "full"):
        raise ValueError(f"неизвестный режим обновления: {mode!r}")
    global _cheevo_pipeline_running
    with _cheevo_pipeline_lock:
        if _cheevo_pipeline_running:
            return False
        _cheevo_pipeline_running = True
    threading.Thread(target=_cheevo_run_pipeline, args=(mode,), daemon=True).start()
    return True


# ============================================================
# RETROACHIEVEMENTS — порт retro_api.py
# ============================================================

CHEEVO_RA_BASE_URL = "https://retroachievements.org/API"


def _cheevo_ra_ensure_dict(data, endpoint):
    """RA иногда отвечает голой строкой (напр. "Invalid API Key") вместо
    JSON-объекта — без этой проверки любой .get(...) падает с невнятным
    'str' object has no attribute 'get'."""
    if isinstance(data, dict):
        return data
    print(f"[cheevoscope] RA API {endpoint} вернул не объект: {data!r}", flush=True)
    return {}


def _cheevo_ra_get(endpoint, params=None, timeout=15, max_retries=3):
    url = f"{CHEEVO_RA_BASE_URL}/{endpoint}.php"
    query = {"z": _cheevo_ra_username(), "y": _cheevo_ra_api_key(), **(params or {})}
    for attempt in range(max_retries):
        with _cheevo_ra_limiter:
            try:
                full_url = url + "?" + urllib.parse.urlencode(query)
                req = urllib.request.Request(full_url)
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    return json.loads(resp.read())
            except urllib.error.HTTPError as e:
                if e.code == 429 and attempt < max_retries - 1:
                    time.sleep(2 ** (attempt + 1))
                    continue
                if attempt < max_retries - 1:
                    time.sleep(2 ** (attempt + 1))
                    continue
                print(f"[cheevoscope] не удалось получить {endpoint} от RA API: {e}", flush=True)
                return {}
            except urllib.error.URLError as e:
                if attempt < max_retries - 1:
                    time.sleep(2 ** (attempt + 1))
                    continue
                print(f"[cheevoscope] не удалось получить {endpoint} от RA API: {e}", flush=True)
                return {}
    return {}


def cheevo_ra_get_user_profile():
    return _cheevo_ra_ensure_dict(_cheevo_ra_get("API_GetUserProfile", {"u": _cheevo_ra_username()}), "API_GetUserProfile")


def cheevo_ra_get_user_completion_progress(max_pages=20):
    """Постранично ВСЕ игры пользователя с прогрессом."""
    results = []
    offset = 0
    page_size = 100
    for _ in range(max_pages):
        raw = _cheevo_ra_get("API_GetUserCompletionProgress", {"u": _cheevo_ra_username(), "c": page_size, "o": offset})
        data = _cheevo_ra_ensure_dict(raw, "API_GetUserCompletionProgress")
        if not data:
            break
        chunk = [g for g in data.get("Results", []) if isinstance(g, dict)]
        results.extend(chunk)
        total = data.get("Total", len(results))
        offset += page_size
        if offset >= total or not chunk:
            break
    return results


def cheevo_ra_get_game_info_and_user_progress(game_id):
    raw = _cheevo_ra_get("API_GetGameInfoAndUserProgress", {"u": _cheevo_ra_username(), "g": game_id})
    return _cheevo_ra_ensure_dict(raw, "API_GetGameInfoAndUserProgress")


def cheevo_ra_get_user_awards():
    data = _cheevo_ra_ensure_dict(_cheevo_ra_get("API_GetUserAwards", {"u": _cheevo_ra_username()}), "API_GetUserAwards")
    return [a for a in data.get("VisibleUserAwards", []) if isinstance(a, dict)]


def cheevo_ra_get_user_recent_achievements(minutes=60 * 24 * 14):
    data = _cheevo_ra_get("API_GetUserRecentAchievements", {"u": _cheevo_ra_username(), "m": minutes})
    return [a for a in data if isinstance(a, dict)] if isinstance(data, list) else []


# ---------- Порт retro_stats.py ----------

def cheevo_ra_fetch_profile():
    return cheevo_ra_get_user_profile()


def cheevo_ra_fetch_completion_progress():
    return cheevo_ra_get_user_completion_progress()


def cheevo_ra_fetch_awards():
    return cheevo_ra_get_user_awards()


def cheevo_ra_fetch_recent_achievements():
    return cheevo_ra_get_user_recent_achievements()


def _cheevo_ra_game_detail_cache_ttl(progress_entry):
    max_possible = progress_entry.get("MaxPossible") or 0
    num_awarded_hc = progress_entry.get("NumAwardedHardcore") or 0
    num_awarded = progress_entry.get("NumAwarded") or 0
    if num_awarded == 0:
        return CHEEVO_RETRO_NO_PROGRESS_CACHE_TTL_HOURS
    if max_possible and num_awarded_hc == max_possible:
        return CHEEVO_RETRO_MASTERED_CACHE_TTL_HOURS
    return 0.0


def _cheevo_ra_fetch_one_game_detail(progress_entry):
    game_id = progress_entry["GameID"]
    cache_key = f"retro_detail_{game_id}"
    cached = cheevo_cache_get_with_age(cache_key)
    ttl = _cheevo_ra_game_detail_cache_ttl(progress_entry)
    if cached is not None:
        data, age_hours = cached
        if age_hours <= ttl and isinstance(data, dict):
            return data
    detail = cheevo_ra_get_game_info_and_user_progress(game_id)
    cheevo_cache_set(cache_key, detail)
    return detail


def cheevo_ra_fetch_game_details(progress_list):
    return _cheevo_run_parallel(progress_list, _cheevo_ra_fetch_one_game_detail, 3, id_key="GameID")


def cheevo_ra_load_retro_report():
    return _cheevo_load_json_file(CHEEVO_RETRO_REPORT_JSON_FILE, {})


def cheevo_ra_generate_report(profile, progress_list, awards, recent, game_details):
    games = []
    points_by_console = {}
    total_hardcore_earned = 0
    total_softcore_earned = 0
    total_possible = 0
    mastered_count = 0
    completed_count = 0
    rarity_candidates = []

    for entry in progress_list:
        if not isinstance(entry, dict):
            continue
        game_id = entry.get("GameID")
        max_possible = entry.get("MaxPossible") or 0
        num_awarded = entry.get("NumAwarded") or 0
        num_awarded_hc = entry.get("NumAwardedHardcore") or 0
        console = entry.get("ConsoleName", "—")

        hardcore_pct = round(100 * num_awarded_hc / max_possible, 1) if max_possible else 0.0
        softcore_pct = round(100 * num_awarded / max_possible, 1) if max_possible else 0.0
        is_mastered = max_possible > 0 and num_awarded_hc == max_possible
        is_completed = max_possible > 0 and num_awarded == max_possible and not is_mastered

        if is_mastered:
            mastered_count += 1
        elif is_completed:
            completed_count += 1

        total_hardcore_earned += num_awarded_hc
        total_softcore_earned += num_awarded
        total_possible += max_possible

        detail = game_details.get(game_id) or {}
        if not isinstance(detail, dict):
            detail = {}
        detail_achievements = (detail.get("Achievements") or {}).values()
        hardcore_points = sum(int(a.get("Points") or 0) for a in detail_achievements if a.get("DateEarnedHardcore"))
        softcore_points = sum(int(a.get("Points") or 0) for a in detail_achievements if a.get("DateEarned"))
        if detail_achievements:
            bucket = points_by_console.setdefault(console, {"hardcore": 0, "softcore": 0})
            bucket["hardcore"] += hardcore_points
            bucket["softcore"] += softcore_points

        total_players = detail.get("NumDistinctPlayersHardcore") or detail.get("NumDistinctPlayersCasual") or 0
        if total_players:
            for a in detail_achievements:
                if not a.get("DateEarned"):
                    continue
                num_a_hc = a.get("NumAwardedHardcore") or 0
                percent = round(100 * num_a_hc / total_players, 1)
                rarity_candidates.append({"game_id": game_id, "game": entry.get("Title", f"game {game_id}"),
                                           "name": a.get("Title", ""), "global_percent": percent})

        games.append({
            "game_id": game_id, "title": entry.get("Title", f"game {game_id}"), "console": console,
            "image_icon": entry.get("ImageIcon", ""), "max_possible": max_possible,
            "num_awarded": num_awarded, "num_awarded_hardcore": num_awarded_hc,
            "hardcore_percent": hardcore_pct, "softcore_percent": softcore_pct,
            "status": "mastered" if is_mastered else ("completed" if is_completed else "in_progress"),
            "most_recent_award_date": entry.get("MostRecentAwardedDate"),
        })

    games.sort(key=lambda g: (g["most_recent_award_date"] or ""), reverse=True)
    overall_hardcore_percent = round(100 * total_hardcore_earned / total_possible, 1) if total_possible else 0.0

    awards_safe = [a for a in awards if isinstance(a, dict)]
    awards_out = [
        {"title": a.get("Title", ""), "console": a.get("ConsoleName", ""),
         "award_type": a.get("AwardType", ""), "award_date": a.get("AwardedAt", "")}
        for a in sorted(awards_safe, key=lambda a: a.get("AwardedAt", ""), reverse=True)
    ]
    recent_out = [
        {"achievement": r.get("Title", ""), "game": r.get("GameTitle", ""),
         "date": r.get("Date", ""), "hardcore": bool(r.get("HardcoreMode"))}
        for r in recent if isinstance(r, dict)
    ]

    rarity_candidates.sort(key=lambda c: c["global_percent"])
    rarest_achievements = rarity_candidates[:10]
    rarity_tiers = cheevo_compute_rarity_tiers(rarity_candidates)

    if not game_details:
        previous = cheevo_ra_load_retro_report()
        points_by_console = previous.get("points_by_console", {})
        rarest_achievements = previous.get("rarest_achievements", [])
        rarity_tiers = previous.get("rarity_tiers", {"total_rated": 0, "counts": {}, "coolness_score": 0.0})

    report = {
        "generated_at": _cheevo_now_iso(),
        "profile": {
            "username": profile.get("User", ""), "points": profile.get("TotalPoints", 0),
            "retro_points": profile.get("TotalTruePoints", 0), "rank": profile.get("Rank", None),
            "avatar_url": profile.get("UserPic", ""),
        },
        "summary": {
            "games_count": len(games), "games_mastered": mastered_count, "games_completed": completed_count,
            "achievements_hardcore_total": total_hardcore_earned, "achievements_softcore_total": total_softcore_earned,
            "achievements_possible_total": total_possible, "overall_hardcore_percent": overall_hardcore_percent,
        },
        "points_by_console": points_by_console, "games": games, "awards": awards_out,
        "recent_achievements": recent_out, "rarest_achievements": rarest_achievements, "rarity_tiers": rarity_tiers,
    }
    _cheevo_atomic_write_json(CHEEVO_RETRO_REPORT_JSON_FILE, report)
    return report


# ---------- Порт retro_pipeline.py ----------

_cheevo_ra_pipeline_lock = threading.Lock()
_cheevo_ra_pipeline_running = False


def _cheevo_ra_run_quick_pipeline():
    _cheevo_write_status(CHEEVO_RETRO_STATUS_FILE, state="running", stage="profile", progress=None, error=None)
    profile = cheevo_ra_fetch_profile()
    _cheevo_write_status(CHEEVO_RETRO_STATUS_FILE, state="running", stage="games", progress=None)
    progress_list = cheevo_ra_fetch_completion_progress()
    _cheevo_write_status(CHEEVO_RETRO_STATUS_FILE, state="running", stage="awards", progress=None)
    awards = cheevo_ra_fetch_awards()
    recent = cheevo_ra_fetch_recent_achievements()
    _cheevo_write_status(CHEEVO_RETRO_STATUS_FILE, state="running", stage="report", progress=None)
    cheevo_ra_generate_report(profile, progress_list, awards, recent, game_details={})


def _cheevo_ra_run_full_pipeline():
    _cheevo_write_status(CHEEVO_RETRO_STATUS_FILE, state="running", stage="profile", progress=None, error=None)
    profile = cheevo_ra_fetch_profile()
    _cheevo_write_status(CHEEVO_RETRO_STATUS_FILE, state="running", stage="games", progress=None)
    progress_list = cheevo_ra_fetch_completion_progress()
    cheevo_ra_generate_report(profile, progress_list, [], [], game_details={})
    _cheevo_write_status(CHEEVO_RETRO_STATUS_FILE, state="running", stage="game_details", progress=None)
    game_details = cheevo_ra_fetch_game_details(progress_list)
    _cheevo_write_status(CHEEVO_RETRO_STATUS_FILE, state="running", stage="awards", progress=None)
    awards = cheevo_ra_fetch_awards()
    recent = cheevo_ra_fetch_recent_achievements()
    _cheevo_write_status(CHEEVO_RETRO_STATUS_FILE, state="running", stage="report", progress=None)
    cheevo_ra_generate_report(profile, progress_list, awards, recent, game_details)


def _cheevo_ra_run_pipeline(mode):
    global _cheevo_ra_pipeline_running
    try:
        cheevo_validate_retro_config()
        if mode == "full":
            _cheevo_ra_run_full_pipeline()
        else:
            _cheevo_ra_run_quick_pipeline()
        _cheevo_write_status(CHEEVO_RETRO_STATUS_FILE, state="done", stage=None, progress=None, last_success_at=_cheevo_now_iso(), error=None)
        print(f"[cheevoscope] обновление (RA, {mode}) завершено успешно", flush=True)
    except Exception as e:
        print(f"[cheevoscope] ошибка обновления (RA, {mode}): {e}", flush=True)
        _cheevo_write_status(CHEEVO_RETRO_STATUS_FILE, state="error", error=str(e))
    finally:
        with _cheevo_ra_pipeline_lock:
            _cheevo_ra_pipeline_running = False


def cheevo_ra_start_refresh(mode="quick"):
    if mode not in ("quick", "full"):
        raise ValueError(f"неизвестный режим обновления: {mode!r}")
    global _cheevo_ra_pipeline_running
    with _cheevo_ra_pipeline_lock:
        if _cheevo_ra_pipeline_running:
            return False
        _cheevo_ra_pipeline_running = True
    threading.Thread(target=_cheevo_ra_run_pipeline, args=(mode,), daemon=True).start()
    return True


# ============================================================
# Модалка "все ачивки" — порт achievement_details.py
# ============================================================

# ============================================================
# Кэш иконок ачивок на диске — раньше картинки в модалке "все ачивки"
# всегда грузились НАПРЯМУЮ с CDN Steam/RA при каждом открытии, из
# браузера пользователя — медленно и зависит от доступности чужого CDN.
# Иконки практически никогда не меняются после публикации, поэтому раз
# скачали — храним бессрочно (без TTL, в отличие от игровых данных).
# ============================================================

def _cheevo_cache_icon(url, prefix):
    """Скачивает иконку (если ещё не скачана) и возвращает ЛОКАЛЬНОЕ имя
    файла — фронтенд отдаёт его через cheevoscope_local_image_proxy, а не
    напрямую как абсолютный URL внешнего CDN."""
    if not url:
        return None
    basename = url.split("/")[-1].split("?")[0]
    if not basename:
        return None
    # Префикс разводит по играм/платформам — на случай совпадения имени
    # файла на разных CDN (маловероятно, но дёшево подстраховаться).
    local_filename = f"{prefix}_{basename}"
    local_path = os.path.join(CHEEVO_IMAGES_DIR, local_filename)
    if os.path.exists(local_path):
        return local_filename
    data = cheevo_download_image_bytes(url)
    if data is None:
        return None
    try:
        os.makedirs(CHEEVO_IMAGES_DIR, exist_ok=True)
        with open(local_path, "wb") as f:
            f.write(data)
    except OSError:
        return None
    return local_filename


def cheevo_get_steam_game_achievements(appid):
    schema = cheevo_cached_call(f"schema_ru_{appid}", lambda: cheevo_get_schema_for_game(appid),
                                 ttl_hours=CHEEVO_ACHIEVEMENT_SCHEMA_CACHE_TTL_HOURS)
    if not schema:
        return {"appid": appid, "available": False, "achievements": []}

    global_pct = cheevo_cached_call(f"global_pct_{appid}", lambda: cheevo_get_global_achievement_percentages(appid),
                                     ttl_hours=CHEEVO_CACHE_TTL_HOURS)
    pct_by_name = {a["name"]: a.get("percent") for a in global_pct}

    # cheevo_get_player_achievements раньше вызывался напрямую при КАЖДОМ
    # открытии модалки — ни разу не заглядывая в кэш вообще, даже если
    # основной пайплайн обновления только что получил те же данные. У
    # основного кэша (player_ach_{appid}) TTL для активно играемых игр
    # намеренно 0 (см. _cheevo_achievements_cache_ttl_hours — плановое
    # обновление должно видеть свежий прогресс), но для МОДАЛКИ, открытой
    # руками, это не годится: два клика по одной игре подряд означали два
    # похода в Steam подряд. Сначала проверяем общий кэш (бесплатный выигрыш
    # для завершённых/нулевых игр — там TTL и так большой), если он "не
    # свежий" — свой короткий кэш только для модалки (15 минут), и только
    # если оба промахнулись — идём в сеть.
    cache_key = f"player_ach_{appid}"
    modal_cache_key = f"player_ach_modal_{appid}"
    player_data = None
    shared_cached = cheevo_cache_get_with_age(cache_key)
    if shared_cached is not None:
        cached_data, age_hours = shared_cached
        if age_hours <= _cheevo_achievements_cache_ttl_hours(cached_data):
            player_data = cached_data
    if player_data is None:
        player_data = cheevo_cache_get(modal_cache_key, ttl_hours=0.25)
    if player_data is None:
        player_data = cheevo_get_player_achievements(appid)
        if not player_data.get("transient_error"):
            cheevo_cache_set(modal_cache_key, player_data)
            # Заодно обновляем и общий кэш — основной пайплайн тоже
            # выиграет от уже свежих данных, не будет дёргать Steam повторно
            # сразу после того, как пользователь сам открыл модалку.
            cheevo_cache_set(cache_key, player_data)
    unlocked_by_name = {a["apiname"]: a.get("unlocktime") for a in player_data.get("achievements", []) if a.get("achieved") == 1}

    achievements = []
    for a in schema:
        apiname = a.get("name")
        raw_percent = pct_by_name.get(apiname)
        percent = None
        if raw_percent is not None:
            try:
                percent = float(raw_percent)
            except (TypeError, ValueError):
                percent = None
        achievements.append({
            "apiname": apiname, "name": a.get("displayName", apiname), "description": a.get("description", ""),
            "icon": a.get("icon", ""), "icon_gray": a.get("icongray", ""),
            "global_percent": round(percent, 1) if percent is not None else None,
            "unlocked": apiname in unlocked_by_name, "unlock_time": unlocked_by_name.get(apiname),
        })
    achievements.sort(key=lambda a: (a["global_percent"] is None, a["global_percent"] or 0))

    # Кэшируем иконки на диск ПАРАЛЛЕЛЬНО (в игре может быть и 100+ ачивок —
    # последовательно было бы заметно медленно) и подменяем URL внешнего
    # CDN на локальное имя файла — фронтенд отдаёт его через
    # cheevoscope_local_image_proxy при следующих открытиях модалки.
    def _cache_both_icons(a):
        return (
            _cheevo_cache_icon(a["icon"], f"ach{appid}"),
            _cheevo_cache_icon(a["icon_gray"], f"achgray{appid}"),
        )

    with ThreadPoolExecutor(max_workers=10) as pool:
        cached_pairs = list(pool.map(_cache_both_icons, achievements))
    for a, (icon_local, icon_gray_local) in zip(achievements, cached_pairs):
        a["icon"] = icon_local
        a["icon_gray"] = icon_gray_local

    return {"appid": appid, "available": True, "achievements": achievements}


def cheevo_get_retro_game_achievements(game_id):
    cache_key = f"retro_detail_{game_id}"
    cached = cheevo_cache_get_with_age(cache_key)
    detail = None
    if cached is not None:
        data, age_hours = cached
        if age_hours <= 6 and isinstance(data, dict):
            detail = data
    if detail is None:
        detail = cheevo_ra_get_game_info_and_user_progress(game_id)
        if detail:
            cheevo_cache_set(cache_key, detail)

    if not detail or not detail.get("Achievements"):
        return {"game_id": game_id, "available": False, "achievements": []}

    total_players = detail.get("NumDistinctPlayersHardcore") or detail.get("NumDistinctPlayersCasual") or 0
    achievements_raw = detail.get("Achievements")
    if not isinstance(achievements_raw, dict):
        return {"game_id": game_id, "available": False, "achievements": []}

    achievements = []
    for a in achievements_raw.values():
        if not isinstance(a, dict):
            continue
        num_awarded_hc = a.get("NumAwardedHardcore") or 0
        rarity_hardcore = round(100 * num_awarded_hc / total_players, 1) if total_players else None
        achievements.append({
            "id": a.get("ID"), "name": a.get("Title", ""), "description": a.get("Description", ""),
            "points": a.get("Points", 0),
            "badge_url": f"https://retroachievements.org/Badge/{a.get('BadgeName')}.png" if a.get("BadgeName") else "",
            "global_percent": rarity_hardcore, "unlocked": bool(a.get("DateEarned")),
            "unlocked_hardcore": bool(a.get("DateEarnedHardcore")),
            "unlock_time": a.get("DateEarnedHardcore") or a.get("DateEarned"),
        })
    achievements.sort(key=lambda a: (a["global_percent"] is None, a["global_percent"] or 0))

    with ThreadPoolExecutor(max_workers=10) as pool:
        cached_badges = list(pool.map(lambda a: _cheevo_cache_icon(a["badge_url"], "rabadge"), achievements))
    for a, badge_local in zip(achievements, cached_badges):
        a["badge_url"] = badge_local

    return {"game_id": game_id, "available": True, "achievements": achievements}


# ============================================================
# Фоновое почасовое обновление — замена systemd-таймера/hourly_refresh.py
# оригинала. Тот же принцип, что ntfy_push_worker (см. ниже) — фоновый
# поток внутри уже работающего процесса хаба, не отдельный cron/systemd.
# ============================================================

def cheevo_hourly_worker():
    while True:
        time.sleep(3600)
        try:
            if _cheevo_steam_api_key() and _cheevo_steam_id():
                print("[cheevoscope] почасовая автопроверка: Steam (quick)", flush=True)
                _cheevo_run_pipeline_sync_safe("quick")
        except Exception as e:
            print(f"[cheevoscope] почасовая автопроверка: Steam не выполнен — {e}", flush=True)

        try:
            if _cheevo_ra_username() and _cheevo_ra_api_key():
                print("[cheevoscope] почасовая автопроверка: RetroAchievements (quick)", flush=True)
                _cheevo_run_ra_pipeline_sync_safe("quick")
        except Exception as e:
            print(f"[cheevoscope] почасовая автопроверка: RetroAchievements не выполнен — {e}", flush=True)


def _cheevo_run_pipeline_sync_safe(mode):
    """Синхронный вызов пайплайна Steam для фонового потока — не через
    start_refresh (тот только СТАВИТ отдельный поток и сразу возвращается),
    напрямую и с той же защитой от параллельного запуска."""
    global _cheevo_pipeline_running
    with _cheevo_pipeline_lock:
        if _cheevo_pipeline_running:
            print("[cheevoscope] обновление уже идёт — пропускаю (Steam)", flush=True)
            return
        _cheevo_pipeline_running = True
    _cheevo_run_pipeline(mode)


def _cheevo_run_ra_pipeline_sync_safe(mode):
    global _cheevo_ra_pipeline_running
    with _cheevo_ra_pipeline_lock:
        if _cheevo_ra_pipeline_running:
            print("[cheevoscope] обновление уже идёт — пропускаю (RA)", flush=True)
            return
        _cheevo_ra_pipeline_running = True
    _cheevo_ra_run_pipeline(mode)


# ============================================================
# Точки входа для виджета хаба — та же форма данных, что раньше отдавал
# отдельный контейнер по HTTP, только теперь считается нативно на месте.
# ============================================================

def widget_cheevoscope():
    try:
        cheevo_validate_config()
    except RuntimeError as e:
        return {"error": str(e)}

    steam_report = _cheevo_load_json_file(CHEEVO_REPORT_JSON_FILE, None)
    if steam_report is None:
        return {
            "generated_at": None,
            "status": {"steam": _cheevo_read_status(CHEEVO_STATUS_FILE), "retro": None},
            "steam": {"summary": {}, "games": [], "rarity_tiers": {}, "rarest": [], "heatmap": {}},
            "retro": None,
        }

    retro_report = {}
    if _cheevo_ra_username() and _cheevo_ra_api_key():
        retro_report = cheevo_ra_load_retro_report()

    retro_summary = (retro_report or {}).get("summary") or {}
    has_retro = bool(retro_summary.get("games_count"))

    steam_status = _cheevo_read_status(CHEEVO_STATUS_FILE)
    retro_status = _cheevo_read_status(CHEEVO_RETRO_STATUS_FILE) if has_retro else None

    return {
        "generated_at": steam_report.get("generated_at"),
        "status": {
            "steam": steam_status,
            "retro": retro_status,
        },
        "steam": {
            "summary": steam_report.get("summary") or {},
            "games": steam_report.get("games_grid") or [],
            "rarity_tiers": steam_report.get("rarity_tiers") or {},
            "rarest": steam_report.get("rarest_achievements") or [],
            "heatmap": steam_report.get("activity_heatmap") or {},
        },
        "retro": {
            "profile": retro_report.get("profile") or {},
            "summary": retro_summary,
            "games": retro_report.get("games") or [],
            "points_by_console": retro_report.get("points_by_console") or {},
            "rarity_tiers": retro_report.get("rarity_tiers") or {},
            "rarest": retro_report.get("rarest_achievements") or [],
            "awards": retro_report.get("awards") or [],
            "recent": retro_report.get("recent_achievements") or [],
        } if has_retro else None,
    }


def widget_cheevoscope_refresh(handler, query):
    """POST /api/cheevoscope/refresh?mode=quick|full — запускает нативное
    обновление в фоновом потоке (не проксирует никуда, раньше здесь был
    HTTP-запрос к отдельному контейнеру)."""
    mode = (query.get("mode", ["quick"])[0] or "quick")
    if mode not in ("quick", "full"):
        handler._send_json({"error": f"неизвестный режим обновления: {mode!r}"}, status=400)
        return

    results = {}
    try:
        started = cheevo_start_refresh(mode)
        results["steam"] = {"started": started, "mode": mode} if started else {"started": False, "message": "обновление уже идёт"}
    except RuntimeError as e:
        results["steam"] = {"error": str(e)}

    if _cheevo_ra_username() and _cheevo_ra_api_key():
        try:
            started = cheevo_ra_start_refresh(mode)
            results["retro"] = {"started": started, "mode": mode} if started else {"started": False, "message": "обновление уже идёт"}
        except RuntimeError as e:
            results["retro"] = {"error": str(e)}

    handler._send_json(results)


def widget_cheevoscope_achievements(handler, appid):
    """GET /api/cheevoscope/game/<appid>/achievements — модалка "все ачивки" (Steam)."""
    if not (appid or "").isdigit():
        handler._send_json({"available": False, "achievements": [], "error": "некорректный appid"}, status=400)
        return
    try:
        handler._send_json(cheevo_get_steam_game_achievements(int(appid)))
    except Exception as e:
        handler._send_json({"available": False, "achievements": [], "error": str(e)})


def widget_cheevoscope_retro_achievements(handler, game_id):
    """GET /api/cheevoscope/retro/game/<id>/achievements — та же модалка, источник RA."""
    if not (game_id or "").isdigit():
        handler._send_json({"available": False, "achievements": [], "error": "некорректный id"}, status=400)
        return
    try:
        handler._send_json(cheevo_get_retro_game_achievements(int(game_id)))
    except Exception as e:
        handler._send_json({"available": False, "achievements": [], "error": str(e)})


def cheevoscope_local_image_proxy(handler, filename):
    """GET /api/cheevoscope/local-image/<filename> — обложка игры, скачанная
    на диск хаба (см. cheevo_fetch_game_images). Раньше это был прокси на
    /static/ отдельного контейнера — теперь просто раздача своего файла,
    как у memoscope_image_proxy."""
    if not re.fullmatch(r"[\w.-]+", filename or "") or ".." in filename:
        handler.send_response(400)
        handler._security_headers()
        handler.end_headers()
        return
    path = os.path.join(CHEEVO_IMAGES_DIR, filename)
    ext = os.path.splitext(filename)[1].lower()
    content_type = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp"}.get(ext, "application/octet-stream")
    handler._send_file(path, content_type)



CHEEVOSCOPE_PYEOF

    echo "${GREEN}[✓]${NC} backend/cheevoscope.py создан: $HUB_DIR/backend/cheevoscope.py"

    echo "${CYAN}[*]${NC} Перезапускаю хаб, чтобы подхватить новый файл и ключи..."
    if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -qx dk_nexus404; then
        docker restart dk_nexus404 >/dev/null 2>>"$LOGFILE" || echo "${YELLOW}[?]${NC} Не удалось перезапустить dk_nexus404 автоматически — перезапустите вручную: docker restart dk_nexus404"
    fi

    echo "${GREEN}[✓]${NC} Шаг 2 завершён успешно"
    mark_done "step13_2"
fi

# ================== ШАГ 3 ==================
if is_done "step13_3"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 3: Карточка в хабе"
    echo "===========================================================================${NC}"

    add_hub_card "Cheevoscope" "Игровая статистика" "" "fas fa-trophy" "Сервисы" "widget" "cheevoscope-stats"
    echo "${GREEN}[✓]${NC} Карточка в хабе добавлена"

    echo ""
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  CHEEVOSCOPE НАСТРОЕН"
    echo "===========================================================================${NC}"
    echo "Откройте хаб → карточка Cheevoscope → «обновить всё» — подтянет"
    echo "список игр, достижения, картинки и цены. Дальше — раз в час хаб сам"
    echo "тихо проверяет новые достижения в фоне (без цен/отзывов/картинок —"
    echo "для этого по-прежнему нужна кнопка «обновить всё» вручную)."

    echo "${GREEN}[✓]${NC} Шаг 3 завершён успешно"
    mark_done "step13_3"
fi
