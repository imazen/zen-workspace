# Picker + Sweep Handoff — 2026-05-06

State summary as of session end. For day-to-day operations consult the
per-repo CLAUDE.md files cross-referenced below.

## TL;DR — what shipped this session

1. **lz77-vs-RLE empirical decision:** keep `lz77=True` as zenjxl
   encoder default. RLE matches LZ77 on photos but regresses synthetic
   gradients 100-389%. Full report: `zenjxl/benchmarks/lz77_vs_rle_v07_2026-05-06.md`.
2. **Public docker training image** (`ghcr.io/imazen/zen-train:0.1.2`)
   verified end-to-end. Cloud `picker_multi` reproduces local champion
   byte-exact (-1.879% bytes / +0.402 zensim).
3. **Sweep fleet rationalized.** Killed 192 of 200 idle vast.ai
   instances ($19.69/hr → $1.20/hr); cleared 140 stale claim files;
   8 survivors now finishing the last 7 chunks across v08/v09/v11.
4. **v07 winner identified:** `patches=True` is the dominant Pareto
   knob (42 of 117 v07-beats-v06 cells); `gaborish=False` second.
5. **Picker champion (v06 sweep):** `zensim_mask_histgb` at -1.879%
   bytes / +0.402 zensim with 62.8% default-rate.

## Active sweeps (status as of 2026-05-06 02:30 UTC)

| Sweep | R2 chunks | Total | Workers kept | Notes |
|---|---:|---:|---:|---|
| v06 | 198 | ~200 | 0 | DONE |
| v07 | 34 | 34 | 0 | DONE |
| v08 | 98 | 100 | 2 | 98% — 2 chunks left after claim-clear |
| v09 | 17 | 21 | 3 | 81% — 4 chunks left after claim-clear |
| v10 | 60 | 60 | 0 | DONE — multi-codec (zenjxl/avif/webp) |
| v11 | 19 | 20 | 2 | 95% — 1 chunk left after claim-clear |
| smoketest | — | — | 0 | destroyed after success |

Burn rate: ~$1.20/hr (was $19.69/hr before kill).

## Pending pickers to train

User confirmed (just before session pause) to kick off four
partial-data picker trainings on local box. Data downloaded to
`~/sweep-data/v0X/`; concatenated TSVs ready for v09/v11/v10 codecs.

| Picker | Data | Script | Status |
|---|---|---|---|
| v10 multi-codec router | 60/60 | `~/sweep-data/picker_v10_multicodec.py` (NEW) | Not yet run |
| v08 (v06 grid + v07 winners) | 98/100 | `~/sweep-data/picker_v06_v08_union.py` (existing) | Not yet run |
| v11 per-distance-band | 19/20 | `picker_v06_multi.py zenjxl_v11.tsv` | Not yet run |
| v09 force_strategy | 17/21 | `picker_v06_multi.py zenjxl_v09.tsv` | Not yet run |

All four train on this box (sklearn) in <10 min each. Expected outputs
land in `/tmp/picker_*_report.md`; commit promising ones to
`~/work/zen/zenanalyze/benchmarks/`.

## Where docs landed

| Repo | File | Purpose |
|---|---|---|
| zen-train-docker | `CLAUDE.md` (NEW) | Cloud training ops, 0.1.0/0.1.1/0.1.2 bug history, GHCR auth recipe |
| zen-train-docker | `README.md` | Updated to point at 0.1.2 + smoke test result |
| zenjxl | `benchmarks/INDEX.md` (NEW) | Catalog of every benchmark report; encoder default decisions; picker lineage |
| zenjxl | `benchmarks/lz77_vs_rle_v07_2026-05-06.md` (NEW) | Full lz77 finding writeup |
| turbo-metrics | `scripts/sweep/CLAUDE.md` (NEW) | Sweep operations: cgroup parallelism, vastai quirks, claim recovery, cost control |
| sweep-data | `NOTES.md` (NEW) | Local-dir layout + recovery recipes (R2 download, concatenation, training) |
| zen-workspace | `PICKER-SWEEP-HANDOFF-2026-05-06.md` (this file) | Session handoff |

## Repo branch state (caveats)

- **zenjxl:** detached-HEAD picker chain pre-existed from prior
  sessions. New work pushed to branch `bench/picker-lineage-and-lz77`
  (commit `a21f986` builds on `91af553` `4482847` `74464a9`). Main
  is at `7fa18ef` and ahead via different topology — not merged.
- **turbo-metrics:** new sweep ops doc committed locally at `903052f`
  on detached HEAD; **push blocked** by pre-push `cargo fmt` hook
  failing on UNRELATED code. User should resolve the unrelated fmt
  issue before pushing this commit.
- **zen-train-docker:** new commits on main (`42dbc35`); not yet pushed.
- **zenanalyze:** prior session commits pre-existed; nothing new from
  this session.

## Key recovery commands

```bash
# Check sweep progress
set -a; source ~/.config/cloudflare/r2-credentials; set +a
for s in sweep-v08 sweep-v09 sweep-v10 sweep-v11; do
  n=$(AWS_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY \
    aws --endpoint-url "https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com" \
    s3 ls s3://zentrain/${s}-2026-05-05/ --recursive | grep -c '\.tsv$')
  echo "$s: $n .tsv files"
done

# Check vast.ai burn
vastai show instances --raw | python3 -c "
import json,sys
d=json.loads(sys.stdin.read()); insts = d if isinstance(d, list) else d.get('instances', [])
total = sum(i.get('dph_total') or 0 for i in insts)
print(f'instances: {len(insts)}, burn: \${total:.2f}/hr (\${total*24:.2f}/day)')"

# Train a picker on partial data
cd ~/sweep-data
python3 picker_v06_multi.py zenjxl_v06.tsv /tmp/picker_v06_report.md

# Launch a cloud training run
export VAST_API_KEY=$(cat ~/.config/vastai/vast_api_key)
source ~/.config/cloudflare/r2-credentials
export ZEN_DATASET_CSV=s3://zentrain/datasets/zenjxl_v06.tsv
export ZEN_ZENANALYZE_TSV=s3://zentrain/features/zenjxl_features_v04full_2026-05-04.tsv
RUN_ID="train-$(date -u +%Y%m%d-%H%M%S)"
bash ~/work/zen/zen-train-docker/scripts/launch_vastai.sh picker_multi $RUN_ID --raw
```

## Open questions / next-step suggestions

1. **Run the four partial-data pickers** (user confirmed; just hadn't
   kicked off when pivoted to lz77 question + this docs pass).
2. **Extend lz77 sweep to e0–e4.** Current data covers only e5/e7/e9.
   RLE may dominate at low effort; would inform whether `lz77=True`
   should be effort-conditional.
3. **Watch the 8 surviving sweep workers.** With claims cleared they
   should pick up the last 7 chunks within one chunk-cycle (~5h).
   If R2 still shows no new uploads after that, debug per-worker.
4. **Decoder-bug attribution:** zenjxl-decoder rejects some files
   `djxl 0.10.3` (libjxl C) accepts. **libjxl is the authority, not
   jxl-oxide.** Tracked separately; not this session's scope.
5. **Rebalance pipeline (task #20):** still in progress. Will inform
   the next zensim training round on rebalanced corpus.
