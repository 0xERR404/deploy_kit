#!/bin/bash
# =============================================================================
# MemoScope — свой блог/заметки (посты с картинкой и лёгким форматированием,
# 2 колонки на ПК). Свой лёгкий сервис — данные и вся логика живут прямо в
# самом хабе, но отдельным файлом backend/memoscope.py (не одним большим
# app.py — см. общее обсуждение архитектуры в 04_nexus404.sh), не отдельный
# docker-контейнер. Этот модуль кладёт файл рядом с app.py (тот же volume,
# ./backend:/app/backend — см. docker-compose.yml хаба) и регистрирует карточку.
#
# STATEFILE: "step15_N".
# =============================================================================

enable_full_logging

echo "${BOLD}${CYAN}==========================================================================="
echo "  ЗАМЕТКИ (MEMOSCOPE)"
echo "===========================================================================${NC}"

TOTAL_STEPS=2
DONE_COUNT=$(grep -c '^step15_' "$STATEFILE" 2>/dev/null || true)
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
if is_done "step15_1"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 1: Код виджета"
    echo "===========================================================================${NC}"

    mkdir -p "$HUB_DIR/backend"
    cat > "$HUB_DIR/backend/memoscope.py" << 'MEMOSCOPE_PYEOF'
"""memoscope.py — свой блог/заметки (посты с картинкой, лёгкое
форматирование, masonry в 2 колонки на фронтенде). Свой лёгкий виджет
хаба — живёт в том же процессе/контейнере, что и сам хаб (app.py), но
отдельным файлом для читаемости."""
import base64
import json
import os
import re
import time

from _shared import next_unique_id

# ============================================================
# MEMOSCOPE — свой блог/заметки, тоже прямо на диске хаба. Картинка к
# посту хранится файлом (не в самом JSON — не раздувать его base64),
# отдаётся через отдельный маршрут с той же проверкой сессии, что и весь
# остальной хаб (см. do_GET — этот путь НЕ в списке публичных PWA-файлов).
# ============================================================
MEMOSCOPE_FILE = "/app/data/memoscope_posts.json"
MEMOSCOPE_IMAGES_DIR = "/app/data/memoscope_images"


# ============================================================
# MEMOSCOPE
# ============================================================
def load_memoscope():
    try:
        with open(MEMOSCOPE_FILE) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return []


def save_memoscope(posts):
    with open(MEMOSCOPE_FILE, "w") as f:
        json.dump(posts, f)


def _save_memoscope_image(post_id, image_data_url):
    """image_data_url — строка "data:image/png;base64,...." из FileReader
    на клиенте. Возвращает относительное имя файла или None."""
    if not image_data_url or not image_data_url.startswith("data:"):
        return None
    try:
        header, b64data = image_data_url.split(",", 1)
        mime = header.split(";")[0].split(":")[1]
        ext = {"image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "image/gif": "gif"}.get(mime, "jpg")
        raw = base64.b64decode(b64data)
    except Exception:
        return None
    os.makedirs(MEMOSCOPE_IMAGES_DIR, exist_ok=True)
    filename = f"{post_id}.{ext}"
    with open(os.path.join(MEMOSCOPE_IMAGES_DIR, filename), "wb") as f:
        f.write(raw)
    return filename


def widget_memoscope():
    return {"posts": load_memoscope()}


def widget_memoscope_add(handler):
    content_length = int(handler.headers.get("Content-Length", 0))
    if content_length <= 0:
        handler._send_json({"error": "пустой запрос"}, status=400)
        return
    try:
        body = json.loads(handler.rfile.read(content_length))
    except json.JSONDecodeError:
        handler._send_json({"error": "некорректный JSON"}, status=400)
        return

    html = (body.get("html") or "").strip()
    if not html:
        handler._send_json({"error": "пустой пост"}, status=400)
        return

    post_id = next_unique_id()
    image_filename = _save_memoscope_image(post_id, body.get("image_data_url"))
    posts = load_memoscope()
    posts.append({
        "id": post_id,
        "date": time.strftime("%d.%m.%Y %H:%M"),
        "image": image_filename,
        "html": html,
    })
    save_memoscope(posts)
    handler._send_json({"ok": True})


def widget_memoscope_edit(handler, post_id):
    content_length = int(handler.headers.get("Content-Length", 0))
    if content_length <= 0:
        handler._send_json({"error": "пустой запрос"}, status=400)
        return
    try:
        body = json.loads(handler.rfile.read(content_length))
    except json.JSONDecodeError:
        handler._send_json({"error": "некорректный JSON"}, status=400)
        return

    posts = load_memoscope()
    post = next((p for p in posts if str(p["id"]) == str(post_id)), None)
    if not post:
        handler._send_json({"error": "пост не найден"}, status=404)
        return

    html = (body.get("html") or "").strip()
    if not html:
        handler._send_json({"error": "пустой пост"}, status=400)
        return
    post["html"] = html

    # Картинку меняем, только если реально прислали новую — "image_data_url"
    # отсутствует в body у клиента, если пользователь её не трогал при
    # редактировании (иначе при каждом сохранении текста без новой картинки
    # мы бы стирали уже загруженную).
    if "image_data_url" in body:
        if post.get("image"):
            old_path = os.path.join(MEMOSCOPE_IMAGES_DIR, post["image"])
            if os.path.exists(old_path):
                os.remove(old_path)
        post["image"] = _save_memoscope_image(post_id, body.get("image_data_url"))

    save_memoscope(posts)
    handler._send_json({"ok": True})


def widget_memoscope_delete(handler, post_id):
    posts = load_memoscope()
    post = next((p for p in posts if str(p["id"]) == str(post_id)), None)
    if not post:
        handler._send_json({"error": "пост не найден"}, status=404)
        return
    if post.get("image"):
        old_path = os.path.join(MEMOSCOPE_IMAGES_DIR, post["image"])
        if os.path.exists(old_path):
            os.remove(old_path)
    posts = [p for p in posts if str(p["id"]) != str(post_id)]
    save_memoscope(posts)
    handler._send_json({"ok": True})


def memoscope_image_proxy(handler, filename):
    """GET /api/memoscope/image/<filename> — отдаёт картинку поста.
    НЕ в списке публичных PWA-файлов — проходит обычный гейт сессии
    в do_GET, как и весь остальной хаб."""
    if not re.fullmatch(r"[\w.-]+", filename or "") or ".." in filename:
        handler.send_response(400)
        handler._security_headers()
        handler.end_headers()
        return
    path = os.path.join(MEMOSCOPE_IMAGES_DIR, filename)
    ext = os.path.splitext(filename)[1].lower()
    content_type = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp", ".gif": "image/gif"}.get(ext, "application/octet-stream")
    handler._send_file(path, content_type)


MEMOSCOPE_PYEOF

    echo "${GREEN}[✓]${NC} backend/memoscope.py создан: $HUB_DIR/backend/memoscope.py"

    echo "${CYAN}[*]${NC} Перезапускаю хаб, чтобы подхватить новый файл..."
    if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -qx dk_nexus404; then
        docker restart dk_nexus404 >/dev/null 2>>"$LOGFILE" || echo "${YELLOW}[?]${NC} Не удалось перезапустить dk_nexus404 автоматически — перезапустите вручную: docker restart dk_nexus404"
    fi

    echo "${GREEN}[✓]${NC} Шаг 1 завершён успешно"
    mark_done "step15_1"
fi

# ================== ШАГ 2 ==================
if is_done "step15_2"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 2: Карточка в хабе"
    echo "===========================================================================${NC}"

    add_hub_card "MemoScope" "Заметки" "" "fas fa-note-sticky" "Сервисы" "widget" "memoscope-posts"
    echo "${GREEN}[✓]${NC} Карточка MemoScope добавлена в хаб"

    echo "${GREEN}[✓]${NC} Шаг 2 завершён успешно"
    mark_done "step15_2"
fi

echo ""
echo "${BOLD}${GREEN}==========================================================================="
echo "  MEMOSCOPE ГОТОВ"
echo "===========================================================================${NC}"
echo "Откройте хаб — карточка MemoScope уже там. Посты, картинки и вся"
echo "логика — внутри самого хаба, отдельно настраивать здесь нечего."
echo ""
