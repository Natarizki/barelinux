# BareLinux Factory (BLF)

**Status:** Proposed feature; specification baseline only. No implementation or working distro export is claimed.

BareLinux Factory is the official, optional OS-building environment for creating independent Linux distributions from a BareLinux host. It uses a Linux From Scratch (LFS)-based build process and produces a standalone target root filesystem and, when the selected profile supports it, a bootable ISO image.

## Product decision

BLF is part of the official BareLinux project and roadmap, but it is not a mandatory component of the minimal BareLinux installation.

- **Official:** maintained, versioned, documented, and tested by the BareLinux project.
- **Optional:** users may omit it from an installation and install/enable it when needed.
- **Isolated:** builds run in dedicated workspaces and must not modify the running host system.
- **CLI-first:** the complete workflow is available from the terminal; no GUI is required.
- **Independent output:** exported distributions must not depend on the BareLinux host to boot or operate, unless a profile explicitly documents such a dependency.

“Optional core” means optional to install, not unofficial or third-party.

## User-facing command concept

The following is the proposed command interface, not an implemented command set:

```sh
lfs enter
lfs init MyDistro
lfs MyDistro configure
lfs MyDistro build
lfs MyDistro export
```

- `lfs enter` enters the BLF build environment.
- `lfs init <name>` creates a new distro project and isolated workspace.
- `lfs <name> configure` validates and edits the distro profile.
- `lfs <name> build` builds the selected toolchain, base system, kernel, and boot components.
- `lfs <name> export` packages verified build outputs into the selected deliverables.

The CLI syntax may evolve during implementation. Commands must fail clearly when prerequisites, source verification, or required build stages are incomplete.

## Distro profile

Each distro project must define at least:

- distro name, identifier, version, and release metadata;
- target architecture and CPU baseline;
- libc and toolchain choices;
- kernel source, configuration, and required drivers;
- init system and service configuration;
- package selection and package sources;
- filesystem and storage layout;
- bootloader and BIOS/UEFI support;
- image format and export targets;
- license and source-attribution metadata.

Profiles must be declarative, versioned, and validated before building. User-supplied names and configuration values must never be interpolated into shell commands unsafely.

## Build architecture

1. **Factory environment:** reproducible, isolated toolchain/build environment.
2. **Source manager:** pinned source versions, verified cryptographic digests, license records, and patch provenance.
3. **Toolchain stage:** cross-toolchain and target build tools, following the selected LFS build plan.
4. **System stage:** target libraries, utilities, init system, kernel, and selected packages.
5. **Image stage:** initramfs, bootloader configuration, root filesystem image, and ISO assembly.
6. **Validation stage:** structural checks, boot tests, and export manifest generation.

Build stages must be resumable where safe and must record their inputs, outputs, logs, and checksums. Unverified source archives must not be built.

## Isolation and safety requirements

- Never build directly into the running host's `/`, `/usr`, or `/etc`.
- Use a per-project workspace with explicit ownership and cleanup boundaries.
- Do not run arbitrary project scripts as host root.
- Use controlled namespaces, containers, or another documented isolation mechanism; detect unavailable isolation features and fail closed.
- Validate archive paths and symlinks before extraction.
- Keep credentials and signing keys out of build logs and exported artifacts.
- Require explicit confirmation before destructive cleanup or overwriting an existing export.

## Export and acceptance criteria

An export is not considered successful merely because an ISO file exists. A release candidate must include:

- standalone root filesystem and boot artifacts;
- ISO image and SHA-256 checksum;
- distro profile and build manifest;
- source/version/license inventory;
- build logs and validation report;
- successful boot tests for every boot mode the profile claims to support.

A claimed bootable ISO must be tested in virtual firmware (BIOS and/or UEFI as declared by the profile) and checked for reaching the expected system target. Hardware testing is recommended before calling a release production-ready.

## Relationship to BareLinux

BLF is a separate optional subsystem. Its installation, removal, or build failure must not prevent the normal BareLinux host from booting. It may reuse BareLinux tooling and policies, but exported distributions are separate products with their own profiles, versions, validation results, and release artifacts.

## Implementation roadmap

1. Finalize the profile schema and command-line contract.
2. Implement isolated workspace creation and `lfs enter`.
3. Implement source locking, verification, and reproducible toolchain stages.
4. Implement base-system build stages and resumable state tracking.
5. Implement kernel, initramfs, and bootloader integration.
6. Implement ISO export and BIOS/UEFI boot validation.
7. Add example distro profiles and end-to-end CI tests.

**Current limitation:** this document records the agreed design direction. BLF is not implemented yet, and no distro can currently be built or exported with these commands.
