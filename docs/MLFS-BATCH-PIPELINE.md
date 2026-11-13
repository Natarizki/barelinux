# BareLinux Raw MLFS + ALFS Package Pipeline

**Status:** Raw MLFS 13.1 and pinned jhalfs pass CI. The source gate generates jhalfs' own Makefile and dependency graph from the local raw book using the `systemd` and `ml_32` (x86_64 + i686) profile. Binutils Pass 1 has executed through jhalfs' generated Makefile, passed linker/assembler validation, and published a resumable build-root artifact. The first full-book attempts reached `502-gcc-pass1` but failed because `gcc-16.2.0.tar.xz` was missing from the build root's `sources/` directory. Inspection of the uploaded failure artifact confirmed this was a source-staging failure, not a GCC compilation failure. The source gate now enables jhalfs' built-in package retrieval, and the full-book runner verifies the complete source URL inventory and book-provided MD5 checks before running the Makefile. The fix is committed and awaiting a fresh end-to-end CI run; no complete MLFS base system or ISO has been produced yet.

## Goal

Build BareLinux from the official raw MLFS 13.1 instructions using ALFS/jhalfs for recipe generation and automation. The pipeline must preserve MLFS multilib procedures, build every selected package, integrate the immutable system, assemble the ISO, and boot-test it.

## Source of truth and automation

- Raw book: official MLFS 13.1 source tree from the official LFS Git repository's `multilib` branch.
- Automation: official ALFS implementation, jhalfs.
- Adapter: BareLinux-maintained integration that makes jhalfs consume and validate raw MLFS.
- Pinned MLFS commit: `3d65852c3f2506a7bd1a0e052d43a5a3499a079f` (resolved from the official `multilib` branch; MLFS 13.1 release marker verified).
- Pinned jhalfs commit: `a13fd9828b8c28d02dfde824a441cd7dd3a1643d`.
- jhalfs compatibility with MLFS is not assumed. Its generated scripts and dependency graph must pass explicit compatibility tests.

See [ALFS + Raw MLFS Integration](ALFS-MLFS-INTEGRATION.md).

## Why the build is staged

MLFS is a dependency-ordered source build, not a flat list of independent packages. The cross-toolchain must exist before temporary tools; temporary tools must exist before entering the target root; the target root must be complete before kernel, initramfs, and ISO assembly. ALFS can generate the build orchestration, but BareLinux retains one independently triggerable GitHub Actions workflow per package/build stage. Each workflow owns its logs, status, retry boundary, and artifact.

## Planned pipeline groups

1. **Raw book and adapter gate**
   - Pin the MLFS book commit and jhalfs commit.
   - Verify the pinned book corresponds to MLFS 13.1.
   - Run jhalfs against the raw MLFS tree through the BareLinux adapter.
   - Audit generated recipes and dependency graph for expected multilib branches and package order.
   - Fail closed on unsupported XML/XSLT constructs or any fallback to vanilla LFS.
   - **Current result:** CI generated 131 command scripts; 35 generated scripts contain recognizable multilib instructions. jhalfs' source retrieval is now enabled in the build configuration; the full-book runner has a preflight for missing source files and the generated MD5SUMS inventory.

2. **Source and policy gate**
   - Reconcile the package inventory against the complete MLFS 13.1 book and BareLinux profile.
   - Pin every source archive and required patch with an independently verified digest or verified upstream signature.
   - Record source URL, version, archive format, digest, license, patch set, and provenance.
   - Reject missing, ambiguous, or mismatched source locks before any build starts.

3. **Cross-toolchain**
   - Binutils Pass 1
   - GCC Pass 1, including pinned GMP, MPFR, and MPC inputs
   - Linux API headers
   - Glibc
   - Libstdc++
   - Validate compiler target, linker emulations, sysroot, headers, libc ABI, and x86_64/i686 multilib outputs before publishing artifacts.

4. **Temporary cross tools**
   - Build the raw MLFS temporary tool set in dependency order.
   - Build Binutils Pass 2 and GCC Pass 2 only after prerequisites are present.
   - Run executable smoke tests against the target tuple and sysroot.

5. **Isolated target-root bootstrap**
   - Provision a controlled build root; do not treat an ordinary workspace shell as chroot isolation.
   - Build the additional temporary tools inside the target-root environment.
   - Validate mount setup, ownership, device nodes, and cleanup boundaries.

6. **Final base system**
   - Build all selected MLFS final-system packages in dependency order.
   - Run each package's supported test suite or a documented targeted test where the full suite is unavailable.
   - Capture test output, build logs, installed-file manifest, and package provenance.
   - Reject failed tests unless a narrowly scoped, reviewed exception is recorded.

7. **BareLinux integration**
   - Apply the pinned kernel configuration and build the selected kernel.
   - Integrate systemd, Limine, AppArmor policy, MPL, HSR, immutable /usr, writable /etc, /var, /home, and A/B snapshot layout.
   - Validate ABI, dynamic dependencies, service units, boot entries, filesystem layout, and recovery path.

8. **ISO assembly and acceptance**
   - Produce the ISO, checksum, build manifest, source/license inventory, and validation report.
   - Run BIOS and UEFI virtual-machine boot tests.
   - Verify boot reaches the expected system target and recovery/fallback behavior works.
   - Publish a release artifact only after all required checks pass.

## Workflow and artifact strategy

- Give every package its own workflow file (for example, `build-binutils-pass1.yml`, `build-gcc-pass1.yml`, and `build-glibc.yml`); do not combine unrelated package builds into a matrix or monolithic workflow.
- Add a separate workflow for raw-book/jhalfs compatibility validation; it does not replace package workflows.
- Trigger each package workflow independently with `workflow_dispatch` and automatically when its own recipe or source lock changes.
- Package workflows consume only validated generated recipes and exact prerequisite artifacts.
- Parallelize only packages whose dependency artifacts are already available and whose build/install roots are isolated.
- Keep toolchain transitions and target-root mutations serialized by explicit prerequisite artifacts and validation gates.
- Use immutable, checksummed artifacts between workflows.
- Cache only verified source archives and completed stage outputs. Never treat a cache hit as proof of build success.
- Preserve failed-job logs and stage manifests so a retry can resume from the last validated boundary.
- Set disk/time budgets per stage and fail early when capacity is insufficient.

## Required validation layers

- **Book:** exact upstream commits, MLFS 13.1 identity, raw multilib XML/profile preservation.
- **Generated recipes:** jhalfs parsing, command extraction, dependency graph, no silent vanilla-LFS fallback.
- **Source:** digest/signature verification before extraction; safe archive path/link checks.
- **Build:** configure, compile, install, and package-specific tests.
- **ABI:** ELF class, machine, interpreter, symbol versions, library paths, and x86_64/i686 multilib checks.
- **Filesystem:** no writes outside the stage root; no unsafe symlink/path escapes; ownership and permissions reviewed.
- **Integration:** service dependencies, kernel modules, initramfs contents, bootloader config, and recovery paths.
- **Image:** ISO structure, checksum, BIOS boot, UEFI boot, and post-boot smoke tests.

## Current blockers

- Full MLFS book execution and generated-command semantic review are still pending; Binutils Pass 1 is the first successfully executed jhalfs Makefile checkpoint.
- The current package inventory is a structural inventory of 83 records, not yet proven complete against the full MLFS book.
- Only Binutils SHA-256 is independently pinned in the initial toolchain manifest; other source digests remain pending.
- Patch inventory SHA-256 values remain pending.
- Binutils Pass 1 has passed its jhalfs Makefile target, installed linker/assembler checks, and build-root artifact upload (`.github/workflows/build-binutils-pass1.yml`). The automatic continuation uses `.github/workflows/build-mlfs-full.yml` to execute the complete jhalfs Makefile in one job. The standalone GCC checkpoint workflow is manual-only for debugging. The latest full-book failure was traced to the absent GCC source archive; jhalfs source retrieval and an explicit archive/checksum preflight have now been enabled, pending CI verification.
- Secure build isolation, remaining package recipes, final-system integration, and ISO boot acceptance remain unimplemented.

These blockers are intentional fail-closed gates. Do not bypass them by trusting an unverified download, substituting host packages, or marking an unbuilt stage complete.
