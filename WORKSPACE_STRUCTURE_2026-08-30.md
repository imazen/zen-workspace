# Zen crate tree: one workspace, or targeted fixes? — 2026-08-30

**Question asked:** could a unified single Rust workspace fix the dependency mess when
co-developing this crate tree, and can git/jj workspaces help? Constraints: reuse what
we can, keep it simple, make it faster to iterate across machines.

**Answer: no — don't build the monorepo. Three targeted fixes get most of the benefit,
and most of the tooling to do them already exists in this repo and is simply not wired
up.** The one problem a monorepo would fix structurally (version skew) is real and I do
not want to hand-wave it; see [§9 The strongest argument against this recommendation](#9-the-strongest-argument-against-this-recommendation).

Everything below was measured on 2026-08-30 against the tree on this Mac (`cargo 1.98.0`,
`rustc 1.98.0`). Cargo-semantics claims carry a test ID (T1–T11) and are reproducible from
[§10](#10-reproducing-the-cargo-semantics-tests). Nothing outside `~/tmp` was modified.

---

## 1. The headline numbers

| Fact | Value |
|---|---|
| Canonical repos (physically distinct) | **73** (76 listed; 3 are symlink aliases) |
| Repo-root manifests declaring `[workspace]` | **37** (22 virtual, 15 package+workspace hybrids) |
| Workspace members declared at those roots | **190** |
| Unique `Cargo.toml` manifests in the tree | **505** |
| Sibling path deps (escaping their own repo) | **99**, across **65** distinct repo→repo edges |
| …of which are **broken today** | **15** |
| `[patch.*]` entries | **231**, in 33 manifests, covering 59 distinct crates |
| Nested standalone sub-workspaces (`fuzz/`, `apidoc/`, …) | **101** |
| …carrying a **duplicated** patch table | **18** |
| Crates patched to **conflicting sources** across repos | **10** (3 of them to *three* sources) |
| Git patches floating on a default branch | **35** |
| **Inert** patches (on-disk version can't satisfy the requirement) | **30** |
| Sibling-clone steps across all CI | **235**, of which **95 (40%) float on a default branch** |
| Repos whose CI cannot resolve their own path deps | **4** (3 red now, 1 latent) |
| `superwork check` result today | **exit 1 — 234 errors, 42 warnings** |
| `rav1d-safe` builds resolved simultaneously | **5** (3 git revs + 2 registry versions) |

---

## 2. Method, and one methodological warning

Static analysis used `tomllib` (not regex) over all 505 manifests — 0 parse errors. Cargo
semantics were tested against synthetic fixtures in `~/tmp`. The prototype in
[§5](#5-b-the-cheaper-middle-path-that-actually-works) runs against **pristine `git archive`
copies of the real repos**, so the real repos were never touched.

`cargo metadata --format-version 1 --locked` is the non-mutating probe, and it earns its
keep: it separates a genuine unresolvable requirement from a merely stale lock. Run today,
`zenanalyze`, `zenjpeg`, `jxl-encoder`, `zenjxl` and `zenpipe` all resolve clean, and
`zenmetrics` fails with `cannot update the lock file ... because --locked was passed` —
a **stale lock**, not a resolution failure. I could not reproduce the
`failed to select a version for the requirement zenanalyze = "^0.2.0"` errors as a current
steady state; they were transient states during the day's work. What is reproducible is the
structural cause and the CI-side failure, both documented below.

**Warning worth keeping:** the local `zenmetrics` worktree is ~13 h behind `master@origin`
and does not contain the deps that are breaking CI. **A purely local check would have
refuted a true claim.** Verify cross-repo claims against `@origin`, not the working tree.

---

## 3. What cargo actually permits — the five facts the design turns on

These were the open questions. Four of the five answers rule something out.

**T1 — Workspace members may NOT live outside the workspace root directory.** The owner's
instinct was right; path *dependencies* may point outside, members may not:

```
error: workspace member `/Users/lilith/tmp/wsproto/repoA/crateA/Cargo.toml`
is not hierarchically below the workspace root `/Users/lilith/tmp/wsproto/umbrella/Cargo.toml`
```

So `members = ["../zenjpeg/zenjpeg"]` is dead. **The naive dev-umbrella is impossible.**

**T3 — But a root placed in the *parent* directory of the repos works.** A
`/Users/lilith/work/zen/Cargo.toml` with `members = ["zenjpeg/zenjpeg", …]` satisfies the
hierarchy rule with no git history moved. That is the only shape a monorepo-without-a-merge
could take.

**T4 — …except every member must first stop being a workspace root.**

```
error: multiple workspace roots found in the same workspace:
  /Users/lilith/tmp/wsproto2/repoA
  /Users/lilith/tmp/wsproto2/repoB
  /Users/lilith/tmp/wsproto2
```

That is **37 root manifests** that must lose `[workspace]` (and with it their members globs,
`exclude` lists, `workspace.dependencies` and profiles), after which **none of them builds
standalone**. This is the real price of A, and it is not small.

**T2 — A symlink farm does not rescue it.** Cargo resolves a member's relative path deps
against the *symlink* location, not the real directory:

```
failed to read `/Users/lilith/tmp/wsproto2/umbrella2/repoA/crateA/Cargo.toml`
```

A farm only works if you also rewrite every relative path dep — i.e. generate manifests.
That fails "keep it simple".

**T5 — `[patch.crates-io]` in a parent `.cargo/config.toml` works, with zero manifest edits.**
Cargo discovers config by walking up from the CWD, so one file above the repos applies to
all of them. Relative paths inside it are anchored at **the directory containing `.cargo/`**,
not the CWD — stable and predictable, which is what you want for a shared table. Verified
resolving *and compiling* (T5c). This is the fact the recommendation rests on.

**T6 — and nested standalone sub-workspaces inherit it.** A `fuzz/` directory with its own
`[workspace]`, which inherits nothing from anything, picked up the parent config patch.
**This is the decisive asymmetry: the config table fixes the 18 duplicated sub-workspace
patch tables; a monorepo cannot, because those directories are not members.**

Two more that matter for safety and cost:

**T7/T8 — config and manifest patch tables *merge* for different crates, but for the same
crate the config silently wins.** No warning. Good for incremental migration (add the config
table without touching a manifest); a hazard if a repo has a deliberate divergent pin. See
[§8](#8-what-breaks-what-it-costs-and-what-this-does-not-fix).

**T10 — `cargo …--workspace` unifies features across members; `-p` does not.** A shared
dependency was built with a member's `heavy` feature enabled under `--workspace`, and without
it under `-p`. In a monorepo, `cargo test --workspace` would build shared deps with the union
of every member's features — the GPU/CUDA features in `zenmetrics` would leak into every
build that shares a dependency with it.

**T11 — a shared `CARGO_TARGET_DIR` already gives cross-workspace artifact reuse.** Two
separate workspaces, same target dir: the second compiled only itself and reused both
dependencies. The monorepo's build-cost advantage is available today for the price of one
environment variable.

---

## 4. (A) Would one unified workspace fix it?

Per problem, honestly.

**#1 patch composition — partially, and it loses to the config table.** In-tree path deps
inside one workspace need no patch entries at all, so the 85 patch entries in root manifests
mostly evaporate. But **101 nested sub-workspaces are not members and inherit nothing**;
the 18 that duplicate a patch table would still duplicate it. The config table fixes all of
them (T6). Note the sub-workspaces are separate by **convention, not necessity** —
`zenutils` makes its fuzz dir a member, proving it is possible — but making 21 fuzz dirs
members means `cargo build --workspace` starts pulling `libfuzzer-sys` and nightly-only
sanitizer deps into everyone's build. That is why the convention exists, and it is a good
reason to keep it.

**#2 / #3 sibling clones and floating branches — yes, fixed by construction.** Nothing to
clone, one branch, one commit. This is the monorepo's genuine win, and today's cost is
concrete: **235 clone steps across CI, 95 of them floating.** `zenmetrics` performs **105
sibling clones per run** (21 repos × 5 jobs). `zenjpeg` has 50 clone steps and **every one
floats**, so a push to `imazen/zenanalyze` can turn `zenjpeg` red with no zenjpeg commit.
What replaces it in CI: path-filtering (`paths:` / `dorny/paths-filter`) plus `-p` scoping,
which you need anyway to avoid T10's feature unification.

**#4 version skew — yes, structurally, and this is the monorepo's best argument.** One lock
means one version, full stop. Today `rav1d-safe` is resolved as **five distinct builds
simultaneously** — three git revs (`66f58fa6`, `140f9145`, `f6aed27e`) plus registry `0.5.7`
and `0.5.5`. The rev `140f9145` is named in **no manifest at all**; it arrives transitively
through a `zenavif` git patch and is locked in 8 places. Four lockfiles
(`zenmetrics`, and three under `zensim/`) pin a rev their own manifests can no longer
produce.

The same disease in miniature, live in `jxl-encoder` right now:
`jxl-encoder/jxl-encoder/Cargo.toml` requires `zenjxl-decoder = "0.3.8"`, the sibling on
disk is **0.4.0**, so the repo's own `[patch] zenjxl-decoder = { path = … }` is **silently
inert** — cargo cannot use a 0.4.0 patch for a `^0.3.8` requirement, falls back to registry
`0.3.10`, and emits only a `patch ... was not used in the crate graph` warning. Three lines
above the patch, a comment says "Path-patched to the local sibling." **The comment stopped
being true when zenjxl-decoder went 0.4.0, and nothing caught it.**

**#5 registry truth — a monorepo makes this WORSE, and this is the problem that reaches
users.** Verified today: published `jxl-encoder 0.3.1` **does not build from crates.io** —
44 errors compiling `jxl-encoder-simd 0.3.0` against `magetypes 0.9.28` (`f32x4::raw()` and
`from_float32x4_t` no longer exist). Local builds never saw it because every local build
resolves through path deps. A monorepo makes *every* build path-resolved, removing even the
accidental chance of noticing. **Whatever else is decided, #5 needs a deliberate gate**
([§7 step 3](#7-migration-path-start-small-abandon-cheaply)).

**#6 unpublished crates — yes for in-tree crates**, same mechanism as #4.

**#7 `cargo fmt --all` reaching into siblings — unchanged.** It is a `--all` scoping problem,
not a workspace-topology problem; a monorepo arguably makes it worse by making "all" mean 190
members. Fix is unchanged: scope to in-repo members.

**Cost.** Measured, not hand-waved: across the 7 repos I resolved, the per-repo dependency
graphs sum to **1,614 packages** but the deduplicated union is **659** — a **2.45× duplication
factor**, so a monorepo genuinely compiles less. But **T11 shows a shared `CARGO_TARGET_DIR`
captures that same reuse today**, and T10 shows `--workspace` costs you feature unification
that `-p` does not. Current CI wall-clock for the big repos: zenmetrics **88.8 min** (11
jobs), zenpipe **66.4**, zenjpeg **56.8**, imageflow **39.0**, rav1d-safe **21.6**. A
`--workspace` build over 190 members including CUDA/burn-adjacent code would exceed all of
them; `-p` scoping plus path-filtering is not an optimization there, it is mandatory.

**What genuinely cannot join.** All confirmed as GitHub forks with live upstream parents:

| Repo | Upstream parent |
|---|---|
| `dssim` | `kornelski/dssim` |
| `jxl-oxide` | `tirr-c/jxl-oxide` |
| `moxcms` | `awxkee/moxcms` |
| `image-tiff` | `image-rs/image-tiff` |
| `fax` | `pdf-rs/fax` |
| `rust-rgb` | `kornelski/rust-rgb` |
| `mozjpeg` | `mozilla/mozjpeg` |

Plus `jpegli` (a direct `google/jpegli` clone, not even a fork), the data repos
(`codec-corpus` 0.92 GB of git, `zentrain-corpus` 0.47 GB), and anything on an independent
release cadence — `archmage`/`magetypes` most sharply, since `magetypes 0.9.28` is precisely
what breaks published `jxl-encoder-simd`.

**Verdict on A:** it fixes #2/#3/#4/#6, does not fully fix #1, makes #5 worse, does nothing
for #7, and costs 37 manifest restructurings after which no repo builds standalone.

---

## 5. (B) The cheaper middle path that actually works

The umbrella-with-external-members is impossible (T1). What works is **one generated
`.cargo/config.toml` above the repos**, carrying the union of every repo's patch table.

### The prototype

Built at `~/tmp/zenproto` from **pristine `git archive` copies of 16 real repos**
(371 MB), driven by `~/tmp/zenproto/build_umbrella.py`, which:

1. reads every repo-root manifest's `[patch.*]` tables,
2. reports crates patched to **different sources** in different repos,
3. reports git patches floating on a default branch,
4. emits one unified `[patch.crates-io]` table (paths rewritten absolute),
5. **strips the `[patch]` section from every mirrored manifest.**

Generalised to the whole tree, `scripts/patch-conflict-audit.py` reports over 61 repos
and 85 root-manifest patch entries:

- **10 crates are patched to conflicting sources**, three of them to *three* different
  sources: `zenjpeg`, `zenjxl-decoder`, `zenwebp`. Also `zenanalyze`, `zenavif`, `zenjxl`,
  `zenpng`, `zensim`, `jxl-encoder`, `ultrahdr-core`.
- **35 git patches float on a default branch.**
- **30 inert patches** — a path patch whose on-disk version cannot satisfy the requirement
  it is meant to override.

The worst case:

```
zenanalyze: 2 different sources
   path  /Users/lilith/work/zen/zenanalyze     <- jxl-encoder, zenmetrics
   git   imazen/zenanalyze @ <default-branch>  <- ultrahdr, zenjpeg, zenjxl,
                                                  zenpipe, zensr, zenwebp
zenjpeg: 3 different sources
   git   imazen/zenjpeg @ main                 <- imageflow
   path  /Users/lilith/work/zen/zenjpeg/zenjpeg <- jxl-encoder, zenjxl
   git   imazen/zenjpeg @ <default-branch>     <- zenpipe
```

That is problem #4 caught by one script: build `zenjxl` and you get zenanalyze from a
floating git branch; build `jxl-encoder` and you get it from disk. Different code, silently.
The inert list catches the `jxl-encoder` case described in §4 and four more of the same
shape, including `zenimage` patching `butteraugli` it cannot use (`requires '0.8'`, disk is
`0.9.4`) and `codec-eval` patching `zenjpeg` (`requires '0.3'`, disk is `0.9.0`).

### The result

With **all manifest patch tables removed** and **one** shared config, on the real manifests:

```
zenanalyze       RESOLVES
zenjpeg          RESOLVES
jxl-encoder      RESOLVES
zenjxl           RESOLVES
zenjxl-decoder   RESOLVES
zenwebp          RESOLVES
zenpng           RESOLVES
```

…and `zenanalyze` now resolves to **the same path in all three** consumers that previously
disagreed. This is the exact chain that broke repeatedly.

### Why this is the right shape

- **One file, no manifest edits.** 231 patch entries collapse to one table.
- **It reaches where a monorepo cannot** — the 18 sub-workspace duplicates (T6).
- **It merges rather than replaces** (T7), so it can be adopted repo-by-repo.
- **Abandoning it is `rm` of one file.**
- **It is already half-built here.** `Superwork.toml` has a `[ci.patch_repos]` map of ~110
  crate→URL entries and `cargo superwork ci-patch-list` regenerates it (178 lines, runs
  clean today). The generator exists; only the emit-as-`.cargo/config.toml` target is missing.

### The one honest limitation

A unified table does **not** force version unification. Cargo applies a patch only if its
version satisfies the requirement, else it silently falls back to the registry — exactly the
`jxl-encoder`/`zenjxl-decoder` case, which reproduced inside the prototype. You get a
`patch ... was not used in the crate graph` **warning**, not an error. So this makes skew
*visible and centrally located*; it does not make it *impossible*. Only the monorepo does
that.

---

## 6. (C) Do git worktrees / jj workspaces help?

**No.** Both are per-repo mechanisms. Neither has any effect on cross-repo dependency
resolution, which is where every problem on the list lives. They also actively add divergent
resolution contexts: the tree currently holds **11 `--`-suffixed worktree dirs plus 11 hidden
ones under `.claude/worktrees/`** that the `--` naming convention does not catch. One of the
hidden ones — `zenavif/.claude/worktrees/maint-review-zensim-loop/` — is a real 17 MB tree
with **its own `[patch]` tables and its own `Cargo.lock`**, i.e. a 12th independent answer to
"which rav1d-safe are we on". Given the recorded 145-worktree incident, the recommendation is
to prune, not add: `cargo superwork worktrees` already inventories them.

Of the cross-repo alternatives:

- **Submodules / `git subtree`** — solve "get the right revisions together", but pin every
  sibling explicitly, so the daily edit-two-repos-at-once loop becomes a pointer-bump per
  edit. Worse for iteration speed, which is the stated goal.
- **A repo-manifest tool** — the right answer, and **it already exists here**:
  `Superwork.toml` with `scan_dirs`/`extra_roots` plus `cargo superwork setup`
  ("Clone all ecosystem repos on a new machine").
- **Sparse / partial clone** — solves a size problem this tree does not have (§7).

---

## 7. (D) Cross-machine

The cost is smaller than it looks, and it is not the git.

- **63 repos = 4.0 GB of `.git` total.** Two repos dominate: `codec-corpus` (0.92 GB) and
  `zentrain-corpus` (0.47 GB), both data. Source repos are small.
- **42 `target/` dirs = 128 GB.** This is the actual per-machine cost, it is rebuilt not
  cloned, and a monorepo does not remove it — though a **shared `CARGO_TARGET_DIR` measurably
  shrinks it** (T11 verified reuse; 2.45× duplication measured).

So: `cargo superwork setup` for the clone, one shared `CARGO_TARGET_DIR`, and one shared
`.cargo/config.toml`. That is the whole per-machine cost.

The genuine cross-machine blocker is different and already present: **15 broken sibling path
deps**, three of which are hard-coded foreign absolute paths that can never resolve here —
`/home/lilith/work/codec-eval` (a Linux path, in `zenjpeg/internal/jpegli-cpp/jpegli-rs/`,
inside `workspace.dependencies`) and `/root/aom-rs/crates/aom-decode` (a container path, in
`zenav1-svt/rust/tools/decode_diff/`, replicated into two worktrees). `glassa` has 8 of 9
sibling deps dead, including two `../zen/...` paths written from *inside* `zen/`, resolving
to `zen/zen/...`. **A monorepo would not have prevented any of these; `superwork check`
catches them today.**

---

## 8. What breaks, what it costs, and what this does NOT fix

**Risks of the recommendation.**

- **T8 is the sharp edge**: where a repo deliberately pins a crate differently from the
  ecosystem default, the config table silently overrides it, with no warning. Mitigation:
  keep the generated table to genuinely-shared crates, and diff
  `cargo metadata` with and without `--config` in CI for any repo that had its own pin.
- **Lockfile churn.** Introducing or removing the table changes resolution; every repo
  re-locks once. Expect one noisy commit per repo, and use `--locked` afterwards to detect
  drift.
- **Discoverability.** A patch table that is not in the manifest is a table a newcomer will
  not find. It must be generated, checked in, and named in each repo's CLAUDE.md.

**What it does not fix.**

- **Version skew remains possible** (§5's limitation) — only detectable, not impossible.
- **`cargo fmt --all` reaching into siblings** — unchanged, and unrelated to topology.
- **Published-crate breakage** is not fixed by any topology; it needs the gate in step 3.
- **`glassa`'s 8 dead path deps** and the foreign absolute paths need hand repair regardless.

**The gate that already exists and is broken.** `cargo superwork check` runs today and exits
1 with **234 errors / 42 warnings** over 255 crates and 1,101 internal deps:

| Class | Count | Assessment |
|---|---|---|
| Dual-spec (path-only dep, needs version to publish) | 84 | Real, but noisy — many are unpublishable binaries |
| **Version consistency** | **70** | **Real — this is problem #4, already detected** |
| Path validity | 80 | **72 (90%) are false positives** |
| Unknown references | 7 warnings | Real (`glassa`, `zenav1-svt`) |

The path-validity false positives come from **one bug**: for a dep declared
`{ workspace = true }` in a member, superwork resolves the *root's* path relative to the
*member's* directory. `zenmetrics-api → butteraugli-gpu` is reported missing at
`crates/butteraugli-gpu`, which exists — relative to the workspace root, where the root
manifest declares it. **This is why the gate is not wired into CI: its loudest class is 90%
noise, so nobody trusts it.** Fixing that one resolution rule is the highest-leverage change
available, because the same tool already detects problems #2, #3, #4 and the cross-machine
path breakage.

---

## 9. The strongest argument against this recommendation

**The monorepo makes correctness structural; my recommendation makes it discipline-dependent
— and the discipline has already failed, repeatedly, in writing.**

`zenmetrics` master is red right now. Three path deps on `zenav1-aom` landed in commit
`2690d66e` (2026-08-30 05:17Z); `ci.yml` mentions `zenav1-aom` **zero times**; all 9 jobs die
at manifest load before compiling anything:

```
failed to load manifest for dependency `zenav1-aom-bench`
Caused by: failed to read `/home/runner/work/zenmetrics/zenav1-aom/crates/aom-bench/Cargo.toml`
```

Twelve consecutive failures; last green was 2026-08-29 17:24Z. And zenmetrics' own
`CLAUDE.md` **already documents the exact rule** — from the identical `zenflate` incident on
2026-07-29 — that every new sibling path dep needs a matching clone in all five copies of the
clone step. **The rule was written down, then violated three days later.** `Superwork.toml`
carries a similar comment recording how a missing `zenanalyze` clone broke zenpipe CI on
2026-06-12.

That is the case for A: a documented rule, a tool that detects violations, and a repo that
went red anyway. Under one workspace this class of failure cannot occur — there is nothing to
clone, nothing to pin, and one lock. Three repos are red today for reasons a monorepo would
make unrepresentable (`zenmetrics`, `zenimage`, `imageflow-server-rs`), and a fourth
(`glassa`) is latently broken.

**Why I still recommend against it.** The monorepo trades a failure mode that is *loud,
local, and caught within minutes by CI* for one that is *silent and reaches users* — verified
today as `jxl-encoder 0.3.1`, published and unbuildable, 44 errors, invisible in-workspace. It
also costs 37 manifest restructurings after which no repo builds standalone, and it cannot
absorb the 7 upstream forks or the 101 sub-workspaces. The targeted fixes reach all of those.

**The tiebreaker is the false-positive bug.** The reason to believe "wire up the gate" is not
just optimism this time: the gate has never had a fair run. It is 90% noise in its loudest
class, so its 70 genuine version-consistency findings — problem #4, exactly — have been
drowned out. Fix that one bug and turn the check red-blocking, and if the tree *still* drifts
after that, the structural argument wins and this decision should be revisited. That is a
falsifiable test, and it costs about a day rather than a quarter.

---

## 10. Migration path: start small, abandon cheaply

Ordered by leverage per hour. **Each step is independently valuable and independently
reversible.** Nothing here requires the next step to be worth doing.

**Step 1 — fix `superwork check`'s workspace-inheritance path resolution (~1 h).**
Resolve `{ workspace = true }` inherited path deps against the workspace root, not the member
directory. Removes 72 of 80 false positives. Then triage what is left: 8 real path errors,
70 version-consistency errors, 84 dual-spec.
*Abandon:* revert one commit. *Fixes:* makes #2/#3/#4 detectable and believable.

**Step 2 — teach `superwork ci-patch-list` to emit `.cargo/config.toml`, and generate one
(~1 h).** The crate→URL map and the generator already exist. Emit the dev table at
`/Users/lilith/work/.cargo/config.toml`; check it in; verify with `cargo metadata --locked`
per repo. Then delete per-repo `[patch]` tables opportunistically — T7 means both can coexist
indefinitely, so this never has to be a big-bang.
*Abandon:* `rm` one file. *Fixes:* #1 including the 18 sub-workspaces, and centralises #4/#6.
*Verify against the prototype:* `~/tmp/zenproto/build_umbrella.py` already does this end-to-end.

**Step 3 — a registry-truth gate (~half a day).** One CI job per publishable crate that
builds with the dev patches **off**. `superwork ci-prep` / `unpatch` already perform exactly
this transformation, and `Superwork.toml` already declares
`[ci] default_strategy = "strip_path"` plus `[ci.overrides]` that delete `patch.crates-io`.
Run it on the publish wave.
*Abandon:* delete one job. *Fixes:* **#5 — the only problem that reaches users**, and the one
a monorepo would make worse.

**Step 4 — make the CI gap unrepresentable (~half a day).** `zenjpeg` already has the right
pattern and it is the only one in the tree: a guard step that greps for surviving
out-of-checkout path deps and hard-fails with
`::error::a path dependency still points outside the checkout`. Add that guard to
`ci-gen`'s template and sync it everywhere; replace the 5 hand-copied clone blocks with
`superwork ci-clone`; pin the 95 floating clones.
*Abandon:* revert the template. *Fixes:* #2/#3 at the source — zenmetrics would have gone red
on the *manifest edit*, not six hours later.

**Step 5 — cheap wins, minutes each.** Set a shared `CARGO_TARGET_DIR` (T11 — measured
2.45× dedup). Document `cargo superwork setup` as the machine-2 procedure. Run
`superwork worktrees` and prune the 22 stale trees, including the 11 hidden under
`.claude/worktrees/` that the `--` convention misses.

**Only if steps 1–4 land and the tree still drifts:** revisit the monorepo, and scope it to
the tight core (`zenanalyze`, `zenjpeg`, `jxl-encoder`, `zenjxl`, `zenjxl-decoder`) — five
repos, not 73 — leaving the 7 upstream forks, the independently-released `archmage`/`magetypes`,
and the data repos outside. That is a weekend, and it is a decision better made with a
believable `superwork check` than without one.

---

## 11. Reproducing the cargo-semantics tests

Fixtures under `~/tmp` (scratch; recreate as needed). All are seconds to run.

| ID | Claim | Fixture |
|---|---|---|
| T1 | Members outside the root are refused | `~/tmp/wsproto/umbrella` |
| T2 | Symlink farm breaks relative path deps | `~/tmp/wsproto/umbrella2` |
| T3 | A root in the repos' parent dir works | `~/tmp/wsproto/Cargo.toml` |
| T4 | Members declaring `[workspace]` are refused | `~/tmp/wsproto2` |
| T5 | Parent `.cargo/config.toml` `[patch]` applies, anchored at the config dir | `~/tmp/wsproto3` |
| T6 | Nested standalone sub-workspaces inherit it | `~/tmp/wsproto3/repoB/fuzz` |
| T7 | Config + manifest patches merge (different crates) | `~/tmp/wsproto3/repoC` |
| T8 | Config wins silently (same crate) | `~/tmp/wsproto3/repoC` |
| T9 | `cargo --config <file>` works for `[patch]` | `~/tmp/altconfig.toml` |
| T10 | `--workspace` unifies features, `-p` does not | `~/tmp/featws` |
| T11 | Shared `CARGO_TARGET_DIR` reuses artifacts across workspaces | `~/tmp/sharedtarget` |

Real-tree prototype: `~/tmp/zenproto/` (16 `git archive` copies + `build_umbrella.py`),
which demonstrates the strip-manifests-and-share-one-config end state.

The cleaned-up conflict detector is committed at `scripts/patch-conflict-audit.py` and runs
against the live tree, read-only:

```bash
python3 scripts/patch-conflict-audit.py                 # audit; exit 1 on findings
python3 scripts/patch-conflict-audit.py --emit-config /Users/lilith/work/.cargo/config.toml
```

It should be folded into `cargo superwork check` rather than maintained separately — it
overlaps that tool's version-consistency analysis and adds the conflict/floating/inert
classes. Note it currently reads **root** manifests for patch tables (85 entries); the 18
duplicated sub-workspace tables are counted in §1 by a separate full-tree walk.

Registry-truth check (verifies #5 in ~2 min):

```bash
cargo new --lib /tmp/x && cd /tmp/x
cargo add jxl-encoder@=0.3.1 && cargo check   # 44 errors in jxl-encoder-simd 0.3.0
```
