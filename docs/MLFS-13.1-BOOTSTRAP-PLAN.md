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

- The five-entry mlfs-13.1-toolchain.tsv file is only an initial source-integrity gate. The new mlfs-13.1-package-inventory.tsv records 83 unique package/build inputs from the MLFS 13.1 Chapters 5-8 package sequence. It is an inventory, not a download manifest: exact archive URLs, SHA-256 values, and Chapter 3 patch records still need to be locked separately.
- systemd is part of the eventual target userspace, not one of the five cross-toolchain bootstrap components.
- The current manifest's systemd entry must not be interpreted as permission to build systemd during cross-toolchain bootstrap.
- The kernel API headers used by the cross-toolchain are not the same thing as the final BareLinux kernel image.
- The final kernel will be selected and built separately from the BareLinux-approved CachyOS-derived source and pinned configuration.

## Host requirements and CI consequences

The MLFS host-requirements chapter recommends at least four CPU cores and 8 GB RAM for practical build performance. It also requires a Linux host, UNIX 98 PTY support, and a defined set of development tools and aliases. The official book warns that untested newer host compiler/binutils versions may break the build.

The current CI host check is an initial prerequisite smoke test only. Before running a real MLFS build, extend it to verify the complete MLFS 13.1 host requirements and explicitly test that the host can compile and execute a 32-bit i686 program. The current Arch container setup has not yet demonstrated that multilib host capability.

Reference: https://www.linuxfromscratch.org/mlfs/view/stable/chapter02/hostreqs.html

## Package inventory

The current package inventory is maintained in [mlfs-13.1-package-inventory.tsv](../sources/manifests/mlfs-13.1-package-inventory.tsv) and checked by `scripts/check-package-inventory.sh`. It separates cross-toolchain passes, cross-compiled temporary tools, chroot temporary tools, and final-system packages. GRUB is recorded as reference-only because BareLinux uses Limine. The MLFS Linux API headers are retained, while the final BareLinux kernel source/configuration is tracked separately.

The inventory does not yet claim to include every supplemental documentation archive listed in Chapter 3. Those can be tracked separately if the build or documentation policy needs them.

## Required patch inventory

The Chapter 3.3 patch list is tracked separately in [mlfs-13.1-patches.tsv](../sources/manifests/mlfs-13.1-patches.tsv). It records the exact upstream URLs and the book-published MD5 values as provenance only. Those MD5 values are not accepted by the SHA-256 download gate.

BareLinux tracks the eight patches relevant to the selected userspace, with the glibc FHS patch marked for review because BareLinux has its own immutable filesystem policy. The OpenRC lock patch is retained as an excluded reference because BareLinux uses systemd, not OpenRC. Every patch SHA-256 remains pending independent verification; therefore no patch download is currently authorized.

The patch inventory is checked by `scripts/check-patch-inventory.sh` in CI. A structurally valid inventory does not mean that its patches have been downloaded, verified, or applied.

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
- 83-entry MLFS 13.1 build-package inventory and CI inventory validator
- Full source URL/SHA-256 lockfile and independent SHA-256 verification for all required archives and patches
- Verified SHA-256 digests for every required archive and applicable patch
- Complete host-requirements and 32-bit execution checks
- Reproducibly pinned container and package snapshot
- Cross-toolchain, temporary tools, chroot, and final system builds
- BareLinux root filesystem, kernel, Limine integration, and bootable ISO

This document is a plan and validation boundary; it does not claim that any MLFS package has been compiled.
