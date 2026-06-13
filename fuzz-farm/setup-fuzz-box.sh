#!/usr/bin/env bash
# setup-fuzz-box.sh — provision a fresh Hetzner box into a zen fuzz worker.
# Run as ROOT over ssh:  ssh root@<ip> 'bash -s' < setup-fuzz-box.sh
# (launch-boxes.sh scp's this + fuzz-rotate.sh + zen-fuzz.service to
#  ~/fuzz-farm-src/ first, then pipes this script in.)
#
# Installs: apt build deps + rustup (stable+nightly, cargo-fuzz needs nightly) +
# cargo-fuzz + s5cmd, then the rotate script + systemd unit (enabled, NOT
# started — start after the tree is synced and R2 creds are pushed). Idempotent.
set -euo pipefail
log(){ printf '\n=== %s ===\n' "$*"; }
SRC="${SRC:-$HOME/fuzz-farm-src}"
ARCH_DEB="$(dpkg --print-architecture)"   # arm64 | amd64

log "apt build deps ($ARCH_DEB)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# Pure-Rust codecs mostly, but jpegli-cpp wants cmake+c++, dav1d/rav1e want nasm,
# and clang/lld speed linking. ssl/zlib cover the few crates that link system libs.
apt-get install -y --no-install-recommends \
  build-essential clang lld cmake ninja-build nasm yasm pkg-config \
  git curl ca-certificates python3 jq \
  libssl-dev zlib1g-dev

log "rustup + stable + nightly"
if ! command -v rustup >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain stable --profile minimal
fi
. "$HOME/.cargo/env"
rustup toolchain install nightly --profile minimal
rustup component add --toolchain nightly llvm-tools-preview rust-src || true

log "cargo-fuzz"
command -v cargo-fuzz >/dev/null 2>&1 || cargo install cargo-fuzz --locked

log "s5cmd (R2 client)"
if ! command -v s5cmd >/dev/null 2>&1; then
  case "$ARCH_DEB" in arm64) S5A=Linux-arm64;; *) S5A=Linux-64bit;; esac
  V="$(curl -fsSL https://api.github.com/repos/peak/s5cmd/releases/latest | jq -r .tag_name | tr -d v)"
  TMP="$(mktemp -d)"
  curl -fsSL "https://github.com/peak/s5cmd/releases/download/v${V}/s5cmd_${V}_${S5A}.tar.gz" -o "$TMP/s.tgz"
  tar -xzf "$TMP/s.tgz" -C "$TMP" s5cmd && install -m755 "$TMP/s5cmd" /usr/local/bin/s5cmd
  rm -rf "$TMP"
fi

log "install rotate script + systemd unit"
mkdir -p "$HOME/fuzz-farm/bin" "$HOME/.config/zenfuzz"
install -m755 "$SRC/fuzz-rotate.sh"   "$HOME/fuzz-farm/bin/fuzz-rotate.sh"
install -m644 "$SRC/crates.list"      "$HOME/fuzz-farm/crates.list"
install -m644 "$SRC/zen-fuzz.service" /etc/systemd/system/zen-fuzz.service
systemctl daemon-reload
systemctl enable zen-fuzz.service

echo
echo "=== setup-fuzz-box DONE on $(hostname) ($ARCH_DEB) ==="
rustc +nightly --version 2>/dev/null || true
cargo +nightly fuzz --version 2>/dev/null || true
s5cmd version 2>/dev/null || true
echo "NEXT (from workstation): sync-tree.sh + refresh-r2-creds.sh, then: systemctl start zen-fuzz"
