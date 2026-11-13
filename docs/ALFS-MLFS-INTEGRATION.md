# ALFS + Raw MLFS Integration

**Architecture decision:** BareLinux uses the official ALFS automation engine with the unmodified MLFS book source as its build recipe authority. The MLFS book is not replaced with vanilla LFS, translated into a different recipe set, or silently patched to remove multilib instructions.

## Upstream inputs

- **Book:** MLFS 13.1 stable, x86_64 with i686 multilib.
- **Raw book source:** the official LFS Git repository, checked out on its `multilib` branch as documented by the MLFS download page: `https://git.linuxfromscratch.org/lfs.git`.
- **Automation:** official ALFS implementation, jhalfs, from `https://git.linuxfromscratch.org/jhalfs.git`.
- **Book release reference:** [MLFS 13.1 stable book](https://rivendell.linuxfromscratch.org/mlfs/view/stable/index.html).

The upstream MLFS download instructions describe the `multilib` branch as the source checkout. BareLinux resolved and pinned MLFS 13.1 to commit `3d65852c3f2506a7bd1a0e052d43a5a3499a079f` (commit date 2026-10-26). The jhalfs source is pinned to `a13fd9828b8c28d02dfde824a441cd7dd3a1643d`.

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

The XSLT-generation gate has passed. The Binutils Pass 1 workflow is now configured to execute the generated ALFS recipe; only after that package workflow passes can the first ALFS-driven package build be considered proven. Full Makefile orchestration and all remaining package workflows are still outstanding.


## Confirmed jhalfs adapter surface

The pinned jhalfs revision exposes the required integration points in its own source:

- `Config.in` provides a **Local Copy** book-source mode and a `BOOK` path setting.
- `common/libs/func_book_parser` uses the configured local `BOOK` tree when `WORKING_COPY` is enabled, then profiles `index.xml` and invokes the LFS extraction stylesheet.
- The same configuration still contains legacy `ml_32`, `ml_x32`, and `ml_all` profile choices. MLFS 13.1's current book has moved away from the old `ARCH` rendering parameter and presents 32-bit support as part of the current multilib book. Therefore the adapter tests the raw book with the legacy architecture profile set to `default`, rather than asking jhalfs to filter it using an obsolete profile name.

This is a reason to prefer the local-copy adapter: it prevents jhalfs from fetching a different LFS book or silently substituting a vanilla LFS branch.

The source-audit workflow (run [#2](https://github.com/Natarizki/barelinux/actions/runs/43408490505)) performs the compatibility check: it fetches pinned raw MLFS and jhalfs sources, profiles the MLFS XML as systemd, and runs jhalfs's own LFS extraction XSLT against that profiled book. CI successfully generated **131 package command scripts**, and 35 generated scripts contain recognizable multilib instructions. The artifact preserves the generated command tree for review.

Passing this XSLT test proves only that recipe generation works structurally. It does **not** prove that every generated command is semantically correct, that jhalfs' full Makefile orchestration is safe for BareLinux, or that any package has been compiled. Generated scripts still require review and package-level build tests before they can enter the production pipeline.
