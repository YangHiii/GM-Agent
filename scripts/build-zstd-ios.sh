#!/bin/sh
# 交叉编译 zstd 为 arm64 iOS 静态库（CI 用）
set -eu

VERSION=${ZSTD_VERSION:-1.5.6}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST="$ROOT/third_party/zstd"
CACHE=${ZSTD_CACHE:-$ROOT/build/zstd-cache}

mkdir -p "$DEST" "$CACHE"

if [ -f "$DEST/arm64/lib/libzstd.a" ]; then
  echo "== zstd 已存在：$DEST/arm64/lib"
  exit 0
fi
if [ -f "$CACHE/arm64/lib/libzstd.a" ]; then
  echo "== 命中 zstd 缓存"
  mkdir -p "$DEST"
  cp -R "$CACHE/arm64" "$DEST/"
  exit 0
fi

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
WORK="$ROOT/build/zstd-$VERSION"
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

if [ ! -f "zstd-$VERSION.tar.gz" ]; then
  curl -fL --retry 3 -o "zstd-$VERSION.tar.gz" \
    "https://github.com/facebook/zstd/releases/download/v$VERSION/zstd-$VERSION.tar.gz"
fi
tar xzf "zstd-$VERSION.tar.gz"
cd "zstd-$VERSION/lib"

CC_BIN="$(xcrun -f clang) -target arm64-apple-ios15.0 -isysroot $SDK -O2"
make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" \
  CC="$CC_BIN" \
  AR="$(xcrun -f ar)" \
  libzstd.a

mkdir -p "$CACHE/arm64/lib" "$CACHE/arm64/include"
cp libzstd.a "$CACHE/arm64/lib/"
cp zstd.h zdict.h zstd_errors.h "$CACHE/arm64/include/" 2>/dev/null || true

if ! file "$CACHE/arm64/lib/libzstd.a" | grep -qi "arm64\|Mach-O"; then
  echo "!! libzstd.a 不是 iOS arm64" >&2
  file "$CACHE/arm64/lib/libzstd.a" >&2
  exit 1
fi

mkdir -p "$DEST"
cp -R "$CACHE/arm64" "$DEST/"
echo "== zstd 完成"
ls -lh "$DEST/arm64/lib/libzstd.a"
