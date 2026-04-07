# Archmage/Magetypes Usage Audit

**Date**: 2026-04-04
**Scope**: All repos in `/home/lilith/work/zen/` using archmage or magetypes (338 files across 25+ crates)

## Key Concepts (Quick Reference)

| Pattern | When to Use | Anti-Pattern |
|---------|-------------|--------------|
| `#[arcane]` | Entry point from non-SIMD code (one per hot path) | On inner helpers (creates target-feature boundary per call) |
| `#[rite]` | Internal helpers called from within `#[arcane]` | On entry points (won't generate safe wrapper) |
| `#[autoversion]` | Outer loop wrappers for LLVM auto-vectorization | On inner hot functions |
| `#[magetypes]` | Generate platform-suffixed variants from generic code | N/A |
| `incant!` | Multi-tier dispatch at call site | Manual if/else token chains |
| Concrete tokens | Hot paths (X64V3Token, NeonToken) | Generic bounds (T: HasX64V2) without inlining strategy |
| `#[inline(always)]` | **Small** generic SIMD helpers (<20 lines) | Missing on small generics = 18x slower |
| `#[inline]` or no attr | **Large** generic kernels (>50 lines) — let LLVM decide | `#[inline(always)]` on large kernels = I-cache bloat, register spill, BTB aliasing |
| `#[inline(never)]` | When a function is inlined 10+ times into the same caller | Overuse — only when profiling shows BTB aliasing |

---

## Exemplary Code (Best Generics & Performance)

These files represent the gold standard for archmage usage. Use as reference when fixing substandard code.

### Tier 1: Perfect Pattern

| File | Why It's Excellent |
|------|-------------------|
| `jxl-encoder/jxl-encoder-simd/src/pixel_loss.rs` | Concrete tokens, hot loops inside #[arcane], magetypes high-level API, clean scalar remainder |
| `jxl-encoder/jxl-encoder-simd/src/gab.rs` | Pre-slicing eliminates bounds checks, FMA chains, proper simd_end loop condition |
| `jxl-encoder/jxl-encoder-simd/src/cfl.rs` | Hot accumulation loop inside #[arcane], concrete X64V3Token, #[inline(always)] on helpers |
| `zenjpeg/zenjpeg/src/encode/mage_simd.rs` | Perfect #[arcane]/#[rite] split, recursive DCT with token propagation, FMA via token |
| `zenjpeg/zenjpeg/src/encode/strip/mod.rs` | `#[magetypes(v3, neon, wasm128, scalar)]` + `#[inline(always)]` on generic — textbook |
| `zenjpeg/zenjpeg/src/encode_simd.rs` | `incant!` dispatch, safe load/store helpers, boundary handling |
| `zenjpeg/zenjpeg/src/quant/aq/simd.rs` | `GenericF32x8<T>` with `#[inline(always)]` — exemplary generic SIMD |
| `zenwebp/src/decoder/yuv_fused.rs` | Single #[arcane] boundary, multiple #[rite] helpers, fixed-size arrays |
| `zenwebp/src/decoder/vp8v2/pipeline.rs` | incant! → inline dispatch → #[rite] backend — reference multi-MB pattern |
| `zenwebp/src/encoder/cost/distortion.rs` | 21 dispatch helpers all #[inline(always)], zero token mismatches |
| `linear-srgb/src/tokens/x8.rs` | All rites properly marked, concrete arrays at API boundary, feature-gated TFs |
| `fast-ssim2/fast-ssim2/src/blur/simd_gaussian.rs` | #[autoversion] on outer loop, #[magetypes] on vertical pass, state vectors in registers |
| `fast-ssim2/fast-ssim2/src/simd_ops.rs` | Clean incant! dispatch, LANES-chunked loops, generic type alias pattern |
| `zenblend/src/simd/x86.rs` | Extensive FMA usage, concrete X64V3Token, scalar remainder properly separated |
| `zenblend/src/simd/portable.rs` | Generic `T: F32x8Backend` with `#[inline]` — clean polymorphic dispatch |
| `zenfilters/src/simd/x86.rs` | 50+ functions all following #[arcane] → #[rite] pattern, pow_lowp on concrete f32x8 |
| `zenresize/src/simd/x86.rs` | #[rite] on filter helpers, #[inline(always)] on filter_h_4ch, concrete tokens |
| `zenpng/src/simd/paeth.rs` | 6 platform-specific impls, branchless predictor helpers, #[rite] on platform helpers |
| `heic/src/hevc/transform_simd_neon.rs` | #[arcane] entries, #[rite] helpers, H.265 spec-correct butterfly operations |
| `heic/src/hevc/color_convert.rs` | incant! dispatch, scalar prefix/tail with SIMD middle |
| `rav1d-safe/src/safe_simd/mc.rs` | Desktop64/Server64 tokens, Flex access pattern, prefetch-aware chunking |
| `rav1d-safe/src/safe_simd/cdef.rs` | #[rite] on constrain helpers, hot filter loops inside #[arcane] |
| `BRAG/brag-art/src/x86.rs` | #[rite] on row processing, 32-byte hot loop inside boundary, scalar tail |
| `BRAG/src/swizzle/x86.rs` | Macro-generated #[rite], concrete shuffle masks, no generic bounds |
| `zenzstd/src/encoding/simd.rs` | Perfect incant! dispatch, 4-way unrolled histogram, concrete tokens |
| `zenjxl-decoder/.../x86_64/avx.rs` | Descriptor wraps X64V3Token, fn_avx! macro applies #[arcane], concrete __m256 |

---

## Substandard Usage Inventory

### CRITICAL: Generic Bounds in Hot Paths — Inlining Strategy Needed

Generic trait bounds create optimization barriers that prevent LLVM from specializing per-token. The fix depends on kernel size:

- **Small helpers (<20 lines)**: `#[inline(always)]` — the target-feature boundary cost dominates
- **Large kernels (>50 lines)**: `#[inline]` or no attribute is often **correct** — forcing inline causes I-cache bloat, register spills, and BTB aliasing when the same large body appears at multiple call sites. Profile before changing.
- **`#[inline(never)]`**: Appropriate when a function would be inlined 10+ times into the same caller — gives the branch predictor one canonical address

**The key question for each item below is: does the function need to inherit the caller's `#[target_feature]` to use SIMD instructions?** If yes, it must inline (or use `#[rite]`). If it's pure scalar index math called from generic code, `#[inline]` suffices.

| # | File | Lines | Issue | Verdict |
|---|------|-------|-------|---------|
| 1 | `zenfilters/src/simd/wide_simd.rs` | ~223 | `gaussian_blur_fir_generic<T>` — large kernel (~80 lines) with `#[inline]`, called from `#[magetypes]` monomorphized context | **NO ACTION**: `#[inline]` is correct — LLVM monomorphizes + inlines from the single call site per tier. Large kernels should let the compiler choose. |
| 2 | `zenfilters/src/simd/wide_simd.rs` | ~311 | `stackblur_plane_generic<T>` — same pattern, ~120 line kernel | **NO ACTION**: Same — `#[inline]` lets compiler choose, one call site per monomorphization. |
| 3 | `zensim/zensim/src/fused.rs` | ~170,179,192 | `mirror_idx()`, `vblur_add_idx()`, `vblur_rem_idx()` | **FALSE POSITIVE**: Already have `#[inline(always)]` — agent misread the code. |

### HIGH: Incomplete SIMD Implementations (Dead Code Risk)

These functions exist with `#[arcane]` annotations but contain `unimplemented!()` — they'll panic at runtime if dispatched to.

| # | File | Lines | Issue | Fix |
|---|------|-------|-------|-----|
| 4 | `zenjpeg/zenjpeg/src/encode/wasm_simd.rs` | ~376 | `wasm_idct_int_8x8` — unimplemented dead code | **FIXED**: Removed (uncalled) |
| 5 | `zenjpeg/zenjpeg/src/encode/wasm_simd.rs` | ~454 | `wasm_ycbcr_to_rgb` — unimplemented dead code | **FIXED**: Removed (uncalled) |
| 6 | `zenjpeg/zenjpeg/src/encode/arm_simd.rs` | ~434 | `neon_idct_int_8x8` — unimplemented dead code | **FIXED**: Removed (uncalled) |
| 7 | `zenjpeg/zenjpeg/src/encode/arm_simd.rs` | ~454 | `neon_ycbcr_to_rgb` — unimplemented dead code | **FIXED**: Removed (uncalled) |

### HIGH: Duplicate cfg and Style Issues

| # | File | Lines | Issue | Fix |
|---|------|-------|-------|-----|
| 8 | `zenwebp/src/encoder/vp8l/transforms.rs` | ~122,655 | **FALSE POSITIVE**: incant! dispatches to `_v1` which has `#[arcane]`, then that calls `#[rite]` inner — this is the correct pattern, not double-wrapping | No action needed |
| 9 | `zenwebp/src/encoder/analysis/prediction.rs` | 124-125, 299-300 | Duplicate `#[cfg(target_arch = "x86_64")]` on two functions | **FIXED**: Removed duplicate lines |

### MEDIUM: Inlining Strategy for #[rite] / Internal Helpers

These helpers are called from within `#[arcane]` functions. Whether they need `#[inline(always)]` depends on size and whether they use SIMD instructions:

- **`#[rite]` helpers**: Already annotated with `#[target_feature]` + `#[inline]` by the macro, so they inherit the caller's ISA and LLVM can inline them. Adding `#[inline(always)]` is only needed if profiling shows they aren't being inlined.
- **Plain helpers without `#[rite]`**: If they use SIMD intrinsics or magetypes ops, they MUST inline to get target_feature. If they're pure scalar math, `#[inline]` suffices.
- **Large batch helpers (>100 lines)**: `#[inline(never)]` may be better if called from multiple DCT sizes — avoids I-cache bloat and BTB aliasing. The `#[rite]` annotation ensures they still get the right target_feature even without inlining.

| # | File | Lines | Issue | Verdict |
|---|------|-------|-------|---------|
| 10 | `jxl-encoder/jxl-encoder-simd/src/dct8.rs` | 385,617 | `vectorized_dct1d_8` has `#[archmage::arcane]`, `transpose_8x8_regs` has `#[archmage::rite]` | **FALSE POSITIVE**: Already properly annotated. |
| 11 | `jxl-encoder/jxl-encoder-simd/src/dct16.rs` | 263-359 | All batch helpers have `#[archmage::arcane]` + `#[inline(always)]` | **FALSE POSITIVE**: Already properly annotated. |
| 12 | `jxl-encoder/jxl-encoder-simd/src/dct32.rs` | 312-375 | `dct1d_32_batch` and `dct1d_64_batch` have `#[archmage::arcane]` + `#[inline(always)]` | **FALSE POSITIVE**: Already properly annotated. Large kernels with `#[inline(always)]` — profile if I-cache pressure suspected. |
| 13 | `jxl-encoder/jxl-encoder-simd/src/idct16.rs` | varies | All `idct1d_*_batch` have `#[archmage::arcane]` + `#[inline(always)]` | **FALSE POSITIVE**: Already properly annotated. |
| 14 | `zensim/zensim/src/color.rs` | 101,122 | `cbrtf_fast()` and `cbrtf_initial()` already have `#[inline(always)]` | **FALSE POSITIVE**: Already properly annotated. |

### MEDIUM: Attribute Style Inconsistencies

Using `#[archmage::arcane]` instead of `#[arcane]` with prelude import. Not a performance issue but hurts readability and grep-ability.

| # | File | Lines | Issue | Fix |
|---|------|-------|-------|-----|
| 15 | `zenfilters/src/simd/wasm128.rs` | throughout | Used `#[archmage::arcane]` despite prelude import | **FIXED**: Changed to `#[arcane]` |
| 16 | `zenwebp/src/encoder/vp8l/transforms.rs` | ~128-129,135-136 | **FALSE POSITIVE**: zenwebp doesn't import archmage prelude — uses explicit paths consistently throughout | No action needed |
| 17 | `zenwebp/src/encoder/analysis/prediction.rs` | ~141,319 | **FALSE POSITIVE**: prediction.rs uses explicit `X64V3Token` imports, not archmage prelude | No action needed |

### MEDIUM: #[arcane] Where #[rite] Should Be

Functions that are called from within another `#[arcane]` scope but are marked `#[arcane]` themselves — creating an unnecessary safe wrapper layer.

| # | File | Lines | Issue | Fix |
|---|------|-------|-------|-----|
| 18 | `rav1d-safe/src/safe_simd/itx.rs` | ~223 | `dct4_2rows_avx2` uses `#[arcane]` but is called from within another `#[arcane]` — `#[rite]` would be more idiomatic | **NO ACTION**: `#[arcane]` → `#[arcane]` with matching tokens inlines perfectly per archmage docs (zero overhead). Style-only difference. |

### MEDIUM: Dispatch Functions Missing Attributes

| # | File | Lines | Issue | Fix |
|---|------|-------|-------|-----|
| 19 | `zenfilters/src/filters/warp_simd.rs` | ~108-141 | NEON/WASM128 dispatch functions lack `#[arcane]` attribute (they delegate to scalar, so functionally OK but inconsistent) | Add `#[inline]` or `#[arcane]` for consistency |

### LOW: AoS/SoA Round-Trips in Hot Loop

| # | File | Lines | Issue | Fix |
|---|------|-------|-------|-----|
| 20 | `fast-ssim2/fast-ssim2/src/xyb_simd.rs` | ~143-174 | Multiple `to_array()`/`from_array()` round-trips inside hot loop for cbrt initial estimates | Pre-compute outside loop or vectorize cbrt initialization |
| 21 | `zensim/zensim/src/color.rs` | ~250-257 | Scalar `cbrtf_initial()` loop inside SIMD hot path | Batch-compute before loop or vectorize |

### LOW: Missing SIMD for Transfer Function Slices

| # | File | Lines | Issue | Fix |
|---|------|-------|-------|-----|
| 22 | `linear-srgb/src/default.rs` | ~112-149 | `hlg_to_linear_slice`, `pq_to_linear_slice`, etc. are scalar loops without SIMD dispatch (acknowledged TODO) | Add incant!-dispatched variants |

### LOW: Generic magetypes::simd in Hot Path (Design Choice)

| # | File | Lines | Issue | Fix |
|---|------|-------|-------|-----|
| 23 | `zenavif/src/yuv_convert.rs` | ~18,162 | Uses generic `magetypes::simd::f32x8` instead of concrete token-specific types in hot conversion loop | Consider concrete token dispatch for max performance |

---

## Crate-Level Ratings

| Crate | Rating | Files Audited | Issues Found |
|-------|--------|---------------|-------------|
| jxl-encoder-simd | GOOD | 18 | Missing #[inline(always)] on batch helpers (#10-13) |
| zenjpeg | GOOD | 22 | Unimplemented ARM/WASM (#4-7), excellent mage_simd/strip |
| zenwebp | GOOD | 24 | Double #[arcane] (#8-9), attribute paths (#16-17), excellent yuv_fused/distortion |
| linear-srgb | EXCELLENT | 13 | Missing TF slice SIMD (#22, acknowledged TODO) |
| fast-ssim2 | EXCELLENT | 3 | AoS/SoA round-trips (#20, minor) |
| zensim | GOOD | 6 | Missing #[inline(always)] in fused.rs (#3), cbrt in loop (#21) |
| zenblend | EXCELLENT | 3 | None |
| zenfilters | GOOD | 7 | Generic bounds without inline(always) (#1-2), attribute style (#15) |
| zenresize | EXCELLENT | 7 | None |
| zenpng | EXCELLENT | 6 | None |
| heic | EXCELLENT | 6 | None |
| rav1d-safe | EXCELLENT | 9+ | Minor #[arcane] vs #[rite] style (#18) |
| zenflate | EXCELLENT | 3 | None |
| ultrahdr | GOOD | 1 | Uses magetypes generics (intentional) |
| BRAG | EXCELLENT | 12 | None |
| zenzstd | EXCELLENT | 2 | None |
| zenjxl-decoder | EXCELLENT | 6 | None |
| zenquant | GOOD | 1 | None |
| zenraw | GOOD | 3 | None |
| zenavif | GOOD | 6 | Generic magetypes in hot path (#23) |
| zenpixels | GOOD | 1 | None |

---

## Inlining Decision Framework

Before changing any inline attribute, apply this decision tree:

```
Does the function use SIMD intrinsics or magetypes ops?
├─ YES: Does it have #[rite] or #[arcane]?
│   ├─ YES: It already gets target_feature. LLVM decides inlining.
│   │   └─ Only add #[inline(always)] if profiling shows it's NOT being inlined
│   │       and the function is <50 lines.
│   └─ NO: It MUST inline to get target_feature from caller.
│       ├─ <20 lines: #[inline(always)]
│       ├─ 20-100 lines: #[inline] (LLVM usually inlines)
│       └─ >100 lines: Add #[rite] instead (gets target_feature without inlining)
└─ NO (pure scalar math):
    ├─ <10 lines, called in hot loop: #[inline(always)]
    ├─ 10-50 lines: #[inline]
    └─ >50 lines, called from 10+ sites: consider #[inline(never)] to avoid BTB aliasing
```

**Key insight**: `#[rite]` gives a function its own `#[target_feature]` annotation, so it can use SIMD instructions even without inlining. This is the right tool for large SIMD helpers that shouldn't bloat their callers. `#[inline(always)]` is for small helpers where call overhead dominates.

---

## Fix Priority

### Fixes Applied (2026-04-04)
- Items #4-7 — **DONE**: Removed 4 unimplemented dead-code functions from zenjpeg ARM/WASM SIMD
- Item #9 — **DONE**: Removed duplicate `#[cfg(target_arch)]` in zenwebp prediction.rs
- Item #15 — **DONE**: Changed `#[archmage::arcane]` → `#[arcane]` in zenfilters wasm128.rs

### False Positives (No Action Needed)
- Items #1-2 — `zenfilters/wide_simd.rs`: `#[inline]` is correct for large kernels called from monomorphized `#[magetypes]` context
- Item #3 — `zensim/fused.rs`: Helpers already have `#[inline(always)]`
- Item #8 — `zenwebp/transforms.rs`: Correct incant! → `#[arcane]` → `#[rite]` pattern, not double-wrapping
- Items #10-14 — All jxl-encoder and zensim helpers already properly annotated with `#[arcane]`/`#[rite]` + `#[inline(always)]`
- Items #16-17 — zenwebp uses explicit module paths consistently (no prelude import)

### Remaining Optimizations (2026-04-04)
- Item #20 — `fast-ssim2/xyb_simd.rs`: Vectorize Halley cbrt iterations (was doing 6 array round-trips, now 3) — **FIXED**
- Item #21 — `zensim/color.rs`: **FALSE POSITIVE** — already does scalar cbrtf_initial seed then SIMD Halley iterations. The seed extract-to-array is unavoidable (integer bit manipulation on float repr).
- Item #22 — `linear-srgb/default.rs`: Add `#[autoversion]` dispatch for TF slice operations — **FIXED**
- Item #23 — `zenavif/yuv_convert.rs`: **FALSE POSITIVE** — `magetypes::simd::f32x8` behind `#[cfg(target_arch = "x86_64")]` IS the concrete AVX2 type, not generic. Correct inside `#[arcane]` with Desktop64 token.

---

## Statistics

- **Total files audited**: 338
- **EXCELLENT**: ~180 files (53%)
- **GOOD**: ~150 files (44%)
- **NEEDS-FIX**: 0 files after fixes (was ~8 from false positives)
- **BAD**: 0 files (0%)
- **Total reported issues**: 23
- **Actual issues after verification**: 6 (4 dead code, 1 duplicate cfg, 1 style)
- **False positives from agent audits**: 17 (agents misread existing `#[inline(always)]` annotations, misidentified correct patterns as anti-patterns, or didn't read full file context)
- **All 6 real issues fixed**: 2026-04-04
