#!/usr/bin/env bash
# fuzz-nightly.sh — Run all zen* fuzz targets nightly.
#
# Each target gets DURATION seconds (default 300 = 5 min).
# Total runtime: ~57 targets × 5 min ≈ 4.75 hours.
#
# Logs to /tmp/fuzz-nightly-YYYY-MM-DD.log
# New crashes/OOMs go to each crate's fuzz/artifacts/ directory.

set -eo pipefail

DURATION="${1:-300}"
DATE=$(date +%Y-%m-%d)
LOG="/tmp/fuzz-nightly-${DATE}.log"
SUMMARY="/tmp/fuzz-nightly-${DATE}-summary.txt"

echo "=== Nightly fuzz run: $DATE, ${DURATION}s per target ===" | tee "$LOG"
echo "" >> "$LOG"

TOTAL_TARGETS=0
TOTAL_CRASHES=0
TOTAL_OOMS=0
FAILED_BUILDS=0

fuzz_crate() {
    local crate_dir="$1"
    local crate_name=$(basename "$crate_dir")

    echo "━━━ $crate_name ━━━" | tee -a "$LOG"

    cd "$crate_dir"

    # Build first
    if ! cargo +nightly fuzz build >> "$LOG" 2>&1; then
        echo "  BUILD FAILED — skipping" | tee -a "$LOG"
        FAILED_BUILDS=$((FAILED_BUILDS + 1))
        return
    fi

    # Count artifacts before
    local before_crashes=$(find fuzz/artifacts -name "crash-*" -type f 2>/dev/null | wc -l)
    local before_ooms=$(find fuzz/artifacts -name "oom-*" -type f 2>/dev/null | wc -l)

    # Run each target
    for target in $(cargo +nightly fuzz list 2>/dev/null); do
        TOTAL_TARGETS=$((TOTAL_TARGETS + 1))
        echo -n "  $target (${DURATION}s)... " | tee -a "$LOG"

        # Find best corpus dir
        local corpus_dir=""
        if [ -d "fuzz/corpus/seed/mixed" ]; then
            corpus_dir="fuzz/corpus/seed/mixed"
        elif [ -d "fuzz/corpus/seed" ]; then
            corpus_dir="fuzz/corpus/seed"
        elif [ -d "fuzz/corpus/$target" ]; then
            corpus_dir="fuzz/corpus/$target"
        fi

        # Find dict
        local dict_arg=""
        for dict in fuzz/multiformat.dict fuzz/*.dict; do
            if [ -f "$dict" ]; then
                dict_arg="-dict=$dict"
                break
            fi
        done

        # Run (allow failure — crashes are expected findings, not errors)
        if cargo +nightly fuzz run "$target" $corpus_dir -- $dict_arg -max_total_time="$DURATION" >> "$LOG" 2>&1; then
            echo "ok" | tee -a "$LOG"
        else
            local exit_code=$?
            case $exit_code in
                77) echo "CRASH" | tee -a "$LOG" ;;
                71) echo "OOM" | tee -a "$LOG" ;;
                *)  echo "exit=$exit_code" | tee -a "$LOG" ;;
            esac
        fi
    done

    # Count new artifacts
    local after_crashes=$(find fuzz/artifacts -name "crash-*" -type f 2>/dev/null | wc -l)
    local after_ooms=$(find fuzz/artifacts -name "oom-*" -type f 2>/dev/null | wc -l)
    local new_crashes=$((after_crashes - before_crashes))
    local new_ooms=$((after_ooms - before_ooms))

    if [ "$new_crashes" -gt 0 ] || [ "$new_ooms" -gt 0 ]; then
        echo "  ⚠ NEW: $new_crashes crashes, $new_ooms OOMs" | tee -a "$LOG"
    fi

    TOTAL_CRASHES=$((TOTAL_CRASHES + new_crashes))
    TOTAL_OOMS=$((TOTAL_OOMS + new_ooms))
    echo "" >> "$LOG"
}

# All zen crates with fuzz targets
fuzz_crate /home/lilith/work/zen/zencodecs
fuzz_crate /home/lilith/work/zen/zenjpeg/zenjpeg
fuzz_crate /home/lilith/work/zen/zenpng
fuzz_crate /home/lilith/work/zen/zengif
fuzz_crate /home/lilith/work/zen/zenwebp
fuzz_crate /home/lilith/work/zen/zenavif
fuzz_crate /home/lilith/work/zen/zenavif-parse
fuzz_crate /home/lilith/work/zen/zenjxl-decoder/zenjxl-decoder
fuzz_crate /home/lilith/work/zen/heic
fuzz_crate /home/lilith/work/zen/rav1d-safe
fuzz_crate /home/lilith/work/zen/zenbitmaps
fuzz_crate /home/lilith/work/zen/zenflate
fuzz_crate /home/lilith/work/zen/zenzstd
fuzz_crate /home/lilith/work/zen/zenrav1e
fuzz_crate /home/lilith/work/zen/image-tiff

# imageflow (on fuzz-setup branch, uses --fuzz-dir)
echo "━━━ imageflow ━━━" | tee -a "$LOG"
cd /home/lilith/work/imageflow
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "fuzz-setup" ]; then
    git stash -q 2>/dev/null || true
    git checkout fuzz-setup -q 2>/dev/null || {
        echo "  SKIP: fuzz-setup branch not found" | tee -a "$LOG"
    }
fi
if [ "$(git branch --show-current)" = "fuzz-setup" ]; then
    for target in fuzz_decode fuzz_transcode fuzz_pipeline; do
        TOTAL_TARGETS=$((TOTAL_TARGETS + 1))
        echo -n "  $target (${DURATION}s)... " | tee -a "$LOG"
        if cargo +nightly fuzz run --fuzz-dir fuzz "$target" -- -max_total_time="$DURATION" >> "$LOG" 2>&1; then
            echo "ok" | tee -a "$LOG"
        else
            case $? in
                77) echo "CRASH" | tee -a "$LOG" ;;
                71) echo "OOM" | tee -a "$LOG" ;;
                *)  echo "exit=$?" | tee -a "$LOG" ;;
            esac
        fi
    done
    git checkout "$CURRENT_BRANCH" -q 2>/dev/null || true
    git stash pop -q 2>/dev/null || true
fi

# Sync new artifacts to block storage
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$SCRIPT_DIR/fuzz-sync.sh" ]; then
    echo "Syncing fuzz state to /mnt/v/fuzzes/ ..." | tee -a "$LOG"
    "$SCRIPT_DIR/fuzz-sync.sh" push >> "$LOG" 2>&1 || echo "  sync failed (mount missing?)" | tee -a "$LOG"
fi

# Summary
cat <<EOF | tee "$SUMMARY" | tee -a "$LOG"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
NIGHTLY FUZZ SUMMARY — $DATE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Targets run:    $TOTAL_TARGETS
Duration/target: ${DURATION}s
Build failures: $FAILED_BUILDS
New crashes:    $TOTAL_CRASHES
New OOMs:       $TOTAL_OOMS
Log:            $LOG
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
