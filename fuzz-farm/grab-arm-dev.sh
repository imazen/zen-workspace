#!/usr/bin/env bash
# grab-arm-dev.sh — the moment Hetzner ARM stock returns, grab a >=32GB ARM box
# (cax41 = 16c/32GB by default) and provision it as a DEV box you can code on:
# full mise toolchain via the standard setup-arm-box.sh, PLUS fuzzing as a NICED
# background layer (dev stays primary — fuzz only uses spare CPU/IO). Per request:
# this box is for CODE DEV, not fuzzing-only.
#
# Run on a cron every ~30 min; it no-ops until cax41 stock appears, then creates +
# dev-provisions + onboards fuzzing, and disarms its own cron line.
#   arm:    (crontab -l 2>/dev/null; echo "*/30 * * * * $PWD/grab-arm-dev.sh >> /tmp/fuzz-arm-grab.log 2>&1") | crontab -
#   disarm: crontab -l | grep -v grab-arm-dev.sh | crontab -
set -uo pipefail
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY="${FUZZ_SSH_KEY:-$HOME/.ssh/zen-arm-dev}"
NAME="${ARM_DEV_NAME:-zen-arm-xl}"
TYPE="${FUZZ_ARM_TYPE:-cax41}"               # >=32GB ARM
ZSCRIPTS="$HOME/work/zen/scripts"            # setup-arm-box.sh + .mise.toml (dev parity)
CLOUDINIT="$HOME/work/zen/hetzner-arm-config/cloud-init.yaml"   # creates ubuntu user + PAM fix
SSHKEY_NAME="${HCLOUD_SSH_KEY:-zen-arm-dev-20260528}"
LOCATIONS=(${HCLOUD_LOCATIONS:-fsn1 nbg1 hel1})
export HCLOUD_TOKEN="$(grep -E '^api_token=' "$HOME/.config/hetzner/credentials" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' \r')"
SSHO="-i $KEY -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new"
stamp(){ date -u +%FT%TZ; }
disarm(){ crontab -l 2>/dev/null | grep -v 'grab-arm-dev.sh' | crontab - 2>/dev/null || true; }
ip(){ hcloud server ip "$NAME" 2>/dev/null; }

# Already up + dev-provisioned (mise toolchain present)? Done — disarm.
a="$(ip)"
if [ -n "$a" ] && ssh $SSHO "ubuntu@$a" 'command -v cargo && command -v jj' >/dev/null 2>&1; then
  echo "$(stamp) $NAME already up + dev-provisioned — disarming"; disarm; exit 0
fi

# 1. Create the cax41 with the DEV cloud-init (ubuntu user + PAM aging fix), trying locations.
if [ -z "$a" ]; then
  ok=""
  for loc in "${LOCATIONS[@]}"; do
    if hcloud server create --name "$NAME" --type "$TYPE" --image ubuntu-24.04 --location "$loc" \
         --ssh-key "$SSHKEY_NAME" --label purpose=dev --label fuzz=yes --label owner=lilith \
         --user-data-from-file "$CLOUDINIT" >/dev/null 2>&1; then
      ok=1; echo "$(stamp) $NAME ($TYPE) created in $loc"; break
    fi
  done
  [ -n "$ok" ] || { echo "$(stamp) no $TYPE stock in ${LOCATIONS[*]} — will retry"; exit 0; }
fi
a="$(ip)"; [ -n "$a" ] || { echo "$(stamp) no ip yet"; exit 0; }

# Wait for ssh, then make sure ubuntu has the login key (cloud-init keys root via --ssh-key).
for _ in $(seq 1 60); do ssh $SSHO "root@$a" true 2>/dev/null && break; sleep 5; done
ssh $SSHO "root@$a" 'id ubuntu >/dev/null 2>&1 && install -d -o ubuntu -g ubuntu ~ubuntu/.ssh && \
  cp /root/.ssh/authorized_keys ~ubuntu/.ssh/authorized_keys && chown ubuntu:ubuntu ~ubuntu/.ssh/authorized_keys' || true

# 2. DEV parity: the standard ARM dev-box setup (mise fleet, cargo, cloud CLIs), run as ubuntu.
scp -q $SSHO "$ZSCRIPTS/.mise.toml" "root@$a:/home/ubuntu/zen-mise.toml" 2>/dev/null || true
GHTOK="$(gh auth token 2>/dev/null)"
ssh $SSHO "root@$a" "sudo -u ubuntu env GH_TOKEN='$GHTOK' GITHUB_TOKEN='$GHTOK' bash -s" \
  < "$ZSCRIPTS/setup-arm-box.sh" || echo "$(stamp) WARN: dev setup-arm-box had issues — finish manually"

# 3. FUZZ as a niced background layer (root): toolchain + service, dev stays primary.
ssh $SSHO "root@$a" 'mkdir -p ~/fuzz-farm-src'
scp -q $SSHO "$HERE/fuzz-rotate.sh" "$HERE/zen-fuzz.service" "$HERE/crates.list" "root@$a:fuzz-farm-src/"
ssh $SSHO "root@$a" 'bash -s' < "$HERE/setup-fuzz-box.sh" || echo "$(stamp) WARN: fuzz setup had issues"
# dev-friendly fuzz: niced + low weight, ~6 of 16 cores, capped RAM (32GB box).
ssh $SSHO "root@$a" 'mkdir -p /etc/systemd/system/zen-fuzz.service.d
  printf "[Service]\nNice=19\nCPUWeight=20\nIOWeight=20\nMemoryMax=14G\nEnvironment=FORKS=6\n" \
    > /etc/systemd/system/zen-fuzz.service.d/devbox.conf
  systemctl daemon-reload'
"$HERE/sync-tree.sh"        "root@$a" || echo "$(stamp) WARN: sync-tree failed"
"$HERE/refresh-r2-creds.sh" "root@$a" || echo "$(stamp) WARN: cred push failed"
ssh $SSHO "root@$a" 'systemctl start zen-fuzz' || true

echo "$(stamp) $NAME ($TYPE) UP at $a — DEV-provisioned + fuzzing (niced)."
echo "$(stamp) finish: 'ssh ubuntu@$a' then run 'claude' once (OAuth login). It's labeled purpose=dev (kill-boxes won't touch it)."
disarm