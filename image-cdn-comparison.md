# Image CDN / Processing Service Feature Matrix

Comparison of Imageflow against all major image CDNs and processing services.

---

## Services Compared

| Category | Service | Type |
|----------|---------|------|
| **Ours** | **Imageflow 4** | Self-hosted server / library |
| **Major SaaS** | Cloudinary | SaaS CDN + DAM |
| | imgix | SaaS CDN |
| | Cloudflare Images | Edge CDN integration |
| | ImageKit | SaaS CDN + DAM |
| **CDN-Integrated** | Akamai IVM | Enterprise CDN add-on |
| | Fastly IO | CDN add-on |
| | Bunny Optimizer | CDN add-on |
| | KeyCDN | CDN add-on |
| **Specialty SaaS** | Sirv | SaaS CDN (e-commerce focus) |
| | Uploadcare | SaaS CDN + upload widget |
| **Open Source** | Thumbor | Self-hosted (Python/PIL) |
| | Imaginary | Self-hosted (Go/libvips) |
| | libvips/sharp | Library (C/Node.js) |

---

## 1. Input Format Support

| Format | Imageflow | Cloudinary | imgix | Cloudflare | ImageKit | Akamai | Fastly | Bunny | KeyCDN | Sirv | Uploadcare | Thumbor | Imaginary | libvips |
|--------|-----------|------------|-------|------------|----------|--------|--------|-------|--------|------|------------|---------|-----------|---------|
| JPEG | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| PNG | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| WebP | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| GIF | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | Yes | Opt | Yes |
| AVIF | Yes | Yes | Yes | Yes | Yes | Yes | Yes | — | — | Yes | Yes | — | — | Yes |
| HEIC/HEIF | Yes | Yes | Yes | Yes | Yes | Yes | Yes | — | — | Yes | Yes | — | Yes | Yes |
| JPEG XL | — | Yes | — | — | — | — | Yes | — | — | — | — | — | — | Yes |
| TIFF | — | Yes | Yes | — | Yes | Yes | — | — | Yes | Yes | Yes | — | Opt | Yes |
| SVG | — | Yes | Yes | Sanitize | Yes | — | — | — | — | Yes | — | — | Opt | Yes |
| PSD | — | Yes | Yes | — | — | — | — | — | — | Yes | — | — | — | — |
| PDF | — | Yes | Yes | — | Yes | — | — | — | — | Yes | — | — | Opt | Yes |
| BMP | Yes | Yes | — | — | — | Yes | — | — | — | — | Yes | — | — | Yes |
| RAW/DNG | — | — | — | — | — | — | — | — | — | — | — | — | — | — |
| EPS/AI | — | Yes | — | — | — | — | — | — | — | Yes | — | — | — | — |
| JPEG 2000 | — | — | — | — | — | Yes | — | — | — | — | — | — | — | Yes |
| OpenEXR | — | — | — | — | — | — | — | — | — | — | — | — | — | Yes |

**Imageflow notes:** Decode via zencodecs (pure Rust). AVIF decode via zenavif, HEIC via heic. JXL decode in progress (zenjxl-decoder exists). No SVG/PDF/PSD — these are document formats, not raster pipelines.

---

## 2. Output Format Support

| Format | Imageflow | Cloudinary | imgix | Cloudflare | ImageKit | Akamai | Fastly | Bunny | KeyCDN | Sirv | Uploadcare | Thumbor | Imaginary | libvips |
|--------|-----------|------------|-------|------------|----------|--------|--------|-------|--------|------|------------|---------|-----------|---------|
| JPEG | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| Progressive JPEG | Yes | Yes | Yes | Yes | Yes | Yes | Yes | — | Yes | — | Yes | Yes | — | Yes |
| PNG | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| Lossy PNG (pngquant) | Yes | — | — | — | — | — | — | — | — | — | — | — | — | — |
| WebP | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| AVIF | WIP | Yes | Yes | Yes | Yes | Yes | Yes | — | — | — | Yes | Yes | — | Yes |
| JPEG XL | WIP | Yes | — | — | — | — | Yes | — | — | — | — | — | — | Yes |
| GIF | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | — | Yes | — | Yes | — | Yes |
| MP4 (from GIF) | — | Yes | Yes | — | Yes | — | — | — | — | — | — | — | — | — |
| Blurhash | — | — | Yes | — | — | — | — | — | — | — | Yes | — | — | — |

**Imageflow notes:** MozJPEG encoder for JPEG. Lossy PNG via pngquant integration (unique). AVIF/JXL encode actively in development via zenrav1e/zenjxl. `f_auto` format negotiation planned.

---

## 3. Resize & Crop Operations

| Feature | Imageflow | Cloudinary | imgix | Cloudflare | ImageKit | Akamai | Fastly | Bunny | KeyCDN | Sirv | Uploadcare | Thumbor | Imaginary | libvips |
|---------|-----------|------------|-------|------------|----------|--------|--------|-------|--------|------|------------|---------|-----------|---------|
| Fit (within bounds) | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| Fill (crop to exact) | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | — | — | Yes |
| Pad (letterbox) | Yes | Yes | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | — | Yes | Yes | Yes |
| Scale (distort) | Yes | Yes | Yes | Yes | — | Yes | Yes | — | — | Yes | — | — | — | Yes |
| Downscale only | Yes | Yes | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | — | — | — | Yes |
| Upscale control | Yes | Yes | Yes | — | — | — | — | — | — | Yes | — | Yes | Yes | — |
| DPR multiplier | — | Yes | Yes | Yes | Yes | — | Yes | — | — | — | — | — | — | — |
| Manual crop (coords) | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| Percentage crop | Yes | Yes | — | — | — | — | — | — | — | — | — | — | — | — |
| Auto-trim whitespace | Yes | Yes | Yes | Yes | — | Yes | Yes | — | Yes | Yes | Yes | Yes | — | Yes |
| Aspect ratio crop | Yes | Yes | Yes | — | Yes | Yes | — | Yes | — | Yes | Yes | — | — | — |

**Imageflow notes:** 9 constraint modes (fit, within, within_crop, fit_crop, aspect_crop, larger_than, distort, within_pad, fit_pad). Per-axis scale control (up/down/both/canvas). Percentage-based crop coordinates via `cropxunits`/`cropyunits`.

---

## 4. Resampling Filters

| Feature | Imageflow | Cloudinary | imgix | Cloudflare | ImageKit | Akamai | Fastly | Bunny | KeyCDN | Sirv | Uploadcare | Thumbor | Imaginary | libvips |
|---------|-----------|------------|-------|------------|----------|--------|--------|-------|--------|------|------------|---------|-----------|---------|
| Filter count | **31** | ~3 | ~3 | 1 | 1 | ~3 | ~3 | 1 | 1 | 1 | 1 | ~3 | 1 | ~8 |
| Lanczos | Yes | Yes | Yes | Yes | — | Yes | Yes | — | — | — | — | Yes | — | Yes |
| Robidoux family | Yes | — | — | — | — | — | — | — | — | — | — | — | — | — |
| Ginseng | Yes | — | — | — | — | — | — | — | — | — | — | — | — | — |
| Cubic variants | Yes | — | — | — | — | — | — | — | — | — | — | — | — | Yes |
| Mitchell-Netravali | Yes | — | — | — | — | — | — | — | — | — | — | — | — | Yes |
| Separate up/down filters | Yes | — | — | — | — | — | — | — | — | — | — | — | — | — |
| Linear-light resampling | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | Yes |

**Imageflow advantage:** 31 resampling filters with independent up/down selection. Linear-light (gamma-correct) resampling by default — most CDNs resize in sRGB (incorrect, causes darkening at edges). This is Imageflow's single biggest quality advantage over every SaaS competitor.

---

## 5. Color & Tone Adjustments

| Feature | Imageflow | Cloudinary | imgix | Cloudflare | ImageKit | Akamai | Fastly | Bunny | KeyCDN | Sirv | Uploadcare | Thumbor | Imaginary | libvips |
|---------|-----------|------------|-------|------------|----------|--------|--------|-------|--------|------|------------|---------|-----------|---------|
| Brightness | Yes | Yes | Yes | Yes | — | — | Yes | Yes | — | Yes | Yes | Yes | — | Yes |
| Contrast | Yes | Yes | Yes | Yes | — | — | Yes | Yes | — | Yes | — | Yes | — | Yes |
| Saturation | Yes | Yes | Yes | Yes | — | Yes | Yes | Yes | — | Yes | — | Yes | — | — |
| Sharpen | Yes | Yes | Yes | Yes | — | Yes | Yes | Yes | Yes | Yes | Yes | Yes | — | Yes |
| Unsharp mask | — | Yes | Yes | — | — | Yes | — | — | — | — | Yes | — | — | Yes |
| Blur | — | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | Yes | Yes |
| Gamma | — | Yes | Yes | Yes | — | — | — | Yes | Yes | — | — | — | — | Yes |
| Hue shift | — | Yes | Yes | — | — | Yes | — | Yes | — | Yes | — | — | — | — |
| Vibrance | — | Yes | Yes | — | — | — | — | — | — | — | — | — | — | — |
| Exposure | — | Yes | Yes | — | — | — | — | — | — | Yes | — | — | — | — |
| Highlights/Shadows | — | Yes | Yes | — | — | — | — | — | — | Yes | — | — | — | — |
| Grayscale | Yes | Yes | Yes | Sat=0 | — | Yes | Yes | — | Yes | Yes | Yes | Yes | — | — |
| Sepia | Yes | Yes | Yes | — | — | — | — | Yes | — | — | — | — | — | — |
| Invert | Yes | Yes | Yes | — | — | — | — | — | Yes | — | Yes | — | — | — |
| Color matrix | Yes | — | — | — | — | — | — | — | — | — | — | — | — | — |
| White balance | Yes | — | — | — | — | — | — | — | — | — | — | — | — | — |

**Imageflow notes:** Color operations run in sRGB via `color_filter_srgb`. Sharpen integrated into resize pipeline with conditional trigger. White balance via histogram analysis. Color matrix for arbitrary linear transforms. Zenfilters (separate crate) adds 45+ Oklab perceptual filters, SIMD-accelerated — but not yet wired into imageflow4 URL API.

---

## 6. Smart/AI Features

| Feature | Imageflow | Cloudinary | imgix | Cloudflare | ImageKit | Akamai | Fastly | Bunny | KeyCDN | Sirv | Uploadcare | Thumbor | Imaginary | libvips |
|---------|-----------|------------|-------|------------|----------|--------|--------|-------|--------|------|------------|---------|-----------|---------|
| Face-aware crop | — | Yes | Yes | Yes | Yes | Yes | — | Yes | — | Yes | Yes | Yes | — | — |
| Content-aware crop | — | Yes | Yes | Yes | Yes | Yes | — | — | — | — | Yes | Yes | Yes | — |
| Object detection | — | Yes | — | — | — | — | — | — | — | — | Yes | — | — | — |
| Background removal | — | Yes | Yes | Yes | — | — | — | — | — | — | Yes | — | — | — |
| Generative fill | — | Yes | Yes | — | — | — | — | — | — | — | — | — | — | — |
| Generative remove | — | Yes | — | — | — | — | — | — | — | — | — | — | — | — |
| Generative replace | — | Yes | — | — | — | — | — | — | — | — | — | — | — | — |
| AI upscale | — | Yes | Yes | — | — | — | — | — | — | — | — | — | — | — |
| Auto-enhance | — | Yes | Yes | — | — | — | — | — | — | — | Yes | — | — | — |
| Red-eye removal | — | Yes | Yes | — | — | — | — | — | — | — | — | Yes | — | — |
| OCR | — | Yes | — | — | — | — | — | — | — | — | — | — | — | — |
| NSFW detection | — | Yes | — | — | — | — | — | — | — | — | Yes | — | — | — |

**Imageflow notes:** No AI/ML features in the image pipeline itself. `zensally` (ONNX face detection) and `zentract` (ONNX inference) exist as separate crates but aren't wired into imageflow4's URL API yet. This is the largest feature gap vs. SaaS competitors.

---

## 7. Overlays & Composition

| Feature | Imageflow | Cloudinary | imgix | Cloudflare | ImageKit | Akamai | Fastly | Bunny | KeyCDN | Sirv | Uploadcare | Thumbor | Imaginary | libvips |
|---------|-----------|------------|-------|------------|----------|--------|--------|-------|--------|------|------------|---------|-----------|---------|
| Image watermark | Yes | Yes | Yes | — | Yes | Yes | Yes | — | Yes | Yes | Yes | Yes | Yes | Yes |
| Text overlay | — | Yes | Yes | — | Yes | — | — | — | — | Yes | Yes | — | Yes | — |
| Multi-layer compositing | Yes | Yes | Yes | — | Yes | — | — | — | — | — | Yes | — | — | Yes |
| Gravity/anchor positioning | Yes | Yes | Yes | — | Yes | Yes | — | — | — | Yes | Yes | Yes | — | — |
| Opacity control | Yes | Yes | Yes | — | — | Yes | — | — | Yes | Yes | — | — | — | — |
| Min-size threshold | Yes | — | Yes | — | — | — | — | — | — | — | — | — | — | — |
| Blend modes | — | Yes | Yes | — | Yes | — | — | — | — | — | — | — | — | Yes |

**Imageflow notes:** Image watermarks with gravity, fit modes, opacity, and min-size thresholds. Multi-input graph allows arbitrary compositing. No text rendering — Imageflow renders pixels, not glyphs.

---

## 8. Quality Optimization

| Feature | Imageflow | Cloudinary | imgix | Cloudflare | ImageKit | Akamai | Fastly | Bunny | KeyCDN | Sirv | Uploadcare | Thumbor | Imaginary | libvips |
|---------|-----------|------------|-------|------------|----------|--------|--------|-------|--------|------|------------|---------|-----------|---------|
| Auto format (Accept) | Planned | Yes | Yes | Yes | Yes | Yes | Yes | Yes | — | Yes | Yes | Yes | — | — |
| Perceptual quality metric | **Yes** | Yes | — | — | — | Yes | — | — | — | — | Yes | — | — | — |
| JPEG quality probing | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | — |
| Shrink guarantee | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | — |
| MozJPEG encoder | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | Opt |
| Butteraugli targeting | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | — |
| SSIM2 targeting | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | — |
| Lossless JPEG fast path | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | — |
| Slow-connection quality | — | — | — | Yes | — | — | — | — | — | — | — | — | — | — |
| Lossy PNG (pngquant) | Yes | — | — | — | — | — | — | — | — | — | — | — | — | — |
| File-size targeting | — | — | — | — | — | — | — | — | — | — | — | Yes | — | — |

**Imageflow advantage:** Quality probing reads the source JPEG encoder family and quality level, then calibrates re-encode quality to match. Butteraugli and SSIMULACRA2 distance targeting for perceptual quality. Shrink guarantee ensures output ≤ source file size. MozJPEG for optimal Huffman tables and trellis quantization. Lossless JPEG fast path (DCT-domain transforms) for orientation-only pipelines at ~10x speed. No other CDN offers this combination.

---

## 9. Color Management

| Feature | Imageflow | Cloudinary | imgix | Cloudflare | ImageKit | Akamai | Fastly | Bunny | KeyCDN | Sirv | Uploadcare | Thumbor | Imaginary | libvips |
|---------|-----------|------------|-------|------------|----------|--------|--------|-------|--------|------|------------|---------|-----------|---------|
| ICC profile preserve | Yes | Yes | — | Yes | — | — | — | — | — | — | — | — | — | Yes |
| ICC profile convert | Yes | Yes | — | — | — | — | — | — | — | — | Yes | — | — | Yes |
| Custom ICC profile | — | Yes | — | — | — | — | — | — | — | — | — | — | — | Yes |
| sRGB conversion | Yes | Yes | Yes | — | — | — | — | — | — | — | Yes | — | Yes | Yes |
| CMYK handling | — | Yes | Auto | — | — | — | — | — | — | — | — | — | — | Yes |
| Wide gamut (P3/2020) | **CICP** | — | — | — | — | — | — | — | — | — | — | — | — | — |
| HDR / PQ / HLG | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | — |
| UltraHDR gain maps | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | — |
| Linear-light pipeline | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | Yes |
| Per-op color space | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | — |
| Atomic finalization | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | — |

**Imageflow advantage:** End-to-end ICC profiles, CICP-native HDR (PQ, HLG, BT.2020), UltraHDR gain map decode/encode, linear-light resize, per-operation working space negotiation (linear for resize, Oklab for sharpen, premultiplied for compositing), atomic finalization guaranteeing pixel/metadata sync. No CDN competitor handles HDR or gain maps. Cloudinary has good ICC support but no HDR pipeline.

---

## 10. Security & DoS Protection

| Feature | Imageflow | Cloudinary | imgix | Cloudflare | ImageKit | Akamai | Fastly | Bunny | KeyCDN | Sirv | Uploadcare | Thumbor | Imaginary | libvips |
|---------|-----------|------------|-------|------------|----------|--------|--------|-------|--------|------|------------|---------|-----------|---------|
| Max decode size limit | **Yes** | — | — | — | — | — | — | — | — | — | — | — | Yes | — |
| Max frame size limit | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | — |
| Max encode size limit | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | — |
| Megapixel limit | **Yes** | Yes | — | Yes | Yes | — | Yes | — | — | — | Yes | Yes | Yes | — |
| Memory-bounded streaming | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | Yes |
| Signed URLs | Server | Yes | MD5 | Yes | SHA256 | Yes | — | SHA256 | SHA256 | JWT | SHA256 | SHA1 | HMAC | N/A |
| SVG sanitization | — | — | — | **Yes** | — | — | — | — | — | — | — | — | — | — |
| Content Credentials (C2PA) | — | — | — | **Yes** | — | — | — | — | — | — | — | — | — | — |
| Malware scanning | — | — | — | — | — | — | — | — | — | — | **Yes** | — | — | — |
| Pure Rust (no C libs) | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | — |

**Imageflow advantage:** Configurable per-operation dimension and megapixel limits (decode, frame, encode). Strip-based streaming = O(strip_height × width) memory, not O(width × height). Pure Rust codec stack eliminates C library memory safety risks. SaaS providers handle DoS at the platform level (rate limiting, WAF) but don't expose per-request resource controls.

---

## 11. Architecture & Performance

| Feature | Imageflow | Cloudinary | imgix | Cloudflare | ImageKit | Akamai | Fastly | Bunny | KeyCDN | Sirv | Uploadcare | Thumbor | Imaginary | libvips |
|---------|-----------|------------|-------|------------|----------|--------|--------|-------|--------|------|------------|---------|-----------|---------|
| Streaming/strip pipeline | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | **Yes** |
| Graph-based pipeline | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | **Yes** |
| Multi-output (fan-out) | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | Yes |
| Lossless JPEG fast path | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | — |
| Process isolation (CLI) | Yes | SaaS | SaaS | Edge | SaaS | Edge | Edge | Edge | Edge | SaaS | SaaS | Yes | Yes | N/A |
| SIMD acceleration | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | Yes |
| Self-hostable | **Yes** | — | — | — | — | — | — | — | — | — | — | Yes | Yes | Yes |
| Edge computing | — | Multi-CDN | CDN | **330+ PoPs** | CDN | **4000+ PoPs** | CDN | 119 PoPs | CDN | CDN | 325K nodes | — | — | — |
| On-demand (lazy) | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | N/A |
| Pre-processing (eager) | Yes | Yes | — | — | — | — | — | — | — | — | — | — | — | N/A |

**Imageflow advantage:** Strip-based streaming (16-row default) with per-operation fat-strip overlap. Acyclic graph pipelines with single-decode fan-out to multiple outputs. Lossless JPEG fast path for orientation-only transforms (~10x speedup). SIMD via archmage (AVX2/FMA). Claimed 17x faster than ImageMagick.

---

## 12. API & Integration

| Feature | Imageflow | Cloudinary | imgix | Cloudflare | ImageKit | Akamai | Fastly | Bunny | KeyCDN | Sirv | Uploadcare | Thumbor | Imaginary | libvips |
|---------|-----------|------------|-------|------------|----------|--------|--------|-------|--------|------|------------|---------|-----------|---------|
| URL querystring API | **Yes** | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes | — |
| JSON graph API | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | — |
| Compact srcset syntax | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | — |
| C ABI | Yes | — | — | — | — | — | — | — | — | — | — | — | — | Yes |
| ImageResizer compat | **Yes** | — | — | — | — | — | — | — | — | — | — | — | — | — |
| .NET bindings | Yes | Yes | — | — | Yes | — | — | — | — | — | — | — | — | — |
| Node.js bindings | Yes | Yes | Yes | Workers | Yes | — | — | — | — | — | Yes | — | — | **Yes** |
| Go bindings | Yes | Yes | Yes | — | Yes | — | Yes | — | — | — | Yes | — | Native | — |
| Python bindings | — | Yes | Yes | — | Yes | — | — | — | — | — | Yes | Native | — | Yes |
| Chained transforms | Yes | Yes | Yes | — | Yes | — | — | — | — | Yes | Yes | Yes | Yes | — |
| Named presets | — | Yes | — | Variants | Yes | Policies | — | Classes | — | Profiles | — | — | — | — |
| Conditional transforms | — | Yes | — | — | Yes | Yes | — | — | — | — | — | — | — | — |

**Imageflow advantage:** Dual API — URL querystring (backward-compatible with ImageResizer 4) and JSON graph (arbitrary acyclic pipelines with multiple I/O). Compact srcset syntax (`?srcset=webp-70,sharp-15,100w,2x`). C ABI for embedding. No other service offers graph-based pipeline definition via API.

---

## 13. Video Processing

| Feature | Imageflow | Cloudinary | imgix | Cloudflare | ImageKit | Akamai | Fastly | Bunny | Sirv | Uploadcare |
|---------|-----------|------------|-------|------------|----------|--------|--------|-------|------|------------|
| Transcoding | — | Yes | Yes | — | Yes | Yes | — | Stream | — | — |
| HLS/DASH | — | Yes | Yes | — | Yes | Yes | — | Yes | — | — |
| AV1 output | — | Yes | — | — | Yes | — | — | — | — | — |
| Smart crop (video) | — | Yes | Yes | — | — | — | — | — | — | — |
| Subtitles/captions | — | Yes | — | — | — | — | — | — | — | — |
| GIF → MP4 | — | Yes | Yes | — | Yes | — | — | — | — | — |
| Live streaming | — | Yes | — | Stream | — | — | — | Yes | — | — |

**Imageflow:** Not a video processor. This is a legitimate scope difference, not a gap.

---

## 14. Pricing Comparison

| Service | Model | Entry Price | Unit Economics | Free Tier |
|---------|-------|-------------|----------------|-----------|
| **Imageflow** | Self-hosted | Infrastructure only | CPU + RAM cost | Open source (AGPL) |
| **Cloudinary** | Credits (shared) | $89/mo (225 credits) | ~$0.40/credit | 25 credits/mo |
| **imgix** | Credits | $75/mo (375 credits) | ~$0.20/credit | 100 credits (trial) |
| **Cloudflare** | Per-transform | $0 (5K free) | $0.50/1K transforms | 5K transforms/mo |
| **ImageKit** | Bandwidth | $0 (20 GB free) | $0.45/GB overage | 20 GB/mo |
| **Akamai IVM** | Enterprise quote | Custom | — | — |
| **Fastly IO** | Per-request | $1,500/mo (30M req) | $0.05/1K requests | — |
| **Bunny** | Flat rate | $9.50/mo/zone | Unlimited transforms | — |
| **KeyCDN** | Per-operation | $4/mo minimum | $0.40/1K operations | — |
| **Sirv** | Storage+bandwidth | $19/mo | Unlimited transforms | 500 MB / 2 GB |
| **Uploadcare** | Operations | $79/mo | Per-op + traffic | Limited |
| **Thumbor** | Self-hosted | Infrastructure only | CPU + RAM cost | Open source (MIT) |
| **Imaginary** | Self-hosted | Infrastructure only | CPU + RAM cost | Open source (MIT) |
| **libvips/sharp** | Library | $0 | — | Open source (LGPL) |

**Imageflow advantage:** Self-hosted = predictable costs that scale with compute, not with requests or bandwidth. No per-image or per-transform fees. AGPL license may be limiting for some use cases (commercial license available).

---

## 15. Unique Differentiators Summary

### Imageflow's exclusive advantages (no competitor matches):

1. **31 resampling filters** with independent up/down selection — most CDNs offer 1-3
2. **Linear-light resampling by default** — competitors resize in sRGB, causing edge darkening
3. **Perceptual quality targeting** — Butteraugli and SSIMULACRA2 distance metrics for encode quality
4. **JPEG quality probing** — reads source encoder family + quality to calibrate re-encode
5. **Shrink guarantee** — output file ≤ input file, always
6. **Lossless JPEG fast path** — DCT-domain transforms for orientation-only, ~10x faster
7. **UltraHDR / HDR gain maps** — decode and encode, spatially locked secondary planes
8. **CICP-native HDR pipeline** — PQ, HLG, BT.2020 color codes
9. **Per-operation color space negotiation** — linear for resize, Oklab for sharpen, premultiplied for compositing
10. **Atomic color finalization** — ICC + CICP + pixels guaranteed in sync
11. **Graph-based JSON API** — arbitrary acyclic pipeline topologies with multi-input/multi-output
12. **Pure Rust codec stack** — no C library dependencies, memory-safe by construction
13. **Lossy PNG** — pngquant integration for dramatic PNG size reduction
14. **Configurable per-request resource limits** — decode/frame/encode size caps for DoS prevention

### Where competitors lead:

1. **AI/ML features** — Cloudinary and imgix have generative AI (fill, remove, replace, upscale, background removal). Imageflow has none in the URL API.
2. **Face/content-aware cropping** — Every major SaaS CDN has this. Imageflow does not (zensally exists but isn't integrated).
3. **Text overlays** — Cloudinary, imgix, Sirv, ImageKit all render text. Imageflow doesn't do glyph rendering.
4. **Auto format negotiation** — `f_auto` / `format=auto` is table stakes for CDNs. Imageflow has this planned but not shipped.
5. **Video processing** — Cloudinary, imgix, ImageKit handle video. Imageflow is image-only.
6. **Edge distribution** — SaaS CDNs cache at hundreds/thousands of edge locations. Self-hosted Imageflow needs a CDN in front.
7. **SVG/PDF rendering** — Several competitors rasterize SVG and PDF. Imageflow handles raster formats only.
8. **Content Credentials (C2PA)** — Cloudflare preserves and extends C2PA provenance chains. Unique.
9. **Managed service simplicity** — SaaS CDNs require zero infrastructure management.

### Where Imageflow is unique in class:

Among **self-hosted** solutions (vs. Thumbor, Imaginary, libvips/sharp):
- Only one with a URL querystring API AND graph-based JSON API
- Only one with strip-based streaming (O(rows) memory, not O(pixels))
- Only one with HDR/UltraHDR support
- Only one with perceptual quality metrics for encode decisions
- Only one with JPEG quality probing and shrink guarantee
- Only one with 31 resampling filters and linear-light default
- Only one with pure Rust codecs (no C library attack surface)

---

## Recommendations for Imageflow Positioning

**Target as "best quality, best performance, self-hosted":**
- Lead with linear-light resampling (measurable quality difference in every resize)
- Lead with perceptual quality optimization (smaller files at same visual quality)
- Lead with security story (pure Rust, resource limits, streaming pipeline)
- Lead with HDR/UltraHDR (no competitor has this)

**Close the gap on table-stakes features:**
- `f_auto` format negotiation (highest impact, lowest effort)
- AVIF + JXL encode (in progress via zenrav1e/zenjxl)
- Face-aware crop (zensally exists, wire it in)
- Blur filter (commonly expected)

**Don't try to compete on:**
- Generative AI (Cloudinary/imgix have massive ML infrastructure)
- Video processing (different domain)
- Edge distribution (pair with Cloudflare/Fastly/Bunny CDN instead)
- Text rendering (not core value prop)
