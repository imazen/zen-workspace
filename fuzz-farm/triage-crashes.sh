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
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$HOME/.cargo/bin:/usr/local/bin:$PATH"
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


# Ledger-hit re-open check: a signature hash in $LEDGER only proves an issue
# was FILED for it once, not that the bug is still fixed. If the mapped issue
# is CLOSED as COMPLETED but a crash with that exact hash was found AFTER the
# close, that's a live regression (a narrower fix than the bug class, or a
# re-break) — suppressing it forever hid ~10k zencodec/exif_roundtrip crashes
# for 2.5 weeks after #30 closed (2026-06-15 fix, 2026-07-02 discovered
# still-reproducing via manual audit; see zencodec#107).
#
# The mirror ($STATE/crashes) is never pruned — every run re-walks the FULL
# history of every crash ever pulled, not just this run's new arrivals. So the
# check can't be "is the mapped issue closed" alone, or the very act of
# closing an issue would make every pre-existing (already-fixed, stale) mirror
# file look like a fresh regression forever, refiling on a loop. Compare the
# meta.json's R2 LastModified (when the box actually uploaded it, i.e. roughly
# "when the box found this crash") against the issue's closedAt: only an
# upload newer than the close is evidence the bug is still alive.
#
# Do NOT use the local file mtime for this: s5cmd sync does NOT preserve the
# R2 object's timestamp (v2.3.0 has no such option — an earlier revision of
# this heuristic assumed it did). Local mtime is just "when this file was
# last (re-)synced", so any mirror re-materialization makes every closed
# panic signature look freshly recurred — that's exactly how zencodec#113
# got falsely re-filed on 2026-07-12 (mirror re-sync at 19:35Z, "RECURRED"
# filing at 19:49Z, while R2 showed no upload for that box since 07-02).
#
# Cache lookups per-URL per run: a single sig-hash can map to thousands of
# crash files in one pull.
declare -A _issue_state_cache _issue_reason_cache _issue_closed_cache _r2_epoch_cache
r2_upload_epoch(){  # $1=local mirror path -> sets R2_EPOCH to the R2 object's LastModified as epoch seconds ('' if not on R2 / lookup failed)
  local rel="${1#"$STATE/crashes/"}" line d t
  if [ -z "${_r2_epoch_cache[$rel]+x}" ]; then
    line="$(s5 ls "s3://$BUCKET/crashes/$rel" 2>/dev/null | tail -1)"   # "2026/07/02 00:27:13  4749  <key>" — date/time are UTC
    read -r d t _ <<<"$line"
    _r2_epoch_cache[$rel]=""
    if [ -n "${d:-}" ] && [ -n "${t:-}" ]; then
      _r2_epoch_cache[$rel]="$(date -u -d "${d//\//-} $t" +%s 2>/dev/null || true)"
    fi
  fi
  R2_EPOCH="${_r2_epoch_cache[$rel]}"
}
ledger_hit_is_stale_closed(){  # $1=sig_hash $2=meta.json path $3=normalized sig text -> 0 if mapped issue is CLOSED+COMPLETED AND this artifact postdates the close (don't suppress)
  local url json meta_epoch closed_epoch
  # oom/leak/timeout buckets are coarse-grained by design (ANY slow/OOM input
  # for a target collapses to one hash, regardless of root cause) — the
  # fuzzer periodically finding *some* new slow input after a perf fix isn't
  # evidence that fix regressed, unlike a panic recurring at the exact same
  # file:line:col. Only re-open panics.
  [[ "$3" == "panic "* ]] || return 1
  url="$(grep "^$1	" "$LEDGER" 2>/dev/null | tail -1 | cut -f3)"
  [[ "$url" == http* ]] || return 1   # placeholder rows (unknown/issues-disabled) — keep suppressing
  if [ -z "${_issue_state_cache[$url]+x}" ]; then
    json="$(gh issue view "$url" --json state,stateReason,closedAt 2>/dev/null)"
    _issue_state_cache[$url]="$(echo "$json" | jq -r '.state // "UNKNOWN"' 2>/dev/null)"
    _issue_reason_cache[$url]="$(echo "$json" | jq -r '.stateReason // ""' 2>/dev/null)"
    _issue_closed_cache[$url]="$(echo "$json" | jq -r '.closedAt // ""' 2>/dev/null)"
  fi
  [ "${_issue_state_cache[$url]}" = "CLOSED" ] && [ "${_issue_reason_cache[$url]}" = "COMPLETED" ] || return 1
  [ -n "${_issue_closed_cache[$url]}" ] || return 1                       # no timestamp — don't guess, stay suppressed
  r2_upload_epoch "$2"                       # R2 LastModified, NOT local mtime (see comment above / zencodec#113)
  meta_epoch="$R2_EPOCH"
  [ -n "$meta_epoch" ] || return 1           # no upload-time evidence — stay suppressed
  closed_epoch="$(date -d "${_issue_closed_cache[$url]}" +%s 2>/dev/null)" || return 1
  [ "$meta_epoch" -gt "$closed_epoch" ]
}

filed=0; queued=0; skipped=0; buildfail=0; reopened=0; unclass=0
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
BUILD=re.compile(r"failed to build fuzz script|requires the features:|error\[E\d{2,4}\]|error: could not compile|no bin target named|error: failed to run custom build command|error: linking with|error: failed to select a version|error: failed to load manifest|error: failed to parse manifest")
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
    m=re.search(r"(ERROR: libFuzzer:.*|SUMMARY:.*|ERROR: AddressSanitizer.*|ERROR: (?:Leak|Memory|Undefined|Thread)Sanitizer.*)",blob)
    if m: return re.sub(r"0x[0-9a-fA-F]+","0xADDR",re.sub(r"\d+","N",m.group(1)))[:160]
    # Nothing recognisable: no panic location, no sanitizer / libFuzzer summary,
    # no oom/leak/timeout artifact. The box's repro did not crash — a build that
    # failed in a way BUILD does not list, a fork-mode-only flake, a repro run in
    # the wrong checkout. Filing it keys the issue on the artifact's OWN NAME:
    # one issue per artifact, forever (zenwebp#87/#88, 2026-08-23/24, were two
    # "no bin target named demux_container" build logs). Not a finding.
    return "UNCLASSIFIED"
ns=norm()
if ns is None: print("SKIP|||||"); sys.exit(0)
if ns=="UNCLASSIFIED": print("UNCLASS|||||"); sys.exit(0)
h=hashlib.sha256(f"{c}\n{t}\n{ns}".encode()).hexdigest()[:16]
print(f"FILE|{h}|{c}|{t}|{a}|{ns.replace(chr(124),'/')}")
PY
)
  case "$verdict" in
    FILE) ;;
    UNCLASS) unclass=$((unclass+1)); echo "  ?? unclassifiable repro (no panic / sanitizer signature) — not a finding, skipped: $meta"; continue ;;
    *) buildfail=$((buildfail+1)); continue ;;
  esac
  [ -n "$sig_hash" ] || continue
  is_regression=0
  if grep -q "^$sig_hash	" "$LEDGER" 2>/dev/null; then
    if ledger_hit_is_stale_closed "$sig_hash" "$meta" "$sig"; then
      prior_url="$(grep "^$sig_hash	" "$LEDGER" | tail -1 | cut -f3)"
      echo "  ↻ sig $sig_hash maps to CLOSED+COMPLETED $prior_url but this artifact postdates the close — treating as a regression, not suppressing"
      is_regression=1; reopened=$((reopened+1))
    else
      skipped=$((skipped+1)); continue
    fi
  fi

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

  if [ "$is_regression" = "1" ]; then
    title="fuzz: ${crate_rel}::${target} crash ($sig_hash) — RECURRED after $prior_url"
  else
    title="fuzz: ${crate_rel}::${target} crash ($sig_hash)"
  fi
  body="$(mktemp)"
  {
    echo "Found by the continuous fuzz farm (libFuzzer)."
    echo
    if [ "$is_regression" = "1" ]; then
      echo "**This signature was previously filed and closed as fixed at $prior_url — crashes with the identical panic location kept arriving afterward, so this is either an incomplete fix or a re-break, not a duplicate.**"
      echo
    fi
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
    elif [ "$(gh repo view "$repo" --json hasIssuesEnabled -q .hasIssuesEnabled 2>/dev/null)" = "false" ]; then
      # Issues are disabled on this repo — creating will fail forever. Queue it
      # for manual review and ledger it so we don't retry-loop every run (e.g.
      # lilith/weezl, 2026-06-14). The repro + meta still live in R2.
      echo "  ⚠ $repo has Issues disabled — queued for manual review (sig $sig_hash)"
      echo -e "$sig_hash\t$repo\t$target\t$arch\t$cdir\tISSUES-DISABLED" >>"$QUEUE"
      echo -e "$sig_hash\t$repo\t(issues-disabled — queued for manual review)" >>"$LEDGER"
      queued=$((queued+1))
    else
      echo "  FAILED to file issue for $repo (sig $sig_hash) — left for retry" >&2
    fi
  fi
  rm -f "$body"
done < <(find "$STATE/crashes" -name meta.json 2>/dev/null)

echo "=== triage done: filed=$filed regressions=$reopened queued(manual)=$queued already-known=$skipped build-failures-skipped=$buildfail unclassifiable-skipped=$unclass ==="
[ "$queued" -gt 0 ] && echo "third-party / unknown crashes need manual review: $QUEUE"
