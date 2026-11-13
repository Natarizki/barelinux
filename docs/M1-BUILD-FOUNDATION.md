# M1 — Build Foundation

## Objective

Establish a controlled, repeatable foundation for building the BareLinux x86_64 system from source.

## Build baseline

BareLinux requires full multilib, so the initial source baseline follows **Multilib Linux From Scratch (MLFS) 13.1**, rather than assuming a single-ABI LFS build is sufficient.

- Official book: https://rivendell.linuxfromscratch.org/mlfs/view/stable/
- Book release: MLFS 13.1
- Target architecture: x86_64 with i686 multilib
- Initial pinned components: Binutils 2.47, GCC 16.2.0, glibc 2.44, Linux 7.1.8, systemd 261.2

The manifest at `sources/manifests/mlfs-13.1-toolchain.tsv` records the initial upstream archive locations and versions. It is a **version manifest, not yet a cryptographic lockfile**.

## Host and target separation

- GitHub Actions `ubuntu-latest` is the initial CI host runner.
- The runner is a build host only; it is not the BareLinux target system.
- The target root filesystem must be assembled from pinned source inputs.
- A pinned build container/tool environment must be selected before compiling target components.

## M1 sequence

1. Validate repository configuration and source manifest.
2. Import and verify official upstream SHA-256 checksums.
3. Establish an isolated MLFS build environment and cross-toolchain.
4. Build the initial userspace and required libraries.
5. Integrate systemd and the selected CachyOS-derived kernel source/configuration.
6. Assemble a minimal root filesystem.
7. Produce a bootable development image with Limine.
8. Boot-test the image in CI where runner capabilities permit.

## Safety and integrity gate

No source archive may be downloaded or compiled until each archive has a verified SHA-256 digest from a trusted upstream checksum source. Do not replace missing digests with guessed values or checksums computed from an untrusted download.

## Completion criteria

M1 is complete only when CI can produce a bootable x86_64 development image and automated tests verify that it boots into the expected CLI environment.

## Current status

The repository currently validates architecture/build configuration and the initial pinned-version manifest. It does not yet compile the toolchain, build a root filesystem, or produce a bootable ISO.
