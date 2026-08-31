# Reducing build permutations: config values, not feature flags or env vars

**Owner directives this encodes** (2026-08-30/31): *"feature flags are lowkey evil"*,
*"env vars are slow and bad"*, and — the constraint that shapes everything —
*"we will continue exploring alternate IQA and search methods and encoding modes."*

The goal is not fewer knobs. It is the **same or more** exploration surface at a
**fraction of the build permutations**, with every variant compiled, type-checked
and testable.

## The measurement

`jxl-encoder`, 2026-08-31:

| | count |
|---|--:|
| cargo features | **37** |
| `env::var` calls in `src/` | **205** |
| distinct env var names | **57** |
| of those calls, near a `OnceLock`/`static` cache | ~29 |
| ⇒ re-read on every call | **~176** |
| read inside a loop body | ≥ 8 |

`env::var` allocates a `String` and takes a process-global lock on every call, so
"slow" is measurable, not theoretical. The concentration is exactly where the
exploration happens: `vardct/zensim_loop.rs` 27, `vardct/encoder.rs` 22,
`modular/tree_learn.rs` 22.

Neither mechanism is free of a second, larger cost: **a configuration nobody
builds is a configuration where bugs live.** Five measured instances from one
session:

- `zenjxl-decoder`'s fuzz harness built with default features off, so only the
  scalar tier was ever fuzzed — **2 of 3 CPU-divergence defects were structurally
  unreachable** by the fuzzer that existed to find them.
- `zenwebp`'s clippy job ran only `--features analyzer`, so five `dev/` targets
  behind `analyzer-bundled` were **never linted**; six findings had accumulated.
- `zensr`'s `Test (chooser)` ran a configuration where every behavioural test was
  `#[cfg]`'d out — a green step asserting only that the crate compiled.
- `jxl-encoder`'s `unsafe-asm` is compiled by **nothing** — not CI, not the dev
  box — so that file is edited blind.
- **19 `__expert`-gated examples do not compile** (`effort` is `pub(crate) mod`);
  no clippy job enables `__expert`, so CI never sees it.

## The reframe

> **Exploration variants are *values*, not build configurations.**

One binary contains every variant; selection happens at runtime by passing a
value. 2ⁿ build configs collapse toward one, and — the part that matters — the
variants stay compiled, so they stay type-checked, lintable, fuzzable and
testable.

## Four mechanisms, chosen by shape

### 1. Closed set, known at compile time → `enum` + match

Encoding modes, controllers, search strategies. Zero dispatch cost,
exhaustiveness-checked, every arm compiled.

```rust
enum Controller {
    PowerLaw { exp: f32, clamp: f32 },
    Secant   { min_eps: f32, min_dlnl: f32 },
}
```

That single enum replaces `JXL_ZENSIM_SECANT`, `_MIN_EPS`, `_MIN_DLNL`,
`_CTRL_EXP`, `_CTRL_CLAMP` — five untyped strings become typed fields, and a
fitted constant becomes a visible default rather than a runtime string parse.
`EncoderStrategy` is already this shape and is the model to copy.

### 2. Open set → trait object

IQA metrics, because new ones keep arriving:

```rust
trait QualityMetric {
    fn score(&self, reference: &Image, distorted: &Image) -> f64;
    fn name(&self) -> &str;
}
```

The search loop takes `&dyn QualityMetric`. **Adding a metric is adding an impl —
zero new build configurations.** One vtable call per *score* is nothing beside
computing the metric.

**This is the opposite verdict from `zenanalyze-api`, deliberately.** There a
trait was cut because the data flow is *push* — the host hands an offer down and
the codec answers yes/no — so a trait added a pull-shaped indirection nobody
called. Here the encoder genuinely must **call** the metric mid-search. Same
tool, opposite answer, because the direction of control differs. When in doubt,
ask who calls whom.

### 3. Instrumentation → an observer, not an env var

```rust
on_iteration: Option<&dyn Fn(&IterationRecord)>,
```

Most of the 57 env names exist because a benchmark harness needed data out of a
deep loop and env was the path of least resistance. With an observer the harness
passes a closure and receives **typed** data; the library stops parsing strings
and writing files. This retires the whole `*_TRACE` / `*_DUMP_*` / `*_TSV` /
`*_PATH` family — roughly 20 of the 57 by name.

### 4. Features only for genuinely build-affecting axes

> **A feature is legitimate only if removing it removes a dependency or a
> platform capability. A feature that merely selects behaviour is a value in
> disguise.**

Survivors: `std`, `parallel` (pulls rayon), SIMD tiers that must compile
differently, heavy optional deps (a GPU backend, an ML runtime). Everything else
becomes a config field. Every surviving feature is built in CI — affordable
precisely because there are few.

## The gate that stops the regrowth

List the build configurations CI actually runs in one place, and **fail the build
when a feature appears that is not in that matrix.** Without this the count
regrows silently; 37 features did not arrive in one commit. This converts drift
into a decision each time.

## Migration — three phases, incremental by design

**Phase 1 — shim.** Introduce the config struct and the observer; parse env
**once at construction** into typed fields. One place reads env, everything else
reads a struct. Kills all ~176 uncached reads and every hot-loop read. Mechanical,
and lands between exploration work rather than blocking it.

**Phase 2 — harnesses set the struct directly**, deleting the shim per knob.

**Phase 3 — behaviour-selecting features become fields** and leave the matrix.

Phase 1 alone captures most of the speed and testability win.

## The objection, answered

*"Then dead experimental code ships."* Dead code that compiles is **tested** code
— that is the point, not the cost. Binary size is handled by the coarse features
plus LTO, and for the genuinely size-sensitive target (wasm) the small orthogonal
feature set is the lever. The trade is a hypothetical size cost against a
**measured, five-times-over** failure mode: untested configurations hiding bugs.
