<p align="center">
  <img src="assets/brand/barelinux-logo.svg" alt="BareLinux logo: wordmark with white X in a black square" width="720">
</p>

# BareLinux

**Minimal by default. Modular by design.**

BareLinux is an independent, x86_64 Linux distribution designed around an immutable system model and a CLI-only interface.

## Project status

BareLinux is in the early **M1 — Build Foundation** stage. The repository includes a real Binutils Pass 1 build from verified MLFS source, but does not yet produce a complete root filesystem or bootable image.

## Design baseline

- Build instructions: raw Multilib Linux From Scratch (MLFS) 13.1
- Automation: ALFS/jhalfs with a BareLinux MLFS adapter
- Architecture: x86_64 with full i686 multilib
- CPU baseline: x86-64; AVX2 is optional and runtime-aware
- System model: immutable, snapshot-based
- Kernel: CachyOS-derived kernel, built from pinned source
- Init and service manager: systemd
- Bootloader: Limine
- Default filesystem: Btrfs; ZFS is optional
- Package manager: MPL (planned, Rust, CLI-only)
- Privilege manager: HSR (planned, Rust)
- Interface and installer: CLI-only
- Build and CI: GitHub Actions

## Development principles

1. Pin source versions and verify source integrity before building.
2. Preserve raw MLFS instructions, including multilib branches.
3. Keep the build host separate from the target root filesystem.
4. Do not claim a build stage is complete until its output is tested.
5. Reject unverified ABI adaptations and incompatible packages.
6. Keep core-system changes transactional and recoverable.

## Repository layout

- `assets/brand/` — official brand assets
- `config/` — architecture and build configuration
- `sources/manifests/` — pinned upstream source-version manifests
- `scripts/` — build and validation scripts
- `bin/` — BareLinux Factory CLI
- `Makefile` — BLF CLI installation and test targets
- `.github/workflows/` — GitHub Actions workflows
- `docs/` — design and engineering documentation

## Core source-build system

[**BareLinux Core Build System**](docs/BARELINUX-FACTORY.md) is mandatory. It uses raw MLFS 13.1 as the recipe authority and ALFS/jhalfs as the automation engine, connected through a BareLinux adapter. The workspace CLI and real Binutils Pass 1 build stage are implemented; ALFS–MLFS compatibility, the remaining package stages, secure build isolation, and bootable ISO export are still under development.

See the [ALFS + Raw MLFS integration specification](docs/ALFS-MLFS-INTEGRATION.md) for the exact upstream and adapter boundary.

## Current milestone

See [M1 Build Foundation](docs/M1-BUILD-FOUNDATION.md), the [Core Build System specification](docs/BARELINUX-FACTORY.md), and the live [Build Status](docs/BUILD-STATUS.md).
