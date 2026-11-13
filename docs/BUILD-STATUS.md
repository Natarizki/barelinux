# BareLinux Build Status

**Last engineering checkpoint:** ISO assembly and boot acceptance tooling.

## Verified in CI

- Architecture and MLFS 13.1 policy validation
- Source-fetcher fail-closed behavior
- Package and patch inventory structure
- ISO assembler shell syntax and rejection of incomplete workspaces
- Live-kernel configuration validator regression tests

These checks validate repository logic. They do not prove that MLFS has been compiled or that an ISO boots.

## Current build execution\n\n- Binutils Pass 1 is built and validated through the generated jhalfs Makefile.\n- A continuous six-hour full-MLFS workflow resumed from the verified Binutils artifact and reached the generated `502-gcc-pass1` target, but failed during jhalfs' LFS-user/root privilege transition. The runner now provisions a temporary, validated sudoers rule for the disposable `lfs` account and removes it on exit; the fresh Binutils checkpoint succeeded and automatically triggered a full-book retry; that workflow is currently preparing the hosted runner and has not yet restarted jhalfs.\n\n## Not built yet

- Complete, independently verified SHA-256 source lockfile for every required MLFS archive and patch
- Complete MLFS cross-toolchain, temporary toolchain, and final userspace (full-book workflow pending)
- Complete MLFS chroot/final userspace root filesystem
- BareLinux kernel image with every required live-media driver built in
- Static initramfs BusyBox
- Pinned Limine v12+ BIOS/UEFI binary set
- BareLinux ISO
- BIOS and UEFI QEMU boot acceptance

## Build order and release gates

1. Reconcile the package inventory against the exact MLFS 13.1 stable book.
2. Lock every archive and applicable patch to the exact book URL and independently verified SHA-256.
3. Build the MLFS cross-toolchain, temporary tools, and final rootfs in book order; preserve logs and test results.
4. Apply BareLinux-specific systemd, immutable filesystem, and security configuration.
5. Build the kernel and run `scripts/check-kernel-config.sh` against its final `.config`.
6. Supply a static BusyBox initramfs and a pinned Limine BIOS/UEFI asset set.
7. Run `scripts/build-iso.sh`.
8. Run `scripts/test-iso-boot.sh` and require both BIOS and UEFI to reach the systemd multi-user target.

A successful ISO assembly command is not a release pass. The image remains a build candidate until both firmware-mode boot tests pass and the immutable root behavior is checked.

## Resource note

The MLFS 13.1 host requirements recommend at least four CPU cores and 8 GB RAM for practical build performance. The full MLFS build runner is `.github/workflows/build-mlfs-full.yml`; it is a long-running GitHub-hosted build and has not yet proven that the complete book fits the runner's disk/time budget. Full build resource availability and disk capacity must be verified before scheduling the long compile.
