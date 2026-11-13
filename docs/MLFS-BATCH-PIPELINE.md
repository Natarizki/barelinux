# BareLinux MLFS Batch Build and Validation Pipeline

**Status:** Execution design. Binutils Pass 1 is built and uploaded; the complete package pipeline is not implemented yet.

## Goal

Build the complete BareLinux base system and ISO as a coordinated pipeline, rather than stopping after one package per interaction. The pipeline must build every package selected by the frozen BareLinux profile, run package-level checks, integrate the immutable system, assemble the ISO, and boot-test it.

## Why the build is staged

MLFS is a dependency-ordered source build, not a flat list of independent packages. The cross-toolchain must exist before temporary tools; temporary tools must exist before entering the target root; the target root must be complete before kernel, initramfs, and ISO assembly. A single giant job would make failures expensive and difficult to resume. BareLinux will use one independently triggerable GitHub Actions workflow per package or narrowly defined build stage. Each workflow owns its logs, status, retry boundary, and artifact. A dependency graph controls which upstream artifacts must exist before a downstream workflow can run.

## Planned pipeline groups

1. **Source and policy gate**
   - Reconcile the package inventory against the complete MLFS 13.1 book and the BareLinux profile.
   - Pin every source archive and required patch with an independently verified digest or verified upstream signature.
   - Record source URL, version, archive format, digest algorithm/value, license, patch set, and provenance.
   - Reject missing, ambiguous, or mismatched source locks before any build starts.

2. **Cross-toolchain**
   - Binutils Pass 1
   - GCC Pass 1, including pinned GMP, MPFR, and MPC inputs
   - Linux API headers
   - Glibc
   - Libstdc++
   - Validate compiler target, linker emulations, sysroot, headers, libc ABI, and x86_64/i686 multilib outputs before publishing the stage artifact.

3. **Temporary cross tools**
   - Build the MLFS temporary tool set in dependency order.
   - Build Binutils Pass 2 and GCC Pass 2 only after their prerequisites are present.
   - Run executable smoke tests against the target tuple and sysroot.

4. **Isolated target-root bootstrap**
   - Provision a controlled build root; do not treat an ordinary workspace shell as chroot isolation.
   - Build the additional temporary tools inside the target-root environment.
   - Validate mount setup, ownership, device nodes, and cleanup boundaries.

5. **Final base system**
   - Build all selected MLFS final-system packages in dependency order.
   - Run each package's supported test suite or a documented targeted test where the full suite is unavailable.
   - Capture test output, build logs, installed-file manifest, and package provenance.
   - Reject failed tests unless a narrowly scoped, reviewed exception is recorded.

6. **BareLinux integration**
   - Apply the pinned kernel configuration and build the selected kernel.
   - Integrate systemd, Limine, AppArmor policy, MPL, HSR, immutable /usr, writable /etc, /var, /home, and A/B snapshot layout.
   - Validate ABI, dynamic dependencies, service units, boot entries, filesystem layout, and recovery path.

7. **ISO assembly and acceptance**
   - Produce the ISO, checksum, build manifest, source/license inventory, and validation report.
   - Run BIOS and UEFI virtual-machine boot tests.
   - Verify boot reaches the expected system target and that recovery/fallback behavior is functional.
   - Publish a release artifact only after all required checks pass.

## Parallelism and artifact strategy

- Give every package its own workflow file (for example, `build-binutils-pass1.yml`, `build-gcc-pass1.yml`, and `build-glibc.yml`); do not combine unrelated package builds into a matrix or monolithic workflow.
- Trigger a package workflow independently with `workflow_dispatch` and automatically when its own recipe or source lock changes.
- Parallelize only packages whose dependency artifacts are already available and whose build/install roots are isolated.
- Keep toolchain transitions and target-root mutations serialized by explicit prerequisite artifacts and validation gates.
- Use separate CI jobs for independent package groups; pass immutable, checksummed artifacts between jobs.
- Cache only verified source archives and completed stage outputs. Never treat a cache hit as proof of build success.
- Preserve failed-job logs and stage manifests so a retry can resume from the last validated boundary.
- Set disk/time budgets per stage and fail early when capacity is insufficient.

## Required validation layers

- **Source:** digest/signature verification before extraction; safe archive path/link checks.
- **Build:** configure, compile, install, and package-specific tests.
- **ABI:** ELF class, machine, interpreter, symbol versions, library paths, and x86_64/i686 multilib checks.
- **Filesystem:** no writes outside the stage root; no unsafe symlink/path escapes; ownership and permissions reviewed.
- **Integration:** service dependencies, kernel modules, initramfs contents, bootloader config, and recovery paths.
- **Image:** ISO structure, checksum, BIOS boot, UEFI boot, and post-boot smoke tests.

## Current blockers

- The current package inventory is a structural inventory of 83 records, not yet proven complete against the full MLFS book.
- The initial source manifest has only Binutils SHA-256 independently pinned; other source digests remain pending.
- Patch inventory SHA-256 values remain pending.
- Only Binutils Pass 1 currently has a real compile/install/validation implementation and a dedicated package workflow (`.github/workflows/build-binutils-pass1.yml`).
- Secure chroot/build isolation, the remaining MLFS recipes, final-system integration, and ISO boot acceptance remain unimplemented.

These blockers are intentional fail-closed gates. Do not bypass them by trusting an unverified download, substituting host packages, or marking an unbuilt stage complete.

## Reference

The pipeline ordering follows the official [MLFS 13.1 cross-toolchain and temporary-tools part](https://www.linuxfromscratch.org/mlfs/view/stable/part3.html) and the [MLFS 13.1 book index](https://rivendell.linuxfromscratch.org/mlfs/view/stable/index.html).
