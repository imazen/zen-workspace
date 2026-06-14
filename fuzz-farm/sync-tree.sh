#!/usr/bin/env bash
# sync-tree.sh — push the buildable workspace tree to a fuzz box. The workstation
# is the source of truth: its committed+working tree always builds, so the boxes
# mirror it (rather than git-cloning 60+ repos and risking path-dep commit skew).
# Run it after provisioning and periodically (cron) to keep boxes on current code.
#
#   sync-tree.sh root@<ip> [root@<ip2> ...]
#
# Additive (no --delete): a crate removed locally just lingers on the box.
# Excludes build output + per-target corpus/artifacts (those live in ~/fuzz-farm
# on the box, outside the tree, so a re-sync never clobbers fuzzing state).
set -euo pipefail
# cron runs with a minimal PATH; s5cmd/hcloud live in ~/.local/bin, cargo in ~/.cargo/bin
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"
# Hosts: explicit args, else auto-resolve every purpose=fuzz box (cron-friendly;
# picks up the ARM box automatically once it joins).
if [ "$#" -ge 1 ]; then HOSTS=("$@"); else
  export HCLOUD_TOKEN="$(grep -E '^api_token=' "$HOME/.config/hetzner/credentials" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' \r')"
  mapfile -t HOSTS < <(hcloud server list -l purpose=fuzz -o noheader -o columns=ipv4 2>/dev/null | sed 's/^/root@/')
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

for HOST in "${HOSTS[@]}"; do
  echo "=== sync -> $HOST ==="
  $SSHC "$HOST" 'mkdir -p ~/work/zen' || { echo "  ssh failed, skipping $HOST"; continue; }
  rsync -az --info=stats1 -e "$SSHC" "${EXCL[@]}" "$SRC_ZEN/" "$HOST:work/zen/"
  for s in "${EXTRA[@]}"; do
    [ -d "$HOME/work/$s" ] || continue
    $SSHC "$HOST" "mkdir -p 'work/$(dirname "$s")'" 2>/dev/null || true   # for sub-path entries
    rsync -az -e "$SSHC" "${EXCL[@]}" "$HOME/work/$s/" "$HOST:work/$s/"
  done
  echo "  tree synced to $HOST"
done
