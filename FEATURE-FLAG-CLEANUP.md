# Feature Flag Cleanup

Inventory from 2026-03-18. Covers all crates in `~/work/zen/`.

## Drop (dead/empty/deprecated)

| Crate | Feature | Reason |
|-------|---------|--------|
| **zenjpeg** | `archmage-simd` | Empty `[]`. Archmage is now a mandatory dep. Backwards-compat shim for nothing. |
| **zenjpeg** | `wasm-simd` | Empty `[]`. WASM SIMD is controlled by `RUSTFLAGS -Ctarget-feature=+simd128`, not a cargo feature. |
| **zengif** | `exoquant-deprecated` | Literally says "deprecated" in the name. |
| **linear-srgb** | `unsafe_simd` | Contradicts `#![forbid(unsafe_code)]` policy. If it does nothing unsafe anymore, it's dead. If it does, it shouldn't exist. |
| **linear-srgb-pulp** | *(entire crate)* | Superseded by `linear-srgb`. Check if anything still depends on it. |

## Consolidate (too granular)

| Crate | Features | Suggestion |
|-------|----------|------------|
| **jxl-encoder** | `trace-bitstream`, `debug-tokens`, `debug-dc`, `debug-ac-strategy`, `debug-rect` | One `debug` feature. Nobody enables `debug-dc` without `debug-tokens`. |
| **zenjxl-decoder** | `sse42`, `avx`, `avx512`, `neon`, `wasm128` | Just `all-simd` (already the default). Runtime dispatch picks the right path. Individual SIMD features only matter for binary-size-constrained WASM, and `wasm128` alone covers that. |
| **whereat** | `_tinyvec-64-bytes`, `_tinyvec-128-bytes`, `_tinyvec-256-bytes`, `_tinyvec-512-bytes` | One `tinyvec` feature with a sensible default size. Four size variants is a configuration knob pretending to be features. |
| **whereat** | `_smallvec-128-bytes`, `_smallvec-256-bytes` | Same — one `smallvec` feature. |
| **zenrav1e** | `dump_ivf`, `dump_lookahead_data`, `desync_finder` | One `debug-dump` feature. These are all diagnostic inspection tools. |

## Questionable / rename

| Crate | Feature | Issue |
|-------|---------|-------|
| **zenravif** | `imazen` | Opaque name. What does it actually toggle? If it's internal build config, it shouldn't be a public feature. |
| **zenresize** | `pretty-safe` | Unclear name. If it disables optimizations for debugging, call it `debug`. If it enables extra bounds checks, call it `checked`. |
| **zenresize** | `bench-simd-competitors` | Benchmark feature in a library crate. Should be a dev-dependency or example feature, not a library feature. |
| **zenbitmaps** | `all` | Doesn't include `zencodec` or `std`. Misleading name — rename to `formats` or drop it. |
| **zencodecs** | `calibrate` | Seems internal. If it's only used by benchmarking/training tools, it shouldn't be in the library. |
| **zenfilters** | `experimental` | Permanent `experimental` features tend to stay forever. Either stabilize or give it a specific name for what it gates. |

## `_`-prefixed features that should become dev-deps or cfg(test)

These are scattered across several crates and shouldn't be cargo features at all:

- **zenwebp**: `_benchmarks`, `_corpus_tests`, `_profiling`, `_wasm_profiling`
- **zenpng**: `_dev`
- **zenavif**: `_dev`
- **zenjpeg**: `profile`, `alloc-instrument`, `test-utils`, `corpus-tests`, `ffi-tests`

These gate test/benchmark code. The `_` prefix is a convention hack to hide them from users, but they still pollute `--all-features` builds and can cause surprising compile failures. Better pattern: `cfg(test)` or separate binary crates for benchmarks.
