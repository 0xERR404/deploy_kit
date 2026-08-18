#!/bin/bash
# =============================================================================
# install.sh — устанавливает deploy_kit без зависимости от git: тянет файлы
# напрямую через curl из GitHub и сразу запускает меню.
#
# Одностроковая установка:
#   curl -fsSL https://raw.githubusercontent.com/0xERR404/deploy_kit/main/install.sh | sudo bash
#
# ВАЖНО: EXPECTED_SHA256 ниже — хэши конкретных версий menu.sh/common.sh/
# modules/01_base_setup.sh. При любом изменении этих файлов хэши нужно
# пересчитать и обновить здесь, иначе установка будет падать с ошибкой
# проверки целостности. Пересчитать:
# sha256sum menu.sh common.sh modules/01_base_setup.sh modules/02_docker_caddy.sh modules/03_pocketid.sh modules/04_nexus404.sh modules/05_ntfy.sh modules/06_beszel.sh modules/07_vaultwarden.sh modules/08_forgejo.sh modules/13_cheevoscope.sh modules/14_walletscope.sh modules/15_memoscope.sh modules/_planned.sh modules/16_summary.sh tools/test_ntfy.sh
# =============================================================================
set -e

REPO_RAW="https://raw.githubusercontent.com/0xERR404/deploy_kit/main"
INSTALL_DIR="/var/lib/deploy_kit"

declare -A EXPECTED_SHA256=(
    ["menu.sh"]="dcb434b9c18b4384c752956d726991d0ef6a27a905650623a737d57ab4a6c928"
    ["common.sh"]="663ab228ee49e0c9a65b64239b44c74dd62de417d32102457d9b8efe8d9cc0f4"
    ["modules/01_base_setup.sh"]="ac7c1b5fad7d680d185f5f81bcedae1bebec738655ad968af147871f5b689373"
    ["modules/02_docker_caddy.sh"]="991a8341302367fe723114c0789c4fa15b4275c2cfa017076689f0917cf6b502"
    ["modules/03_pocketid.sh"]="1fdef10eef6758fb85205b204ef86417fd7179d756f27882f4f6038e15d9993b"
    ["modules/04_nexus404.sh"]="dfc49b5300f185f4d79e9f6b8241593f721e7f90b30e647f9d41f6db558c7eda"
    ["modules/05_ntfy.sh"]="5363fd1eb29dd7d7ff167a53700044da77817d85ba7fabf83172df98af589b9e"
    ["modules/06_beszel.sh"]="5ae6e8d3af6ad794ed7f80cfb44831e44edf670848b35f1928329ff915a4e8ac"
    ["modules/07_vaultwarden.sh"]="fd6dfc7d7a8d93bba86e3a5de662930d6a46175f471069b8c3aaed37f34af4b3"
    ["modules/08_forgejo.sh"]="e15823dc432c968ec4c64bfeaee180685441d6b1fdb2363ff946691e7dc3afaf"
    ["modules/13_cheevoscope.sh"]="b22db1bf15adbb7350d00ff216461b67d0d24bdc4703c6f6cd3c90c8757f5cda"
    ["modules/14_walletscope.sh"]="17c027e90b4b813ce4dc517551d3c00b60237aa2ac5535cf32ba2702f2b44a7d"
    ["modules/15_memoscope.sh"]="c0efe53b2b7eb61a83299c95b6fca3538a178ddbf843e6762c09f67a6b2aac31"
    ["modules/_planned.sh"]="712a4e431ab0a1b2bc45ca304e36ec1aa8b48f9b22a7800d173ec3f63d4fe246"
    ["modules/16_summary.sh"]="464e2c26854a2e5b0cf17b1de3c044f99c784d6886983e4c77810b0da540ea6d"
    ["tools/test_ntfy.sh"]="0feeac84be69288d2f09968b516f796623397d21f37ad105aa59fb2c03c1040c"
)

if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Запускать нужно от root (или через sudo)"
    exit 1
fi

if ! grep -qiE 'ubuntu|debian' /etc/os-release 2>/dev/null; then
    echo "[!] Поддерживаются только Ubuntu/Debian — обнаружена другая ОС, прерываю."
    exit 1
fi

echo "[*] Скачиваю deploy_kit в $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR/modules" "$INSTALL_DIR/tools"

download() {
    local path="$1"
    local expected="${EXPECTED_SHA256[$path]}"
    local actual

    curl -fsSL "$REPO_RAW/$path" -o "$INSTALL_DIR/$path"

    actual=$(sha256sum "$INSTALL_DIR/$path" | awk '{print $1}')
    if [ "$actual" != "$expected" ]; then
        echo "[!] Проверка SHA-256 не пройдена для $path"
        echo "    ожидалось: $expected"
        echo "    получено:  $actual"
        echo "[!] Файл повреждён при скачивании или репозиторий обновился, а install.sh — нет."
        exit 1
    fi
}

download "menu.sh"
download "common.sh"
download "modules/01_base_setup.sh"
download "modules/02_docker_caddy.sh"
download "modules/03_pocketid.sh"
download "modules/04_nexus404.sh"
download "modules/05_ntfy.sh"
download "modules/06_beszel.sh"
download "modules/07_vaultwarden.sh"
download "modules/08_forgejo.sh"
download "modules/13_cheevoscope.sh"
download "modules/14_walletscope.sh"
download "modules/15_memoscope.sh"
download "modules/_planned.sh"
download "modules/16_summary.sh"
download "tools/test_ntfy.sh"

chmod +x "$INSTALL_DIR/menu.sh" "$INSTALL_DIR/common.sh" \
    "$INSTALL_DIR/modules/01_base_setup.sh" "$INSTALL_DIR/modules/02_docker_caddy.sh" \
    "$INSTALL_DIR/modules/03_pocketid.sh" "$INSTALL_DIR/modules/04_nexus404.sh" \
    "$INSTALL_DIR/modules/05_ntfy.sh" \
    "$INSTALL_DIR/modules/06_beszel.sh" \
    "$INSTALL_DIR/modules/07_vaultwarden.sh" "$INSTALL_DIR/modules/08_forgejo.sh" \
    "$INSTALL_DIR/modules/13_cheevoscope.sh" \
    "$INSTALL_DIR/modules/14_walletscope.sh" "$INSTALL_DIR/modules/15_memoscope.sh" \
    "$INSTALL_DIR/modules/_planned.sh" "$INSTALL_DIR/modules/16_summary.sh" \
    "$INSTALL_DIR/tools/test_ntfy.sh"

echo "[✓] Готово, запускаю меню..."
echo ""
exec bash "$INSTALL_DIR/menu.sh" < /dev/tty
