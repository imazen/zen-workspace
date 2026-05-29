# R2 + sweep-data organization plan — codec sweeps / encoder testing / pickers / IQA

**Date:** 2026-05-27. Companion to `DATA_PROVENANCE.md` (which is the
per-run *index*; this is the *target structure* + migration plan).
**Status:** PROPOSAL. Captures the live R2 state, the four workstreams
that produce/consume sweep data, the problems with today's layout, and
a clean target organization + non-breaking migration.

R2 endpoint: `https://338ad3b06716695d6e2c81c864e387d8.r2.cloudflarestorage.com`.
Mint scoped per-workstream tokens per `~/work/claudehints/topics/r2-credentials.md`.

---

## 1. The four workstreams + who produces/consumes what

The data pipeline is one DAG; the four "workstreams" are consumers that
read/write specific layers of it:

```
sources ──► encodes ──► metric scores ──► features ──► training views ──► bakes
(images)   (codec out)  (per-metric)      (zensim/      (assembled,        (shipped
                                           zenanalyze)   rebuildable)        models)
```

| Workstream | Produces | Consumes | Producer code | Today's R2 home |
|---|---|---|---|---|
| **A. Codec sweeps** (RD: encode a corpus across q/knob grids, score) | encodes + metric-score sidecars (omni) + zensim feature parquets | sources | `zenmetrics/crates/vastai-fleet` → `zen-sweep-worker`; `scripts/sweep/` | `zentrain/sweep-v*`, `*-backfill`, `omni-multi-codec`, `multi-codec` |
| **B. Encoder testing** (does a jxl-encoder change improve RD on a corpus?) | per-config encode+score sweeps, Pareto deltas | sources, (metric libs) | `jxl-encoder/zenjxl-tuning-sweep` + `zenjxl-tuning-runner`; W44 series | `zen-tuning-ephemeral/w44-*` |
| **C. Pickers** (per-codec + cross-codec `MetaPicker` model training) | picker training tables, picker bakes | sweep metric scores + zenanalyze features + Pareto oracle | `zenanalyze/zenpicker` + `zentrain` (py) → `zenpredict-bake` | `zentrain/picker-training-*`, `per_codec_training-*`, `codec-corpus/selector-v0.3` |
| **D. IQA work** (perceptual metric training/validation: zensim) | feature parquets, zensim bakes, panel evals | sources + metric scores (ssim2/cvvdp/butter/iwssim) + human-MOS corpora | `zensim` + `zensim-validate` + `zenstats`; `zenmetrics` GPU metrics | `zentrain/canonical-*`, `features/`, `bakes-*`, local 372-feat corpora |

**Shared substrate all four touch:** the *encodes* layer (codec output
bytes) and the *metric-scores* layer (per-(encode, metric) values). A
codec sweep (A) produces them; pickers (C) and IQA (D) consume them;
encoder testing (B) produces its own short-lived copies. Today they are
NOT shared — each run re-encodes + re-stores under its own `<run>/encoded/`
prefix, so identical (image, codec, knob) cells are stored many times.

---

## 2. Problems with today's layout

1. **`zentrain` is an overloaded kitchen sink** — ~40 top-level dirs
   spanning all four workstreams + smoke runs + bakes. No
   concern-separation; impossible to scope a token to "just sweeps" or
   "just training."
2. **Dated-experiment sprawl, never consolidated** — `sweep-v04`…
   `sweep-v16`, 4 separate `*-backfill-*` dirs, multiple `canonical-*`
   and `picker-training-*`. CLAUDE.md's "dated dirs OK ≤7 days then
   consolidate or archive" rule is being violated wholesale.
3. **No content-addressing on encodes** — encoded variants live at
   `<run>/encoded/<chunk>/<filename>`, run-scoped. The same
   (image, codec, knob) encode produced by two runs is stored twice.
   CLAUDE.md §4 mandates content-addressed `artifacts/<codec>/<sha256>.<ext>`
   for dedup; that's not happening.
4. **Metric scores welded to one feature-set version** — omni sidecars
   carry the 6 GPU scores AND a 300-feat zensim vector in the same
   parquet, so a new feature extractor or a new metric forces a full
   re-run instead of a thin new sidecar (violates CLAUDE.md §3
   "separate encode / metric / feature / anchor").
5. **Ephemeral vs durable is bucket-mixed** — `zen-tuning-ephemeral`
   correctly isolates B's transient sweeps, but A's smoke runs +
   throwaway experiments live in `zentrain` next to canonical data.
6. **No lifecycle/TTL** — nothing expires; ephemeral encoder-test
   sweeps accrete forever.

---

## 3. Target organization

> **Decisions locked 2026-05-27 (user):** (1) layers are **prefixes
> inside the EXISTING buckets** — keep current names, no new buckets
> (R2 can't rename anyway, and a "rename" = new bucket + full copy +
> repoint every consumer, not worth it). (2) Encodes are **NOT flatly
> content-addressed** — flat sha namespace makes scripted lifecycle
> ops (e.g. "purge all encodes from an outdated encoder commit")
> impossible. Encodes are **attribute-partitioned, content-addressed
> within the partition** (§3b). (3) **No TTL** on `zen-tuning-ephemeral`
> yet. (4) Plan-only — no migration executed until reviewed.

### 3a. Layers as prefixes in the existing buckets

Keep the three existing buckets; organize the pipeline layers as
top-level prefixes. Scoped tokens use the R2 temp-cred `prefixes` field
(per `~/work/claudehints/topics/r2-credentials.md`) to grant
per-layer access without new buckets.

| Bucket (existing) | Layer prefixes | Mutability | Scoped-token grant |
|---|---|---|---|
| `codec-corpus` (= sources) | `synthetic-v2/`, `variants/`, `blobs/`, `manifests/`, `icc-profiles/`, `fuzz/`, + new `iqa/` (human-MOS corpora) | write-rarely, read-always | workers: read-only |
| `zentrain` (= the pipeline) | `encodes/` (§3b) · `metrics/<metric>/<run>/` · `features/<extractor>@<ver>/<run>/` · `train/` (derived views + canonical corpora) · `bakes/` (+ `pickers/`, `zensim/`) · `_archive/` | append-only per layer; `train/` rebuildable | sweep worker: read `codec-corpus/` + r/w `zentrain/encodes/` + write `zentrain/metrics/`; trainer: read `zentrain/{encodes,metrics,features,train}/` |
| `zen-tuning-ephemeral` (= encoder testing + smoke) | `w44-*/`, `*-smoke-*/`, `corpus/`, `heartbeat/` | transient (no TTL yet — user, 2026-05-27) | tuning worker: read `codec-corpus/` + r/w `zen-tuning-ephemeral/` |

Prefix-scoping keeps the no-everything-token property: a codec-sweep
worker's temp cred is scoped to `codec-corpus/` (read) +
`zentrain/encodes/` & `zentrain/metrics/` (write); it can never touch
`zentrain/bakes/` or another workstream's data.

### 3b. Encodes: attribute-PARTITIONED, content-addressed within (purgeable)

Flat content-addressing (`encodes/<codec>/<sha>.<ext>`) was rejected:
the sha is opaque, so you can't scriptably purge by attribute — "delete
every encode from outdated jxl-encoder commit `6b8eefc1`" or "drop all
zenjxl q<5 from the W44-66 era" become impossible without an index walk,
and even then a flat namespace can't prefix-delete. The churning
attribute IS the encoder version, and outdated-encoder purges are a real
op. So **partition by the attributes you purge along, content-address
within the partition:**

```
zentrain/encodes/<codec>/<encoder_id>/<content_sha256>.<ext>
zentrain/encodes/_index/<codec>/<encoder_id>.parquet
    # rows: (image_path, knob_tuple_json) -> content_sha, bytes, encode_ms
```

- `<encoder_id>` = the encoder's pinned commit/version (e.g.
  `jxl-encoder@7de1db87`, `zenjpeg@bdc7f4c`). It's the lifecycle key.
- **Purge an outdated encoder = one prefix delete:**
  `s5cmd rm 's3://zentrain/encodes/zenjxl/jxl-encoder@6b8eefc1/*'` (+ its
  `_index` shard). No index walk, no orphan hunt.
- **Dedup still works WITHIN a `(codec, encoder_id)` partition** —
  identical bytes across runs/corpora at the same encoder version
  collapse to one `content_sha` object. Cross-encoder-version byte
  identity is rare and deliberately NOT deduped (keeping it would
  re-introduce the un-purgeable flat namespace).
- Every sweep cell references `(codec, encoder_id, content_sha)`. A new
  metric run reads the `_index`, pulls bytes by sha, scores, writes a
  thin `zentrain/metrics/<metric>/<run>/...` sidecar — no re-encode.

This satisfies CLAUDE.md §4 (persist encoded variants, content-addressed
for dedup) AND keeps encoder-version lifecycle management as cheap
prefix ops — the property the user flagged as load-bearing.

### 3c. Thin sidecars, one concern each (CLAUDE.md §3)

- A metric score row = `(encode_sha, metric_id, score, diffmap_sha?)`.
- A feature row = `(encode_sha | pair_key, extractor@version, f0..fN)`.
- Training views are a JOIN of the above, materialized into `zen-train/`
  and cheap to rebuild — never the source of truth.
- This means: new metric = 1 new sidecar dir. New feature extractor
  version = 1 new sidecar dir. Neither re-runs encodes.

### 3d. Naming + lifecycle

- **Run id:** `<workstream>-<purpose>-<YYYY-MM-DD>` (e.g.
  `sweepA-zenjpeg-q-grid-2026-05-27`, `encB-w44-230-dct-2026-05-27`).
- **Every run dir carries `_MANIFEST.json`** with `build_commit`
  (codec + worker SHAs), row count, sha256s, input refs, R2/Tower
  mirror (CLAUDE.md §2). No manifest = untrustworthy.
- **Lifecycle:** dated dir ≤ 7 days → promote findings to canonical
  (`zentrain/train/` or `zentrain/bakes/`) OR move to `zentrain/_archive/`.
  `zen-tuning-ephemeral` gets **NO TTL for now** (user, 2026-05-27 —
  revisit after in-flight encoder campaigns settle; manual
  archive/delete in the meantime). Canonical corpora are date-stamped
  and immutable once published.

> **Layer → prefix map** (since layers are prefixes in existing buckets,
> §3a): in §4–§5 below, read `zen-sources`→`codec-corpus`,
> `zen-encodes`→`zentrain/encodes`, `zen-metrics`→`zentrain/metrics`,
> `zen-features`→`zentrain/features`, `zen-train`→`zentrain/train`,
> `zen-bakes`→`zentrain/bakes`, `zen-ephemeral`→`zen-tuning-ephemeral`.
- **One canonical path per artifact** (CLAUDE.md §8). The 3× duplicated
  canonical parquets the 2026-05-20 inventory found get a single home in
  `zen-train/canonical-<date>/`; others alias or move to `_archive/`.

---

## 4. Per-workstream specifics

- **A. Codec sweeps** → write `zen-encodes` (content-addressed) +
  `zen-metrics`. Stop welding features into omni sidecars; emit feature
  parquets to `zen-features` keyed on `encode_sha`. The existing
  `zentrain/sweep-v*` + `omni-multi-codec` become migration sources.
- **B. Encoder testing** → stays in `zen-ephemeral` (it's transient by
  nature — "did this jxl change help?"). Pareto deltas that inform a
  shipped encoder default get promoted to a committed `benchmarks/` doc
  in the codec repo, not left in R2. W44 series is the model; keep it
  isolated + TTL'd.
- **C. Pickers** → training tables are DERIVED views in `zen-train/picker/`,
  rebuilt from `zen-metrics` + `zen-features` + the Pareto oracle. Picker
  bakes + manifests in `zen-bakes/pickers/`. `codec-corpus/selector-v0.3`
  consolidates into `zen-bakes/pickers/`.
- **D. IQA work** → human-MOS corpora (CID22/KADID/TID/KonJND/AIC) are
  sources in `zen-sources/iqa/`; per-corpus feature parquets in
  `zen-features/zensim@<ver>/`; zensim bakes in `zen-bakes/zensim/`;
  the canonical train/val split in `zen-train/zensim-<date>/`. The
  feature-index-version incompatibility (300-feat vs 372-feat across
  zensim builds — see DATA_PROVENANCE.md) is handled by the
  `@<extractor-version>` in the `zen-features` path: never join across
  versions.

---

## 5. Migration (non-breaking)

1. **Freeze new sprawl:** all NEW runs use the target buckets/naming
   immediately. No new dated dir in `zentrain`.
2. **Stand up `zen-encodes` content-addressing forward-only:** the next
   sweep writes content-addressed; back-port the existing
   `omni-multi-codec` / `cvvdp-v15rc` encoded prefixes by sha-indexing
   them in place (a one-time job that reads each `encoded/<chunk>/` and
   writes `zen-encodes/_index/`), no re-encode.
3. **Promote canonical, archive the rest:** `canonical-2026-05-21`
   (the v11 training set) → `zen-train/canonical-2026-05-21/` as the one
   canonical home; the dozen `sweep-v04..v16` dirs → `zentrain/_archive/`
   (keep for forensics, out of the active namespace).
4. **Tower mirror before any delete** (CLAUDE.md §5): nothing leaves R2
   without a Tower copy + 3-file sha verify.
5. **Update `DATA_PROVENANCE.md`** to point at the new homes as each
   layer migrates; this plan is the target, that doc stays the live
   index.

## 6. Decisions (resolved 2026-05-27)

1. **Layout:** layers are **prefixes in the existing buckets** (§3a),
   not new buckets. Keep `codec-corpus` / `zentrain` / `zen-tuning-ephemeral`.
2. **Encodes:** **attribute-partitioned + content-addressed within**
   (§3b) — `encodes/<codec>/<encoder_id>/<sha>.<ext>` — so outdated-encoder
   purges are a prefix delete. Flat content-addressing rejected.
3. **TTL:** none on `zen-tuning-ephemeral` for now; revisit later.
4. **Execution:** plan-only. No buckets created, no migration run, no
   R2 mutations. This doc is the agreed target for review; nothing
   moves until the user says go.

### Still open (deferred, not blocking)

- When migration starts: the order in §5 (freeze sprawl → forward-only
  content-addressed encodes → promote canonical + `_archive/` the
  `sweep-v04..v16` dirs → Tower-mirror-before-delete).
- Whether the `zen-tuning-ephemeral` W44 runs that informed shipped
  jxl-encoder defaults get their Pareto results promoted to committed
  `benchmarks/` docs before any future cleanup (recommended, not urgent).
