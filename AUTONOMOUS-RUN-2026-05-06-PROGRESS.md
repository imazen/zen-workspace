# Autonomous picker/zensim work — 2026-05-06 (~1h36m in, 10h budget)

## Current state — exceeding original plan

**6 baked ZNPR v3 artifacts shipped** during this run; **−12% bytes Pareto move from meta-picker v0.2** plus **−3.32% from v0.7b + per-class encoder rule** stack to a substantial production improvement.

## Headline numbers

### Meta-picker v0.2 (NEW, just baked at 1h36m)

Trained on **rebalanced corpus + v10 unified data** (70k rows, ~400 unique images, 5 content classes):

| class | n | acc | Δbytes vs always-jxl |
|---|---:|---:|---:|
| document | 17 | 70.6% | 0.00% |
| **lineart** | 44 | 47.7% | **−46.27%** |
| **photo** | 93 | 58.1% | **−26.44%** |
| screen | 22 | 86.4% | −11.55% |
| **synthetic** | 13 | 46.2% | **−59.18%** |
| **OVERALL** | **189** | **59.3%** | **−12.03%** |

Captures 53% of −22.76% oracle ceiling.

### Per-codec picker v0.7b (committed earlier this run)

End-to-end Pareto move on v06 holdout: **−3.32% bytes overall** (vs +1.7% for shipped v0.6 — that's a 5pp improvement). Photo −1.11%, lineart −4.84%, screen −5.90%, synthetic −14.71%.

### V0_6 zensim retrained on rebalanced corpus

| Variant | val_mean SROCC | Δ vs baseline |
|---|---:|---:|
| V0_6 baseline (no cclass) | 0.8258 | — |
| **V0_6 + cclass** | **0.8386** | **+0.0128** |
| V0_6 + FiLM | (in flight, ~10-15 min) | TBD |
| V0_6 + MoE | (queued after FiLM) | TBD |

## Baked artifacts (this run)

| File | Size | Purpose |
|---|---:|---|
| `zenanalyze/benchmarks/zenpicker_meta_v0.2_2026-05-06.bin` | 18 KB | Class-balanced meta-picker (5-class input) — **NEW** |
| `zenanalyze/benchmarks/zenpicker_meta_v0.1_2026-05-06.bin` | 24 KB | First baked meta-picker (3-family) |
| `zenanalyze/benchmarks/zenjxl_picker_v0.7b_2026-05-06.bin` | 67 KB | Content-class-aware picker, screen-gated |
| `zenanalyze/benchmarks/zenjxl_picker_v0.6_mlp_2026-05-06.bin` | 65 KB | MLP variant of zensim_mask champion |
| `zenanalyze/benchmarks/content_classifier_v0.2_2026-05-06.bin` | 8 KB | 99.6% acc 4-class classifier |
| `zensim/runs/v06_baseline_rebal_*.bin` | 62 KB | V0_6 baseline retrained on rebalanced |
| `zensim/runs/v06_cclass_rebal_*.bin` | 63 KB | V0_6 + cclass retrained |

## End-to-end production pipeline

```
features (zenanalyze)                                            
        ↓                                                         
content_classifier_v0.2.bin → cclass label                        
        ↓                                                         
[features ⊕ cclass_onehot ⊕ target_band]                          
        ↓                                                         
meta_v0.2.bin → codec choice (jxl/avif/webp)                      
        ↓                                                         
zenjxl_picker_v0.7b.bin (if jxl) → (effort, biters, ziters) cell  
        ↓                                                         
per-class encoder rule → (patches, gaborish, pdl)                 
        ↓                                                         
EncoderConfig
```

Compounded production move expected: **−12% (routing) + −1-3% (per-codec picker on jxl-routed) + −10% (encoder rule on screens) = single-digit-percent overall on mixed traffic, much higher on screen/synthetic content.**

## Open PRs this run

| Repo | # | Title | Status |
|---|---|---|---|
| zenmetrics | #1, #2, #3 | sweep migration + DoS patch + Dockerfile | MERGED |
| zenmetrics | #4 | v12 balanced sweep launcher | open |
| zenmetrics | #5 | onstart prefer image-baked binary | open |
| zenanalyze | #73 | per-class picker findings + bakes | open |
| jxl-encoder | #30 | DoS fixes | MERGED |

## Sweep state

- **v12 (600 chunks)**: 585/600 landed; auto-kill armed when 600 hits
- **v06/v07/v08/v09/v10/v11**: previously committed
- **vast.ai burn**: ~$7.65/hr peak; will drop to $0 when v12 finishes

## What's next (remaining 8h+ in budget)

1. Wait for FiLM + MoE trainings (~30-60 min)
2. Eval all 4 V0_6 variants vs V0_2 + V0_6 dct_hf reigning champion → pick zensim champion
3. Re-bake meta-picker v0.3 with FULL v12 data (600 chunks) for slightly better numbers
4. Wire all baked .bins into codec crates as include_bytes!() defaults (task #36)
5. Implement runtime content-class gate + per-class encoder rule in zenjxl crate (tasks #37, #38)

## Lessons learned (this run)

- **vast.ai's `--image` skips ENTRYPOINT** — `--onstart-cmd` required
- **vast.ai supports `--login '-u USER -p TOKEN registry'`** for private GHCR
- **Docker image's binary location**: onstart_v3.sh defaulted to `/workspace/sweep/zen-metrics`, image had it at `/usr/local/bin/zen-metrics`. Made fix (PR #5) to prefer image-baked.
- **CLI metric kebab-case**: `ssim2-gpu` not `ssim2_gpu` — workers fail every chunk on snake_case
- **Per-worker effective parallelism is RAM-bound** (`min(cgroup_cores, ram_gb*2/3) - 2`). Right filter is `cpu_ram>30` for parallel=20+, but cuts available offers.
- **Photo-dominated training corpora hide regressions**. Per-class breakdown is mandatory.
