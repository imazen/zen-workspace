#!/usr/bin/env bash
# bringup-arm.sh — idempotently bring up the ARM fuzz box (cax31) the moment
# Hetzner CAX stock returns. Built for the recurring CAX drought: run it on a
# cron every ~20 min and it no-ops until stock appears, then creates + provisions
# + syncs + starts fuzzing, and disarms its own cron line. Once zen-fuzz-arm is
# up and fuzzing, every later run is a no-op.
#
#   arm the retry:   (crontab -l 2>/dev/null; echo "*/20 * * * * $PWD/bringup-arm.sh >> /tmp/fuzz-arm-bringup.log 2>&1") | crontab -
#   disarm:          crontab -l | grep -v bringup-arm.sh | crontab -
set -uo pipefail
# cron runs with a minimal PATH; s5cmd/hcloud live in ~/.local/bin, cargo in ~/.cargo/bin
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY="${FUZZ_SSH_KEY:-$HOME/.ssh/zen-arm-dev}"
export HCLOUD_TOKEN="$(grep -E '^api_token=' "$HOME/.config/hetzner/credentials" | head -1 | cut -d= -f2- | tr -d ' \r')"
SSHO="-i $KEY -o ConnectTimeout=12 -o StrictHostKeyChecking=accept-new"
ip(){ hcloud server ip zen-fuzz-arm 2>/dev/null; }
disarm(){ crontab -l 2>/dev/null | grep -v 'bringup-arm.sh' | crontab - 2>/dev/null || true; }
stamp(){ date -u +%FT%TZ; }

# Already up + fuzzing? done — disarm the retry cron.
a="$(ip)"
if [ -n "$a" ] && ssh $SSHO "root@$a" 'systemctl is-active zen-fuzz' 2>/dev/null | grep -q '^active'; then
  echo "$(stamp) zen-fuzz-arm already up + fuzzing — disarming"; disarm; exit 0
fi

# Try to create + provision (create is a no-op if the box already exists; this
# also covers the case where it was created but provisioning was interrupted).
if ! "$HERE/launch-boxes.sh" arm; then
  echo "$(stamp) launch-boxes.sh arm returned nonzero"; fi
a="$(ip)"
if [ -z "$a" ]; then echo "$(stamp) still no CAX stock — will retry"; exit 0; fi

echo "$(stamp) zen-fuzz-arm exists at $a — seeding tree + creds + starting"
"$HERE/sync-tree.sh"        "root@$a" || { echo "$(stamp) sync failed; retry next tick"; exit 0; }
"$HERE/refresh-r2-creds.sh" "root@$a" || { echo "$(stamp) cred push failed; retry next tick"; exit 0; }
ssh $SSHO "root@$a" 'systemctl start zen-fuzz' || { echo "$(stamp) start failed; retry next tick"; exit 0; }
echo "$(stamp) zen-fuzz-arm BROUGHT UP + fuzzing — disarming"; disarm
