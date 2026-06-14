#!/usr/bin/env bash
# launch-boxes.sh — create + provision the two persistent Hetzner fuzz boxes.
#
#   THIS SPENDS MONEY (it is the billable step; run it deliberately):
#     zen-fuzz-arm  cax41  16c/32GB arm64 ~€0.0593/hr  (~€37/mo monthly cap)  [FUZZ_ARM_TYPE]
#     zen-fuzz-x86  cpx42  8c/16GB x86     ~€0.0481/hr  (~€30/mo monthly cap)
#   Labeled purpose=fuzz so jobdash's group=<RUN>-scoped fleet-kill never touches
#   them. Idempotent: skips a box that already exists. Tear down: kill-boxes.sh.
#
#   launch-boxes.sh [arm|x86|both]      (default both)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHICH="${1:-both}"
KEY="${FUZZ_SSH_KEY:-$HOME/.ssh/zen-arm-dev}"
SSHKEY_NAME="${HCLOUD_SSH_KEY:-zen-arm-dev-20260528}"
IMAGE="${FUZZ_IMAGE:-ubuntu-24.04}"
LOCATIONS=(${HCLOUD_LOCATIONS:-fsn1 nbg1 hel1})
export HCLOUD_TOKEN="$(grep -E '^api_token=' "$HOME/.config/hetzner/credentials" | head -1 | cut -d= -f2- | tr -d ' \r')"

CLOUDINIT="$(mktemp)"
cat > "$CLOUDINIT" <<'YAML'
#cloud-config
# Minimal: just the Hetzner-Ubuntu PAM password-aging fix (key-only root logins
# lock out after ~1 day without it). All real provisioning is setup-fuzz-box.sh.
runcmd:
  - chage -d 99999 -E -1 -I -1 -M -1 root || true
  - passwd -u root 2>/dev/null || true
  - touch /var/lib/zen-fuzz-bootstrap-done
YAML

create_box(){ # <name> <type>
  local name="$1" stype="$2" loc
  if hcloud server describe "$name" >/dev/null 2>&1; then
    echo "$name already exists (ip $(hcloud server ip "$name" 2>/dev/null)) — skipping create"; return 0
  fi
  for loc in "${LOCATIONS[@]}"; do
    echo "creating $name ($stype) in $loc ..."
    if hcloud server create --name "$name" --type "$stype" --image "$IMAGE" \
        --location "$loc" --ssh-key "$SSHKEY_NAME" \
        --label purpose=fuzz --label fuzz=yes --label owner=lilith \
        --user-data-from-file "$CLOUDINIT" >/dev/null 2>&1; then
      echo "  $name up in $loc"; return 0
    fi
    echo "  $stype unavailable in $loc, trying next..."
  done
  echo "  FAILED: $stype unavailable in all of: ${LOCATIONS[*]} (Hetzner stock?)" >&2
  return 1
}

provision(){ # <name>
  local name="$1" ip; ip="$(hcloud server ip "$name")"
  echo "waiting for ssh on $name ($ip) ..."
  for _ in $(seq 1 60); do
    if ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 \
         "root@$ip" true 2>/dev/null; then break; fi
    sleep 5
  done
  echo "scp farm scripts -> $name"
  ssh -i "$KEY" "root@$ip" 'mkdir -p ~/fuzz-farm-src'
  scp -q -i "$KEY" "$HERE/fuzz-rotate.sh" "$HERE/zen-fuzz.service" "$HERE/crates.list" "root@$ip:fuzz-farm-src/"
  echo "running setup-fuzz-box.sh on $name (apt + rust + cargo-fuzz; a few min)..."
  ssh -i "$KEY" "root@$ip" 'bash -s' < "$HERE/setup-fuzz-box.sh"
  echo "$name provisioned (ip $ip)"
}

do_arm=0; do_x86=0
case "$WHICH" in
  both) do_arm=1; do_x86=1;;
  arm)  do_arm=1;;
  x86)  do_x86=1;;
  *) echo "usage: launch-boxes.sh [arm|x86|both]" >&2; exit 1;;
esac
[ "$do_arm" = 1 ] && { create_box zen-fuzz-arm "${FUZZ_ARM_TYPE:-cax41}" && provision zen-fuzz-arm || echo ">> arm box not ready (stock?); rerun later: launch-boxes.sh arm"; }
[ "$do_x86" = 1 ] && { create_box zen-fuzz-x86 cpx42 && provision zen-fuzz-x86 || echo ">> x86 box not ready; rerun later: launch-boxes.sh x86"; }
rm -f "$CLOUDINIT"

echo
echo "=== next (from workstation) ==="
echo "  HOSTS=\$(for b in zen-fuzz-arm zen-fuzz-x86; do hcloud server ip \$b 2>/dev/null | sed 's/^/root@/'; done)"
echo "  $HERE/sync-tree.sh        \$HOSTS      # seed buildable tree (minutes)"
echo "  $HERE/refresh-r2-creds.sh \$HOSTS      # push scoped R2 creds"
echo "  for h in \$HOSTS; do ssh -i $KEY \$h systemctl start zen-fuzz; done"
