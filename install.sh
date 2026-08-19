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
    ["menu.sh"]="a6e34e9d12f37c62c5e0d0908e049e1d9fe99b282685ad63088b126c03387cdc"
    ["common.sh"]="aa36e8bc81b5971955166eb16b809bd3457c317fbf1e9f8b2171cfa7d52f14cb"
    ["modules/01_base_setup.sh"]="ac7c1b5fad7d680d185f5f81bcedae1bebec738655ad968af147871f5b689373"
    ["modules/02_docker_caddy.sh"]="997fb12bde30972447ac4da2c836dccf47f147f8b9a730947a2a1666b4e59203"
    ["modules/03_pocketid.sh"]="29866323c1d397814ec42529b941a8df72b118eb2da76cdbed594ecc90cdc32b"
    ["modules/04_nexus404.sh"]="2ef832e53508bb8c2ac0b1056ee3aa5f078cd7d8c2107888dae345732ed69f06"
    ["modules/05_ntfy.sh"]="01d9a5088e9135813bfbb2f52b43ee452cd7fe62b9948135a2eea2de31b9541d"
    ["modules/06_beszel.sh"]="71000162c8c0e15757f51f96d90b5e5676d8edd78698330f8877185728ff2cc6"
    ["modules/07_vaultwarden.sh"]="dfb661494acff5488f24e94c21173c4fe29e373234ef749e0cbdb2755896f43c"
    ["modules/08_forgejo.sh"]="f778d5a255d20e5f038f9ebc18097a368bdc3469f7f7a203293679ff7a77b208"
    ["modules/13_cheevoscope.sh"]="fb2143460bc94c1b264fdbd45d53012153313ff9771b61c57df410dfb1dd44a2"
    ["modules/14_walletscope.sh"]="a5954f29b38a04695e026b909b16a19136412624fc987e6b8cceb8a5a860292d"
    ["modules/15_memoscope.sh"]="9f923f6a389f9890102c620b6397b5c9f9d0c8b25b43840b8f3840ae0199549c"
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
