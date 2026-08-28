#!/usr/bin/env bash
# install-permanent-r2-cred.sh — replace the 7-day temp R2 cred on every fuzz=yes
# box with a PERMANENT, bucket-scoped R2 API token, so the farm no longer depends
# on the workstation being up to rotate credentials.
#
# The workstation cannot mint this token: the local R2_API_TOKEN has R2 read +
# temp-cred-mint only (token management returns 9109 Unauthorized), and the
# wrangler OAuth grant carries no token-management scope. Create it once by hand:
#
#   Cloudflare dashboard -> R2 -> "Manage R2 API Tokens" -> Create API token
#     Name        : zenfuzz-farm-worker
#     Permissions : Object Read & Write
#     Bucket      : zenfuzz   (Apply to specific buckets only — NOT all buckets)
#     TTL         : Forever
#
# It returns an Access Key ID + Secret Access Key. Then:
#
#   read -rs -p 'access key id: ' R2_PERM_ACCESS_KEY_ID;  echo
#   read -rs -p 'secret: '        R2_PERM_SECRET_ACCESS_KEY; echo
#   export R2_PERM_ACCESS_KEY_ID R2_PERM_SECRET_ACCESS_KEY
#   ~/work/zenfuzz-farm/install-permanent-r2-cred.sh
#
# (`read -rs` keeps the secret out of shell history and out of `ps`.)
set -uo pipefail
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"

AK="${R2_PERM_ACCESS_KEY_ID:-}"
SK="${R2_PERM_SECRET_ACCESS_KEY:-}"
[ -n "$AK" ] && [ -n "$SK" ] || {
  echo "set R2_PERM_ACCESS_KEY_ID and R2_PERM_SECRET_ACCESS_KEY first (see header)" >&2; exit 2; }

set -a; . "$HOME/.config/cloudflare/r2-credentials"; set +a   # for R2_ACCOUNT_ID only
EP="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
BUCKET="${ZENFUZZ_BUCKET:-zenfuzz}"
KEY="${FUZZ_SSH_KEY:-$HOME/.ssh/zen-arm-dev}"
SSHC="ssh -i $KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20"

s5p(){ AWS_ACCESS_KEY_ID="$AK" AWS_SECRET_ACCESS_KEY="$SK" AWS_SESSION_TOKEN="" \
       AWS_REGION=auto s5cmd --endpoint-url "$EP" "$@"; }

echo "=== 1. verify the new cred can READ s3://$BUCKET ==="
# A freshly-minted R2 token is not immediately active — observed 2026-07-30, the
# first probe seconds after creation failed while the identical call succeeded
# shortly after. Retry rather than treat propagation lag as a bad credential.
ok=0
for i in $(seq 1 12); do
  if s5p ls "s3://$BUCKET/corpus/" >/dev/null 2>&1; then ok=1; break; fi
  [ "$i" -eq 1 ] && echo "  not active yet — waiting for token propagation…"
  sleep 10
done
[ "$ok" -eq 1 ] || { echo "  FAILED: cannot list $BUCKET after ~2 min" >&2; exit 1; }
echo "  ok"

echo "=== 2. verify it can WRITE (round-trip a probe object) ==="
probe="$(mktemp)"; echo "zenfuzz permanent-cred probe" > "$probe"
pkey="s3://$BUCKET/imported/_credcheck/probe.txt"
s5p cp "$probe" "$pkey" >/dev/null 2>&1 || { echo "  FAILED: cannot write to $BUCKET" >&2; rm -f "$probe"; exit 1; }
s5p rm "$pkey" >/dev/null 2>&1
rm -f "$probe"; echo "  ok"

echo "=== 3. verify it is SCOPED (must NOT reach another bucket) ==="
if s5p ls "s3://zentrain/" >/dev/null 2>&1; then
  echo "  WARNING: this cred can also list s3://zentrain — it is NOT bucket-scoped." >&2
  echo "  Re-create it with 'Apply to specific buckets only -> zenfuzz'. Aborting." >&2
  exit 1
fi
echo "  ok — denied on other buckets, as intended"

echo "=== 4. write r2.env to every fuzz=yes box ==="
export HCLOUD_TOKEN="$(grep -E '^api_token=' "$HOME/.config/hetzner/credentials" | head -1 | cut -d= -f2- | tr -d ' \r')"
mapfile -t HOSTS < <(hcloud server list -l fuzz=yes -o noheader -o columns=ipv4 2>/dev/null | sed 's/^/root@/')
[ "${#HOSTS[@]}" -ge 1 ] || { echo "no fuzz=yes boxes found" >&2; exit 1; }

ENVFILE="$(mktemp)"; chmod 600 "$ENVFILE"
cat > "$ENVFILE" <<EOF
# PERMANENT bucket-scoped R2 cred for $BUCKET — installed $(date -u +%FT%TZ).
# Does not expire; refresh-r2-creds.sh is no longer needed (and its cron was
# removed, because re-running it would clobber this file with a 7-day temp cred).
# The unset below is load-bearing: fuzz-rotate.sh sources this file into a
# long-running shell, so a stale AWS_SESSION_TOKEN from a previous TEMP cred
# would otherwise persist in the process and 403 every request.
unset AWS_SESSION_TOKEN
export R2_ENDPOINT="$EP"
export R2_BUCKET="$BUCKET"
export AWS_ACCESS_KEY_ID="$AK"
export AWS_SECRET_ACCESS_KEY="$SK"
EOF

for H in "${HOSTS[@]}"; do
  echo "--- $H ---"
  $SSHC "$H" 'mkdir -p ~/.config/zenfuzz' \
    && scp -q -i "$KEY" "$ENVFILE" "$H:.config/zenfuzz/r2.env" \
    && $SSHC "$H" 'chmod 600 ~/.config/zenfuzz/r2.env' || { echo "  FAILED to install"; continue; }
  # Restart so the long-lived rotate process drops any stale session token.
  $SSHC "$H" 'systemctl restart zen-fuzz 2>/dev/null; sleep 2; systemctl is-active zen-fuzz' 2>/dev/null
  # Verify from the box, with the box's own file.
  $SSHC "$H" 'set -a; . ~/.config/zenfuzz/r2.env; set +a
     AWS_REGION=auto s5cmd --endpoint-url "$R2_ENDPOINT" ls "s3://$R2_BUCKET/corpus/" >/dev/null 2>&1 \
       && echo "  R2 reachable from box: ok" || echo "  R2 FAILED from box"'
done
rm -f "$ENVFILE"

echo "=== 5. keep a copy on the workstation for provisioning new boxes ==="
WS="$HOME/.config/cloudflare/zenfuzz-permanent.env"
umask 077; cat > "$WS" <<EOF
# PERMANENT bucket-scoped R2 cred for $BUCKET (installed $(date -u +%FT%TZ)).
# Used to provision new fuzz boxes: re-run install-permanent-r2-cred.sh with
# these exported as R2_PERM_ACCESS_KEY_ID / R2_PERM_SECRET_ACCESS_KEY.
export R2_PERM_ACCESS_KEY_ID="$AK"
export R2_PERM_SECRET_ACCESS_KEY="$SK"
EOF
chmod 600 "$WS"; echo "  saved $WS (600)"

echo
echo "=== 6. REMAINING MANUAL STEP ==="
echo "Remove the temp-cred rotation cron, or it will overwrite r2.env within 4 days:"
echo "  crontab -e   # delete the line: 37 4 */4 * * ... refresh-r2-creds.sh"
crontab -l 2>/dev/null | grep -n 'refresh-r2-creds' || echo "  (no such cron line found — nothing to remove)"
