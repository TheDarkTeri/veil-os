#!/usr/bin/env bash
#
# Adapts Bazzite's ISO installer so that the ISO installs Veil OS.
#
#   usage: iso/patch-installer.sh <path to Bazzite's installer/ directory>
#
# Veil OS has no installer of its own. The ISO workflow checks out the
# installer/ directory of github.com/ublue-os/bazzite at a pinned commit and
# builds it with Veil OS as the image to install. This script makes four
# changes to that installer and nothing else. The first three are needed
# because Bazzite's scripts assume the image is *called* bazzite-something;
# the fourth works around an installer failure on Fedora 45:
#
#   1. Which image gets installed (required: without this the installer has no target).
#   2. The boot menu of the ISO (name only).
#   3. The word "Bazzite" in the live session's welcome dialogs (name only).
#   4. /mnt becomes a real directory in the live session (required on
#      Fedora 45: otherwise the install stops with systemd-tmpfiles exit code 73).
#
# Like the other scripts in this repo, every change is guarded. If Bazzite's
# files no longer look the way this script expects (after bumping the pinned
# commit), it exits non-zero and the ISO build stops, instead of producing an
# ISO that installs the wrong thing.
#
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: patch-installer.sh <path to the Bazzite installer/ directory>" >&2; exit 2; }
INSTALLER_DIR="$1"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HOOK="${INSTALLER_DIR}/titanoboa_hook_postrootfs.sh"
LOGIN="${INSTALLER_DIR}/system_files/shared/usr/bin/on_gui_login.sh"
ISO_YAML="${INSTALLER_DIR}/iso.yaml"
OUR_ISO_YAML="${HERE}/iso.yaml"

# Name-based switches in Bazzite's hook, answered for Veil OS:
#   *-nvidia*  yes: make the live desktop usable on NVIDIA hardware (it runs on
#                   the open nouveau driver; the real driver comes with the install).
#   *-deck*    no:  that one only turns on an on-screen keyboard for handhelds.
LIVE_VARIANT="bazzite-nvidia"

fail() {
    echo "patch-installer.sh: $*" >&2
    exit 1
}

# count FILE FIXED-STRING -> number of lines containing it
count() {
    grep -cF -- "$2" "$1" || true
}

for f in "${HOOK}" "${LOGIN}" "${ISO_YAML}" "${OUR_ISO_YAML}"; do
    [[ -f "${f}" ]] || fail "${f} not found"
done

BACKUP="$(mktemp -d)"
trap 'rm -rf "${BACKUP}"' EXIT
cp "${HOOK}" "${BACKUP}/hook"
cp "${LOGIN}" "${BACKUP}/login"
cp "${ISO_YAML}" "${BACKUP}/iso.yaml"

# -- 1. Which image gets installed ---------------------------------------------
# Upstream finds it with "the first image in container storage named bazzite*":
#
#   imageref="$(podman images --format '{{ index .Names 0 }}\n' 'bazzite*' | head -1)"
#   imageref="${imageref##*://}"
#   imageref="${imageref%%:*}"
#   imagetag="$(podman images --format '{{ .Tag }}\n' "$imageref" | head -1)"
#
# ghcr.io/thedarkteri/veil-os does not match, so imageref would be empty.
# INSTALL_IMAGE_PAYLOAD (the build argument that names the image to embed) is
# already in the hook's environment, so use it directly.
echo "==> 1/4 install target"

start_line="$(grep -n '^imageref="\$(podman images' "${HOOK}" | cut -d: -f1 || true)"
end_line="$(grep -n '^imagetag="\$(podman images' "${HOOK}" | cut -d: -f1 || true)"
[[ "${start_line}" =~ ^[0-9]+$ ]] || fail "expected exactly one 'imageref=\"\$(podman images' line in ${HOOK}"
[[ "${end_line}" =~ ^[0-9]+$ ]] || fail "expected exactly one 'imagetag=\"\$(podman images' line in ${HOOK}"
(( end_line - start_line == 3 )) \
    || fail "the image lookup in ${HOOK} is no longer the 4-line block this script replaces (lines ${start_line}-${end_line})"

# These two lines are what make the installer deploy the embedded image and
# then point the installed system at the registry for updates. They must still
# be there, and still be driven by $imageref:$imagetag.
[[ "$(count "${HOOK}" 'ostreecontainer --url=$imageref:$imagetag --transport=containers-storage')" == 1 ]] \
    || fail "the 'ostreecontainer --url=\$imageref:\$imagetag' line is missing or changed in ${HOOK}"
[[ "$(count "${HOOK}" 'bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry $imageref:$imagetag')" == 1 ]] \
    || fail "the 'bootc switch ... \$imageref:\$imagetag' line is missing or changed in ${HOOK}"

cat > "${BACKUP}/replacement" <<EOF
# Veil OS: install the image named by INSTALL_IMAGE_PAYLOAD (see iso/patch-installer.sh).
: "\${INSTALL_IMAGE_PAYLOAD:?}"
[[ \$INSTALL_IMAGE_PAYLOAD == *:* ]] || { echo "INSTALL_IMAGE_PAYLOAD needs a tag: \$INSTALL_IMAGE_PAYLOAD" >&2; exit 1; }
imageref="\${INSTALL_IMAGE_PAYLOAD%:*}"
imagetag="\${INSTALL_IMAGE_PAYLOAD##*:}"
# Veil OS: answers the name-based checks further down (*-nvidia*, *-deck*).
payload_variant="${LIVE_VARIANT}"
EOF

awk -v first="${start_line}" -v last="${end_line}" -v repl="${BACKUP}/replacement" '
    NR == first { while ((getline line < repl) > 0) print line }
    NR >= first && NR <= last { next }
    { print }
' "${BACKUP}/hook" > "${BACKUP}/hook.new"

# The checks that used the image's name now use payload_variant.
[[ "$(count "${BACKUP}/hook.new" '[[ $imageref == *-nvidia* ]]')" -ge 1 ]] \
    || fail "no '[[ \$imageref == *-nvidia* ]]' check found in ${HOOK}"
sed -i -e 's/\[\[ \$imageref == \*-nvidia\* \]\]/[[ $payload_variant == *-nvidia* ]]/' \
       -e 's/\[\[ \$imageref == \*-deck\* \]\]/[[ $payload_variant == *-deck* ]]/' "${BACKUP}/hook.new"

[[ "$(count "${BACKUP}/hook.new" '$imageref ==')" == 0 ]] \
    || fail "${HOOK} still compares \$imageref against a name pattern this script does not know"
[[ "$(count "${BACKUP}/hook.new" "'bazzite*'")" == 0 ]] \
    || fail "${HOOK} still looks an image up by the name 'bazzite*'"

cat "${BACKUP}/hook.new" > "${HOOK}"   # keeps the file's mode
bash -n "${HOOK}" || fail "${HOOK} is not valid bash after patching"

# -- 2. Boot menu ------------------------------------------------------------------
echo "==> 2/4 boot menu"
label="$(sed -n 's/^label: *"\(.*\)" *$/\1/p' "${OUR_ISO_YAML}")"
[[ -n "${label}" ]] || fail "no label found in ${OUR_ISO_YAML}"
entries="$(grep -c '^ *linux:' "${OUR_ISO_YAML}" || true)"
with_label="$(grep -c "^ *linux:.* root=live:CDLABEL=${label} " "${OUR_ISO_YAML}" || true)"
[[ "${entries}" -ge 1 && "${entries}" == "${with_label}" ]] \
    || fail "every 'linux:' line in ${OUR_ISO_YAML} must contain root=live:CDLABEL=${label}"
# Same keys as upstream's file, so Titanoboa finds what it expects.
for key in 'label:' 'grub2:' 'entries:' 'initrd:'; do
    [[ "$(count "${ISO_YAML}" "${key}")" -ge 1 ]] || fail "upstream ${ISO_YAML} has no '${key}' (format changed?)"
done
cat "${OUR_ISO_YAML}" > "${ISO_YAML}"

# -- 3. Welcome dialogs --------------------------------------------------------------
# The live session's login script shows the "Install ..." dialog. It also has
# a helper that warns about the wrong Bazzite image for your GPU; that helper
# finds the image by the name 'bazzite*', finds nothing here, and skips itself.
# That is intended, so make sure it still works that way.
echo "==> 3/4 welcome dialogs"
[[ "$(count "${LOGIN}" 'Welcome to the Live ISO for Bazzite')" == 1 ]] \
    || fail "welcome text not found in ${LOGIN}"
[[ "$(count "${LOGIN}" 'install_button="Install Bazzite"')" == 1 ]] \
    || fail "install button not found in ${LOGIN}"
[[ "$(count "${LOGIN}" "podman images --format '{{ index .Names 0 }}\\n' 'bazzite*')")" == 1 ]] \
    || fail "the hardware helper's image lookup changed in ${LOGIN}"
[[ "$(count "${LOGIN}" 'if [ -z "$image_name" ]; then')" == 1 ]] \
    || fail "the hardware helper no longer skips itself when it finds no image in ${LOGIN}"

sed -i 's/Bazzite/Veil OS/g' "${LOGIN}"
[[ "$(count "${LOGIN}" 'Bazzite')" == 0 ]] || fail "'Bazzite' still appears in ${LOGIN}"
bash -n "${LOGIN}" || fail "${LOGIN} is not valid bash after patching"

# -- 4. /mnt must be a real directory in the live environment --------------------------
# Found by the first test install (2026-11-13): the installer died with
#   systemd-tmpfiles --create --boot --root=/mnt/sysroot --prefix=/var/home  -> exit code 73
# and no message. With SYSTEMD_LOG_LEVEL=debug it says:
#   Path '/mnt/sysroot/var/home' is not under root '/var/mnt/sysroot', refusing SELinux label fix.
#
# On Fedora Atomic images /mnt is a symlink to /var/mnt, and the live session
# IS such an image. Anaconda tells systemd-tmpfiles --root=/mnt/sysroot.
# systemd 262 (Fedora 45) resolves the root to /var/mnt/sysroot for its SELinux
# code but keeps the unresolved spelling for the files, then refuses to label a
# file that is "not under" the root. Making /mnt a real directory in the live
# image removes the two spellings. secureblue fixed its live ISO the same way
# (secureblue/secureblue pull request 2808).
#
# This only changes the live environment. The installed system keeps its
# normal /mnt -> /var/mnt symlink.
echo "==> 4/4 /mnt in the live environment"
BUILD_SH="${INSTALLER_DIR}/build.sh"
[[ -f "${BUILD_SH}" ]] || fail "${BUILD_SH} not found"
for f in "${HOOK}" "${BUILD_SH}"; do
    if grep -qE '(^|[[:space:]"'"'"'])/mnt([[:space:]"'"'"']|$)' "${f}"; then
        fail "${f} now handles /mnt itself; check whether step 4 of this script is still needed"
    fi
done

cat >> "${HOOK}" <<'EOF'

# Veil OS: /mnt must be a real directory in the live session, not the usual
# symlink to /var/mnt, or the installer's systemd-tmpfiles step fails with
# exit code 73 (see iso/patch-installer.sh, step 4).
if [[ -L /mnt ]]; then
    rm /mnt
    mkdir -m 0755 /mnt
fi
[[ -d /mnt && ! -L /mnt ]] || { echo "/mnt is not a real directory" >&2; exit 1; }
EOF
bash -n "${HOOK}" || fail "${HOOK} is not valid bash after patching"

# -- Show what changed -----------------------------------------------------------------
echo
echo "---- ${HOOK}"
diff -u "${BACKUP}/hook" "${HOOK}" || true
echo
echo "---- ${ISO_YAML}"
diff -u "${BACKUP}/iso.yaml" "${ISO_YAML}" || true
echo
echo "---- ${LOGIN}: $(diff "${BACKUP}/login" "${LOGIN}" | grep -c '^>' || true) lines changed (Bazzite -> Veil OS)"
echo
echo "==> Installer patched for Veil OS"
