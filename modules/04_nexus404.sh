#!/bin/bash
# =============================================================================
# Модуль: NEXUS404 Hub — свой хаб, замена Homer.
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
echo "  УСТАНОВКА NEXUS404 HUB"
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
    echo "  ШАГ 1: Установка NEXUS404 Hub"
    echo "===========================================================================${NC}"

    if ! check_disk_space 256; then
        echo "${RED}[!]${NC} Меньше 256 MB свободного места на диске — недостаточно"
        exit 1
    fi

    mkdir -p "$HUB_DIR/html" "$HUB_DIR/data"

    # Перезаписываем всегда, когда этот шаг реально выполняется — от
    # повторной перезаписи при обычном использовании защищает is_done
    # снаружи (см. "ШАГ N" выше), а не проверка существования файла: без
    # этого пункт меню "u) Обновить" (сброс STATEFILE) не имел бы смысла —
    # шаг бы посчитался непройденным, но файл всё равно не обновился бы.
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
  .status-actions{ display:flex; align-items:center; gap:14px; flex-shrink:0; }
  .status-actions .logout-link{ color:var(--muted); text-decoration:none; font-size:0.72rem; }
  .status-actions .logout-link:hover{ color:var(--red); }
  .js-push-toggle:hover{ color:var(--accent) !important; }
  .header-right{ display:flex; align-items:center; gap:16px; flex-wrap:wrap; justify-content:flex-end; flex-shrink:0; }

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
  .grid-2col{ grid-template-columns:repeat(2, minmax(0, 1fr)) !important; }
  .stack-grid{ grid-template-columns:1fr !important; }
  @media(max-width:1100px){ .grid{ grid-template-columns:repeat(3, minmax(0, 1fr)); } }
  @media(max-width:760px){ .grid{ grid-template-columns:repeat(2, minmax(0, 1fr)); gap:10px; } }
  @media(max-width:420px){ .grid{ grid-template-columns:repeat(2, minmax(0, 1fr)); gap:8px; } .grid-2col-mobile{ grid-template-columns:repeat(2, minmax(0, 1fr)) !important; gap:8px; }
    .wallet-card-actions{ flex-direction:column; }
    .wallet-card-actions button{ width:100%; }
  }
  @media(max-width:760px){
    .wallet-card-main{ order:1; }
    .wallet-card-deposit{ order:2; }
    .wallet-card-fiat{ order:3; }
    .wallet-card-crypto{ order:4; }
    .repo-meta-sep{ display:none; }
    .repo-date{ display:block; margin-top:2px; }
    .rates-grid{ grid-template-columns:repeat(2, minmax(0, 1fr)); }
  }

  .card{ background:var(--panel); border:1px solid var(--line); border-radius:var(--card-radius); padding:16px 16px 10px; transition:all 0.2s ease; cursor:pointer; text-decoration:none; color:var(--text); display:flex; flex-direction:column; justify-content:space-between; min-height:125px; box-shadow:0 0 20px rgba(108,142,255,0.04); }
  .card:hover{ border-color:var(--accent); transform:translateY(-2px); background:#12162e; box-shadow:0 0 30px rgba(108,142,255,0.1); }
  .card.static{ cursor:default; }
  .card.static:hover{ border-color:var(--line); transform:none; background:var(--panel); box-shadow:0 0 20px rgba(108,142,255,0.04); }
  .card .top { display:flex; flex-direction:column; gap:4px; }
  .card .name{ font-size:0.8rem; font-weight:500; color:var(--text); text-transform:uppercase; letter-spacing:0.04em; overflow-wrap:break-word; }
  .card .desc{ font-size:0.75rem; color:var(--muted); letter-spacing:0.02em; text-transform:uppercase; }
  .card .bottom{ display:flex; align-items:center; justify-content:space-between; margin-top:4px; padding-top:4px; border-top:1px solid var(--line); gap:8px; }
  .card .badge{ font-size:0.65rem; padding:3px 11px; border-radius:10px; background:var(--line); color:var(--muted); text-transform:uppercase; font-weight:600; letter-spacing:0.04em; transition:all 0.2s ease; white-space:nowrap; }
  .card .ping{ font-size:0.65rem; font-weight:600; white-space:nowrap; }

  .section-title{ display:flex; align-items:center; font-size:0.75rem; color:var(--amber); text-transform:uppercase; letter-spacing:0.08em; margin:14px 0 10px; padding:10px 16px; min-height:46px; box-sizing:border-box; background:var(--panel); border:1px solid var(--line); border-radius:var(--card-radius); text-shadow:0 0 12px rgba(255,204,102,0.25); overflow:hidden; }
  .empty-state{ color:var(--muted); font-size:0.8rem; padding:30px 0; text-align:center; border:1px dashed var(--line); border-radius:var(--card-radius); }
  footer{ margin-top:14px; text-align:center; font-size:0.76rem; color:var(--muted); border-top:1px solid var(--line); padding-top:14px; }

  .metrics-row{ display:flex; gap:1px; border:1px solid var(--line); margin-top:auto; box-shadow:0 0 20px rgba(108,142,255,0.04); overflow-x:auto; scrollbar-width:none; -ms-overflow-style:none; }
  .metrics-row::-webkit-scrollbar{ display:none; }
  .metrics-row .metric{ flex:1; min-width:100px; background:var(--panel); padding:8px 12px; }
  .metrics-row .metric:nth-child(2){ text-align:center; }
  .metrics-row .metric:nth-child(3){ text-align:right; }
  .metrics-row .metric .k{ display:block; font-size:0.55rem; color:var(--muted); text-transform:lowercase; letter-spacing:0.06em; margin-bottom:1px; }
  .metrics-row .metric .v{ font-size:0.8rem; color:var(--accent); text-shadow:0 0 20px rgba(108,142,255,0.15); white-space:nowrap; }

  /* ===== оверлей сервиса/виджета =====
     Панель (заголовок + кнопки действий + "назад") — единый flex-контейнер
     с переносом: на узких экранах кнопки action переходят на вторую
     строку, а не тычутся в кнопку "назад" впритык. */
  .service-overlay{ display:none; position:fixed; inset:0; z-index:1000; background:var(--bg); flex-direction:column; padding:clamp(16px, 4vw, 40px) clamp(12px, 3vw, 20px); box-sizing:border-box; }
  .service-overlay.open{ display:flex; }
  .service-overlay-bar{ display:flex; align-items:center; justify-content:space-between; flex-wrap:wrap; gap:8px 10px; padding:10px 16px; min-height:46px; box-sizing:border-box; border:1px solid var(--line); border-radius:var(--card-radius); background:var(--panel); font-size:0.75rem; text-transform:uppercase; letter-spacing:0.05em; color:var(--amber); text-shadow:0 0 12px rgba(255,204,102,0.25); margin:14px 0 10px; }
  .service-overlay-bar-left{ display:flex; align-items:center; gap:10px; flex-wrap:wrap; row-gap:6px; min-width:0; flex:1; }
  #overlayTitle{ overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .service-overlay-actions{ display:flex; align-items:center; gap:6px; flex-wrap:wrap; }
  .service-overlay-actions:empty{ display:none; }
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
  .ms-modal-backdrop{ position:fixed; inset:0; background:rgba(4,5,8,0.75); backdrop-filter:blur(2px); display:none; align-items:center; justify-content:center; z-index:2000; padding:16px; }
  .ms-modal-backdrop.open{ display:flex; }
  .ms-modal-box{ background:var(--panel); border:1px solid var(--line); border-radius:var(--card-radius); width:100%; max-width:640px; max-height:90vh; display:flex; flex-direction:column; box-shadow:0 20px 60px rgba(0,0,0,0.5); }
  .ms-modal-header{ display:flex; justify-content:space-between; align-items:center; gap:10px; padding:14px 18px; border-bottom:1px solid var(--line); }
  .ms-modal-header .title{ font-size:0.85rem; text-transform:uppercase; letter-spacing:0.05em; color:var(--accent); overflow-wrap:break-word; }
  .ms-modal-body{ padding:18px; overflow-y:auto; flex:1; scrollbar-width:none; -ms-overflow-style:none; }
  .ms-modal-body::-webkit-scrollbar{ display:none; }
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

  /* ===== WalletScope ===== */
  .balance-label{ font-size:0.65rem; text-transform:uppercase; letter-spacing:0.05em; color:var(--muted); }
  .balance-amount{ font-size:clamp(1rem, 3.2vw, 1.3rem); font-weight:600; overflow-wrap:break-word; margin-top:4px; }
  .wallet-balance-card{ padding:12px 12px 8px !important; min-height:0 !important; }
  @media(max-width:420px){ .balance-amount{ font-size:1.05rem !important; } }
  .rates-grid{ display:grid; grid-template-columns:repeat(4, minmax(0, 1fr)); gap:6px; }
  .rate-chip{ aspect-ratio:1; border-radius:6px; padding:6px; font-size:0.75rem; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:2px; min-width:0; }
  .rate-chip .sym{ color:var(--muted); font-size:0.65rem; text-transform:uppercase; }
  .rate-chip .val{ color:var(--text); font-weight:600; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .tx-amount.income{ color:var(--green); }
  .tx-amount.expense{ color:var(--red); }
  .tx-amount.deposit_in{ color:var(--accent); }
  .tx-amount.deposit_out{ color:var(--accent); }

  /* ===== MemoScope: посты ===== */
  .memo-columns{ display:flex; gap:14px; align-items:flex-start; }
  .memo-col{ display:flex; flex-direction:column; gap:14px; flex:1; min-width:0; }
  .memo-post .post-date{ font-size:0.65rem; color:var(--muted); margin-bottom:6px; text-transform:uppercase; letter-spacing:0.05em; }
  .memo-post .post-body{ font-size:0.85rem; line-height:1.55; overflow-wrap:break-word; }
  .memo-post .post-body h1{ font-size:1.1rem; margin:0 0 8px; color:var(--text); }
  .memo-post .post-body h2{ font-size:1rem; margin:0 0 8px; color:var(--text); }
  .memo-post .post-body ul, .memo-post .post-body ol{ margin:8px 0; padding-left:20px; }

  @media(max-width:600px){
    .header-row{ gap:6px 10px; }
    .prompt .cmd{ display:none; }
    .status-indicator{ font-size:0.66rem; gap:5px; }
    .title-block{ padding-left:10px; }
    .section-title, .service-overlay-bar{ font-size:0.6rem; }
    .card{ padding:12px 12px 8px; min-height:110px; }
    .card .name{ font-size:0.8rem; }
    .card .desc{ font-size:0.68rem; }
    .review-percent{ display:none; }
    .service-overlay-bar{ padding:8px 10px; gap:6px 8px; }
    .service-overlay-bar-left{ gap:6px; row-gap:4px; }
    .service-overlay-bar .back{ padding:4px 10px; font-size:0.65rem; }
    .service-overlay-bar #overlayActions button:not(.cheevo-icon-btn){ font-size:0.58rem !important; padding:3px 5px !important; }
    .service-overlay-bar #overlayActions .cheevo-icon-btn{ font-size:1.05rem !important; padding:2px 12px !important; height:30px !important; }
    /* header-right на мобильном "растворяется" (display:contents) — без
       этого order/flex-basis у status-indicator/status-actions работали
       бы только друг относительно друга ВНУТРИ обёртки, а не относительно
       prompt на уровне всей шапки (обёртка сама была бы одним "куском",
       который header-row мог бы отправить вообще куда угодно как единое
       целое — именно это и плыло на практике). Ряд 1: prompt слева,
       "online" справа. Ряд 2 (колокольчик+выйти) — на новую строку
       (flex-basis:100% всегда переносит элемент целиком), прижат вправо. */
    .header-right{ display:contents; }
    .status-indicator{ order:1; }
    .status-actions{ order:2; flex-basis:100%; justify-content:flex-end; gap:14px; }
  }
  @media(max-width:420px){
    .metrics-row{ flex-wrap:nowrap; }
    .metrics-row .metric{ min-width:0; padding:6px 8px; }
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
    <div class="header-right">
      <div class="status-actions">
        <a href="#" onclick="togglePushSubscription();return false;" class="js-push-toggle" style="color:var(--muted);display:flex;align-items:center;"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg></a>
        <a href="/logout" class="logout-link">[выйти]</a>
      </div>
      <div class="status-indicator"><span class="dot"></span>online</div>
    </div>
  </div>
  <div class="title-block">
    <div class="brand"><span class="highlight">NEXUS404</span></div>
    <span class="sub">hub</span>
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
      <div class="header-right">
      <div class="status-actions">
        <a href="#" onclick="togglePushSubscription();return false;" class="js-push-toggle" style="color:var(--muted);display:flex;align-items:center;"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg></a>
        <a href="/logout" class="logout-link">[выйти]</a>
      </div>
      <div class="status-indicator"><span class="dot"></span>online</div>
    </div>
    </div>
    <div class="title-block">
      <div class="brand"><span class="highlight">NEXUS404</span></div>
      <span class="sub">hub</span>
    </div>
    <div class="service-overlay-bar">
      <div class="service-overlay-bar-left">
        <span id="overlayTitle">СЕРВИС</span>
        <div id="overlayActions" class="service-overlay-actions"></div>
      </div>
      <button class="back" onclick="closeOverlay()">← назад</button>
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

<!-- WalletScope: снятие с депозита -->
<div class="ms-modal-backdrop" id="walletWithdrawModalBackdrop">
  <div class="ms-modal-box">
    <div class="ms-modal-header"><span class="title">Снять с депозита</span><button class="ms-btn" onclick="closeWalletModal('walletWithdrawModalBackdrop')">✕</button></div>
    <div class="ms-modal-body"><div class="ms-field"><label>Сумма, ₽ (доступно на депозите: <span id="walletWithdrawAvailable"></span>)</label><input type="number" id="walletWithdrawAmount" placeholder="0"></div></div>
    <div class="ms-modal-footer"><button class="ms-btn" onclick="closeWalletModal('walletWithdrawModalBackdrop')">Отмена</button><button class="ms-btn primary" onclick="walletSaveWithdraw()">Снять</button></div>
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
        <button type="button" id="memoRemoveImageBtn" onclick="memoRemoveImage()" style="display:none;margin-top:8px;font-size:0.7rem;background:none;border:1px solid var(--line);color:var(--red);border-radius:6px;padding:5px 10px;cursor:pointer;font-family:inherit;">✕ убрать картинку</button>
      </div>
    </div>
    <div class="ms-modal-footer"><button class="ms-btn" onclick="closeMemoModal()">Отмена</button><button class="ms-btn primary" onclick="memoSavePost()">Сохранить</button></div>
  </div>
</div>

<div class="ms-modal-backdrop" id="cheevoAchModalBackdrop">
  <div class="ms-modal-box" style="max-width:720px;">
    <div class="ms-modal-header"><span class="title" id="cheevoAchModalTitle">Достижения</span><button class="ms-btn" onclick="closeCheevoAchModal()">✕</button></div>
    <div class="ms-modal-body" id="cheevoAchModalBody"></div>
  </div>
</div>

<script>
  let currentCards = [];
  // Самописные виджеты (без отдельного сервера под ними) — используется и
  // в renderGroups (деление на секции), и в loadCardPreviews (у них нет
  // понятия online/offline, в отличие от "сервисов").
  const OWN_WIDGET_IDS = ['walletscope-data', 'memoscope-posts', 'cheevoscope-stats'];

  let currentCardsJson = '';

  async function loadCards() {
    let freshJson;
    try {
      const res = await fetch('/data/cards.json', { cache: 'no-store' });
      freshJson = await res.text();
      currentCards = JSON.parse(freshJson);
    } catch (e) {
      currentCards = [];
      freshJson = '[]';
    }
    // Список карточек меняется только когда что-то новое устанавливают
    // (запускают модуль) — не каждые 30 секунд. Пересобирать весь DOM
    // карточек на каждый опрос значило мерцать всей страницей на ровном
    // месте (особенно заметно на втором мониторе) — пересобираем только
    // если состав реально изменился, иначе просто обновляем данные внутри
    // уже существующих карточек (loadCardPreviews не трогает остальной DOM).
    if (freshJson !== currentCardsJson) {
      currentCardsJson = freshJson;
      renderGroups(currentCards);
    }
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
    const isService = !OWN_WIDGET_IDS.includes(item.widget);
    const initialBadge = isService ? 'checking...' : escapeHtml(badgeLabel);
    const initialBadgeStyle = isService ? 'background:rgba(255,204,102,0.1);color:var(--amber);' : 'background:var(--line);color:var(--muted);';
    return `
      <div class="card" data-widget="${widget}" data-service="${isService ? '1' : '0'}"
           onclick="openService('${safeName}', '${widget}')">
        <div class="top">
          <div class="name">${safeName}</div>
          <div class="desc">${escapeHtml(item.subtitle || '')}</div>
          <div class="card-preview" style="margin-top:4px;display:flex;flex-direction:column;gap:2px;"></div>
        </div>
        <div class="bottom">
          <span class="badge" style="${initialBadgeStyle}">${initialBadge}</span>
          <span class="ping"></span>
        </div>
      </div>
    `;
  }

  // Подтягивает краткую сводку в каждую карточку-виджет на главном экране —
  // не весь виджет, только одна строка (число/статус), чтобы не заходить
  // внутрь ради простого взгляда "всё ли в порядке". online/ping_ms (если
  // есть в ответе — только у "сервисов", у собственных виджетов такого
  // понятия нет) меряются прямо в бэкенде хаба, при том же самом запросе,
  // которым он и так уже ходит за данными — отдельного пинга не нужно
  // (сервисы внутренние, из браузера напрямую всё равно недостижимы).
  async function loadCardPreviews(groups) {
    const items = groups.flatMap(g => g.items).filter(i => i.mode === 'widget' && i.widget);
    for (const item of items) {
      try {
        const res = await fetch(`/api/widgets/${item.widget}`, { cache: 'no-store' });
        const data = await res.json();
        const card = document.querySelector(`.card[data-widget="${item.widget}"] .card-preview`);
        const badgeEl = document.querySelector(`.card[data-widget="${item.widget}"] .badge`);
        const pingEl = document.querySelector(`.card[data-widget="${item.widget}"] .ping`);
        if (card) {
          if (data.error) {
            card.innerHTML = '';
          } else {
            const lines = summarizeWidget(item.widget, data);
            card.innerHTML = lines.map(line => `<div style="color:var(--accent);font-size:0.8rem;">${escapeHtml(line)}</div>`).join('');
          }
        }
        // Бейдж "online"/"offline" — только у "сервисов" (см. OWN_WIDGET_IDS),
        // у собственных виджетов (WalletScope/MemoScope/Cheevoscope) такого
        // понятия нет — их бейдж остаётся статичным "виджет".
        if (badgeEl && !OWN_WIDGET_IDS.includes(item.widget)) {
          if (typeof data.online === 'boolean') {
            badgeEl.textContent = data.online ? 'online' : 'offline';
            badgeEl.style.background = data.online ? 'rgba(76,175,80,0.15)' : 'rgba(244,67,54,0.15)';
            badgeEl.style.color = data.online ? 'var(--green)' : 'var(--red)';
            badgeEl.style.boxShadow = data.online ? '0 0 8px rgba(76,175,80,0.35)' : '0 0 8px rgba(244,67,54,0.35)';
          } else {
            badgeEl.textContent = 'checking...';
            badgeEl.style.background = 'rgba(255,204,102,0.1)';
            badgeEl.style.color = 'var(--amber)';
            badgeEl.style.boxShadow = '0 0 8px rgba(255,204,102,0.3)';
          }
        }
        if (pingEl) {
          if (data.online && data.ping_ms != null) {
            pingEl.textContent = `${data.ping_ms}ms`;
            // Градация по скорости отклика — не про "хорошо/плохо для
            // сервиса", просто ориентир, насколько быстро хаб достучался.
            pingEl.style.color = data.ping_ms < 150 ? 'var(--green)' : (data.ping_ms < 400 ? 'var(--amber)' : 'var(--red)');
          } else {
            pingEl.textContent = '';
          }
        }
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
      const sum = (d.steam && d.steam.summary) || {};
      if (!sum.games_count) return [];
      return [`${sum.games_count} игр, ${sum.total_hours ?? 0}ч`, `ачивок: ${sum.achievements_overall_percent ?? 0}%`];
    }
    if (widgetId === 'walletscope-data') {
      return [`карта: ${formatRub(d.card)}`, `депозит: ${formatRub(d.deposit)}`];
    }
    if (widgetId === 'memoscope-posts') {
      const posts = d.posts || [];
      if (!posts.length) return [];
      const sorted = [...posts].sort((a, b) => b.id - a.id);
      return [`постов: ${posts.length}`, `посл.: ${sorted[0].date}`];
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

  // Для текста, который идёт ВНУТРЬ одинарных JS-кавычек onclick="...",
  // а сам onclick лежит внутри HTML-атрибута (двойные кавычки) — экраниро-
  // вать нужно строго в этом порядке: сначала JS-строку (иначе апостроф
  // сломает саму строку), потом уже итог целиком под HTML-атрибут. Раньше
  // порядок был обратный (сначала escapeHtml, потом replace апострофа) —
  // escapeHtml уже переводил ' в &#39;, так что последующий replace не
  // находил в тексте ни одного литерального апострофа. Браузер же при
  // разборе HTML-атрибута расшифровывает &#39; обратно в ' — на выходе
  // получался неэкранированный апостроф прямо посреди одинарной JS-строки,
  // ломающий её (любое название вида "Assassin's Creed" — а таких в
  // библиотеках полно — и клик по карточке молча переставал работать).
  function cheevoJsAttr(s) {
    return escapeHtml(String(s || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'"));
  }

  // Автообновление в реальном времени для открытого виджета Beszel — сам
  // Beszel обновляет метрики раз в несколько секунд на своей стороне,
  // но наш виджет раньше подгружал их один раз при открытии и больше не
  // трогал, пока не закроешь/откроешь заново. Таймер запускается только
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
    // закрывала бы всё приложение целиком, а не оверлей. Хэш в адресе
    // (не просто тот же адрес) нужен, чтобы обновление страницы (F5) не
    // выкидывало на главную — при загрузке проверяем хэш и восстанавливаем
    // открытый виджет (см. restoreOpenWidgetFromHash ниже).
    history.pushState({ nexusOverlay: true }, '', `#${encodeURIComponent(widget)}`);
  }

  // silent=true — тихое фоновое обновление (для автообновления по
  // таймеру): не показываем "загрузка данных..." заново (не мигаем
  // существующим содержимым) и при сетевой ошибке просто пропускаем
  // такт, оставляя последние известные данные на экране, а не заменяя их
  // сообщением об ошибке — единичный неудачный опрос не повод стирать то,
  // что человек уже видит.
  let currentOpenWidgetId = null;

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
    currentOpenWidgetId = widgetId;
    container.innerHTML = renderWidget(widgetId, data);
    if (widgetId === 'memoscope-posts') memoLayout();
    if (widgetId === 'cheevoscope-stats') cheevoFillHeatmap();
  }

  function renderWidget(widgetId, d) {
    if (widgetId === 'beszel-metrics') {
      if (!d.systems || d.systems.length === 0) {
        return `<div class="widget-placeholder">систем в Beszel пока нет</div>`;
      }
      return `<div class="widget-body"><div class="grid">${d.systems.map(sys => {
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
      return `<div class="widget-body"><div class="grid">
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
              <input type="text" id="fj-new-repo-desc" placeholder="описание (необязательно)" style="background:var(--bg);border:1px solid var(--line);color:var(--text);padding:6px 10px;border-radius:6px;font-family:inherit;font-size:0.75rem;">
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
            <div class="desc repo-meta" style="margin-top:4px;"><span class="repo-size">${formatKb(repo.size_kb)}</span><span class="repo-meta-sep"> · </span><span class="repo-date">${formatNtfyTime(Math.floor(new Date(repo.updated_at).getTime()/1000)).slice(0,10)}</span></div>
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
  let cheevoStatusTimerInterval = null;

  function cheevoFormatAgo(isoString) {
    if (!isoString) return null;
    const then = new Date(isoString).getTime();
    if (isNaN(then)) return null;
    let sec = Math.max(0, Math.floor((Date.now() - then) / 1000));
    if (sec < 60) return `${sec} сек назад`;
    let min = Math.floor(sec / 60);
    if (min < 60) return `${min} мин назад`;
    let hrs = Math.floor(min / 60);
    if (hrs < 24) return `${hrs} ч ${min % 60} мин назад`;
    const days = Math.floor(hrs / 24);
    return `${days} дн назад`;
  }

  function cheevoRenderStatusLine(status) {
    if (!status) return '';
    const steam = status.steam || {};
    const parts = [];
    if (steam.state === 'running') {
      const stageNames = { games_list: 'список игр', images: 'картинки', achievements: 'достижения', reviews: 'отзывы', library_cost: 'цены', report: 'сборка отчёта' };
      parts.push(`<span style="color:var(--amber);">идёт обновление (${stageNames[steam.stage] || steam.stage || '...'})</span>`);
    } else if (steam.state === 'error') {
      parts.push(`<span style="color:var(--red);">последняя попытка не удалась: ${escapeHtml(steam.error || 'неизвестная ошибка')}</span>`);
    }
    const agoText = cheevoFormatAgo(steam.last_success_at);
    if (agoText) {
      parts.push(`<span id="cheevo-last-success-ago" data-iso="${escapeHtml(steam.last_success_at)}">последнее успешное обновление: ${agoText}</span>`);
    } else if (steam.state !== 'running') {
      parts.push('<span style="color:var(--muted);">ни разу не обновлялось успешно</span>');
    }
    if (!parts.length) return '';
    return `<div style="font-size:0.7rem;color:var(--muted);margin-bottom:10px;display:flex;flex-wrap:wrap;gap:10px;">${parts.join('')}</div>`;
  }

  function cheevoTickStatusTimer() {
    const el = document.getElementById('cheevo-last-success-ago');
    if (!el) return;
    const iso = el.dataset.iso;
    const agoText = cheevoFormatAgo(iso);
    if (agoText) el.textContent = `последнее успешное обновление: ${agoText}`;
  }

  function renderCheevoscope(d) {
    cheevoLastData = d;
    const actionsEl = document.getElementById('overlayActions');
    if (actionsEl) {
      actionsEl.innerHTML = `
        <button class="cheevo-icon-btn" onclick="refreshCheevoscope('quick')" title="Быстрое обновление (список игр + достижения)" style="font-size:0.8rem;color:var(--accent);background:none;border:1px solid var(--line);padding:3px 9px;height:24px;border-radius:6px;cursor:pointer;font-family:inherit;white-space:nowrap;">↻</button>
        <button class="cheevo-icon-btn" onclick="refreshCheevoscope('full')" title="Полное обновление (+ цены, отзывы, картинки)" style="font-size:0.8rem;color:var(--muted);background:none;border:1px solid var(--line);padding:3px 9px;height:24px;border-radius:6px;cursor:pointer;font-family:inherit;white-space:nowrap;">↻+</button>
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

    if (!cheevoStatusTimerInterval) {
      cheevoStatusTimerInterval = setInterval(cheevoTickStatusTimer, 1000);
    }

    return `<div class="widget-body">
      ${cheevoRenderStatusLine(d.status)}
      <div style="display:flex;gap:6px;margin-bottom:14px;">${tabButtons}</div>
      ${body}
    </div>`;
  }

  function switchCheevoTab(tab) {
    cheevoActiveTab = tab;
    const container = document.getElementById('overlayBody');
    if (container && cheevoLastData) container.innerHTML = renderCheevoscope(cheevoLastData);
    cheevoFillHeatmap();
  }

  function cheevoRows(pairs) {
    return pairs.map(([k, v]) => `
      <div style="border-top:1px solid var(--line);padding-top:4px;display:flex;justify-content:space-between;font-size:0.75rem;color:var(--muted);"><span>${k}</span><span style="color:var(--text);">${v}</span></div>
    `).join('');
  }

  // Те же цвета и пороги, что и в cheevoRarityChips ниже — используется
  // везде, где нужно покрасить конкретную ачивку по её реальному тиру
  // редкости (не бинарно "супер редкая или нет").
  const CHEEVO_TIER_COLORS = {
    gold: '#ffd700', purple: '#b565f0', blue: '#6c8eff',
    green: '#4caf50', white: '#e8e8e8', gray: '#8a8f9c',
  };
  function cheevoTierColor(percent) {
    if (percent == null) return CHEEVO_TIER_COLORS.gray;
    if (percent <= 1) return CHEEVO_TIER_COLORS.gold;
    if (percent <= 3) return CHEEVO_TIER_COLORS.purple;
    if (percent <= 8) return CHEEVO_TIER_COLORS.blue;
    if (percent <= 20) return CHEEVO_TIER_COLORS.green;
    if (percent <= 50) return CHEEVO_TIER_COLORS.white;
    return CHEEVO_TIER_COLORS.gray;
  }

  function cheevoRarityChips(tiers) {
    if (!tiers || !tiers.total_rated) return '';
    // Точки в реальных цветах тира — тот же приём, что золотая точка
    // "online" в шапке. Без подписи тира — цвет сам по себе достаточно
    // говорящий, само число крупнее и заметнее.
    const tierColors = CHEEVO_TIER_COLORS;
    const chips = Object.entries(tiers.counts || {}).map(([tier, count]) => `
      <div style="display:flex;align-items:center;gap:7px;border:1px solid var(--line);border-radius:8px;padding:6px 12px;">
        <span style="width:11px;height:11px;border-radius:50%;background:${tierColors[tier] || 'var(--muted)'};box-shadow:0 0 8px ${tierColors[tier] || 'var(--muted)'}90;flex-shrink:0;"></span>
        <span style="color:var(--text);font-size:0.95rem;font-weight:600;">${count}</span>
      </div>
    `).join('');
    return `<div style="display:flex;flex-wrap:wrap;gap:8px;margin:8px 0 0;">${chips}</div>`;
  }

  function cheevoHeatmapCells(heatmap) {
    const counts = heatmap || {};
    if (!Object.keys(counts).length) return null;
    const days = 365;
    const today = new Date();
    const cells = [];
    // cells[0] — сегодня, cells[последний] — 364 дня назад. Верхний левый
    // угол сетки (первая клетка первой строки) получится сегодняшним днём.
    for (let i = 0; i < days; i++) {
      const d2 = new Date(today);
      d2.setDate(d2.getDate() - i);
      cells.push(counts[d2.toISOString().slice(0, 10)] || 0);
    }
    return cells;
  }

  // Ширина клетки заранее не известна — карточка активности растянута
  // наравне с соседними (см. renderCheevoSteamTab), а её реальную ширину
  // браузер посчитает только после вставки в DOM. Поэтому сначала рисуем
  // пустой placeholder, а после вставки — меряем и дозаполняем (тот же
  // приём, что и в memoLayout для MemoScope).
  function cheevoFillHeatmap() {
    const el = document.getElementById('cheevo-heatmap-cells');
    if (!el || !cheevoLastData) return;
    const cells = cheevoHeatmapCells((cheevoLastData.steam || {}).heatmap);
    if (!cells) { el.innerHTML = ''; return; }
    const max = Math.max(1, ...cells);
    const colors = ['rgba(255,255,255,0.05)', 'rgba(108,142,255,0.3)', 'rgba(108,142,255,0.55)', 'rgba(108,142,255,0.8)', 'var(--amber)'];
    const level = n => n === 0 ? 0 : Math.min(4, Math.ceil((n / max) * 4));
    const perRow = 21; // 3 недели горизонтально в одной строке
    const gap = 2;
    const containerWidth = el.clientWidth || (el.parentElement && el.parentElement.clientWidth) || 250;
    const cellSize = Math.max(6, Math.floor((containerWidth - gap * (perRow - 1)) / perRow));
    // Верхний левый угол — сегодня, дальше слева направо и сверху вниз =
    // от нового к старому (cells уже в этом порядке, см. cheevoHeatmapCells).
    const rows = [];
    for (let i = 0; i < cells.length; i += perRow) rows.push(cells.slice(i, i + perRow));
    el.style.display = 'flex';
    el.style.flexDirection = 'column';
    el.style.alignItems = 'center';
    el.innerHTML = rows.map(row => `
      <div style="display:flex;gap:${gap}px;margin-bottom:${gap}px;">${row.map(n => `<div style="width:${cellSize}px;height:${cellSize}px;border-radius:2px;background:${colors[level(n)]};flex-shrink:0;"></div>`).join('')}</div>
    `).join('');
  }

  function cheevoRarestList(rarest) {
    if (!rarest || !rarest.length) return '';
    return rarest.map(a => {
      const color = cheevoTierColor(a.global_percent);
      return `<div style="font-size:0.72rem;color:var(--text);border-top:1px solid var(--line);border-left:3px solid ${color};padding:4px 0 4px 8px;margin-top:4px;">${escapeHtml(a.name || a.achievement || '')}<div style="color:${color};font-size:0.65rem;margin-top:1px;font-weight:600;">${escapeHtml(a.game || '')} · ${a.global_percent ?? '?'}%</div></div>`;
    }).join('');
  }

  // Карточка с заголовком в том же стиле, что и остальные карточки хаба —
  // используется для heatmap и списка редких ачивок, чтобы они не висели
  // голым текстом на фоне, а смотрелись как часть общей сетки.
  function cheevoInfoCard(title, content) {
    if (!content) return '';
    return `<div class="card static" style="align-items:stretch;cursor:default;height:100%;">
      <div class="top" style="width:100%;">
        <div class="name" style="margin-bottom:6px;">${escapeHtml(title)}</div>
        <div>${content}</div>
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
    // review_desc и т.п. считаются и хранятся бэкендом (см. cheevo_fetch_reviews),
    // но раньше нигде не отрисовывались на карточке — реальный пробел, не
    // просто "не завезли": данные были готовы, просто не выводились.
    const reviewColor = (g.review_positive_percent ?? 0) >= 70 ? 'var(--green)' : ((g.review_positive_percent ?? 0) >= 40 ? 'var(--amber)' : 'var(--red)');
    const reviewBlock = g.review_desc ? `
      <div style="font-size:0.65rem;color:${reviewColor};margin-top:4px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${escapeHtml(g.review_desc)}<span class="review-percent"> · ${g.review_positive_percent ?? 0}%</span></div>` : '';
    return `<div class="card${onclick ? '' : ' static'}" data-name="${escapeHtml((g.name || '').toLowerCase())}" data-hours="${g.hours ?? 0}" data-achpct="${g.achievements_percent ?? -1}" ${onclick ? `onclick="${onclick}"` : 'style="cursor:default;"'}>
      <div class="top">
        <img src="${escapeHtml(candidates[0] || '')}" data-candidates='${escapeHtml(JSON.stringify(candidates))}' data-fallback-idx="0" loading="lazy" onerror="handleCheevoImgError(this)" style="width:100%;aspect-ratio:16/7.5;object-fit:cover;border-radius:6px;margin-bottom:8px;background:var(--bg);">
        <div class="name" style="display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;">${escapeHtml(g.name || '')}</div>
        <div class="desc" style="margin-top:2px;">${g.hours ?? 0}ч</div>
        ${reviewBlock}
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
    return `<div class="card static" data-name="${escapeHtml((g.title || '').toLowerCase())}" data-hours="0" data-hardcore="${g.hardcore_percent ?? 0}" data-softcore="${g.softcore_percent ?? 0}" style="flex-direction:row;align-items:center;gap:10px;cursor:pointer;min-height:0;padding:10px 12px;" onclick="openCheevoAchievements('retro', ${g.game_id}, '${cheevoJsAttr(g.title)}')">
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
    const statBlock = (value, label, color) => `
      <div>
        <div style="font-size:1.35rem;font-weight:600;color:${color || 'var(--text)'};">${value}</div>
        <div class="balance-label" style="margin-top:2px;">${label}</div>
      </div>`;
    const summaryCard = `
      <div class="card static" style="align-items:stretch;cursor:default;height:100%;">
        <div class="top" style="width:100%;">
          <div class="name" style="margin-bottom:10px;">steam</div>
          <div style="display:grid;grid-template-columns:repeat(2, minmax(0,1fr));gap:12px;">
            ${statBlock(sum.games_count ?? 0, 'игр в библиотеке')}
            ${statBlock(`${sum.total_hours ?? 0}ч`, 'наиграно часов')}
            ${statBlock(`${sum.achievements_overall_percent ?? 0}%`, `ачивок: ${sum.achievements_unlocked_total ?? 0}/${sum.achievements_available_total ?? 0}`, 'var(--accent)')}
            ${statBlock(sum.games_completed_100 ?? 0, 'пройдено на 100%', 'var(--amber)')}
          </div>
          <div style="margin-top:10px;border-top:1px solid var(--line);padding-top:8px;"><span style="font-size:0.7rem;color:var(--muted);">стоимость библиотеки</span><div style="font-size:1.35rem;font-weight:600;color:var(--text);margin-top:2px;">$${sum.library_cost_usd ?? 0}</div></div>
          ${cheevoRarityChips(s.rarity_tiers)}
        </div>
      </div>`;
    const rarestCard = cheevoInfoCard('редчайшие достижения', cheevoRarestList((s.rarest || []).slice(0, 6)));
    const heatmapCard = (s.heatmap && Object.keys(s.heatmap).length)
      ? cheevoInfoCard('активность за год', '<div id="cheevo-heatmap-cells"></div>')
      : '';
    const topRow = `<div style="display:flex;gap:14px;margin-bottom:14px;flex-wrap:wrap;">
      <div style="flex:1;min-width:220px;">${summaryCard}</div>
      <div style="flex:1;min-width:220px;">${rarestCard}</div>
      <div style="flex:1;min-width:220px;">${heatmapCard}</div>
    </div>`;
    const games = s.games || [];
    const searchBar = games.length ? `<div style="display:flex;gap:8px;margin-bottom:12px;flex-wrap:wrap;">
      <input type="text" id="cheevo-search-steam" placeholder="Поиск по названию…" oninput="cheevoFilterGames('cheevo-games-steam', 'cheevo-search-steam', 'cheevo-sort-steam')" style="flex:1;min-width:160px;background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:7px 10px;color:var(--text);font-family:inherit;font-size:0.8rem;">
      <select id="cheevo-sort-steam" onchange="cheevoFilterGames('cheevo-games-steam', 'cheevo-search-steam', 'cheevo-sort-steam')" style="background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:7px 10px;color:var(--text);font-family:inherit;font-size:0.8rem;">
        <option value="name">По алфавиту</option>
        <option value="hours">По часам в игре</option>
        <option value="achievements">По % достижений</option>
      </select>
    </div>` : '';
    const gamesGrid = games.length
      ? `${searchBar}<div class="grid" id="cheevo-games-steam">${cheevoGamesWithDivider(games)}</div>`
      : `<div class="widget-placeholder">игр пока нет — нажмите "обновить"</div>`;
    return topRow + gamesGrid;
  }

  // Игры с достижениями и без — раздельно, с тонким разделителем между
  // ними (backend уже отдаёт список в этом порядке — с ачивками сначала).
  // Ищем точку перехода динамически (а не полагаемся на фиксированный
  // индекс) — безопасно даже после поиска/сортировки, если группировка
  // всё ещё целиком последовательна; если нет — просто не показываем
  // разделитель, чтобы не воткнуть его в случайное место.
  function cheevoGamesWithDivider(games) {
    const withAch = games.filter(g => g.achievements_percent !== null && g.achievements_percent !== undefined);
    const withoutAch = games.filter(g => g.achievements_percent === null || g.achievements_percent === undefined);
    const isCleanSplit = withAch.length + withoutAch.length === games.length &&
      games.slice(0, withAch.length).every(g => withAch.includes(g));
    const cardsHtml = (list) => list.map(g => cheevoGameCard(
      g.appid, g,
      g.achievements_total ? `openCheevoAchievements('steam', ${g.appid}, '${cheevoJsAttr(g.name)}')` : '',
    )).join('');
    if (!isCleanSplit || !withoutAch.length || !withAch.length) {
      return cardsHtml(games);
    }
    const divider = `<div class="cheevo-group-label" style="grid-column:1/-1;display:flex;align-items:center;gap:10px;margin:6px 0;color:var(--muted);font-size:0.7rem;text-transform:uppercase;letter-spacing:0.05em;">
      <div style="flex:1;height:1px;background:var(--line);"></div>без достижений<div style="flex:1;height:1px;background:var(--line);"></div>
    </div>`;
    return cardsHtml(withAch) + divider + cardsHtml(withoutAch);
  }

  // Поиск+сортировка списка игр — та же логика, что была в оригинальном
  // проекте (см. templates/*.html filterGamesGrid): по алфавиту (умолчание)
  // не трогаем порядок построения (уже "с ачивками сначала"), сортировки
  // по часам/% ачивок/hardcore/softcore перемешивают эту группировку —
  // тогда прячем разделитель (в перемешанном порядке он теряет смысл).
  function cheevoFilterGames(gridId, searchId, sortId) {
    const grid = document.getElementById(gridId);
    if (!grid) return;
    const query = (document.getElementById(searchId).value || '').trim().toLowerCase();
    const sortBy = document.getElementById(sortId).value;
    const tiles = Array.from(grid.querySelectorAll(':scope > .card'));
    const labels = Array.from(grid.querySelectorAll(':scope > .cheevo-group-label'));

    tiles.forEach(tile => {
      const match = (tile.dataset.name || '').includes(query);
      tile.style.display = match ? '' : 'none';
    });

    if (sortBy !== 'name') {
      labels.forEach(l => { l.style.display = 'none'; });
      const key = sortBy === 'hours' ? 'hours' : (sortBy === 'achievements' ? 'achpct' : (sortBy === 'hardcore' ? 'hardcore' : 'softcore'));
      const sorted = tiles.slice().sort((a, b) => Number(b.dataset[key] || -1) - Number(a.dataset[key] || -1));
      sorted.forEach(tile => grid.appendChild(tile));
    } else {
      labels.forEach(l => {
        const next = l.nextElementSibling;
        // Группа "без достижений" — единственная за разделителем; видимость
        // самого разделителя зависит от того, остался ли там хоть один
        // видимый тайл после поиска.
        let anyVisible = false;
        let sib = next;
        while (sib) { if (sib.classList.contains('card') && sib.style.display !== 'none') anyVisible = true; sib = sib.nextElementSibling; }
        l.style.display = anyVisible ? '' : 'none';
      });
    }
  }

  function renderCheevoRetroTab(r) {
    if (!r) return '<div class="widget-placeholder">RetroAchievements не настроен</div>';
    const sum = r.summary || {};
    const profile = r.profile || {};
    const statBlock = (value, label, color) => `
      <div>
        <div style="font-size:1.35rem;font-weight:600;color:${color || 'var(--text)'};">${value}</div>
        <div class="balance-label" style="margin-top:2px;">${label}</div>
      </div>`;
    const summaryCard = `
      <div class="card static" style="align-items:stretch;cursor:default;height:100%;">
        <div class="top" style="width:100%;">
          <div class="name" style="margin-bottom:10px;">${escapeHtml(profile.username || 'retroachievements')}</div>
          <div style="display:grid;grid-template-columns:repeat(2, minmax(0,1fr));gap:12px;">
            ${statBlock(sum.games_count ?? 0, 'игр')}
            ${statBlock(sum.games_mastered ?? 0, 'замастерено', 'var(--amber)')}
            ${statBlock(`${sum.overall_hardcore_percent ?? 0}%`, `хардкор: ${sum.games_completed ?? 0} пройдено`, 'var(--accent)')}
            ${statBlock(profile.points ?? 0, `очки (хардкор: ${profile.retro_points ?? 0})`)}
          </div>
          ${cheevoRarityChips(r.rarity_tiers)}
        </div>
      </div>`;
    const consoles = Object.entries(r.points_by_console || {});
    const consolesContent = consoles.length
      ? consoles.map(([name, pts]) => `<div style="font-size:0.75rem;color:var(--muted);border-top:1px solid var(--line);padding-top:6px;margin-top:6px;display:flex;justify-content:space-between;"><span>${escapeHtml(name)}</span><span style="color:var(--text);">${pts.hardcore ?? 0} (софткор: ${pts.softcore ?? 0})</span></div>`).join('')
      : '';
    const consolesCard = cheevoInfoCard('очки по консолям', consolesContent);
    const rarestCard = cheevoInfoCard('редчайшие достижения', cheevoRarestList((r.rarest || []).slice(0, 6)));
    const topRow = `<div style="display:flex;gap:14px;margin-bottom:14px;flex-wrap:wrap;">
      <div style="flex:1;min-width:220px;">${summaryCard}</div>
      <div style="flex:1;min-width:220px;">${consolesCard}</div>
      <div style="flex:1;min-width:220px;">${rarestCard}</div>
    </div>`;
    const games = r.games || [];
    const searchBarRA = games.length ? `<div style="display:flex;gap:8px;margin-bottom:12px;flex-wrap:wrap;">
      <input type="text" id="cheevo-search-retro" placeholder="Поиск по названию…" oninput="cheevoFilterGames('cheevo-games-retro', 'cheevo-search-retro', 'cheevo-sort-retro')" style="flex:1;min-width:160px;background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:7px 10px;color:var(--text);font-family:inherit;font-size:0.8rem;">
      <select id="cheevo-sort-retro" onchange="cheevoFilterGames('cheevo-games-retro', 'cheevo-search-retro', 'cheevo-sort-retro')" style="background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:7px 10px;color:var(--text);font-family:inherit;font-size:0.8rem;">
        <option value="name">По алфавиту</option>
        <option value="hardcore">По hardcore %</option>
        <option value="softcore">По softcore %</option>
      </select>
    </div>` : '';
    const gamesGrid = games.length
      ? `${searchBarRA}<div id="cheevo-games-retro" style="display:flex;flex-direction:column;gap:8px;">${games.map(cheevoRetroRow).join('')}</div>`
      : '';
    return topRow + gamesGrid;
  }

  function renderCheevoOverallTab(s, r) {
    s = s || {};
    const sum = s.summary || {};
    const rsum = (r && r.summary) || {};
    const rprofile = (r && r.profile) || {};
    const steamSummaryCard = `
      <div class="card static" style="align-items:stretch;cursor:default;height:100%;">
        <div class="top" style="width:100%;">
          <div class="name" style="margin-bottom:8px;">steam</div>
          <div style="display:flex;flex-direction:column;gap:4px;">${cheevoRows([
            ['игр', sum.games_count ?? 0], ['часов', sum.total_hours ?? 0], ['ачивок', `${sum.achievements_overall_percent ?? 0}%`],
          ])}</div>
        </div>
      </div>`;
    const raSummaryCard = `
      <div class="card static" style="align-items:stretch;cursor:default;height:100%;">
        <div class="top" style="width:100%;">
          <div class="name" style="margin-bottom:8px;">retroachievements</div>
          <div style="display:flex;flex-direction:column;gap:4px;">${cheevoRows([
            ['игр', rsum.games_count ?? 0], ['очки', rprofile.points ?? 0], ['% хардкор', `${rsum.overall_hardcore_percent ?? 0}%`],
          ])}</div>
        </div>
      </div>`;
    const summariesRow = `<div style="display:flex;gap:14px;margin-bottom:14px;flex-wrap:wrap;">
      <div style="flex:1;min-width:220px;">${steamSummaryCard}</div>
      <div style="flex:1;min-width:220px;">${raSummaryCard}</div>
    </div>`;
    const steamRarest = cheevoInfoCard('редчайшие (steam)', cheevoRarestList((s.rarest || []).slice(0, 10)));
    const raRarest = cheevoInfoCard('редчайшие (RA)', cheevoRarestList((r && r.rarest || []).slice(0, 10)));
    const rarestRow = (steamRarest || raRarest) ? `<div style="display:flex;gap:14px;flex-wrap:wrap;">
      <div style="flex:1;min-width:220px;">${steamRarest}</div>
      <div style="flex:1;min-width:220px;">${raRarest}</div>
    </div>` : '';
    return summariesRow + rarestRow;
  }

  async function openCheevoAchievements(platform, id, name) {
    document.getElementById('cheevoAchModalTitle').textContent = name;
    const body = document.getElementById('cheevoAchModalBody');
    body.innerHTML = `<div class="widget-placeholder">загрузка ачивок...</div>`;
    document.getElementById('cheevoAchModalBackdrop').classList.add('open');
    history.pushState({ modalOpen: true }, '', location.href);
    const url = platform === 'retro' ? `/api/cheevoscope/retro/game/${id}/achievements` : `/api/cheevoscope/game/${id}/achievements`;
    try {
      const res = await fetch(url);
      const data = await res.json();
      if (!data.available || !data.achievements.length) {
        body.innerHTML = `<div class="widget-placeholder">данных по ачивкам нет</div>`;
        return;
      }
      body.innerHTML = `<div class="grid stack-grid">${data.achievements.map(a => {
        const iconFile = platform === 'retro' ? a.badge_url : (a.unlocked ? a.icon : (a.icon_gray || a.icon));
        const icon = iconFile ? `/api/cheevoscope/local-image/${encodeURIComponent(iconFile)}` : '';
        const color = cheevoTierColor(a.global_percent);
        return `
        <div class="card static" style="flex-direction:row;align-items:center;gap:10px;cursor:default;opacity:${a.unlocked ? '1' : '0.5'};min-height:0;padding:8px 10px;border-color:${color};box-shadow:0 0 10px ${color}30;">
          ${icon ? `<img src="${escapeHtml(icon)}" style="width:36px;height:36px;border-radius:6px;flex-shrink:0;">` : ''}
          <div style="min-width:0;flex:1;">
            <div class="name" style="white-space:normal;font-size:0.82rem;">${escapeHtml(a.name || a.achievement || '')}</div>
            <div class="desc" style="margin-top:1px;text-transform:none;white-space:normal;font-size:0.7rem;">${escapeHtml(a.description || '')}</div>
          </div>
          <div style="font-size:0.75rem;color:${color};flex-shrink:0;font-weight:700;">${a.global_percent ?? '?'}%</div>
        </div>`;
      }).join('')}</div>`;
    } catch (e) {
      body.innerHTML = `<div class="widget-placeholder">не удалось загрузить: ${escapeHtml(e.message)}</div>`;
    }
  }

  // Закрытие модалок теперь ВСЕГДА через history.back() (не прямое
  // удаление класса) — так глубина истории браузера точно совпадает с
  // реальной глубиной интерфейса (главная -> виджет -> модалка), и
  // системная кнопка "назад" сама, без всяких хаков-компенсаций, ведёт
  // себя правильно на каждом уровне. Раньше модалки НЕ добавляли свою
  // запись в историю, а закрытие через "назад" пыталось задним числом
  // компенсировать это повторным pushState — на практике сбивало счёт (по
  // реальным сообщениям пользователей второе "назад" перепрыгивало сразу к
  // окну входа, а должно было сначала попасть на главный экран).
  function closeCheevoAchModal() {
    history.back();
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
    const txCards = sorted.map(tx => `
      <div class="card static" style="align-items:stretch;cursor:default;">
        <div class="top" style="width:100%;">
          <div class="name" style="white-space:normal;overflow-wrap:break-word;">${escapeHtml(tx.desc)}</div>
          <div class="desc">${escapeHtml(tx.date)}</div>
          <div class="tx-amount ${tx.type}" style="margin-top:8px;font-size:1rem;">${(tx.type === 'income' || tx.type === 'deposit_in') ? '+' : '−'}${formatRub(tx.amount)}</div>
        </div>
        <div class="bottom" style="border-top:1px solid var(--line);padding-top:8px;margin-top:8px;justify-content:flex-end;gap:6px;">
          <button onclick="walletEditTx(${tx.id})" style="font-size:0.65rem;background:none;border:1px solid var(--line);color:var(--text);border-radius:5px;padding:3px 7px;cursor:pointer;font-family:inherit;">✎</button>
          <button onclick="walletDeleteTx(${tx.id})" style="font-size:0.65rem;background:none;border:1px solid var(--line);color:var(--red);border-radius:5px;padding:3px 7px;cursor:pointer;font-family:inherit;">✕</button>
        </div>
      </div>`).join('');

    return `<div class="widget-body">
      <div class="grid grid-2col-mobile" style="margin-bottom:14px;align-items:start;">
        <div class="card static wallet-card-main wallet-balance-card" style="align-items:stretch;cursor:default;">
          <div class="top" style="width:100%;">
            <div class="balance-label">Карта</div>
            <div class="balance-amount">${formatRub(d.card)}</div>
            <div class="wallet-card-actions" style="display:flex;gap:6px;flex-wrap:wrap;margin-top:8px;">
              <button onclick="walletOpenTxModal('income')" style="font-size:0.7rem;color:var(--green);background:none;border:1px solid var(--line);padding:6px 10px;border-radius:6px;cursor:pointer;font-family:inherit;">+ доход</button>
              <button onclick="walletOpenTxModal('expense')" style="font-size:0.7rem;color:var(--red);background:none;border:1px solid var(--line);padding:6px 10px;border-radius:6px;cursor:pointer;font-family:inherit;">− расход</button>
            </div>
          </div>
        </div>
        <div class="card static wallet-card-fiat wallet-balance-card" style="align-items:stretch;cursor:default;">
          <div class="top" style="width:100%;">
            <div class="balance-label">Валюта</div>
            <div class="rates-grid" style="margin-top:8px;">
              ${rateChip('USD', rates.usd, true)}
              ${rateChip('EUR', rates.eur, true)}
              ${rateChip('KZT', rates.kzt, true)}
              ${rateChip('CNY', rates.cny, true)}
            </div>
          </div>
        </div>
        <div class="card static wallet-card-crypto wallet-balance-card" style="align-items:stretch;cursor:default;">
          <div class="top" style="width:100%;">
            <div class="balance-label">Криптовалюта</div>
            <div class="rates-grid" style="margin-top:8px;">
              ${rateChip('BTC', rates.btc, true)}
              ${rateChip('ETH', rates.eth, true)}
              ${rateChip('XMR', rates.xmr, true)}
              ${rateChip('DOGE', rates.doge, true)}
            </div>
          </div>
        </div>
        <div class="card static wallet-card-deposit wallet-balance-card" style="align-items:stretch;cursor:default;">
          <div class="top" style="width:100%;">
            <div class="balance-label">Депозит</div>
            <div class="balance-amount">${formatRub(d.deposit)}</div>
            <div class="wallet-card-actions" style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap;">
              <button onclick="walletOpenTransferModal()" style="font-size:0.7rem;color:var(--accent);background:none;border:1px solid var(--line);padding:6px 10px;border-radius:6px;cursor:pointer;font-family:inherit;">→ на депозит</button>
              <button onclick="walletOpenWithdrawModal()" style="font-size:0.7rem;color:var(--amber);background:none;border:1px solid var(--line);padding:6px 10px;border-radius:6px;cursor:pointer;font-family:inherit;">← снять</button>
            </div>
          </div>
        </div>
      </div>
      <div class="name" style="margin-bottom:8px;">операции</div>
      <div class="grid grid-2col-mobile">${txCards || '<div class="widget-placeholder">записей пока нет</div>'}</div>
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
    history.pushState({ modalOpen: true }, '', location.href);
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
    history.pushState({ modalOpen: true }, '', location.href);
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

  function walletOpenWithdrawModal() {
    document.getElementById('walletWithdrawAvailable').textContent = formatRub(walletLastData ? walletLastData.deposit : 0);
    document.getElementById('walletWithdrawAmount').value = '';
    document.getElementById('walletWithdrawModalBackdrop').classList.add('open');
    history.pushState({ modalOpen: true }, '', location.href);
  }

  async function walletSaveWithdraw() {
    const amount = parseFloat(document.getElementById('walletWithdrawAmount').value) || 0;
    if (amount <= 0) return;
    const res = await fetch('/api/walletscope/withdraw', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ amount }),
    });
    const data = await res.json();
    if (data.error) { alert(data.error); return; }
    closeWalletModal('walletWithdrawModalBackdrop');
    loadWidget('walletscope-data', document.getElementById('overlayBody'));
  }

  function closeWalletModal(id) {
    history.back();
  }

  // ===== MemoScope =====
  let memoLastPosts = [];
  let memoEditingPostId = null;

  function renderMemoScope(d) {
    const actionsEl = document.getElementById('overlayActions');
    if (actionsEl) {
      actionsEl.innerHTML = `<button onclick="memoOpenPostModal()" style="font-size:0.65rem;color:var(--accent);background:none;border:1px solid var(--line);padding:3px 8px;height:24px;border-radius:6px;cursor:pointer;font-family:inherit;">+ пост</button>`;
    }
    memoLastPosts = d.posts || [];
    return `<div class="widget-body"><div id="memoMasonryRoot"></div></div>`;
  }

  function memoBuildPostEl(post) {
    const el = document.createElement('div');
    el.className = 'card static memo-post';
    el.style.cssText = 'cursor:default;align-items:stretch;';
    const imgTag = post.image
      ? `<div style="border-radius:6px;margin-bottom:10px;display:flex;align-items:center;justify-content:center;"><img src="/api/memoscope/image/${encodeURIComponent(post.image)}" loading="lazy" style="max-width:100%;max-height:260px;width:auto;height:auto;border-radius:6px;display:block;"></div>`
      : '';
    el.innerHTML = `
      <div class="top" style="width:100%;">
        ${imgTag}
        <div class="post-date">${escapeHtml(post.date)}</div>
        <div class="post-body">${post.html}</div>
      </div>
      <div class="bottom" style="border-top:1px solid var(--line);padding-top:8px;margin-top:10px;justify-content:flex-end;gap:6px;">
        <button onclick="memoEditPost(${post.id})" style="font-size:0.65rem;background:none;border:1px solid var(--line);color:var(--text);border-radius:5px;padding:3px 7px;cursor:pointer;font-family:inherit;">✎</button>
        <button onclick="memoDeletePost(${post.id})" style="font-size:0.65rem;background:none;border:1px solid var(--line);color:var(--red);border-radius:5px;padding:3px 7px;cursor:pointer;font-family:inherit;">✕</button>
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
    if (document.getElementById('cheevo-heatmap-cells')) cheevoFillHeatmap();
  });

  function memoOpenPostModal(post) {
    memoEditingPostId = post ? post.id : null;
    document.getElementById('memoPostModalTitle').textContent = post ? 'Изменить пост' : 'Новый пост';
    document.getElementById('memoEditorArea').innerHTML = post ? post.html : '';
    const preview = document.getElementById('memoImagePreview');
    const removeBtn = document.getElementById('memoRemoveImageBtn');
    if (post && post.image) {
      preview.src = `/api/memoscope/image/${encodeURIComponent(post.image)}`;
      preview.style.display = 'block';
      delete preview.dataset.value;
      preview.dataset.unchanged = '1';
      removeBtn.style.display = 'inline-block';
    } else {
      preview.style.display = 'none'; preview.removeAttribute('src');
      delete preview.dataset.value; delete preview.dataset.unchanged;
      removeBtn.style.display = 'none';
    }
    document.getElementById('memoImageInput').value = '';
    document.getElementById('memoPostModalBackdrop').classList.add('open');
    history.pushState({ modalOpen: true }, '', location.href);
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
      document.getElementById('memoRemoveImageBtn').style.display = 'inline-block';
    };
    reader.readAsDataURL(file);
  }

  // Убирает картинку у поста — отдельно от удаления самого поста. Снимаем
  // и "unchanged" (была старая), и "value" (была новая выбранная) — при
  // сохранении memoSavePost увидит отсутствие обоих и пошлёт
  // image_data_url:null, что бэкенд (widget_memoscope_edit) уже умеет
  // трактовать как "убрать картинку и удалить файл с диска".
  function memoRemoveImage() {
    const preview = document.getElementById('memoImagePreview');
    preview.style.display = 'none';
    preview.removeAttribute('src');
    delete preview.dataset.value;
    delete preview.dataset.unchanged;
    document.getElementById('memoImageInput').value = '';
    document.getElementById('memoRemoveImageBtn').style.display = 'none';
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
    history.back();
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
    const descInput = document.getElementById('fj-new-repo-desc');
    const privateInput = document.getElementById('fj-new-repo-private');
    const zipInput = document.getElementById('fj-new-repo-zip');
    const statusEl = document.getElementById('fj-create-status');
    const name = nameInput.value.trim();
    if (!name) { statusEl.textContent = 'укажите имя репозитория'; return; }
    if (!zipInput.files.length) { statusEl.textContent = 'выберите ZIP-файл'; return; }

    const form = new FormData();
    form.append('repo_name', name);
    form.append('description', descInput.value.trim());
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
      els.forEach(el => { el.title = 'Push-уведомления недоступны в этом браузере'; el.style.opacity = '0.3'; el.style.pointerEvents = 'none'; });
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
        els.forEach(el => { el.title = 'Уведомления выключены — нажмите, чтобы включить'; el.style.opacity = '0.5'; el.style.filter = 'none'; });
        return;
      }
      const sub = await reg.pushManager.getSubscription();
      els.forEach(el => {
        el.title = sub ? 'Уведомления включены — нажмите, чтобы выключить' : 'Уведомления выключены — нажмите, чтобы включить';
        el.style.opacity = sub ? '1' : '0.5';
        el.style.filter = sub ? 'drop-shadow(0 0 4px var(--accent))' : 'none';
        el.style.color = sub ? 'var(--accent)' : 'var(--muted)';
      });
    } catch (e) {
      els.forEach(el => { el.title = 'Уведомления выключены'; el.style.opacity = '0.5'; });
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
    currentOpenWidgetId = null;
    if (widgetAutoRefreshTimer) {
      clearInterval(widgetAutoRefreshTimer);
      widgetAutoRefreshTimer = null;
    }
    if (cheevoStatusTimerInterval) {
      clearInterval(cheevoStatusTimerInterval);
      cheevoStatusTimerInterval = null;
    }
  }

  function closeOverlay() {
    // Если поверх открыта модалка (транзакция/пост/ачивки) — кнопка
    // "назад" сначала закрывает её саму, а не весь оверлей позади. Через
    // history.back() — модалка тоже кладёт свою запись в историю при
    // открытии (см. openCheevoAchievements/walletOpenTxModal/etc), прямое
    // удаление класса оставило бы эту запись неучтённой "хвостом".
    const openModal = document.querySelector('.ms-modal-backdrop.open');
    if (openModal) { history.back(); return; }
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
  // popstate. Если поверх открыта модалка (транзакция/пост/ачивки) —
  // закрываем только её, а не весь оверлей позади (иначе "назад" сразу
  // выкидывал бы на главную, минуя закрытие модалки). Запись истории для
  // оверлея уже "съедена" самим popstate — восстанавливаем её, чтобы
  // следующее нажатие "назад" закрыло уже сам оверлей, а не пробегало
  // мимо ещё раз впустую.
  window.addEventListener('popstate', () => {
    const openModal = document.querySelector('.ms-modal-backdrop.open');
    if (openModal) {
      openModal.classList.remove('open');
      return;
    }
    closeOverlayDom();
  });

  document.addEventListener('keydown', (e) => {
    const openModal = document.querySelector('.ms-modal-backdrop.open');
    if (e.key === 'Escape') {
      if (openModal) { history.back(); return; }
      closeOverlay();
      return;
    }
    // Backspace как "назад" — только на десктопе (веб), только пока оверлей
    // реально открыт, и только если фокус НЕ в поле ввода/textarea/
    // редактируемом тексте — иначе обычное удаление символа при наборе
    // текста (например, в редакторе поста MemoScope) закрывало бы окно
    // вместо стирания буквы. Если открыта модалка (пост/транзакция/
    // ачивки) — закрывает сначала её, не весь оверлей позади.
    if (e.key === 'Backspace') {
      const overlay = document.getElementById('serviceOverlay');
      if (!overlay || !overlay.classList.contains('open')) return;
      const active = document.activeElement;
      const isEditable = active && (
        active.tagName === 'INPUT' || active.tagName === 'TEXTAREA' || active.isContentEditable
      );
      if (isEditable) return;
      e.preventDefault();
      if (openModal) { history.back(); return; }
      closeOverlay();
    }
  });

  // Свайп между вкладками Cheevoscope на мобильном (Steam/RetroAchievements/
  // Общая статистика) — работает только пока реально открыт именно этот
  // виджет (currentOpenWidgetId, см. loadWidget), чтобы случайный свайп по
  // другому открытому виджету ничего не переключал.
  (function initCheevoSwipe() {
    let touchStartX = 0, touchStartY = 0, touchActive = false;
    const overlayBody = document.getElementById('overlayBody');
    overlayBody.addEventListener('touchstart', (e) => {
      if (currentOpenWidgetId !== 'cheevoscope-stats' || e.touches.length !== 1) { touchActive = false; return; }
      touchStartX = e.touches[0].clientX;
      touchStartY = e.touches[0].clientY;
      touchActive = true;
    }, { passive: true });
    overlayBody.addEventListener('touchend', (e) => {
      if (!touchActive) return;
      touchActive = false;
      if (currentOpenWidgetId !== 'cheevoscope-stats') return;
      const touch = e.changedTouches[0];
      const deltaX = touch.clientX - touchStartX;
      const deltaY = touch.clientY - touchStartY;
      // Заметно больше по горизонтали, чем по вертикали (не спутать с
      // обычным вертикальным скроллом страницы) и достаточно длинный свайп.
      if (Math.abs(deltaX) < 60 || Math.abs(deltaX) < Math.abs(deltaY) * 1.5) return;
      const tabs = ['steam', 'retro', 'overall'];
      const idx = tabs.indexOf(cheevoActiveTab);
      if (idx === -1) return;
      if (deltaX < 0 && idx < tabs.length - 1) switchCheevoTab(tabs[idx + 1]);
      else if (deltaX > 0 && idx > 0) switchCheevoTab(tabs[idx - 1]);
    }, { passive: true });
  })();

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
    .then(() => restoreOpenWidgetFromHash())
    .catch((e) => { console.error('loadCards failed:', e); });
  setInterval(loadCards, 30000);
  setInterval(measureBottomPing, 10000);
  setInterval(tick, 1000);

  // Обновление страницы (F5) раньше всегда возвращало на главную — адрес
  // никогда не менялся при открытии виджета. Теперь при открытии в адрес
  // добавляется #widget-id (см. openService), и здесь при загрузке
  // страницы мы проверяем этот хэш и открываем тот же виджет заново.
  function restoreOpenWidgetFromHash() {
    const widgetId = decodeURIComponent(location.hash.replace(/^#/, ''));
    if (!widgetId) return;
    const item = currentCards.flatMap(g => g.items).find(i => i.widget === widgetId);
    if (!item) return;
    // openService сам сделает pushState с тем же хэшем — не дублируем.
    openService(item.name, item.widget);
  }
</script>
</body>
</html>
HTMLEOF
        echo "${GREEN}[✓]${NC} index.html создан: $HUB_DIR/html/index.html"

    # Иконки + манифест — без них "Добавить на экран" (Android/iOS) не
    # находит нормальную иконку и рисует заглушку: залитый кружок с
    # бейджиком браузера поверх (проверено на практике). Обычная версия —
    # с закруглённым фоном и рамкой; maskable — фон до самых краёв (систем
    # сама обрежет по своей маске: круг/капля/квадрат), текст в безопасной
    # зоне по центру.
    # Перезаписываем всегда, когда шаг реально выполняется - см. пояснение
    # у index.html выше про "u) Обновить" в меню.
    base64 -d > "$HUB_DIR/html/icon-512.png" << 'ICONEOF'
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
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
  "name": "NEXUS404 Hub",
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

    # cards.json — если карточки от других модулей уже накопились в TSV
    # (сервис-модуль отработал раньше хаба вручную/повторно) ИЛИ список
    # пока пуст — hub_regenerate_config создаёт файл в обоих случаях
    # (см. common.sh). Гарантирует, что файл существует ДО первого запроса
    # фронтенда, а не только "появится, когда кто-то что-то установит".
    hub_regenerate_config

    mkdir -p "$HUB_DIR/backend"

    # _shared.py — общие хелперы для отдельных модулей-виджетов
    # (walletscope.py/memoscope.py/cheevoscope.py, пишутся модулями 13-15
    # позже). Перезаписываем всегда (не только при первом запуске, как
    # app.py) — маленький файл без секретов, безопасно обновлять при
    # каждом прогоне модуля.
    cat > "$HUB_DIR/backend/_shared.py" << 'SHAREDEOF'
"""_shared.py — общие хелперы для отдельных модулей-виджетов хаба
(walletscope.py/memoscope.py/cheevoscope.py). НЕ содержит секретов и
бизнес-логики — только то, что реально нужно нескольким модулям сразу.
app.py (ядро хаба) держит собственные копии этих же функций — сознательно,
чтобы не городить циклический импорт между app.py (запускается как
__main__) и этим файлом."""
import os
import threading
import time
import urllib.request

DATA_DIR = "/app/data"


def read_file(path):
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except OSError:
        return None


def http_get(url, headers=None, timeout=30):
    req_headers = {"User-Agent": "deploy_kit-hub/1.0"}
    req_headers.update(headers or {})
    req = urllib.request.Request(url, headers=req_headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status, resp.read()


def http_post(url, headers=None, timeout=30):
    req = urllib.request.Request(url, headers=headers or {}, method="POST", data=b"")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status, resp.read()


# Потокобезопасный генератор ID для транзакций WalletScope и постов
# MemoScope — общий на оба модуля, чтобы гарантированно не совпадали ID
# между ними, даже если это в принципе не критично (разные namespace'ы).
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
SHAREDEOF

    # Перезаписываем всегда, когда шаг реально выполняется - см. пояснение
    # у index.html выше про "u) Обновить" в меню.
    cat > "$HUB_DIR/backend/app.py" << 'PYEOF'
#!/usr/bin/env python3
"""
NEXUS404 Hub — backend хаба. Только стандартная библиотека Python
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

# Простое ограничение частоты попыток входа по IP — без него /auth/callback
# можно было дёргать сколько угодно раз подряд без всякого ограничения. Не
# заменяет fail2ban (тот банит на уровне firewall, здесь — только на уровне
# приложения, в памяти процесса), но закрывает конкретно этот путь атаки
# почти бесплатно. Считаем только РЕАЛЬНО неудачные попытки (истёкший
# code/state, ошибка обмена у Pocket ID) — успешный вход в лимит не
# засчитывается (раньше засчитывался, из-за чего обычный вход с телефона
# и ноутбука подряд мог сам себя заблокировать без всякой атаки).
LOGIN_ATTEMPTS = {}   # ip -> [ts, ts, ...] — только неудачные попытки
LOGIN_RATE_LIMIT = 10       # неудачных попыток
LOGIN_RATE_WINDOW = 300     # за 5 минут


def is_login_rate_limited(ip):
    now = time.time()
    attempts = [t for t in LOGIN_ATTEMPTS.get(ip, []) if now - t < LOGIN_RATE_WINDOW]
    LOGIN_ATTEMPTS[ip] = attempts
    return len(attempts) >= LOGIN_RATE_LIMIT


def record_login_failure(ip):
    now = time.time()
    attempts = [t for t in LOGIN_ATTEMPTS.get(ip, []) if now - t < LOGIN_RATE_WINDOW]
    attempts.append(now)
    LOGIN_ATTEMPTS[ip] = attempts


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


# "Локальный" logout (просто стереть куку хаба) — недостаточно для OIDC:
# у Pocket ID (как у любого IdP) СВОЯ отдельная сессия на своём домене. Без
# явного "end session" у неё пользователь молча переавторизуется заново при
# следующем заходе на /login — Pocket ID видит СВОЮ ещё живую сессию и не
# спрашивает пароль/passkey вообще, что выглядит как "кнопка выйти не
# работает", хотя формально хаб свою куку честно стёр. Решение — RP-Initiated
# Logout по стандарту OIDC: если у Pocket ID есть end_session_endpoint (узнаём
# из штатного .well-known/openid-configuration, не гадаем на конкретном URL
# самостоятельно), редиректим туда — это и обрывает сессию у самого Pocket ID.
_pocketid_end_session_endpoint = None
_pocketid_discovery_checked = False


def get_pocketid_end_session_endpoint():
    global _pocketid_end_session_endpoint, _pocketid_discovery_checked
    if _pocketid_discovery_checked:
        return _pocketid_end_session_endpoint
    if not POCKETID_PUBLIC_URL:
        return None
    try:
        status, body = http_get(f"{POCKETID_INTERNAL_URL}/.well-known/openid-configuration", timeout=5)
        discovery = json.loads(body)
        _pocketid_end_session_endpoint = discovery.get("end_session_endpoint") or None
        # Кэшируем только реальный ответ Pocket ID — даже "поля нет"
        # (значит эта версия не поддерживает RP-Initiated Logout, это
        # долговременный факт про конкретную установку). Сетевую ошибку
        # НЕ кэшируем как результат — иначе один временный сбой Pocket ID
        # навсегда запомнился бы как "endpoint не поддерживается" до
        # перезапуска контейнера хаба.
        _pocketid_discovery_checked = True
    except Exception:
        _pocketid_end_session_endpoint = None
    return _pocketid_end_session_endpoint


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
        "id_token": token_data.get("id_token"),
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
    req_headers = {"User-Agent": "deploy_kit-hub/1.0"}
    req_headers.update(headers or {})
    req = urllib.request.Request(url, headers=req_headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status, resp.read()


def http_post(url, headers=None, timeout=30):
    req = urllib.request.Request(url, headers=headers or {}, method="POST", data=b"")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status, resp.read()


# WalletScope/MemoScope/Cheevoscope — отдельные файлы рядом с app.py (не
# отдельные контейнеры — та же самая среда выполнения, просто разложено
# по файлам для читаемости, а не всё в одном app.py). Модуль может быть
# ещё не установлен (пункты 13/14/15 меню идут ПОСЛЕ хаба, пункт 4) —
# тогда файла на диске просто ещё нет, import должен не падать, а тихо
# оставлять None; все места использования ниже это учитывают.
try:
    import walletscope
except ImportError:
    walletscope = None
try:
    import memoscope
except ImportError:
    memoscope = None
try:
    import cheevoscope
except ImportError:
    cheevoscope = None


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
    _t0 = time.time()
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
                    _t0 = time.time()
                    status, body = http_get(url, headers={"Authorization": new_token})
                else:
                    return {"error": "токен Beszel истёк, обновить не удалось — перезайдите в шаг 2 модуля Beszel"}
            except Exception:
                return {"error": "токен Beszel истёк, обновить не удалось — перезайдите в шаг 2 модуля Beszel"}
        else:
            return {"error": f"Beszel API вернул ошибку HTTP {e.code}"}
    except Exception:
        return {"systems": [], "online": False}
    ping_ms = round((time.time() - _t0) * 1000)

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
    return {"systems": systems, "online": True, "ping_ms": ping_ms}


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
            return {"users": users, "items": items, "online": True}
        except sqlite3.OperationalError:
            time.sleep(0.3)
    return {"users": 0, "items": 0, "online": False}


# ============================================================
# NTFY — последние уведомления из топика (только чтение, отдельный токен)
# ============================================================
def widget_ntfy():
    token = read_file(NTFY_TOKEN_FILE)
    topic = read_file(NTFY_TOPIC_FILE)
    if not token or not topic:
        return {"error": "ntfy ещё не установлен или не сохранил токен/топик"}

    url = f"{NTFY_API}/{topic}/json?poll=1&since=24h"
    _t0 = time.time()
    try:
        status, body = http_get(url, headers={"Authorization": f"Bearer {token}"})
    except Exception:
        return {"messages": [], "online": False}
    ping_ms = round((time.time() - _t0) * 1000)

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
    return {"messages": messages[:10], "online": True, "ping_ms": ping_ms}


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
    _t0 = time.time()
    try:
        status, body = http_get(url, headers={"Authorization": f"token {token}"})
    except Exception:
        return {"repos": [], "online": False}
    ping_ms = round((time.time() - _t0) * 1000)

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
    ], "online": True, "ping_ms": ping_ms}


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
    description = (fields.get("description") or "").strip()
    zip_content = files[0][2]

    try:
        status, repo_data = forgejo_api_request(
            "POST", "/api/v1/user/repos", token,
            {"name": repo_name, "private": private, "auto_init": True, "description": description},
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
}
if cheevoscope:
    WIDGETS["cheevoscope-stats"] = cheevoscope.widget_cheevoscope
if walletscope:
    WIDGETS["walletscope-data"] = walletscope.widget_walletscope
if memoscope:
    WIDGETS["memoscope-posts"] = memoscope.widget_memoscope


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
            self._redirect(build_authorize_url())
            return

        if path == "/auth/callback":
            if not AUTH_ENABLED:
                self._send_json({"error": "вход через Pocket ID не настроен"}, status=503)
                return
            if is_login_rate_limited(self.client_address[0]):
                self._send_json({"error": "слишком много неудачных попыток входа, подождите несколько минут"}, status=429)
                return
            code = query.get("code", [None])[0]
            state = query.get("state", [None])[0]
            if not code or not state:
                record_login_failure(self.client_address[0])
                self._send_json({"error": "нет code/state в ответе Pocket ID"}, status=400)
                return
            session_id, error = exchange_code_for_session(code, state)
            if error:
                record_login_failure(self.client_address[0])
                self._send_json({"error": error}, status=400)
                return
            self._redirect("/", set_cookie=session_id)
            return

        if path == "/logout":
            session = get_session(self) if AUTH_ENABLED else None
            end_session_endpoint = get_pocketid_end_session_endpoint() if AUTH_ENABLED else None
            if end_session_endpoint:
                params = {"post_logout_redirect_uri": HUB_PUBLIC_URL}
                if session and session.get("id_token"):
                    params["id_token_hint"] = session["id_token"]
                self._redirect(f"{end_session_endpoint}?{urllib.parse.urlencode(params)}", clear_cookie=True)
            else:
                # Pocket ID не отдала end_session_endpoint (старая версия
                # без RP-Initiated Logout, либо вообще недоступна прямо
                # сейчас) — хотя бы честно чистим свою куку, это не идеально
                # (сессия у Pocket ID при этом остаётся живой), но лучше,
                # чем совсем ничего не делать.
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

        if cheevoscope and path.startswith("/api/cheevoscope/game/") and path.endswith("/achievements"):
            appid = path[len("/api/cheevoscope/game/"):-len("/achievements")]
            cheevoscope.widget_cheevoscope_achievements(self, appid)
            return

        if cheevoscope and path.startswith("/api/cheevoscope/retro/game/") and path.endswith("/achievements"):
            game_id = path[len("/api/cheevoscope/retro/game/"):-len("/achievements")]
            cheevoscope.widget_cheevoscope_retro_achievements(self, game_id)
            return

        if cheevoscope and path.startswith("/api/cheevoscope/local-image/"):
            filename = urllib.parse.unquote(path[len("/api/cheevoscope/local-image/"):])
            cheevoscope.cheevoscope_local_image_proxy(self, filename)
            return

        if memoscope and path.startswith("/api/memoscope/image/"):
            filename = urllib.parse.unquote(path[len("/api/memoscope/image/"):])
            memoscope.memoscope_image_proxy(self, filename)
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

        if cheevoscope and path == "/api/cheevoscope/refresh":
            cheevoscope.widget_cheevoscope_refresh(self, query)
            return

        if walletscope and path == "/api/walletscope/add":
            walletscope.widget_walletscope_add(self)
            return

        if walletscope and path.startswith("/api/walletscope/edit/"):
            walletscope.widget_walletscope_edit(self, path[len("/api/walletscope/edit/"):])
            return

        if walletscope and path.startswith("/api/walletscope/delete/"):
            walletscope.widget_walletscope_delete(self, path[len("/api/walletscope/delete/"):])
            return

        if walletscope and path == "/api/walletscope/transfer":
            walletscope.widget_walletscope_transfer(self)
            return

        if walletscope and path == "/api/walletscope/withdraw":
            walletscope.widget_walletscope_withdraw(self)
            return

        if memoscope and path == "/api/memoscope/add":
            memoscope.widget_memoscope_add(self)
            return

        if memoscope and path.startswith("/api/memoscope/edit/"):
            memoscope.widget_memoscope_edit(self, path[len("/api/memoscope/edit/"):])
            return

        if memoscope and path.startswith("/api/memoscope/delete/"):
            memoscope.widget_memoscope_delete(self, path[len("/api/memoscope/delete/"):])
            return

        self._send_json({"error": "неизвестный маршрут для POST"}, status=404)




if __name__ == "__main__":
    ensure_vapid_keys()
    threading.Thread(target=ntfy_push_worker, daemon=True).start()
    if cheevoscope:
        os.makedirs(cheevoscope.CHEEVO_CACHE_DIR, exist_ok=True)
        os.makedirs(cheevoscope.CHEEVO_IMAGES_DIR, exist_ok=True)
        threading.Thread(target=cheevoscope.cheevo_hourly_worker, daemon=True).start()
    server = ThreadingHTTPServer(("0.0.0.0", 80), Handler)
    server.serve_forever()
PYEOF
        echo "${GREEN}[✓]${NC} backend/app.py создан: $HUB_DIR/backend/app.py"

    # Перезаписываем всегда, когда шаг реально выполняется - см. пояснение
    # у index.html выше про "u) Обновить" в меню.
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

    # Порт наружу НЕ публикуется — единственный путь снаружи идёт через
    # Caddy (шаг 2), изнутри — по имени контейнера dk_nexus404:80.
    run_spinner "Запуск NEXUS404 Hub" "dk_compose_up '$HUB_DIR'"
    # "docker compose up -d" НЕ перезапускает уже работающий контейнер,
    # если сама конфигурация compose не изменилась — а файлы внутри
    # bind-mount (html/backend/data) при этом сравнении не учитываются
    # вообще. Без явного restart переписанные выше файлы просто повиснут
    # на диске, а старый процесс продолжит работать со старым кодом в
    # памяти — критично для "u) Обновить" в меню (сброс STATEFILE).
    docker restart dk_nexus404 >/dev/null 2>>"$LOGFILE" || true

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
    echo "===== Результаты финальной проверки модуля NEXUS404 Hub ($(date '+%Y-%m-%d %H:%M:%S')) =====" >> "$LOGFILE"

    check_item "Контейнер NEXUS404 Hub запущен" bash -c "docker ps --format '{{.Names}}' | grep -qx dk_nexus404"
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
echo "  NEXUS404 Hub настроен — сохраните эту информацию."
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
