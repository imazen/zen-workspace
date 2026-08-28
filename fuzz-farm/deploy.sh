#!/usr/bin/env bash
# deploy.sh — one-command, VERSIONED redeploy of the fuzz-farm.
#
# Deploys exactly what's committed on imazen/zen-workspace `main` (or a given
# ref) to (a) the ops dir ~/work/zenfuzz-farm where the workstation crons run,
# and (b) every running purpose=fuzz box, then restarts each box's fuzzer.
# Stamps the deployed commit in DEPLOYED_VERSION on both sides so you can always
# see what's live. Idempotent; safe to re-run.
#
#   deploy.sh            # deploy origin/main (the usual case)
#   deploy.sh <git-ref>  # deploy a specific commit / branch / tag
#
# Why this exists: the running copy + boxes must track the committed source, but
# the primary zen-workspace checkout can't be `cp`'d from (it may hold unrelated
# WIP), so we extract the chosen ref with `git archive` — no checkout needed.
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$HOME/.cargo/bin:/usr/local/bin:$PATH"
REPO="${ZEN_WORKSPACE:-$HOME/work/zen-workspace}"
OPS="${ZENFUZZ_OPS:-$HOME/work/zenfuzz-farm}"
KEY="${FUZZ_SSH_KEY:-$HOME/.ssh/zen-arm-dev}"
REF="${1:-origin/main}"

git -C "$REPO" fetch origin main -q 2>/dev/null || true
COMMIT="$(git -C "$REPO" rev-parse --short "$REF")"
STAMP="$COMMIT  $(date -u +%FT%TZ)  ($REF)"
echo "=== deploying fuzz-farm @ $COMMIT ($REF) ==="

# 1. ops dir (the running copy — crons exec from here). Extract the ref, don't checkout.
mkdir -p "$OPS"
git -C "$REPO" archive "$REF" fuzz-farm | tar -x --strip-components=1 -C "$OPS"
chmod +x "$OPS"/*.sh
printf '%s\n' "$STAMP" > "$OPS/DEPLOYED_VERSION"
echo "ops dir updated: $OPS"

# 2. every running purpose=fuzz box: push the box-runtime files + restart.
export HCLOUD_TOKEN="$(grep -E '^api_token=' "$HOME/.config/hetzner/credentials" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' \r')"
mapfile -t IPS < <(hcloud server list -l fuzz=yes -o noheader -o columns=ipv4 2>/dev/null)
if [ "${#IPS[@]}" -eq 0 ]; then
  echo "no purpose=fuzz boxes running — ops dir updated; new boxes pick it up on launch."; exit 0
fi
for ip in "${IPS[@]}"; do
  echo "--- $ip ---"
  if ! ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 "root@$ip" 'mkdir -p ~/fuzz-farm/bin ~/fuzz-farm-src'; then
    echo "  unreachable, skipping"; continue
  fi
  scp -q -i "$KEY" "$OPS/fuzz-rotate.sh" "$OPS/crates.list" "$OPS/zen-fuzz.service" "root@$ip:fuzz-farm-src/"
  ssh -i "$KEY" "root@$ip" "
    install -m755 ~/fuzz-farm-src/fuzz-rotate.sh   ~/fuzz-farm/bin/fuzz-rotate.sh
    install -m644 ~/fuzz-farm-src/crates.list      ~/fuzz-farm/crates.list
    install -m644 ~/fuzz-farm-src/zen-fuzz.service /etc/systemd/system/zen-fuzz.service
    printf '%s\n' '$STAMP' > ~/fuzz-farm/DEPLOYED_VERSION
    systemctl daemon-reload && systemctl restart zen-fuzz && sleep 2
    echo \"  zen-fuzz \$(systemctl is-active zen-fuzz) @ $COMMIT\"
  "
done
echo "=== deployed @ $COMMIT to ${#IPS[@]} box(es) + ops dir ==="
