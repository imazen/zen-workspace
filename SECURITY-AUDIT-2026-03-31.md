# Zen Codec Security Audit — 2026-03-31

Comprehensive security audit of all codec, compression, and container crates in the zen ecosystem.
Threat model: **malicious images entering critical server-side systems**.

## Summary

| Crate | CRIT | HIGH | MED | LOW | Top Issue |
|-------|------|------|-----|-----|-----------|
| **zenjpeg** | 2 | 4 | 5 | 3 | `skip_segment` OOB panic; unbounded ICC alloc |
| **zenpng** | 0 | 0 | 3 | 0 | Unchecked multiply (32-bit); unbounded text chunks |
| **zenwebp** | 2 | 3 | 4 | 4 | `assert!` panics in Huffman/predictor transforms |
| **zengif** | 0 | 2 | 5 | 5 | `Box::leak` per-request memory leak; stats underflow |
| **zentiff + image-tiff** | 3 | 4 | 5 | 5 | BigTIFF unbounded IFD; unenforced limits; assert panics |
| **zenjxl-decoder** | 0 | 3 | 6 | 6 | `assert!` panics in ANS; flat tree OOB; deferred errors |
| **jxl-encoder** | 2 | 4 | 6 | 5 | `assert_eq!` on input; unchecked dimension overflow |
| **zenavif-parse/ser/avif** | 1 | 4 | 4 | 7 | Infinite loop in `tile_log2`; unlimited defaults |
| **heic** | 3 | 5 | 8 | 6 | `expect` panics on dims; PCM unwrap; SAO corruption |
| **zenbitmaps** | 0 | 0 | 2 | 4 | `unreachable!()` violates panic-free claim (TGA) |
| **fax** | 1 | 4 | 2 | 2 | `assert!` panic; u16 overflow; unbounded Vec growth |
| **zenflate + zenzop** | 0 | 2 | 6 | 4 | No output size limit (decompression bombs) |
| **zenraw** | 2 | 5 | 7 | 5 | darktable timeout; `decode_bytes` race condition |
| **rav1d-safe** | 0 | 3 | 3 | 3 | `from_repr().unwrap()`; ITU-T T.35 infallible alloc |
| **aom-decoder-rs** | 2 | 2 | 4 | 5 | No memory limits enforced; all allocs infallible |
| **zenpdf** | 3 | 4 | 5 | 5 | Infinite recursion (hayro); decompression bomb; no limits |
| **ultrahdr** | 0 | 3 | 6 | 8 | OOB panic on stride mismatch; MPF OOM; XMP CPU exhaust |
| **zencodec/zencodecs** | 0 | 0 | 6 | 6 | FormatSet missing bits; fail-open policy defaults |
| **TOTAL** | **21** | **52** | **91** | **85** | |

---

## CRITICAL Findings (21)

### Infinite Loops / Hangs

| ID | Crate | File:Line | Issue |
|----|-------|-----------|-------|
| C-AVIF-1 | zenavif-parse | `obu.rs:626-635` | `tile_log2` infinite loop when `d << 32` wraps to 0 in release; attacker controls frame dimensions |
| C-PDF-1 | zenpdf (hayro-syntax) | `xref.rs:753` | Circular PREV chain in xref causes infinite stack recursion — no cycle detection |
| C-RAW-1 | zenraw | `darktable.rs:201` | `Command::output()` blocks indefinitely — no timeout on darktable-cli subprocess |

### Panics / Crashes from Untrusted Input

| ID | Crate | File:Line | Issue |
|----|-------|-----------|-------|
| C-WEBP-1 | zenwebp | `huffman.rs:184` | `assert!(secondary_table.len() <= 4096)` panics on crafted Huffman tree |
| C-WEBP-2 | zenwebp | `lossless_transform.rs:134+` | 9 `assert!()` calls in predictor transforms — all panic-reachable from bitstream |
| C-JPEG-1 | zenjpeg | `markers.rs:439` | `skip_segment` advances position past data end → OOB panic on next slice |
| C-TIFF-1 | image-tiff | `image.rs:1157-1158` | `assert!` in `expand_chunk` — panics on inconsistent layout from crafted TIFF |
| C-HEIC-1 | heic | `picture.rs:81` | `.expect("frame dimensions overflow")` — reachable via grid/overlay with large ispe dims |
| C-HEIC-2 | heic | `ctu.rs:3432` | `.unwrap()` on `pcm_params` — malformed bitstream sets pcm_flag without SPS PCM enabled |
| C-JXL-E-1 | jxl-encoder | `vardct/encoder.rs:308` | `assert_eq!` on public API — panics on dimension mismatch instead of returning Err |
| C-FAX-1 | fax | `lib.rs:173` | `assert!(bits <= 16)` in public `BitReader::peek()` — panics on misuse |

### OOM / Memory Amplification

| ID | Crate | File:Line | Issue |
|----|-------|-----------|-------|
| C-JPEG-2 | zenjpeg | `icc.rs:56-116` | ICC profile reassembly has no size limit; `MAX_ICC_PROFILE_SIZE` defined but never checked |
| C-TIFF-2 | image-tiff | `mod.rs:1889` | BigTIFF IFD entry count is `u64` — no cap, can loop billions of times |
| C-TIFF-3 | image-tiff | `mod.rs:473` | `ifd_value_size` limit (1 MiB) is defined but **never enforced** — 256x gap |
| C-AOM-1 | aom-decoder-rs | `buffer.rs:42` | `check_memory()` exists but is never called; 65k×65k frame = 25 GB allocation |
| C-AOM-2 | aom-decoder-rs | `buffer.rs:68` | All allocations use infallible `vec![]` — OOM = unrecoverable panic |
| C-PDF-2 | zenpdf (hayro-syntax) | `lzw_flate.rs:25` | FlateDecode `read_to_end()` with no output limit — decompression bomb |
| C-PDF-3 | zenpdf | `render.rs:116` | Direct API has no ResourceLimits — single page at 100x DPI = 16 GB |

### Data Corruption

| ID | Crate | File:Line | Issue |
|----|-------|-----------|-------|
| C-HEIC-3 | heic | `ctu.rs:1116` | SAO offset `as i8` truncation — silent pixel corruption on 10+ bit content |

### Integer Overflow

| ID | Crate | File:Line | Issue |
|----|-------|-----------|-------|
| C-JXL-E-2 | jxl-encoder | `channel.rs:265+` | `width * height * N` unchecked in `from_rgb8` etc. — can wrap on 64-bit, bypassing size check |

### Race Condition

| ID | Crate | File:Line | Issue |
|----|-------|-----------|-------|
| C-RAW-2 | zenraw | `darktable.rs:293` | `decode_bytes` uses fixed temp dir + filename — concurrent calls overwrite each other |

---

## HIGH Findings (52)

### Panics from untrusted input (assert/unwrap/expect)

- **zenjpeg** `entropy/mod.rs:145` — `huff_extend` shift overflow for `dc_cat > 31` (UB in release)
- **zenjpeg** `markers.rs:336` — DRI length not validated → parser desync
- **zenjpeg** `scan.rs:29` — SOS length not validated
- **zenjpeg** SIMD paths — dozens of `try_into().unwrap()` in quant/color hot paths
- **zenwebp** `lossless.rs:58` — `subsample_size` unwrap on u16 conversion
- **zentiff** `mod.rs:644` — FP predictor OOB panic on non-aligned decompressed data
- **zentiff** `mod.rs:1685` — `chunk_offsets[chunk]` direct indexing without bounds check
- **zenraw** `dng_render.rs:735` — `assert_eq!` in public `render()` method
- **heic** `codec.rs:1132` — `.unwrap()` on grid ref in streaming decode
- **heic** `mod.rs:331` — `.unwrap()` on SPS before picture finish
- **jxl-encoder** `huffman_tree.rs:167` — unbounded retry loop; `count_limit` overflows u32 → infinite loop
- **zenjxl-decoder** `ans.rs:241,305` — `assert!` in ANS alias map build
- **zenjxl-decoder** `tree.rs:394` — flat tree traversal can index OOB
- **rav1d-safe** `obu.rs:477+` — `from_repr().unwrap()` on bitstream values (6 sites)
- **rav1d-safe** `decode.rs` — 40+ `.unwrap()` on frame/seq header Options
- **aom-decoder-rs** `decode.rs:78` — `pending_frame_header.unwrap()` double-consume
- **aom-decoder-rs** `mode_info.rs:52` — `ModeInfoGrid::get()` no bounds check → panic
- **fax** `lib.rs:183` — `consume()` underflow panics in debug, wraps to garbage in release
- **fax** `decoder.rs:199` — `b1 as i16` overflows for width > 32767

### OOM / Unbounded allocation

- **zenwebp** `lossless.rs:319` — `num_huff_groups` up to 65536 → hundreds of MB from tiny input
- **zenwebp** — `check_frame_count` is defined but **never called** during ANMF parsing
- **zengif** `encoder.rs:371` — `Box::leak` per encode job — unbounded server-side memory leak
- **zentiff** `decode.rs:274` — `count_pages` walks entire IFD chain on every probe/decode
- **zenraw** `tiff_ifd.rs:238` — `count * type_size` can attempt 32 GB allocation from crafted entry
- **zenraw** `darktable.rs:335` — PFM dimensions validated **after** allocation, not before
- **heic** `ctu.rs:502` — SliceContext maps use infallible `vec![]` — 100+ MB per tile
- **heic** `picture.rs:100` — DecodedFrame planes use infallible `vec![]` — 1.5 GB for 16k×16k 4:4:4
- **jxl-encoder** — `Limits.max_memory_bytes` accepted but **never enforced**
- **jxl-encoder** — No absolute dimension cap; `ImageTooLarge` error defined but never constructed
- **jxl-encoder** `vardct/encoder.rs` — ~30 bytes/pixel infallible allocation without bounds
- **rav1d-safe** `obu.rs:2461` — ITU-T T.35 infallible allocation up to OBU size (~4 GB)
- **zenavif-parse** `lib.rs:1255` — Default constructors use `DecodeConfig::unlimited()`
- **zenavif-parse** `lib.rs:4030+` — No limit on entry_count loops in ipma/stts/stsc/stsz/grpl
- **ultrahdr** `container.rs:364` — `Vec::with_capacity(mp_entry_count)` — crafted MPF = 64 GB attempt
- **ultrahdr** `xmp.rs:173` — `MAX_XMP_LENGTH` defined but never enforced → CPU exhaustion
- **ultrahdr** `apply.rs:192` — OOB panic on stride/dimension mismatch in pixel access
- **fax** `decoder.rs:88` — Group3 unbounded Vec growth; no width bound, a0 wraps u16
- **fax** `decoder.rs:214` — Group4 `a0 + a0a1` u16 overflow → silent wrap

### Deferred/missing error handling

- **zenjxl-decoder** `decode.rs:283` — Deferred error reporting in entropy decoding returns 0 and continues → corrupted output before error detected
- **zenraw** `darktable.rs:220` — Temp file cleanup skipped on error paths (XMP metadata leak)
- **zentiff** `logluv.rs:86` — PackBits RLE silent truncation on short input → corrupted pixels
- **zenpdf** `render.rs:230` — Division by zero / NaN propagation in dimension calculations
- **zenpdf** (hayro) `x_object.rs:103` — No recursion depth limit on form XObject rendering
- **zenpdf** `render.rs:176` — `open_pdf` copies entire input unconditionally (memory doubling)
- **zenpdf** `render.rs:272` — Triple memory materialization in pixmap_to_buffer
- **zenflate** — No output size limit in buffer-to-buffer decompressor (decompression bombs)
- **zenflate** `streaming.rs:512` — Potential stall on crafted input with no output progress

### Other

- **zenraw** `tiff_ifd.rs:238` — Integer overflow on 32-bit targets in `data_size()`
- **zenraw** `decode.rs:664` — `width * height * cpp` overflow on 32-bit
- **aom-decoder-rs** `deblock.rs:84` — `wrapping_sub` fragile in deblock filter
- **heic** `params.rs:582` — `num_long_term_ref_pics_sps` unbounded loop from bitstream
- **heic** `params.rs:567` — `num_short_term_ref_pic_sets` u8 truncation

---

## Cross-Cutting Themes

### 1. `assert!` / `unwrap()` / `expect()` in non-test code (most common issue)
Every crate except zenpng has at least one panic-reachable path from crafted input.
**Fix pattern:** Replace with `if !cond { return Err(at!(Error::...)); }` or `.ok_or(at!(Error::...))?`.

### 2. Limits defined but not enforced
- image-tiff `ifd_value_size`: defined, never checked
- jxl-encoder `max_memory_bytes`: accepted, never enforced
- ultrahdr `MAX_XMP_LENGTH`: defined, never referenced
- zenjpeg `MAX_ICC_PROFILE_SIZE`: defined, never referenced
- aom-decoder-rs `check_memory()`: defined, never called
- zenwebp `check_frame_count()`: defined, never called
- zenavif-parse defaults to `unlimited()`: callers get zero protection

**Fix pattern:** Audit every `Limits`/`ResourceLimits` field and verify it's actually checked before the allocation it's supposed to guard.

### 3. Infallible allocations from attacker-controlled dimensions
heic, aom-decoder-rs, jxl-encoder, and zenraw use `vec![]` for large buffers without `try_reserve`.
**Fix pattern:** `let mut v = Vec::new(); v.try_reserve(size).map_err(|_| at!(Error::Oom))?;`

### 4. Integer overflow in dimension math
`width * height * bpp` computed as `usize` without `checked_mul` in jxl-encoder, zenraw (32-bit), zenpng (32-bit).
**Fix pattern:** `width.checked_mul(height).and_then(|n| n.checked_mul(bpp)).ok_or(at!(Error::Overflow))?`

### 5. Missing `whereat` error context
ultrahdr, zenflate, fax, and parts of zenpng use plain error types without source location.
Lower priority but reduces debuggability for production incidents.

### 6. Upstream dependency risks
- **zenpdf → hayro**: Infinite recursion, decompression bombs, no embedded image size limits
- **zentiff → image-tiff**: BigTIFF unbounded IFDs, unenforced limits, assert panics
- **zenraw → rawloader/rawler**: Trusted but not audited here

---

## Positive Observations

- **`#![forbid(unsafe_code)]`** is universal — eliminates memory corruption / RCE entirely
- **zengif** genuinely earns its "zero-trust" claim (Box::leak aside)
- **zenpng** is the cleanest codec — no CRITICAL or HIGH findings
- **zenjxl-decoder** has been hardened: MA tree quadratic fixed, OOM regression tests, memory tracker
- **zenflate** matches libdeflate safety with cooperative cancellation
- **Fuzz targets** exist for zenjpeg, zenpng, zenwebp, zengif, zenjxl-decoder, image-tiff, rav1d-safe
- **Cooperative cancellation** (`enough::Stop`) widely adopted
- **Fallible allocation** (`try_reserve`) used in zengif, zenjxl-decoder, zenpng, zenflate
- **ResourceLimits** infrastructure in zencodec provides the framework — enforcement gaps are fixable

---

## Priority Fix Order

1. **Replace all `assert!`/`unwrap()`/`expect()` on untrusted data paths** — every one is a DoS vector
2. **Enforce existing limits** — wire up the 6 defined-but-unchecked limit fields
3. **Add `try_reserve` to heic, aom-decoder-rs, jxl-encoder** — infallible allocs are OOM panics
4. **Fix zenavif-parse `tile_log2` infinite loop** — one-line fix (`if k >= 31 { break; }`)
5. **Add timeout to zenraw darktable subprocess** — thread-level DoS
6. **Fix zenraw `decode_bytes` race condition** — use unique temp dir like `decode_file`
7. **Cap zenwebp `num_huff_groups`** and call `check_frame_count()`
8. **Report hayro issues upstream** (infinite recursion, decompression bomb, XObject recursion)
9. **Add checked arithmetic** to jxl-encoder and zenraw dimension calculations
10. **Expand fuzz coverage** to heic, aom-decoder-rs, fax, ultrahdr, zenpdf
