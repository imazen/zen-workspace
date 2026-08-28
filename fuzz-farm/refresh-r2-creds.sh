#!/usr/bin/env bash
# refresh-r2-creds.sh — mint a scoped, auto-expiring R2 credential for the
# `zenfuzz` bucket and push it to each fuzz box at ~/.config/zenfuzz/r2.env.
# The Cloudflare MANAGEMENT token never leaves the workstation; the boxes only
# ever hold a short-lived, single-bucket, object-read-write cred. Run from cron
# (e.g. every 5 days at TTL 7 days). The rotate runner re-sources r2.env each
# pass, so a refreshed cred is picked up without a restart.
#
#   refresh-r2-creds.sh root@<ip> [root@<ip>...]
#
# If the workstation is offline past the TTL, corpus/crash uploads pause (and
# resume on the next refresh); fuzzing keeps running and crashes stay on the box
# disk. For full workstation-independence, swap to a permanent bucket-scoped R2
# token (see README "Credentials").
set -euo pipefail
# cron runs with a minimal PATH; s5cmd/hcloud live in ~/.local/bin, cargo in ~/.cargo/bin
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$HOME/.cargo/bin:/usr/local/bin:$PATH"
# Hosts: explicit args, else auto-resolve every purpose=fuzz box (cron-friendly).
if [ "$#" -ge 1 ]; then HOSTS=("$@"); else
  HCTOK="$(grep -E '^api_token=' "$HOME/.config/hetzner/credentials" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' \r')"
  mapfile -t HOSTS < <(HCLOUD_TOKEN="$HCTOK" hcloud server list -l fuzz=yes -o noheader -o columns=ipv4 2>/dev/null | sed 's/^/root@/')
fi
[ "${#HOSTS[@]}" -ge 1 ] || { echo "no fuzz boxes found (pass root@<ip> or check hcloud)" >&2; exit 0; }
KEY="${FUZZ_SSH_KEY:-$HOME/.ssh/zen-arm-dev}"
BUCKET="${ZENFUZZ_BUCKET:-zenfuzz}"
TTL="${ZENFUZZ_TTL:-604800}"   # 7 days (max)
set -a; . "$HOME/.config/cloudflare/r2-credentials"; set +a
EP="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"

body="$(BUCKET="$BUCKET" TTL="$TTL" python3 -c 'import json,os;print(json.dumps({
  "bucket":os.environ["BUCKET"],
  "parentAccessKeyId":os.environ["R2_ACCESS_KEY_ID"],
  "parentSecretAccessKey":os.environ["R2_SECRET_ACCESS_KEY"],
  "permission":"object-read-write","ttlSeconds":int(os.environ["TTL"])}))')"
resp="$(curl -sS -X POST -H "Authorization: Bearer $R2_API_TOKEN" \
  -H "Content-Type: application/json" -d "$body" \
  "https://api.cloudflare.com/client/v4/accounts/$R2_ACCOUNT_ID/r2/temp-access-credentials")"
if ! read -r AK SK ST < <(echo "$resp" | python3 -c 'import json,sys
r=json.load(sys.stdin)
assert r.get("success"), r
x=r["result"]; print(x["accessKeyId"], x["secretAccessKey"], x["sessionToken"])'); then
  echo "mint failed: $resp" >&2; exit 1
fi

ENVFILE="$(mktemp)"; chmod 600 "$ENVFILE"
cat > "$ENVFILE" <<EOF
# scoped R2 temp cred for bucket=$BUCKET, minted $(date -u +%FT%TZ), ttl=${TTL}s
export R2_ENDPOINT="$EP"
export R2_BUCKET="$BUCKET"
export AWS_ACCESS_KEY_ID="$AK"
export AWS_SECRET_ACCESS_KEY="$SK"
export AWS_SESSION_TOKEN="$ST"
EOF

for HOST in "${HOSTS[@]}"; do
  if ssh -i "$KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 "$HOST" 'mkdir -p ~/.config/zenfuzz' \
     && scp -q -i "$KEY" "$ENVFILE" "$HOST:.config/zenfuzz/r2.env" \
     && ssh -i "$KEY" "$HOST" 'chmod 600 ~/.config/zenfuzz/r2.env'; then
    echo "pushed scoped creds to $HOST (ttl ${TTL}s)"
  else
    echo "FAILED to push creds to $HOST" >&2
  fi
done
rm -f "$ENVFILE"
