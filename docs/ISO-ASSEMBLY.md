# ISO Assembly Contract

This stage packages a completed BareLinux live root filesystem; it does not build the MLFS userspace.

## Required inputs

Set these environment variables to override defaults:

- `BARELINUX_WORK_DIR` (default `work/`)
- `BARELINUX_ROOTFS` (default `work/rootfs/`)
- `BARELINUX_KERNEL` (default `work/kernel/bzImage`)
- `BARELINUX_BUSYBOX` (default `work/initramfs-tools/busybox`): a **static** x86_64 BusyBox with `sh`, `mount`, `mkdir`, `sleep`, and `switch_root` applets
- `BARELINUX_LIMINE_DIR` (default `work/limine/`): Limine v12+ assets `limine-bios-cd.bin`, `limine-uefi-cd.bin`, `limine-bios.sys`, `BOOTX64.EFI`, and the executable `limine` CLI
- `BARELINUX_OUTPUT_DIR` (default `out/`)

The root filesystem must contain executable systemd at `/usr/lib/systemd/systemd` or `/lib/systemd/systemd`, plus `/etc/os-release`. The kernel must have built-in support for the live-media path: devtmpfs, procfs, sysfs, ISO-9660, loop devices, SquashFS with gzip compression, overlayfs, and tmpfs. The initramfs BusyBox must be static.

## Output and boot path

The script creates `out/barelinux-x86_64.iso` and a SHA-256 sidecar. It embeds the rootfs as a read-only SquashFS image, uses a small initramfs to mount the ISO and SquashFS root, creates temporary writable overlays for `/etc`, `/var`, and `/home`, preserves `/dev`, `/proc`, and `/sys`, and hands off to systemd. Limine's BIOS and UEFI CD boot assets are included; the generated ISO is then processed with `limine bios-install`.

This script deliberately refuses incomplete inputs. It does not download unverified bootloader assets, invent a kernel/rootfs, or claim that an image is bootable merely because xorriso returned success.

## Required release tests

A produced image is only a build candidate until it passes:
1. ISO structure and checksum validation.
2. BIOS QEMU boot with a serial/console success marker from the target system.
3. UEFI QEMU boot with OVMF and the same success marker.
4. A test that systemd reaches the declared live target and that the root filesystem is read-only.

The current foundation workflow tests only the builder's fail-closed preflight. It does not run a full distro build or claim bootability.
