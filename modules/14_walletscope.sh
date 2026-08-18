#!/bin/bash
# =============================================================================
# WalletScope — учёт денег в рублях (карта + депозит, переводы между ними,
# курсы USD/EUR/BTC/ETH). Свой лёгкий сервис — данные и вся логика живут
# прямо в самом хабе, но отдельным файлом backend/walletscope.py (не одним
# большим app.py — см. общее обсуждение архитектуры в 04_nexus404.sh),
# не отдельный docker-контейнер. Этот модуль кладёт файл рядом с app.py
# (тот же volume, ./backend:/app/backend — см. docker-compose.yml хаба)
# и регистрирует карточку.
#
# STATEFILE: "step14_N".
# =============================================================================

enable_full_logging

echo "${BOLD}${CYAN}==========================================================================="
echo "  УЧЁТ ФИНАНСОВ (WALLETSCOPE)"
echo "===========================================================================${NC}"

TOTAL_STEPS=2
DONE_COUNT=$(grep -c '^step14_' "$STATEFILE" 2>/dev/null || true)
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

# ================== ШАГ 1 ==================
if is_done "step14_1"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 1: Код виджета"
    echo "===========================================================================${NC}"

    mkdir -p "$HUB_DIR/backend"
    cat > "$HUB_DIR/backend/walletscope.py" << 'WALLETSCOPE_PYEOF'
"""walletscope.py — учёт денег в рублях (карта + депозит, переводы между
ними, курсы USD/EUR/BTC/ETH). Свой лёгкий виджет хаба — живёт в том же
процессе/контейнере, что и сам хаб (app.py), но отдельным файлом для
читаемости (не нужен отдельный сервер — используется только stdlib)."""
import json
import math
import os
import time

from _shared import next_unique_id, http_get

# ============================================================
# WALLETSCOPE — учёт денег в рублях, свой лёгкий виджет хаба (не отдельный
# контейнер — данные лежат прямо на диске хаба, как и push-подписки).
# Два отдельных баланса (карта/депозит) + переводы между ними + курсы
# 4 валют (кэшируются, чтобы не дёргать внешние API на каждое открытие).
# ============================================================
WALLETSCOPE_FILE = "/app/data/walletscope.json"
EXCHANGE_RATES_CACHE_FILE = "/app/data/exchange_rates_cache.json"
EXCHANGE_RATES_TTL = 600  # секунд — курсы не меняются настолько быстро


# ============================================================
# WALLETSCOPE
# ============================================================
def load_walletscope():
    try:
        with open(WALLETSCOPE_FILE) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return {"card": 0, "deposit": 0, "transactions": []}


def save_walletscope(data):
    with open(WALLETSCOPE_FILE, "w") as f:
        json.dump(data, f)


def fetch_exchange_rates():
    """Курсы USD/EUR/BTC/ETH в рублях — с кэшем на диске (EXCHANGE_RATES_TTL),
    чтобы каждое открытие виджета не дёргало внешние API. ЦБ РФ отдаёт
    USD/EUR сразу в рублях (то, что нужно — наш учёт тоже в рублях),
    CoinGecko — BTC/ETH, тоже с явным vs_currencies=rub."""
    try:
        with open(EXCHANGE_RATES_CACHE_FILE) as f:
            cached = json.load(f)
        if time.time() - cached.get("fetched_at", 0) < EXCHANGE_RATES_TTL:
            return cached["rates"]
    except (OSError, json.JSONDecodeError, KeyError):
        pass

    rates = {"usd": None, "eur": None, "btc": None, "eth": None}
    try:
        _, body = http_get("https://www.cbr-xml-daily.ru/daily_json.js", timeout=10)
        cbr = json.loads(body)
        rates["usd"] = round(cbr["Valute"]["USD"]["Value"], 2)
        rates["eur"] = round(cbr["Valute"]["EUR"]["Value"], 2)
    except Exception:
        pass
    try:
        _, body = http_get("https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=rub", timeout=10)
        cg = json.loads(body)
        rates["btc"] = round(cg["bitcoin"]["rub"])
        rates["eth"] = round(cg["ethereum"]["rub"])
    except Exception:
        pass

    # Кэшируем, даже если что-то из двух источников не ответило — лучше
    # показать старое/частичное значение, чем ничего, и не долбить внешний
    # API на каждый следующий опрос виджета впустую.
    with open(EXCHANGE_RATES_CACHE_FILE, "w") as f:
        json.dump({"fetched_at": time.time(), "rates": rates}, f)
    return rates


def widget_walletscope():
    data = load_walletscope()
    data["rates"] = fetch_exchange_rates()
    return data


def widget_walletscope_add(handler):
    content_length = int(handler.headers.get("Content-Length", 0))
    if content_length <= 0:
        handler._send_json({"error": "пустой запрос"}, status=400)
        return
    try:
        body = json.loads(handler.rfile.read(content_length))
    except json.JSONDecodeError:
        handler._send_json({"error": "некорректный JSON"}, status=400)
        return

    tx_type = body.get("type")
    amount = body.get("amount")
    desc = (body.get("desc") or "").strip()[:200] or "Без описания"
    if tx_type not in ("income", "expense"):
        handler._send_json({"error": "type должен быть income или expense"}, status=400)
        return
    try:
        amount = round(float(amount), 2)
        if not math.isfinite(amount):
            amount = 0
    except (TypeError, ValueError):
        amount = 0
    if amount <= 0:
        handler._send_json({"error": "сумма должна быть больше нуля"}, status=400)
        return

    data = load_walletscope()
    data["card"] = round(data.get("card", 0) + (amount if tx_type == "income" else -amount), 2)
    data.setdefault("transactions", []).append({
        "id": next_unique_id(),
        "type": tx_type,
        "amount": amount,
        "desc": desc,
        "date": time.strftime("%d.%m.%Y %H:%M"),
    })
    save_walletscope(data)
    handler._send_json({"ok": True})


def widget_walletscope_edit(handler, tx_id):
    content_length = int(handler.headers.get("Content-Length", 0))
    if content_length <= 0:
        handler._send_json({"error": "пустой запрос"}, status=400)
        return
    try:
        body = json.loads(handler.rfile.read(content_length))
    except json.JSONDecodeError:
        handler._send_json({"error": "некорректный JSON"}, status=400)
        return

    data = load_walletscope()
    tx = next((t for t in data.get("transactions", []) if str(t["id"]) == str(tx_id)), None)
    if not tx:
        handler._send_json({"error": "запись не найдена"}, status=404)
        return

    # Откатываем старый эффект на баланс карты, потом применяем новый —
    # проще и надёжнее, чем высчитывать разницу отдельно для каждого поля.
    data["card"] = round(data["card"] - (tx["amount"] if tx["type"] == "income" else -tx["amount"]), 2)

    new_type = body.get("type", tx["type"])
    new_desc = (body.get("desc") or tx["desc"]).strip()[:200] or "Без описания"
    try:
        new_amount = round(float(body.get("amount", tx["amount"])), 2)
        if not math.isfinite(new_amount):
            new_amount = tx["amount"]
    except (TypeError, ValueError):
        new_amount = tx["amount"]
    if new_type not in ("income", "expense") or new_amount <= 0:
        handler._send_json({"error": "некорректные данные"}, status=400)
        return

    tx["type"] = new_type
    tx["amount"] = new_amount
    tx["desc"] = new_desc
    data["card"] = round(data["card"] + (new_amount if new_type == "income" else -new_amount), 2)
    save_walletscope(data)
    handler._send_json({"ok": True})


def widget_walletscope_delete(handler, tx_id):
    data = load_walletscope()
    tx = next((t for t in data.get("transactions", []) if str(t["id"]) == str(tx_id)), None)
    if not tx:
        handler._send_json({"error": "запись не найдена"}, status=404)
        return
    data["card"] = round(data["card"] - (tx["amount"] if tx["type"] == "income" else -tx["amount"]), 2)
    data["transactions"] = [t for t in data.get("transactions", []) if str(t["id"]) != str(tx_id)]
    save_walletscope(data)
    handler._send_json({"ok": True})


def widget_walletscope_transfer(handler):
    content_length = int(handler.headers.get("Content-Length", 0))
    if content_length <= 0:
        handler._send_json({"error": "пустой запрос"}, status=400)
        return
    try:
        body = json.loads(handler.rfile.read(content_length))
    except json.JSONDecodeError:
        handler._send_json({"error": "некорректный JSON"}, status=400)
        return
    try:
        amount = round(float(body.get("amount")), 2)
        if not math.isfinite(amount):
            amount = 0
    except (TypeError, ValueError):
        amount = 0

    data = load_walletscope()
    if amount <= 0 or amount > data.get("card", 0):
        handler._send_json({"error": "сумма должна быть больше нуля и не больше остатка на карте"}, status=400)
        return
    data["card"] = round(data["card"] - amount, 2)
    data["deposit"] = round(data.get("deposit", 0) + amount, 2)
    save_walletscope(data)
    handler._send_json({"ok": True})


WALLETSCOPE_PYEOF

    echo "${GREEN}[✓]${NC} backend/walletscope.py создан: $HUB_DIR/backend/walletscope.py"

    echo "${CYAN}[*]${NC} Перезапускаю хаб, чтобы подхватить новый файл..."
    if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -qx dk_nexus404; then
        docker restart dk_nexus404 >/dev/null 2>>"$LOGFILE" || echo "${YELLOW}[?]${NC} Не удалось перезапустить dk_nexus404 автоматически — перезапустите вручную: docker restart dk_nexus404"
    fi

    echo "${GREEN}[✓]${NC} Шаг 1 завершён успешно"
    mark_done "step14_1"
fi

# ================== ШАГ 2 ==================
if is_done "step14_2"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 2: Карточка в хабе"
    echo "===========================================================================${NC}"

    add_hub_card "WalletScope" "Учёт финансов" "" "fas fa-wallet" "Сервисы" "widget" "walletscope-data"
    echo "${GREEN}[✓]${NC} Карточка WalletScope добавлена в хаб"

    echo "${GREEN}[✓]${NC} Шаг 2 завершён успешно"
    mark_done "step14_2"
fi

echo ""
echo "${BOLD}${GREEN}==========================================================================="
echo "  WALLETSCOPE ГОТОВ"
echo "===========================================================================${NC}"
echo "Откройте хаб — карточка WalletScope уже там. Данные и курсы валют"
echo "подтягиваются самим хабом, отдельно настраивать здесь нечего."
echo ""
