# BareLinux

**Minimal by default. Modular by design.**

BareLinux is an independent, x86_64, CLI-only Linux distribution built around an immutable system model.

## Project status

BareLinux is in the early **M1 — Build Foundation** stage. The repository currently contains project configuration and foundation checks; it does not yet produce a bootable image.

## Design baseline

- Base system: Linux From Scratch (LFS)
- Architecture: x86_64
- CPU baseline: x86-64; AVX2 is optional
- System model: immutable, snapshot-based
- Kernel: CachyOS-derived kernel, built from pinned source
- Init and service manager: systemd
- Bootloader: Limine
- Default filesystem: Btrfs
- Package manager: MPL (planned, Rust, CLI-only)
- Privilege manager: HSR (planned, Rust)
- Interface: CLI-only
- Build and CI: GitHub Actions

## Development principles

1. Pin source versions and verify source checksums/signatures before building.
2. Keep the build host separate from the target root filesystem.
3. Do not claim a build stage is complete until its output is tested.
4. Reject unverified ABI adaptations and incompatible packages.
5. Keep core-system changes transactional and recoverable.

## Repository layout

- `config/` — architecture and build configuration
- `sources/manifests/` — pinned source manifests (to be added)
- `scripts/` — build and validation scripts
- `.github/workflows/` — GitHub Actions workflows
- `docs/` — design and engineering documentation

## Current milestone

See [M1 Build Foundation](docs/M1-BUILD-FOUNDATION.md).
