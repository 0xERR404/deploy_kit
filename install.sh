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
    ["modules/02_docker_caddy.sh"]="af2c2d4ff3da15b5fd418daff324548f62a1637fe955fa6e74578b4d22d4b7c0"
    ["modules/03_pocketid.sh"]="eb76b89225457988cbd7c3c53286fe4ca5151434f5f2adc4c6433e99fc2220c9"
    ["modules/04_nexus404.sh"]="7c54dd503499be8fded5b3e75da38efb93071ecde0c86c7ee99695584d418048"
    ["modules/05_ntfy.sh"]="4548ee3217254578c8b2b93d9d515f13d25b25d0e8736389f2d2c04284934363"
    ["modules/06_beszel.sh"]="c03cb126bd134b76d802759c1255cb3bc20691be342a3c99ba5d0003ce14fb7e"
    ["modules/07_vaultwarden.sh"]="41b83deb35651c546bf371e2968fd38b8e58bc4effd879efaff8897bdeb981b5"
    ["modules/08_forgejo.sh"]="a3f301ae519f50bf22d09f3507fcf164bef3556459a5b32044e0f5b53ec47045"
    ["modules/13_cheevoscope.sh"]="797c8b2999df502c834bda7fbfc281b3281dffc9a2ad12b9a2777182e69a4b9b"
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
