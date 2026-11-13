# BareLinux Core LFS Build System

**Status:** Core architecture decision approved. Workspace CLI is implemented; the real MLFS build engine and bootable ISO exporter are under development.

BareLinux is built from source using **Multilib Linux From Scratch (MLFS) 13.1**. The source-build system is a mandatory part of BareLinux's engineering architecture, not an optional add-on. The resulting installed BareLinux system does not need to run the factory continuously; the build capability is core to the project and its official build pipeline.

## Non-negotiable product decision

- **Mandatory build foundation:** BareLinux's official system build follows MLFS 13.1, adapted and documented for BareLinux.
- **Real source compilation:** the build engine must compile verified upstream sources in the prescribed dependency order. It must not substitute host binaries or fabricate success markers.
- **Reproducibility:** every source, patch, build option, toolchain, and output must be recorded and integrity-checked.
- **Isolation:** builds must run in a dedicated, controlled environment and must never write into the running host's system directories.
- **Independent output:** a successful export must produce a standalone target root filesystem and validated bootable ISO.
- **CLI-first:** the complete workflow is terminal-driven; no GUI is required.

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
- `BUILD_SYSTEM=mlfs` (mandatory);
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

## Real build architecture

1. **Build host validation:** verify Linux host requirements, PTY, compilers, multilib execution, disk, memory, and required utilities.
2. **Isolation backend:** provision a controlled build root with explicit mount, namespace, ownership, and cleanup boundaries. If isolation is unavailable, stop.
3. **Source lock manager:** use the complete MLFS 13.1 archive and patch lockfile; verify SHA-256/signatures before extraction.
4. **Cross-toolchain:** build Binutils, GCC, Linux API headers, glibc, and libstdc++ in the exact MLFS order, including x86_64/i686 multilib requirements.
5. **Temporary tools:** compile the MLFS temporary toolchain stages.
6. **Target system:** enter the isolated target root and compile the final base system in dependency order.
7. **BareLinux integration:** apply the approved kernel/configuration, systemd, Limine, immutable filesystem layout, and BareLinux policies.
8. **Image assembly:** generate initramfs, root filesystem image, and BIOS/UEFI ISO.
9. **Validation:** run structural checks and virtual firmware boot tests before export is accepted.

Every stage must record its inputs, outputs, logs, and checksums. Safe stages should be resumable; failed stages must not be marked complete.

## Source integrity gate

The current source manifest contains five initial toolchain entries, but four SHA-256 values are still unverified. The package inventory is not a complete source lockfile. Therefore source fetching and compilation must remain blocked until every required archive and patch has an independently verified integrity value. Do not invent checksums or copy a digest from a different archive format.

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

## Current implementation status

Implemented:
- workspace CLI: `lfs init`, `lfs enter`, `lfs doctor`, project status, and profile editing;
- profile validation requiring the MLFS build-system declaration;
- Makefile install/uninstall/test targets;
- CI coverage for the workspace CLI.

Not yet implemented:
- secure build isolation / real chroot environment;
- complete verified source and patch lockfile;
- MLFS cross-toolchain and multilib compilation stages;
- temporary-tools and final-system build recipes;
- kernel, initramfs, Limine integration through the factory;
- real ISO export and BIOS/UEFI boot validation.

**No distro can currently be fully built or exported.** The next engineering milestones are the isolation backend and complete source lock, followed by the first actual MLFS cross-toolchain build. The CI must never call the project buildable until that pipeline has passed end-to-end tests.
