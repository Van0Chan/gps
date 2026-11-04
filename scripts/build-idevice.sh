#!/usr/bin/env bash
# Zostaví knižnicu idevice (Rust) pre iOS a skopíruje ju do Vendor/idevice.
# Potrebuje: macOS, Xcode, rustup.
set -euo pipefail

IDEVICE_REPO="https://github.com/jkcoxson/idevice"
IDEVICE_REV="89702099f4d7552f704f93b4526756abda319ceb"
FEATURES="ring,tcp,tunnel_tcp_stack,dvt,location_simulation,mobile_image_mounter,tss,cryptexd"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/.build/idevice"
OUT="$ROOT/Vendor/idevice"

rustup target add aarch64-apple-ios >/dev/null

if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" remote add origin "$IDEVICE_REPO"
fi
if [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)" != "$IDEVICE_REV" ]; then
  git -C "$SRC" fetch -q --depth 1 origin "$IDEVICE_REV"
  git -C "$SRC" checkout -q --force FETCH_HEAD
fi

(
  cd "$SRC/ffi"
  IPHONEOS_DEPLOYMENT_TARGET=17.0 cargo build --release \
    --target aarch64-apple-ios \
    --no-default-features --features "$FEATURES"
)

mkdir -p "$OUT/include" "$OUT/lib"
cp "$SRC/ffi/idevice.h" "$OUT/include/idevice.h"
cp "$SRC/target/aarch64-apple-ios/release/libidevice_ffi.a" "$OUT/lib/libidevice_ffi.a"
ls -lh "$OUT/lib/libidevice_ffi.a"
