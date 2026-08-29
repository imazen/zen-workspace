# Zen publish-order map — 2026-08-29

**Status:** read-only audit. Nothing was published, pushed, or edited.
**Location note:** the requested path `~/work/zen/PUBLISH_ORDER_2026-08-29.md` is not inside a git
repo (`~/work/zen` is a plain directory holding ~70 independent checkouts), so this doc lives in the
`zen-workspace` repo instead, per the fallback in the brief.

---

## 0. How this was derived

| Evidence | Coverage |
|---|---|
| Static manifest parse | 424 `Cargo.toml` files across 70 repos; `workspace = true` inheritance resolved against the **nearest ancestor** workspace root (nested workspaces exist — `zenjpeg/internal/jpegli-cpp/jpegli-rs`, `zenav1-svt/rust`) |
| crates.io sparse index | every publishable crate name (190), full version list **including yanked flags** and the recorded dependency `req`s of published releases |
| `cargo publish --dry-run --no-verify` | **zenanalyze only** (real repo; run with `--locked` + redirected `CARGO_TARGET_DIR` so it wrote nothing into the repo) |
| Synthetic reproductions in `~/tmp` | each failure mode reproduced in a throwaway crate to pin down exact cargo behaviour — see §3 |

**Why only one real dry run.** At 17:31Z, 11 of the wave repos (`zencodec`, `zensim`, `zenjpeg`,
`jxl-encoder`, `zenwebp`, `zenpng`, `zengif`, `zenjxl-decoder`, `zenavif`, `zenpipe`, `zenrav1e`)
carried a **fresh `.workongoing` marker** from other live agents. Per the concurrency protocol those
repos were not touched. This is a real limitation, stated plainly: the per-crate verdicts below for
those repos come from manifest + registry analysis, not from an executed dry run. The analysis is
mechanical and the rules behind it were verified empirically (§3), but a dry run can still surface a
**compile** failure that manifest analysis cannot — see §11.

---

## 1. The answer — publish order

Seven waves. Everything inside a wave is independent and can go in any order (or in parallel).
Nothing in wave *N* can start until every crate it lists under "after" has landed on crates.io.

```
WAVE 1  butteraugli 0.9.4 · zenanalyze-api 0.1.1 · zenpredict 0.2.0 · zenavif-parse 0.7.0
        zenavif-serialize 0.2.0 · zenbitmaps 0.2.0 · zengif 0.8.0 · zenjxl-decoder 0.4.0
        zenpng 0.2.0 · zenrav1e 0.2.0 · rav1d-safe 0.6.0 · jxl-encoder-macros 0.3.2
        jxl-encoder-simd 0.3.2 · heic-core 0.2.0 · zensally 0.1.0 · zentract-types 0.1.0
        zenwasm-types 0.1.0

WAVE 2  butteraugli-cli 0.9.4 · zenanalyze 0.2.0 · zenpicker 0.1.0 · zenpredict-bake 0.1.0
        zensim 0.3.0 · zenravif 0.2.0 · heic-backend-* 0.2.0 (×5)
        zensally-tract · zensally-zentract · zentract-abi · zentract-api
        zenwasm-abi · zenwasm-api

WAVE 3  zenjpeg 0.9.0 · zenwebp 0.5.0 · zensim-regress 0.4.0 · zenavif 0.1.8 (NOT 0.1.7 — see §8.2)

WAVE 4  jxl-encoder 0.3.2 · ultrahdr-rs 0.4.1 · heic 0.2.1 (NOT 0.2.0 — see §8.2) · squintly 0.1.0

WAVE 5  jxl-encoder-cli 0.3.2 · zenjxl 0.3.0

WAVE 6  zencodecs 0.1.0

WAVE 7  zenfilters 0.1.2 (NOT 0.1.1 — see §8.2) · zenpipe 0.1.0
```

**The spine**, if you only remember one chain:

```
zenanalyze-api 0.1.1  ->  zenanalyze 0.2.0  ->  zenjpeg 0.9.0  ->  jxl-encoder  ->  zenjxl
                          zenpredict 0.2.0  ->  zensim 0.3.0   ->  ^
```

`zenanalyze-api 0.1.1` and `zenpredict 0.2.0` are the two true roots. Neither is blocked by anything.
**Nine crates in the wave sit behind `zenanalyze 0.2.0`** and **eight behind `zenjpeg 0.9.0`** — those
two are the throughput bottlenecks.

**No cycle exists.** See §7 — an apparent `zenjpeg ↔ zensim` cycle dissolves under the correct rules,
but it re-forms if one specific manifest fix is done the obvious way. That is the one decision that
could still make a clean order impossible.

---

## 2. The relayed constraints — verdicts

| # | Claim | Verdict |
|---|---|---|
| 1 | `zenanalyze-api 0.1.1` before `zenanalyze 0.2.0` | **CONFIRMED** — mechanism corrected |
| 2 | `zencodec-testkit` before/with `zencodec 0.2.0` | **CONFIRMED** — and it needs a version bump nobody has made |
| 3 | `zensim 0.3.0` before `zenjpeg` can publish at all | **PARTLY CORRECTED** — right blocker, wrong cause, and incomplete |
| 4 | `butteraugli 0.9.4` + `zenanalyze 0.2.0` gate `jxl-encoder 0.4.0` | **HALF WRONG** — and the real blockers are worse |
| 5 | zenavif is unpublishable; versionless deps, not a CI problem | **CONFIRMED** — count corrected from 7 to 4, and it is **not the only one: 21 crates are in this state** (§5) |

### 1 — CONFIRMED, mechanism corrected

`zenanalyze/Cargo.toml` declares `zenanalyze-api = { version = "0.1.1", path = "zenanalyze-api", optional = true }`.
crates.io has only `zenanalyze-api 0.1.0`. Executed dry run:

```
$ cargo publish -p zenanalyze --dry-run --no-verify --allow-dirty --locked
error: failed to prepare local package for uploading
Caused by:
  failed to select a version for the requirement `zenanalyze-api = "^0.1.1"`
  candidate versions found which didn't match: 0.1.0
```

**Correction:** the failure is a **version-resolution** failure at packaging time, not "unresolved
imports". The manifest already asks for `0.1.1`, so packaging dies before any code is compiled. (An
unresolved-import failure is what you'd get if the manifest still said `0.1.0` while the source used
the new symbols.) The distinction matters because it means the blocker fires with `--no-verify` and
costs seconds to check, not a full verification build.

`FeatureProvider`, `ProviderError`, `OwnedCatalog`, `Select::Names` all exist in
`zenanalyze/zenanalyze-api/src/` and are absent from published `0.1.0`. The optional/feature-gated
status of the dep is irrelevant — cargo resolves optional dependencies too (verified, §3).

### 2 — CONFIRMED, with a bump nobody has made

Published `zencodec-testkit 0.1.0` records `zencodec req=^0.1.26` in the index — read directly from
the sparse index, not inferred. `^0.1.26` on a 0.x crate means `>=0.1.26, <0.2.0`, so it excludes
`0.2.0` and a consumer taking testkit from the registry gets two zencodec copies. Confirmed.

**Two things the relayed version omits:**

* The **fix is already committed in-tree** (`4391021 deps: widen zencodec/zenpixels requirements to
  current-plus-next minor`). The local manifest reads `zencodec = { path = "..", version = ">=0.1.26, <0.3.0" }`.
  It is simply unpublished.
* **`zencodec-testkit 0.1.0` is already taken on crates.io.** The widened range cannot ship under
  that number. Somebody must pick `0.1.1` — that is an unmade decision, not just an ordering fact.

**`zencodec 0.2.0` is not in this wave at all.** The manifest still says `0.1.26`, which is published.
`0.2.0` is a planned breaking release with an unshipped `### QUEUED BREAKING CHANGES` list
(`OutputInfo` rename, `ThreadingPolicy` and `ResourceLimits` ablation, `icc` module removal). It gates
nothing currently pending. Good news for whenever it does ship: every in-scope consumer already
declares `zencodec = ">=0.1.26, <0.3.0"` and will accept `0.2.0` unchanged. The only narrow pins left
are in out-of-scope trees (`imageflow_core` `0.1.24`, retired `zenimage` `0.1.8`, and the
`zenavif--encode-rd` sibling worktree).

### 3 — right blocker, wrong cause, and incomplete

Confirmed that zenjpeg cannot publish and that a versionless dependency is why. The details differ:

* The dep is **pinned by `rev`, not "at 0.3.0"**:
  `zensim = { git = "https://github.com/imazen/zensim", rev = "9d8f73a5…" }` in zenjpeg's
  `[workspace.dependencies]`. There is no version number in it at all.
* **It is not the only one.** `zenyuv = { path = "zenyuv" }` — also versionless, also a normal dep,
  also fatal. Fixing only the zensim line leaves zenjpeg unpublishable.
* `zenpredict` is a third (versionless path dep, optional).
* **zenjpeg's real ordering blocker is `zenanalyze 0.2.0`**, not zensim: zenjpeg declares
  `zenanalyze = { version = "0.2.0" }` against a registry that tops out at `0.1.0`. That edge is
  unconditional and cannot be fixed by editing zenjpeg.
* Whether `zensim 0.3.0` must precede zenjpeg **depends on a decision**: zenjpeg's source builds
  against zensim git `main`. If the fix writes `version = "0.3.0"`, zensim 0.3.0 must land first. If
  `version = "0.2"` suffices for the code, it need not.

The failure mode itself reproduces exactly:

```
error: failed to verify manifest at .../Cargo.toml
Caused by:
  all dependencies must have a version requirement specified when publishing.
  dependency `zensim` does not specify a version
```

### 4 — half wrong

* **`zenanalyze 0.2.0` gates jxl-encoder: TRUE.** `zenanalyze = { version = "0.2.0", optional = true }`,
  registry max `0.1.0`.
* **`butteraugli 0.9.4` does NOT gate jxl-encoder: FALSE as stated.** jxl-encoder declares
  `butteraugli = "0.9"` (and `butteraugli = "0.9"` as a dev-dep). Published `0.9.3` satisfies it. I
  grepped jxl-encoder's `src/`, `tests/` and `examples/` for the 0.9.4-only surface (`linear_planes`,
  `LinearPlanes`, `ScorerBuilder`, `compare_linear_planar_with_stop`) and found **no uses** — the
  `*_from_linear_planes_*` hits in `vardct/zensim_backend.rs` are `zensim_gpu` APIs, a different crate.
  What butteraugli 0.9.4 actually unblocks is **zenmetrics**, which pins `butteraugli = "0.9.4"` behind
  a `[patch.crates-io]` path entry. butteraugli's own changelog says exactly this. zenmetrics'
  butteraugli consumers are all `publish = false`, so this is a build-unpatched concern, not a
  publish-ordering one.
* **jxl-encoder is not 0.4.0.** The workspace is at `0.3.2`; `0.4.0` is aspirational.
* **The real jxl-encoder blockers are worse than the claim** — see §6, class B3. It declares three
  registry dependencies on crates that are `publish = false` and have never existed on crates.io.
  jxl-encoder cannot publish today regardless of zenanalyze or butteraugli.

### 5 — CONFIRMED, count corrected, and it generalises

zenavif is unpublishable for exactly the stated reason, and no CI or clone-siblings change fixes it.
The mechanism is class **B1** (§3), reproduced independently here.

**Count correction.** The root manifest has **six** versionless declarations, but only **four** block
publishing:

| Dep (alias) | Section | Blocks? | Why |
|---|---|---|---|
| `rav1d-safe` (git) | dependencies | **yes** | non-optional; local 0.6.0 > registry 0.5.7 |
| `aom-decode` → `zenav1-aom-decode` (path) | dependencies, optional | **yes** | never published |
| `svtav1` → `zenav1-svt` (path) | dependencies, optional | **yes** | never published |
| `zensim` (git) | dependencies, optional | **yes** | local 0.3.0 > registry 0.2.7 |
| `zensim` (git) | **dev**-dependencies | no | versionless dev-deps are stripped at package time (verified, §3) |
| `zensim-regress` (git) | **dev**-dependencies | no | same |

`zenanalyze-api` is *not* in this set — zenavif declares it `version = "0.1.0"`, which resolves. It is
instead an **under-constrained** dep (§8.3): the manifest names 0.1.0 while a `[patch.crates-io]` git
entry feeds the build 0.1.1, and the manifest's own comment says the patch is to be removed "at the
zenanalyze-api 0.1.1 publish".

**The generalisation is the important part.** Treating this as a zenavif quirk would be wrong:
**21 crates across the workspace are in exactly this state.** Full census in §5.

---

## 3. Blocker classes (and the exact cargo rules behind them)

Every rule below was reproduced in a throwaway crate under `~/tmp`, not taken from memory.

| Class | Condition | What cargo does | Fix type |
|---|---|---|---|
| **B1** | normal or build dep with **no `version`** (path- or git-only) | `error: all dependencies must have a version requirement specified when publishing` — fires at manifest verification, before any build | manifest edit |
| **B2** | dep `version` req that **no published version satisfies**, but the local version does | `error: failed to select a version for the requirement …` at packaging | publish that dep first (**ordering**) |
| **B3** | dep on a crate **absent from crates.io** (`publish = false`, or never released) | `error: no matching package named X found` | decision: publish it, or drop/repoint the dep |
| **B4** | local version number **already taken**, including by a **yanked** release | crates.io rejects the upload | version bump (**decision**) |

Three behaviours that materially change the order, all verified:

1. **Optional dependencies are still resolved.** A dep gated behind an unused feature still blocks
   publishing. Verified: a crate whose *only* dep was `zensim-gpu = { version = "0.0.1", optional = true }`
   failed with `no matching package named zensim-gpu found`.
2. **Versionless dev-dependencies are stripped and are harmless.** Verified: `cargo publish --dry-run`
   on a crate with `[dev-dependencies] zensim = { git = … }` and no version **succeeded** (packaged 4
   files, aborted at upload for dry run).
3. **Versioned dev-dependencies are NOT harmless.** `[dev-dependencies] zensim = "0.3.0"` failed with
   `failed to select a version`. This is why `heic` waits on `zensim`/`zensim-regress` (dev-deps with
   versions) while `zenjpeg` does not (dev-deps without).

Rule 2 vs 3 is the single most misleading part of this graph. A naive "any dependency on an
unreleased crate blocks" model produces a **false cycle** (§7).

Also: `cargo publish --dry-run --no-verify` catches **B1, B2 and B3** and costs seconds. Only compile
failures need the full `--verify` build. That is the cheap gate to run per crate before starting.

---

## 4. Publish order with per-crate preconditions

`After` = must already be on crates.io. `Own version` = is the target number free?
Blocker codes per §3.

### Wave 1 — no ordering blockers

| Crate | Ver | crates.io | Own version | After | Other blockers |
|---|---|---|---|---|---|
| butteraugli | 0.9.4 | 0.9.3 | free | — | none |
| **zenanalyze-api** | **0.1.1** | 0.1.0 | free | — | **none — this is the root, start here** |
| **zenpredict** | **0.2.0** | 0.1.0 | free | — | **none — second root** |
| zenavif-parse | 0.7.0 | 0.6.2 | free | — | none |
| zenavif-serialize | 0.2.0 | 0.1.4 | free | — | none |
| zenbitmaps | 0.2.0 | 0.1.5 | free | — | none |
| zengif | 0.8.0 | 0.7.3 | free | — | none |
| zenjxl-decoder | 0.4.0 | 0.3.10 | free | — | none |
| zenpng | 0.2.0 | 0.1.4 | free | — | none |
| zenrav1e | 0.2.0 | 0.1.4 | free | — | B3 `ivf "0.1"` — see §8.4 (probably benign) |
| jxl-encoder-macros | 0.3.2 | never | free | — | none |
| jxl-encoder-simd | 0.3.2 | 0.3.0 | free | — | none |
| heic-core | 0.2.0 | never | free | — | none |
| zensally | 0.1.0 | never | free | — | none |
| zentract-types | 0.1.0 | never | free | — | none |
| zenwasm-types | 0.1.0 | never | free | — | none |

### Wave 2

| Crate | Ver | crates.io | Own version | After | Other blockers |
|---|---|---|---|---|---|
| **zenanalyze** | **0.2.0** | 0.1.0 | free | `zenanalyze-api 0.1.1` | none — **dry-run verified** |
| **zensim** | **0.3.0** | 0.2.7 | free | `zenpredict 0.2.0` | none |
| butteraugli-cli | 0.9.4 | 0.9.3 | free | `butteraugli 0.9.4` | none |
| zenpicker | 0.1.0 | never | free | `zenpredict 0.2.0` | none |
| zenpredict-bake | 0.1.0 | never | free | `zenpredict 0.2.0` | none |
| zenravif | 0.2.0 | 0.1.3 | free | `zenavif-serialize 0.2.0`, `zenrav1e 0.2.0` | none |
| heic-backend-{d3d11va, mediacodec, mediafoundation, vaapi, videotoolbox} | 0.2.0 | never | free | `heic-core 0.2.0` | none |
| zentract-abi / zentract-api | 0.1.0 | never | free | `zentract-types 0.1.0` | none |
| zenwasm-abi / zenwasm-api | 0.1.0 | never | free | `zenwasm-types 0.1.0` | none |
| zensally-tract | 0.1.0 | never | free | `zensally 0.1.0` | **B1** `zenflate` (versionless git) |
| zensally-zentract | 0.1.0 | never | free | `zensally 0.1.0` | **B1** `zenflate`, `zentract-api` (versionless git) |

### Wave 3

| Crate | Ver | crates.io | Own version | After | Other blockers |
|---|---|---|---|---|---|
| **zenjpeg** | **0.9.0** | 0.8.4 | free | `zenanalyze 0.2.0` | **B1 ×3:** `zenyuv` (path), `zensim` (git rev), `zenpredict` (path) |
| zenwebp | 0.5.0 | 0.4.4 | free | `zenanalyze 0.2.0` | none |
| zensim-regress | 0.4.0 | 0.3.1 | free | `zensim 0.3.0` | none |
| zenavif | ~~0.1.7~~ | 0.1.6 | **TAKEN (yanked)** | `zenanalyze`, `zenavif-parse`, `zenavif-serialize`, `zenpredict`, `zenravif` | **B4 bump to 0.1.8**; **B1 ×5:** `rav1d-safe`, `zenanalyze-api`, `zenav1-aom-decode`, `zenav1-svt`, `zensim` |

### Wave 4

| Crate | Ver | crates.io | Own version | After | Other blockers |
|---|---|---|---|---|---|
| **jxl-encoder** | 0.3.2 | 0.3.1 | free | `jxl-encoder-macros`, `jxl-encoder-simd`, `zenanalyze`, `zenjpeg`, `zensim` | **B3 ×3 — HARD STOP:** `zensim-gpu`, `butteraugli-gpu`, `cvvdp-gpu`; **B1:** `cvvdp` (path) |
| ultrahdr-rs | 0.4.1 | 0.3.5 | free | `zenjpeg 0.9.0` | none |
| heic | ~~0.2.0~~ | 0.1.6 | **TAKEN (yanked)** | `heic-core`, all 5 backends, `zensim`, `zensim-regress` | **B4 bump to 0.2.1** |
| squintly | 0.1.0 | never | free | `zenavif` | none |

### Wave 5

| Crate | Ver | crates.io | Own version | After | Other blockers |
|---|---|---|---|---|---|
| jxl-encoder-cli | 0.3.2 | 0.2.0 | free | `jxl-encoder 0.3.2` | none |
| zenjxl | 0.3.0 | 0.2.1 | free | `jxl-encoder 0.3.2`, `zenjpeg 0.9.0`, `zenjxl-decoder 0.4.0` | none |

### Wave 6

| Crate | Ver | crates.io | Own version | After | Other blockers |
|---|---|---|---|---|---|
| zencodecs | 0.1.0 | never | free | `heic`, `zenavif`, `zenavif-parse`, `zenbitmaps`, `zengif`, `zenjpeg`, `zenjxl`, `zenjxl-decoder`, `zenpng`, `zensim`, `zensim-regress`, `zenwebp` | **B1 ×3:** `zenpicker`, `zenpredict`, `zensvg` (versionless git) |

Note the `zenavif` req is `"0.1.7"` — a yanked number. When zenavif ships as `0.1.8`, this req must
be updated too or zencodecs stays unresolvable.

### Wave 7

| Crate | Ver | crates.io | Own version | After | Other blockers |
|---|---|---|---|---|---|
| zenfilters | ~~0.1.1~~ | 0.1.0 | **TAKEN (yanked)** | `zencodecs 0.1.0`, `zensim 0.3.0` | **B4 bump to 0.1.2** |
| zenpipe | 0.1.0 | never | free | `zenavif`, `zenbitmaps`, `zencodecs`, `zengif`, `zenjpeg`, `zenjxl`, `zenpng`, `zensally`, `zensally-zentract`, `zenwebp` | **B3:** `imageflow_types "0.1.0"`, `imageflow_riapi "0.1.0"` — never published, imageflow is not in this wave |

---

## 5. The versionless-dependency census — how many crates are in zenavif's state

**Answer: 21 crates, across 47 dependency declarations.** Every one of them fails
`cargo publish` today at manifest verification, before any build, with
`all dependencies must have a version requirement specified when publishing`.

Method: static parse of every manifest (workspace inheritance resolved), covering **all** normal and
build dependencies — third-party as well as zen siblings — not just the ones I recognised. Versionless
**dev**-dependencies are excluded because cargo strips them (verified empirically, §3). Each blocked
dependency is then classified against the live crates.io index.

### 5.1 Class breakdown of the 47 blocked dependencies

| Class | Count | Meaning | Owner's options |
|---|---|---|---|
| **UNPUBLISHED** | 23 | the sibling has never been on crates.io, so **no version number can honestly be named** | publish the sibling; or make the dep optional *and* drop it from the published manifest; or accept the crate stays git-only |
| **NEWER-THAN-REGISTRY** | 15 | a published version exists but is older than what the code needs | publish the sibling at the new version first, then name it — this is a pure **ordering** constraint |
| **MERELY UNVERSIONED** | 8 | a published version already satisfies the local code | **add the version field** — one-line fix, no ordering constraint |
| **ALL VERSIONS YANKED** | 1 | `butteraugli-oxide`: 0.1.0, 0.2.0, 0.2.1 all yanked | unyank, publish anew, or drop the dep |

> **Do not invent a version number for an UNPUBLISHED dependency.** Naming a version that does not
> exist produces a crate nobody can resolve — the publish may even succeed while leaving the crate
> permanently broken for every consumer. Another agent correctly refused to do this today.

### 5.2 The 16 crates blocked by an unnamed-able dependency

These cannot enter the publish order at all until a **decision** is made — publish the sibling,
feature-gate-and-drop the dep, or accept git-only distribution. This is the honest answer to "what is
the publish order?" for them: *they are not in it yet*.

| Crate | Unnamed-able deps | Note |
|---|---|---|
| `jxl-encoder` | `cvvdp` (path, optional) | plus 3 **B3** registry deps on `publish = false` GPU crates (§6) — the hardest blocker in the wave |
| `zenavif` | `zenav1-aom-decode`, `zenav1-svt` (both optional) | both optional ⇒ droppable; `rav1d-safe`/`zensim` are ordering-only |
| `zencodecs` | `zenpicker`, `zensvg` (both optional) | `zenpicker` publishes in wave 2; `zensvg` is in `zenextras`, not in this wave |
| `zenpicker-train` | `zenpredict-bake`, `zenstats` | `zenstats` lives in zenmetrics and has never been released |
| `zensally-zentract` | `zentract-api` | publishes in wave 2 — becomes ordering-only once it does |
| `zcimg`, `zenpipe-cmd` | `zencodecs`, `zenpipe` | both are wave-6/7 crates; internal tools — candidates for `publish = false` |
| `wasm-size-shim` | `zenpipe` | 8 versionless deps total; internal tool |
| `jpegli` | `butteraugli-oxide` (all yanked) | tree looks abandoned; `jpegli 0.1.0` is also already taken |
| `zenav1-aom`, `zenav1-aom-decode`, `zenav1-aom-encode` | `zenav1-aom-dsp` etc. | whole AV1 tree is internally versionless |
| `zenav1-svt`, `zenav1-svt-dsp`, `zenav1-svt-encoder`, `svtav1-target` | `zenav1-svt-types` etc. | same |

The two AV1 trees (7 crates) are why zenavif's optional `aom-decode` / `svtav1` features are a
*decision*, not a fix: publishing them means first making two entire encoder workspaces publishable,
each of which is versionless throughout. **Dropping the two optional features from zenavif's published
manifest is by far the cheaper path.**

### 5.3 The 5 crates fixable by naming a version

No decision needed — just manifest edits, though three of them create ordering edges.

| Crate | Versionless deps | Fix |
|---|---|---|
| `zenjpeg` | `zenyuv`, `zensim`, `zenpredict` | `zenyuv` → `version = "0.1.3"` (already published). `zensim`/`zenpredict` are NEWER-THAN-REGISTRY ⇒ ordering edges onto waves 1–2 |
| `zenwebp-recompress` | `zenwebp`, `zensim`, `zenanalyze`, `zenpixels` | `zenpixels` → `"0.2.16"` today; other three wait on waves 2–3 |
| `zensally-tract` | `zenflate`, `tract-onnx` | both satisfiable today (`zenflate 0.4.0`, `tract-onnx 0.23.5`) — pure manifest fix |
| `zjpeg` | `zenjpeg` | waits on wave 3 |
| `compare-ssim` | `fast-ssim2` | `"0.8.2"` today — or set `publish = false` |

### 5.4 What this does to the order

The order in §1 is the order **for crates that can enter it**. Overlaying the census:

* **Wave 1–3 are unaffected** except that `zenjpeg` needs 3 manifest edits before it can publish, and
  `zenavif` needs 2 optional features dropped (or two AV1 trees published) plus a `0.1.8` bump.
* **`jxl-encoder` (wave 4) is the wave's hard stop.** It is blocked by both an unnamed-able path dep
  and three nonexistent registry deps. `jxl-encoder-cli` and `zenjxl` sit behind it, and `zencodecs`
  and `zenpipe` sit behind those. **Waves 4–7 do not start until the jxl-encoder GPU-crate decision is
  made.**
* **`zenpipe`, `zencodecs`, `zcimg`, `zenpipe-cmd`, `wasm-size-shim` may never enter the order**
  without either publishing imageflow/zensvg/zensally or dropping those optional features.

A realistic reading: **waves 1–3 are executable after ~10 manifest edits and 4 version bumps.
Waves 4–7 are blocked on two policy decisions**, not on ordering.

---

## 6. Cannot publish yet — blocker, and what kind of problem it is

| Crate | Blocker | Kind |
|---|---|---|
| **jxl-encoder** | `zensim-gpu`, `butteraugli-gpu`, `cvvdp-gpu` declared as registry deps `"0.0.1"`; all three are `publish = false` in zenmetrics and 404 on crates.io. `cvvdp` is a versionless path dep. | **Decision** — publish the GPU metric crates, or make all four optional-behind-a-non-published-path arrangement that cargo accepts (there isn't one — a registry dep must exist), i.e. remove them from the published manifest |
| **zenjpeg** | `zenyuv` (path, no version), `zensim` (git rev, no version), `zenpredict` (path, no version) | **Bug** — 3 manifest edits. `zenyuv 0.1.3` is already published, so it just needs `version = "0.1.3"` added |
| **zenavif** | `0.1.7` is yanked; 5 versionless deps (`rav1d-safe` git, `zenanalyze-api` git, `zenav1-aom-decode` path, `zenav1-svt` path, `zensim` git) | **Decision + bug.** `zenav1-aom-decode` and `zenav1-svt` have *never* been published and their own repos are full of versionless path deps — publishing zenavif with those features requires publishing two whole AV1 encoder trees first, or dropping those optional features from the published manifest |
| **heic** | `0.2.0` yanked | **Decision** — pick `0.2.1` |
| **zenfilters** | `0.1.1` yanked | **Decision** — pick `0.1.2` |
| **zencodecs** | `zenpicker`, `zenpredict`, `zensvg` versionless git deps | **Bug** — 3 edits (all three crates are publishable in this wave, so versions exist to name) |
| **zenpipe** | `imageflow_types`/`imageflow_riapi` `"0.1.0"`, never published; imageflow is out of scope | **Decision** — publish imageflow crates, or gate those behind a feature that is dropped from the published manifest |
| **zensally-tract / zensally-zentract** | `zenflate`, `zentract-api` versionless git | **Bug** — both are published/publishable, versions exist |
| **zenwebp-recompress** | `zenwebp`, `zensim`, `zenanalyze`, `zenpixels` all versionless path deps | **Bug** — 4 edits |
| **zjpeg** | `zenjpeg` versionless path dep | **Bug** — 1 edit |
| **zenpipe-cmd / zcimg / wasm-size-shim** | versionless path deps (1, 1, and 8 respectively) | **Bug**, or **decision** to set `publish = false` — these look like internal tools, not products |
| **zenpicker-train** | `zenpredict`, `zenpredict-bake`, `zenstats` versionless path deps; `zenstats` has never been published | **Bug + missing release** |
| **compare-ssim** | `fast-ssim2` versionless path dep | **Bug**, or `publish = false` |
| **jpegli** | `butteraugli-oxide` versionless path dep; `jpegli 0.1.0` also already taken, and every `butteraugli-oxide` version is yanked | **Decision** — this tree looks abandoned; likely `publish = false` |
| **zencodec-testkit** | `0.1.0` taken; the widened `zencodec` range is committed but unpublished | **Decision** — pick `0.1.1` |

Six of these are one-line manifest edits. The genuinely hard ones are **jxl-encoder** (needs a policy
call on the GPU crates) and **zenavif** (needs a policy call on the AV1 encoder features).

---

## 7. Cycles

**There is no cycle in the correct graph.** But the naive graph has one, and it is worth recording so
nobody re-derives it and panics:

```
zenjpeg -> zensim -> zenjpeg          (apparent)
```

It dissolves because `zensim`'s dependency on zenjpeg is `[dev-dependencies] zenjpeg = "0.8.4"` and
**0.8.4 is already published**. Not a blocker. Symmetrically, `zenjpeg -> zensim-regress` and
`zenjpeg -> ultrahdr-rs` are dev-deps that are either versionless (stripped) or satisfiable today.

The same false-cycle pattern also appeared for `zenwebp -> zensim` (`"0.2"`, satisfied by 0.2.7),
`zentone -> zensim` (`"0.2.6"`), and `zenjpeg -> zentone` (`"0.1"`).

> **The one way to create a real cycle.** zenjpeg's versionless `zensim` dep must be given a version
> (§2.3). If it is written as `version = "0.3.0"`, the edge `zenjpeg -> zensim` becomes real. It is
> still not a cycle *today* — `zensim`'s side stays at dev-dep `zenjpeg = "0.8.4"`. But if anyone also
> bumps zensim's dev-dep on zenjpeg to `"0.9.0"` in the same wave, that closes a genuine cycle.
>
> **Keep zensim's `[dev-dependencies] zenjpeg` at `0.8.4` (or drop its version entirely) until after
> zenjpeg 0.9.0 lands.** That single rule is what keeps the order acyclic. Same shape applies to
> `heic`, whose dev-deps on `zensim 0.3.0` / `zensim-regress 0.4.0` are what push it to wave 4.

---

## 8. Traps

### 8.1 `[patch.crates-io]` is masking breakage in 20+ manifests

Patch tables were found in 27 manifests. The dangerous ones override a **registry** dep with a
`path`/`git` source, so the workspace compiles against local code while the published manifest names
something else entirely. `cargo publish` does **not** inherit the outer workspace's patches — the
packaged crate is its own workspace — which is exactly why these surface only at publish time.

Worst offenders by count of zen crates patched: `zenpipe` (26), `zensquoosh/crates` (25),
`zenpipe/fuzz` (24), `zenmetrics` (13), `jxl-encoder` (9).

The most consequential ones:

| Patch | Masks |
|---|---|
| `jxl-encoder`: `butteraugli-gpu`, `cvvdp-gpu`, `zensim-gpu` → `../zenmetrics/crates/*` | Three deps that do not exist on crates.io at all (B3) |
| `jxl-encoder`: `zenjpeg`, `zensim`, `zenanalyze`, `zenjxl-decoder` → path | Four B2 ordering blockers |
| `zenjpeg`, `zenwebp`, `zenavif`, `zensr`, `ultrahdr`: `zenanalyze` → git | The `zenanalyze 0.2.0` blocker, in five separate repos |
| `zenpng`, `zenjxl`: `zencodec` → git tag `v0.1.26` | Nothing broken (0.1.26 is published) — these can simply be dropped |

**No `.cargo/config.toml` `paths` overrides are currently active** — I checked all 14 such files
across the tree. zencodec's manifest comment describes a gitignored `paths` override as the local
dev mechanism; none is present right now. If one is added, it becomes a second, *invisible* masking
layer that no manifest audit would catch.

### 8.2 Yanked version numbers — the silent trap

A yanked release still owns its number forever. Any check of the form "crates.io latest is X, local
is Y > X, therefore Y is publishable" **is wrong** for these four:

| Crate | Local | Latest live | Reality |
|---|---|---|---|
| `zenavif` | 0.1.7 | 0.1.6 | **0.1.7 exists, yanked** → must ship 0.1.8 |
| `heic` | 0.2.0 | 0.1.6 | **0.2.0 exists, yanked** → must ship 0.2.1 |
| `zenfilters` | 0.1.1 | 0.1.0 | **0.1.1 exists, yanked** → must ship 0.1.2 |
| `butteraugli-oxide` | 0.2.1 | *(all yanked)* | 0.1.0, 0.2.0, 0.2.1 all yanked |

Downstream reqs naming those numbers must move in the same wave: `zencodecs` asks for
`zenavif "0.1.7"`, and `squintly` asks for `zenavif "0.1.7"` — both break the moment zenavif ships as
0.1.8 instead. Other yanks worth knowing: `zenpixels 0.3.0`, `linear-srgb 0.7.0`, `garb 0.2.7`,
`zenbench 0.1.0/0.1.1/0.1.5`, and nine early `zencodec 0.1.x` releases.

### 8.3 Under-constrained requirements — publishes fine, then fails to build

Distinct from B2 and **not caught by `--no-verify`**. The req resolves, but to an *older* version than
the patch is feeding the local build. The publish succeeds; downstream users get a broken crate.

| Crate | Req | Would resolve | Locally builds against |
|---|---|---|---|
| `jxl-encoder` | `zenjxl-decoder = "0.3.8"` | 0.3.10 | **0.4.0** via `[patch]` path |
| `jxl-encoder` | `butteraugli = "0.9"` | 0.9.3 | 0.9.4 via `[patch]` path |
| `zenwebp` | `zensim = "0.2"` | 0.2.7 | 0.3.0 via `[patch]` git |
| `zenwebp` | `zenanalyze-api = "0.1.0"` | 0.1.0 | 0.1.1 via `[patch]` git |
| `zenjpeg` | `zenanalyze-api = "0.1.0"` | 0.1.0 | 0.1.1 via `[patch]` git |

`zenjxl-decoder 0.3.8 → 0.4.0` is the riskiest: a 0.x minor bump is a breaking change by convention,
so jxl-encoder's `"0.3.8"` almost certainly will not compile against the code it is written for.

**These are the cases only a full `cargo publish --dry-run` (with verification) can catch.** Budget
one verify run per crate in waves 3–7 before the real publish.

### 8.4 `zenrav1e` → `ivf`

`zenrav1e` declares `ivf = { version = "0.1", optional = true }` while also carrying a workspace
member named `ivf` that is `publish = false`. A third-party `ivf` **does** exist on crates.io (up to
0.1.4), so this resolves — but it resolves to *that* crate, not the in-tree one, both locally and
when published. Flagging as **unverified**: I did not confirm whether the in-tree `ivf` is a
divergent fork. If it is, `dump_ivf` builds against the wrong code.

---

## 9. Infrastructure state

The three relayed facts are confirmed and understated.

**Coverage.** 49 repos surveyed, 45 exist under `imazen`. Four are not under `imazen` at all —
`whereat`, `image-tiff`, `zenimage`, `fax` — their git remotes point at `github.com/lilith/*`. Those
four returned genuine HTTP 404s; every other repo returned HTTP 200 with a real list, so "(none)"
below means confirmed-empty, not call-failed.

| Metric | Count |
|---|---|
| Repos with any release-ish workflow | **10 of 45** |
| Repos whose workflow actually runs `cargo publish` | **6 of 45** — zenjpeg, butteraugli, zenjxl-decoder, zenavif, archmage, cargo-copter |
| Of those, ever succeeded at publishing | **3** — butteraugli, archmage, cargo-copter |
| Repos with a crates.io-token-shaped secret | **3 of 45** |
| Repos with **zero** repository secrets | **42 of 45** |

(`zensim`, `fast-ssim2` and `codec-corpus` have release workflows that ship **binaries/tarballs only**
— no `cargo publish`. `zenmetrics` has a `release.yml` on the default branch that the Actions API does
not list, and its publish step is commented out.)

**Org-level secrets: there is no shared crates.io token.** `gh api orgs/imazen/actions/secrets`
returns HTTP 403 (`admin:org` scope absent). Answered instead via
`repos/imazen/<repo>/actions/organization-secrets`, run against all 45 repos: every one returns
exactly one org secret, **`CODECOV_TOKEN`**, and nothing else. So every publishing repo must carry its
own token or use OIDC.

**Per-repo publish capability:**

| Repo | Publish workflow | Runs | Token | Verdict |
|---|---|---|---|---|
| butteraugli | `release.yml`, tag `v*` | 11 success / 7 fail, latest **success** 2026-05-28 | `CARGO_REGISTRY_TOKEN` (repo) | **Works — the reference implementation** |
| archmage | `publish.yml`, **`release: [published]`** | 16 success / 4 fail, latest **success** 2026-07-21 | `CARGO_REGISTRY_TOKEN` in **environment `crates-io`** | Works. Trigger is a GitHub *Release*, not a tag push |
| cargo-copter | `release.yml`, tag `v*` | 5 success / 2 fail, latest success 2026-03-24 | `CARGO_REGISTRY_TOKEN` (repo) | Works |
| zenjpeg | `release.yml`, tag `v*` | **1 "success" / 19 fail**, latest **fail** 2026-08-29 | **none** | Broken. The single success was a dry-run dispatch |
| zenavif | `release.yml`, tags `v*`/`zenavif-*` | **0 success / 10 fail**, latest fail 2026-05-02 | **none**, and references `CRATES_TOKEN` (nonstandard name) | Broken — and currently fails at `Run tests`, before publish |
| zenjxl-decoder | `crates-io-release.yaml`, tag `v*` | **0 success / 12 fail**, latest fail 2026-06-11 | none needed — OIDC trusted publishing | Broken at the `crates-io-auth-action` step: trusted publishing is not configured crates.io-side |

**Consequences for this wave:**

* **This wave is manual.** Of the ~50 crate publishes in §4, exactly three repos have a working
  automated path, and only `butteraugli` is in the wave (`archmage` and `cargo-copter` are not).
  Everything else needs `cargo publish` from a workstation with a token, or CI has to be built first.
* **`archmage` is invisible to a repo-secrets audit.** Its token lives in an environment. Any sweep
  that only reads `repos/*/actions/secrets` will wrongly report it as tokenless.
* **Three different secret names are in use** — `CARGO_REGISTRY_TOKEN` (4 repos), `CRATES_TOKEN`
  (zenavif only, and absent), `CRATES_IO_TOKEN` (zenmetrics, commented out). A token rollout must
  reconcile zenavif's name or it will keep failing with a token present.
* **zenjpeg has a pre-flight token gate** (added 2026-08-29) that hard-fails a tag publish on an empty
  `CARGO_REGISTRY_TOKEN`. Its comment records the prior incident: run 26756503782 created the
  **GitHub Release for v0.8.4 and then died on `cargo publish`**, and 0.8.4 reached crates.io only by
  a manual human publish. The gate is scoped to tag pushes with `dry_run != 'true'`, so the two
  dispatch runs on 2026-08-29 bypassed it and died at `Publish (dry run)` instead. It also references
  `secrets.GH_PAT` for private-sibling git rewriting; that secret does not exist either.

---

## 10. Open decisions (nothing can start until these are made)

1. **jxl-encoder and the GPU metric crates.** Publish `zensim-gpu` / `butteraugli-gpu` / `cvvdp-gpu`
   (they are `publish = false` and depend on `zenforks-cubecl`, itself unpublished at 0.10.2), or
   remove them from jxl-encoder's published manifest. Until this is decided jxl-encoder cannot ship,
   and `jxl-encoder-cli` and `zenjxl` cannot ship behind it.
2. **zenavif's AV1 encoder features.** `zenav1-aom-decode` and `zenav1-svt` have never been published
   and their repos carry versionless path deps throughout. Publish those trees, or drop the optional
   features from zenavif's published manifest.
3. **Version numbers for the four yanked-collision crates:** zenavif `0.1.8`, heic `0.2.1`,
   zenfilters `0.1.2`, zencodec-testkit `0.1.1`. Downstream reqs naming the old numbers move with them.
4. **What version zenjpeg should require of zensim.** `"0.3.0"` creates an ordering edge (and the
   cycle risk in §7); a satisfiable `"0.2"` does not. Depends on whether zenjpeg's code needs 0.3.0.
5. **Which of these are products at all.** `wasm-size-shim`, `zcimg`, `zenpipe-cmd`, `compare-ssim`,
   `zenpicker-train`, `zjpeg`, `jpegli`, `squintly` all look like internal tooling yet are
   `publish = true` with versionless path deps. Setting `publish = false` removes 8 crates from the
   wave for free.
6. **Whether to fix release CI first.** 42 repos have no token. Either accept a manual wave, or
   replicate butteraugli's `release.yml` + `CARGO_REGISTRY_TOKEN` across the wave repos before starting.
7. **zencodec 0.2.0 timing.** Not in this wave. When it happens, `zencodec-testkit 0.1.1` ships first
   or simultaneously.

---

## 11. What this analysis cannot tell you

Stated precisely, per the brief.

* **Compile failures are not covered.** Everything in §4 is manifest-and-registry resolvability. A
  crate can pass all of it and still fail its verification build because the published version of a
  dependency lacks a symbol the source uses — §8.3 lists the five known candidates. Only
  `cargo publish --dry-run` **with** verification detects those, and it must be run *after* the
  dependency has actually been published.
* **A dry run is impossible for most of this wave right now, and that is the finding.** `zenjpeg`,
  `jxl-encoder`, `zenjxl`, `zencodecs`, `zenpipe`, `zenavif`, `heic` and `ultrahdr-rs` all depend on
  crates that do not yet exist on crates.io at the required version. Their verify builds cannot be
  performed until their predecessors ship. The order in §1 must be executed incrementally, dry-running
  each wave only once the previous wave is live.
* **Only `zenanalyze` was dry-run against a real repo.** 11 wave repos were claimed by concurrent
  agents (§0). Their verdicts are analytic.
* **`ivf` in zenrav1e is unverified** (§8.4).
* **crates.io-side publish validation was not exercised.** I never contacted the publish endpoint. The
  B1/B2/B3 rules are client-side cargo behaviour, reproduced locally. If crates.io applies additional
  server-side checks, they are not modelled here.
* **Org secret *visibility* settings were not readable** (403, `admin:org` scope). The per-repo
  `organization-secrets` result is stronger evidence for the practical question, but the raw org
  configuration was not inspected.
