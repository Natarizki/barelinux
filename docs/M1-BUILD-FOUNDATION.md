# M1 — Build Foundation

## Objective

Establish a controlled, repeatable foundation for building the BareLinux x86_64 system from source.

## Build baseline

BareLinux requires full multilib, so the initial source baseline follows **Multilib Linux From Scratch (MLFS) 13.1**.

- Official book: https://rivendell.linuxfromscratch.org/mlfs/view/stable/
- Target: x86_64 with i686 multilib
- CPU baseline: x86-64; AVX2 remains optional
- Initial pinned components: Binutils 2.47, GCC 16.2.0, glibc 2.44, Linux 7.1.8, systemd 261.2

The source manifest records versions and upstream archive locations. A source is not eligible for a build until its trusted SHA-256 digest is present and verified.

## Cross-toolchain policy

- Build host and target system are separate.
- The initial host is GitHub Actions `ubuntu-latest`; it is not a BareLinux target.
- Primary ABI: x86_64.
- Secondary ABI: i686.
- Full multilib is mandatory; a 64-bit-only compiler is not an acceptable milestone.
- Toolchain triplets, compiler flags, library directories, and bootstrap order must follow MLFS 13.1 rather than locally invented values.
- Sysroot and cross-tools live under the ignored `work/` directory.
- The build must fail closed if required source digests are absent.

The policy is recorded in `config/toolchain.conf` and checked by `scripts/check-toolchain.sh`. These checks do not claim that a compiler or sysroot exists.

## M1 sequence

1. Validate architecture, build, and toolchain policy.
2. Import trusted source checksums and verify all source archives.
3. Prepare the isolated MLFS build environment.
4. Build the cross-toolchain and both ABI support paths.
5. Build the initial userspace and required libraries.
6. Integrate systemd and the selected CachyOS-derived kernel source/configuration.
7. Assemble a minimal root filesystem.
8. Produce a bootable development ISO with Limine.
9. Boot-test the image in CI where runner capabilities permit.

## Integrity gate

No source archive may be compiled until its SHA-256 digest is independently verified against a trusted upstream source. Missing or malformed digests block the download stage. Never substitute a guessed digest.

## Completion criteria

M1 is complete only when CI can produce a bootable x86_64 development image and automated tests verify that it boots into the expected CLI environment with the intended multilib layout.

## Current status

The repository contains configuration, manifest validation, a fail-closed source fetcher, and policy checks for the future cross-toolchain. It does not yet contain a compiled toolchain, sysroot, root filesystem, kernel, or bootable ISO.
