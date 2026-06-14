#!/usr/bin/env bash
# fuzz-rotate.sh — continuous, round-robin libFuzzer rotation across every zen
# crate's fuzz targets. Runs forever (under systemd, Restart=always) on a
# dedicated Hetzner fuzz box. "Switches constantly": each pass it reshuffles the
# full (crate, target) work-list and gives each target a bounded time-slice on
# all cores via libFuzzer fork mode.
#
# Per target slice:
#   1. pull the SHARED corpus for this target from R2 (so the two boxes — ARM +
#      x86 — cooperatively grow ONE corpus per target)
#   2. fuzz it for $SLICE_SECS using `-fork=$(nproc) -ignore_*=1` (unattended:
#      saves crashes/OOMs/timeouts as artifacts and keeps going)
#   3. push newly-discovered corpus inputs back to R2 (additive sync)
#   4. for any NEW artifact: reproduce once to capture a dedup signature, then
#      upload the raw repro + metadata JSON to R2 (namespaced by arch). The
#      workstation triage cron turns those into deduplicated GitHub issues.
#
# This box NEVER files GitHub issues and NEVER holds a GitHub token — crash
# triage + issue filing happen on the trusted workstation (see triage-crashes.sh).
#
# Config via env (the systemd unit sets these):
#   ZEN_ROOT     tree to scan for fuzz crates            (default ~/work/zen)
#   FUZZ_HOME    box-local state: corpus/artifacts/logs   (default ~/fuzz-farm)
#   SLICE_SECS   seconds per target per visit             (default 600)
#   R2_ENV       sourced R2 creds + endpoint + bucket     (default ~/.config/zenfuzz/r2.env)
#   RSS_LIMIT_MB libFuzzer per-process RSS cap            (default 4096)
#   FUZZ_TIMEOUT per-input timeout seconds                (default 25)
set -uo pipefail

ZEN_ROOT="${ZEN_ROOT:-$HOME/work/zen}"
FUZZ_HOME="${FUZZ_HOME:-$HOME/fuzz-farm}"
SLICE_SECS="${SLICE_SECS:-600}"
R2_ENV="${R2_ENV:-$HOME/.config/zenfuzz/r2.env}"
FUZZ_TIMEOUT="${FUZZ_TIMEOUT:-25}"
NPROC="$(nproc)"
# Per-fork RSS limit FIRST, then derive fork count to fit RAM. Image decoders
# legitimately allocate ~1-2 GB for large buffers, so too LOW a per-fork limit
# causes fork-mode FALSE OOMs (observed 2026-06-14: zenjxl decode of 16-50 byte
# inputs flagged "OOM" at ~1.5 GB/fork but completing well under 2 GB single-
# process — three false zenjxl-decoder issues filed+closed). Fix the limit at
# 2 GB and derive forks so a genuine runaway (>2 GB on a fuzz input) still trips.
RSS_LIMIT_MB="${RSS_LIMIT_MB:-2048}"
MEM_TOTAL_MB="$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 8192)"
FORKS="${FORKS:-$(( (MEM_TOTAL_MB - 3072) / RSS_LIMIT_MB ))}"   # reserve ~3 GB for OS + build
[ "$FORKS" -lt 1 ] && FORKS=1
[ "$FORKS" -gt "$NPROC" ] && FORKS="$NPROC"
case "$(uname -m)" in
  aarch64|arm64) ARCH=arm64 ;;
  x86_64|amd64)  ARCH=x86_64 ;;
  *)             ARCH="$(uname -m)" ;;
esac
HOST="$(hostname -s 2>/dev/null || hostname)"

mkdir -p "$FUZZ_HOME"/{corpus,artifacts,logs,state}
RUNLOG="$FUZZ_HOME/logs/rotate.log"
log() { printf '%s [%s] %s\n' "$(date -u +%FT%TZ)" "$ARCH" "$*" | tee -a "$RUNLOG"; }

# ── R2 helpers ───────────────────────────────────────────────────────────────
# r2.env exports R2_ENDPOINT, R2_BUCKET, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
# and (for temp creds) AWS_SESSION_TOKEN. Sourced fresh each call so a refreshed
# credentials file is picked up without restarting the service.
r2_ready() { [ -f "$R2_ENV" ]; }
s5() {
  set -a; . "$R2_ENV"; set +a
  AWS_REGION=auto s5cmd --endpoint-url "$R2_ENDPOINT" "$@"
}
r2_pull_corpus() { # <r2-key> <localdir>
  r2_ready || return 0
  mkdir -p "$2"
  s5 cp "s3://$R2_BUCKET/corpus/$1/*" "$2/" >/dev/null 2>&1 || true
}
r2_push_corpus() { # <r2-key> <localdir>
  r2_ready || return 0
  s5 sync "$2/" "s3://$R2_BUCKET/corpus/$1/" >/dev/null 2>&1 || true   # additive
}

# ── crash capture ─────────────────────────────────────────────────────────────
# Reproduce a single crashing input once to extract a stable dedup signature
# (panic / sanitizer / libFuzzer line), then upload the raw repro + metadata to
# R2 (namespaced by arch). The workstation triage maps crate_rel -> GitHub repo
# from its own local tree and files deduplicated issues — the box stays
# GitHub-credential-free.
handle_crash() { # <crate_dir> <target> <r2-key> <rel> <artifact-file>
  local crate_dir="$1" target="$2" key="$3" rel="$4" art="$5"
  local repro_log; repro_log="$(mktemp)"
  ( cd "$crate_dir" && timeout 120 cargo +nightly fuzz run "$target" "$art" \
      -- -runs=1 -timeout="$FUZZ_TIMEOUT" -rss_limit_mb="$RSS_LIMIT_MB" ) \
      >"$repro_log" 2>&1 || true

  local art_name; art_name="$(basename "$art")"
  # Signature → dedup key. Resource artifacts (oom/leak/timeout) rarely capture a
  # stable panic line on -runs=1 replay, so a per-input signature would file one
  # issue per input for what is almost always a single bug (e.g. "huge dimensions
  # → unbounded alloc"). Use a COARSE per-target signature for those so they
  # collapse to one issue; keep a FINE panic/sanitizer signature for crashes.
  local sig
  case "$art_name" in
    oom-*)                 sig="out-of-memory (libFuzzer rss limit) in $target" ;;
    leak-*)                sig="memory leak in $target" ;;
    timeout-*|slow-unit-*) sig="timeout / slow-unit in $target" ;;
    *) sig="$(grep -m1 -E "panicked at|ERROR: libFuzzer:|SUMMARY: |ERROR: AddressSanitizer|thread '.*' panicked" "$repro_log" 2>/dev/null \
            | sed -E 's/0x[0-9a-fA-F]+/0xADDR/g' | tr -s ' ' | head -c 200)"
       [ -n "$sig" ] || sig="$art_name" ;;
  esac
  local sig_hash; sig_hash="$(printf '%s\n%s\n%s' "$rel" "$target" "$sig" | sha256sum | cut -c1-16)"
  local meta="$FUZZ_HOME/state/meta-$sig_hash.json"

  REL="$rel" TARGET="$target" ARCHV="$ARCH" HOSTV="$HOST" KEY="$key" \
  ART="$art_name" SH="$sig_hash" SIG="$sig" RL="$repro_log" \
  python3 - "$meta" <<'PY' 2>/dev/null || \
    printf '{"crate_rel":"%s","target":"%s","arch":"%s","sig_hash":"%s","artifact":"%s","corpus_key":"%s","signature":"%s"}\n' \
      "$rel" "$target" "$ARCH" "$sig_hash" "$art_name" "$key" "$sig" > "$meta"
import json,os,sys
trace=""
try:    trace=open(os.environ["RL"]).read()[-4000:]
except Exception: pass
json.dump({
  "crate_rel":os.environ["REL"],"target":os.environ["TARGET"],"arch":os.environ["ARCHV"],
  "host":os.environ["HOSTV"],"corpus_key":os.environ["KEY"],"artifact":os.environ["ART"],
  "sig_hash":os.environ["SH"],"signature":os.environ["SIG"],"trace":trace,
}, open(sys.argv[1],"w"), indent=1)
PY

  log "CRASH $rel :: $target [$ARCH] sig=$sig_hash ($sig)"
  if r2_ready; then
    local r2dir="s3://$R2_BUCKET/crashes/$key/$ARCH/$sig_hash"
    s5 cp "$art"       "$r2dir/$art_name" >/dev/null 2>&1 || true
    s5 cp "$meta"      "$r2dir/meta.json" >/dev/null 2>&1 || true
    s5 cp "$repro_log" "$r2dir/repro.txt" >/dev/null 2>&1 || true
  fi
  rm -f "$repro_log"
}

# ── discovery ──────────────────────────────────────────────────────────────────
# Prefer the canonical allow-list ($FUZZ_HOME/crates.list): one crate relpath per
# line. Falls back to a filtered scan that skips agent worktrees, vendored code,
# and scratch/worktree copies. Either way, only crates whose fuzz/Cargo.toml uses
# libfuzzer-sys are kept (so the AFL crate is excluded). Emits "crate_dir<TAB>target".
emit_targets() { # <crate_dir>
  local crate_dir="$1" t
  [ -d "$crate_dir/fuzz/fuzz_targets" ] || return 0
  grep -q 'libfuzzer-sys' "$crate_dir/fuzz/Cargo.toml" 2>/dev/null || return 0
  # Authoritative target list = registered [[bin]] entries via `cargo fuzz list`,
  # NOT a *.rs glob — globbing picks up orphan/template files (e.g. heic's stray
  # fuzz_target_1.rs) that aren't bin targets and fail `cargo fuzz build`.
  while IFS= read -r t; do
    [ -n "$t" ] && printf '%s\t%s\n' "$crate_dir" "$t"
  done < <(cd "$crate_dir" && cargo +nightly fuzz list 2>/dev/null)
}
discover() {
  local list="${CRATES_LIST:-$FUZZ_HOME/crates.list}" rel ftdir crate_dir
  if [ -f "$list" ]; then
    while IFS= read -r rel; do
      rel="${rel%%#*}"; rel="$(printf '%s' "$rel" | tr -d '[:space:]')"
      [ -n "$rel" ] && emit_targets "$ZEN_ROOT/$rel"
    done < "$list"
  else
    while IFS= read -r ftdir; do
      case "$ftdir" in
        */.claude/*|*/vendor/*|*/worktrees/*|*/_*/*|*--*|*-perm-corpus/*|*-head-test/*) continue ;;
      esac
      emit_targets "${ftdir%/fuzz/fuzz_targets}"
    done < <(find "$ZEN_ROOT" -type d -path '*/fuzz/fuzz_targets' 2>/dev/null)
  fi
}

fuzz_one() { # <crate_dir> <target>
  local crate_dir="$1" target="$2"
  local rel="${crate_dir#$ZEN_ROOT/}"
  local key="$rel/$target"
  local corpus="$FUZZ_HOME/corpus/$key"
  local artdir="$FUZZ_HOME/artifacts/$key/"
  mkdir -p "$corpus" "$artdir"

  local dict_arg=""
  for d in "$crate_dir"/fuzz/multiformat.dict "$crate_dir"/fuzz/*.dict; do
    [ -f "$d" ] && { dict_arg="-dict=$d"; break; }
  done

  r2_pull_corpus "$key" "$corpus"

  local tlog="$FUZZ_HOME/logs/$(echo "$key" | tr '/' '_').log"
  # Build FIRST, outside the fuzz slice — a cold build of a heavy crate can take
  # many minutes; only a generous hang-guard caps it. Skip a target that won't
  # build (logged, retried next pass when source may have been re-synced).
  if ! ( cd "$crate_dir" && timeout 1800 cargo +nightly fuzz build "$target" ) >>"$tlog" 2>&1; then
    log "  build failed/skipped: $rel :: $target (tail $(basename "$tlog"))"
    return 0
  fi

  local marker; marker="$(mktemp)"; touch "$marker"
  log "fuzz $rel :: $target  (${SLICE_SECS}s, fork=$FORKS@${RSS_LIMIT_MB}MB${dict_arg:+, $(basename "${dict_arg#-dict=}")})"
  # Only the FUZZING is time-boxed (libFuzzer self-stops at -max_total_time; the
  # timeout is a backstop). The build above is already cached, so this starts fast.
  ( cd "$crate_dir" && timeout $((SLICE_SECS + 60)) \
      cargo +nightly fuzz run "$target" "$corpus" -- \
        -fork="$FORKS" -ignore_crashes=1 -ignore_ooms=1 -ignore_timeouts=1 \
        -max_total_time="$SLICE_SECS" -rss_limit_mb="$RSS_LIMIT_MB" \
        -timeout="$FUZZ_TIMEOUT" -artifact_prefix="$artdir" $dict_arg \
  ) >>"$tlog" 2>&1 || true

  # new artifacts since the marker → crashes
  local art
  while IFS= read -r art; do
    [ -f "$art" ] || continue
    case "$(basename "$art")" in
      crash-*|oom-*|leak-*|timeout-*|slow-unit-*)
        handle_crash "$crate_dir" "$target" "$key" "$rel" "$art" ;;
    esac
  done < <(find "$artdir" -type f -newer "$marker" 2>/dev/null)
  rm -f "$marker"

  r2_push_corpus "$key" "$corpus"
}

# ── main loop ──────────────────────────────────────────────────────────────────
log "=== fuzz-rotate start: arch=$ARCH host=$HOST nproc=$NPROC forks=$FORKS rss=${RSS_LIMIT_MB}MB slice=${SLICE_SECS}s root=$ZEN_ROOT ==="
if r2_ready; then set -a; . "$R2_ENV"; set +a; log "R2 enabled: s3://$R2_BUCKET via $R2_ENDPOINT"
else log "R2 DISABLED (no $R2_ENV) — corpus + crashes stay box-local only"; fi

pass=0
while :; do
  pass=$((pass + 1))
  mapfile -t work < <(discover | shuf)
  if [ "${#work[@]}" -eq 0 ]; then
    log "no fuzz targets under $ZEN_ROOT — sleeping 300s"; sleep 300; continue
  fi
  log "=== pass $pass: ${#work[@]} targets ==="
  for line in "${work[@]}"; do
    IFS=$'\t' read -r crate_dir target <<<"$line"
    [ -d "$crate_dir" ] || continue
    fuzz_one "$crate_dir" "$target"
  done
  log "=== pass $pass complete ==="
done
