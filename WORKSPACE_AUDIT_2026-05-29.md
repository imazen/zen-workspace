# zen workspace audit — 2026-05-29

Read-only audit of `~/work/zen/`. Goal: push outstanding **safe** work,
inventory all worktrees + branches, report everything else. This pass
made **ZERO commits and ZERO pushes** (see §A.2 — nothing qualified as
safe-push). No worktree was deleted or `jj workspace forget`ed.

Full sweep log: `/tmp/zen_workspace_audit_2026-05-29.log`.
Audit run UTC: 2026-05-29T07:37Z.

Live sessions detected at audit time (`.workongoing` < 10 min):
- `zenmetrics/` — `claude-jobsys-spec` (07:35Z) — **LIVE**
- `zensim/` — `claude-session-panel` (07:28Z, ~9 min) — **LIVE** (this audit's own parent session)

Stale markers (informational, >10 min old; sessions likely ended):
root `.workongoing` (oracle-arm-box 00:44Z), rav1d-safe + zenrav1e
(zenvideo-tune 2026-05-28 17:19Z), zenmetrics--cpu-bench-refresh
(01:59Z BLOCKED), zenanalyze (2026-05-27), commerce-corpus (2026-05-27),
+ several days-old feature-workspace markers.

---

## (A) Per-repo status

### A.1 Classification tally

Scanned **97 dirs** under `~/work/zen/`. Repo dirs: **88**
(38 primary repos + 50 sibling worktrees/`--suffix` dirs). 9 non-repos
(corpus/scratch/config dirs: cpu-backend-bench, gen-clothing,
hetzner-arm-config, jxl-rs-target, _ml-inventory-2026-05-20,
oracle-arm-config, rav1d-bench, retired, scripts, whereat,
work-maintenance, zenjpeg-perm-corpus*, zenmetrics-refs,
zensim-cpu-gpu-bench, zjr-val-scratch).

| Class | Count | Notes |
|---|---|---|
| CLEAN (synced, clean WC) | 33 primary | All imazen/lilith repos with a remote report main/master **SYNCED** |
| SAFE-PUSH | **0** | Nothing qualified — see §A.2 |
| LIVE (fresh marker, skipped) | 2 | zenmetrics, zensim |
| DIRTY-UNCOMMITTED (no marker, ambiguous WIP) | several | See §A.3 |
| LOCAL-ONLY (committed work, NO remote → cannot push) | 4 | commerce-corpus, zenjpeg-recompress, zenlzw, zen-train-docker |
| THIRD-PARTY-DIVERGED (out of push scope) | 1 | fax |

### A.2 What was pushed

**Nothing.** Zero repos qualified as SAFE-PUSH.

Reasoning (verified read-only):
- Every imazen/lilith primary repo that **has a remote** reports its
  `main`/`master` bookmark **SYNCED** with `@origin` (sync check across
  37 repos: all SYNCED except the cases below).
- The only repos with local commits **ahead** of any remote are:
  - **commerce-corpus** — `@` chain of 5 feat commits, **no git remote
    configured at all** (`git remote -v` empty) + dirty WC. Cannot push.
  - **zenjpeg-recompress** — `main` bookmark (3 commits) has `@git` but
    **no `@origin`**, **no remote configured** + dirty WC. Cannot push.
  - **zenlzw** — `main` + 3 branches, **no remote configured**, clean WC.
    Cannot push (local-only repo).
  - **zen-train-docker** — `main` (4 commits), **no remote**, clean WC.
    Cannot push (local-only repo).
  - **fax** — `master` is genuinely **DIVERGED** from `origin`
    (origin = `pdf-rs/fax`, a **third-party upstream**; origin has 4
    commits local lacks, local has 1 origin lacks) + dirty WC. Per
    CLAUDE.md third-party rule + no-force rule: **do not push.** A
    `fork` remote (`lilith/fax`) exists but pushing there is a user
    decision, not a safe-push.

No `jj git push` was run. No bookmark moved. No commit made.

### A.3 DIRTY-UNCOMMITTED primary repos (reported, NOT touched)

Uncommitted changes, no fresh marker, origin unknown — treated as
sacred WIP:

| Repo | Dirty files (sample) | Read |
|---|---|---|
| commerce-corpus | Cargo.*, src/{render,verify_qoi,image_proc,main,tag}.rs (+A) | real WIP, local-only |
| zenjpeg-recompress | CHANGELOG/Cargo/README + ~15 new benchmark TSVs | real WIP, local-only |
| zenmetrics | ~20+ butteraugli-gpu/heaptrack files | **LIVE session** — skip |
| zensim | ~34 src/test files (matches this session's `git status`) | **LIVE session** — skip |
| aom-decoder-rs | Cargo.lock only | lockfile-only (regenerable) |
| BRAG | Cargo.lock(D), Cargo.toml, README.md, docs/index.html | real WIP (imazen) |
| zenblend | untracked `zenblend/` dir | stray dir |
| zendiff | untracked `.gitignore` | trivial |
| zensally | Cargo.toml + `training/__pycache__`, `training/checkpoints/` | real WIP + py caches |
| zensquoosh | 1-line lib.rs edit | trivial WIP |
| zentract | untracked bench_models*.py, ideas.md | scratch WIP |

None pushed/committed/discarded.

---

## (B) Worktree + branch inventory (report-only, no deletion)

### B.1 jj workspaces

**Sibling `--suffix` workspaces on disk: ~50.** Reachability of each
workspace's content-tip from a tracked remote bookmark + dirty-WC state
determines class. "MERGED-CLEAN" below = committed content reachable
from a remote bookmark AND clean WC (safe to clean *later*, pending user
OK). Dirty workspaces are kept regardless of reachability.

**Non-zensim suffix workspaces:**

| Workspace | Parent | Reach | Dirty | Class |
|---|---|---|---|---|
| jxl-encoder-gpu--afv-patches-cache | jxl-encoder-gpu | merged | 0 | MERGED-CLEAN |
| jxl-encoder-gpu--kavoid-chunk2 | jxl-encoder-gpu | merged | 0 | MERGED-CLEAN |
| jxl-encoder-gpu--kavoid-chunk3 | jxl-encoder-gpu | merged | 0 | MERGED-CLEAN |
| linear-srgb--pub-tf-x16 | linear-srgb | merged | 6 | UNMERGED/WIP (dirty + stale marker 2026-05-02) |
| zenanalyze--v11-docs | zenanalyze | merged | 0 | MERGED-CLEAN |
| zenanalyze--zenpicker-rename | zenanalyze | merged | 3 | UNMERGED/WIP (dirty; named bm feat/zenpicker-i8-agreement) |
| zenavif--av1-backends-spike | zenavif | merged | 10 | UNMERGED/WIP (dirty; abandoned/spike bm) |
| zenavif-parse--zmlp-extractor | zenavif-parse | merged | 0 | MERGED-CLEAN |
| zenavif-serialize--gainmlp | zenavif-serialize | merged | 0 | MERGED-CLEAN |
| zenjpeg--diagnostics | zenjpeg | merged | 18 | UNMERGED/WIP (dirty; `diagnostics` bm) |
| zenmetrics--cpu-bench-refresh | zenmetrics | merged | 0 | MERGED-CLEAN (but stale BLOCKED marker 01:59Z) |
| zenmetrics--cvvdp-cpu-kernels | zenmetrics | merged | 0 | MERGED-CLEAN |
| zenmetrics--hetzner-provider | zenmetrics | merged | 0 | MERGED-CLEAN (marker 2026-05-28) |
| zenmetrics--ptx-floor-bump | zenmetrics | merged | 0 | MERGED-CLEAN |
| zenmetrics--zenfleet-hoist | zenmetrics | merged | 0 | MERGED-CLEAN |
| zenmetrics--zensim-weights | zenmetrics | merged | 0 | MERGED-CLEAN |
| zenmetrics--acumen-gpu | zenmetrics | merged | 0 | MERGED-CLEAN |
| zenpipe--garb-deinterleave | zenpipe | merged | 0 | MERGED-CLEAN |
| zenpixels--fast-gamut-refactor | zenpixels | **1 unpushed** | 2 | UNMERGED/WIP |
| zenpixels--gamut-detect | zenpixels | merged | 6 | UNMERGED/WIP (dirty) |
| zenpixels--hdr-iqa-plumbing | zenpixels | merged | 0 | MERGED-CLEAN |
| zenpixels--pr33 | zenpixels | merged | 0 | MERGED-CLEAN |
| zentone--gainmap-mlp | zentone | merged | 0 | MERGED-CLEAN |
| zenwebp--libwebp-shim | zenwebp | merged* | 4 | UNMERGED/WIP (init prototype on root + dirty) |

**zensim suffix workspaces (29 on disk; all content-tips reachable from
remote bookmarks):** clean ones are MERGED-CLEAN, dirty ones kept.

- MERGED-CLEAN (clean WC): zensim--exp-chunkc-pergroup,
  zensim--exp-percentile-pool, zensim--v05-calibrate, zensim--recover,
  and the 4 detached `--at-*` checkouts (at-2dab8f3, at-a8d9c84,
  at-bb3f4a3, at-e565101), zensim--lastweek-baseline,
  zensim--v06-rebalance, zensim--productionize-v6 (separate git clone).
- UNMERGED/WIP (dirty WC — keep): zensim--372feat(6),
  zensim--bake-compare(8), zensim--canonical-corpus(1),
  zensim--compression-audit(1), zensim--cross-codec-v8(1),
  zensim--ex2-persample-alpha(1), zensim--ex2-stdpool-konjnd010(3),
  zensim--ex2-stdpool-nonin(3), zensim--ex-mix3(1),
  zensim--feature-audit(1), zensim--hybrid-runtime(12),
  zensim--konjnd-densify(5), zensim--persample-finetune(6),
  zensim--persample-runtime(11), zensim--pjnd-pairweighting(6),
  zensim--principled-activity(**36**), zensim--two-trail(7),
  zensim--v24-alpha(3).
- Several have `(divergent)` change markers (canonical-corpus,
  compression-audit, hybrid-runtime, persample-runtime, two-trail) —
  benign jj divergent-change state, not conflicts; do not "fix".

**ORPHANED workspace registrations (registered in `jj workspace list`
but NO directory on disk — harmless but cleanable later):**
- jxl-encoder-gpu: `afv-cost-grid`, `dropped-audit-2`,
  `entropy-mul-bundle`, `jxl-encoder-gpu--kavoid-entropy-port`,
  `jxl-encoder-gpu--patches-afv-preservation`,
  `jxl-encoder-gpu--upload-bw-probe`, `patches-fast-path`
- zenmetrics: `zenmetrics--spec-providers`
- zensim: `diffmap-public-ctors`, `zensim--exp-v22-hybrid`,
  `zensim--phase-4-zenblend`, `zensim--v6-reship`, `zengrid-analysis`,
  `zero-weight-elide`
  (These are `jj workspace forget <name>` candidates — no dir to rm.)

### B.2 git worktrees (plain-git)

`rav1d-safe` has one git worktree registered (the repo root itself,
`931edae [main]`) — normal, not a sibling worktree.

### B.3 Local branches with stranded (unpushed) work

Branches with commits **not on any remote** (genuinely stranded):

- **rawloader-fork:`approach-a-checked-default`** — 3 commits unpushed
  (`1c2c9ec`, `94cd50c`, `0c77ab4` — fuzzing-panic regression tests +
  scoped clippy deny). Third-party fork (origin = upstream rawler).
- **weezl:`wuffs-yield-on-full-fix`** — 1 commit `bd6a704` (marked
  "temp"); plus `wuffs-bench-compare`, `yield-on-full-regression`,
  `wuffs-bench-generators`(ahead 2), `chunked-decode-table-v2`(ahead 4)
  — all no-upstream / ahead-of-upstream. (lilith/weezl fork.)
- **rav1d-safe** abandoned branches: `abandoned/compact-guards`,
  `abandoned/narrow-guards`, `abandoned/narrow-guards-backup` (no
  upstream), `abandoned/copy-buffer-threading` (ahead 11, behind 241),
  `abandoned/rayon-threading` (upstream gone). Self-labelled abandoned.
- **fast-ssim2:`abandoned/archmage-migration`** — ahead 4 of its
  upstream (self-labelled abandoned).
- **zenlzw** (NO REMOTE): `main` + `archive/prescan-auto`,
  `archive/zenlzw-experimental`, `pr/weezl-optimizations` — entire repo
  is local-only, all branches unpushed.
- **zen-train-docker** (NO REMOTE): `main` (4 commits) — local-only.

---

## (C) Loose workspace docs (Phase 4)

`~/work/zen/` is **not a repo** (no `.git`, no `.jj`). Loose files at
root (all untracked, no canonical home):

ARCHITECTURE.md (18 KB), ARCHMAGE-AUDIT.md, ARM_DEV_BOX.md,
CONTEXT-HANDOFF.md, Cross.toml, **DATA_PROVENANCE.md (22 KB)**,
EXPERIMENTS-SURVEY-2026-05-17.md, FEATURE-FLAG-CLEANUP.md,
filter-repos.sh, fuzz-nightly.sh, image-cdn-comparison.md,
LOCAL_DISTRO_INVENTORY.md, ORACLE_ARM_BOX.md,
R2_ORGANIZATION_PLAN_2026-05-27.md, raw-processing-research.md,
RECOVERY_HANDOFF_2026-05-08.md, RECOVERY_PLAN_2026-05-08.md,
repo-list.txt, SECURITY-AUDIT-2026-03-31.md, Cargo.lock, justfile +
`scripts/{arm,install_mise.sh,setup-arm-box.sh,...}`.

**Finding:** NO canonical home and NO Tower mirror exists. Tower
(`/mnt/tower/output/`) has *data* dirs (zensim, zenjpeg, zenjxl,
zensim-archive-2026-05-20) but none of these meta-docs. `work-maintenance/`
is a loose (non-repo) licensing-helper dir, not a doc home.
DATA_PROVENANCE.md is referenced as the canonical ML index by the
project CLAUDE.md files but lives only as an uncommitted loose file —
**single point of failure** (a reboot wipes nothing here since it's
`~/work` not `/tmp`, but there is no version history or backup).

**Recommendation (user decides — I did NOT create or commit anything):**
Create a `imazen/zen-workspace-docs` git repo (or `lilith/`) and move
these meta-docs into it with history, OR mirror them to
`/mnt/tower/output/zen-workspace-docs/`. DATA_PROVENANCE.md +
the RECOVERY_*/EXPERIMENTS-SURVEY docs especially warrant version
control. Do NOT commit them into any existing crate repo (wrong scope).

---

## (D) Action lists for the user

### SAFE TO CLEAN — pending user OK (clean WC + content reachable from remote)

jj-workspace-forget + `rm -rf` candidates (verify `.workongoing` age
and that they're yours before removing):
- jxl-encoder-gpu--afv-patches-cache, --kavoid-chunk2, --kavoid-chunk3
- zenanalyze--v11-docs
- zenavif-parse--zmlp-extractor
- zenavif-serialize--gainmlp
- zenmetrics--cvvdp-cpu-kernels, --ptx-floor-bump, --zenfleet-hoist,
  --zensim-weights, --acumen-gpu  (NOT --hetzner-provider: marker
  2026-05-28; NOT --cpu-bench-refresh: BLOCKED-marker, likely paused)
- zenpipe--garb-deinterleave
- zenpixels--hdr-iqa-plumbing, --pr33
- zentone--gainmap-mlp
- zensim: --exp-chunkc-pergroup, --exp-percentile-pool, --v05-calibrate,
  --recover, --at-2dab8f3, --at-a8d9c84, --at-bb3f4a3, --at-e565101,
  --lastweek-baseline, --v06-rebalance, --productionize-v6

Orphaned workspace registrations (just `jj workspace forget <name>`, no dir): see §B.1.

### DO NOT TOUCH — has work / live / wild

- **LIVE:** zenmetrics (default — jobsys-spec marker fresh), zensim
  (default — panel session, this audit's parent).
- **DIRTY WIP (no remote / sacred):** commerce-corpus, zenjpeg-recompress,
  zenlzw, zen-train-docker (all local-only repos — back up before any
  cleanup), BRAG, zensally, zensquoosh, zentract.
- **UNMERGED/WIP workspaces (dirty):** all dirty workspaces in §B.1/B.2,
  notably zensim--principled-activity (36 dirty files),
  zensim--hybrid-runtime (12), zensim--persample-runtime (11),
  zenjpeg--diagnostics (18), zenavif--av1-backends-spike (10),
  zenpixels--fast-gamut-refactor (1 unpushed commit + dirty).
- **THIRD-PARTY / stranded branches:** fax (diverged third-party),
  rawloader-fork:approach-a-checked-default (3 unpushed), weezl temp/abandoned
  branches. Do not delete; user decides merge-vs-discard.
- **Stale-marker workspaces (likely paused, not dead):**
  linear-srgb--pub-tf-x16, zenanalyze--zenpicker-rename,
  zenmetrics--cpu-bench-refresh (BLOCKED), rav1d-safe/zenrav1e
  (zenvideo-tune).

---

## Discipline notes

- No `.workongoing` marker was written (read-only audit, no repo
  mutated). No commit, no push, no force, no worktree deletion, no
  `jj op restore`, no discard of any uncommitted change.
- This file (`WORKSPACE_AUDIT_2026-05-29.md`) is an intentionally-loose
  workspace doc, left untracked at `~/work/zen/` root alongside the
  other meta-docs (see §C).
