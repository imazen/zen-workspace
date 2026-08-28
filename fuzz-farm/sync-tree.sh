#!/usr/bin/env bash
# sync-tree.sh — push the buildable workspace tree to a fuzz box. The workstation
# tree is the base (siblings, path deps — cheaper than git-cloning 60+ repos and
# risking path-dep commit skew), and every crate in crates.list is then OVERLAID
# with its pushed origin/main (or origin/master) so the farm fuzzes what is
# committed upstream, never a checkout nobody has pulled for a week. Run it after
# provisioning and periodically (cron) to keep boxes on current code.
#
#   sync-tree.sh root@<ip> [root@<ip2> ...]
#
# Additive (no --delete): a crate removed locally just lingers on the box.
# Excludes build output + per-target corpus/artifacts (those live in ~/fuzz-farm
# on the box, outside the tree, so a re-sync never clobbers fuzzing state).
set -euo pipefail
# cron runs with a minimal PATH; s5cmd/hcloud live in ~/.local/bin, cargo in ~/.cargo/bin
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$HOME/.cargo/bin:/usr/local/bin:$PATH"
# Hosts: explicit args, else auto-resolve every fuzz=yes box (cron-friendly;
# picks up the ARM box automatically once it joins). fuzz=yes is the farm-
# membership label (separate from purpose=fuzz, so the shared zen-arm-dev dev box
# can be a member without being a deletable dedicated box).
if [ "$#" -ge 1 ]; then HOSTS=("$@"); else
  export HCLOUD_TOKEN="$(grep -E '^api_token=' "$HOME/.config/hetzner/credentials" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' \r')"
  mapfile -t HOSTS < <(hcloud server list -l fuzz=yes -o noheader -o columns=ipv4 2>/dev/null | sed 's/^/root@/')
fi
[ "${#HOSTS[@]}" -ge 1 ] || { echo "no fuzz boxes found (pass root@<ip> or check hcloud)" >&2; exit 0; }
KEY="${FUZZ_SSH_KEY:-$HOME/.ssh/zen-arm-dev}"
SRC_ZEN="${ZEN_SRC:-$HOME/work/zen}"
# ~/work siblings the path-dep graph reaches. codec-corpus is a 20 GB image
# corpus — ship ONLY its crate/ source (zencodecs fuzz path-deps it; target/ is
# excluded so this is small). Entries may be sub-paths; structure is preserved.
EXTRA=(${FUZZ_EXTRA_REPOS:-archmage magetypes codec-corpus/crate})
SSHC="ssh -i $KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20"

# Keep .git (some build.rs read the commit hash) but drop the huge / irrelevant.
# A fuzz box only needs SOURCE to build. Drop build output, scratch/retired
# trees, big data, and prebuilt binaries — but keep .git (some build.rs read the
# commit) and small benchmarks/*.bin (some libs include_bytes! picker models).
EXCL=(--exclude 'target/' --exclude '.jj/' --exclude 'node_modules/'
      --exclude '.venv/' --exclude 'venv/'
      --exclude 'fuzz/target/' --exclude 'fuzz/corpus/' --exclude 'fuzz/artifacts/'
      --exclude '.workongoing' --exclude '.claude/'
      --exclude '/_*' --exclude '/retired/' --exclude '/gen-clothing/'
      --exclude '/zenmetrics-refs/' --exclude 'zenmetrics/scripts/'
      --exclude '*--*/' --exclude '*-perm-corpus/' --exclude '*-head-test/'
      --exclude 'naga-metal-msl-repro/'
      --exclude '*.parquet' --exclude '*.tsv' --exclude '*.zip'
      --exclude 'perf.data' --exclude 'perf.data.old'
      --exclude 'zen-sweep-worker' --exclude 'zen-metrics' --exclude 'vastai-fleet'
      --exclude '*-runner-bin' --exclude 'zen-metrics-bin')

CRATES_LIST="${CRATES_LIST:-$HOME/work/zenfuzz-farm/crates.list}"
# Overlay every crates.list crate with its COMMITTED source from the repo's
# default remote branch, so the boxes fuzz what is pushed — never the
# workstation's working tree. Until 2026-08-28 only the fuzz/ harness was
# overlaid: the crate SOURCE was whatever the workstation checkout held, and a
# checkout nobody had pulled for a week made the farm re-find bugs fixed days
# earlier on origin (aom-decoder-rs#12/#13 and zenextras#17–#20 were "RECURRED"
# filings against exactly such stale trees). The export is rsync'd with --delete
# so files removed upstream disappear too; the box's .git (build.rs commit
# hashes) and its gitignored fuzz/{target,corpus,artifacts} + target/ are left
# alone. A repo without origin/main|master, or one whose archive fails, keeps
# the rsync'd working tree and says so.
EXPORT="${FUZZ_EXPORT_DIR:-$HOME/tmp/fuzz-farm-export}"
canon_ref() { # <repo-root> -> origin/main | origin/master | ""
  local root="$1"
  git -C "$root" fetch origin -q 2>/dev/null || true
  if git -C "$root" rev-parse -q --verify origin/main >/dev/null 2>&1; then echo origin/main
  elif git -C "$root" rev-parse -q --verify origin/master >/dev/null 2>&1; then echo origin/master
  fi
}
overlay_canonical_crates() { # <host>
  local host="$1" rel root rrel sub ref dest depth
  [ -f "$CRATES_LIST" ] || return 0
  local -A seen=()
  while IFS= read -r rel; do
    rel="${rel%%#*}"; rel="$(printf '%s' "$rel" | tr -d '[:space:]')"; [ -n "$rel" ] || continue
    [ -d "$SRC_ZEN/$rel" ] || continue
    root="$(git -C "$SRC_ZEN/$rel" rev-parse --show-toplevel 2>/dev/null)" || continue
    rrel="${root#$HOME/work/}"                              # repo path under ~/work, e.g. zen/zenjpeg
    sub="${SRC_ZEN}/${rel}"; sub="${sub#"$root"/}"          # crate path within repo
    [ "$sub" = "$SRC_ZEN/$rel" ] && sub=""                  # crate == repo root
    [ -n "${seen[$root|$sub]+x}" ] && continue; seen[$root|$sub]=1
    ref="$(canon_ref "$root")"
    [ -n "$ref" ] || { echo "  !! $rrel: no origin/main or origin/master — left as the working tree"; continue; }
    dest="$EXPORT/$rrel${sub:+/$sub}"
    rm -rf "$dest"; mkdir -p "$dest"
    if [ -n "$sub" ]; then
      depth=$(( $(printf '%s' "$sub" | tr -cd '/' | wc -c) + 1 ))
      git -C "$root" archive "$ref" "$sub" | tar -x --strip-components="$depth" -C "$dest"
    else
      git -C "$root" archive "$ref" | tar -x -C "$dest"
    fi || { echo "  !! $rrel${sub:+/$sub}: git archive $ref failed — left as the working tree"; continue; }
    if rsync -az --delete -e "$SSHC" \
         --exclude 'target/' --exclude 'fuzz/target/' --exclude 'fuzz/corpus/' \
         --exclude 'fuzz/artifacts/' --exclude '.git/' \
         "$dest/" "$host:work/$rrel${sub:+/$sub}/"; then
      echo "  overlaid $rrel${sub:+/$sub} @ $(git -C "$root" rev-parse --short "$ref") ($ref)"
    else
      echo "  !! rsync overlay failed for $rrel${sub:+/$sub} — box keeps the working tree"
    fi
  done < "$CRATES_LIST"
}

for HOST in "${HOSTS[@]}"; do
  echo "=== sync -> $HOST ==="
  $SSHC "$HOST" 'mkdir -p ~/work/zen' || { echo "  ssh failed, skipping $HOST"; continue; }
  rsync -az --info=stats1 -e "$SSHC" "${EXCL[@]}" "$SRC_ZEN/" "$HOST:work/zen/"
  for s in "${EXTRA[@]}"; do
    [ -d "$HOME/work/$s" ] || continue
    $SSHC "$HOST" "mkdir -p 'work/$(dirname "$s")'" 2>/dev/null || true   # for sub-path entries
    rsync -az -e "$SSHC" "${EXCL[@]}" "$HOME/work/$s/" "$HOST:work/$s/"
  done
  overlay_canonical_crates "$HOST"   # every fuzzed crate = its pushed origin/main|master, over any local WIP/staleness
  echo "  tree synced to $HOST"
done
