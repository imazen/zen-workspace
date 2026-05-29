#!/bin/bash
# Parallel fuzzing sweep across the zen ecosystem
# Usage: ./fuzz-sweep.sh <seconds_per_target> <parallel_jobs>
# Example: ./fuzz-sweep.sh 120 16   (2 min per target, 16 parallel)

set -euo pipefail

SECONDS_PER=${1:-120}
JOBS=${2:-16}
LOGDIR="/tmp/fuzz-sweep-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOGDIR"

echo "=== Fuzz sweep: ${SECONDS_PER}s per target, $JOBS parallel ==="
echo "Logs: $LOGDIR"
echo "Started: $(date)"

# Discover all fuzz targets
declare -a TARGETS=()
for repo in ~/work/zen/*/; do
    # Direct fuzz targets
    if [ -d "$repo/fuzz/fuzz_targets" ]; then
        for t in "$repo"/fuzz/fuzz_targets/*.rs; do
            [ -f "$t" ] || continue
            target=$(basename "$t" .rs)
            TARGETS+=("$repo|$target")
        done
    fi
    # Nested crate fuzz targets (zenjpeg/zenjpeg/, zenjxl-decoder/zenjxl-decoder/, etc.)
    for sub in "$repo"/*/fuzz/fuzz_targets; do
        if [ -d "$sub" ]; then
            subdir=$(dirname $(dirname "$sub"))
            for t in "$sub"/*.rs; do
                [ -f "$t" ] || continue
                target=$(basename "$t" .rs)
                TARGETS+=("$subdir|$target")
            done
        fi
    done
done

echo "Found ${#TARGETS[@]} targets"

# Run targets in parallel batches
run_target() {
    local entry="$1"
    local repo="${entry%%|*}"
    local target="${entry##*|}"
    local name=$(basename "$repo")
    local logfile="$LOGDIR/${name}_${target}.log"
    local crashdir="$LOGDIR/${name}_${target}_crashes"

    mkdir -p "$crashdir"

    # Find dictionary if available
    local dict_flag=""
    local dict=$(find "$repo" -maxdepth 3 -name "*.dict" -path "*/fuzz/*" 2>/dev/null | head -1)
    if [ -n "$dict" ]; then
        dict_flag="-dict=$dict"
    fi

    # Find corpus dir
    local corpus_flag=""
    local corpus="$repo/fuzz/corpus/$target"
    if [ -d "$corpus" ]; then
        corpus_flag="$corpus"
    fi

    echo "[START] $name/$target (dict: $(basename "${dict:-none}"), corpus: $([ -d "${corpus:-/nonexistent}" ] && echo "yes" || echo "no"))"

    # Run fuzzer with timeout, capture crashes
    cd "$repo"
    timeout $((SECONDS_PER + 30)) cargo +nightly fuzz run "$target" \
        -- -max_total_time="$SECONDS_PER" \
        -artifact_prefix="$crashdir/" \
        $dict_flag \
        -jobs=1 -workers=1 \
        -print_final_stats=1 \
        $corpus_flag \
        > "$logfile" 2>&1 || true

    # Check for crashes
    local crashes=$(find "$crashdir" -type f 2>/dev/null | wc -l)
    if [ "$crashes" -gt 0 ]; then
        echo "[CRASH] $name/$target — $crashes crashes found!"
    else
        # Check log for panics/errors
        if grep -q "SUMMARY: libFuzzer: deadly signal\|panicked at\|ERROR: libFuzzer" "$logfile" 2>/dev/null; then
            echo "[ERROR] $name/$target — see $logfile"
        else
            local execs=$(grep -oP 'stat::number_of_executed_units:\s*\K\d+' "$logfile" 2>/dev/null | tail -1)
            echo "[OK]    $name/$target — ${execs:-?} executions"
        fi
    fi
}

export -f run_target
export SECONDS_PER LOGDIR

printf '%s\n' "${TARGETS[@]}" | xargs -P "$JOBS" -I{} bash -c 'run_target "$@"' _ {}

echo ""
echo "=== Sweep complete: $(date) ==="
echo "Crashes:"
find "$LOGDIR" -name "*_crashes" -type d ! -empty -exec sh -c 'echo "  $(basename {}): $(ls {} | wc -l) files"' \;
echo "Logs: $LOGDIR"
