# Zen image-stack experiments survey — 2026-05-17

Aggregate of 12 parallel Explore-agent reports covering the latest work branches across:
zenmetrics · zensim · zenpredict · zenpicker · zenanalyze · zentrain · zenjpeg · zenwebp · jxl-encoder/zenjxl-decoder/zenjxl · zenavif/zenrav1e/rav1d-safe/aom-decoder-rs/zenavif-parse/zenavif-serialize · zenfilters · zenfaces (zensally) · zenresize/zenquant/zenblend/zenpixels(+convert)/linear-srgb/garb/zenflate/zenzop · Python training pipelines · workspace-level docs.

All facts below are sourced from `git log`, in-repo docs, and on-disk runs. Where reports flag a divergence between memory and current source, the source wins. Section §6 lists those.

## 1. Snapshot per stack

| Stack | Cutting-edge branch / commit | One-line state |
|---|---|---|
| **zenmetrics** | `master`, HEAD `6d260de` (2026-05-17) + 14 unpushed commits | Phase 4 (`compute_handles` + zenmetrics-api umbrella) queued; IW-SSIM 1.17M-pair backfill ready to launch; v16 cross-codec sweep still blocked on docker dlopen |
| **zensim** | `main`, HEAD `bf4a1e8` (2026-05-17) — T11.20b cycle | `V_22-mix+konjnd@0.10` ship candidate breaks CID22↔KonJND trade (CID22 0.7986 ± 0.0084 / KonJND 0.9219); user gate pending |
| **zenpredict + zenpicker** | zenpredict 0.2.1 PUBLISHED (v3 + 5 stacked FeatureTransforms); zenpicker 0.1.0 unwired | v3 includes `output_specs / discrete_sets / sparse_overrides / feature_transforms` + multi-codec union schema (v3.2). Only zenwebp_picker_v0.1 actually wired in production |
| **zenanalyze + zentrain** | main HEAD 2026-05-17; `feat/dense-percentiles` quarantined | 102 active feature IDs (memory said 90 dense extras are on a *quarantined* branch — not merged). v2/v3 picker bakes RETRACTED on zenjpeg/zenavif after multi-seed lock; only zenwebp v3_stable ships |
| **zenjpeg** | main `368f2ad6` (2026-05-04); active `diagnostics` worktree | Boundary-RD (Phase 4–5.5) validated on gb82, opt-in feature; per-class DQT signal probe; AQ controller scaffold queued; zensim-guided perceptual loop validated |
| **zenwebp** | main 2026-05-08, `fix/security-audit-2026-05-06` | Picker v0.3 (97 KB, q30-q90, −4.60% bytes, 87.1% win) ready to wire; v0.1 (138 KB) still embedded. Decoder 1.11× v1 → v2 streaming cache. High-q photo divergence (#50) repro tool in place |
| **jxl-encoder** | many heads; `--modular-predictor-wireup` just landed | At parity with cjxl-e7 on size + butteraugli; modular path 0.7% smaller on CLIC. **64 active jj worktrees**: CMYK, float16, HDR gainmap, chroma-subsampling, etc. GPU pipeline 2.5–11.8× but can't reach bitstream stage |
| **zenjxl-decoder** | main `0231975` (2026-05-17) | Stable / mature. Multi-arch SIMD complete. Latest is dependency bump + regression coverage |
| **AVIF stack** | zenavif `fd79a8d` (2026-05-04), zenrav1e `12b5c32f` (2026-05-06), rav1d-safe `05c65ef` (2026-05-05) | rav1d-safe pure-Rust 100% safe SIMD, 784/803 conformance. **aom-decoder-rs is maintenance-only** (35 days idle; 0/15 conformance, transform 2× error + chroma not wired) |
| **zenfilters + zensally** | zenfilters in `zenpipe` workspace v0.1.1 (81 filters, 34 LUT presets); zensally v0.1.0 (MicroSalNet v3ds 15.7 ms, F_β 0.652) | **Memory says 46 filters — actually 81 now.** FusedAdjust is 12 ops (not 10). Mobile saliency export not yet present |
| **Processing primitives** | zenresize `fix/const-generic-tap-dispatch`, zenpixels `feat/fast-gamut-refactor` + F16 add, zenflate `fix/streaming-backref-bounds`, linear-srgb on `9dcec51` detached | Active perf work on resize, pixels, flate. zenquant + zenzop stagnant (maintenance only) |
| **Python training** | zentrain `train_hybrid.py` 3,178 lines (2026-05-17); zensim/scripts/v_next/ 50 scripts PARKED | Phase 3 port (FiLM/MoE/cclass/dct_hf/magnitude-matching/sampler-bias) scaffolded, not started. V0_5 was 11.77% contaminated; V0_7 seed=1 is clean ship at CID22 0.8933 |
| **Workspace docs** | RECOVERY_PLAN_2026-05-08, RECOVERY_HANDOFF_2026-05-08, ARCHMAGE-AUDIT, FEATURE-FLAG-CLEANUP, gainmap-spec-status/ | Phase 0 done. Phase 1 (read/distill) done. Phase 2 (cherry-picks) partial. Phase 3 (zentrain port) is the critical-path gate |

## 2. Next experiments — priority table

Sorted by criticality. Effort and prereqs from the source reports.

| # | Stack | Experiment | Hypothesis / win condition | Effort | Prereqs / blockers |
|---|---|---|---|---|---|
| 1 | **zensim** | Ship `v22_mix_cv40_konjnd_0.1_s3_h128_packed` | KonJND 0.30→0.92 while CID22 within noise (−0.018 ± 0.008) | 0.5 d | User gate decision |
| 2 | **zenmetrics** | Push umbrella + compute_handles (chain 934844c + 2686687) + run single-box v16 smoke | Confirm Dockerfile builds, GPU score columns present in TSV. 5× per-pair-upload savings (~68 ms saved) | 1 d | Real-GPU host (not WSL2 snap-docker); push the 14 unpushed commits first |
| 3 | **zenmetrics** | Launch IW-SSIM backfill (1.17 M pairs) on vast.ai | Adds iwssim_imazen column to V_22-mix corpus | 4-12 h fleet time | Boot image + SWEEP_BIN_OVERRIDE patch ready; PINNED TASK update |
| 4 | **zenanalyze/zentrain** | Phase 3 port: FiLM/MoE/cclass/dct_hf/magnitude-matching/sampler-bias from Rust worktrees to `zensim_metric_train.py` | Unlocks ZNPR v3 publish + zenpredict 0.2.0 SemVer-clean ship | 1-2 d | None — scaffolding done |
| 5 | **zensim** | Triple-mix CVVDP + IWSSIM + ssim2_log (T11.23) at 0.4/0.4/0.2 | Closes KADID/TID regression vs pure-CVVDP while keeping CID22 > 0.86 | 1 d (single seed); 5 d (5-seed CI) | Waits on item 1 |
| 6 | **zenwebp** | Wire picker v0.3 (97 KB) into prod, replace embedded v0.1 (138 KB) | −4.60 % bytes, 87.1 % win, all bands ship | 0.5 d | Code integration only |
| 7 | **jxl-encoder GPU** | Port libjxl's `kAvoidEntropyOfTransforms` X-channel multi-block weight | Removes DCT32/64 over-selection band-aid (entropy_mul lift); fixes regression at d ≥ 1.5 | 2-3 d | Empirical `entropy_mul = base + scale · distance` fit |
| 8 | **jxl-encoder GPU** | Close GPU→CPU handoff: upstream jxl-encoder API to accept pre-quantized coefficients | Avoids redo-from-scratch; GPU pipeline reaches bitstream | 3-5 d | Spec change in encoder public API |
| 9 | **rav1d-safe** | Frame-threading (n_fc > 1) via COW pixel buffers or refcounted frame handles | Throughput scaling beyond tile-thread (n_tc) ceiling | 5+ d | Conflicting mutable/immutable refs on same buffer |
| 10 | **aom-decoder-rs** | Apply 2× transform normalization fix + wire chroma coefficient application + inter prediction | Move from 0/15 to N/15 conformance | 3-5 d for transforms; weeks for inter | Decide vs deprecate in favor of rav1d-safe |
| 11 | **zenfilters** | Lens Blur (depth-aware bokeh) | New filter; needs depth model integration | 3-5 d | Depth model via zentract |
| 12 | **zenfilters** | Regional tone mapping (per-region scene curves) | Close H=0.185 / C=0.162 regional gaps | 2 d | Saliency map (zensally) integration |
| 13 | **zensally** | YuNet INT8 quantize → ~175 KB | Smaller embedded footprint at iso-quality | 1 d | None |
| 14 | **zenpixels-convert** | Bench `convert_u16_rgb_simd_lutdec_polyenc` vs pure-poly on HDR thumbs | Expected +30–50 % on hot path; if true, enable by default | 0.5 d | None (stubs ready) |
| 15 | **zenflate** | Land Pigz-style parallel-gzip with GF(2) CRC matrix sync | Measured 3.1–3.4× on 4 T | 2 d | None |
| 16 | **zenresize** | AVX-512 `filter_v_row_i16` (32 i16 / iter vs 16) | Width-doubling on vertical pass | 1 d | Const-generic tap dispatch must land first |
| 17 | **zenmetrics** | Verify CVVDP parity gate (<0.10 JOD mean / <0.30 JOD max) on non-WSL2 box | Unblocks shipping `cvvdp_gpu_imazen_*` column | 0.5 d host time | Real-GPU access (snap-docker WSL2 has atomic<f32> panic) |
| 18 | **zenanalyze/zentrain** | Zenavif corpus expansion: 218 → 1 000+ val rows OR prune config grid 200 → < 150 | Currently 1.1 rows / config < 5-row safety floor | 1-2 d corpus; 0.5 d grid | Sweep budget |
| 19 | **zenpredict** | Multi-codec joint-picker bake (Predictor::predict_multi_codec is ready, no bake yet) | Joint trunk over 4-codec union features | 2 d | zentrain `--multi-codec-mode` flag |
| 20 | **zensim** | Per-band TV regularizer (B1 q [50,65) needs higher TV than B0/B3) | Closes V0_7 vs ssim2 −0.027 B1 gap | 1 d | None |

## 3. Adjust-and-rerun table

These are experiments where the original run had a methodology gap, single-seed verdict reversed by multi-seed, or a knob that needs broadening.

| # | Stack | Original experiment | What to adjust | Why |
|---|---|---|---|---|
| A1 | **zensim** | CVVDP+IWSSIM α-sweep at 0.40/0.50 (single-seed) | Run α ∈ {0.30, 0.40, 0.50, 0.60, 0.75} × 5 seeds | Single-seed verdicts reversed by 3-seed lock elsewhere; sensitivity to α undertested |
| A2 | **zensim** | KonJND weight w=0.10 (one point) | Run w ∈ {0.05, 0.08, 0.10, 0.12} × 3 seeds | Find true optimum of KonJND fix vs CID22 cost trade |
| A3 | **zensim** | V_22-IW v2 on TID: clips at 0.9617 | Run `bake_verdict --corpora tid` on PreviewV0_5 per-pair | Check for per-corpus scaling bias |
| A4 | **zenanalyze/zentrain** | zenavif v2 / zenjpeg v2 picker single-seed verdict (+1.65 / +3.74 pp) | Re-run on LOO-pruned features, then 3-seed multi-lock | Single-seed within stdev — both retracted |
| A5 | **zenjpeg** | Boundary-RD validated on gb82 (25 photos) only | Re-run on codec-corpus CID22 + diverse content, q70-q95 | Confirm generalization before merge to main |
| A6 | **zenjpeg** | Hybrid trellis λ=14.5 (single point) | Sweep λ ∈ [12, 16] on CID22/gb82 per Q | Find Q-dependent optimum |
| A7 | **zenjpeg** | Screenshot AQ gate (Phase 5.5 Run B) | Retrain `aq-mean/aq-std` thresholds on larger screenshot corpus | Generalization test |
| A8 | **zenwebp** | Picker v0.3 A/B on cid22-val (41 images) | Bigger external corpus A/B post-integration | Confirm out-of-distribution |
| A9 | **zenwebp** | Chroma-spatial classifier AUC 0.8587 | Retry with luma-structure or per-block chroma+luma interaction | Currently fails on colorful vector art |
| A10 | **jxl-encoder GPU** | Strat-search corpus regression (DCT32/64 band-aid) | Re-tune entropy_mul once libjxl X-channel weight ports | Proper fix vs current temporary lift |
| A11 | **zenrav1e + zenavif** | QM quality collapse claim (q95 76→49) | Re-run end-to-end encode-decode-zensim q70-q100 after `zenrav1e@30d37fc` | Verify fix landed end-to-end |
| A12 | **zenpredict** | i8/Lz4 quantization measured on 228→384→1 shape | Re-measure on production shapes (51→64→24 etc.) | Shape-dependent gain |
| A13 | **zenpredict** | LOO + warm-start stack (negative result) | Revisit with stacked feature-transforms (5 winners shipped) | New transforms may flip the verdict |
| A14 | **zenflate** | L1 instruction overhead (48 % vs C, 232 B stack frame) | Try `#[inline(never)]` on cold paths + explicit i16 hash table | Previous `HtMatchfinder` inline regressed +14.8 % |
| A15 | **linear-srgb** | f32 RGBA cross-tier FMA drift (~1 ULP) | Re-run Tango paired-bench under current LLVM | Verify bounds still hold |
| A16 | **zenpixels-convert** | CMS via `cms-moxcms` feature | Profile ICC parse+apply vs matrix-only on real sRGB↔P3 | If < 2 ms overhead, make default |
| A17 | **zensim** | V0_7 seed=1 ships (single winner from 5-seed) | Run 5 *more* seeds at (h=128, TV=10) on clean corpus | Confirm 5.46 % non-mono floor reproducible |
| A18 | **zenmetrics** | v16 cross-codec sweep | Single-box smoke before fleet relaunch; finalize corpus (canonical vs v15r) + codec grid | First attempt had empty score columns — root-cause before retrying |

## 4. Excluded directions — do NOT revive without strong cause

| Direction | Where flagged | Reason |
|---|---|---|
| **V_20b Su 2023 distortion manifold** | zensim | synth→authentic pre-train FALSIFIED on CID22 |
| **dssim supervised co-training** | zensim | 5 variants regressed CID22 0.04–0.07 — fundamentally opposed objective |
| **Linear-weights scaling (V0_1/V0_2)** | zensim | Plateaued at CID22 0.867–0.869; MLP wins by +0.020–0.025 consistently |
| **CID22 training-fold fine-tune** | zensim | PROHIBITED — CID22 is validation-only, 49 ref held-out is sacred |
| **dHash d ≤ 16 contamination quarantine** | zensim | 80 %+ false positives (UI screenshots, sky regions). Use d ≤ 10 + manual verify |
| **V0_5 inflated CID22 (0.8900)** | zensim | 11.77 % training contamination — exclude from comparisons |
| **HVS-feature augmenter in pickers** | zentrain | −6.14 / −2.27 / −2.39 pp across 3 codecs despite top screen rank |
| **Dense-percentiles 90 extra features merged to main** | zenanalyze | Quarantined (background-agent clobbers recorded); research-only |
| **zenjpeg v2 / zenavif v2 picker bakes** | zentrain | Single-seed verdicts within stdev; multi-seed invalidated — retracted |
| **Aggregate (KADID + TID + CID22) / 3 SROCC** | zentrain | Hides CID22 regressions; CID22 is gold standard, others integrity-only |
| **Synthetic ssim2-target val_srocc selection** | zentrain | Trainer's own loss > 0.99 does NOT predict held-out CID22 — must eval per-seed CID22 directly |
| **Parallel AQ (zenjpeg, 2026-01-17)** | zenjpeg | ~0.2 µs / block too fine for rayon; 5× slowdown |
| **AVX-512 dual-block DCT** | zenjpeg | 128-bit lane crossing in ZMM 2.3× slower than AVX2 8×8 |
| **Linear iteration for AC refinement** | zenjpeg | 83 % more mispredicts than bitmap-skip |
| **IDCT scaling** | zenjpeg | Poor quality, marginal speed gain — already removed |
| **Per-image DQT zero-bias seeding** | zenjpeg | Negative — global tables sufficient |
| **VP8 coefficient parsing branchless** | zenwebp | Eliminated 7.6 M branches but +37.4 M instructions net negative |
| **Token buffer staging in stack** | zenwebp | +1.4 M memset instructions net regression |
| **Loop filter AVX2 32-pixel batching** | zenwebp | Blocked by cross-MB write interference; dual cache required; complexity not worth ~5 % |
| **Threading in zenwebp decoder** | zenwebp | libwebp 2-thread pipeline is net negative (−37 % to −2 %) |
| **Burn convolution spike** | zenmetrics | 4.32× regression vs hand-written cubecl kernel — namespace reserved |
| **GPU entropy coder + bitstream assembly** | jxl-encoder | Bit-serial / branch-heavy — CPU SIMD wins |
| **Replacing CPU encoder in jxl-encoder-gpu** | jxl-encoder | Acceleration library only; bitstream stays CPU |
| **Splines default-on at e ≥ 8** | jxl-encoder | Zero perf benefit per 2026-05-15 bench despite lower butteraugli |
| **VAQ in zenrav1e** | AVIF | Consistently +2.8 % BD-rate worse — psy-tune already covers it |
| **Trellis quant in zenrav1e** | AVIF | +34 % encode time for 0.3 % BPP savings |
| **Per-SB delta-q / complex segmentation** | AVIF | Shifts operating point, not efficiency |
| **SVT-AV1 integration** | AVIF | Maintenance burden; zenrav1e proven |
| **AVX-512 paths in rav1d-safe** | AVIF | Diminishing returns vs AVX2 for still image |
| **CSNet / U2-Netp for saliency** | zensally | 360 ms / 1828 ms tract latency — too slow |
| **Octave convolutions + Resize for saliency** | zensally | 201 ms baseline — dilated blocks superior |
| **ImageMagick op-by-op compat layer** | zenfilters | Already done (10 ops, 95 %+ zensim agreement) — not a roadmap item |
| **garb extraction local reimpl** | primitives | Stays as external 0.2.5 crate |
| **zenflate WASM SIMD CRC-32** | primitives | WASM lacks clmul — slice-by-8 (8 KB table) is optimal |
| **zenresize full i32 intermediate** | primitives | 4× ring buffer cost; H/V-first clamping fix sufficient |
| **Extended-synth 340k corpus (e1 fill)** | training | Verdict "skip entirely" — use base 218k + rebalance gen-* classes |
| **`unified_v15rc` as training input** | training | Cross-codec eval corpus only; single-codec training base causes CID22 leakage |
| **V0_6 MoE alone (without Phase 3 full circuit)** | training | Deferred — needs centroid dispatch + per-expert bake packaging |

## 5. Cross-cutting recommendations

### Critical-path gate
**Phase 3 zentrain port** (item 4 above) is the gate for: ZNPR v3 publish (zenpredict 0.2.0), zenavif/zenwebp re-release with stable picker dep, replacing zensim PreviewV0_4 with V0_7+ bakes, and ending the "bundled bake" anti-pattern. Estimated 1-2 days; nothing else publishes until this lands.

### Real-GPU host
Multiple items (#2, #17, large parts of zenmetrics) are blocked on getting off WSL2 snap-docker (atomic<f32> panic in cubecl-cpu fallback). Either provision a non-WSL2 box or fleet vast.ai for parity verification.

### `main` vs `master` drift in zenmetrics
zenmetrics local `master` has PRs #1–6 merged; local `main` has unmerged rayon parallelism + janitor + zenjpeg/zenpng codecs. Needs review and decision: land as proper PRs or rebase. Right now this is a divergence trap for anyone resuming the repo.

### Worktree audit needed in jxl-encoder
**64 active jj worktrees** on jxl-encoder. Most are exploratory. Run `jj workspace list` + last-commit-date pass and either:
- promote: float16, hdr-gainmap, cmyk, modular-predictor-wireup (the active four)
- archive: anything > 30 days idle with no `.workongoing` marker

### Spec-grade gainmap compliance
gainmap-spec-status/ has `gainmap-spec-status` as a directory with sub-docs. P0 task: delete duplicate ISO parser in ultrahdr; add HEIF Amd 1 tmap to heic.

## 6. Source-vs-memory divergences flagged by agents

| Memory says | Source shows | File |
|---|---|---|
| `zenpredict 0.1.0 is v2-only; v3 unpublished` | **zenpredict 0.2.1 published with v3 + 5 new FeatureTransforms** | zenpredict Cargo.toml |
| `zenfilters has 46 filters, FusedAdjust = 10 ops, 276 tests` | **81 filters, FusedAdjust = 12 ops** | zenfilters lib.rs |
| `90 dense-percentile feature IDs 122-211 on feat/dense-percentiles` | **Branch is quarantined; main caps at ~106 active IDs** | zenanalyze main |
| `zenwebp_picker_v0.1.bin is the production binary` | True — but **v0.3 is fully validated (−4.60 % bytes) and ready to wire** | zenwebp main |
| `V_X canonical training is the 218k base` | **V0_7 seed=1 from `synthetic-v2/training_safe_synthetic_perceptual_clean.csv` after 11.77 % leak audit dropped 28 %** | zensim v07 commit `c4b059a7` |
| `JPEG-AIC corpus is named JPEG-AIC` | Match (and in zenpapers corpus) | — |
| `aom-decoder-rs and rav1d-safe are both actively developed AV1 decoders` | **aom-decoder-rs has been idle 35 days; 0/15 conformance vectors pass MD5** | aom-decoder-rs git log |
| `zenanalyze API freeze 0.1.x **forever**` | Confirmed; main is stable | zenanalyze Cargo.toml |
| `zensim/scripts/v_next/ is parked for removal` | Confirmed; 50 scripts last touched 2026-05-17 but classified parked | zensim CONTEXT-HANDOFF |
| `extended 340k training_safe_synthetic_extended.csv` | Confirmed (305,111 rows on disk; "340k claimed" rounded) | /mnt/v/output/zensim |

These divergences should be reflected in MEMORY.md the next time it's updated; in the meantime, treat source as authoritative.

## 7. Files / paths to know

Recovery & cross-cutting:
- `~/work/zen/RECOVERY_PLAN_2026-05-08.md` — 4-phase plan, blocking deps
- `~/work/zen/RECOVERY_HANDOFF_2026-05-08.md` — status of cherry-picks
- `~/work/zen/zenanalyze/everything.md` — central training/picker tracker
- `~/work/zen/ARCHMAGE-AUDIT.md` — 338-file SIMD-dispatch audit
- `~/work/zen/FEATURE-FLAG-CLEANUP.md` — feature-flag inventory
- `~/work/zen/gainmap-spec-status/` — HDR gain-map cross-spec map
- `~/work/zen/image-cdn-comparison.md` — Imageflow 4 vs 14 CDN services

Training data:
- `/mnt/v/output/zensim/synthetic-v2/training_safe_synthetic.csv` (196 k rows base)
- `/mnt/v/output/zensim/synthetic-v2/training_safe_synthetic_perceptual_clean.csv` (post-leak-audit)
- `/mnt/v/zen/zensim-training/2026-05-07/unified/` (cross-codec eval, 5.19 M rows, 7 parquets)

ZNPR v3 reference:
- `~/work/zen/zenanalyze/zenpredict/docs/ZNPR_V3.md` (v3 spec)
- `~/work/zen/zenanalyze/zenpredict/src/feature_transform.rs` (14 variants)

---

*Synthesized from 12 parallel Explore-agent reports, 2026-05-17. Reports cite specific commit hashes; this file does not. For commit-level traceability, re-run `git log` in the named repo on the named date.*
