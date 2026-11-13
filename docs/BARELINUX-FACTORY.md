# BareLinux Core Build System

**Status:** Workspace CLI is implemented. Raw MLFS 13.1 and jhalfs are pinned; jhalfs has successfully generated the MLFS package command scripts. The first package workflow is being migrated to execute the generated ALFS recipe. The complete build engine and bootable ISO exporter remain under development.

BareLinux is built from source using **raw Multilib Linux From Scratch (MLFS) 13.1**. **ALFS/jhalfs** is the automation engine. The official MLFS book remains the authority for package instructions and multilib procedures; BareLinux's adapter connects that raw book to jhalfs without silently converting it to vanilla LFS. This build system is mandatory to BareLinux's engineering architecture.

## Non-negotiable product decision

- **Raw MLFS:** use the official MLFS book source and preserve its multilib instructions.
- **ALFS automation:** use jhalfs to parse book instructions and generate executable recipes/build orchestration, with a BareLinux adapter for MLFS compatibility.
- **No assumed compatibility:** jhalfs does not officially list MLFS as a supported book; the adapter must prove correct parsing and generated output before full builds are enabled.
- **Real source compilation:** compile verified upstream sources in the prescribed dependency order. Never substitute host binaries or fabricate success markers.
- **Reproducibility:** pin book and automation commits, source archives, patches, build options, toolchain, and outputs.
- **Isolation:** builds must run in a dedicated, controlled environment and must never write into the running host's system directories.
- **Independent output:** successful export must produce a standalone target root filesystem and validated bootable ISO.
- **CLI-first:** the complete workflow is terminal-driven; no GUI is required.

See [ALFS + Raw MLFS Integration](ALFS-MLFS-INTEGRATION.md) for upstream source selection, adapter responsibilities, and acceptance gates.

## User-facing workflow

The workspace CLI currently supports project creation, profile validation, status, and a factory shell:

```sh
lfs init MyDistro
lfs MyDistro configure
lfs enter MyDistro
lfs MyDistro build
lfs MyDistro export
```

The CLI is not yet the complete build system. At present, `lfs enter` opens a workspace shell and is **not** a chroot or security boundary. `build` and `export` fail closed until their real engines and acceptance tests are implemented.

## Distro profile

Each project profile is declarative and must define at least:

- distro name, identifier, version, and release metadata;
- `BUILD_SYSTEM=mlfs` and `BUILD_AUTOMATION=alfs`;
- pinned MLFS book commit and jhalfs commit;
- target architecture and CPU baseline;
- libc and toolchain choices;
- kernel source, configuration, and required drivers;
- init system and service configuration;
- package selection and package sources;
- filesystem and storage layout;
- bootloader and BIOS/UEFI support;
- image format and export targets;
- license and source-attribution metadata.

Profiles are parsed as data, never sourced as shell code. Unknown or unsupported values must be rejected before build execution.

## Build architecture

1. **Upstream lock:** fetch official raw MLFS source from the `multilib` branch at pinned commit `3d65852c3f2506a7bd1a0e052d43a5a3499a079f`, and pin jhalfs at `a13fd9828b8c28d02dfde824a441cd7dd3a1643d`. The branch name is retained as provenance; builds use the locked commit.
2. **Adapter validation:** configure jhalfs against the raw MLFS tree; verify MLFS identity, architecture profiles, XML/XSLT handling, and multilib branches. Fail closed on unsupported constructs.
3. **Recipe generation:** generate shell recipes and the dependency graph from the validated book. Audit generated output before execution.
4. **Source lock:** pin every package archive and patch with independently verified integrity values.
5. **Build host validation and isolation:** verify host requirements, then provision a controlled build root with explicit mount, namespace, ownership, and cleanup boundaries. If isolation is unavailable, stop.
6. **Package workflows:** run one GitHub Actions workflow per package/build stage. Consume only validated generated recipes and exact prerequisite artifacts.
7. **Cross-toolchain and temporary tools:** follow the raw MLFS order, including x86_64/i686 multilib stages.
8. **Target system:** compile the final base system in the isolated target root.
9. **BareLinux integration:** apply the approved kernel/configuration, systemd, Limine, immutable filesystem layout, and BareLinux policies.
10. **Image assembly and validation:** generate initramfs, root filesystem image, BIOS/UEFI ISO, checksums, and virtual firmware boot reports.

Every stage must record its inputs, outputs, logs, and checksums. Safe stages should be resumable; failed stages must not be marked complete.

## Source integrity gate

The current source manifest contains five initial toolchain entries, but four SHA-256 values are still unverified. The package inventory is not a complete source lockfile. Source fetching and compilation must remain blocked for any package whose archive or patch lacks an independently verified integrity value. Do not invent checksums or copy a digest from a different archive format.

## Isolation and safety

- Never build into the running host's `/`, `/usr`, or `/etc`.
- Never execute project-controlled scripts as host root.
- Validate archive paths and symlinks before extraction.
- Keep signing keys and credentials out of logs and artifacts.
- Require explicit confirmation before destructive cleanup or overwriting exports.
- Treat `lfs enter` as an ordinary workspace shell until the isolation backend is implemented; never describe it as a secure chroot before then.

## Export acceptance criteria

A successful export must contain:
- standalone root filesystem and boot artifacts;
- bootable ISO and SHA-256 checksum;
- exact distro profile and build manifest;
- source/version/license inventory;
- build logs and validation report;
- successful BIOS and/or UEFI boot tests for every mode claimed by the profile.

An ISO file existing on disk is not proof that it boots.

## First real build stage: Binutils Pass 1

The repository contains `scripts/build-binutils-pass1-alfs.sh` and a dedicated workflow, `.github/workflows/build-binutils-pass1.yml`. It generates the package command from the pinned raw MLFS book using the pinned jhalfs XSLT, verifies the Binutils 2.47 source archive and SHA-256, checks archive paths and links, refuses root execution, requires a workspace owned by the build user, executes the generated MLFS command, installs under the workspace target's `tools` prefix, validates the cross-linker and assembler, and records success only after validation.

Run the first stage with:

```sh
lfs init MyDistro
lfs MyDistro build binutils-pass1
```

This is one bootstrap stage, **not** a complete MLFS build or bootable distro. The source-audit workflow has proven jhalfs XSLT generation against the pinned MLFS book; the package workflow now executes the generated Binutils Pass 1 recipe. GCC Pass 1 is the next dependency stage after the Binutils artifact is validated.

## Current implementation status

Implemented:
- workspace CLI: `lfs init`, `lfs enter`, `lfs doctor`, project status, and profile editing;
- profile validation requiring the MLFS build-system declaration;
- Makefile install/uninstall/test targets;
- CI coverage for the workspace CLI;
- real Binutils Pass 1 compile/install/validation workflow.

Not yet implemented:
- complete jhalfs Makefile orchestration and generated-recipe semantic review;
- successful execution of the ALFS-generated Binutils Pass 1 package workflow;
- secure build isolation / real chroot environment;
- complete verified source and patch lockfile;
- remaining MLFS cross-toolchain and multilib compilation stages;
- temporary-tools and final-system build recipes;
- kernel, initramfs, Limine integration through the factory;
- real ISO export and BIOS/UEFI boot validation.

**No distro can currently be fully built or exported.** The next milestone is to pin the raw MLFS and jhalfs inputs, then implement and test the adapter before scaling out package workflows.
