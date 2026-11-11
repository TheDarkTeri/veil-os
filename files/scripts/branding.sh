#!/usr/bin/env bash
#
# Veil OS branding. Runs once, at image build time (see recipes/recipe.yml).
#
# Every edit below is guarded: if the line or file it expects is not there
# (because Bazzite changed something upstream), the script exits non-zero and
# the build fails. A failed build is better than a half-branded image.
#
set -euo pipefail

DISTRO_NAME="Veil OS"
DISTRO_HOSTNAME="veil-os"
DISTRO_URL="https://github.com/TheDarkTeri/veil-os"

OS_RELEASE="/usr/lib/os-release"

# The wallpaper and boot logo are copied in by the "files" module before this runs.
WALLPAPER="/usr/share/wallpapers/VeilOS/contents/images/1920x1080.png"
WATERMARK="/usr/share/plymouth/themes/spinner/watermark.png"
# The wallpaper Bazzite configures as the KDE default.
BAZZITE_WALLPAPER="/usr/share/wallpapers/convergence.jxl"
LOOK_AND_FEEL_DIR="/usr/share/plasma/look-and-feel"

fail() {
    echo "branding.sh: $*" >&2
    exit 1
}

# set_key KEY VALUE
# Replace an existing KEY=... line in os-release with KEY="VALUE".
set_key() {
    local key="$1" value="$2"
    grep -q "^${key}=" "${OS_RELEASE}" \
        || fail "${key} not found in ${OS_RELEASE}"
    sed -i "s|^${key}=.*|${key}=\"${value}\"|" "${OS_RELEASE}"
}

# -- 0. The files this script relies on must exist ----------------------------
[[ -f "${OS_RELEASE}" ]] || fail "${OS_RELEASE} is missing"
[[ -f "${WALLPAPER}" ]] || fail "${WALLPAPER} is missing (files module did not copy it?)"
[[ -f "${WATERMARK}" ]] || fail "${WATERMARK} is missing (files module did not copy it?)"

# -- 1. os-release: display fields only ---------------------------------------
# What is changed: the name people see (About dialog, boot menu, login prompt),
# the default hostname, and the URLs, so bug reports do not go to Bazzite.
#
# What is deliberately NOT changed: ID, ID_LIKE, VARIANT_ID and the VERSION
# fields. Bazzite's own tooling and package repos identify the system by them.
echo "==> Rebranding ${OS_RELEASE}"
set_key NAME "${DISTRO_NAME}"
set_key PRETTY_NAME "${DISTRO_NAME}"
set_key DEFAULT_HOSTNAME "${DISTRO_HOSTNAME}"
set_key HOME_URL "${DISTRO_URL}"
set_key DOCUMENTATION_URL "${DISTRO_URL}#readme"
set_key SUPPORT_URL "${DISTRO_URL}/issues"
set_key BUG_REPORT_URL "${DISTRO_URL}/issues"

# BOOTLOADER_NAME is "Bazzite <version>". Swap only the name, keep the version.
grep -q '^BOOTLOADER_NAME="Bazzite' "${OS_RELEASE}" \
    || fail "BOOTLOADER_NAME does not start with \"Bazzite\" in ${OS_RELEASE}"
sed -i "s|^BOOTLOADER_NAME=\"Bazzite|BOOTLOADER_NAME=\"${DISTRO_NAME}|" "${OS_RELEASE}"

echo "--- ${OS_RELEASE} is now:"
cat "${OS_RELEASE}"
echo "---"

# -- 2. Default KDE wallpaper ---------------------------------------------------
# Bazzite sets the wallpaper for a new user's desktop in a small setup script
# inside each of its Plasma look-and-feel packages. Point those at our image.
# This affects new user accounts; an existing account keeps the wallpaper it has.
echo "==> Setting the default KDE wallpaper"
mapfile -t setup_scripts < <(
    grep -rlF --include='org.kde.plasma.folder.js' \
        "${BAZZITE_WALLPAPER}" "${LOOK_AND_FEEL_DIR}" || true
)
(( ${#setup_scripts[@]} > 0 )) \
    || fail "no org.kde.plasma.folder.js under ${LOOK_AND_FEEL_DIR} references ${BAZZITE_WALLPAPER}"

for setup_script in "${setup_scripts[@]}"; do
    sed -i "s|${BAZZITE_WALLPAPER}|${WALLPAPER}|g" "${setup_script}"
    grep -qF "${WALLPAPER}" "${setup_script}" \
        || fail "wallpaper path was not written to ${setup_script}"
    echo "    updated ${setup_script}"
done

echo "==> Branding done"
