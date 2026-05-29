# Local distro inventory (lilith box, 2026-05-28)

Source: WSL2 Ubuntu 22.04 jammy, x86_64. Used as the parity reference
for the Oracle ARM box (`~/work/zen/ORACLE_ARM_BOX.md`).

## Toolchains
- **Rust 1.95** stable + nightly (default stable), many archived toolchains kept
- **Node v24.12** via nvm
- **Go** (system)
- **Python 3** + uv + pip3

## Cargo-installed binaries (full list, ~/.cargo/bin)
bindgen-cli, butteraugli-cli, c2rust, cargo-asm, cargo-audit, cargo-binstall,
cargo-bloat, cargo-copter, cargo-crap, cargo-crev, cargo-deny, cargo-depsize,
cargo-disasm, cargo-download, cargo-edit, cargo-expand, cargo-export,
cargo-fuzz, cargo-geiger, cargo-hack, cargo-llvm-cov, cargo-llvm-lines,
cargo-msrv, cargo-nextest, cargo-outdated, cargo-override, cargo-public-api,
cargo-read, cargo-scan, cargo-semver-checks, cargo-show-asm, cargo-superwork,
cargo-sweep, cargo-tarpaulin, cargo-trust, critcmp, cross, crusader, dssim,
durs, flamegraph, frum, git-delta, hyperfine, img2svg, inferno, jj-cli, just,
jxl-inspect, jxl-oxide-cli, mdbook, mdbook-mermaid, obsidian-export, oxipng,
pdf_oxide, resvg, ripgrep, samply, summarize, tract, trunk, twiggy, vtracer,
wasm-bindgen-cli, wasm-pack, wasm-tools, yazi-build, yazi-cli, yazi-fm, zellij

## Cloud CLIs
- aws (~/.local/bin), oci (~/bin), doctl (snap), az (apt), kubectl, s5cmd, rclone
- **Missing locally** (would be nice to also install on ARM): hcloud, gcloud, helm

## Profiling/perf
- valgrind, heaptrack, hyperfine, flamegraph, inferno, samply, perf

## APT deltas worth replicating (excluded: all CUDA — no GPU on A1.Flex)
- build-essential, clang, lld, cmake, ninja-build, meson, pkg-config, mold
- ripgrep, fd-find, fzf, bat, git-delta, tmux, htop, jq, gh
- valgrind, heaptrack, hyperfine
- libssl-dev, libsqlite3-dev, libpq-dev, libffi-dev, libjpeg-dev, libpng-dev,
  libtiff-dev, libwebp-dev, libudev-dev, libnuma-dev, libzstd-dev, libbz2-dev,
  libdeflate-dev, liblzma-dev, libtbb-dev, zlib1g-dev
- ghostscript, protobuf-compiler
- linux-tools-generic (perf)

## Node global packages
- @anthropic-ai/claude-code (Claude Code CLI itself)
- @mermaid-js/mermaid-cli, svgo

## Setup mechanism (2026-05-28+)

The canonical declarative inventory for new boxes is
**`~/work/zen/scripts/.mise.toml`**, applied via
[mise](https://mise.jdx.dev/). The local box predates this; mise is not
yet bootstrapped here. For a fresh deploy (arm-zen, future replacements):

1. APT layer: system libs / dev headers from `setup-arm-box.sh` apt-install.
2. mise layer: `curl https://mise.run | sh` + `mise install` against the
   shared `.mise.toml` — covers rust, node, python, jj, just, samply,
   ripgrep/fd/bat/fzf, hyperfine, ~25 cargo-* subcommands, mdbook,
   wasm-tools, oxipng, gh.
3. Tail: hcloud, s5cmd, rclone, oci-via-pipx, Claude CLI via nvm, plus
   the from-source cargo crates (dssim, butteraugli-cli, git-delta).

This file (`LOCAL_DISTRO_INVENTORY.md`) is the **descriptive parity
reference** — what's installed on the local lilith box. The
**prescriptive** source of truth is `.mise.toml`. When a new tool lands
locally and we want it on dev boxes too, add it to `.mise.toml`.
