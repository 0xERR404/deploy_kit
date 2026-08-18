#!/bin/bash
# =============================================================================
# Модуль: NEXUS404 Interface — свой хаб, замена Homer.
#
# Ставится СРАЗУ ПОСЛЕ Pocket ID и ДО ntfy/Beszel/Vaultwarden/Forgejo/остальных
# сервис-модулей — четвёртым пунктом меню (был перенесён сюда специально:
# см. историю обсуждения — раньше Homer стоял 6-м, после ntfy/Beszel, из-за
# чего добавление карточек требовало отдельной "очереди на потом"; теперь
# хаб уже живой к моменту, когда любой следующий модуль вызовет add_hub_card).
#
# STATEFILE: "step4_N".
#
# АРХИТЕКТУРА (коротко, подробности — в common.sh у hub_regenerate_config/
# add_hub_card/claim_root_domain):
#
#   - Хаб — ЕДИНСТВЕННАЯ точка входа для человека. Живёт на корневом домене
#     как default-обработчик (claim_root_domain "hub" "" ...) — то есть
#     ловит всё, что не подошло другим зарегистрированным путям (например
#     секретному пути Vaultwarden, когда тот появится).
#   - Карточки НЕ хардкожены. Любой другой модуль (сейчас и в будущем)
#     вызывает add_hub_card() из common.sh — хаб её тут же подхватывает,
#     файл data/cards.json перегенерируется целиком при каждом вызове.
#     Если какой-то модуль НЕ УСТАНОВЛЕН (Syncthing, Remnawave — что угодно
#     из ещё не готового) — просто никогда не вызовет add_hub_card, и его
#     карточки в хабе не появится. Хабу это не нужно знать заранее, ничего
#     не падает и не требует особой обработки "а если этого сервиса нет".
#   - Устанавливается ДО всех сервис-модулей специально, чтобы карточки
#     появлялись сразу по ходу установки, а не очередью "на потом" (см.
#     заголовок выше). При этом хаб прекрасно стартует и с ПУСТЫМ списком
#     карточек — фронтенд показывает "пока ничего не установлено" вместо
#     ошибки (см. index.html, .empty-state).
#   - Сервисы открываются В ТОМ ЖЕ ОКНЕ (widget-оверлей на фронтенде), не
#     новой вкладкой и НЕ чужим iframe — хаб сам через свой API забирает
#     нужные данные у сервиса (по docker-сети) и рисует их своим единым
#     UI. См. index.html, openService()/loadWidget()/renderWidget().
#   - Своего логина у хаба пока НЕТ в этом модуле — обсуждался отдельный
#     самописный auth (WalletScope/MemoScope-стиль), это отдельная задача,
#     сюда сознательно не включена, пока не попросили явно.
# =============================================================================

enable_full_logging

echo "${BOLD}${CYAN}==========================================================================="
echo "  УСТАНОВКА NEXUS404 INTERFACE"
echo "===========================================================================${NC}"

TOTAL_STEPS=4
DONE_COUNT=$(grep -c '^step4_' "$STATEFILE" 2>/dev/null || true)
DONE_COUNT="${DONE_COUNT:-0}"
if [ "$DONE_COUNT" -gt 0 ] && [ "$DONE_COUNT" -lt "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Найден файл состояния: пройдено $DONE_COUNT из $TOTAL_STEPS шагов модуля, продолжаем"
elif [ "$DONE_COUNT" -ge "$TOTAL_STEPS" ]; then
    echo "${CYAN}[*]${NC} Модуль уже был выполнен ранее (все $TOTAL_STEPS шага пройдены)"
fi
echo ""

# ================== ШАГ 1 ==================
if is_done "step4_1"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 1: Установка NEXUS404 Interface"
    echo "===========================================================================${NC}"

    if ! check_disk_space 256; then
        echo "${RED}[!]${NC} Меньше 256 MB свободного места на диске — недостаточно"
        exit 1
    fi

    mkdir -p "$HUB_DIR/html" "$HUB_DIR/data"

    # index.html не перезаписываем, если уже правили руками — как и с
    # Caddyfile/конфигами в остальных модулях.
    if [ ! -f "$HUB_DIR/html/index.html" ]; then
        cat > "$HUB_DIR/html/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>NEXUS404</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/flag-icons/7.2.3/css/flag-icons.min.css">
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='6' fill='%236c8eff'/%3E%3C/svg%3E">
<link rel="manifest" href="manifest.json">
<link rel="apple-touch-icon" href="icon-512.png">
<meta name="theme-color" content="#08090c">
<style>
  :root{
    --bg:#08090c; --panel:#0e1015; --line: rgba(108,142,255,0.18);
    --text:#d6ddff; --muted:#6d7290; --accent:#6c8eff; --amber:#ffcc66;
    --green:#66bb6a; --red:#ef5350; --card-radius:8px;
  }
  *{box-sizing:border-box;margin:0;padding:0;}
  html,body{height:100%;}
  body{ background:var(--bg); color:var(--text); font-family: ui-monospace, SFMono-Regular, "SF Mono", Consolas, "Liberation Mono", monospace; padding:clamp(16px, 4vw, 40px) clamp(12px, 3vw, 20px); min-height:100vh; box-sizing:border-box; display:flex; flex-direction:column; }
  .scanlines{ position:fixed; inset:0; z-index:0; pointer-events:none; background:repeating-linear-gradient(to bottom, rgba(255,255,255,0.025) 0px, rgba(255,255,255,0.025) 1px, transparent 1px, transparent 3px); }
  .glow{ position:fixed; inset:0; z-index:0; pointer-events:none; background:radial-gradient(circle at 50% 30%, rgba(108,142,255,0.06) 0%, transparent 60%); }
  .wrap{ max-width:960px; margin:0 auto; position:relative; z-index:1; width:100%; display:flex; flex-direction:column; flex:1; }

  /* ===== шапка ===== */
  .header-row{ display:flex; flex-wrap:wrap; justify-content:space-between; align-items:center; gap:8px 16px; margin-bottom:6px; position:sticky; top:0; z-index:50; background:var(--bg); padding:12px 8px; min-height:46px; box-sizing:border-box; border-bottom:1px solid var(--line); }
  .prompt{ color:var(--accent); font-size:0.82rem; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .prompt .user{ color:var(--amber); }
  .prompt .at{ color:var(--muted); }
  .prompt .host{ color:var(--text); }
  .prompt .colon{ color:var(--muted); }
  .prompt .path{ color:var(--accent); }
  .prompt .cmd{ color:var(--text); }
  .prompt .cursor{ display:inline-block; width:7px; height:1em; background:var(--amber); vertical-align:-2px; margin-left:2px; animation:blink 1s step-end infinite; box-shadow:0 0 12px rgba(255,204,102,0.6); }
  @keyframes blink{ 50%{ opacity:0; } }
  .status-indicator{ display:flex; align-items:center; gap:7px; font-size:0.72rem; color:var(--muted); flex-shrink:0; }
  .status-indicator .dot{ width:6px; height:6px; border-radius:50%; background:var(--amber); animation:pulse 2s ease-in-out infinite; box-shadow:0 0 10px rgba(255,204,102,0.3); }
  @keyframes pulse{ 0%,100%{ opacity:1; } 50%{ opacity:0.35; } }

  .title-block{ display:flex; align-items:center; flex-wrap:wrap; gap:10px 15px; margin:clamp(12px, 3vw, 16px) 0 clamp(16px, 4vw, 22px); border-left:3px solid var(--accent); padding-left:14px; }
  .title-block .brand{ font-size:clamp(1.05rem, 3vw, 1.35rem); font-weight:500; color:var(--text); text-transform:uppercase; letter-spacing:0.06em; }
  .title-block .brand .highlight{ color:var(--accent); text-shadow:0 0 25px rgba(108,142,255,0.4); }
  .title-block .sub{ font-size:clamp(1.05rem, 3vw, 1.35rem); color:var(--accent); text-transform:uppercase; letter-spacing:0.06em; text-shadow: 0 0 20px rgba(108,142,255,0.6); }

  /* ===== адаптивная сетка карточек =====
     Один согласованный набор брейкпоинтов на всё: 5 колонок на широких
     экранах, плавно сужается до 2 на телефоне. minmax(0,...) — не
     фиксированная ширина колонки, а честное деление доступного места,
     без "перетекания" карточек за край на промежуточных ширинах. */
  .grid{ display:grid; grid-template-columns:repeat(4, minmax(0, 1fr)); gap:14px; margin-bottom:20px; }
  .stack-grid{ grid-template-columns:1fr !important; }
  @media(max-width:1100px){ .grid{ grid-template-columns:repeat(3, minmax(0, 1fr)); } }
  @media(max-width:760px){ .grid{ grid-template-columns:repeat(2, minmax(0, 1fr)); gap:10px; } }
  @media(max-width:420px){ .grid{ grid-template-columns:1fr; } }

  .card{ background:var(--panel); border:1px solid var(--line); border-radius:var(--card-radius); padding:16px 16px 10px; transition:all 0.2s ease; cursor:pointer; text-decoration:none; color:var(--text); display:flex; flex-direction:column; justify-content:space-between; min-height:125px; box-shadow:0 0 20px rgba(108,142,255,0.04); }
  .card:hover{ border-color:var(--accent); transform:translateY(-2px); background:#12162e; box-shadow:0 0 30px rgba(108,142,255,0.1); }
  .card.static{ cursor:default; }
  .card.static:hover{ border-color:var(--line); transform:none; background:var(--panel); box-shadow:0 0 20px rgba(108,142,255,0.04); }
  .card .top { display:flex; flex-direction:column; gap:4px; }
  .card .name{ font-size:0.8rem; font-weight:500; color:var(--text); text-transform:uppercase; letter-spacing:0.04em; overflow-wrap:break-word; }
  .card .desc{ font-size:0.75rem; color:var(--muted); letter-spacing:0.02em; text-transform:uppercase; }
  .card .bottom{ display:flex; align-items:center; justify-content:space-between; margin-top:4px; padding-top:4px; border-top:1px solid var(--line); gap:8px; }
  .card .badge{ font-size:0.55rem; padding:2px 10px; border-radius:10px; background:var(--line); color:var(--muted); text-transform:uppercase; font-weight:600; letter-spacing:0.04em; transition:all 0.2s ease; white-space:nowrap; }

  .section-title{ display:flex; align-items:center; font-size:0.75rem; color:var(--amber); text-transform:uppercase; letter-spacing:0.08em; margin:14px 0 10px; padding:10px 16px; min-height:46px; box-sizing:border-box; background:var(--panel); border:1px solid var(--line); border-radius:var(--card-radius); text-shadow:0 0 12px rgba(255,204,102,0.25); overflow:hidden; }
  .empty-state{ color:var(--muted); font-size:0.8rem; padding:30px 0; text-align:center; border:1px dashed var(--line); border-radius:var(--card-radius); }
  footer{ margin-top:auto; text-align:center; font-size:0.76rem; color:var(--muted); border-top:1px solid var(--line); padding-top:14px; }

  .metrics-row{ display:flex; gap:1px; border:1px solid var(--line); margin-top:10px; box-shadow:0 0 20px rgba(108,142,255,0.04); overflow-x:auto; }
  .metrics-row .metric{ flex:1; min-width:100px; background:var(--panel); padding:8px 12px; }
  .metrics-row .metric .k{ display:block; font-size:0.55rem; color:var(--muted); text-transform:lowercase; letter-spacing:0.06em; margin-bottom:1px; }
  .metrics-row .metric .v{ font-size:0.8rem; color:var(--accent); text-shadow:0 0 20px rgba(108,142,255,0.15); white-space:nowrap; }

  /* ===== оверлей сервиса/виджета =====
     Панель (заголовок + кнопки действий + "назад") — единый flex-контейнер
     с переносом: на узких экранах кнопки action переходят на вторую
     строку, а не тычутся в кнопку "назад" впритык. */
  .service-overlay{ display:none; position:fixed; inset:0; z-index:1000; background:var(--bg); flex-direction:column; padding:clamp(16px, 4vw, 40px) clamp(12px, 3vw, 20px); box-sizing:border-box; }
  .service-overlay.open{ display:flex; }
  .service-overlay-bar{ display:flex; flex-wrap:wrap; align-items:center; justify-content:space-between; gap:8px 12px; padding:10px 16px; min-height:46px; box-sizing:border-box; border:1px solid var(--line); border-radius:var(--card-radius); background:var(--panel); font-size:0.75rem; text-transform:uppercase; letter-spacing:0.05em; color:var(--amber); text-shadow:0 0 12px rgba(255,204,102,0.25); margin:14px 0 10px; }
  .service-overlay-bar > div:first-child{ flex-wrap:wrap; row-gap:6px; }
  .service-overlay-bar .back{ background:none; border:1px solid var(--line); color:var(--text); padding:4px 14px; height:28px; box-sizing:border-box; border-radius:6px; cursor:pointer; font-family:inherit; font-size:0.75rem; display:flex; align-items:center; flex-shrink:0; }
  .service-overlay-bar .back:hover{ border-color:var(--accent); }
  .service-overlay .widget-placeholder{ flex:1; display:flex; align-items:center; justify-content:center; color:var(--muted); font-size:0.85rem; text-align:center; padding:20px; }
  .widget-body{ padding:0 0 20px; overflow-y:auto; flex:1; scrollbar-width:none; -ms-overflow-style:none; }
  .widget-body::-webkit-scrollbar{ display:none; }
  #overlayBody{ scrollbar-width:none; -ms-overflow-style:none; }
  #overlayBody::-webkit-scrollbar{ display:none; }
  .no-scrollbar{ scrollbar-width:none; -ms-overflow-style:none; }
  .no-scrollbar::-webkit-scrollbar{ display:none; }
  .widget-note{ font-size:0.6rem; color:var(--muted); text-align:center; margin-top:14px; }

  /* ===== WalletScope/MemoScope: модалки ===== */
  .ms-modal-backdrop{ position:fixed; inset:0; background:rgba(4,5,8,0.75); backdrop-filter:blur(2px); display:none; align-items:center; justify-content:center; z-index:200; padding:16px; }
  .ms-modal-backdrop.open{ display:flex; }
  .ms-modal-box{ background:var(--panel); border:1px solid var(--line); border-radius:var(--card-radius); width:100%; max-width:640px; max-height:90vh; display:flex; flex-direction:column; box-shadow:0 20px 60px rgba(0,0,0,0.5); }
  .ms-modal-header{ display:flex; justify-content:space-between; align-items:center; gap:10px; padding:14px 18px; border-bottom:1px solid var(--line); }
  .ms-modal-header .title{ font-size:0.85rem; text-transform:uppercase; letter-spacing:0.05em; color:var(--accent); overflow-wrap:break-word; }
  .ms-modal-body{ padding:18px; overflow-y:auto; flex:1; }
  .ms-modal-footer{ padding:14px 18px; border-top:1px solid var(--line); display:flex; flex-wrap:wrap; justify-content:flex-end; gap:8px; }
  .ms-field{ margin-bottom:14px; }
  .ms-field label{ display:block; font-size:0.7rem; color:var(--muted); text-transform:uppercase; letter-spacing:0.05em; margin-bottom:6px; }
  .ms-field input[type=text], .ms-field input[type=number]{ width:100%; background:var(--bg); border:1px solid var(--line); border-radius:6px; color:var(--text); font-family:inherit; font-size:0.85rem; padding:9px 10px; box-sizing:border-box; }
  .ms-field input[type=file]{ font-size:0.75rem; color:var(--muted); max-width:100%; }
  .ms-btn{ font-family:inherit; font-size:0.75rem; background:none; border:1px solid var(--line); color:var(--text); border-radius:6px; padding:7px 14px; cursor:pointer; }
  .ms-btn.primary{ background:rgba(108,142,255,0.12); color:var(--accent); }
  .ms-editor-toolbar{ display:flex; gap:4px; margin-bottom:8px; flex-wrap:wrap; }
  .ms-editor-toolbar button{ font-family:inherit; font-size:0.75rem; background:var(--bg); border:1px solid var(--line); color:var(--text); border-radius:5px; padding:5px 9px; cursor:pointer; min-width:30px; }
  .ms-editor-toolbar button:hover{ background:rgba(108,142,255,0.1); color:var(--accent); }
  .ms-editor-toolbar button.b{ font-weight:700; }
  .ms-editor-toolbar button.i{ font-style:italic; }
  .ms-editor-toolbar button.u{ text-decoration:underline; }
  #memoEditorArea{ min-height:180px; background:var(--bg); border:1px solid var(--line); border-radius:6px; padding:12px; font-size:0.85rem; line-height:1.6; color:var(--text); outline:none; overflow-wrap:break-word; }
  #memoEditorArea h1{ font-size:1.1rem; margin:0 0 8px; }
  #memoEditorArea h2{ font-size:1rem; margin:0 0 8px; }
  #memoEditorArea ul, #memoEditorArea ol{ margin:8px 0; padding-left:20px; }
  #memoImagePreview{ margin-top:10px; max-width:100%; max-height:140px; border-radius:6px; display:none; }

  /* ===== WalletScope: сводка/курсы/операции — своя адаптивная сетка,
     отдельная от .grid (у неё две ощутимо разные по смыслу колонки, а не
     N одинаковых карточек), сужается до одной колонки раньше общей сетки,
     чтобы крупные суммы не переносились криво. ===== */
  .wallet-balances{ display:grid; grid-template-columns:repeat(2, minmax(0, 1fr)); gap:14px; margin-bottom:16px; }
  @media(max-width:520px){ .wallet-balances{ gap:8px; } }
  .balance-card{ display:flex; flex-direction:column; gap:8px; min-width:0; }
  .balance-label{ font-size:0.7rem; text-transform:uppercase; letter-spacing:0.05em; color:var(--muted); }
  .balance-amount{ font-size:clamp(1.25rem, 5vw, 1.6rem); font-weight:600; overflow-wrap:break-word; }
  .rates-row{ display:grid; grid-template-columns:repeat(4, minmax(0, 1fr)); gap:8px; margin-bottom:16px; }
  @media(max-width:520px){ .rates-row{ grid-template-columns:repeat(2, minmax(0, 1fr)); } }
  .rate-chip{ border:1px solid var(--line); border-radius:6px; padding:8px 10px; font-size:0.75rem; display:flex; flex-direction:column; gap:2px; min-width:0; }
  .rate-chip .sym{ color:var(--muted); font-size:0.65rem; text-transform:uppercase; }
  .rate-chip .val{ color:var(--text); font-weight:600; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .tx-row{ display:flex; align-items:center; gap:10px; padding:10px 0; border-top:1px solid var(--line); flex-wrap:wrap; }
  .tx-row:first-child{ border-top:none; }
  .tx-desc{ flex:1; min-width:120px; }
  .tx-desc .title{ font-size:0.85rem; overflow-wrap:break-word; }
  .tx-desc .meta{ font-size:0.7rem; color:var(--muted); margin-top:2px; }
  .tx-amount{ font-size:0.9rem; font-weight:600; white-space:nowrap; }
  .tx-amount.income{ color:var(--green); }
  .tx-amount.expense{ color:var(--red); }
  .tx-row .actions{ display:flex; gap:4px; opacity:0.5; flex-shrink:0; }
  .tx-row:hover .actions{ opacity:1; }

  /* ===== MemoScope: посты ===== */
  .memo-columns{ display:flex; gap:14px; align-items:flex-start; }
  .memo-col{ display:flex; flex-direction:column; gap:14px; flex:1; min-width:0; }
  .memo-post img{ width:100%; border-radius:6px; margin-bottom:10px; display:block; object-fit:cover; max-height:220px; }
  .memo-post .post-date{ font-size:0.65rem; color:var(--muted); margin-bottom:6px; text-transform:uppercase; letter-spacing:0.05em; }
  .memo-post .post-body{ font-size:0.85rem; line-height:1.55; overflow-wrap:break-word; }
  .memo-post .post-body h1{ font-size:1.1rem; margin:0 0 8px; color:var(--text); }
  .memo-post .post-body h2{ font-size:1rem; margin:0 0 8px; color:var(--text); }
  .memo-post .post-body ul, .memo-post .post-body ol{ margin:8px 0; padding-left:20px; }
  .memo-post .post-actions{ display:flex; gap:6px; margin-top:10px; flex-wrap:wrap; }

  @media(max-width:600px){
    .header-row{ gap:6px 10px; }
    .prompt .cmd{ display:none; }
    .status-indicator{ font-size:0.66rem; gap:5px; }
    .title-block{ padding-left:10px; }
    .section-title, .service-overlay-bar{ font-size:0.65rem; }
    .card{ padding:12px 12px 8px; min-height:110px; }
    .card .name{ font-size:0.8rem; }
    .card .desc{ font-size:0.68rem; }
  }
  @media(max-width:420px){
    .metrics-row{ flex-wrap:nowrap; }
    .metrics-row .metric{ min-width:0; padding:6px 8px; text-align:center; }
    .metrics-row .metric .k{ font-size:0.5rem; }
    .metrics-row .metric .v{ font-size:0.65rem; }
    footer{ font-size:0.65rem; padding-top:10px; margin-top:16px; }
  }
</style>
</head>
<body>
<div class="scanlines"></div>
<div class="glow"></div>
<div class="wrap">
  <div class="header-row">
    <div class="prompt"><span class="user">0xERR404</span><span class="at">@</span><span class="host js-domain" id="domain">localhost</span><span class="colon">:</span><span class="path">~$</span> <span class="cmd">./nexus404</span><span class="cursor"></span></div>
    <div class="status-indicator"><span class="dot"></span>online<a href="#" onclick="togglePushSubscription();return false;" class="js-push-toggle" style="margin-left:14px;color:var(--muted);text-decoration:none;">[уведомления: ...]</a><a href="/logout" style="margin-left:14px;color:var(--muted);text-decoration:none;">[выйти]</a></div>
  </div>
  <div class="title-block">
    <div class="brand"><span class="highlight">NEXUS404</span></div>
    <span class="sub">interface</span>
  </div>
  <div id="groups"></div>
  <div class="metrics-row">
    <div class="metric"><span class="k">отклик</span><span class="v" id="ping">— ms</span></div>
    <div class="metric"><span class="k">аптайм</span><span class="v" id="timer">00:00</span></div>
    <div class="metric"><span class="k">сервисов</span><span class="v" id="serviceCount">0</span></div>
  </div>
  <footer><span class="js-footer-brand" id="footer-brand">NEXUS404</span> © <span class="js-year" id="year">2026</span></footer>
</div>

<div class="service-overlay" id="serviceOverlay">
  <div class="scanlines"></div>
  <div class="glow"></div>
  <div class="wrap" style="display:flex; flex-direction:column; height:100%; width:100%;">
    <div class="header-row">
      <div class="prompt"><span class="user">0xERR404</span><span class="at">@</span><span class="host js-domain">localhost</span><span class="colon">:</span><span class="path">~$</span> <span class="cmd">./nexus404</span><span class="cursor"></span></div>
      <div class="status-indicator"><span class="dot"></span>online<a href="#" onclick="togglePushSubscription();return false;" class="js-push-toggle" style="margin-left:14px;color:var(--muted);text-decoration:none;">[уведомления: ...]</a><a href="/logout" style="margin-left:14px;color:var(--muted);text-decoration:none;">[выйти]</a></div>
    </div>
    <div class="title-block">
      <div class="brand"><span class="highlight">NEXUS404</span></div>
      <span class="sub">interface</span>
    </div>
    <div class="service-overlay-bar">
      <div style="display:flex;align-items:center;gap:10px;min-width:0;flex-wrap:wrap;row-gap:6px;">
        <span id="overlayTitle">СЕРВИС</span>
        <div id="overlayActions" style="display:flex;align-items:center;gap:6px;flex-wrap:wrap;"></div>
      </div>
      <button class="back" onclick="closeOverlay()">← назад в NEXUS404</button>
    </div>
    <div id="overlayBody" style="flex:1; overflow-y:auto;"></div>
    <footer><span class="js-footer-brand">NEXUS404</span> © <span class="js-year">2026</span></footer>
  </div>
</div>

<!-- WalletScope: транзакция -->
<div class="ms-modal-backdrop" id="walletTxModalBackdrop">
  <div class="ms-modal-box">
    <div class="ms-modal-header"><span class="title" id="walletTxModalTitle">Добавить доход</span><button class="ms-btn" onclick="closeWalletModal('walletTxModalBackdrop')">✕</button></div>
    <div class="ms-modal-body">
      <div class="ms-field"><label>Сумма, ₽</label><input type="number" id="walletTxAmount" placeholder="0"></div>
      <div class="ms-field"><label>Описание</label><input type="text" id="walletTxDesc" placeholder="например, ЗП за август"></div>
    </div>
    <div class="ms-modal-footer"><button class="ms-btn" onclick="closeWalletModal('walletTxModalBackdrop')">Отмена</button><button class="ms-btn primary" onclick="walletSaveTx()">Сохранить</button></div>
  </div>
</div>

<!-- WalletScope: перевод на депозит -->
<div class="ms-modal-backdrop" id="walletTransferModalBackdrop">
  <div class="ms-modal-box">
    <div class="ms-modal-header"><span class="title">Перевести на депозит</span><button class="ms-btn" onclick="closeWalletModal('walletTransferModalBackdrop')">✕</button></div>
    <div class="ms-modal-body"><div class="ms-field"><label>Сумма, ₽ (доступно на карте: <span id="walletTransferAvailable"></span>)</label><input type="number" id="walletTransferAmount" placeholder="0"></div></div>
    <div class="ms-modal-footer"><button class="ms-btn" onclick="closeWalletModal('walletTransferModalBackdrop')">Отмена</button><button class="ms-btn primary" onclick="walletSaveTransfer()">Перевести</button></div>
  </div>
</div>

<!-- MemoScope: пост -->
<div class="ms-modal-backdrop" id="memoPostModalBackdrop">
  <div class="ms-modal-box" style="max-width:720px;">
    <div class="ms-modal-header"><span class="title" id="memoPostModalTitle">Новый пост</span><button class="ms-btn" onclick="closeMemoModal()">✕</button></div>
    <div class="ms-modal-body">
      <div class="ms-editor-toolbar">
        <button class="b" onclick="memoFmt('bold')" title="Жирный">Ж</button>
        <button class="i" onclick="memoFmt('italic')" title="Курсив">К</button>
        <button class="u" onclick="memoFmt('underline')" title="Подчёркнутый">Ч</button>
        <button onclick="memoFmt('formatBlock','H1')" title="Заголовок">H1</button>
        <button onclick="memoFmt('formatBlock','H2')" title="Подзаголовок">H2</button>
        <button onclick="memoFmt('insertUnorderedList')" title="Маркированный список">•—</button>
        <button onclick="memoFmt('insertOrderedList')" title="Нумерованный список">1.—</button>
        <button onclick="memoFmt('formatBlock','P')" title="Обычный текст">¶</button>
      </div>
      <div id="memoEditorArea" contenteditable="true"></div>
      <div class="ms-field" style="margin-top:14px;">
        <label>Картинка к посту (появится сверху)</label>
        <input type="file" id="memoImageInput" accept="image/*" onchange="memoPreviewImage(event)">
        <img id="memoImagePreview">
      </div>
    </div>
    <div class="ms-modal-footer"><button class="ms-btn" onclick="closeMemoModal()">Отмена</button><button class="ms-btn primary" onclick="memoSavePost()">Сохранить</button></div>
  </div>
</div>

<script>
  let currentCards = [];

  async function loadCards() {
    try {
      const res = await fetch('/data/cards.json', { cache: 'no-store' });
      currentCards = await res.json();
    } catch (e) {
      currentCards = [];
    }
    renderGroups(currentCards);
    loadCardPreviews(currentCards);
  }

  function renderGroups(groups) {
    const container = document.getElementById('groups');
    const allItems = groups.flatMap(g => g.items);
    document.getElementById('serviceCount').textContent = allItems.length;

    if (allItems.length === 0) {
      container.innerHTML = `
        <div class="section-title">сервисы</div>
        <div class="empty-state">пока ничего не установлено — карточки появятся сами,<br>по мере установки модулей deploy_kit</div>
      `;
      return;
    }

    // Делим по признаку "чей это проект": Beszel/Vaultwarden/Forgejo/ntfy —
    // чужой open-source, хаб для них просто клиент к их API в отдельном
    // контейнере. WalletScope/MemoScope/Cheevoscope — все три собственные
    // проекты автора ("самописные"), написаны в одном духе — и теперь все
    // три одинаково живут прямо внутри хаба, без отдельного контейнера
    // (Cheevoscope раньше был исключением из-за requests/python-dotenv, не
    // stdlib — перенесён на urllib, технический долг устранён).
    const OWN_WIDGET_IDS = ['walletscope-data', 'memoscope-posts', 'cheevoscope-stats'];
    const services = allItems.filter(i => !OWN_WIDGET_IDS.includes(i.widget));
    const ownWidgets = allItems.filter(i => OWN_WIDGET_IDS.includes(i.widget));

    let html = '';
    if (services.length) {
      html += `<div class="section-title">сервисы</div><div class="grid">${services.map(i => renderCard(i, 'сервис')).join('')}</div>`;
    }
    if (ownWidgets.length) {
      html += `<div class="section-title">виджеты</div><div class="grid">${ownWidgets.map(i => renderCard(i, 'виджет')).join('')}</div>`;
    }
    container.innerHTML = html;
  }

  function renderCard(item, badgeLabel) {
    const safeName = escapeHtml(item.name);
    const widget = escapeHtml(item.widget || '');
    return `
      <div class="card" data-widget="${widget}"
           onclick="openService('${safeName}', '${widget}')">
        <div class="top">
          <div class="name">${safeName}</div>
          <div class="desc">${escapeHtml(item.subtitle || '')}</div>
          <div class="card-preview" style="margin-top:4px;display:flex;flex-direction:column;gap:2px;"></div>
        </div>
        <div class="bottom">
          <span class="badge" style="background:var(--line);color:var(--muted);">${escapeHtml(badgeLabel)}</span>
        </div>
      </div>
    `;
  }

  // Подтягивает краткую сводку в каждую карточку-виджет на главном экране —
  // не весь виджет, только одна строка (число/статус), чтобы не заходить
  // внутрь ради простого взгляда "всё ли в порядке".
  async function loadCardPreviews(groups) {
    const items = groups.flatMap(g => g.items).filter(i => i.mode === 'widget' && i.widget);
    for (const item of items) {
      try {
        const res = await fetch(`/api/widgets/${item.widget}`, { cache: 'no-store' });
        const data = await res.json();
        const card = document.querySelector(`.card[data-widget="${item.widget}"] .card-preview`);
        if (!card) continue;
        if (data.error) { card.innerHTML = ''; continue; }
        const lines = summarizeWidget(item.widget, data);
        card.innerHTML = lines.map(line => `<div style="color:var(--accent);font-size:0.8rem;">${escapeHtml(line)}</div>`).join('');
      } catch (e) { /* тихо — это необязательное превью, не основная функция */ }
    }
  }

  function summarizeWidget(widgetId, d) {
    if (widgetId === 'beszel-metrics') {
      const systems = d.systems || [];
      if (!systems.length) return [];
      const first = systems[0];
      return [
        `cpu: ${first.cpu_pct}%`,
        `ram: ${first.mem_pct}%`
      ];
    }
    if (widgetId === 'vaultwarden-meta') {
      if (d.users == null) return [];
      return [`${d.users} пользователей`, `${d.items} записей`];
    }
    if (widgetId === 'ntfy-feed') {
      const messages = d.messages || [];
      const n = messages.length;
      const lines = [`${n} за 24ч`];
      if (n > 0) lines.push(`посл.: ${formatNtfyTime(messages[0].time).slice(11)}`);
      return lines;
    }
    if (widgetId === 'forgejo-repos') {
      const repos = d.repos || [];
      if (!repos.length) return [];
      const totalKb = repos.reduce((s, r) => s + (r.size_kb || 0), 0);
      return [`${repos.length} репозитори${repos.length === 1 ? 'й' : 'ев'}`, formatKb(totalKb) + ' всего'];
    }
    if (widgetId === 'cheevoscope-stats') {
      const s = d.steam || {};
      if (!s.games_count) return [];
      return [`${s.games_count} игр, ${s.total_hours}ч`, `ачивок: ${s.achievements_overall_percent ?? 0}%`];
    }
    if (widgetId === 'walletscope-data') {
      return [`карта: ${formatRub(d.card)}`, `депозит: ${formatRub(d.deposit)}`];
    }
    if (widgetId === 'memoscope-posts') {
      const posts = d.posts || [];
      if (!posts.length) return [];
      return [`постов: ${posts.length}`];
    }
    return [];
  }

  // Список стран по-русски -> ISO 3166-1 alpha-2. Ищем вхождение названия
  // страны в имени сервера (регистр не важен) и рисуем флаг рядом — Beszel
  // сам по себе страну не хранит (нет такого поля, проверено по исходникам),
  // весь способ — распознавание по свободному тексту имени.
  const COUNTRY_CODES = {
    'россия': 'RU', 'украина': 'UA', 'беларусь': 'BY', 'белоруссия': 'BY',
    'казахстан': 'KZ', 'узбекистан': 'UZ', 'армения': 'AM', 'грузия': 'GE',
    'азербайджан': 'AZ', 'молдова': 'MD', 'германия': 'DE', 'франция': 'FR',
    'нидерланды': 'NL', 'голландия': 'NL', 'финляндия': 'FI', 'швеция': 'SE',
    'норвегия': 'NO', 'польша': 'PL', 'литва': 'LT', 'латвия': 'LV',
    'эстония': 'EE', 'чехия': 'CZ', 'словакия': 'SK', 'австрия': 'AT',
    'швейцария': 'CH', 'италия': 'IT', 'испания': 'ES', 'португалия': 'PT',
    'великобритания': 'GB', 'англия': 'GB', 'ирландия': 'IE', 'бельгия': 'BE',
    'дания': 'DK', 'исландия': 'IS', 'турция': 'TR', 'кипр': 'CY',
    'греция': 'GR', 'болгария': 'BG', 'румыния': 'RO', 'венгрия': 'HU',
    'сербия': 'RS', 'хорватия': 'HR', 'сша': 'US', 'америка': 'US',
    'канада': 'CA', 'мексика': 'MX', 'бразилия': 'BR', 'аргентина': 'AR',
    'япония': 'JP', 'китай': 'CN', 'корея': 'KR', 'индия': 'IN',
    'сингапур': 'SG', 'индонезия': 'ID', 'вьетнам': 'VN', 'таиланд': 'TH',
    'оаэ': 'AE', 'эмираты': 'AE', 'израиль': 'IL', 'австралия': 'AU',
  };

  function extractCountry(name) {
    const lower = (name || '').toLowerCase();
    for (const key in COUNTRY_CODES) {
      const idx = lower.indexOf(key);
      if (idx !== -1) {
        const code = COUNTRY_CODES[key].toLowerCase();
        const flag = `<span class="fi fi-${code}" style="border-radius:2px;"></span>`;
        // Убираем слово страны из отображаемого имени (и лишний пробел
        // перед/после него), остаётся только "Сервер #1", а не
        // "Сервер #1 Россия" рядом с флагом — флаг сам говорит за страну.
        const cleaned = (name || '').replace(new RegExp(key, 'i'), '').replace(/\s+/g, ' ').trim();
        return { flag, cleaned };
      }
    }
    return { flag: '', cleaned: name || '' };
  }

  function escapeHtml(s) {
    return String(s || '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  }

  // Автообновление в реальном времени для открытого виджета Beszel — сам
  // Beszel обновляет метрики раз в несколько секунд на своей стороне,
  // но наш виджет раньше подгружал их один раз при открытии и больше не
  // трогал, пока не закроешь/откроешь заново. taймер запускается только
  // на время, пока оверлей с этим виджетом открыт (см. closeOverlayDom).
  let widgetAutoRefreshTimer = null;
  const WIDGET_AUTOREFRESH_MS = {
    'beszel-metrics': 5000,
  };

  function openService(name, widget) {
    const overlay = document.getElementById('serviceOverlay');
    document.getElementById('overlayTitle').textContent = name;
    document.getElementById('overlayActions').innerHTML = '';
    const body = document.getElementById('overlayBody');
    body.innerHTML = `<div class="widget-placeholder">загрузка данных...</div>`;
    loadWidget(widget, body);
    const interval = WIDGET_AUTOREFRESH_MS[widget];
    if (interval) {
      widgetAutoRefreshTimer = setInterval(() => loadWidget(widget, body, true), interval);
    }
    overlay.classList.add('open');
    // Добавляем запись в историю браузера — без этого системная кнопка
    // "назад" на Android (и жест "назад" в PWA, добавленном на экран)
    // закрывала бы всё приложение целиком, а не оверлей.
    history.pushState({ nexusOverlay: true }, '', location.href);
  }

  // silent=true — тихое фоновое обновление (для автообновления по
  // таймеру): не показываем "загрузка данных..." заново (не мигаем
  // существующим содержимым) и при сетевой ошибке просто пропускаем
  // такт, оставляя последние известные данные на экране, а не заменяя их
  // сообщением об ошибке — единичный неудачный опрос не повод стирать то,
  // что человек уже видит.
  async function loadWidget(widgetId, container, silent) {
    let data;
    try {
      const res = await fetch(`/api/widgets/${widgetId}`, { cache: 'no-store' });
      data = await res.json();
    } catch (e) {
      if (silent) return;
      container.innerHTML = `<div class="widget-placeholder">не удалось связаться с хабом</div>`;
      return;
    }
    if (data.error) {
      if (silent) return;
      container.innerHTML = `<div class="widget-placeholder">${escapeHtml(data.error)}</div>`;
      return;
    }
    container.innerHTML = renderWidget(widgetId, data);
    if (widgetId === 'memoscope-posts') memoLayout();
  }

  function renderWidget(widgetId, d) {
    if (widgetId === 'beszel-metrics') {
      if (!d.systems || d.systems.length === 0) {
        return `<div class="widget-placeholder">систем в Beszel пока нет</div>`;
      }
      return `<div class="widget-body"><div class="grid stack-grid">${d.systems.map(sys => {
        const netKb = sys.network_bytes_recent ? (sys.network_bytes_recent / 1024).toFixed(1) : '0';
        return `
          <div class="card static" style="align-items:stretch;cursor:default;">
            <div class="top" style="width:100%;">
              <div class="name" style="margin-bottom:8px;">${(() => { const c = extractCountry(sys.name); return escapeHtml(c.cleaned) + (c.flag ? ' ' + c.flag : ''); })()}</div>
              <div style="display:flex;flex-direction:column;gap:4px;">
                <div style="border-top:1px solid var(--line);padding-top:6px;display:flex;justify-content:space-between;font-size:0.8rem;color:var(--muted);"><span>cpu</span><span style="color:var(--text);">${sys.cpu_pct}%</span></div>
                <div style="border-top:1px solid var(--line);padding-top:6px;display:flex;justify-content:space-between;font-size:0.8rem;color:var(--muted);"><span>ram</span><span style="color:var(--text);">${sys.mem_pct}%</span></div>
                <div style="border-top:1px solid var(--line);padding-top:6px;display:flex;justify-content:space-between;font-size:0.8rem;color:var(--muted);"><span>hdd</span><span style="color:var(--text);">${sys.disk_pct}%</span></div>
                <div style="border-top:1px solid var(--line);padding-top:6px;display:flex;justify-content:space-between;font-size:0.8rem;color:var(--muted);"><span>net</span><span style="color:var(--text);">${netKb} КБ</span></div>
              </div>
            </div>
          </div>`;
      }).join('')}</div></div>`;
    }
    if (widgetId === 'vaultwarden-meta') {
      return `<div class="widget-body"><div class="grid stack-grid">
      <div class="card static" style="align-items:stretch;cursor:default;">
        <div class="top" style="width:100%;">
          <div class="name" style="margin-bottom:8px;">vaultwarden</div>
          <div style="display:flex;flex-direction:column;gap:4px;">
            <div style="border-top:1px solid var(--line);padding-top:6px;display:flex;justify-content:space-between;font-size:0.8rem;color:var(--muted);"><span>пользователи</span><span style="color:var(--text);">${d.users}</span></div>
            <div style="border-top:1px solid var(--line);padding-top:6px;display:flex;justify-content:space-between;font-size:0.8rem;color:var(--muted);"><span>записей (паролей)</span><span style="color:var(--text);">${d.items}</span></div>
          </div>
        </div>
      </div>
      </div>
      <div class="widget-note">сами пароли серверу не видны — zero-knowledge шифрование</div>
      </div>`;
    }
    if (widgetId === 'ntfy-feed') {
      if (!d.messages || d.messages.length === 0) {
        return `<div class="widget-placeholder">уведомлений за последние 24 часа нет</div>`;
      }
      // notify_send (common.sh) сам проставляет метку сервера в заголовок
      // каждого уведомления как "[метка] текст" — парсим её здесь, чтобы
      // показать её ВНУТРИ карточки, а не как отдельную секцию-группу.
      const items = d.messages.map(m => {
        const match = /^\[([^\]]+)\]\s*(.*)$/.exec(m.title || '');
        const label = match ? match[1] : '';
        const title = match ? match[2] : (m.title || 'уведомление');
        // Разбиваем по запятым — "Адрес: X, fail2ban: Y, попыток: Z" читается
        // строками гораздо аккуратнее, чем одним слипшимся абзацем с переносом
        // где попало.
        const messageLines = (m.message || '').split(',').map(s => s.trim()).filter(Boolean);
        return { id: m.id, label, title, messageLines, time: m.time || 0 };
      });
      return `<div class="widget-body"><div class="grid">${items.map(msg => `
        <div class="card static" id="ntfy-msg-${escapeHtml(msg.id || '')}">
          <div class="top" style="width:100%;">
            <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:8px;">
              <div class="name" style="display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;">${escapeHtml(msg.title)}</div>
              <button onclick="deleteNtfyMessage('${escapeHtml(msg.id || '')}')" title="Удалить"
                      style="background:none;border:none;color:var(--muted);cursor:pointer;font-size:0.9rem;line-height:1;padding:0 2px;flex-shrink:0;">✕</button>
            </div>
            ${msg.label ? `<div class="desc" style="margin-top:2px;">${escapeHtml(msg.label)}</div>` : ''}
            <div style="margin-top:6px;color:var(--text);font-size:0.75rem;display:flex;flex-direction:column;gap:2px;">
              ${msg.messageLines.map(line => `<div style="word-break:break-word;">${escapeHtml(line)}</div>`).join('')}
            </div>
          </div>
          <div class="bottom">
            <span class="ping" style="color:var(--muted);">${formatNtfyTime(msg.time)}</span>
          </div>
        </div>
      `).join('')}</div></div>`;
    }
    if (widgetId === 'forgejo-repos') {
      const createPanel = `
        <div class="card static" style="margin-bottom:14px;">
          <div class="top" style="width:100%;">
            <div class="name">создать репозиторий из ZIP</div>
            <div style="margin-top:8px;display:flex;flex-direction:column;gap:6px;">
              <input type="text" id="fj-new-repo-name" placeholder="имя-репозитория" style="background:var(--bg);border:1px solid var(--line);color:var(--text);padding:6px 10px;border-radius:6px;font-family:inherit;font-size:0.75rem;">
              <label style="font-size:0.7rem;color:var(--muted);display:flex;align-items:center;gap:6px;"><input type="checkbox" id="fj-new-repo-private"> приватный</label>
              <input type="file" id="fj-new-repo-zip" accept=".zip" style="font-size:0.7rem;color:var(--muted);">
              <button onclick="createForgejoRepoFromZip()" style="font-size:0.7rem;color:var(--accent);background:none;border:1px solid var(--line);padding:6px 10px;border-radius:6px;cursor:pointer;font-family:inherit;">загрузить и создать</button>
              <div id="fj-create-status" style="font-size:0.65rem;color:var(--muted);"></div>
            </div>
          </div>
        </div>`;
      if (!d.repos || d.repos.length === 0) {
        return `<div class="widget-body">${createPanel}<div class="widget-placeholder">репозиториев пока нет</div></div>`;
      }
      return `<div class="widget-body">${createPanel}<div class="grid">${d.repos.map(repo => {
        const safeId = repo.full_name.replace(/[^\w-]/g,'_');
        return `
        <div class="card static" id="fj-repo-${escapeHtml(safeId)}">
          <div class="top">
            <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:8px;">
              <div class="name">${escapeHtml(repo.name)}</div>
              ${repo.private ? '<span class="badge">приватный</span>' : ''}
            </div>
            <div class="desc" style="margin-top:4px;color:var(--text);text-transform:none;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${escapeHtml(repo.description || 'без описания')}</div>
            <div class="desc" style="margin-top:4px;">${formatKb(repo.size_kb)} · ${formatNtfyTime(Math.floor(new Date(repo.updated_at).getTime()/1000)).slice(0,10)}</div>
            <input type="file" id="fj-upload-${escapeHtml(safeId)}" multiple style="display:none;" onchange="uploadFilesToForgejoRepo('${escapeHtml(repo.full_name)}')">
          </div>
          <div class="bottom" style="display:grid;grid-template-columns:1fr 1fr;gap:6px;">
            <a href="/api/forgejo/download/${encodeURIComponent(repo.full_name)}" style="font-size:0.65rem;color:var(--accent);text-decoration:none;border:1px solid var(--line);padding:5px 8px;border-radius:6px;text-align:center;">скачать</a>
            <button onclick="copyForgejoLink('${escapeHtml(repo.full_name)}')" style="font-size:0.65rem;color:var(--muted);background:none;border:1px solid var(--line);padding:5px 8px;border-radius:6px;cursor:pointer;font-family:inherit;">ссылка</button>
            <button onclick="document.getElementById('fj-upload-${escapeHtml(safeId)}').click()" style="font-size:0.65rem;color:var(--accent);background:none;border:1px solid var(--line);padding:5px 8px;border-radius:6px;cursor:pointer;font-family:inherit;">загрузить</button>
            <button onclick="copyForgejoCurlCommand('${escapeHtml(repo.full_name)}', '${escapeHtml(repo.html_url || '')}')" style="font-size:0.65rem;color:var(--muted);background:none;border:1px solid var(--line);padding:5px 8px;border-radius:6px;cursor:pointer;font-family:inherit;">curl</button>
          </div>
        </div>
      `;
      }).join('')}</div></div>`;
    }
    if (widgetId === 'cheevoscope-stats') {
      return renderCheevoscope(d);
    }
    if (widgetId === 'walletscope-data') {
      return renderWalletScope(d);
    }
    if (widgetId === 'memoscope-posts') {
      return renderMemoScope(d);
    }
    return `<div class="widget-body"><pre style="color:var(--muted);font-size:0.7rem;white-space:pre-wrap;">${escapeHtml(JSON.stringify(d, null, 2))}</pre></div>`;
  }

  // ===== Cheevoscope: вкладки + плитка игр + модалка ачивок =====
  let cheevoActiveTab = 'steam';
  let cheevoLastData = null;

  function renderCheevoscope(d) {
    cheevoLastData = d;
    const actionsEl = document.getElementById('overlayActions');
    if (actionsEl) {
      actionsEl.innerHTML = `
        <button onclick="refreshCheevoscope('quick')" style="font-size:0.65rem;color:var(--accent);background:none;border:1px solid var(--line);padding:3px 8px;height:24px;border-radius:6px;cursor:pointer;font-family:inherit;white-space:nowrap;">обновить</button>
        <button onclick="refreshCheevoscope('full')" style="font-size:0.65rem;color:var(--muted);background:none;border:1px solid var(--line);padding:3px 8px;height:24px;border-radius:6px;cursor:pointer;font-family:inherit;white-space:nowrap;">обновить всё</button>
        <span id="cheevo-refresh-status" style="font-size:0.6rem;color:var(--muted);white-space:nowrap;"></span>
      `;
    }
    const tabs = [['steam', 'Steam'], ['retro', 'RetroAchievements'], ['overall', 'Общая статистика']];
    if (!tabs.find(t => t[0] === cheevoActiveTab)) cheevoActiveTab = 'steam';
    const tabButtons = tabs.map(([id, label]) => `
      <button onclick="switchCheevoTab('${id}')" style="font-size:0.7rem;padding:6px 12px;border-radius:6px;cursor:pointer;font-family:inherit;border:1px solid var(--line);background:${cheevoActiveTab === id ? 'rgba(108,142,255,0.12)' : 'none'};color:${cheevoActiveTab === id ? 'var(--accent)' : 'var(--muted)'};">${label}</button>
    `).join('');
    let body = renderCheevoSteamTab(d.steam);
    if (cheevoActiveTab === 'retro') body = renderCheevoRetroTab(d.retro);
    else if (cheevoActiveTab === 'overall') body = renderCheevoOverallTab(d.steam, d.retro);

    return `<div class="widget-body">
      <div style="display:flex;gap:6px;margin-bottom:14px;">${tabButtons}</div>
      ${body}
    </div>`;
  }

  function switchCheevoTab(tab) {
    cheevoActiveTab = tab;
    const container = document.getElementById('overlayBody');
    if (container && cheevoLastData) container.innerHTML = renderCheevoscope(cheevoLastData);
  }

  function cheevoRows(pairs) {
    return pairs.map(([k, v]) => `
      <div style="border-top:1px solid var(--line);padding-top:6px;display:flex;justify-content:space-between;font-size:0.8rem;color:var(--muted);"><span>${k}</span><span style="color:var(--text);">${v}</span></div>
    `).join('');
  }

  function cheevoRarityChips(tiers) {
    if (!tiers || !tiers.total_rated) return '';
    const chips = Object.entries(tiers.counts || {}).map(([tier, count]) => `
      <div style="font-size:0.65rem;color:var(--muted);border:1px solid var(--line);border-radius:6px;padding:4px 8px;">${escapeHtml(tier)}: <span style="color:var(--text);">${count}</span></div>
    `).join('');
    return `<div style="display:flex;flex-wrap:wrap;gap:6px;margin:10px 0;">${chips}</div>`;
  }

  function cheevoHeatmap(heatmap) {
    const counts = heatmap || {};
    if (!Object.keys(counts).length) return '';
    const days = 84;
    const today = new Date();
    const cells = [];
    for (let i = days - 1; i >= 0; i--) {
      const d2 = new Date(today);
      d2.setDate(d2.getDate() - i);
      cells.push(counts[d2.toISOString().slice(0, 10)] || 0);
    }
    const max = Math.max(1, ...cells);
    const colors = ['rgba(255,255,255,0.05)', 'rgba(108,142,255,0.3)', 'rgba(108,142,255,0.55)', 'rgba(108,142,255,0.8)', 'var(--accent)'];
    const level = n => n === 0 ? 0 : Math.min(4, Math.ceil((n / max) * 4));
    const weeks = [];
    for (let w = 0; w < Math.ceil(days / 7); w++) weeks.push(cells.slice(w * 7, w * 7 + 7));
    return weeks.map(week => `
      <div style="display:flex;flex-direction:column;gap:3px;">${week.map(n => `<div style="width:10px;height:10px;border-radius:2px;background:${colors[level(n)]};"></div>`).join('')}</div>
    `).join('');
  }

  function cheevoRarestList(rarest) {
    if (!rarest || !rarest.length) return '';
    return rarest.map(a => `<div style="font-size:0.75rem;color:var(--text);border-top:1px solid var(--line);padding-top:6px;margin-top:6px;">${escapeHtml(a.name || a.achievement || '')}<div style="color:var(--muted);font-size:0.7rem;margin-top:2px;">${escapeHtml(a.game || '')} · ${a.global_percent ?? '?'}%</div></div>`).join('');
  }

  // Карточка с заголовком в том же стиле, что и остальные карточки хаба —
  // используется для heatmap и списка редких ачивок, чтобы они не висели
  // голым текстом на фоне, а смотрелись как часть общей сетки.
  function cheevoInfoCard(title, content, options) {
    if (!content) return '';
    const wrapStyle = options && options.scrollX ? 'display:flex;gap:3px;overflow-x:auto;' : '';
    const wrapClass = options && options.scrollX ? 'no-scrollbar' : '';
    return `<div class="card static" style="align-items:stretch;cursor:default;">
      <div class="top" style="width:100%;">
        <div class="name" style="margin-bottom:10px;">${escapeHtml(title)}</div>
        <div class="${wrapClass}" style="${wrapStyle}">${content}</div>
      </div>
    </div>`;
  }


  // Приоритет картинки: локальный файл -> header_image -> capsule_imagev5
  // -> capsule_image -> угадывание по именам файлов Steam на двух CDN.
  const CHEEVO_IMG_CDN_HOSTS = ['cdn.cloudflare.steamstatic.com', 'cdn.akamai.steamstatic.com'];
  const CHEEVO_IMG_FILE_VARIANTS = ['header.jpg', 'capsule_616x353.jpg', 'library_hero.jpg', 'capsule_231x87.jpg', 'library_600x900_2x.jpg', 'library_600x900.jpg', 'capsule_184x69.jpg'];

  function cheevoImgCandidates(appid, g) {
    const list = [];
    if (g.local_image) list.push(`/api/cheevoscope/local-image/${g.local_image}`);
    if (g.header_image) list.push(g.header_image);
    if (g.capsule_imagev5) list.push(g.capsule_imagev5);
    if (g.capsule_image) list.push(g.capsule_image);
    for (const file of CHEEVO_IMG_FILE_VARIANTS) {
      for (const host of CHEEVO_IMG_CDN_HOSTS) list.push(`https://${host}/steam/apps/${appid}/${file}`);
    }
    return list;
  }

  // onerror у <img> — перебираем кандидатов по очереди, скрываем картинку
  // насовсем только когда исчерпаны все варианты.
  function handleCheevoImgError(img) {
    let candidates;
    try { candidates = JSON.parse(img.dataset.candidates || '[]'); } catch (e) { candidates = []; }
    const idx = parseInt(img.dataset.fallbackIdx || '0', 10) + 1;
    if (idx < candidates.length) {
      img.dataset.fallbackIdx = String(idx);
      img.src = candidates[idx];
    } else {
      img.style.display = 'none';
    }
  }

  function cheevoAchColor(pct) {
    if (pct === null || pct === undefined) return 'var(--muted)';
    return pct >= 100 ? 'var(--amber)' : 'var(--accent)';
  }

  function cheevoGameCard(appid, g, onclick) {
    const hasAch = g.achievements_percent !== null && g.achievements_percent !== undefined;
    const candidates = cheevoImgCandidates(appid, g);
    const color = cheevoAchColor(g.achievements_percent);
    const achBlock = hasAch ? `
      <div style="display:flex;justify-content:space-between;font-size:0.7rem;margin-top:6px;">
        <span style="color:var(--muted);">${g.achievements_unlocked}/${g.achievements_total}</span>
        <span style="color:${color};font-weight:600;">${g.achievements_percent}%</span>
      </div>
      <div style="height:4px;border-radius:2px;background:rgba(255,255,255,0.08);margin-top:4px;overflow:hidden;">
        <div style="height:100%;width:${g.achievements_percent}%;background:${color};"></div>
      </div>` : `<div class="desc" style="margin-top:6px;">нет достижений</div>`;
    return `<div class="card${onclick ? '' : ' static'}" ${onclick ? `onclick="${onclick}"` : 'style="cursor:default;"'}>
      <div class="top">
        <img src="${escapeHtml(candidates[0] || '')}" data-candidates='${escapeHtml(JSON.stringify(candidates))}' data-fallback-idx="0" loading="lazy" onerror="handleCheevoImgError(this)" style="width:100%;aspect-ratio:16/7.5;object-fit:cover;border-radius:6px;margin-bottom:8px;background:var(--bg);">
        <div class="name" style="display:-webkit-box;-webkit-line-clamp:1;-webkit-box-orient:vertical;overflow:hidden;">${escapeHtml(g.name || '')}</div>
        <div class="desc" style="margin-top:2px;">${g.hours ?? 0}ч</div>
        ${achBlock}
      </div>
    </div>`;
  }

  // Список-строка для RetroAchievements — в оригинале НЕ плитка с обложкой,
  // а компактная строка (иконка + консоль + счётчик hardcore + два бара).
  function cheevoRetroRow(g) {
    const statusText = g.status === 'mastered' ? 'замастерено' : (g.status === 'completed' ? 'завершено' : 'в процессе');
    const barColor = g.status === 'mastered' ? 'var(--amber)' : 'var(--accent)';
    const icon = g.image_icon ? `<img src="https://media.retroachievements.org${escapeHtml(g.image_icon)}" loading="lazy" style="width:40px;height:40px;border-radius:6px;flex-shrink:0;object-fit:cover;">` : '';
    return `<div class="card static" style="flex-direction:row;align-items:center;gap:10px;cursor:pointer;min-height:0;padding:10px 12px;" onclick="openCheevoAchievements('retro', ${g.game_id}, '${escapeHtml(g.title || '').replace(/'/g, "\\'")}')">
      ${icon}
      <div style="min-width:0;flex:1;">
        <div class="name" style="white-space:normal;">${escapeHtml(g.title || '')}</div>
        <div class="desc" style="margin-top:2px;">${escapeHtml(g.console || '')} · ${g.num_awarded_hardcore ?? 0}/${g.max_possible ?? 0} HC</div>
        <div style="height:4px;border-radius:2px;background:rgba(255,255,255,0.08);margin-top:6px;overflow:hidden;">
          <div style="height:100%;width:${g.hardcore_percent ?? 0}%;background:${barColor};"></div>
        </div>
      </div>
      <div style="text-align:right;flex-shrink:0;">
        <div style="font-size:0.75rem;color:${barColor};font-weight:600;">${g.hardcore_percent ?? 0}%</div>
        <div style="font-size:0.6rem;color:var(--muted);text-transform:uppercase;margin-top:2px;">${statusText}</div>
      </div>
    </div>`;
  }

  function renderCheevoSteamTab(s) {
    s = s || {};
    const sum = s.summary || {};
    const summaryCard = `
      <div class="card static" style="align-items:stretch;cursor:default;">
        <div class="top" style="width:100%;">
          <div class="name" style="margin-bottom:8px;">steam</div>
          <div style="display:flex;flex-direction:column;gap:4px;">
            ${cheevoRows([
              ['игр в библиотеке', sum.games_count ?? 0],
              ['наиграно часов', sum.total_hours ?? 0],
              ['ачивок', `${sum.achievements_unlocked_total ?? 0}/${sum.achievements_available_total ?? 0} (${sum.achievements_overall_percent ?? 0}%)`],
              ['пройдено на 100%', sum.games_completed_100 ?? 0],
              ['стоимость библ.', `$${sum.library_cost_usd ?? 0}`],
            ])}
          </div>
          ${cheevoRarityChips(s.rarity_tiers)}
        </div>
      </div>`;
    const heatmapCard = cheevoInfoCard('активность за 12 недель', cheevoHeatmap(s.heatmap), { scrollX: true });
    const rarestCard = cheevoInfoCard('редчайшие достижения', cheevoRarestList(s.rarest));
    const topRow = `<div class="grid" style="margin-bottom:14px;">${summaryCard}${heatmapCard}${rarestCard}</div>`;
    const games = s.games || [];
    const gamesGrid = games.length
      ? `<div class="grid">${games.map(g => cheevoGameCard(
          g.appid, g,
          g.achievements_total ? `openCheevoAchievements('steam', ${g.appid}, '${escapeHtml(g.name || '').replace(/'/g, "\\'")}')` : '',
        )).join('')}</div>`
      : `<div class="widget-placeholder">игр пока нет — нажмите "обновить"</div>`;
    return topRow + gamesGrid;
  }

  function renderCheevoRetroTab(r) {
    if (!r) return '<div class="widget-placeholder">RetroAchievements не настроен</div>';
    const sum = r.summary || {};
    const profile = r.profile || {};
    const summaryCard = `
      <div class="card static" style="align-items:stretch;cursor:default;">
        <div class="top" style="width:100%;">
          <div class="name" style="margin-bottom:8px;">${escapeHtml(profile.username || 'retroachievements')}</div>
          <div style="display:flex;flex-direction:column;gap:4px;">
            ${cheevoRows([
              ['игр', sum.games_count ?? 0],
              ['замастерено', sum.games_mastered ?? 0],
              ['пройдено', sum.games_completed ?? 0],
              ['очки', profile.points ?? 0],
              ['хардкор-очки', profile.retro_points ?? 0],
              ['% хардкор', `${sum.overall_hardcore_percent ?? 0}%`],
            ])}
          </div>
          ${cheevoRarityChips(r.rarity_tiers)}
        </div>
      </div>`;
    const consoles = Object.entries(r.points_by_console || {});
    const consolesContent = consoles.length
      ? consoles.map(([name, pts]) => `<div style="font-size:0.75rem;color:var(--muted);border-top:1px solid var(--line);padding-top:6px;margin-top:6px;display:flex;justify-content:space-between;"><span>${escapeHtml(name)}</span><span style="color:var(--text);">${pts.hardcore ?? 0} (софткор: ${pts.softcore ?? 0})</span></div>`).join('')
      : '';
    const consolesCard = cheevoInfoCard('очки по консолям', consolesContent);
    const rarestCard = cheevoInfoCard('редчайшие достижения', cheevoRarestList(r.rarest));
    const topRow = `<div class="grid" style="margin-bottom:14px;">${summaryCard}${consolesCard}${rarestCard}</div>`;
    const games = r.games || [];
    const gamesGrid = games.length
      ? `<div style="display:flex;flex-direction:column;gap:8px;">${games.map(cheevoRetroRow).join('')}</div>`
      : '';
    return topRow + gamesGrid;
  }

  function renderCheevoOverallTab(s, r) {
    s = s || {};
    const sum = s.summary || {};
    const rsum = (r && r.summary) || {};
    const rprofile = (r && r.profile) || {};
    return `<div class="grid stack-grid">
      <div class="card static" style="align-items:stretch;cursor:default;">
        <div class="top" style="width:100%;">
          <div class="name" style="margin-bottom:8px;">steam</div>
          <div style="display:flex;flex-direction:column;gap:4px;">${cheevoRows([
            ['игр', sum.games_count ?? 0], ['часов', sum.total_hours ?? 0], ['ачивок', `${sum.achievements_overall_percent ?? 0}%`],
          ])}</div>
        </div>
      </div>
      <div class="card static" style="align-items:stretch;cursor:default;">
        <div class="top" style="width:100%;">
          <div class="name" style="margin-bottom:8px;">retroachievements</div>
          <div style="display:flex;flex-direction:column;gap:4px;">${cheevoRows([
            ['игр', rsum.games_count ?? 0], ['очки', rprofile.points ?? 0], ['% хардкор', `${rsum.overall_hardcore_percent ?? 0}%`],
          ])}</div>
        </div>
      </div>
    </div>`;
  }

  async function openCheevoAchievements(platform, id, name) {
    const overlay = document.getElementById('serviceOverlay');
    document.getElementById('overlayTitle').textContent = name;
    const body = document.getElementById('overlayBody');
    body.innerHTML = `<div class="widget-placeholder">загрузка ачивок...</div>`;
    overlay.classList.add('open');
    history.pushState({ nexusOverlay: true }, '', location.href);
    const url = platform === 'retro' ? `/api/cheevoscope/retro/game/${id}/achievements` : `/api/cheevoscope/game/${id}/achievements`;
    try {
      const res = await fetch(url);
      const data = await res.json();
      if (!data.available || !data.achievements.length) {
        body.innerHTML = `<div class="widget-placeholder">данных по ачивкам нет</div>`;
        return;
      }
      body.innerHTML = `<div class="widget-body"><div class="grid stack-grid">${data.achievements.map(a => {
        const icon = platform === 'retro' ? a.badge_url : (a.unlocked ? a.icon : (a.icon_gray || a.icon));
        return `
        <div class="card static" style="flex-direction:row;align-items:center;gap:10px;cursor:default;opacity:${a.unlocked ? '1' : '0.5'};">
          ${icon ? `<img src="${escapeHtml(icon)}" style="width:40px;height:40px;border-radius:6px;flex-shrink:0;">` : ''}
          <div style="min-width:0;flex:1;">
            <div class="name" style="white-space:normal;">${escapeHtml(a.name || a.achievement || '')}</div>
            <div class="desc" style="margin-top:2px;text-transform:none;white-space:normal;">${escapeHtml(a.description || '')}</div>
          </div>
          <div style="font-size:0.7rem;color:var(--amber);flex-shrink:0;">${a.global_percent ?? '?'}%</div>
        </div>`;
      }).join('')}</div></div>`;
    } catch (e) {
      body.innerHTML = `<div class="widget-placeholder">не удалось загрузить: ${escapeHtml(e.message)}</div>`;
    }
  }

  // ===== WalletScope =====
  function formatRub(n) {
    n = Number(n) || 0;
    return n.toLocaleString('ru-RU') + ' ₽';
  }

  let walletLastData = null;

  function renderWalletScope(d) {
    walletLastData = d;
    const actionsEl = document.getElementById('overlayActions');
    if (actionsEl) actionsEl.innerHTML = '';
    const rates = d.rates || {};
    const rateChip = (sym, val, isRub) => `
      <div class="rate-chip">
        <span class="sym">${sym}</span>
        <span class="val">${val == null ? '—' : (isRub ? formatRub(val) : val)}</span>
      </div>`;
    const sorted = [...(d.transactions || [])].sort((a, b) => b.id - a.id);
    const txRows = sorted.map(tx => `
      <div class="tx-row">
        <div class="tx-desc">
          <div class="title">${escapeHtml(tx.desc)}</div>
          <div class="meta">${escapeHtml(tx.date)}</div>
        </div>
        <div class="tx-amount ${tx.type}">${tx.type === 'income' ? '+' : '−'}${formatRub(tx.amount)}</div>
        <div class="actions">
          <button onclick="walletEditTx(${tx.id})" style="font-size:0.65rem;background:none;border:1px solid var(--line);color:var(--text);border-radius:5px;padding:3px 7px;cursor:pointer;font-family:inherit;">✎</button>
          <button onclick="walletDeleteTx(${tx.id})" style="font-size:0.65rem;background:none;border:1px solid var(--line);color:var(--red);border-radius:5px;padding:3px 7px;cursor:pointer;font-family:inherit;">✕</button>
        </div>
      </div>`).join('');

    return `<div class="widget-body">
      <div class="card static" style="align-items:stretch;cursor:default;margin-bottom:14px;">
        <div class="top" style="width:100%;">
          <div class="wallet-balances">
            <div class="balance-card">
              <div class="balance-label">Карта</div>
              <div class="balance-amount">${formatRub(d.card)}</div>
              <div style="display:flex;gap:6px;flex-wrap:wrap;">
                <button onclick="walletOpenTxModal('income')" style="font-size:0.7rem;color:var(--green);background:none;border:1px solid var(--line);padding:6px 10px;border-radius:6px;cursor:pointer;font-family:inherit;">+ доход</button>
                <button onclick="walletOpenTxModal('expense')" style="font-size:0.7rem;color:var(--red);background:none;border:1px solid var(--line);padding:6px 10px;border-radius:6px;cursor:pointer;font-family:inherit;">− расход</button>
              </div>
            </div>
            <div class="balance-card">
              <div class="balance-label">Депозит</div>
              <div class="balance-amount">${formatRub(d.deposit)}</div>
              <div><button onclick="walletOpenTransferModal()" style="font-size:0.7rem;color:var(--accent);background:none;border:1px solid var(--line);padding:6px 10px;border-radius:6px;cursor:pointer;font-family:inherit;">→ на депозит</button></div>
            </div>
          </div>
          <div class="rates-row">
            ${rateChip('USD', rates.usd, true)}
            ${rateChip('EUR', rates.eur, true)}
            ${rateChip('BTC', rates.btc, true)}
            ${rateChip('ETH', rates.eth, true)}
          </div>
        </div>
      </div>
      <div class="card static" style="align-items:stretch;cursor:default;">
        <div class="top" style="width:100%;">
          <div class="name" style="margin-bottom:8px;">операции</div>
          <div>${txRows || '<div class="widget-placeholder">записей пока нет</div>'}</div>
        </div>
      </div>
    </div>`;
  }

  let walletEditingTxId = null;

  function walletOpenTxModal(type, tx) {
    walletEditingTxId = tx ? tx.id : null;
    document.getElementById('walletTxModalTitle').textContent = tx ? 'Изменить запись' : (type === 'income' ? 'Добавить доход' : 'Добавить расход');
    document.getElementById('walletTxAmount').value = tx ? tx.amount : '';
    document.getElementById('walletTxDesc').value = tx ? tx.desc : '';
    document.getElementById('walletTxModalBackdrop').dataset.type = type;
    document.getElementById('walletTxModalBackdrop').classList.add('open');
  }

  function walletEditTx(id) {
    if (!walletLastData) return;
    const tx = (walletLastData.transactions || []).find(t => t.id === id);
    if (tx) walletOpenTxModal(tx.type, tx);
  }

  async function walletDeleteTx(id) {
    await fetch(`/api/walletscope/delete/${id}`, { method: 'POST' });
    loadWidget('walletscope-data', document.getElementById('overlayBody'));
  }

  async function walletSaveTx() {
    const amount = parseFloat(document.getElementById('walletTxAmount').value) || 0;
    const desc = document.getElementById('walletTxDesc').value.trim();
    const type = document.getElementById('walletTxModalBackdrop').dataset.type;
    if (amount <= 0) return;
    if (walletEditingTxId) {
      await fetch(`/api/walletscope/edit/${walletEditingTxId}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type, amount, desc }),
      });
    } else {
      await fetch('/api/walletscope/add', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type, amount, desc }),
      });
    }
    closeWalletModal('walletTxModalBackdrop');
    loadWidget('walletscope-data', document.getElementById('overlayBody'));
  }

  function walletOpenTransferModal() {
    document.getElementById('walletTransferAvailable').textContent = formatRub(walletLastData ? walletLastData.card : 0);
    document.getElementById('walletTransferAmount').value = '';
    document.getElementById('walletTransferModalBackdrop').classList.add('open');
  }

  async function walletSaveTransfer() {
    const amount = parseFloat(document.getElementById('walletTransferAmount').value) || 0;
    if (amount <= 0) return;
    const res = await fetch('/api/walletscope/transfer', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ amount }),
    });
    const data = await res.json();
    if (data.error) { alert(data.error); return; }
    closeWalletModal('walletTransferModalBackdrop');
    loadWidget('walletscope-data', document.getElementById('overlayBody'));
  }

  function closeWalletModal(id) {
    document.getElementById(id).classList.remove('open');
  }

  // ===== MemoScope =====
  let memoLastPosts = [];
  let memoEditingPostId = null;

  function renderMemoScope(d) {
    const actionsEl = document.getElementById('overlayActions');
    if (actionsEl) {
      actionsEl.innerHTML = `<button onclick="memoOpenPostModal()" style="font-size:0.65rem;color:var(--accent);background:none;border:1px solid var(--line);padding:3px 8px;height:24px;border-radius:6px;cursor:pointer;font-family:inherit;">+ добавить пост</button>`;
    }
    memoLastPosts = d.posts || [];
    return `<div class="widget-body"><div id="memoMasonryRoot"></div></div>`;
  }

  function memoBuildPostEl(post) {
    const el = document.createElement('div');
    el.className = 'card static memo-post';
    el.style.cssText = 'cursor:default;align-items:stretch;';
    const imgTag = post.image ? `<img src="/api/memoscope/image/${encodeURIComponent(post.image)}" loading="lazy">` : '';
    el.innerHTML = `
      <div class="top" style="width:100%;">
        ${imgTag}
        <div class="post-date">${escapeHtml(post.date)}</div>
        <div class="post-body">${post.html}</div>
        <div class="post-actions">
          <button onclick="memoEditPost(${post.id})" style="font-size:0.65rem;background:none;border:1px solid var(--line);color:var(--text);border-radius:5px;padding:3px 7px;cursor:pointer;font-family:inherit;">✎ изменить</button>
          <button onclick="memoDeletePost(${post.id})" style="font-size:0.65rem;background:none;border:1px solid var(--line);color:var(--red);border-radius:5px;padding:3px 7px;cursor:pointer;font-family:inherit;">✕ удалить</button>
        </div>
      </div>`;
    return el;
  }

  // Masonry в 2 колонки по реальной высоте (не альтернация индекса) —
  // каждый следующий пост уходит в ту колонку, что сейчас короче. Самый
  // новый пост всегда первым попадает в левую (она стартует с высоты 0).
  function memoLayout() {
    const root = document.getElementById('memoMasonryRoot');
    if (!root) return;
    root.innerHTML = '';
    const sorted = [...memoLastPosts].sort((a, b) => b.id - a.id);
    if (!sorted.length) {
      root.innerHTML = '<div class="widget-placeholder">постов пока нет — нажмите "+ добавить пост"</div>';
      return;
    }
    if (window.innerWidth <= 760) {
      const col = document.createElement('div');
      col.className = 'memo-col';
      sorted.forEach(p => col.appendChild(memoBuildPostEl(p)));
      root.appendChild(col);
      return;
    }
    const row = document.createElement('div');
    row.className = 'memo-columns';
    const left = document.createElement('div');
    const right = document.createElement('div');
    left.className = 'memo-col';
    right.className = 'memo-col';
    row.appendChild(left); row.appendChild(right);
    root.appendChild(row);
    sorted.forEach(p => {
      const el = memoBuildPostEl(p);
      if (left.offsetHeight <= right.offsetHeight) left.appendChild(el); else right.appendChild(el);
    });
  }

  window.addEventListener('resize', () => {
    if (document.getElementById('memoMasonryRoot')) memoLayout();
  });

  function memoOpenPostModal(post) {
    memoEditingPostId = post ? post.id : null;
    document.getElementById('memoPostModalTitle').textContent = post ? 'Изменить пост' : 'Новый пост';
    document.getElementById('memoEditorArea').innerHTML = post ? post.html : '';
    const preview = document.getElementById('memoImagePreview');
    if (post && post.image) {
      preview.src = `/api/memoscope/image/${encodeURIComponent(post.image)}`;
      preview.style.display = 'block';
      delete preview.dataset.value;
      preview.dataset.unchanged = '1';
    } else {
      preview.style.display = 'none'; preview.removeAttribute('src');
      delete preview.dataset.value; delete preview.dataset.unchanged;
    }
    document.getElementById('memoImageInput').value = '';
    document.getElementById('memoPostModalBackdrop').classList.add('open');
  }

  function memoEditPost(id) {
    const post = memoLastPosts.find(p => p.id === id);
    if (post) memoOpenPostModal(post);
  }

  async function memoDeletePost(id) {
    await fetch(`/api/memoscope/delete/${id}`, { method: 'POST' });
    loadWidget('memoscope-posts', document.getElementById('overlayBody'));
  }

  function memoPreviewImage(event) {
    const file = event.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = e => {
      const preview = document.getElementById('memoImagePreview');
      preview.src = e.target.result;
      preview.style.display = 'block';
      preview.dataset.value = e.target.result;
      delete preview.dataset.unchanged;
    };
    reader.readAsDataURL(file);
  }

  async function memoSavePost() {
    const html = document.getElementById('memoEditorArea').innerHTML.trim();
    if (!html) return;
    const preview = document.getElementById('memoImagePreview');
    const body = { html };
    // "unchanged" — картинка уже была у поста, и пользователь её не менял:
    // не шлём image_data_url вообще, чтобы бэкенд не затирал существующую
    // (см. widget_memoscope_edit — поле трогается только если оно есть в body).
    if (!preview.dataset.unchanged) {
      body.image_data_url = preview.dataset.value || null;
    }
    if (memoEditingPostId) {
      await fetch(`/api/memoscope/edit/${memoEditingPostId}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
      });
    } else {
      await fetch('/api/memoscope/add', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
      });
    }
    closeMemoModal();
    loadWidget('memoscope-posts', document.getElementById('overlayBody'));
  }

  function memoFmt(cmd, value) {
    document.getElementById('memoEditorArea').focus();
    document.execCommand(cmd, false, value || null);
  }

  function closeMemoModal() {
    document.getElementById('memoPostModalBackdrop').classList.remove('open');
  }

  function formatNtfyTime(unixTime) {
    if (!unixTime) return '';
    const d = new Date(unixTime * 1000);
    const pad = n => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  }

  function formatKb(kb) {
    if (!kb) return '0 КБ';
    if (kb < 1024) return `${kb} КБ`;
    return `${(kb / 1024).toFixed(1)} МБ`;
  }

  function copyForgejoLink(fullName) {
    const url = `${window.location.origin}/api/forgejo/download/${encodeURIComponent(fullName)}`;
    navigator.clipboard.writeText(url).then(() => {
      alert('Ссылка скопирована — она рабочая, только пока вы вошли в хаб');
    }).catch(() => {
      prompt('Скопируйте ссылку вручную:', url);
    });
  }

  async function refreshCheevoscope(mode) {
    const statusEl = document.getElementById('cheevo-refresh-status');
    if (statusEl) statusEl.textContent = 'запускаю обновление...';
    try {
      const res = await fetch(`/api/cheevoscope/refresh?mode=${encodeURIComponent(mode)}`, { method: 'POST' });
      const data = await res.json();
      const steamMsg = data.steam && data.steam.started === false
        ? 'обновление уже идёт'
        : (data.steam && data.steam.error ? `ошибка: ${data.steam.error}` : 'запущено — обновится в фоне за минуту-другую');
      if (statusEl) statusEl.textContent = steamMsg;
    } catch (e) {
      if (statusEl) statusEl.textContent = 'не удалось запустить: ' + e.message;
    }
  }

  async function createForgejoRepoFromZip() {
    const nameInput = document.getElementById('fj-new-repo-name');
    const privateInput = document.getElementById('fj-new-repo-private');
    const zipInput = document.getElementById('fj-new-repo-zip');
    const statusEl = document.getElementById('fj-create-status');
    const name = nameInput.value.trim();
    if (!name) { statusEl.textContent = 'укажите имя репозитория'; return; }
    if (!zipInput.files.length) { statusEl.textContent = 'выберите ZIP-файл'; return; }

    const form = new FormData();
    form.append('repo_name', name);
    form.append('private', privateInput.checked ? 'true' : 'false');
    form.append('file', zipInput.files[0]);

    statusEl.textContent = 'загрузка и распаковка... это может занять время для больших архивов';
    try {
      const res = await fetch('/api/forgejo/create-from-zip', { method: 'POST', body: form });
      const data = await res.json();
      if (data.error) {
        statusEl.textContent = 'ошибка: ' + data.error;
        return;
      }
      statusEl.textContent = `готово: ${data.repo}, файлов залито: ${data.uploaded.length}` +
        (data.errors.length ? `, ошибок: ${data.errors.length}` : '');
      loadWidget('forgejo-repos', document.getElementById('overlayBody'));
    } catch (e) {
      statusEl.textContent = 'ошибка сети: ' + e.message;
    }
  }

  async function uploadFilesToForgejoRepo(fullName) {
    const safeId = fullName.replace(/[^\w-]/g, '_');
    const input = document.getElementById(`fj-upload-${safeId}`);
    if (!input.files.length) { alert('выберите файлы для загрузки'); return; }

    const form = new FormData();
    for (const file of input.files) {
      form.append('files[]', file, file.name);
    }
    try {
      const res = await fetch(`/api/forgejo/upload/${encodeURIComponent(fullName)}`, { method: 'POST', body: form });
      const data = await res.json();
      if (data.error) { alert('Ошибка: ' + data.error); return; }
      alert(`Загружено: ${data.uploaded.length}` + (data.errors.length ? `, ошибок: ${data.errors.length}` : ''));
      loadWidget('forgejo-repos', document.getElementById('overlayBody'));
    } catch (e) {
      alert('Ошибка сети: ' + e.message);
    }
  }

  // copyForgejoCurlCommand — строит адрес API из html_url репозитория (не
  // гадает по window.location.origin), потому что Forgejo может жить не
  // на корне домена, а под своим путём (например "/git" — так у нас по
  // умолчанию), и это влияет на реальный адрес API тоже (у Forgejo ВСЕ
  // маршруты, включая API, монтируются с этим же префиксом).
  function copyForgejoCurlCommand(fullName, htmlUrl) {
    let apiBase = window.location.origin;
    if (htmlUrl) {
      try {
        const u = new URL(htmlUrl);
        const parts = u.pathname.split('/').filter(Boolean);
        parts.pop(); parts.pop(); // убираем "owner/repo" из хвоста пути
        apiBase = `${u.origin}${parts.length ? '/' + parts.join('/') : ''}`;
      } catch (e) { /* оставляем apiBase по умолчанию */ }
    }
    const cmd = `curl -X POST "${apiBase}/api/v1/repos/${fullName}/contents/ПУТЬ_В_РЕПО/имя-файла" \\
  -H "Authorization: token ВАШ_ТОКЕН_FORGEJO" \\
  -H "Content-Type: application/json" \\
  -d "{\\"content\\": \\"$(base64 -w0 /путь/к/локальному/файлу)\\", \\"message\\": \\"deploy\\"}"`;
    navigator.clipboard.writeText(cmd).then(() => {
      alert('Команда скопирована.\n\nЗамените:\n— ВАШ_ТОКЕН_FORGEJO — личный токен (Forgejo → Settings → Applications → Generate New Token)\n— ПУТЬ_В_РЕПО/имя-файла — куда класть файл в репозитории\n— /путь/к/локальному/файлу — что заливать');
    }).catch(() => {
      prompt('Скопируйте команду вручную:', cmd);
    });
  }

  // ===== Push-уведомления (Web Push) =====
  // Стандартный способ передать VAPID-ключ в PushManager.subscribe() —
  // он ожидает Uint8Array, а сервер отдаёт base64url-строку.
  function urlBase64ToUint8Array(base64String) {
    const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
    const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    const raw = atob(base64);
    return Uint8Array.from([...raw].map(c => c.charCodeAt(0)));
  }

  function pushSupported() {
    return 'serviceWorker' in navigator && 'PushManager' in window;
  }

  async function updatePushToggleText() {
    const els = document.querySelectorAll('.js-push-toggle');
    if (!pushSupported()) {
      els.forEach(el => { el.textContent = '[уведомления недоступны]'; el.style.opacity = '0.4'; el.style.pointerEvents = 'none'; });
      return;
    }
    try {
      // getRegistration() — НЕ serviceWorker.ready: .ready может ждать
      // бесконечно, если регистрация так и не удалась (например, SW не
      // может активироваться в незащищённом контексте) — тогда кнопка
      // навсегда зависла бы на "...". getRegistration() возвращает
      // undefined сразу, если активной регистрации нет.
      const reg = await navigator.serviceWorker.getRegistration();
      if (!reg) {
        els.forEach(el => { el.textContent = '[уведомления: выкл]'; });
        return;
      }
      const sub = await reg.pushManager.getSubscription();
      els.forEach(el => { el.textContent = sub ? '[уведомления: вкл]' : '[уведомления: выкл]'; });
    } catch (e) {
      els.forEach(el => { el.textContent = '[уведомления: выкл]'; });
    }
  }

  async function togglePushSubscription() {
    if (!pushSupported()) {
      alert('Этот браузер не поддерживает push-уведомления (нужен Service Worker + Push API).');
      return;
    }
    try {
      const reg = await Promise.race([
        navigator.serviceWorker.ready,
        new Promise((_, reject) => setTimeout(() => reject(new Error('Service Worker не активировался (нужен HTTPS)')), 5000)),
      ]);
      const existing = await reg.pushManager.getSubscription();
      if (existing) {
        // Уже подписаны — отписываемся и на сервере, и в самом браузере
        await fetch('/api/push/unsubscribe', {
          method: 'POST',
          body: JSON.stringify({ endpoint: existing.endpoint }),
        });
        await existing.unsubscribe();
        await updatePushToggleText();
        return;
      }

      if (Notification.permission === 'denied') {
        alert('Уведомления заблокированы в настройках браузера для этого сайта — включите вручную в настройках сайта.');
        return;
      }
      const permission = await Notification.requestPermission();
      if (permission !== 'granted') {
        return;
      }

      const keyRes = await fetch('/api/push/vapid-public-key');
      const { key } = await keyRes.json();
      if (!key) {
        alert('Сервер ещё не сгенерировал ключ для push — попробуйте через минуту.');
        return;
      }

      const sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(key),
      });
      await fetch('/api/push/subscribe', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(sub.toJSON()),
      });
      await updatePushToggleText();
    } catch (e) {
      alert('Не удалось изменить подписку на уведомления: ' + e.message);
    }
  }

  if (pushSupported()) {
    navigator.serviceWorker.register('/sw.js').then(() => updatePushToggleText()).catch(() => updatePushToggleText());
  } else {
    updatePushToggleText();
  }


  async function deleteNtfyMessage(id) {
    if (!id) return;
    try {
      const res = await fetch(`/api/widgets/ntfy-feed/${id}`, { method: 'DELETE' });
      const data = await res.json();
      if (data.error) {
        alert('Не удалось удалить: ' + data.error);
        return;
      }
      const el = document.getElementById(`ntfy-msg-${id}`);
      if (el) el.remove();
    } catch (e) {
      alert('Не удалось удалить: ' + e.message);
    }
  }
  function closeOverlayDom() {
    document.getElementById('serviceOverlay').classList.remove('open');
    document.getElementById('overlayBody').innerHTML = '';
    document.getElementById('overlayActions').innerHTML = '';
    if (widgetAutoRefreshTimer) {
      clearInterval(widgetAutoRefreshTimer);
      widgetAutoRefreshTimer = null;
    }
  }

  function closeOverlay() {
    // Не закрываем DOM напрямую — идём через history.back(), чтобы запись,
    // добавленная в openService(), не оставалась "хвостом" в истории
    // (иначе следующее нажатие системной кнопки "назад" пришлось бы делать
    // впустую, просто чтобы убрать этот хвост). history.back() асинхронно
    // вызовет popstate — реальное закрытие произойдёт там.
    if (history.state && history.state.nexusOverlay) {
      history.back();
    } else {
      closeOverlayDom();
    }
  }

  // Системная кнопка "назад" (Android) и жест "назад" в PWA тоже вызывают
  // popstate — реагируем так же, как на клик по кнопке в интерфейсе.
  window.addEventListener('popstate', closeOverlayDom);

  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeOverlay(); });

  async function measureBottomPing(){
    const el = document.getElementById('ping');
    const start = performance.now();
    try {
      await fetch(location.href, { method: 'HEAD', cache: 'no-store' });
      el.textContent = Math.round(performance.now() - start) + ' ms';
    } catch(e) { el.textContent = 'н/д'; }
  }

  const startTime = Date.now();
  function tick(){
    const s = Math.floor((Date.now()-startTime)/1000);
    const m = String(Math.floor(s/60)).padStart(2,'0');
    const sec = String(s%60).padStart(2,'0');
    document.getElementById('timer').textContent = `${m}:${sec}`;
  }

  const hostname = window.location.hostname || 'localhost';
  document.querySelectorAll('.js-footer-brand').forEach(el => el.textContent = hostname.replace(/^www\./, '').toUpperCase());
  document.querySelectorAll('.js-year').forEach(el => el.textContent = new Date().getFullYear());
  document.querySelectorAll('.js-domain').forEach(el => el.textContent = hostname);

  loadCards()
    .catch((e) => { console.error('loadCards failed:', e); });
  setInterval(loadCards, 30000);
  setInterval(measureBottomPing, 10000);
  setInterval(tick, 1000);
</script>
</body>
</html>
HTMLEOF
        echo "${GREEN}[✓]${NC} index.html создан: $HUB_DIR/html/index.html"
    else
        echo "${CYAN}[*]${NC} index.html уже существует, не трогаю (возможны ручные правки)"
    fi

    # Иконки + манифест — без них "Добавить на экран" (Android/iOS) не
    # находит нормальную иконку и рисует заглушку: залитый кружок с
    # бейджиком браузера поверх (проверено на практике). Обычная версия —
    # с закруглённым фоном и рамкой; maskable — фон до самых краёв (систем
    # сама обрежет по своей маске: круг/капля/квадрат), текст в безопасной
    # зоне по центру.
    if [ ! -f "$HUB_DIR/html/icon-512.png" ]; then
        base64 -d > "$HUB_DIR/html/icon-512.png" << 'ICONEOF'
iVBORw0KGgoAAAANSUhEUgAAAgAAAAIACAIAAAB7GkOtAAAaWElEQVR4nO3daZCd1X3g4fd2t6TWvgvtawuxaBcIJGxsbGwsIjl2ZnC8pKgsVFKZVBYzmSRlx8Rh4mCnCuOacc0Hxx8mVA0Ez9jEBsfGQ0Li2MYQDGIRIKu1ISGBkCwkQWvplno+NCMQtLpv3/fcdzvP89X26ePG/v/uee/tc2vtI8ckAMSnJe8NAJAPAQCIlAAAREoAACIlAACREgCASAkAQKQEACBSAgAQKQEAiJQAAERKAAAiJQAAkRIAgEgJAECkBAAgUgIAECkBAIiUAABESgAAIiUAAJESAIBICQBApNry3kCJ3fSFY3lvAUiSJPn6Z8fmvYVSqrWPHJP3HkrArIfSUYVBCUD/THyoGD14JwE4h7kPlacEZwmAoQ/xijwGUQfA6AeSiDMQYwDMfaBfsZUgrgAY/cCg4slAFAEw94EGVL4EFQ+A0Q+kVOEMVDYA2Yz+O2+dlsFPAQZw4y0HMvgplcxABQPQpNFv1kOJNKkKFctA1QIQdvob+lABYWNQpQZUJwChRr+hDxUWKgbVyEBFApB++pv7EJX0JahAA0ofgJSj39yHyKUsQakzUO4ApJn+Rj9wVpoMlLcBZQ1Aw6Pf3AcG0HAJypiBUgagselv9AN1aiwDpWtA+QLQwPQ3+oEGNJCBcjWgTAHwwh/IWLWPAqUJgBf+QF6qehQoRwCGOv2NfiC4oWag+A1oyXsDgzP9gSIY6mwp/m3ERT8BDOk3aPQDGRjSUaDI54BCnwBMf6CAhjRtinwOKG4ATH+gsKrRgII+Aqr/92X0Azmq/3FQAZ8FFfEEYPoDZVH/FCrgOaBwATD9gXIpbwOKFQDTHyijkjagQAEw/YHyKmMDivImcJ2/EaMfKLg63xYuwnvChTgBmP5AZdQ5qYpwDihEAOph+gNlUZZ5lX8AipBBgOzlPv1yDoCHP0AlleJBUJ4BMP2BCit+A/J/BDQw0x8or4JPsNwCUE/0Cv67AxhUPXMsr0NAPgEw/YF4FLYBRX8EBECT5BAAL/+B2BTzEJB1AEx/IE4FbEDhHgGZ/kBVFW2+ZRqA3P/sDaDgspyT2QXAwx+AQj0IKtAjINMfiEFxZl1GAfDwB6B+2czMopwAipNEgGYryMTLIgBe/gMMVQaTsxAngILEECAzRZh7TQ/AoBErwm8BIHuDTr9mHwIKcQIAIHs5B8DLfyBm+c7A5gbA278AaTR1iuZ5AvDyHyDHSdjEAHj5D5Be82apN4EBIpVbADz/AeiT1zxsVgA8/wEIpUkTNZ8TgJf/AG+Vy1RsSgC8/AcIqxlz1ZvAAJHKIQCe/wC8U/az0QkAIFLhA+ANAIBmCD5dsz4BeP4DcD4ZT0iPgAAiFTgAnv8ANE/YGesEABCpTAPgDQCAgWU5J50AACIlAACRChkA7wADNFvASZvdCcAbAAD1yGxaegQEECkBAIiUAABESgAAIiUAAJEKFgCfAQXIRqh5m9EJwGdAAeqXzcz0CAggUgIAECkBAIiUAABESgAAIiUAAJESAIBICQBApAQAIFICABApAQCIlAAAREoAACIlAACREgCASAkAQKQEACBSAgAQKQEAiJQAAERKAAAiJQAAkRIAgEgJAECkBAAgUgIAECkBAIiUAABESgAAIiUAAJESAIBICQBApAQAIFICABApAQCIlAAAREoAACIlAACREgCASAkAQKQEACBSAgAQKQEAiJQAAERKAAAiJQAAkRIAgEgJAECkBAAgUgIAECkBAIiUAABESgAAIiUAAJESAIBICQBApAQAIFICABApAQCIlAAAREoAACIlAACREgCASAkAQKQEACBSAgAQKQEAiJQAAERKAAAi1Zb3Bujf1NlrNvzm95r9U073nPzfX1526sSrzf5BA1t61R+sfv+fh13zZ//381se/h9h1yyLtRtuu+jy32rqj+jp7rrrtvlN/RFkwAkgaq1tIxYs+5W8d0FIU2dftuSy38h7F5SDAMRu8cpP5r0FgmlpHb5+0x21mv9fUxf/Q4ndpBnLJ15wad67IIzl7/6j8VOX5L0LSkMASBav+lTeWyCACVOXLL3qD/LeBWUiACQLlv2H1tbhee+CVGq1lnWbvtLinyNDIQAkI0ZOnHPR9XnvglQuWnvT1Nlr8t4FJSMAJEmSdHgruMxGj5+96n2fyXsXlI8AkCRJMmPh1aPHz857FzRo3cbb24aNynsXlI8AkCRJUqu1LFrx8bx3QSMWLr9h5qJr8t4FpSQAvKFj5ceTpJb3Lhia9lGTL7/ur/LeBWUlALxhzIS5Mxa8K+9dMDRrN/z1iJET894FZSUAvKljlbeCy2T24g/Mv/Sjee+CEhMA3jT3oo3D28fnvQvqMmz4mCt+6W/y3gXlJgC8qbVtxIKl7oYrh9XXfm70uFl574JyEwDO4SlQKUybs3bJZb+e9y4oPQHgHJNnrHA3XMG1tg5ft+kOH9kiPQHg7RwCCm7Z1TePn7I4711QBQLA2y1c9h/dKVZYE6ddvPSq3897F1SEAPB2I0ZOnLtkQ967oB+1Wuu6TXe0tAzLeyNUhADQD0+BiuniK357yqzVee+C6hAA+jFj4Xt8xLBoxkyYu/KaP817F1SKANCPWq1l0Up3wxWLKz8JTgDoX8fKT/igYXEsWvHxGQvfk/cuqBoBoH9jJsyd7m64YmgfPeWyD/5l3rugggSA8+pY+Ym8t0CSJMnaDbe58pNmEADOa97FG4ePGJf3LmI3Z8mH5l/yy3nvgmoSAM6rta19wTJ3w+Vp2IixV1z/pbx3QWUJAAPxZfH5WnPtLaPGzsh7F1SWADCQyTNXTrzgkrx3Ealpc6+8cM2Nee+CKhMABuEQkIvWthHrN33ZJ3FpKgFgEAuX3+BuuOwtv/qPx03uyHsXVJwAMIgRIyfOWfKhvHcRl4kXXLp0/e/lvQuqTwAYnKdAWarVWtdvuqPW0pb3Rqg+AWBwMxe9d9S4mXnvIhaXXPk7k2euzHsXREEAGFyt1tKxwt1wWRg7cf6K94a68rN3z9bvB1qKahIA6rLI3XCZuHLj7W3DRgZZ6uc/u/PACz8NshRVJQDUZezEedPnX5X3LiquY+UnZyx4d5Cluo7t/9mDtwZZigoTAOrla8KaauSYaZd98POhVnvkH/+0++SxUKtRVQJAvdwN11RrN3xxePuEIEvtevbbnv5TDwGgXq1t7fOXfjTvXVTTnIs2zLt4Y5ClTh4//Oj3PhNkKSpPABgCT4GaYfiIcVdsCHbl52M/+IsTr78SajWqTQAYgikzV02YdlHeu6iaNR/4i1FjpwdZav+OH25/8u+DLEUMBCAivb2n0y+yeNWn0i/CWdPnX7V49a8FWaqn+/jD998cZCkiIQAReWXPv6f/ZMjCZe6GC6a1bcSVG28P9QcWmx/64muvvhBkKSIhABHp6T6+85lvpVxkxKhJc5ZcF2Q/rHjPn4ybtDDIUgf3PfHcI18LshTxEIC4dD5xV/pF3A0XxKTpyy5d97tBljpzpvvh+z4d5BEfURGAuBzc98ThA8+lXGTmovf6nsKUai1t6z/8lVBXfm758VcPv/xskKWIigBEJ/0hoFZrXbTS3XCpXLrudydNXxZkqaOHOp/64e1BliI2AhCdHU9948zpUykX6XA3XApjJy1Y8Z7/Emix3p/cd/Pp1P9AiZMAROfk8cPp7wkYO3H+9Pnrg+wnPrV1G29vbWsPstbWx/7OlZ80TABitO2J/5V+EW8FN2bx6l+bPv9dQZbqOrb/8X/6r0GWIk4CEKP9O/719SN7Uy4y9+KNw0aMDbKfeIwcc8Gaa28JtZorP0lJAGLU23sm/YUBbcNGLlj6K0H2E48rrv/S8PbxQZbateUfXPlJSgIQqc7NdydJb8pFOlZ+IshmIjHv4o1zL7o+yFInjx9+9Puu/CQtAYjUa6/u2b/zRykXmTJrtbvh6jS8ffzaDV8MtdpjP7jlxOsHQ61GtAQgXp3eCs7QZR/8y5FjpgVZav+Of93+5D1BliJyAhCvF57/7qkTr6ZcZOHyG1pahoXYTpVNX/DuUKXs6T7+8P3/OchSIADxOt1zcsfT30y5SPuoye6GG1hrW/u6jcH+UnfzQ7e58pNQBCBqngJlYOU1fzZ24vwgSx3c98Rzj/xtkKUgEYDI/eKlZ37x0tMpF5nZcY274c5n8owVl1z5O0GWcuUnwQlA7NL/VXCt1rpoxa8G2UzF1Fra1m26o1ZrDbKaKz8JTgBit/Ppb57uOZlyEX8Q0K+l639v0vSlQZZy5SfNIACxO3XiyAvP359ykbGTFlwwz91w5xg3edHyq/840GK9P7nv0678JDgBINkW5GvCVnkr+K1q6zZ+ubVtRJC1tj72dwdeeCTIUvBWAkDy0s4fpf9k4byLN7kb7qwL19x4wbx1QZbqOrrPlZ80iQCQJElv5+a7Uy7RNmzkgks/GmQ3ZTdq7IzV134u1Go/deUnTSMAJEmSdG6+u7f3TMpFPAXqc8X1Xxo+YlyQpXZt+Ye9P38gyFLwTgJAkiRJ19F9+7b/S8pFpsxaPWHqkhDbKbH5l/zynCUfCrKUKz9pNgHgDZ2bQ/xVcNyHgOHtE9Zu+OtQq7nyk2YTAN6wZ+sDJ7t+kXKRhcs/FvPdcJdfd2v76KlBlnLlJxkQAN5w5vSp7U99I+Ui7aMmz17ywSD7KZ0ZC69etOLjQZbq6e5y5ScZEADe5G64hrUNG7lu45dDrbb5oS+68pMMCABvevWVrQdffDzlIrM63jdq7PQg+ymRldf82ZgJc4MsdfDFx5975GtBloKBCQDn6Ez9V8ER3g03Zeaqi6/47SBL/f8rP9N+JBfqIQCcY+eWe3u6j6dcZFFMd8O1tAwLeOXnMz/+74cPPBdkKRiUAHCO7pPHdj/7nZSLjJu0MNRFCMW39Krfn3jBJUGWOnJw29M/DPZGAgxKAHi7zs0h7oaL463gcZM7ll19c6DFeh++/2ZXfpIlAeDtXt798NFf7Ei5yLxLNg0bPibIfgqstn7THa2tw4OstfWx/+nKTzImAPQj/VvBbcNGzV9a8bvhllz269PmXhFkqa6j+x5/0JWfZE0A6Mf2J+9J/92z1X4KNGrczMBXfp56LdRqUCcBoB/HX3v5xW0Pplxk6uw146t7N9yV138p1DOuXVvudeUnuRAA+pf+y+KTJFlc0c+Dzr/0o7MvvC7IUiePH370+58NshQMlQDQv73bHjzx+ispF6nk3XAjRk5c+6EvhFrtsQc+58pP8iIA9K/3TM/2J1PfDTd6yuwLPxBkP8Vx+XV/1T56SpCl9m3/l/QX8EHDBIDzCvIUqGJvBc9c9N6Fy28IslRPd9dPv+vKT/IkAJzX0UOdB/Y8mnKRWYvfP3LMBUH2k7u2YaOu/KXbQ632xD/f9tqre0KtBg0QAAaS/oLoKt0Nt+p9nxkzYU6QpQ6++Pjzj/5tkKWgYQLAQHZt+Xb6z6d3VOKzQFNmrb5o7U1BlnLlJwUhAAykp7tr95Zvp1xk3ORF0+ZeGWQ/eWlpGbZ+01dqtTD/f3nmR//NlZ8UgQAwiDB/EFDyL4tf+q4/nDDtoiBLHTm47el/uyPIUpCSADCIV/Y+duSVrSkXmXfJh8t7N9z4KRcuf/cfBVqs9+H7Pu3KTwpCABjcts13p1yhbdio+Zd+JMReslartazfdEdLwCs/U3+wCkIRAAa348l7zpzpTrlIRzmfAi25/Denzrk8yFKu/KRoBIDBneg6tHfrD1IuMnX2ZeOnXBhkP5lpaR2++n3BLur56T/+iSs/KRQBoC5hviasbIeAltZhbcNHB1lq15Z79/48bUQhLAGgLi92/nPXsf0pF1m0/IZaS1uQ/ZSLKz8pJgGgLr29p7c/eU/KRdpHT63e3XD1cOUnxRTjyzEa0/nEXcve9YdJUkuzyOKVn9zz/PdCbaksrvrIV6/6yFfz3kVIbcNG3XjLgaH+p5575Gv//sCfN2M/NMYJgHodO7zrpV0/SbnIrI73jxwzLch+gJQEgCEIcDdcS1tl7oaDshMAhmD3c/efOnk05SLVuBsOKkAAGILTPSd2PXNvykXGTe6YNmdtkP0AaQgAQxPma8JWfSr9IkBKAsDQHNq3+fDLz6ZcZP4lHw71B1ZAwwSAIUv/VnDb8NElvRsOqkQAGLIdT/+f9BcaL67Wl8VDGQkAQ3by+OE9W9P+MdfUOZePn7I4yH6AxggAjUj/FChJkg6HAMiVANCI/Tt++PqRvSkXWbTiY3HeDQcFIQA0orf3TGfqrwlrHz119uJrg+wHaIAA0KDOzXf39p5JuYinQJAjAaBBrx/Z+9LOf0u5yOzF17obDvIiADRu2xNpvyas1tK2cPnHgmwGGCoBoHF7nv/uyeOHUy7ibjjIiwDQuNOnT+18+pspFxk/ZfG0OZcH2Q8wJAJAKkHuhpvls0CQBwEglcMvbzm0/8mUi9RqrUE2AwyJAJBWZ+q3goFcCABp7XzmW6d7TuS9C2DIBIC0Tp04svu5+/PeBTBkAkAAngJBGQkAAby068fHDu/OexfA0AgAQfR2bnYIgJIRAMLYvvnv098NB2TJbeyE0XVs/77tD83qeH/eGwmp59Trd95a4rvqLl33n9Z84PPNWLmnu+uu2+Y3Y2Wy5ARAMEG+JgzIjAAQzJ6tD5zoOpT3LoB6CQDBnDnTveOpb+S9C6BeAkBI6b8hAMiMABDSkVe2Hnzx8bx3AdRFAAgsyAXRQAYEgMB2PXNvT3dX3rsABicABNZ96rXdz34n710AgxMAwvMUCEpBAAjvwAuPHD3UmfcugEEIAE3RufnuvLcADEIAaIrtT97Te6Yn710AAxEAmuL4awf2bnsw710AAxEAmsU3BEDBCQDNsnfbg8dfO5D3LoDzEgCapfdMz/Yn78l7F8B5CQBN5CkQFJkA0ERHD20/8MIjee8C6J8A0Fz+KhgKSwBort3Pfqf71Gt57wLohwDQXD3dXbueuTfvXQD9EACazlMgKCYBoOkOvvj4q69szXsXwNsJAFno9F3BUDwCQBZ2PPWNM2e6894FcA4BIAsnug7t2fpA3rsAziEAZKTTW8FQMAJARvZtf6jr6L68dwG8SQDISG/vGXfDQaEIANnp3HxXkvTmvQvgDQJAdo4d3v3Srh/nvQvgDQJApvxBABSHAJCp3c/dd+rEkbx3ASSJAJCx0z0ndz7zrbx3ASRJktTaR44JstBNXzg2wL96563TgvwUgEjceMtAX6n99c+OTf8jnAAAIiUAAJESAIBICQBApAQAIFICABApAQCIlAAAREoAACIlAACREgCASAkAQKQEACBSAgAQKQEAiJQAAERKAAAiJQAAkRIAgEgJAECkBAAgUgIAECkBAIiUAABESgAAIiUAAJESAIBICQBApAQAIFICABApAQCIlAAAREoAACIlAACREgCASAkAQKQEACBSAgAQKQEAiJQAAERKAAAiJQAAkRIAgEgJAECkBAAgUgIAECkBAIiUAABESgAAIiUAAJESAIBICQBApAQAIFICABApAQCIlAAAREoAACIlAACREgCASAkAQKQEACBSAgAQKQEAiJQAAERKAAAiJQAAkRIAgEgJAECkBAAgUgIAEKmMAnDjLQey+UEAFZDNzAwWgK9/dmyopQAYQKh56xEQQKQEACBSAgAQKQEAiJQAAEQquwD4JChAPTKbliED4JOgAM0WcNJ6BAQQKQEAiFSmAfA2AMDAspyTTgAAkQocAO8DAzRP2BnrBAAQqawD4G0AgPPJeEKGD4CnQADNEHy6egQEEKkcAuApEMA7ZT8bnQAAItWUAHgbACCsZszVfE4AngIBvFUuU7FZAXAIAAilSRM1t/cAHAIA+uQ1D70JDBCpJgbAUyCA9Jo3S/M8AXgKBJDjJGxuABwCANJo6hTN+T0AhwAgZvnOQG8CA0Sq6QEY9PziEADEadDp1+yn6IU4AWgAEJsizL0sAuCtYIChymByFuIEkBQjhgDZKMjEyygADgEA9ctmZhblBJAUJokATVWcWZddAOoJWnF+LwDNUM+Uy+yRSaYnAA+CAAaW5Zws0COgPg4BQFUVbb5lHQAPgoA4FerhT58cTgAaAMSmgNM/KeAjIACykU8AHAKAeBTz5X+S4wlAA4AYFHb6J8V/BKQBQHkVfILlGYA6o1fw3yBAv+qcXTn+gVTOJwANACqp+NM/yT0ASd7//QHykvv0yz8AdXIIAMqiLPOqEAHwIAiojFI8/OlTax85Ju89vOGmLxyr8995563TmroTgAbU/yK1CNM/KcgJoE/9vxFHAaBoSjf9k0IFINEAoJzKOP2TogUg0QCgbEo6/ZMCBiDRAKA8yjv9k0K9Cfw29b8nnHhbGMjckF6AFnD6J8U8AfQZ0u/LUQDIUgWmf1LkACQaABRSNaZ/UuRHQGcN6VlQ4nEQ0DRDfaFZ5OmfFPwE0Geov0FHAaAZKjb9k1KcAPoM9RyQOAoAgTTwsrL40z8pUQCShhqQyACQQmNPFEox/ZNyBaCPowCQjaq+8D+rfAFIHAWAJqv2C/+zShmApNEGJDIADKjhT5GUbvon5Q1An4YzkCgB8BZpPj1YxtHfp9wBSNI1IJEBiF7KD46Xd/onFQhAn5QZSJQAIpP+D4ZKPfr7VCQASYgG9FECqLBQfyhagemfVCkAfUJloI8YQAWEvR2gGqO/T9UCkIRuwFliACXSpCthqjT9k0oGoE+TMvA2qgC5y+b6r4qN/j6VDUCfbDIAVFglR3+figegjwwADajw6O8TRQDOUgJgUJWf+2fFFYA+MgD0K57R3yfGAJylBEAS39w/K+oA9JEBiFa0o7+PAJxDDKDyIh/6byUA/VMCqBhz/50EoC56AKVj4g9KABqnClAQZn1jBAAgUi15bwCAfAgAQKQEACBSAgAQKQEAiJQAAERKAAAiJQAAkRIAgEgJAECkBAAgUgIAECkBAIiUAABESgAAIiUAAJESAIBICQBApAQAIFICABApAQCIlAAAROr/AQlefRYh1dqaAAAAAElFTkSuQmCC
ICONEOF
        base64 -d > "$HUB_DIR/html/icon-192.png" << 'ICON192EOF'
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
ICON192EOF
        base64 -d > "$HUB_DIR/html/icon-maskable-512.png" << 'ICONMASKEOF'
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
ICONMASKEOF
        base64 -d > "$HUB_DIR/html/icon-maskable-192.png" << 'ICONMASK192EOF'
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
ICONMASK192EOF
        cat > "$HUB_DIR/html/manifest.json" << 'MANIFESTEOF'
{
  "name": "NEXUS404 Interface",
  "short_name": "NEXUS404",
  "start_url": ".",
  "display": "standalone",
  "background_color": "#08090c",
  "theme_color": "#08090c",
  "icons": [
    { "src": "icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any" },
    { "src": "icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" },
    { "src": "icon-maskable-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable" },
    { "src": "icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
MANIFESTEOF
        echo "${GREEN}[✓]${NC} Иконки и манифест созданы — 'Добавить на экран' теперь покажет"
        echo "    настоящую иконку, а не заглушку с бейджиком браузера"
    fi

    if [ ! -f "$HUB_DIR/html/sw.js" ]; then
        cat > "$HUB_DIR/html/sw.js" << 'SWEOF'
// Service Worker — без него push-уведомления невозможны в принципе:
// событие "push" может обработать только активный service worker,
// даже когда сама страница хаба закрыта или телефон заблокирован.
self.addEventListener('push', (event) => {
  let data = { title: 'NEXUS404', body: 'Новое уведомление' };
  try {
    if (event.data) data = event.data.json();
  } catch (e) { /* тело не JSON — используем заголовок по умолчанию */ }

  event.waitUntil(
    self.registration.showNotification(data.title || 'NEXUS404', {
      body: data.body || '',
      icon: '/icon-512.png',
      badge: '/icon-512.png',
      tag: 'nexus404-ntfy',
    })
  );
});

// Пустой pass-through fetch — не для кэша (оффлайн не нужен), а чтобы
// Chrome засчитал критерий устанавливаемости PWA (без него "Добавить на
// экран" давало обычный ярлык, а не полноценную установку).
self.addEventListener('fetch', (event) => {
  event.respondWith(fetch(event.request));
});

// Клик по уведомлению — открыть хаб (если уже открыт в какой-то вкладке,
// просто сфокусировать её, не плодить новые вкладки).
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      for (const client of windowClients) {
        if ('focus' in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow('/');
    })
  );
});
SWEOF
        echo "${GREEN}[✓]${NC} Service Worker создан: $HUB_DIR/html/sw.js"
    fi

    # cards.json — если карточки от других модулей уже накопились в TSV
    # (сервис-модуль отработал раньше хаба вручную/повторно) ИЛИ список
    # пока пуст — hub_regenerate_config создаёт файл в обоих случаях
    # (см. common.sh). Гарантирует, что файл существует ДО первого запроса
    # фронтенда, а не только "появится, когда кто-то что-то установит".
    hub_regenerate_config

    mkdir -p "$HUB_DIR/backend"
    if [ ! -f "$HUB_DIR/backend/app.py" ]; then
        cat > "$HUB_DIR/backend/app.py" << 'PYEOF'
#!/usr/bin/env python3
"""
NEXUS404 Interface — backend хаба. Только стандартная библиотека Python
(без pip-зависимостей — образ python:3.12-alpine, ничего доустанавливать
не нужно, контейнер стартует мгновенно).

Отдаёт:
  - статику фронтенда (/app/html)
  - /data/cards.json (генерируется common.sh:hub_regenerate_config на хосте)
  - /api/widgets/<id> — реальные данные виджетов (Beszel/Vaultwarden/ntfy),
    читает токены/БД, которые сервис-модули уже сохранили на диске, и сама
    стучится в API этих сервисов изнутри docker-сети (по имени контейнера).

Названия полей API Beszel/Vaultwarden сверены по исходникам (не угадывание):
  - Beszel:      github.com/henrygd/beszel, internal/entities/system/system.go
                 (структура Info: cpu, mp, dp, bb)
  - Vaultwarden: github.com/dani-garcia/vaultwarden, src/db/schema.rs
                 (таблицы users, ciphers)
"""
import base64
import math
import io
import re
import zipfile
import hashlib
import http.cookies
import json
import os
import secrets
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HTML_DIR = "/app/html"
DATA_DIR = "/app/data"

# Потокобезопасный генератор ID для транзакций WalletScope и постов
# MemoScope. Просто int(time.time()*1000) может совпасть при двух быстрых
# подряд запросах (миллисекундное разрешение, ThreadingHTTPServer — запросы
# из разных потоков реально успевают попасть в одну и ту же миллисекунду) —
# совпадение ID ломает edit/delete (находят не ту запись). Здесь — то же
# время, но с гарантией строгого возрастания и уникальности.
_id_lock = threading.Lock()
_last_generated_id = 0


def next_unique_id():
    global _last_generated_id
    with _id_lock:
        candidate = int(time.time() * 1000)
        if candidate <= _last_generated_id:
            candidate = _last_generated_id + 1
        _last_generated_id = candidate
        return candidate


# ============================================================
# ВХОД В ХАБ ЧЕРЕЗ POCKET ID (OIDC Authorization Code + PKCE)
#
# Хаб — единственная внешняя точка входа во всю систему, поэтому свой
# логин ему нужен обязательно, не косметика. Вместо своей системы паролей/
# сессий — хаб сам становится OIDC-клиентом Pocket ID, тем же протоколом,
# что уже работает у Vaultwarden/Forgejo (регистрация клиента — см.
# common.sh:dk_pocketid_oidc_register_client, вызывается из 04_nexus404.sh
# шаг 3). Адреса эндпоинтов сверены по исходникам Pocket ID (не угадывание):
# github.com/pocket-id/pocket-id, тег v2.13.0,
# backend/internal/controller/well_known_controller.go —
#   authorization_endpoint: {PUBLIC_URL}/authorize   (страница в браузере)
#   token_endpoint:         {INTERNAL_URL}/api/oidc/token      (сервер-сервер)
#   userinfo_endpoint:      {INTERNAL_URL}/api/oidc/userinfo   (сервер-сервер)
#
# ОГРАНИЧЕНИЕ (осознанное, не упущение): сессии и незавершённые попытки
# входа (LOGIN_STATES) хранятся в памяти процесса — при перезапуске
# контейнера (redeploy хаба) все залогиненные разлогинятся, придётся войти
# заново. Для личного использования это приемлемо; если понадобится
# переживать перезапуски — нужно вынести сессии во внешнее хранилище
# (Redis/файл), сейчас сознательно не делаем ради простоты.
# ============================================================
POCKETID_CLIENT_ID = os.environ.get("POCKETID_CLIENT_ID", "")
POCKETID_CLIENT_SECRET = os.environ.get("POCKETID_CLIENT_SECRET", "")
POCKETID_PUBLIC_URL = os.environ.get("POCKETID_PUBLIC_URL", "")
POCKETID_INTERNAL_URL = "http://dk_pocketid:1411"
HUB_PUBLIC_URL = os.environ.get("HUB_PUBLIC_URL", "")
AUTH_ENABLED = bool(POCKETID_CLIENT_ID and POCKETID_CLIENT_SECRET and POCKETID_PUBLIC_URL)

SESSION_COOKIE = "nexus_session"
SESSION_TTL = 12 * 3600       # 12 часов
LOGIN_STATE_TTL = 600         # 10 минут на прохождение входа

SESSIONS = {}       # session_id -> {"exp": ts, "email": str}
LOGIN_STATES = {}   # state -> {"verifier": str, "exp": ts}

# Простое ограничение частоты попыток входа по IP — без него /login и
# /auth/callback можно было дёргать сколько угодно раз подряд без всякого
# ограничения. Не заменяет fail2ban (тот банит на уровне firewall, здесь —
# только на уровне приложения, в памяти процесса), но закрывает конкретно
# этот путь атаки почти бесплатно.
LOGIN_ATTEMPTS = {}   # ip -> [ts, ts, ...]
LOGIN_RATE_LIMIT = 10       # попыток
LOGIN_RATE_WINDOW = 300     # за 5 минут


def check_login_rate_limit(ip):
    now = time.time()
    attempts = [t for t in LOGIN_ATTEMPTS.get(ip, []) if now - t < LOGIN_RATE_WINDOW]
    attempts.append(now)
    LOGIN_ATTEMPTS[ip] = attempts
    return len(attempts) <= LOGIN_RATE_LIMIT


def _cleanup_expired():
    now = time.time()
    for d in (SESSIONS, LOGIN_STATES):
        for k in [k for k, v in d.items() if v["exp"] < now]:
            del d[k]
    for ip in [ip for ip, times in LOGIN_ATTEMPTS.items() if not any(now - t < LOGIN_RATE_WINDOW for t in times)]:
        del LOGIN_ATTEMPTS[ip]


def make_pkce_pair():
    verifier = base64.urlsafe_b64encode(secrets.token_bytes(40)).rstrip(b"=").decode()
    challenge = base64.urlsafe_b64encode(
        hashlib.sha256(verifier.encode()).digest()
    ).rstrip(b"=").decode()
    return verifier, challenge


def build_authorize_url():
    _cleanup_expired()
    state = secrets.token_urlsafe(24)
    verifier, challenge = make_pkce_pair()
    LOGIN_STATES[state] = {"verifier": verifier, "exp": time.time() + LOGIN_STATE_TTL}
    params = {
        "response_type": "code",
        "client_id": POCKETID_CLIENT_ID,
        "redirect_uri": f"{HUB_PUBLIC_URL}/auth/callback",
        "scope": "openid profile email",
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
    }
    return f"{POCKETID_PUBLIC_URL}/authorize?{urllib.parse.urlencode(params)}"


def exchange_code_for_session(code, state):
    _cleanup_expired()
    login_state = LOGIN_STATES.pop(state, None)
    if not login_state:
        return None, "сессия входа истекла или недействительна, попробуйте снова"

    token_payload = urllib.parse.urlencode({
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": f"{HUB_PUBLIC_URL}/auth/callback",
        "client_id": POCKETID_CLIENT_ID,
        "client_secret": POCKETID_CLIENT_SECRET,
        "code_verifier": login_state["verifier"],
    }).encode()

    req = urllib.request.Request(
        f"{POCKETID_INTERNAL_URL}/api/oidc/token",
        data=token_payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            token_data = json.loads(resp.read())
    except Exception as e:
        return None, f"не удалось обменять код на токен: {e}"

    access_token = token_data.get("access_token")
    if not access_token:
        return None, "Pocket ID не вернула access_token"

    userinfo_req = urllib.request.Request(
        f"{POCKETID_INTERNAL_URL}/api/oidc/userinfo",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    try:
        with urllib.request.urlopen(userinfo_req, timeout=10) as resp:
            userinfo = json.loads(resp.read())
    except Exception as e:
        return None, f"не удалось получить данные пользователя: {e}"

    session_id = secrets.token_urlsafe(32)
    SESSIONS[session_id] = {
        "exp": time.time() + SESSION_TTL,
        "email": userinfo.get("email", ""),
    }
    return session_id, None


def get_session(handler):
    cookie_header = handler.headers.get("Cookie", "")
    cookies = http.cookies.SimpleCookie()
    cookies.load(cookie_header)
    if SESSION_COOKIE not in cookies:
        return None
    session_id = cookies[SESSION_COOKIE].value
    session = SESSIONS.get(session_id)
    if not session or session["exp"] < time.time():
        SESSIONS.pop(session_id, None)
        return None
    return session

BESZEL_TOKEN_FILE = "/secrets/beszel/admin_authtoken"
BESZEL_API = "http://dk_beszel:8090"

VAULT_DB_FILE = "/secrets/vaultwarden-data/db.sqlite3"

NTFY_TOKEN_FILE = "/secrets/ntfy/hub_reader_token"
NTFY_TOPIC_FILE = "/secrets/ntfy/topic_name"
NTFY_API = "http://dk_ntfy:80"

FORGEJO_TOKEN_FILE = "/secrets/forgejo/hub_widget_token"
FORGEJO_API = "http://dk_forgejo:3000"

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
# соблюдается даже при параллельных запросах (см. CheevoRateLimiter). Не
# трогать без причины — см. обоснование в оригинальном проекте: 0.25с (4
# запроса/сек) на практике не приводит к 429 даже на 400+ играх.
CHEEVO_REQUEST_DELAY = 0.25
CHEEVO_API_CONCURRENCY = 10
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

CHEEVO_RA_REQUEST_DELAY = 0.5
CHEEVO_RA_CONCURRENCY = 3

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
# MEMOSCOPE — свой блог/заметки, тоже прямо на диске хаба. Картинка к
# посту хранится файлом (не в самом JSON — не раздувать его base64),
# отдаётся через отдельный маршрут с той же проверкой сессии, что и весь
# остальной хаб (см. do_GET — этот путь НЕ в списке публичных PWA-файлов).
# ============================================================
MEMOSCOPE_FILE = "/app/data/memoscope_posts.json"
MEMOSCOPE_IMAGES_DIR = "/app/data/memoscope_images"

# ============================================================
# PUSH-УВЕДОМЛЕНИЯ (Web Push) — реальные пуши на телефон/десктоп при
# новом сообщении в ntfy, даже когда хаб не открыт. Шифрование и
# VAPID-подпись — через pywebpush (см. заголовок файла шапки модуля,
# почему не самописная крипто: в stdlib Python нет AES вообще).
# ============================================================
VAPID_PRIVATE_KEY_FILE = "/app/data/vapid_private.pem"
VAPID_PUBLIC_KEY_FILE = "/app/data/vapid_public.txt"
PUSH_SUBSCRIPTIONS_FILE = "/app/data/push_subscriptions.json"
NTFY_PUSH_LAST_CHECK_FILE = "/app/data/ntfy_push_last_check.txt"
PUSH_POLL_INTERVAL = 20  # секунд между опросами ntfy на новые сообщения


def read_file(path):
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except OSError:
        return None


def http_get(url, headers=None, timeout=30):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status, resp.read()


def http_post(url, headers=None, timeout=30):
    req = urllib.request.Request(url, headers=headers or {}, method="POST", data=b"")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status, resp.read()


# ============================================================
# BESZEL — CPU/RAM/диск/сеть последней системы (не весь веб-интерфейс)
# ============================================================
def widget_beszel():
    token = read_file(BESZEL_TOKEN_FILE)
    if not token:
        return {"error": "нет сохранённого токена Beszel — пройдите шаг 2 модуля Beszel заново"}

    # perPage=50, не 1 — Beszel следит не только за этим сервером (хаб +
    # агенты на других серверах), карточек может быть больше одной. Порядок
    # по имени — стабильный, не "последний обновившийся" (перескакивал бы
    # местами между запросами).
    url = f"{BESZEL_API}/api/collections/systems/records?perPage=50&sort=name"
    try:
        status, body = http_get(url, headers={"Authorization": token})
    except urllib.error.HTTPError as e:
        if e.code == 401:
            # Токен PocketBase мог протухнуть — пробуем обновить тем же
            # токеном (стандартный auth-refresh PocketBase), сохраняем
            # новый и повторяем запрос один раз.
            try:
                _, refresh_body = http_post(
                    f"{BESZEL_API}/api/collections/users/auth-refresh",
                    headers={"Authorization": token},
                )
                new_token = json.loads(refresh_body).get("token")
                if new_token:
                    with open(BESZEL_TOKEN_FILE, "w") as f:
                        f.write(new_token)
                    status, body = http_get(url, headers={"Authorization": new_token})
                else:
                    return {"error": "токен Beszel истёк, обновить не удалось — перезайдите в шаг 2 модуля Beszel"}
            except Exception:
                return {"error": "токен Beszel истёк, обновить не удалось — перезайдите в шаг 2 модуля Beszel"}
        else:
            return {"error": f"Beszel API вернул ошибку HTTP {e.code}"}
    except Exception as e:
        return {"error": f"не удалось достучаться до Beszel: {e}"}

    try:
        items = json.loads(body).get("items", [])
    except json.JSONDecodeError:
        return {"error": "Beszel вернул нечитаемый ответ"}
    if not items:
        return {"error": "в Beszel пока нет ни одной системы"}

    systems = []
    for item in items:
        info = item.get("info", {})
        systems.append({
            "name": item.get("name", "сервер"),
            "status": item.get("status", ""),
            "cpu_pct": round(info.get("cpu", 0), 1),
            "mem_pct": round(info.get("mp", 0), 1),
            "disk_pct": round(info.get("dp", 0), 1),
            # "bb" — сумма отправленных+полученных байт за последний интервал
            # опроса агента (не обязательно ровно 1 секунда — Beszel сам
            # решает интервал), показываем как есть, не выдавая за точную
            # "скорость".
            "network_bytes_recent": info.get("bb", 0),
        })
    return {"systems": systems}


# ============================================================
# VAULTWARDEN — количество пользователей и записей (не сами пароли,
# читать расшифрованные данные сервер физически не может — zero-knowledge)
# ============================================================
def widget_vaultwarden():
    if not os.path.exists(VAULT_DB_FILE):
        return {"error": "база данных Vaultwarden пока не найдена — сервис ещё не установлен?"}

    for attempt in range(3):
        try:
            conn = sqlite3.connect(f"file:{VAULT_DB_FILE}?mode=ro", uri=True, timeout=3)
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM users")
            users = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM ciphers WHERE deleted_at IS NULL")
            items = cur.fetchone()[0]
            conn.close()
            return {"users": users, "items": items}
        except sqlite3.OperationalError:
            time.sleep(0.3)
    return {"error": "база данных Vaultwarden временно занята — попробуйте обновить чуть позже"}


# ============================================================
# NTFY — последние уведомления из топика (только чтение, отдельный токен)
# ============================================================
def widget_ntfy():
    token = read_file(NTFY_TOKEN_FILE)
    topic = read_file(NTFY_TOPIC_FILE)
    if not token or not topic:
        return {"error": "ntfy ещё не установлен или не сохранил токен/топик"}

    url = f"{NTFY_API}/{topic}/json?poll=1&since=24h"
    try:
        status, body = http_get(url, headers={"Authorization": f"Bearer {token}"})
    except Exception as e:
        return {"error": f"не удалось достучаться до ntfy: {e}"}

    messages = []
    deleted_ids = set()
    for line in body.decode("utf-8", errors="ignore").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        # "message_delete" — не настоящее удаление на стороне ntfy (это
        # публикация отдельного события-маркера с тем же sequence_id/id,
        # см. common.sh:widget_ntfy — исходники ntfy: handleActionMessage),
        # исходное сообщение остаётся в кэше ntfy. Фильтруем здесь сами —
        # для пользователя хаба это неотличимо от настоящего удаления.
        if msg.get("event") == "message_delete":
            deleted_ids.add(msg.get("sequence_id") or msg.get("id"))
            continue
        if msg.get("event") == "message":
            messages.append({
                "id": msg.get("id"),
                "title": msg.get("title", ""),
                "message": msg.get("message", ""),
                "time": msg.get("time", 0),
            })
    messages = [m for m in messages if m["id"] not in deleted_ids]
    messages.sort(key=lambda m: m["time"], reverse=True)
    return {"messages": messages[:10]}


def widget_ntfy_delete(msg_id):
    token = read_file(NTFY_TOKEN_FILE)
    topic = read_file(NTFY_TOPIC_FILE)
    if not token or not topic:
        return {"error": "ntfy ещё не установлен или не сохранил токен/топик"}
    if not msg_id or not msg_id.isalnum():
        return {"error": "некорректный id сообщения"}

    url = f"{NTFY_API}/{topic}/{msg_id}"
    req = urllib.request.Request(url, method="DELETE", headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            resp.read()
        return {"ok": True}
    except Exception as e:
        return {"error": f"не удалось удалить: {e}"}


# ============================================================
# FORGEJO — список репозиториев (без редактора/файлового браузера — по
# решению; нужны только список, скачивание архива и прямая ссылка). Формат
# полей ответа API сверен по исходникам Forgejo (modules/structs/repo.go):
# name, full_name, description, size, updated_at, private, default_branch.
# Заголовок авторизации — "token <X>" (эквивалентен "Bearer <X>", проверено
# по исходникам services/auth: httpauth.ParseAuthorizationHeader принимает
# оба варианта одинаково).
# ============================================================
def widget_forgejo():
    token = read_file(FORGEJO_TOKEN_FILE)
    if not token:
        return {"error": "нет сохранённого токена Forgejo — пройдите шаг 8 модуля Forgejo заново"}

    url = f"{FORGEJO_API}/api/v1/user/repos?limit=50"
    try:
        status, body = http_get(url, headers={"Authorization": f"token {token}"})
    except Exception as e:
        return {"error": f"не удалось достучаться до Forgejo: {e}"}

    try:
        repos = json.loads(body)
    except json.JSONDecodeError:
        return {"error": "Forgejo вернул нечитаемый ответ"}

    return {"repos": [
        {
            "name": r.get("name"),
            "full_name": r.get("full_name"),
            "description": r.get("description") or "",
            "size_kb": r.get("size", 0),
            "updated_at": r.get("updated_at", ""),
            "private": r.get("private", False),
            "default_branch": r.get("default_branch", "master"),
            "html_url": r.get("html_url", ""),
        }
        for r in repos
    ]}


def forgejo_download_proxy(full_name, handler):
    """Скачивание архива репозитория — токен остаётся на сервере, в браузер
    никогда не попадает (тот же принцип, что и у остальных прокси-вызовов).
    Отдаёт файл потоково, не грузя целиком в память — архивы репозиториев
    могут быть большими."""
    token = read_file(FORGEJO_TOKEN_FILE)
    if not token:
        handler._send_json({"error": "нет сохранённого токена Forgejo"}, status=503)
        return
    # full_name — "owner/repo", проверяем формат заранее (защита от path
    # injection в URL — тот же приём, что и в widget_ntfy_delete)
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", full_name or ""):
        handler._send_json({"error": "некорректное имя репозитория"}, status=400)
        return

    info_url = f"{FORGEJO_API}/api/v1/repos/{full_name}"
    try:
        _, info_body = http_get(info_url, headers={"Authorization": f"token {token}"})
        branch = json.loads(info_body).get("default_branch", "master")
    except Exception as e:
        handler._send_json({"error": f"не удалось получить репозиторий: {e}"}, status=502)
        return

    archive_url = f"{FORGEJO_API}/api/v1/repos/{full_name}/archive/{branch}.zip"
    req = urllib.request.Request(archive_url, headers={"Authorization": f"token {token}"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            repo_short = full_name.split("/")[-1]
            handler.send_response(200)
            handler.send_header("Content-Type", "application/zip")
            handler.send_header("Content-Disposition", f'attachment; filename="{repo_short}.zip"')
            handler.send_header("X-Content-Type-Options", "nosniff")
            handler.end_headers()
            while True:
                chunk = resp.read(65536)
                if not chunk:
                    break
                handler.wfile.write(chunk)
    except Exception as e:
        handler._send_json({"error": f"не удалось скачать архив: {e}"}, status=502)


def parse_multipart(content_type, body):
    """Разбор multipart/form-data вручную — в стандартной библиотеке Python
    нет готового парсера форм для http.server (cgi.FieldStorage удалён в
    новых версиях Python). Проверено тестами на текстовых полях, бинарном
    ZIP-содержимом и файле с завершающим "\\n" в конце (см. историю — первая
    версия на .strip(b'\\r\\n') портила такой файл, strip трактует аргумент
    как набор символов, а не точную подстроку — заменено на точные срезы)."""
    if "boundary=" not in content_type:
        return None, None
    boundary = content_type.split("boundary=")[1].strip()
    if boundary.startswith('"') and boundary.endswith('"'):
        boundary = boundary[1:-1]
    boundary_bytes = ("--" + boundary).encode()

    parts = body.split(boundary_bytes)
    fields = {}
    files = []
    for part in parts:
        if not part or part in (b"--", b"--\r\n", b"\r\n"):
            continue
        if part.startswith(b"\r\n"):
            part = part[2:]
        if part.endswith(b"\r\n"):
            part = part[:-2]
        if b"\r\n\r\n" not in part:
            continue
        headers_blob, content = part.split(b"\r\n\r\n", 1)
        headers_text = headers_blob.decode("utf-8", errors="ignore")
        name_match = re.search(r'name="([^"]*)"', headers_text)
        filename_match = re.search(r'filename="([^"]*)"', headers_text)
        if not name_match:
            continue
        name = name_match.group(1)
        if filename_match and filename_match.group(1):
            files.append((name, filename_match.group(1), content))
        else:
            fields[name] = content.decode("utf-8", errors="ignore")
    return fields, files


def forgejo_api_request(method, path, token, json_body=None):
    """Общий helper для JSON-запросов к API Forgejo (не для скачивания
    файлов — там нужен потоковый доступ, см. forgejo_download_proxy)."""
    url = f"{FORGEJO_API}{path}"
    data = json.dumps(json_body).encode() if json_body is not None else None
    req = urllib.request.Request(
        url, data=data, method=method,
        headers={"Authorization": f"token {token}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.status, json.loads(resp.read() or b"{}")


def forgejo_create_file(full_name, token, filepath, content_bytes, message):
    """POST /repos/{owner}/{repo}/contents/{filepath} — создание одного
    файла (см. modules/structs/repo_file.go: CreateFileOptions —
    ContentBase64, message)."""
    encoded = base64.b64encode(content_bytes).decode()
    # filepath может содержать "/" (вложенные папки) — это часть URL, не
    # query-параметр, urllib.parse.quote с safe="/" сохраняет разделители
    quoted_path = urllib.parse.quote(filepath, safe="/")
    return forgejo_api_request(
        "POST", f"/api/v1/repos/{full_name}/contents/{quoted_path}", token,
        {"content": encoded, "message": message},
    )


def widget_forgejo_upload_files(full_name, handler):
    """Загрузка одного/нескольких файлов в УЖЕ существующий репозиторий —
    каждый файл своим отдельным коммитом (у Forgejo нет REST-эндпоинта
    "закоммитить пачку файлов одним коммитом" без применения git-патча
    вручную — не делаем этого ради надёжности, чуть медленнее, зато просто
    и предсказуемо)."""
    token = read_file(FORGEJO_TOKEN_FILE)
    if not token:
        handler._send_json({"error": "нет сохранённого токена Forgejo"}, status=503)
        return
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", full_name or ""):
        handler._send_json({"error": "некорректное имя репозитория"}, status=400)
        return

    content_length = int(handler.headers.get("Content-Length", 0))
    if content_length <= 0:
        handler._send_json({"error": "пустой запрос"}, status=400)
        return
    body = handler.rfile.read(content_length)
    _, files = parse_multipart(handler.headers.get("Content-Type", ""), body)
    if not files:
        handler._send_json({"error": "файлы не найдены в запросе"}, status=400)
        return

    uploaded, errors = [], []
    for _, filename, content in files:
        try:
            status, _ = forgejo_create_file(full_name, token, filename, content, f"Загружено через хаб: {filename}")
            uploaded.append(filename)
        except urllib.error.HTTPError as e:
            errors.append(f"{filename}: HTTP {e.code}")
        except Exception as e:
            errors.append(f"{filename}: {e}")

    handler._send_json({"uploaded": uploaded, "errors": errors})


def widget_forgejo_upload_zip(handler):
    """Создание НОВОГО репозитория из ZIP — распаковываем на стороне
    сервера (io.BytesIO, без временных файлов на диске) и заливаем каждый
    файл через API поштучно. Директории и служебные файлы архива (__MACOSX,
    .DS_Store) пропускаем."""
    token = read_file(FORGEJO_TOKEN_FILE)
    if not token:
        handler._send_json({"error": "нет сохранённого токена Forgejo"}, status=503)
        return

    content_length = int(handler.headers.get("Content-Length", 0))
    if content_length <= 0:
        handler._send_json({"error": "пустой запрос"}, status=400)
        return
    body = handler.rfile.read(content_length)
    fields, files = parse_multipart(handler.headers.get("Content-Type", ""), body)
    if not fields or not files:
        handler._send_json({"error": "не удалось разобрать форму"}, status=400)
        return

    repo_name = (fields.get("repo_name") or "").strip()
    if not re.fullmatch(r"[\w.-]+", repo_name or ""):
        handler._send_json({"error": "некорректное имя репозитория (буквы/цифры/-/_/. без пробелов)"}, status=400)
        return
    private = fields.get("private") == "true"
    zip_content = files[0][2]

    try:
        status, repo_data = forgejo_api_request(
            "POST", "/api/v1/user/repos", token,
            {"name": repo_name, "private": private, "auto_init": True},
        )
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="ignore")
        handler._send_json({"error": f"не удалось создать репозиторий (HTTP {e.code}): {detail}"}, status=502)
        return
    except Exception as e:
        handler._send_json({"error": f"не удалось создать репозиторий: {e}"}, status=502)
        return

    full_name = repo_data.get("full_name")
    if not full_name:
        handler._send_json({"error": "Forgejo не вернула full_name созданного репозитория"}, status=502)
        return

    uploaded, errors = [], []
    try:
        with zipfile.ZipFile(io.BytesIO(zip_content)) as zf:
            for info in zf.infolist():
                if info.is_dir():
                    continue
                name = info.filename
                if "__MACOSX" in name or name.endswith(".DS_Store"):
                    continue
                try:
                    data = zf.read(info)
                    forgejo_create_file(full_name, token, name, data, f"Импорт из ZIP: {name}")
                    uploaded.append(name)
                except Exception as e:
                    errors.append(f"{name}: {e}")
    except zipfile.BadZipFile:
        handler._send_json({"error": "файл повреждён или не является ZIP-архивом", "repo_created": full_name}, status=400)
        return

    handler._send_json({"repo": full_name, "uploaded": uploaded, "errors": errors})


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

def cheevo_get_steam_game_achievements(appid):
    schema = cheevo_cached_call(f"schema_ru_{appid}", lambda: cheevo_get_schema_for_game(appid),
                                 ttl_hours=CHEEVO_ACHIEVEMENT_SCHEMA_CACHE_TTL_HOURS)
    if not schema:
        return {"appid": appid, "available": False, "achievements": []}

    global_pct = cheevo_cached_call(f"global_pct_{appid}", lambda: cheevo_get_global_achievement_percentages(appid),
                                     ttl_hours=CHEEVO_CACHE_TTL_HOURS)
    pct_by_name = {a["name"]: a.get("percent") for a in global_pct}

    player_data = cheevo_get_player_achievements(appid)
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
            "steam": {"summary": {}, "games": [], "rarity_tiers": {}, "rarest": [], "heatmap": {}},
            "retro": None,
        }

    retro_report = {}
    if _cheevo_ra_username() and _cheevo_ra_api_key():
        retro_report = cheevo_ra_load_retro_report()

    retro_summary = (retro_report or {}).get("summary") or {}
    has_retro = bool(retro_summary.get("games_count"))

    return {
        "generated_at": steam_report.get("generated_at"),
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


def ensure_vapid_keys():
    """Генерирует пару VAPID-ключей один раз при первом запуске и сохраняет
    на диск (volume, переживает перезапуск контейнера) — иначе каждый
    перезапуск хаба означал бы новый ключ и все существующие подписки
    браузеров стали бы недействительными."""
    if os.path.exists(VAPID_PRIVATE_KEY_FILE) and os.path.exists(VAPID_PUBLIC_KEY_FILE):
        return
    from py_vapid import Vapid
    from cryptography.hazmat.primitives import serialization

    v = Vapid()
    v.generate_keys()
    with open(VAPID_PRIVATE_KEY_FILE, "wb") as f:
        f.write(v.private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        ))
    pub_raw = v.public_key.public_bytes(
        encoding=serialization.Encoding.X962,
        format=serialization.PublicFormat.UncompressedPoint,
    )
    pub_b64url = base64.urlsafe_b64encode(pub_raw).decode().rstrip("=")
    with open(VAPID_PUBLIC_KEY_FILE, "w") as f:
        f.write(pub_b64url)


def load_push_subscriptions():
    if not os.path.exists(PUSH_SUBSCRIPTIONS_FILE):
        return []
    try:
        return json.loads(read_file(PUSH_SUBSCRIPTIONS_FILE) or "[]")
    except json.JSONDecodeError:
        return []


def save_push_subscriptions(subs):
    with open(PUSH_SUBSCRIPTIONS_FILE, "w") as f:
        json.dump(subs, f)


def widget_push_subscribe(handler):
    content_length = int(handler.headers.get("Content-Length", 0))
    if content_length <= 0:
        handler._send_json({"error": "пустой запрос"}, status=400)
        return
    try:
        sub = json.loads(handler.rfile.read(content_length))
    except json.JSONDecodeError:
        handler._send_json({"error": "некорректный JSON"}, status=400)
        return
    if not sub.get("endpoint") or not sub.get("keys", {}).get("p256dh") or not sub.get("keys", {}).get("auth"):
        handler._send_json({"error": "неполная подписка (нет endpoint/keys)"}, status=400)
        return

    subs = load_push_subscriptions()
    # Не дублируем — один и тот же браузер может прислать ту же подписку
    # повторно (например, если страницу открыли на двух вкладках).
    subs = [s for s in subs if s.get("endpoint") != sub["endpoint"]]
    subs.append(sub)
    save_push_subscriptions(subs)
    handler._send_json({"ok": True})


def widget_push_unsubscribe(handler):
    content_length = int(handler.headers.get("Content-Length", 0))
    body = handler.rfile.read(content_length) if content_length > 0 else b"{}"
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        data = {}
    endpoint = data.get("endpoint")
    subs = load_push_subscriptions()
    subs = [s for s in subs if s.get("endpoint") != endpoint]
    save_push_subscriptions(subs)
    handler._send_json({"ok": True})


def _compact_for_push(text, max_len):
    """Сжимает текст для push-баннера: многострочные детали (частый формат
    у notify_send — "Логин: X\\nАдрес: Y\\nСпособ: Z") сводим в одну строку
    через " · ", затем обрезаем по длине. Полный, неурезанный текст всё
    равно виден в самом виджете хаба — здесь сокращаем только то, что
    реально ложится в баннер уведомления на телефоне."""
    if not text:
        return ""
    one_line = " · ".join(line.strip() for line in text.split("\n") if line.strip())
    if len(one_line) > max_len:
        one_line = one_line[:max_len - 1].rstrip() + "…"
    return one_line


def send_push_to_all(msg):
    """Шлёт одно ntfy-сообщение всем сохранённым подпискам. Недействительные
    подписки (410/404 — пользователь снял разрешение или удалил PWA) сами
    удаляются из хранилища; временные ошибки (сеть, 5xx у push-сервиса) —
    подписку не трогаем, попробуем в следующий раз."""
    subs = load_push_subscriptions()
    if not subs:
        print(f"[push] нет сохранённых подписок — некому слать", flush=True)
        return
    from pywebpush import webpush, WebPushException

    title = _compact_for_push(msg.get("title") or "Уведомление", 60)
    body_text = _compact_for_push(msg.get("message", ""), 100)
    payload = json.dumps({"title": title, "body": body_text})

    remaining = []
    changed = False
    for sub in subs:
        try:
            webpush(
                subscription_info=sub,
                data=payload,
                vapid_private_key=VAPID_PRIVATE_KEY_FILE,
                vapid_claims={"sub": "mailto:admin@localhost"},
            )
            remaining.append(sub)
            print(f"[push] отправлено на {sub.get('endpoint', '?')[:60]}...", flush=True)
        except WebPushException as e:
            status_code = getattr(getattr(e, "response", None), "status_code", None)
            resp_text = ""
            try:
                resp_text = getattr(e, "response", None).text[:200]
            except Exception:
                pass
            print(f"[push] WebPushException status={status_code} body={resp_text!r} endpoint={sub.get('endpoint', '?')[:60]}", flush=True)
            if status_code in (404, 410):
                changed = True
                continue
            remaining.append(sub)
        except Exception as e:
            print(f"[push] непредвиденная ошибка отправки: {type(e).__name__}: {e}", flush=True)
            remaining.append(sub)
    if changed:
        save_push_subscriptions(remaining)


def check_ntfy_for_push():
    token = read_file(NTFY_TOKEN_FILE)
    topic = read_file(NTFY_TOPIC_FILE)
    if not token or not topic:
        print(f"[push] нет токена/топика ntfy (token={bool(token)}, topic={bool(topic)}) — пропускаю опрос", flush=True)
        return

    last_ts_raw = read_file(NTFY_PUSH_LAST_CHECK_FILE)
    if last_ts_raw and last_ts_raw.isdigit():
        last_ts = int(last_ts_raw)
    else:
        # Первый запуск — сохраняем "сейчас" сразу, иначе без файла since
        # всегда "сейчас" и сообщения никогда не находятся.
        last_ts = int(time.time())
        with open(NTFY_PUSH_LAST_CHECK_FILE, "w") as f:
            f.write(str(last_ts))
    since = last_ts + 1

    url = f"{NTFY_API}/{topic}/json?poll=1&since={since}"
    try:
        _, body = http_get(url, headers={"Authorization": f"Bearer {token}"})
    except Exception as e:
        print(f"[push] не удалось опросить ntfy ({url}): {type(e).__name__}: {e}", flush=True)
        return

    max_ts = last_ts
    found_any = False
    for line in body.decode("utf-8", errors="ignore").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if msg.get("event") != "message":
            continue
        found_any = True
        if msg.get("time", 0) > max_ts:
            max_ts = msg.get("time", 0)
        print(f"[push] новое сообщение ntfy: {msg.get('title', '')!r} / {msg.get('message', '')!r}", flush=True)
        send_push_to_all(msg)

    if not found_any:
        # Тихо в норме (нет новых сообщений большую часть времени) — но
        # печатаем изредка (раз в ~10 опросов), чтобы было видно в логе,
        # что фоновый поток вообще жив и реально ходит в ntfy, а не
        # застрял/упал где-то до этого места.
        if int(time.time()) % (PUSH_POLL_INTERVAL * 10) < PUSH_POLL_INTERVAL:
            print(f"[push] опрос прошёл, новых сообщений нет (since={since})", flush=True)

    if max_ts > last_ts:
        with open(NTFY_PUSH_LAST_CHECK_FILE, "w") as f:
            f.write(str(max_ts))


def ntfy_push_worker():
    while True:
        try:
            check_ntfy_for_push()
        except Exception as e:
            print(f"[push] ntfy_push_worker упал на такте: {type(e).__name__}: {e}", flush=True)
        time.sleep(PUSH_POLL_INTERVAL)


WIDGETS = {
    "beszel-metrics": widget_beszel,
    "vaultwarden-meta": widget_vaultwarden,
    "ntfy-feed": widget_ntfy,
    "forgejo-repos": widget_forgejo,
    "cheevoscope-stats": widget_cheevoscope,
    "walletscope-data": widget_walletscope,
    "memoscope-posts": widget_memoscope,
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # тихо — логи docker и так есть через `docker logs`, дублировать незачем

    def _security_headers(self):
        # X-Frame-Options — запрещает встраивать сам хаб в чужой iframe
        # (защита от clickjacking). Сам хаб никого ни во что не встраивает —
        # все сервисы отдают данные только через собственный API хаба.
        self.send_header("X-Frame-Options", "SAMEORIGIN")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "same-origin")

    def _send_json(self, obj, status=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._security_headers()
        self.end_headers()
        # HEAD — только заголовки, без тела (см. do_HEAD = do_GET ниже).
        if self.command != "HEAD":
            self.wfile.write(body)

    def _send_file(self, path, content_type):
        try:
            with open(path, "rb") as f:
                body = f.read()
        except OSError:
            self.send_response(404)
            self._security_headers()
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self._security_headers()
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _redirect(self, location, set_cookie=None, clear_cookie=False):
        self.send_response(302)
        self.send_header("Location", location)
        if set_cookie:
            self.send_header(
                "Set-Cookie",
                f"{SESSION_COOKIE}={set_cookie}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age={SESSION_TTL}",
            )
        if clear_cookie:
            self.send_header("Set-Cookie", f"{SESSION_COOKIE}=; Path=/; Max-Age=0")
        self._security_headers()
        self.end_headers()

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)

        # ---- auth-маршруты — доступны ВСЕГДА, без проверки сессии
        # (иначе замкнутый круг: чтобы войти, потребовался бы уже вход) ----
        if path == "/login":
            if not AUTH_ENABLED:
                self._send_json({"error": "вход через Pocket ID не настроен — см. модуль NEXUS404, шаг 3"}, status=503)
                return
            if not check_login_rate_limit(self.client_address[0]):
                self._send_json({"error": "слишком много попыток входа, подождите несколько минут"}, status=429)
                return
            self._redirect(build_authorize_url())
            return

        if path == "/auth/callback":
            if not AUTH_ENABLED:
                self._send_json({"error": "вход через Pocket ID не настроен"}, status=503)
                return
            if not check_login_rate_limit(self.client_address[0]):
                self._send_json({"error": "слишком много попыток входа, подождите несколько минут"}, status=429)
                return
            code = query.get("code", [None])[0]
            state = query.get("state", [None])[0]
            if not code or not state:
                self._send_json({"error": "нет code/state в ответе Pocket ID"}, status=400)
                return
            session_id, error = exchange_code_for_session(code, state)
            if error:
                self._send_json({"error": error}, status=400)
                return
            self._redirect("/", set_cookie=session_id)
            return

        if path == "/logout":
            self._redirect("/", clear_cookie=True)
            return

        # /api/auth-check — сюда обращается Caddy (forward_auth) ПЕРЕД тем,
        # как пустить запрос на защищённые пути других сервисов (сейчас —
        # веб-часть Forgejo, см. modules/08_forgejo.sh). Caddy шлёт сюда
        # копию оригинального запроса (включая куки) и смотрит только на
        # код ответа — 2xx значит "пускать", что угодно ещё значит "нет".
        # Та же логика, что и для самого хаба: если Pocket ID вообще не
        # настроен (AUTH_ENABLED=false), не блокируем — это уже было решено
        # раньше для хаба, здесь просто то же самое поведение.
        if path == "/api/auth-check":
            if AUTH_ENABLED and not get_session(self):
                self.send_response(401)
                self._security_headers()
                self.end_headers()
                return
            self.send_response(200)
            self._security_headers()
            self.end_headers()
            return

        if path == "/api/push/vapid-public-key":
            key = read_file(VAPID_PUBLIC_KEY_FILE) or ""
            self._send_json({"key": key})
            return

        # PWA-ресурсы (манифест/иконки/service worker) — ДОСТУПНЫ БЕЗ СЕССИИ.
        # Без этого исключения браузер получал бы 302 на /login вместо
        # самого manifest.json (не может распарсить редирект как JSON) —
        # Chrome тогда не проходит проверку устанавливаемости PWA и
        # "Добавить на экран" сохраняет обычный ярлык вместо полноценного
        # приложения. Ничего секретного в этих файлах нет — они и так
        # предназначены быть публичными на любом сайте.
        PWA_PUBLIC_FILES = {
            "/manifest.json": "application/manifest+json",
            "/sw.js": "application/javascript",
            "/icon-192.png": "image/png",
            "/icon-512.png": "image/png",
            "/icon-maskable-192.png": "image/png",
            "/icon-maskable-512.png": "image/png",
        }
        if path in PWA_PUBLIC_FILES:
            self._send_file(os.path.join(HTML_DIR, path.lstrip("/")), PWA_PUBLIC_FILES[path])
            return

        # ---- всё остальное — только с действующей сессией, если вход
        # вообще настроен (AUTH_ENABLED). Если не настроен — хаб открыт
        # (тот же режим, что был раньше, до этого шага) ----
        if AUTH_ENABLED and not get_session(self):
            self._redirect("/login")
            return

        if path.startswith("/api/widgets/"):
            widget_id = path[len("/api/widgets/"):]
            fn = WIDGETS.get(widget_id)
            if not fn:
                self._send_json({"error": f"неизвестный виджет '{widget_id}'"}, status=404)
                return
            self._send_json(fn())
            return

        if path.startswith("/api/forgejo/download/"):
            # unquote ОБЯЗАТЕЛЕН: фронтенд кодирует repo.full_name через
            # encodeURIComponent (см. HTML-шаблон карточки репо) — это
            # превращает "owner/repo" в "owner%2Frepo", а self.path здесь
            # берётся сырым, без декодирования. Без unquote full_name
            # приходит в forgejo_download_proxy буквально с "%2F" вместо
            # "/", regex-проверка не находит разделителя и отдаёт
            # "некорректное имя репозитория" — хотя имя было корректным.
            full_name = urllib.parse.unquote(path[len("/api/forgejo/download/"):])
            forgejo_download_proxy(full_name, self)
            return

        if path.startswith("/api/cheevoscope/game/") and path.endswith("/achievements"):
            appid = path[len("/api/cheevoscope/game/"):-len("/achievements")]
            widget_cheevoscope_achievements(self, appid)
            return

        if path.startswith("/api/cheevoscope/retro/game/") and path.endswith("/achievements"):
            game_id = path[len("/api/cheevoscope/retro/game/"):-len("/achievements")]
            widget_cheevoscope_retro_achievements(self, game_id)
            return

        if path.startswith("/api/cheevoscope/local-image/"):
            filename = urllib.parse.unquote(path[len("/api/cheevoscope/local-image/"):])
            cheevoscope_local_image_proxy(self, filename)
            return

        if path.startswith("/api/memoscope/image/"):
            filename = urllib.parse.unquote(path[len("/api/memoscope/image/"):])
            memoscope_image_proxy(self, filename)
            return

        if path == "/data/cards.json":
            self._send_file(os.path.join(DATA_DIR, "cards.json"), "application/json; charset=utf-8")
            return

        if path == "/" or path == "":
            self._send_file(os.path.join(HTML_DIR, "index.html"), "text/html; charset=utf-8")
            return

        # остальная статика (если появится) — по расширению файла, минимально
        safe_path = os.path.normpath(path).lstrip("/")
        full_path = os.path.join(HTML_DIR, safe_path)
        if not full_path.startswith(HTML_DIR):
            self.send_response(403)
            self.end_headers()
            return
        ext_map = {".css": "text/css", ".js": "application/javascript", ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/manifest+json"}
        content_type = ext_map.get(os.path.splitext(full_path)[1], "application/octet-stream")
        self._send_file(full_path, content_type)

    # Без do_HEAD http.server сам отвечает 501 на любой не-GET/POST/DELETE
    # метод — ловилось на HEAD-проверках PWA-ресурсов. Тело не пишется
    # благодаря проверке self.command != "HEAD" в _send_file/_send_json.
    do_HEAD = do_GET

    def do_DELETE(self):
        path = self.path.split("?", 1)[0]

        if AUTH_ENABLED and not get_session(self):
            self._send_json({"error": "не авторизован"}, status=401)
            return

        # /api/widgets/ntfy-feed/<id> — удаление конкретного уведомления.
        # Единственный поддерживаемый DELETE-маршрут пока — остальные
        # виджеты (Beszel/Vaultwarden) только читают данные, удалять нечего.
        prefix = "/api/widgets/ntfy-feed/"
        if path.startswith(prefix):
            msg_id = path[len(prefix):]
            self._send_json(widget_ntfy_delete(msg_id))
            return

        self._send_json({"error": "неизвестный маршрут для DELETE"}, status=404)

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)

        if AUTH_ENABLED and not get_session(self):
            self._send_json({"error": "не авторизован"}, status=401)
            return

        # /api/forgejo/upload/<owner>/<repo> — файлы в уже существующий репозиторий
        prefix = "/api/forgejo/upload/"
        if path.startswith(prefix):
            # unquote — та же причина, что и в /api/forgejo/download/ выше:
            # фронтенд шлёт encodeURIComponent(fullName), "/" приходит как
            # "%2F".
            full_name = urllib.parse.unquote(path[len(prefix):])
            widget_forgejo_upload_files(full_name, self)
            return

        # /api/forgejo/create-from-zip — новый репозиторий из ZIP
        if path == "/api/forgejo/create-from-zip":
            widget_forgejo_upload_zip(self)
            return

        if path == "/api/push/subscribe":
            widget_push_subscribe(self)
            return

        if path == "/api/push/unsubscribe":
            widget_push_unsubscribe(self)
            return

        if path == "/api/cheevoscope/refresh":
            widget_cheevoscope_refresh(self, query)
            return

        if path == "/api/walletscope/add":
            widget_walletscope_add(self)
            return

        if path.startswith("/api/walletscope/edit/"):
            widget_walletscope_edit(self, path[len("/api/walletscope/edit/"):])
            return

        if path.startswith("/api/walletscope/delete/"):
            widget_walletscope_delete(self, path[len("/api/walletscope/delete/"):])
            return

        if path == "/api/walletscope/transfer":
            widget_walletscope_transfer(self)
            return

        if path == "/api/memoscope/add":
            widget_memoscope_add(self)
            return

        if path.startswith("/api/memoscope/edit/"):
            widget_memoscope_edit(self, path[len("/api/memoscope/edit/"):])
            return

        if path.startswith("/api/memoscope/delete/"):
            widget_memoscope_delete(self, path[len("/api/memoscope/delete/"):])
            return

        self._send_json({"error": "неизвестный маршрут для POST"}, status=404)




if __name__ == "__main__":
    ensure_vapid_keys()
    os.makedirs(CHEEVO_CACHE_DIR, exist_ok=True)
    os.makedirs(CHEEVO_IMAGES_DIR, exist_ok=True)
    threading.Thread(target=ntfy_push_worker, daemon=True).start()
    threading.Thread(target=cheevo_hourly_worker, daemon=True).start()
    server = ThreadingHTTPServer(("0.0.0.0", 80), Handler)
    server.serve_forever()
PYEOF
        echo "${GREEN}[✓]${NC} backend/app.py создан: $HUB_DIR/backend/app.py"
    else
        echo "${CYAN}[*]${NC} backend/app.py уже существует, не трогаю (возможны ручные правки)"
    fi

    if [ ! -f "$HUB_DIR/docker-compose.yml" ]; then
        cat > "$HUB_DIR/docker-compose.yml" << EOF
services:
  nexus404:
    image: python:3.12-alpine
    container_name: dk_nexus404
    restart: unless-stopped
    command: ["sh", "-c", "pip install --no-cache-dir pywebpush --break-system-packages --quiet && python3 /app/backend/app.py"]
    volumes:
      - ./html:/app/html:ro
      - ./data:/app/data
      - ./backend:/app/backend:ro
      - ./pip-cache:/root/.cache/pip
      # Read-only монтирование данных ДРУГИХ сервисов — нужно виджетам,
      # чтобы сходить в их API/БД изнутри docker-сети. Если сервис ещё не
      # установлен на момент запуска хаба (обычный случай — хаб ставится
      # ПЕРВЫМ, см. заголовок файла) — Docker создаст пустую директорию, а
      # когда сервис появится позже, его файлы станут видны здесь сами,
      # без перезапуска контейнера (обычный bind-mount, не копия).
      - ${APPS_DIR}/beszel:/secrets/beszel:ro
      - ${APPS_DIR}/vaultwarden/data:/secrets/vaultwarden-data:ro
      - ${APPS_DIR}/ntfy:/secrets/ntfy:ro
      - ${APPS_DIR}/forgejo:/secrets/forgejo:ro
    networks:
      - ${DK_NETWORK}

networks:
  ${DK_NETWORK}:
    external: true
EOF
        echo "${GREEN}[✓]${NC} docker-compose.yml создан: $HUB_DIR/docker-compose.yml"
    else
        echo "${CYAN}[*]${NC} docker-compose.yml уже существует, не трогаю"
    fi

    # Порт наружу НЕ публикуется — единственный путь снаружи идёт через
    # Caddy (шаг 2), изнутри — по имени контейнера dk_nexus404:80.
    run_spinner "Запуск NEXUS404 Interface" "dk_compose_up '$HUB_DIR'"

    echo "${GREEN}[✓]${NC} Шаг 1 завершён успешно"
    mark_done "step4_1"
fi

# ================== ШАГ 2 ==================
if is_done "step4_2"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 2: Caddy (хаб — default-обработчик корневого домена)"
    echo "===========================================================================${NC}"

    DK_ROOT_DOMAIN_S2=$(read_or_default "$DOMAINFILE" "")
    if [ -z "$DK_ROOT_DOMAIN_S2" ]; then
        echo "${YELLOW}[?]${NC} Базовый домен не настроен — хаб будет доступен только изнутри"
        echo "    docker-сети, без внешнего адреса. Настройте домен (модуль 2, шаг 5)"
        echo "    и запустите этот шаг заново, когда он появится."
    else
        # path="" -> default-обработчик, см. claim_root_domain/rebuild_root_caddy
        # в common.sh: он ловит всё, что не подошло другим зарегистрированным
        # путям (например будущему секретному пути Vaultwarden). На хаб
        # претендует только он один — конфликтов с другими default-заявками
        # в проекте нет.
        claim_root_domain "hub" "" "reverse_proxy dk_nexus404:80"
        echo "${GREEN}[✓]${NC} Caddy настроен: https://${DK_ROOT_DOMAIN_S2} -> dk_nexus404:80"
    fi

    echo "${GREEN}[✓]${NC} Шаг 2 завершён успешно"
    mark_done "step4_2"
fi

# ================== ШАГ 3 ==================
if is_done "step4_3"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 3: Вход в хаб через Pocket ID (OIDC)"
    echo "===========================================================================${NC}"

    # ВАЖНО: хаб — ЕДИНСТВЕННАЯ внешняя точка входа во всю систему. Без
    # этого шага он открыт вообще всем, кто знает домен — ни пароля, ни
    # passkey, никакой преграды. Раньше здесь планировался отдельный
    # самописный логин — вместо этого хаб сам становится ещё одним OIDC-
    # клиентом Pocket ID (тем же протоколом, что уже работает у Vaultwarden/
    # Forgejo), а не изобретает свою систему паролей/сессий с нуля.
    HUB_OIDC_SECRET_FILE="$HUB_DIR/oidc_client_secret"
    POCKETID_URL_FILE_REF="$POCKETID_DIR_REF/public_url"

    if ! dk_pocketid_available; then
        echo "${YELLOW}[?]${NC} Pocket ID не установлена — хаб остаётся БЕЗ ЗАЩИТЫ, открыт всем,"
        echo "    кто знает домен. Установите Pocket ID (пункт меню 3) и запустите"
        echo "    этот шаг заново — без него это не косметика, а дыра в безопасности."
    elif ! [ -s "$POCKETID_URL_FILE_REF" ]; then
        echo "${YELLOW}[?]${NC} Pocket ID установлена, но не нашёл её адрес — похоже, тот"
        echo "    модуль не был доведён до конца. Хаб остаётся без защиты, пропускаю."
    else
        DK_ROOT_DOMAIN_S3=$(dk_hostname)
        POCKETID_URL_S3=$(cat "$POCKETID_URL_FILE_REF")
        REDIRECT_URI="https://${DK_ROOT_DOMAIN_S3}/auth/callback"

        if dk_pocketid_oidc_register_client "NEXUS404 Hub" "$REDIRECT_URI" "$HUB_OIDC_SECRET_FILE"; then
            HUB_OIDC_CLIENT_ID=$(cat "${HUB_OIDC_SECRET_FILE}.id")
            HUB_OIDC_CLIENT_SECRET=$(cat "$HUB_OIDC_SECRET_FILE")

            # Тот же приём доверия сертификату, что у Vaultwarden/Forgejo —
            # хаб тоже ходит на HTTPS Pocket ID (обмен кода на токен идёт
            # через внутренний адрес dk_pocketid:1411, но это всё ещё HTTPS
            # запрос изнутри Python, urllib проверяет сертификат так же).
            # Python-образ (python:3.12-alpine) уже содержит системные CA —
            # добавлять отдельный бандл не требуется, в отличие от Vaultwarden/
            # Forgejo (у них по умолчанию урезанный набор корневых сертификатов).

            # Патчим docker-compose.yml — добавляем переменные окружения для
            # OIDC, если их там ещё нет (idempotent retrofit, тот же приём,
            # что у Vaultwarden с SSO_*).
            if ! grep -q 'POCKETID_CLIENT_ID' "$HUB_DIR/docker-compose.yml"; then
                awk -v cid="$HUB_OIDC_CLIENT_ID" -v secret="$HUB_OIDC_CLIENT_SECRET" \
                    -v pid_url="$POCKETID_URL_S3" -v hub_url="https://${DK_ROOT_DOMAIN_S3}" '
                    /command:/ && !done {
                        print
                        print "    environment:"
                        print "      POCKETID_CLIENT_ID: \"" cid "\""
                        print "      POCKETID_CLIENT_SECRET: \"" secret "\""
                        print "      POCKETID_PUBLIC_URL: \"" pid_url "\""
                        print "      HUB_PUBLIC_URL: \"" hub_url "\""
                        done=1
                        next
                    }
                    { print }
                ' "$HUB_DIR/docker-compose.yml" > "$HUB_DIR/docker-compose.yml.dk_tmp"
                cat "$HUB_DIR/docker-compose.yml.dk_tmp" > "$HUB_DIR/docker-compose.yml"
                rm -f "$HUB_DIR/docker-compose.yml.dk_tmp"
                echo "${GREEN}[✓]${NC} Переменные окружения OIDC добавлены в docker-compose.yml"
            fi

            run_spinner "Применяю вход через Pocket ID (пересоздание хаба)" "dk_compose_up '$HUB_DIR'"
            echo "${GREEN}[✓]${NC} Хаб теперь требует вход через Pocket ID (passkey) —"
            echo "    без него внутрь не попасть, даже зная домен"
        else
            echo "${YELLOW}[?]${NC} Не удалось зарегистрировать клиента в Pocket ID — хаб остаётся"
            echo "    БЕЗ ЗАЩИТЫ. Смотрите вывод выше, запустите этот шаг заново."
        fi
    fi

    echo "${GREEN}[✓]${NC} Шаг 3 завершён успешно"
    mark_done "step4_3"
fi

# ================== ШАГ 4 ==================
if is_done "step4_4"; then
    :
else
    echo "${BOLD}${CYAN}==========================================================================="
    echo "  ШАГ 4: Финальная проверка"
    echo "===========================================================================${NC}"

    CHECK_FAILED=0
    echo "===== Результаты финальной проверки модуля NEXUS404 Interface ($(date '+%Y-%m-%d %H:%M:%S')) =====" >> "$LOGFILE"

    check_item "Контейнер NEXUS404 Interface запущен" bash -c "docker ps --format '{{.Names}}' | grep -qx dk_nexus404"
    check_item "index.html существует" test -s "$HUB_DIR/html/index.html"
    check_item "backend/app.py существует" test -s "$HUB_DIR/backend/app.py"
    check_item "PWA-манифест существует" test -s "$HUB_DIR/html/manifest.json"
    check_item "Иконки существуют" test -s "$HUB_DIR/html/icon-512.png"
    check_item "Service Worker существует (для push)" test -s "$HUB_DIR/html/sw.js"
    check_item "cards.json существует" test -f "$HUB_CONFIG_FILE"
    # ВАЖНО: НЕ urllib.request.urlopen() — он сам следует по редиректам, а с
    # включённым Pocket ID (шаг 3) "/" отдаёт 302 на "/login", который сам
    # редиректит ЕЩЁ РАЗ, уже наружу на внешний https://<pocketid>/authorize.
    # Проверка живости хаба тогда начинает зависеть от того, достучится ли
    # контейнер до внешнего адреса — хотя по смыслу достаточно, что сам хаб
    # вообще отвечает (пусть даже редиректом на /login — это нормальный
    # признак жизни, а не повод считать хаб недоступным). http.client без
    # редиректов — принимаем любой валидный HTTP-ответ, а не только 200.
    check_item "Хаб отвечает изнутри сети" bash -c "docker exec dk_nexus404 python3 -c 'import http.client; c = http.client.HTTPConnection(\"localhost\", 80, timeout=5); c.request(\"GET\", \"/\"); c.getresponse(); c.close()'"
    if [ -s "$HUB_DIR/oidc_client_secret" ]; then
        check_item "Вход через Pocket ID настроен" test -s "$HUB_DIR/oidc_client_secret"
    else
        echo "${YELLOW}[?]${NC}  Вход через Pocket ID НЕ настроен — хаб открыт всем, кто знает домен"
    fi

    echo ""
    if [ "$CHECK_FAILED" -eq 0 ]; then
        echo "${GREEN}[✓]${NC} Все проверки пройдены успешно"
    else
        echo "${RED}[!]${NC} Проверок с ошибкой: $CHECK_FAILED — просмотрите список выше"
    fi

    echo "${GREEN}[✓]${NC} Шаг 4 завершён успешно"
    mark_done "step4_4"
fi

echo ""
echo "${BOLD}${CYAN}==========================================================================="
echo "  NEXUS404 Interface настроен — сохраните эту информацию."
echo "===========================================================================${NC}"
DK_ROOT_DOMAIN_NOW=$(read_or_default "$DOMAINFILE" "")
if [ -n "$DK_ROOT_DOMAIN_NOW" ]; then
    echo "$(pad_field "Адрес хаба:" "$FIELD_WIDTH")https://${DK_ROOT_DOMAIN_NOW}"
else
    echo "$(pad_field "Адрес хаба:" "$FIELD_WIDTH")не настроен (нет базового домена)"
fi
CARD_COUNT=0
[ -f "$HUB_CARDS_FILE" ] && CARD_COUNT=$(wc -l < "$HUB_CARDS_FILE")
echo "$(pad_field "Карточек сейчас:" "$FIELD_WIDTH")${CARD_COUNT}"
echo "$(pad_field "Файл карточек:" "$FIELD_WIDTH")$HUB_CARDS_FILE"
echo ""
echo "${CYAN}[*]${NC} Карточки появятся сами по ходу установки остальных модулей —"
echo "    руками сюда ничего добавлять не нужно."
echo ""
