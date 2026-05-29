#!/usr/bin/env bash
# Cross-platform SIMD parity test runner
#
# Tests all image crates on x86_64 (native), aarch64 (cross/qemu), and
# wasm32 (wasmtime+simd128). Reports pass/fail per crate per target.
#
# Usage: ./scripts/cross-platform-test.sh [crate...]
# No args = test all image crates.

set -euo pipefail
cd "$(dirname "$0")/.."

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Crates with SIMD code that need cross-platform testing.
# Format: "crate_name:manifest_path:wasm_ok"
# wasm_ok=yes means cargo test works on wasm32 (no fs4/criterion/rayon dev-deps)
# wasm_ok=check means only cargo check works (dev-deps block cargo test)
CRATES=(
  "linear-srgb:linear-srgb/Cargo.toml:yes"
  "zenblend:zenblend/Cargo.toml:yes"
  "zenpng:zenpng/Cargo.toml:yes"
  "zenwebp:zenwebp/Cargo.toml:yes"
  "heic:heic/Cargo.toml:check"       # criterion dev-dep
  "zenquant:zenquant/Cargo.toml:check"  # fd-lock dev-dep
  "fast-ssim2:fast-ssim2/fast-ssim2/Cargo.toml:check"  # zenbench dev-dep
  "zenjpeg:zenjpeg/zenjpeg/Cargo.toml:check"  # zenbench dev-dep
  "zenresize:zenresize/Cargo.toml:check"  # zenbench dev-dep
  "zenfilters:zenfilters/Cargo.toml:check"  # zenbench dev-dep
  "zensim:zensim/zensim/Cargo.toml:check"  # zenbench dev-dep
  "ultrahdr-core:ultrahdr/ultrahdr-core/Cargo.toml:yes"
  "zenpixels-convert:zenpixels/zenpixels-convert/Cargo.toml:yes"
  "zenzstd:zenzstd/Cargo.toml:check"  # fd-lock dev-dep
)

# Filter to requested crates if args given
if [ $# -gt 0 ]; then
  FILTERED=()
  for arg in "$@"; do
    for entry in "${CRATES[@]}"; do
      name="${entry%%:*}"
      if [ "$name" = "$arg" ]; then
        FILTERED+=("$entry")
      fi
    done
  done
  CRATES=("${FILTERED[@]}")
fi

pass=0
fail=0
skip=0
results=""

run_test() {
  local name="$1" manifest="$2" target="$3" extra_flags="$4"
  local cmd result exit_code

  if [ "$target" = "aarch64-unknown-linux-gnu" ]; then
    cmd="cross test --manifest-path $manifest --target $target --release --lib $extra_flags"
  else
    cmd="cargo test --manifest-path $manifest --target $target --release --lib $extra_flags"
  fi

  result=$($cmd 2>&1) && exit_code=0 || exit_code=$?

  local test_line
  test_line=$(echo "$result" | grep 'test result:' | tail -1)

  if [ $exit_code -eq 0 ] && [ -n "$test_line" ]; then
    local passed
    passed=$(echo "$test_line" | grep -o '[0-9]* passed' | grep -o '[0-9]*')
    printf "${GREEN}PASS${NC} %-22s %-30s %s tests\n" "$name" "$target" "$passed"
    results+="PASS $name $target ${passed}t\n"
    ((pass++))
  else
    local err
    err=$(echo "$result" | grep -E 'error(\[|:)' | head -1)
    printf "${RED}FAIL${NC} %-22s %-30s %s\n" "$name" "$target" "$err"
    results+="FAIL $name $target\n"
    ((fail++))
  fi
}

run_check() {
  local name="$1" manifest="$2" target="$3" extra_flags="$4"
  local result exit_code

  result=$(cargo check --manifest-path "$manifest" --target "$target" $extra_flags 2>&1) && exit_code=0 || exit_code=$?

  if [ $exit_code -eq 0 ]; then
    printf "${YELLOW}CHECK${NC} %-21s %-30s compiles OK (test blocked by dev-deps)\n" "$name" "$target"
    results+="CHECK $name $target\n"
    ((skip++))
  else
    local err
    err=$(echo "$result" | grep -E 'error(\[|:)' | head -1)
    printf "${RED}FAIL${NC} %-22s %-30s %s\n" "$name" "$target" "$err"
    results+="FAIL $name $target\n"
    ((fail++))
  fi
}

echo "========================================================"
echo "Cross-platform SIMD parity tests"
echo "========================================================"
echo ""

# x86_64 (native)
echo "--- x86_64 (native) ---"
for entry in "${CRATES[@]}"; do
  IFS=: read -r name manifest wasm_ok <<< "$entry"
  run_test "$name" "$manifest" "x86_64-unknown-linux-gnu" ""
done
echo ""

# aarch64 (cross/qemu)
echo "--- aarch64-unknown-linux-gnu (cross/qemu) ---"
for entry in "${CRATES[@]}"; do
  IFS=: read -r name manifest wasm_ok <<< "$entry"
  run_test "$name" "$manifest" "aarch64-unknown-linux-gnu" ""
done
echo ""

# wasm32 (wasmtime + simd128)
echo "--- wasm32-wasip1 (wasmtime + simd128) ---"
export RUSTFLAGS="-C target-feature=+simd128"
for entry in "${CRATES[@]}"; do
  IFS=: read -r name manifest wasm_ok <<< "$entry"
  if [ "$wasm_ok" = "yes" ]; then
    run_test "$name" "$manifest" "wasm32-wasip1" ""
  else
    run_check "$name" "$manifest" "wasm32-wasip1" ""
  fi
done
unset RUSTFLAGS
echo ""

# Summary
echo "========================================================"
echo "Summary: ${pass} passed, ${fail} failed, ${skip} check-only"
echo "========================================================"
echo ""
printf "$results" | column -t
