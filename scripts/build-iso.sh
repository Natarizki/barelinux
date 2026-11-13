#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${BARELINUX_WORK_DIR:-${ROOT_DIR}/work}"
ROOTFS="${BARELINUX_ROOTFS:-${WORK_DIR}/rootfs}"
KERNEL="${BARELINUX_KERNEL:-${WORK_DIR}/kernel/bzImage}"
KERNEL_CONFIG="${BARELINUX_KERNEL_CONFIG:-${WORK_DIR}/kernel/.config}"
BUSYBOX="${BARELINUX_BUSYBOX:-${WORK_DIR}/initramfs-tools/busybox}"
LIMINE_DIR="${BARELINUX_LIMINE_DIR:-${WORK_DIR}/limine}"
OUTPUT_DIR="${BARELINUX_OUTPUT_DIR:-${ROOT_DIR}/out}"
STAGING="${WORK_DIR}/iso-root"
INITRD_ROOT="${WORK_DIR}/initramfs-root"
ISO="${OUTPUT_DIR}/barelinux-x86_64.iso"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"; }

for cmd in mksquashfs cpio gzip xorriso sha256sum file readelf grep find install ln rm chmod; do need "$cmd"; done
[[ -d "$ROOTFS" ]] || fail "Root filesystem directory not found: $ROOTFS"
[[ -s "$KERNEL" ]] || fail "Kernel image not found: $KERNEL"
[[ -f "$KERNEL_CONFIG" ]] || fail "Kernel .config not found: $KERNEL_CONFIG"
bash "$ROOT_DIR/scripts/check-kernel-config.sh" "$KERNEL_CONFIG"
[[ -x "$BUSYBOX" ]] || fail "A static BusyBox executable is required: $BUSYBOX"
[[ -d "$LIMINE_DIR" ]] || fail "Limine asset directory not found: $LIMINE_DIR"

SYSTEMD="$ROOTFS/usr/lib/systemd/systemd"
[[ -x "$SYSTEMD" ]] || SYSTEMD="$ROOTFS/lib/systemd/systemd"
[[ -x "$SYSTEMD" ]] || fail "Rootfs must contain executable systemd at /usr/lib/systemd/systemd or /lib/systemd/systemd"
[[ -f "$ROOTFS/etc/os-release" ]] || fail "Rootfs is missing /etc/os-release"

if readelf -l "$BUSYBOX" 2>/dev/null | grep -q 'INTERP'; then
    fail "BusyBox is dynamically linked; build a static BusyBox for the initramfs"
fi

find_limine_asset() {
    local name="$1"
    local found
    found="$(find "$LIMINE_DIR" -type f -name "$name" -print -quit)"
    [[ -n "$found" ]] || fail "Missing Limine asset: $name"
    printf '%s' "$found"
}

LIMINE_BIOS_CD="$(find_limine_asset limine-bios-cd.bin)"
LIMINE_UEFI_CD="$(find_limine_asset limine-uefi-cd.bin)"
LIMINE_BIOS_SYS="$(find_limine_asset limine-bios.sys)"
LIMINE_EFI="$(find_limine_asset BOOTX64.EFI)"
LIMINE_CLI="$(find "$LIMINE_DIR" -type f -name limine -perm -u+x -print -quit)"
[[ -n "$LIMINE_CLI" ]] || fail "Missing executable Limine CLI (v12+ limine bios-install)"

rm -rf "$STAGING" "$INITRD_ROOT"
mkdir -p "$STAGING/boot" "$STAGING/EFI/BOOT" "$INITRD_ROOT/bin" "$INITRD_ROOT/dev" "$INITRD_ROOT/proc" "$INITRD_ROOT/sys" "$INITRD_ROOT/run" "$OUTPUT_DIR"

mksquashfs "$ROOTFS" "$STAGING/boot/rootfs.squashfs" -comp gzip -noappend -all-root
install -m 0644 "$KERNEL" "$STAGING/boot/vmlinuz"
install -m 0644 "$LIMINE_BIOS_SYS" "$STAGING/limine-bios.sys"
install -m 0644 "$LIMINE_BIOS_CD" "$STAGING/boot/limine-bios-cd.bin"
install -m 0644 "$LIMINE_UEFI_CD" "$STAGING/boot/limine-uefi-cd.bin"
install -m 0644 "$LIMINE_EFI" "$STAGING/EFI/BOOT/BOOTX64.EFI"
install -m 0755 "$BUSYBOX" "$INITRD_ROOT/bin/busybox"

for applet in sh mount umount mkdir sleep switch_root; do
    ln -s busybox "$INITRD_ROOT/bin/$applet"
done

cat > "$INITRD_ROOT/init" <<'INIT'
#!/bin/sh
PATH=/bin
export PATH
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mkdir -p /run/iso /newroot
n=0
media=
while [ "$n" -lt 30 ] && [ -z "$media" ]; do
    for dev in /dev/sr* /dev/sd* /dev/vd* /dev/nvme*n*; do
        [ -b "$dev" ] || continue
        if mount -t iso9660 -o ro "$dev" /run/iso 2>/dev/null; then
            if [ -f /run/iso/boot/rootfs.squashfs ]; then
                media="$dev"
                break
            fi
            umount /run/iso 2>/dev/null || true
        fi
    done
    [ -n "$media" ] || sleep 1
    n=$((n + 1))
done
if [ -z "$media" ]; then
    echo "BareLinux: could not locate BareLinux ISO9660 media"
    exec /bin/sh
fi
if ! mount -t squashfs -o loop,ro /run/iso/boot/rootfs.squashfs /newroot; then
    echo "BareLinux: could not mount immutable root filesystem"
    exec /bin/sh
fi
mkdir -p /newroot/etc /newroot/var /newroot/home /newroot/root /newroot/tmp /newroot/run /newroot/dev /newroot/proc /newroot/sys
mount -t tmpfs tmpfs /newroot/run
mkdir -p /newroot/run/iso /newroot/run/etc-upper /newroot/run/etc-work /newroot/run/var-upper /newroot/run/var-work /newroot/run/home-upper /newroot/run/home-work /newroot/run/root-upper /newroot/run/root-work
mount -t overlay overlay -o lowerdir=/newroot/etc,upperdir=/newroot/run/etc-upper,workdir=/newroot/run/etc-work /newroot/etc
mount -t overlay overlay -o lowerdir=/newroot/var,upperdir=/newroot/run/var-upper,workdir=/newroot/run/var-work /newroot/var
mount -t overlay overlay -o lowerdir=/newroot/home,upperdir=/newroot/run/home-upper,workdir=/newroot/run/home-work /newroot/home
mount -t overlay overlay -o lowerdir=/newroot/root,upperdir=/newroot/run/root-upper,workdir=/newroot/run/root-work /newroot/root
mount -t tmpfs -o mode=1777 tmpfs /newroot/tmp
mount --move /run/iso /newroot/run/iso
mount --move /dev /newroot/dev
mount --move /proc /newroot/proc
mount --move /sys /newroot/sys
echo "BareLinux: handing off to systemd"
exec switch_root /newroot /usr/lib/systemd/systemd
echo "BareLinux: systemd handoff failed"
exec /bin/sh
INIT
chmod 0755 "$INITRD_ROOT/init"

(
    cd "$INITRD_ROOT"
    find . -print0 | cpio --null -o --format=newc 2>/dev/null | gzip -9
) > "$STAGING/boot/initramfs.cpio.gz"

cat > "$STAGING/limine.conf" <<'CONF'
timeout: 5
default_entry: BareLinux

/BareLinux
    protocol: linux
    kernel_path: boot():/boot/vmlinuz
    module_path: boot():/boot/initramfs.cpio.gz
    cmdline: loglevel=4 ro
CONF

xorriso -as mkisofs \
    -R -r -J -V BARELINUX \
    -b boot/limine-bios-cd.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    --efi-boot boot/limine-uefi-cd.bin \
    -efi-boot-part --efi-boot-image --protective-msdos-label \
    "$STAGING" -o "$ISO"
"$LIMINE_CLI" bios-install "$ISO"

(
    cd "$OUTPUT_DIR"
    sha256sum "$(basename "$ISO")" > "$(basename "$ISO").sha256"
)
printf 'ISO created: %s\n' "$ISO"
printf 'Checksum: %s\n' "$ISO.sha256"
