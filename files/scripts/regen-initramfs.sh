#!/usr/bin/env bash
#
# Rebuild the initramfs. Runs once, at image build time (see recipes/recipe.yml).
#
# Why: the boot splash (Plymouth) starts from inside the initramfs, long before
# the real root filesystem is mounted. Its theme files, including the logo at
# /usr/share/plymouth/themes/spinner/watermark.png, are copied INTO the
# initramfs when it is generated. Replacing the PNG on disk is not enough; the
# initramfs has to be regenerated or the old Bazzite logo keeps showing.
#
# How: this mirrors the dracut call Bazzite itself uses to build its initramfs
# (build_files/build-initramfs.sh in github.com/ublue-os/bazzite), so the
# result is built the same way as the one it replaces.
#
set -euo pipefail

fail() {
    echo "regen-initramfs.sh: $*" >&2
    exit 1
}

# The installed kernel's version, e.g. "7.0.9-ogc3.2.fc45.x86_64".
# (Same query as upstream.)
QUALIFIED_KERNEL="$(
    dnf5 repoquery \
        --installed \
        --queryformat='%{evr}.%{arch}' \
        kernel
)"

[[ -n "${QUALIFIED_KERNEL}" ]] || fail "no installed 'kernel' package found"

# If the query ever returns something unexpected (no kernel, or two kernels run
# together), this directory will not exist and the build stops here.
MODULES_DIR="/usr/lib/modules/${QUALIFIED_KERNEL}"
INITRAMFS="${MODULES_DIR}/initramfs.img"
[[ -d "${MODULES_DIR}" ]] \
    || fail "${MODULES_DIR} does not exist (kernel query returned '${QUALIFIED_KERNEL}')"

echo "==> Rebuilding ${INITRAMFS}"

# Bazzite temporarily removes the per-build fields from os-release while dracut
# runs, so that the initramfs does not change on every build just because the
# version string did. Do the same, and always restore the file afterwards.
OS_RELEASE="/usr/lib/os-release"
TMP_OS_RELEASE="$(mktemp --tmpdir 'os-release-XXXXXXXXXX')"
cp "${OS_RELEASE}" "${TMP_OS_RELEASE}"
restore_os_release() {
    cp "${TMP_OS_RELEASE}" "${OS_RELEASE}"
    rm -f "${TMP_OS_RELEASE}"
}
trap restore_os_release EXIT
sed -Ei -e '/^((OSTREE_)?(IMAGE_)?VERSION|PRETTY_NAME|BUILD_ID|BOOTLOADER_NAME|IMAGE_ID)=/d' "${OS_RELEASE}"

# --no-hostonly  generic initramfs with drivers for any hardware, not just the build machine
# --kver         build for the image's kernel, not the build machine's
# --reproducible same input gives the same output
# --add fido2    Bazzite includes FIDO2 support (unlocking encrypted disks with a security key)
# -f             overwrite the existing file
DRACUT_NO_XATTR=1 /usr/bin/dracut \
    --no-hostonly \
    --kver "${QUALIFIED_KERNEL}" \
    --reproducible \
    -v \
    --add fido2 \
    -f "${INITRAMFS}"

# Readable by root only, as upstream does.
chmod 0600 "${INITRAMFS}"

[[ -s "${INITRAMFS}" ]] || fail "${INITRAMFS} is empty after dracut"
echo "==> Initramfs rebuilt for kernel ${QUALIFIED_KERNEL}"
