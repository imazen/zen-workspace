#!/usr/bin/env bash
# Additive sync of all fuzz state (corpus, artifacts, regression seeds)
# between local repos and /mnt/v/fuzzes/<repo>/.
#
# Usage:
#   fuzz-sync.sh              # sync all repos (default: push)
#   fuzz-sync.sh push         # local → /mnt/v/fuzzes/ (additive, no --delete)
#   fuzz-sync.sh pull         # /mnt/v/fuzzes/ → local (additive, no --delete)
#   fuzz-sync.sh status       # show what's on disk vs block storage
#   fuzz-sync.sh push zenwebp # sync one repo only
#
# Additive means files are only ever added, never removed. Safe to run
# at any time without losing data on either side.
#
# Block storage layout:
#   /mnt/v/fuzzes/<repo>/artifacts/   — crash/oom/leak/slow-unit files
#   /mnt/v/fuzzes/<repo>/corpus/      — libFuzzer accumulated corpus
#   /mnt/v/fuzzes/<repo>/regression/  — committed regression seeds (mirror)
#   /mnt/v/fuzzes/<repo>/*.dict       — format dictionaries

set -euo pipefail

FUZZ_STORE="/mnt/v/fuzzes"
ZEN_ROOT="${ZEN_ROOT:-$HOME/work/zen}"

# Map of repo short names → local fuzz dir paths.
# Add new repos here as they gain fuzz targets.
declare -A REPOS=(
  [zenwebp]="$ZEN_ROOT/zenwebp/fuzz"
  [zenjpeg]="$ZEN_ROOT/zenjpeg/zenjpeg/fuzz"
  [zenpng]="$ZEN_ROOT/zenpng/fuzz"
  [zengif]="$ZEN_ROOT/zengif/fuzz"
  [zentiff]="$ZEN_ROOT/zentiff/fuzz"
  [zenjxl-decoder]="$ZEN_ROOT/zenjxl-decoder/fuzz"
  [zenavif]="$ZEN_ROOT/zenavif/fuzz"
  [zenavif-parse]="$ZEN_ROOT/zenavif-parse/fuzz"
  [zenflate]="$ZEN_ROOT/zenflate/fuzz"
  [zenpipe]="$ZEN_ROOT/zenpipe/fuzz"
  [zencodecs]="$ZEN_ROOT/zencodecs/fuzz"
  [zenpdf]="$ZEN_ROOT/zenpdf/fuzz"
  [zenraw]="$ZEN_ROOT/zenraw/fuzz"
  [weezl]="$ZEN_ROOT/zenlzw/fuzz"
  [zenbitmaps]="$ZEN_ROOT/zenbitmaps/fuzz"
  [zensvg]="$ZEN_ROOT/zensvg/fuzz"
  [zenzstd]="$ZEN_ROOT/zenzstd/fuzz"
  [aom-decoder-rs]="$ZEN_ROOT/aom-decoder-rs/fuzz"
  [fax]="$ZEN_ROOT/fax/fuzz"
  [heic]="$ZEN_ROOT/heic/fuzz"
  [imageflow]="$ZEN_ROOT/imageflow/fuzz"
  [image-tiff]="$ZEN_ROOT/image-tiff/fuzz"
  [rav1d-safe]="$ZEN_ROOT/rav1d-safe/fuzz"
  [ultrahdr]="$ZEN_ROOT/ultrahdr/fuzz"
  [zenrav1e]="$ZEN_ROOT/zenrav1e/fuzz"
)

SUBDIRS=(artifacts corpus regression)

sync_push() {
  local name="$1" local_fuzz="$2"
  local dst="$FUZZ_STORE/$name"
  mkdir -p "$dst"
  for sub in "${SUBDIRS[@]}"; do
    [ -d "$local_fuzz/$sub" ] && rsync -a "$local_fuzz/$sub/" "$dst/$sub/"
  done
  # Sync dictionaries
  for f in "$local_fuzz"/*.dict; do
    [ -f "$f" ] && cp -n "$f" "$dst/"
  done
  echo "  push: $name"
}

sync_pull() {
  local name="$1" local_fuzz="$2"
  local src="$FUZZ_STORE/$name"
  [ -d "$src" ] || return 0
  for sub in "${SUBDIRS[@]}"; do
    [ -d "$src/$sub" ] && { mkdir -p "$local_fuzz/$sub"; rsync -a "$src/$sub/" "$local_fuzz/$sub/"; }
  done
  for f in "$src"/*.dict; do
    [ -f "$f" ] && cp -n "$f" "$local_fuzz/"
  done
  echo "  pull: $name"
}

show_status() {
  printf "%-20s %6s %6s %6s   %6s %6s %6s\n" \
    "REPO" "L:art" "L:corp" "L:reg" "R:art" "R:corp" "R:reg"
  printf "%s\n" "--------------------------------------------------------------------"
  for name in $(echo "${!REPOS[@]}" | tr ' ' '\n' | sort); do
    local_fuzz="${REPOS[$name]}"
    remote="$FUZZ_STORE/$name"
    la=0; lc=0; lr=0; ra=0; rc=0; rr=0
    [ -d "$local_fuzz/artifacts" ] && la=$(find "$local_fuzz/artifacts" -type f 2>/dev/null | wc -l)
    [ -d "$local_fuzz/corpus" ]    && lc=$(find "$local_fuzz/corpus"    -type f 2>/dev/null | wc -l)
    [ -d "$local_fuzz/regression" ] && lr=$(find "$local_fuzz/regression" -type f 2>/dev/null | wc -l)
    [ -d "$remote/artifacts" ]  && ra=$(find "$remote/artifacts"  -type f 2>/dev/null | wc -l)
    [ -d "$remote/corpus" ]     && rc=$(find "$remote/corpus"     -type f 2>/dev/null | wc -l)
    [ -d "$remote/regression" ] && rr=$(find "$remote/regression" -type f 2>/dev/null | wc -l)
    printf "%-20s %6d %6d %6d   %6d %6d %6d" "$name" "$la" "$lc" "$lr" "$ra" "$rc" "$rr"
    # Flag orphans: local artifacts not in remote
    if [ "$la" -gt "$ra" ]; then
      printf "  ← %d new local artifacts" $((la - ra))
    fi
    printf "\n"
  done
}

# --- main ---

ACTION="${1:-push}"
FILTER="${2:-}"

if [ "$ACTION" = "status" ]; then
  show_status
  exit 0
fi

if ! mountpoint -q /mnt/v 2>/dev/null; then
  echo "error: /mnt/v is not mounted" >&2
  exit 1
fi

for name in $(echo "${!REPOS[@]}" | tr ' ' '\n' | sort); do
  local_fuzz="${REPOS[$name]}"
  [ -d "$local_fuzz" ] || continue
  [ -n "$FILTER" ] && [ "$name" != "$FILTER" ] && continue

  case "$ACTION" in
    push) sync_push "$name" "$local_fuzz" ;;
    pull) sync_pull "$name" "$local_fuzz" ;;
    *)    echo "usage: $0 {push|pull|status} [repo-name]" >&2; exit 1 ;;
  esac
done

echo "done."
