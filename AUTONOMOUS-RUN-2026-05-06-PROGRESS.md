# Autonomous picker/zensim work — 2026-05-06 (~1h11m in, 10h budget)

Live progress doc. Updated as findings land.

## Headline numbers (verified by simulation on v06 holdout)

**End-to-end Pareto move** vs current shipped v0.6 picker: **−5pp better mean bytes** (was +1.7%, now −3.3%):

| Class | n | v0.6 default Δ | v0.7b alone Δ | v0.7b + per-class encoder rule Δ |
|---|---:|---:|---:|---:|
| photo | 1162 | 0% | −1.12% | −1.11% |
| lineart | 56 | 0% | −3.85% | **−4.84%** |
| screen | 70 | 0% | 0% (gated) | **−5.90%** |
| synthetic | 70 | 0% | 0% | **−14.71%** |
| **OVERALL** | **1358** | 0% | −0.95% | **−3.32%** |

Baseline-relative move (vs current shipped v0.6 with hidden +41% screen regression) is even larger.

## What's shipped (committed) so far

### Security fixes (jxl-encoder)
- ✅ PR #30 MERGED: LZ77 + patches.rs OOB index DoS fixes (find_matches window_mask, BFS bounds check)
- ✅ Tracking issue #31 with reproduction trigger image
- ⏳ jxl-encoder 0.3.2 release (cargo publish) — not blocking; using `[patch.crates-io]` git ref

### Sweep infrastructure (zenmetrics)
- ✅ PR #1, #2, #3 MERGED:
  - mid-chunk flush sidecar (60s interval, max 60s loss per worker death)
  - CHUNK_SIZE=2 (was 25)  
  - cfg_attr-guarded reference/distorted unused-variable warnings
  - `[patch.crates-io]` for jxl-encoder DoS fix
  - Dockerfile.sweep with 3-stage build (rust:1.93 → helpers → runtime)
- ✅ Image pushed: `ghcr.io/imazen/zen-metrics-sweep:0.6.1` (250 MB, GHCR)
  - **Visibility currently private**; needs manual web-UI flip OR pull via `vastai create instance --login`
- 🆕 PR #4 OPEN: v12 balanced unified-codec sweep launcher

### Per-class findings (committed)
- ✅ `zenjxl/benchmarks/lz77_vs_rle_v07_2026-05-06.md` — keep `lz77=True` (RLE regresses synthetic 100-389%)
- ✅ `zenjxl/benchmarks/patches_per_class_v07_2026-05-06.md` — `patches=True` saves -7.7% on screens, free elsewhere
- ✅ `zenjxl/benchmarks/per_class_encoder_rule_v07_v08_2026-05-06.md` — rule for per-class encoder defaults
- ✅ `zenanalyze/benchmarks/picker_v06_per_class_audit_2026-05-06.md` — found +41% bytes regression on screen
- ✅ `zenanalyze/benchmarks/picker_v0.7_lineage_2026-05-06.md` — v0.7b methodology
- ✅ `zenanalyze/benchmarks/end_to_end_pareto_simulation_2026-05-06.md` — combined -3.32% Pareto move

### Baked artifacts (ZNPR v3, ready to ship)
| File | Size | Purpose |
|---|---:|---|
| `zenanalyze/benchmarks/zenjxl_picker_v0.6_mlp_2026-05-06.bin` | 65 KB | MLP zensim_mask champion |
| `zenanalyze/benchmarks/zenjxl_picker_v0.7b_2026-05-06.bin` | 67 KB | v0.7b — cclass-aware + screen gate |
| `zenanalyze/benchmarks/zenpicker_meta_v0.1_2026-05-06.bin` | 24 KB | First baked meta-picker (3-family) |
| `zenanalyze/benchmarks/content_classifier_v0.2_2026-05-06.bin` | 8 KB | 99.6% acc 4-class classifier |

All 4 inspect cleanly via `zenpredict-inspect`. PR #73 open on zenanalyze with all this work.

## In flight (this run)

| Task | ETA | Status |
|---|---|---|
| v12 sweep (50 workers, 200 imgs × 3 codecs, ~600 chunks) | 30-45 min | 30 running, 18 loading, 2 created |
| V0_6 baseline (zensim) on rebalanced corpus | ~25 min | 70% feature extract |
| V0_6 cclass (zensim) on rebalanced corpus | ~24 min | 70% feature extract |
| V0_6 FiLM | (chained, after baseline+cclass) | queued |
| V0_6 MoE | (chained) | queued |

Burn rate: ~$5/hr on vast.ai.

## Manual actions blocking shipping

1. **GHCR visibility flip** for `imazen/zen-metrics-sweep` (web UI). Currently using `--login` with GH token as a workaround.
2. **jxl-encoder 0.3.2 cargo publish** (low-priority; `[patch.crates-io]` works fine).
3. **PR review/merge** for: zenanalyze#73 (picker artifacts), zenmetrics#4 (v12 launcher).

## Remaining (post-this-run)

- Wire baked .bins into codec crates as include_bytes!() defaults (task #36)
- Implement content-class gate at zenjxl encoder API (task #37)
- Implement per-class encoder rule (task #38)
- 6-family meta-picker (need jpeg/png/gif sweep coverage; task #39)
- Ship content classifier v0.2 in zenanalyze runtime (task #40)
- Pick zensim champion from V0_6 baseline/cclass/FiLM/MoE results once trainings finish (task #33)

## Lessons learned

- **vast.ai's `--image` mode skips ENTRYPOINT**; need `--onstart-cmd` explicitly. Same gotcha as zen-train smoke test.
- **vast.ai supports `--login '-u USER -p TOKEN registry'`** for private images; can sidestep visibility flip.
- **zen-metrics sweep CLI uses kebab-case metric names** (`ssim2-gpu` not `ssim2_gpu`). Workers fail every chunk if jobspec uses snake_case. Cost me a worker round-trip (~5 min).
- **Photo-dominated training corpora hide regressions**. The shipped v0.6 picker headline -1.879% bytes masked a +41.4% regression on screen content. Per-class breakdowns are mandatory for picker training reports.
- **Excluding a class from training + runtime gating beats trying to learn the class from photo-majority data**. v0.7b vs v0.7: same architecture, screen-included training added information but didn't fix screen (+50% bytes). Excluding screen from training + hard-routing at inference (v0.7b) drops screen to 0%.
- **`patches=True` is a free Pareto win on screens** but neutral elsewhere. Should be class-conditional in encoder defaults.
