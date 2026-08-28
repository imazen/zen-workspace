#!/usr/bin/env bash
# mint-permanent-r2-token.sh — create a NON-EXPIRING, single-bucket R2 API token
# for the fuzz farm, then hand it to install-permanent-r2-cred.sh.
#
# Uses ~/.config/cloudflare/cf-token-mint (CF_TOKEN_MINT_TOKEN) — an ACCOUNT-owned
# token carrying "Account API Tokens Write". NOT R2_API_TOKEN: that one mints temp
# creds only and 9109s on every token-management path (as do the three account
# tokens in ~/fun/weaver/.env and the expired wrangler OAuth grant).
#
# Verified against the LIVE API 2026-07-30:
#   - the mint token is account-owned, so /user/tokens/* returns 9109
#     "Valid user-level authentication not found" — use /accounts/<acct>/tokens
#   - bucket scoping = permission group "Workers R2 Storage Bucket Item Write",
#     resolved BY NAME (the docs example's id is Read in this account — see below),
#     with resource key com.cloudflare.edge.r2.bucket.<acct>_default_<bucket>
#   - S3 Access Key ID = the token's id; Secret = SHA-256 of the token's value
#   - omitting expires_on entirely = never expires
set -uo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$HOME/.cargo/bin:/usr/local/bin:$PATH"
set -a; . "$HOME/.config/cloudflare/r2-credentials"; set +a
# The R2_API_TOKEN can mint TEMP creds but cannot manage tokens (9109 on every
# token path). Minting needs the separate account-owned token that carries
# "Account API Tokens Write".
[ -f "$HOME/.config/cloudflare/cf-token-mint" ] && { set -a; . "$HOME/.config/cloudflare/cf-token-mint"; set +a; }
MINT_TOKEN="${CF_TOKEN_MINT_TOKEN:-}"
BUCKET="${ZENFUZZ_BUCKET:-zenfuzz}"
NAME="${TOKEN_NAME:-zenfuzz-farm-worker}"
API="https://api.cloudflare.com/client/v4"

echo "=== 1. confirm we hold a token that may manage tokens ==="
[ -n "$MINT_TOKEN" ] || { echo "  no CF_TOKEN_MINT_TOKEN (see ~/.config/cloudflare/cf-token-mint)" >&2; exit 3; }
# It is ACCOUNT-owned: /user/tokens/* returns 9109 for it. Use the /accounts path.
pg="$(curl -sS -H "Authorization: Bearer $MINT_TOKEN" "$API/accounts/$R2_ACCOUNT_ID/tokens/permission_groups")"
if ! echo "$pg" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("success") else 1)'; then
  echo "  mint token cannot manage tokens:" >&2
  echo "$pg" | python3 -c 'import json,sys; print("  ", json.load(sys.stdin).get("errors"))' 2>/dev/null
  exit 3
fi
echo "  ok"

echo "=== 2. resolve the bucket-scoped R2 write permission group ==="
# Resolve by NAME from the live API — do NOT hardcode. The published docs example
# labels 6a018a9f2fc74eb6b293b0c548f38b39 as "Bucket Item Write", but this account's
# live permission-group list reports that id as "Bucket Item READ" (write is
# 2efd5506f9c8494dacb1fa10a3e7d5b6). Hardcoding the doc value would have minted a
# read-only key that silently cannot push corpus.
PGID="$(echo "$pg" | python3 -c '
import json,sys
d=json.load(sys.stdin)
for g in d.get("result",[]):
    if g.get("name")=="Workers R2 Storage Bucket Item Write":
        print(g["id"]); break
')"
[ -n "$PGID" ] || { echo "  could not resolve 'Workers R2 Storage Bucket Item Write' by name" >&2; exit 1; }
echo "  permission group: $PGID (resolved by name)"

echo "=== 3. create the token (no expires_on => never expires) ==="
RES="com.cloudflare.edge.r2.bucket.${R2_ACCOUNT_ID}_default_${BUCKET}"
body="$(NAME="$NAME" PGID="$PGID" RES="$RES" python3 -c '
import json,os
print(json.dumps({
  "name": os.environ["NAME"],
  "policies": [{
    "effect": "allow",
    "permission_groups": [{"id": os.environ["PGID"]}],
    "resources": {os.environ["RES"]: "*"},
  }],
}))')"
parse_token(){ python3 -c '
import json,sys
r=json.load(sys.stdin)
if not r.get("success"): raise SystemExit(1)
x=r["result"]; print(x["id"], x["value"])'; }

# Account-owned first (matches how the R2 dashboard creates tokens). If the
# account path is refused, fall back to a user-owned token — R2 accepts both,
# and only the user-scoped "API Tokens Write" grant is documented as required.
resp="$(curl -sS -X POST -H "Authorization: Bearer $MINT_TOKEN" \
  -H "Content-Type: application/json" -d "$body" "$API/accounts/$R2_ACCOUNT_ID/tokens")"
OWNER=account
if ! read -r TID TVAL < <(echo "$resp" | parse_token); then
  echo "  account-owned create refused, trying user-owned…"
  echo "$resp" | python3 -c 'import json,sys; print("   ", json.load(sys.stdin).get("errors"))' 2>/dev/null
  resp="$(curl -sS -X POST -H "Authorization: Bearer $MINT_TOKEN" \
    -H "Content-Type: application/json" -d "$body" "$API/user/tokens")"
  OWNER=user
  read -r TID TVAL < <(echo "$resp" | parse_token) || {
    echo "  token creation FAILED on both paths:"; echo "$resp" | head -c 600; exit 1; }
fi
echo "  ($OWNER-owned)"

echo "  created token id ${TID:0:8}… (never expires, bucket=$BUCKET)"

# S3 credentials: access key id = token id, secret = SHA-256 of the token value.
SKV="$(printf '%s' "$TVAL" | sha256sum | cut -d' ' -f1)"

echo "=== 4. stash the raw token value (needed to revoke / re-derive) ==="
umask 077
cat > "$HOME/.config/cloudflare/zenfuzz-token.json" <<EOF
{
  "note": "Permanent R2 API token for the zenfuzz fuzz farm. Revoke via dashboard or DELETE $API/accounts/<acct>/tokens/$TID",
  "created": "$(date -u +%FT%TZ)",
  "name": "$NAME",
  "bucket": "$BUCKET",
  "token_id_is_s3_access_key_id": "$TID",
  "token_value": "$TVAL"
}
EOF
chmod 600 "$HOME/.config/cloudflare/zenfuzz-token.json"
echo "  saved ~/.config/cloudflare/zenfuzz-token.json (600)"

echo "=== 5. install to every fuzz=yes box ==="
export R2_PERM_ACCESS_KEY_ID="$TID" R2_PERM_SECRET_ACCESS_KEY="$SKV"
exec "$(dirname "$0")/install-permanent-r2-cred.sh"
