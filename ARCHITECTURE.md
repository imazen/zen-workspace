# Zen workspace architecture map

**Date:** 2026-05-27. **Status:** SNAPSHOT — a thin human-readable index
of where everything lives in the `~/work/zen/` image stack and how data
flows through it. This is the §5 deliverable of the consolidation spec
(`zenmetrics/docs/ZEN_CLOUD_AND_CONSOLIDATION_SPEC_2026-05-26.md`).

It is a **map, not a deep doc** — it links the authoritative deep docs
rather than duplicating them. When this disagrees with a deep doc, the
deep doc wins; fix this one. `~/work/zen/` is a loose workspace
directory, not a git repo — this file sits next to `DATA_PROVENANCE.md`,
`R2_ORGANIZATION_PLAN_2026-05-27.md`, and the per-topic audits.

Anything I could not verify against the live tree on 2026-05-27 is
marked **(unverified)**. Contradictions between the spec (target) and
current repo reality are flagged inline as **(SPEC vs REALITY)** —
those are the most useful entries to keep current.

---

## 0. Pointer index — where each big decision lives

| Doc | What it's authoritative for | Path |
|---|---|---|
| **Consolidation spec** | cloud-agnostic worker + 5-workstream refactor; target crate homes (§6); sequencing (§7) | `zenmetrics/docs/ZEN_CLOUD_AND_CONSOLIDATION_SPEC_2026-05-26.md` |
| **R2 org plan** | sweep-data layer organization; sources→encodes→metrics→features→train→bakes; attribute-partitioned content-addressed encodes; layers-as-prefixes | `~/work/zen/R2_ORGANIZATION_PLAN_2026-05-27.md` |
| **Data provenance** | live R2 backfill index; sidecar schema; codec commit pins; feature-version incompat | `~/work/zen/DATA_PROVENANCE.md` |
| **Dedup synthesis** | 2026-05-26 verified dedup audit that seeded the consolidation | `zensim/benchmarks/dedup_VERIFIED_synthesis_2026-05-26.md` |
| **Cross-codec inventory** | per-codec cutting edge, recovery-cycle status, backlog | `zenanalyze/everything.md` |
| **ML forensic inventory** | 7-part 2026-05-20 audit of repos + parquets + datasets | `~/work/zen/_ml-inventory-2026-05-20/00-MASTER-SYNTHESIS.md` |
| **R2 credentials / fleet** | scoped-cred minting, session-token gotcha, launcher-mints-per-sweep | `~/work/claudehints/topics/r2-credentials.md` |
| **Crate index** | full crate list + one-line descriptions | `~/.claude/CLAUDE.md` ("Imazen Crate Index") |
| **Per-repo agent context** | methodology, gotchas, known bugs per repo | each repo's `CLAUDE.md` |

---

## 1. The data-flow DAG

One DAG; the four workstreams are consumers that read/write specific
layers (R2 plan §1):

```
sources ──► encodes ──► metric scores ──► features ──► training views ──► bakes
(images)   (codec out)  (per-metric)      (zensim/      (assembled,        (shipped
                                           zenanalyze)   rebuildable)        models)
```

| Layer | Produced by | Consumed by | R2 home (current) |
|---|---|---|---|
| **sources** | corpus curation; human-MOS datasets | every workstream | `codec-corpus/` (+ planned `iqa/` for human-MOS) |
| **encodes** | codec sweeps (A); encoder tests (B) | metrics, features | `zentrain/<run>/encoded/` today → target `zentrain/encodes/<codec>/<encoder_id>/<sha>.<ext>` (R2 plan §3b) |
| **metric scores** | sweep worker GPU metrics | pickers, IQA, picker oracle | `zentrain/<run>/omni/` (omni sidecars) |
| **features** | zensim (CPU) / zenanalyze extractors | IQA training, pickers | `zentrain/<run>/zensim_features/`; local 372-feat at `/mnt/v/zen/zensim-training/2026-05-15-full-features/` |
| **training views** | join of metrics+features+anchors | trainers | `zentrain/canonical-2026-05-21/` (rebuildable) |
| **bakes** | trainers (zensim MLP, picker) | runtime (zensim lib, MetaPicker) | `zensim/zensim/weights/*.bin` (committed) + `s3://zentrain/bakes-2026-05-25/` (mirror) |

**Which workstream touches which layer** (R2 plan §1):

| Workstream | Produces | Consumes |
|---|---|---|
| **A. Codec sweeps** (RD across q/knob grids) | encodes + metric-score sidecars + zensim feature parquets | sources |
| **B. Encoder testing** (does a jxl change improve RD?) | per-config encode+score sweeps, Pareto deltas (transient) | sources, metric libs |
| **C. Pickers** (per-codec + cross-codec model training) | picker training tables, picker bakes | sweep metric scores + features + Pareto oracle |
| **D. IQA work** (perceptual metric train/validate) | feature parquets, zensim bakes, panel evals | sources + metric scores + human-MOS corpora |

Shared substrate all four touch: the **encodes** + **metric-scores**
layers. (Today not deduped across runs — that's the R2-plan §3b fix.)

---

## 2. Per-repo responsibility map

One row per repo: what it OWNS vs does NOT own. Source: the spec §6
crate-home table + the CLAUDE.md "Repo boundaries" section.

| Repo (`~/work/zen/…` unless noted) | OWNS | Does NOT own |
|---|---|---|
| **zensim** | perceptual metric *library* (`zensim/` crate: XYB multi-scale features, MLP runtime via zenpredict re-export, profile slots + shipped bake bytes); the Rust trainer + eval binaries in `zensim-validate` (`zensim_mlp_train`, `bake_verdict`, `panel`); train-core/train-gpu/target/picker-prep helper crates | GPU metric scoring (→ zenmetrics); feature *extraction macro* (→ zenanalyze); training data generation (→ zentrain) |
| **zenmetrics** | GPU metric crates (`butteraugli-gpu`, `dssim-gpu`, `ssim2-gpu`, `iwssim-gpu`, `cvvdp-gpu`/`-cpu`, `zensim-gpu`); `zen-metrics-cli` (score/batch/compare/sweep/assemble); **`zenstats`** (canonical IQA stat panel); **`zen-cloud-*` fleet** + `zen-sweep-worker`; sweep orchestration scripts | model training (delegates); the metric *definitions* zensim owns (re-implements them on GPU) |
| **zenanalyze** (workspace) | image feature *extraction* (`features_table!` macro); **`zenpredict`** (ZNPR v3 format + Predictor runtime + bake CLI); **`zenpicker`** (`CodecFamily` + `MetaPicker`); **`zentrain`** (Python data-prep + per-codec config modules) | metric scoring; perceptual metric library; cloud orchestration |
| **coefficient** (`~/work/coefficient`) | legacy multi-cloud orchestration (the pre-`zen-cloud-*` provider stack); the synthetic-training generator (`examples/generate_zensim_training`) | being partially superseded — providers migrate to `zen-cloud-{gcp,do}` (spec Phase D, **not started**) |
| **zenjpeg / zenwebp / zenavif / zenjxl / zenpng** | each codec's encode/decode; each hosts its own per-codec picker (depends on zenpredict, trained via zentrain) | the meta-picker (zenpicker); metric scoring |
| **jxl-encoder** (`~/work/zen/jxl-encoder`) | pure-Rust JXL encoder; its tuning-sweep harness (`zenjxl-tuning-runner`, `scripts/zenjxl-tuning-sweep`) — workstream B | the deployed sweep worker (spec Phase E migrates it to `zen-sweep-worker`, **not done**) |

---

## 3. The cloud fleet architecture

Spec §1: the binary on a compute node must NOT know which cloud it runs
on. Provider code lives only in pluggable backend crates + the launcher.

### Layering (spec §1.2)

```
zen-sweep-worker   (the deployed binary; baked into the docker image)
   │  generic; selects backend at runtime via --backend + cargo features
   ▼
zen-cloud-core     (pure traits + types + generic run_worker loop; NO gpu/cloud/parquet deps)
   │  JobQueue · BlobStorage · Heartbeat · CredentialSource · WorkerHost
   ▼  provider impls (each its own crate):
zen-cloud-vastai · zen-cloud-salad · zen-cloud-runpod · (planned: -local -gcp -do -akash)
zen-cloud-s3       (shared R2/S3 BlobStorage; vastai+salad+runpod depend on it)
```

Worker vs launcher (spec §1.3): the **worker** is the hot path
($/hr), generic over traits, in the image. The **launcher** runs on the
operator workstation, is provider-coupled (provisioning differs per
cloud), and is NOT unified — that trade is accepted (spec §1.8).

### Crate reality vs spec (verified 2026-05-27)

| Crate (spec §6 target) | Status in `zenmetrics/crates/` | Notes |
|---|---|---|
| `zen-cloud-core` | **EXISTS** (`error/lib/run/traits/types.rs`) | traits + generic loop landed (`de66b1b0`) |
| `zen-cloud-s3` | **EXISTS** (`blob/client/lib.rs`) | shared R2/S3 BlobStorage |
| `zen-cloud-vastai` | **EXISTS** (renamed from `vastai-fleet`) | the proven workhorse worker path |
| `zen-cloud-salad` | **EXISTS** (queue/storage/host/heartbeat/launch.rs) | SaladCloud push/managed-queue (Phase C) |
| `zen-cloud-runpod` | **EXISTS** (same 6 files) | RunPod Pods (pull) provider (Phase F, `82178f44`) |
| `zen-sweep-worker` | **EXISTS** (`main.rs`) | `--backend vastai\|salad\|runpod\|local`; cargo-feature-gated |
| `zen-cloud-local` | **EXISTS** (Phase B, `845ebc5b`/`cd231442`) | filesystem BlobStorage + local-dir JobQueue + `--backend local`; no-spend local worker path |
| `zenmetrics-orchestrator` | **EXISTS** | cloud-orchestration crate (separate agent's work; relationship to `zen-fleet-launch` target TBD) |
| `zen-cloud-gcp` / `-do` | **MISSING** | spec Phase D — coefficient extraction, **not started** |
| `zen-cloud-akash` | **MISSING** | spec Phase G — launcher-divergent, last |
| `zen-fleet-launch` | **MISSING as a crate** | launcher code lives per-provider in each crate's `launch.rs`; a unified `zen-fleet-launch` is the spec target (note: `zenmetrics-orchestrator` exists + may fill this role — reconcile) |
| `vastai-fleet` (old) | **GONE** (verified 2026-05-27) | Phase A rename + delete complete — no stale top-level dir on master |

### Deploy images

- `ghcr.io/imazen/zen-metrics-sweep:<tag>` — the BAKE-EVERYTHING image
  (DATA_PROVENANCE pins v22/v23; newer tags `0.6.x` + a salad image
  `Dockerfile.sweep.salad.v1`). Worker entrypoint hydrates env + verifies
  baked tools, never apt-installs at boot.

### Scoped credentials

- Pattern (claudehint `r2-credentials.md`): the **launcher mints a
  scoped, auto-expiring R2 temp cred per sweep** (one bucket+prefix,
  object-rw, short TTL) and injects `R2_ACCESS_KEY_ID`/`SECRET`/
  `AWS_SESSION_TOKEN` into the container. Never inject the root key.
- **EXISTS** (verified 2026-05-27, commit `3c233dc`): the minter is
  `zen-cloud-core::r2creds::mint_scoped_r2_cred(...)` — async, hits the
  verified Cloudflare `POST .../r2/temp-access-credentials` endpoint,
  returns `ScopedR2Cred { access_key_id, secret_access_key,
  session_token, expires_at }`, TTL-clamped, provider-agnostic. The
  Salad launcher wires it via `SaladApi::create_container_group_with_scoped_cred`
  (`d861b9b`); RunPod/vast launchers can reuse it.
  `CredentialSource::resolve()` (the trait) still only *reads* injected
  creds at the worker — minting is a launcher-side call, by design.

---

## 4. The IQA + stats layer

| Piece | Home | Role |
|---|---|---|
| **zensim** (the metric) | `zensim/zensim` crate | XYB multi-scale perceptual similarity; profile slots ship bake bytes; runtime forwards through `zenpredict::Predictor` |
| **zenstats** (the panel) | `zenmetrics/crates/zenstats` | **canonical** paper-correct Mohammadi 2025 panel: SROCC + PLCC + KROCC + OR (ITU-T P.1401) + PWRC (Wu 2017 SA-ST AUC) + Z-RMSE + MRR + bootstrap CI. Landed `zenmetrics@36d71ca3` |
| Panel consumers (migrated) | `zensim/zensim-validate/src/panel.rs` (re-export shim → zenstats); `bake_verdict`, `ensemble_mix`, `eval_bake_per_band`, `mlp_train/utils`; zenanalyze; jxl-encoder | one stat path; SROCC-alone verdicts are banned |

**Human-MOS corpora** (IQA validation):

| Corpus | Use | Note |
|---|---|---|
| **CID22** | **VALIDATION ONLY — sacred** | only large held-out codec-output human-MOS set; never a training target |
| KADID-10k, TID2013 | OK to train (human MOS) + integrity guards | ~95% non-compression distortions |
| KonJND-1k | aux / PJND calibration anchor | "visually lossless" gate |
| AIC-3 / AIC-4 | **HOLDOUT ONLY** | low-q human-judgment coverage |

**Feature-version incompat caveat (load-bearing):** the 300-feature
zensim vectors (from `zensim-gpu` omni backfills) and the 372-feature
CPU vectors (basic 156 + peaks 72 + masked 72 + IW-pool 72) come from
different zensim builds and are **NOT joinable by feature index**. The
R2-plan fix is `@<extractor-version>` in the feature path (never join
across versions). See DATA_PROVENANCE.md "Zensim 372-feature corpora".

---

## 5. Training + pickers

**zensim metric training** (workstream D):
- Rust trainer `zensim_mlp_train` (in `zensim-validate`) is canonical for
  recent work (V39, V46+). Python `train_v_next_mlp.py` is being retired
  (spec §3); zentrain's Python *data-prep* stays (called as a step).
- **TOML manifests** (`zensim/zensim/weights/manifests/*.toml`) capture
  the full recipe per bake. Spec §3 flips them from output (provenance)
  to input (`--manifest foo.toml` reproduces a bake exactly). 2 manifests
  exist today (v39, zensim_b_phone_oled).
- Shipped bakes are `include_bytes!`'d into `zensim/zensim/src/profile.rs`
  per profile slot (current ship: `v39_v32plus_spline_seed17_2026-05-25`
  as `PreviewV0_3`; plus the SOTA-trail variants V0_5*).

**Pickers** (workstream C):
- `zenpicker::MetaPicker` (cross-codec routing over `CodecFamily
  {Jpeg,Webp,Jxl,Avif,Png,Gif}`) wraps a `zenpredict::Predictor`.
  Per-codec pickers live in each codec crate; only `zenwebp_picker_v0.1.bin`
  is wired into production.
- Picker training data: codec sweeps → `unified_*_cvvdp.parquet` per-codec
  cuts → (today) Python `zentrain/examples/*.py` config modules →
  `zenpredict-bake`.
- **(SPEC vs REALITY)** Spec §4 proposes a new `zenpicker-train` Rust
  binary in the zenanalyze workspace (zenstats eval gate + CubeCL inner
  loop + cmaes search, auto-regenerating MetaPicker). **It does not exist
  yet** — picker training is still Python-first.

---

## 6. Canonical paths (current, 2026-05-27)

Point at the deep docs for detail; do not duplicate.

| Thing | Path | Authority |
|---|---|---|
| Canonical training corpora | `/mnt/v/zen/zensim-training/canonical-2026-05-21/` (local: `train/ val/ scores/ features/ _MANIFEST.json`) + `s3://zentrain/canonical-2026-05-21/` | zensim CLAUDE.md "Canonical corpora"; DATA_PROVENANCE |
| Shipped zensim bakes | `zensim/zensim/weights/*.bin` (committed) + mirror `s3://zentrain/bakes-2026-05-25/` | profile.rs `include_bytes!` |
| Synthetic-v2 base corpus | `/mnt/v/output/zensim/synthetic-v2/` + `s3://codec-corpus/synthetic-v2/` + Tower mirror | DATA_PROVENANCE "Synthetic-v2" |
| R2 buckets (existing) | `zentrain` (pipeline/training), `codec-corpus` (sources), `zen-tuning-ephemeral` (encoder-test sweeps) | r2-credentials.md; R2 plan §3a |
| R2 endpoint | `https://338ad3b06716695d6e2c81c864e387d8.r2.cloudflarestorage.com` | r2-credentials.md |
| Active metric backfills | `s3://zentrain/{cvvdp-v15rc-2026-05-18, omni-multi-codec-2026-05-19, multi-codec-2026-05-18}/` | DATA_PROVENANCE "Active backfills" |
| Tower NAS mirror | `/mnt/tower/output/zensim-archive-2026-05-20/` | DATA_PROVENANCE |

The R2 layout is mid-migration: the **target** (layers as prefixes;
attribute-partitioned content-addressed encodes; thin per-concern
sidecars) is the R2 org plan §3; the **live** state is DATA_PROVENANCE.
No R2 mutation has run — the plan is plan-only (R2 plan §6).

---

## 7. Migration status snapshot (spec §7)

| Phase | What | Status (verified 2026-05-27) |
|---|---|---|
| §1 A | cloud carve (`zen-cloud-core` + worker) | **DONE** (core, s3, vastai, worker; `vastai-fleet/` dir deleted) |
| §1 B | `zen-cloud-local` backend | **DONE** (`845ebc5b`/`cd231442`; `--backend local`, 27 tests, no-spend local path) |
| §1 C | `zen-cloud-salad` | **DONE** (crate + launcher + scoped-cred mint + `:v2` image; on-Salad smoke proved infra, GPU-class fix in flight) |
| §1 D | gcp/do extract from coefficient | **NOT STARTED** (queued, after Salad-fix settles) |
| §1 E | adopt worker everywhere, delete forks | **PARTIAL** (`vastai-fleet/` dir gone; jxl/per-codec sweep forks remain) |
| §1 F | `zen-cloud-runpod` | **DONE** (`82178f44`, Pods pull path) |
| §1 G | `zen-cloud-akash` | **NOT STARTED** (queued, last) |
| §1 scoped creds | `zen-cloud-core::r2creds` minter + Salad launcher wiring | **DONE** (`3c233dc`/`d861b9b`; entrypoint session-token `0ff85b4`) |
| §2 | zenstats finish + publish | `zenstats` landed; zenanalyze + jxl-encoder py reimpls migrated; coefficient migration + crates.io publish remain (publish blocked on green CI) |
| §3 | TOML-driven trainer (input not output) | **DONE** (`25aeb480`): `zensim_mlp_train --manifest` reproduces a bake, sha-verifies inputs; manifest=defaults, CLI wins. Follow-up: standardize manifest path conventions (two manifests disagree) |
| §4 | `zenpicker-train` Rust binary | **NOT STARTED** (after §3) |
| §5 | this `ARCHITECTURE.md` | **this file** |
| (jxl) | `perceptual_tuning` extraction (encode-only build fix) | **DONE** in **jxl-encoder** `3d879dd7` (NOT a zensim module — it's `jxl-encoder/src/vardct/perceptual_tuning.rs`) |

---

## Verification notes / flagged contradictions

The original map (written by an agent racing concurrent landings) flagged
six contradictions; **four were stale/wrong and are corrected here** after
verifying master on 2026-05-27:

1. ~~No scoped-cred minter in `zen-cloud-core`~~ → **WRONG.** It EXISTS:
   `zen-cloud-core::r2creds::mint_scoped_r2_cred` (`3c233dc`), wired into
   the Salad launcher (`d861b9b`). The agent read a pre-`3c233dc` snapshot.
2. ~~No `perceptual_tuning` extraction~~ → **WRONG repo.** It landed in
   **jxl-encoder** (`jxl-encoder/src/vardct/perceptual_tuning.rs`,
   `3d879dd7`), not zensim — the agent searched zensim by mistake.
3. **No `zen-fleet-launch` crate** — STILL TRUE: launcher code lives
   per-provider in each `zen-cloud-*/src/launch.rs`. BUT a
   `zenmetrics-orchestrator` crate now exists (separate agent) that may
   fill this role — reconcile the two.
4. ~~`vastai-fleet/` dir still present~~ → **WRONG.** Verified GONE on
   master; Phase A rename+delete is complete.
5. **`zen-cloud-{gcp,do,akash}` and `zenpicker-train` do not exist yet**
   — STILL TRUE (queued phases). NOTE: `zen-cloud-local` now EXISTS
   (Phase B landed `845ebc5b`) — the agent missed it (concurrent push).
6. The Salad-node smoke gate, RunPod serverless path, and crates.io
   `zenstats` publish are **(unverified)** — code is present but
   end-to-end execution not confirmed from the tree.
