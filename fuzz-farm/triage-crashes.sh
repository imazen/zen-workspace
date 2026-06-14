#!/usr/bin/env bash
# triage-crashes.sh — workstation-side crash triage + GitHub issue filing.
# Pulls new crash artifacts from R2 s3://zenfuzz/crashes/ to the durable mirror,
# dedups by signature, maps each crate to its GitHub repo from the LOCAL tree,
# and AUTO-FILES an issue (assigned to lilith) for imazen/* and lilith/* repos.
# Third-party repos (google/*, libjxl/*, upstream forks) are queued for manual
# review and NEVER auto-posted (per CLAUDE.md). The GitHub token lives only here;
# the fuzz boxes never file issues, and dedup is centralized so two boxes hitting
# the same bug file one issue. Run from cron (e.g. every 30 min).
#
#   DRY_RUN=1 triage-crashes.sh    # print what it would file, touch nothing
set -uo pipefail
# cron runs with a minimal PATH; s5cmd/hcloud live in ~/.local/bin, cargo in ~/.cargo/bin
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"
ZEN_ROOT="${ZEN_ROOT:-$HOME/work/zen}"
STATE="${ZENFUZZ_STATE:-/mnt/v/fuzzes/_farm}"     # durable ledger + crash mirror
LEDGER="$STATE/filed-issues.tsv"                  # sig_hash <TAB> repo <TAB> issue_url
QUEUE="$STATE/needs-review.tsv"                   # third-party crashes (manual)
BUCKET="${ZENFUZZ_BUCKET:-zenfuzz}"
DRY="${DRY_RUN:-0}"

set -a; . "$HOME/.config/cloudflare/r2-credentials"; set +a
EP="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
s5(){ AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
      AWS_REGION=auto s5cmd --endpoint-url "$EP" "$@"; }

mkdir -p "$STATE/crashes"; touch "$LEDGER" "$QUEUE"

echo "=== pulling crashes from s3://$BUCKET/crashes/ -> $STATE/crashes/ ==="
s5 sync "s3://$BUCKET/crashes/*" "$STATE/crashes/" 2>/dev/null || \
  { echo "(nothing to pull yet)"; }

# crate_rel -> owner/repo, from the local tree's origin remote
repo_for(){ git -C "$ZEN_ROOT/$1" remote get-url origin 2>/dev/null \
  | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##'; }

filed=0; queued=0; skipped=0; buildfail=0
while IFS= read -r meta; do
  [ -f "$meta" ] || continue
  # Re-normalize the signature CENTRALLY here — do NOT trust the box's sig_hash.
  # This is the dedup backstop: a box on any runner version (or a new failure
  # mode) can't spam the tracker. We (a) DROP build failures entirely — a repro
  # that won't compile is not a finding (378 bogus rav1d-safe issues on
  # 2026-06-14); (b) key panics on file:line:col, stripping the per-process
  # `thread '<unnamed>' (PID)` prefix that made every crash unique (~130 dup
  # heic/zencodec issues); (c) collapse oom/leak/timeout per target; (d) mask
  # addresses/numbers in sanitizer summaries.
  IFS='|' read -r verdict sig_hash crate_rel target arch sig < <(python3 - "$meta" <<'PY'
import json,sys,re,hashlib
BUILD=re.compile(r"failed to build fuzz script|requires the features:|error\[E\d{2,4}\]|error: could not compile")
LOC=re.compile(r"^\S+\.(rs|c|cc|cpp|h|cxx):\d+:\d+$")
def trim(l): l=re.sub(r"^.*/work/zen/","",l); return re.sub(r"^.*/registry/src/[^/]+/","",l)
try: d=json.load(open(sys.argv[1]))
except Exception: print("SKIP|||||"); sys.exit(0)
c=d.get("crate_rel","");t=d.get("target","");a=d.get("arch","")
sig=(d.get("signature","") or "").strip(); blob=sig+"\n"+(d.get("trace","") or "")
def norm():
    if BUILD.search(blob): return None
    m=re.search(r"panicked at (\S+?:\d+:\d+)",blob)
    loc=m.group(1) if m else (sig if LOC.match(sig) else None)
    if loc: return "panic "+trim(loc)
    low=sig.lower()
    if sig.startswith("oom") or "out-of-memory" in low: return "oom in "+t
    if sig.startswith("leak") or "memory leak" in low: return "leak in "+t
    if sig.startswith(("timeout","slow-unit")) or "timeout" in low: return "timeout in "+t
    m=re.search(r"(ERROR: libFuzzer:.*|SUMMARY:.*|ERROR: AddressSanitizer.*)",blob)
    if m: return re.sub(r"0x[0-9a-fA-F]+","0xADDR",re.sub(r"\d+","N",m.group(1)))[:160]
    return sig[:160] or "unknown"
ns=norm()
if ns is None: print("SKIP|||||"); sys.exit(0)
h=hashlib.sha256(f"{c}\n{t}\n{ns}".encode()).hexdigest()[:16]
print(f"FILE|{h}|{c}|{t}|{a}|{ns.replace(chr(124),'/')}")
PY
)
  [ "$verdict" = "FILE" ] || { buildfail=$((buildfail+1)); continue; }
  [ -n "$sig_hash" ] || continue
  grep -q "^$sig_hash	" "$LEDGER" 2>/dev/null && { skipped=$((skipped+1)); continue; }

  cdir="$(dirname "$meta")"
  repro="$(ls "$cdir"/crash-* "$cdir"/oom-* "$cdir"/leak-* "$cdir"/timeout-* "$cdir"/slow-unit-* 2>/dev/null | head -1)"
  repo="$(repo_for "$crate_rel")"; owner="${repo%%/*}"

  if [ -z "$repo" ]; then
    echo "  ?? no origin for $crate_rel (sig $sig_hash) — queued"; echo -e "$sig_hash\t(unknown:$crate_rel)\t$target\t$arch\t$cdir" >>"$QUEUE"; queued=$((queued+1)); continue
  fi
  case "$owner" in
    imazen|lilith) : ;;   # auto-file ok
    *) echo "  ⚠ third-party repo $repo — queued for manual review (sig $sig_hash)"
       echo -e "$sig_hash\t$repo\t$target\t$arch\t$cdir" >>"$QUEUE"; queued=$((queued+1)); continue ;;
  esac

  title="fuzz: ${crate_rel}::${target} crash ($sig_hash)"
  body="$(mktemp)"
  {
    echo "Found by the continuous fuzz farm (libFuzzer)."
    echo
    echo "- **Crate**: \`$crate_rel\`"
    echo "- **Target**: \`$target\`"
    echo "- **First seen on arch**: \`$arch\`"
    echo "- **Signature** (\`$sig_hash\`): \`$sig\`"
    echo "- **Repro + metadata in R2**: \`s3://$BUCKET/crashes/$crate_rel/$target/$arch/$sig_hash/\`"
    echo "- **Local mirror**: \`$cdir\`"
    echo
    echo "Reproduce:"
    echo '```'
    echo "cd $crate_rel"
    echo "# copy the repro from the R2/local path above, then:"
    echo "cargo +nightly fuzz run $target <repro-file>"
    echo '```'
    echo
    echo "<details><summary>Captured trace (tail)</summary>"
    echo
    echo '```'
    python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("trace","")[-3000:])' "$meta"
    echo '```'
    echo "</details>"
  } > "$body"

  if [ "$DRY" = "1" ]; then
    echo "  [dry-run] would file in $repo: $title"
    sed 's/^/      | /' "$body" | head -8
  else
    url="$(gh issue create -R "$repo" --assignee lilith \
            --label fuzz --title "$title" --body-file "$body" 2>/dev/null \
          || gh issue create -R "$repo" --assignee lilith \
            --title "$title" --body-file "$body" 2>/dev/null)"   # retry w/o label if absent
    if [ -n "$url" ]; then
      echo "  filed $repo: $url"
      echo -e "$sig_hash\t$repo\t$url" >>"$LEDGER"; filed=$((filed+1))
    else
      echo "  FAILED to file issue for $repo (sig $sig_hash) — left for retry" >&2
    fi
  fi
  rm -f "$body"
done < <(find "$STATE/crashes" -name meta.json 2>/dev/null)

echo "=== triage done: filed=$filed queued(manual)=$queued already-known=$skipped build-failures-skipped=$buildfail ==="
[ "$queued" -gt 0 ] && echo "third-party / unknown crashes need manual review: $QUEUE"
