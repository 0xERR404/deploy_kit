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
    ["menu.sh"]="cd23b8a2bee2bb17467ed74628dc5bffe5fa80eba23be59d3ce63d4ab92f1f4c"
    ["common.sh"]="418819acea2d82cc27567edd00632322e13278c897b2bda0eeef03260fd3bcca"
    ["modules/01_base_setup.sh"]="ac7c1b5fad7d680d185f5f81bcedae1bebec738655ad968af147871f5b689373"
    ["modules/02_docker_caddy.sh"]="af2c2d4ff3da15b5fd418daff324548f62a1637fe955fa6e74578b4d22d4b7c0"
    ["modules/03_pocketid.sh"]="eb76b89225457988cbd7c3c53286fe4ca5151434f5f2adc4c6433e99fc2220c9"
    ["modules/04_nexus404.sh"]="e64afa4bc63680fc3cb0bd58a50cf96c43de8288e84f908ca27815e8021e44a4"
    ["modules/05_ntfy.sh"]="75d1e8a46bd6cc9b2b926f94ec1c0f1505c94f4bf6272e2060d943503db95bee"
    ["modules/06_beszel.sh"]="9afa1d6d9bd04e4b5ae2176726332874288016c24db46384566f70310c8483ca"
    ["modules/07_vaultwarden.sh"]="41b83deb35651c546bf371e2968fd38b8e58bc4effd879efaff8897bdeb981b5"
    ["modules/08_forgejo.sh"]="51c5aec70283937521da75ec6cb932dd2a8775c04687c31d30f36b5b1d410f4b"
    ["modules/13_cheevoscope.sh"]="8a22b38a6c79e0aa54c339ef9cbddab94c242ac17309e8107ca8692fdc9beb1d"
    ["modules/14_walletscope.sh"]="94b0cbdfb591cd07031495c1d60fb36faea7275ad21d2f2a89dbf0e4c08643ea"
    ["modules/15_memoscope.sh"]="245cab85ee1a8dc85495476b8c643118ffaf6fa6e486e94ca9cbe64b9454da8b"
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
