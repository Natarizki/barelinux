# ALFS + Raw MLFS Integration

**Architecture decision:** BareLinux uses the official ALFS automation engine with the unmodified MLFS book source as its build recipe authority. The MLFS book is not replaced with vanilla LFS, translated into a different recipe set, or silently patched to remove multilib instructions.

## Upstream inputs

- **Book:** MLFS 13.1 stable, x86_64 with i686 multilib.
- **Raw book source:** the official LFS Git repository, checked out on its `multilib` branch as documented by the MLFS download page: `https://git.linuxfromscratch.org/lfs.git`.
- **Automation:** official ALFS implementation, jhalfs, from `https://git.linuxfromscratch.org/jhalfs.git`.
- **Book release reference:** [MLFS 13.1 stable book](https://rivendell.linuxfromscratch.org/mlfs/view/stable/index.html).

The upstream MLFS download instructions currently describe the `multilib` branch as the source checkout. That branch is a moving development reference, so BareLinux must resolve and record an exact Git commit before building. A version label alone is not a reproducible source lock.

## Required adapter boundary

jhalfs is designed around LFS book XML and generates executable build scripts plus a Makefile. BareLinux will use it as an automation engine, while an adapter handles MLFS-specific selection and validation.

The adapter must:

1. Fetch the official MLFS raw Git source and check out an explicitly pinned commit.
2. Verify that the checked-out book metadata and package instructions correspond to the approved MLFS 13.1 baseline.
3. Preserve MLFS multilib XML, XSLT profiles, architecture conditionals, and package instructions without rewriting them into vanilla LFS.
4. Configure jhalfs to consume that local MLFS book tree. If jhalfs assumes a fixed book path, apply a small, separately maintained adapter patch/configuration rather than modifying the MLFS source.
5. Generate scripts and the build graph, then audit the generated output for expected x86_64/i686 stages and required MLFS multilib branches.
6. Stop on unknown XML constructs, missing recipes, unsupported chapter mappings, or any mismatch between the pinned book and generated scripts.
7. Emit a machine-readable build plan and provenance manifest before package workflows execute.

**Compatibility is not assumed.** Official jhalfs documentation describes LFS and BLFS automation; MLFS is not listed as a supported book. The integration must prove that jhalfs can correctly process the raw MLFS tree. If it cannot, BareLinux must extend the adapter or jhalfs integration without dropping MLFS instructions.

## GitHub Actions model

- Keep one independently triggerable workflow per package/build stage.
- A separate validation workflow checks the pinned raw book, jhalfs revision, adapter, generated recipe scripts, and dependency graph.
- Package workflows consume only validated generated recipes and verified source locks.
- Each workflow publishes a checksummed artifact containing its output, build manifest, and logs.
- Downstream workflows require the exact prerequisite artifact identities; no package workflow may silently rebuild or substitute prerequisites.
- The final rootfs and ISO workflows run only after all required MLFS stages and BareLinux integration stages pass.

ALFS may generate the orchestration Makefile, but it does not replace the package-specific GitHub Actions boundaries requested for BareLinux.

## Important distinction

Raw MLFS is the authority for the base system's build instructions. jhalfs is the mechanism used to interpret and automate those instructions. BareLinux-specific integration (immutable filesystem layout, kernel policy, Limine configuration, MPL, HSR, initramfs, and ISO assembly) remains a separate, explicit layer.

GLFS is not part of the base build path. It may be considered later as an optional gaming-software extension after the base MLFS system is complete.

## Acceptance gates

The ALFS–MLFS integration is not considered complete until CI demonstrates all of the following:

- exact upstream commits are pinned and recorded;
- MLFS 13.1 identity is verified against the pinned raw source;
- jhalfs parses the raw MLFS tree without silently falling back to vanilla LFS;
- generated commands preserve the expected MLFS multilib branches;
- the generated dependency graph matches the MLFS book's package order;
- a representative early-stage package can be built through the generated recipe and validated;
- a deliberately unsupported or altered book input fails closed.

Until those gates pass, the existing Binutils Pass 1 workflow remains the only proven package build. It must not be described as proof that the full ALFS–MLFS integration works.
