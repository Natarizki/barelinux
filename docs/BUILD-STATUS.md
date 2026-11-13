# BareLinux Build Status

**Last engineering checkpoint:** ISO assembly and boot acceptance tooling.

## Verified in CI

- Architecture and MLFS 13.1 policy validation
- Source-fetcher fail-closed behavior
- Package and patch inventory structure
- ISO assembler shell syntax and rejection of incomplete workspaces
- Live-kernel configuration validator regression tests

These checks validate repository logic. They do not prove that MLFS has been compiled or that an ISO boots.

## Current build execution

- Binutils Pass 1 is built and validated through the generated jhalfs Makefile.
- The first full-book attempts restored the verified checkpoint and entered jhalfs target `502-gcc-pass1`, but failed because `gcc-16.2.0.tar.xz` was absent from the build root's `sources/` directory.
- The failure log was inspected from the uploaded workflow artifact; it showed a missing source archive, not a compiler error.
- The source-generation configuration now enables jhalfs' built-in source retrieval, uses curl retries, and keeps the source downloads in the build root. The full-build runner now checks the complete URL inventory, missing-download report, and book-provided MD5 list before starting the Makefile.
- A fresh Binutils checkpoint run will regenerate the source cache with these settings and trigger another full-book attempt. This fix has been committed but has not yet passed a new end-to-end run.

## Not built yet

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
