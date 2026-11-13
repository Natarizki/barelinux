# M1 — Build Foundation

## Objective

Establish a controlled, repeatable foundation for building the BareLinux x86_64 system from Linux From Scratch sources.

## Host and target separation

- GitHub Actions `ubuntu-latest` is the initial CI host runner.
- The runner is a build host only; it is not the BareLinux target system.
- The target root filesystem must be assembled from pinned LFS source inputs.
- A pinned build container/tool environment will be selected before the first full toolchain build.

## M1 sequence

1. Validate repository configuration and build scripts.
2. Define a versioned source manifest with cryptographic checksums.
3. Establish the isolated LFS build environment and cross-toolchain.
4. Build the initial userspace and required libraries.
5. Integrate systemd and the selected kernel source/configuration.
6. Assemble a minimal root filesystem.
7. Produce a bootable development image with Limine.
8. Boot-test the image in CI where runner capabilities permit.

## Completion criteria

M1 is complete only when CI can produce a bootable x86_64 development image and automated tests verify that it boots into the expected CLI environment.

## Current status

The repository currently implements only the initial configuration validator. No toolchain, kernel, root filesystem, or ISO build is claimed to exist yet.
