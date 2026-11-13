# MLFS 13.1 Bootstrap Plan

## Reference and scope

This plan follows the official Multilib Linux From Scratch (MLFS) 13.1 systemd book.

- Book: https://rivendell.linuxfromscratch.org/mlfs/view/stable/
- Release: 13.1, published 2026-08-31
- Target: x86_64/AMD64 with i686 multilib support

MLFS is the source-build foundation, not a prebuilt binary base. BareLinux will adapt its build sequence where required by the immutable layout, security model, kernel choice, and Limine boot flow. Such adaptations must be documented and tested rather than silently diverging from the book.

## Official bootstrap sequence

The MLFS 13.1 cross-toolchain stage lists these components in this order:

1. Binutils 2.47 — pass 1
2. GCC 16.2.0 — pass 1
3. Linux 7.1.8 API headers
4. glibc 2.44
5. libstdc++ from GCC 16.2.0

The temporary-tools stage then builds the book's specified utilities, including M4, Ncurses, Bash, Coreutils, Diffutils, File, Findutils, Gawk, Grep, Gzip, Make, Patch, Sed, Tar, Xz, Binutils pass 2, and GCC pass 2.

After that, MLFS enters chroot and builds the additional temporary tools before proceeding to the complete base system. The exact package order, configure options, multilib instructions, and patches must be taken from the matching 13.1 chapters.

Official stage outline: https://www.linuxfromscratch.org/mlfs/view/stable/part3.html

## Important separation of responsibilities

- The five-entry mlfs-13.1-toolchain.tsv file is currently only an initial source-integrity gate. It is not a complete MLFS package manifest.
- systemd is part of the eventual target userspace, not one of the five cross-toolchain bootstrap components.
- The current manifest's systemd entry must not be interpreted as permission to build systemd during cross-toolchain bootstrap.
- The kernel API headers used by the cross-toolchain are not the same thing as the final BareLinux kernel image.
- The final kernel will be selected and built separately from the BareLinux-approved CachyOS-derived source and pinned configuration.

## Host requirements and CI consequences

The MLFS host-requirements chapter recommends at least four CPU cores and 8 GB RAM for practical build performance. It also requires a Linux host, UNIX 98 PTY support, and a defined set of development tools and aliases. The official book warns that untested newer host compiler/binutils versions may break the build.

The current CI host check is an initial prerequisite smoke test only. Before running a real MLFS build, extend it to verify the complete MLFS 13.1 host requirements and explicitly test that the host can compile and execute a 32-bit i686 program. The current Arch container setup has not yet demonstrated that multilib host capability.

Reference: https://www.linuxfromscratch.org/mlfs/view/stable/chapter02/hostreqs.html

## Source integrity policy

No source is eligible for compilation until all of the following are recorded:

- Exact package name and version from MLFS 13.1
- Exact archive URL matching the book's release tarball
- Cryptographic digest verified against authoritative upstream metadata or a verified signature
- Digest algorithm and value stored with the manifest entry
- Any MLFS-required patch, its exact URL, and its integrity value

Do not copy a checksum for a different archive format (for example, .tar.gz versus .tar.xz). Do not infer SHA-256 from a SHA-512 value. The current fetcher intentionally blocks downloads while the manifest is incomplete.

## Build execution design

The eventual GitHub Actions build must:

1. Use a pinned build-container image digest and a reproducible package snapshot.
2. Allocate a dedicated build workspace under work/; never build into the runner's host root.
3. Create a dedicated unprivileged build user and enforce the MLFS environment and ownership rules.
4. Download only sources that pass the integrity gate.
5. Preserve complete per-package configure, build, test, and install logs.
6. Build in the exact MLFS 13.1 order, with explicit x86_64 and i686 stages.
7. Stop immediately on a failed command or validation.
8. Upload logs and intermediate build metadata as artifacts for diagnosis.
9. Avoid publishing an ISO until the root filesystem and boot path have been independently tested.

## Current status

Completed:
- Repository foundation and configuration checks
- MLFS 13.1 version baseline
- Fail-closed source-fetching logic
- CI validation of configuration, host smoke checks, and source-integrity gate behavior

Not yet completed:
- Full MLFS package and patch manifest
- Verified digests for every required archive and patch
- Complete host-requirements and 32-bit execution checks
- Reproducibly pinned container and package snapshot
- Cross-toolchain, temporary tools, chroot, and final system builds
- BareLinux root filesystem, kernel, Limine integration, and bootable ISO

This document is a plan and validation boundary; it does not claim that any MLFS package has been compiled.
