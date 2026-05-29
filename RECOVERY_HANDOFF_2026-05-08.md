# Recovery cycle handoff — 2026-05-08

Companion to `RECOVERY_PLAN_2026-05-08.md`. This doc records what landed, what's parked, and the explicit next-session continuations.

## TL;DR

Phase 1 (read & distill) **complete**. Phase 2 (cherry-picks) **partially complete** — register commits landed where the user's working tree was clean enough; uncommitted user WIP in zenanalyze, zenmetrics, zenavif, zenwebp, coefficient was preserved untouched in "parking" commits or left as untracked files. Phase 3 (zentrain trainer port) **scaffolded**; substantive ports still TODO. Phase 4 (ZNPR v3) **major finding**: v3 already exists on `zenanalyze/main` (commit 6b552a5, 2026-05-06), and `bake_v2` already emits v3 — zenpredict 0.1.0 on crates.io is the only v2 path left. v3 spec doc drafted at `zenpredict/docs/ZNPR_V3.md`.

## What's on each repo's main / branches now (2026-05-08 end state)

The user clarified mid-session that ALL prior "user WIP" was Claude-Code work
to be driven to completion; the recovery agent re-cleaned and committed it.

| Repo | State | Key commits |
|---|---|---|
| zensim | clean; experimental V0_4 still ships behind `__experimental_versions`. `scripts/v_next/` Python trainer parked for migration to zentrain. | `d530546 docs(recovery): per-repo recovery register 2026-05-08 + park v_next trainer` |
| zenanalyze | **substantial v3 work landed on main** — recovery register, ZNPR v3 spec doc, zentrain scaffold for zensim metric trainer, v3 API hardening (`#[non_exhaustive]` on Header/BakeRequest/BakeError + `BakeRequest::new` + `BakeRequest::builder` fluent API), v3 test coverage (`tests/output_specs.rs` 445 lines), zenjxl picker v0.6 safety audit artifacts. | `11c1180 bench(zenpicker): v0.6 safety audit artifacts`, `0935914 feat(zenpredict): v3 API hardening`, `45e345a docs(zenpredict): draft ZNPR v3 spec`, `d8e45ab docs(recovery): per-repo register 2026-05-08`, `fe6b977 feat(zentrain): scaffold zensim_metric_train.py` |
| zenmetrics | local `master` had divergence vs origin/master (PRs #1–6 already merged origin's pack_scratch / dim-widening work I was about to commit). Pushed register to `docs/recovery-register-2026-05-08` branch. Local `main` (different from `master`!) and divergent local `master` left for user to reconcile. | origin: `4232127 docs(recovery): per-repo register 2026-05-08` on `docs/recovery-register-2026-05-08` |
| zenavif | register branch + benchmark cleanup branch pushed. `>1 MB` benchmark files archived to `/mnt/v/zen/zensim-archive-2026-05-08/zenavif-large-benchmarks/` and added to `.gitignore`. | origin: `fd79a8d` (register), `685aa8a` (bench cleanup) |
| zenwebp | register on `docs/recovery-register-2026-05-08` (sits on top of `fix/security-audit-2026-05-06` pending merge). | origin: `bdd9613 docs(recovery): per-repo register 2026-05-08` |
| coefficient | register on `docs/recovery-register-2026-05-08` after fixing pre-existing `cargo fmt --all` drift in `examples/generate_zensim_training.rs`. | origin: `59544a3 docs(recovery): per-repo register 2026-05-08 + cargo fmt drift` |

## What was archived to durable storage

`/mnt/v/zen/zensim-archive-2026-05-08/`:
- `diffmap-public-ctors.tar.gz`, `phase-4-zenblend.tar.gz`, `zengrid-analysis.tar.gz`, `zero-weight-elide.tar.gz` — 4 dormant zensim sibling worktrees with no commits since 2026-04-29 (sibling dirs at `/home/lilith/work/zen/zensim--*` removed)
- `recovered-parking-patches/zenanalyze-parking.patch` — the patch from a brief mistake where I split user WIP into a "parking" jj commit and accidentally pushed it to zenanalyze main; reverted via `f3057d1`, the actual content was correct so I re-applied as `0935914 feat(zenpredict): v3 API hardening`
- `zenavif-large-benchmarks/` — 13 zenavif benchmark files >1MB (.parquet, .json, .tsv) totaling ~127 MB. Now `.gitignore`d in zenavif

Surviving zensim sibling worktrees (recovery sources for Phase 3): `v04-mlp`, `v06-film`, `v06-moe`, `v06-rebalance`, `v07-e1-ablation`. Move to `/mnt/v/zen/zensim-archive-2026-05-08/` after Phase 3's trainer port finishes.

## zenmetrics divergence (special case)

Local `zenmetrics` had two branches: `main` (where prior-session sweep work accumulated unmerged: `e0b06e1 feat(sweep): add zenjpeg + zenpng codecs`, `c936a4c feat(sweep): inner-loop rayon parallelism`, `8e0963a fix(sweep): catch_unwind`, `d1560b8 sweep: per-fleet janitor`, `b8f85eb docs(recovery): per-repo register 2026-05-08`) and `master` (where PRs go: `abf3344 fix: dim widening + sRGB pack scratch (#6)`, `edb98eb feat(docker): Dockerfile.sweep (#3)`, `6e5798f fix: [patch.crates-io] jxl-encoder DoS fix (#2)`, `f43c0aa feat(sweep): migrate sweep scripts (#1)`).

`master` already has the GPU pack_scratch and dim-widening fixes via PR #6. `main`'s rayon parallelism + janitor + zenjpeg+zenpng codec additions look unmerged — those are PR-sized work blocks. **Action for next session**: review `main..master` and `master..main` carefully and either land remaining `main` commits as proper PRs to `master`, or rebase `main` onto `master` and force-push as a topic branch. Out of scope for this recovery cycle.

## What was archived

`/mnt/v/zen/zensim-archive-2026-05-08/` (~2.3 MB compressed):
- `diffmap-public-ctors.tar.gz` (no commits since 2026-04-26)
- `phase-4-zenblend.tar.gz`
- `zengrid-analysis.tar.gz`
- `zero-weight-elide.tar.gz`

Sibling dirs at `/home/lilith/work/zen/zensim--*` removed for those four. Surviving:
- `zensim--v04-mlp/` — V0_4/V0_5/V0_6 dct_hf canonical results (KEEP, recovery source)
- `zensim--v06-{film,moe,rebalance}/` — V0_6 variants (KEEP)
- `zensim--v07-e1-ablation/` — e1 fill verdict + full Rust trainer reference (KEEP)

## Phase 3 — what to port next

`zenanalyze/zentrain/tools/zensim_metric_train.py` is a SCAFFOLDED skeleton. Implemented:
- canonical synth CSV/parquet loader + KADID/TID/CID22 auxiliary loader
- vectorized RankNet (10–30× faster than per-group loop)
- multi-dataset val_policy=min selection
- per-dataset val SROCC reporting

**TODO ports** (priority order, with v06-* worktree references):

| # | feature | Rust ref (worktree → file) | est effort |
|---|---|---|---|
| 1 | `train_loop` end-to-end wiring + bake to ZNPR v3 | `zensim/scripts/v_next/train_v_next_mlp.py` (existing v_next prototype has the loop) + `zenpredict/src/bake/v2.rs` for v3 builder | ~half day |
| 2 | zenanalyze `dct_hf` feature appender (`attach_zenanalyze_features`) | `zensim--v07-e1-ablation/zensim-validate/src/main.rs::expand_with_zenanalyze_features` | ~2 hours |
| 3 | magnitude-matching loss (`magnitude_match_term`) | `zensim--v04-mlp` Rust trainer | ~1 hour |
| 4 | sampler bias (`--low-band-oversample`) | `zensim--v07-e1-ablation` Rust trainer | ~2 hours |
| 5 | FiLM heads + 5-per-class bake + manifest | `zensim--v06-rebalance/benchmarks/v06_cclass/` for trainer recipe; v06-rebalance Rust `mlp_train::FilmHead` for impl | ~half day |
| 6 | MoE | `zensim--v06-moe/docs/moe_architecture.md` + Rust `mlp_train::MoE` | unverified — train+eval before deciding to keep |
| 7 | multi-target loss (ssim2 + butteraugli_p3) | CID22 paper §6 advice + the `score_butteraugli_pnorm3` column already in synthetic-v2 CSV | ~2 hours |

After all TODOs: train champion, bake to ZNPR v3, validate against held-out CID22 + KonJND-1k. Gate on **CID22 SROCC ≥ 0.8893** (V0_4 baseline) before considering replacing the experimental ship.

## Phase 4 — what to do for v3 publish

(Per user 2026-05-08: "rebake, everyone uses c3", "callee supplied", "DO NOT publish until I approve".)

1. **Yagni-trim public API surface** (per `zenpredict/docs/ZNPR_V3.md` plan):
   - Gate `bake::*` behind `bake` cargo feature (default-on for dev tooling, off for lean runtime). **Code change**: feature attribute on the module + downstream consumers update.
   - Demote `inference::{LayerKind, forward_*}`, `f16_bits_to_f32`, `scale_i8_row` to `pub(crate)`. **Code change**: visibility flip; check zensim/zenpicker/etc for any external usage (probably none).
   - Document `feature_transforms`, `output_value::Default`, `SparseOverride` ordering edge cases (in source comments + `ZNPR_V3.md`).
2. **Migrate consumers**:
   - zensim: re-bake `weights/v0_4_2026-04-30.bin` to v3; bump `Cargo.toml` zenpredict dep to 0.2.0.
   - zenavif: merge `feat/expert-internal-params` (`80b884a`) to main; remove `include_bytes!`; add `with_baked_model(bytes)` API; tag 0.2.0 (don't publish).
   - zenwebp: merge `feat/expert-internal-params` worktree; same API surface; tag 0.5.0 (don't publish).
   - zenpicker: re-bake `benchmarks/zenpicker_meta_v0.5.bin` to v3.
3. **Bump zenpredict to 0.2.0** in Cargo.toml + CHANGELOG.md, NOT yet `cargo publish`.
4. **End-to-end smoke**: with all four consumers cargo-build clean, no crates.io publish.
5. **Tag & request publish window** from user.

## Open user decisions to revisit

(Locked at top of `RECOVERY_PLAN_2026-05-08.md`.)

1. ✅ ZNPR v3 canonical for everyone — confirmed.
2. ✅ Caller-supplied bakes — confirmed.
3. ✅ Dormant worktrees → `archive/` (now `/mnt/v/zen/zensim-archive-2026-05-08/`) — done.
4. ✅ zentrain location: `zenanalyze/zentrain/tools/zensim_metric_train.py` + `examples/zensim_metric_config.py` — landed.
5. ⏸ DO NOT publish new crate versions — honored; all version bumps in unreleased changelog sections.

## Known unfinished business

1. **zensim-bench `dataset_metric_baseline` cannot evaluate dct_hf / FiLM bakes** — it only feeds 228 features. V0_6 dct_hf needs 231 (+3 zenanalyze). FiLM needs per-class dispatch. To validate Phase 3 outputs against held-out CID22, the bench needs extending OR a Python eval harness in zentrain.
2. **The currently-shipped `zensim/weights/v0_4_2026-04-30.bin` was the V0_4 mixed-supervision bake**. The published numbers for V0_5 (CID22 0.8934) and V0_6 dct_hf (CID22 0.8935) on the v04-mlp branch's `4metric_overnight_FINAL_2026-05-01.md` were measured at `n=1500/dataset`. My new full-dataset benches show all the V0_4-equivalent bakes scoring 0.8893 on CID22, suggesting either (a) the published V0_5/V0_6 numbers are sample-size-noisy, or (b) the actual V0_5 / V0_6 dct_hf bakes need extra inputs that the current bench can't supply. **Phase 3 should re-evaluate with the harness fix in #1.**
3. **The 4 zensim sibling worktrees still on disk** (`v04-mlp`, `v06-film`, `v06-moe`, `v06-rebalance`, `v07-e1-ablation`) are recovery sources. Move to `recovered-archive/` after Phase 3 successfully ports the trainer features.
4. **coefficient register file is uncommitted** — needs the user to run `cargo fmt --all` first (their committed code has fmt drift).
5. **zenavif / zenwebp register branches** are pushed to `docs/recovery-register-2026-05-08` — user can review and merge.

## Cross-cutting cleanup tasks for next agent

- For each `.workongoing` marker I created in zenanalyze/zenmetrics/zenavif/zenwebp/coefficient: the next session should refresh or remove based on activity.
- The "(parking — user WIP on this WC)" commits in zenanalyze and zenmetrics need user attention to claim. They are above the recovery-register commit on each branch's history.
- Phase 3 work block: estimated 1–2 days of focused effort to land all TODO ports and re-train champion.
- Phase 4 work block: ~1 day after Phase 3 — yagni-trim + version bump + cross-consumer rebuilds + end-to-end smoke.

## Source references

- `~/work/zen/RECOVERY_PLAN_2026-05-08.md` — the original plan with phase gates and inventory.
- `<repo>/docs/RECOVERY_REGISTER_2026-05-08.md` — per-repo finding/verdict tables.
- `zenanalyze/zenpredict/docs/ZNPR_V3.md` — v3 spec draft + yagni plan + migration order.
- `/mnt/v/zen/zensim-archive-2026-05-08/` — archived dormant zensim sibling dirs.
- `zenanalyze/zentrain/tools/zensim_metric_train.py` — Phase 3 scaffold with port TODOs.
- `zenanalyze/zentrain/examples/zensim_metric_config.py` — configuration example with the V0_4-recipe wiring.
