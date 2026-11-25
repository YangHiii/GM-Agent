#!/bin/sh
# 交叉编译 OpenSSL 3.x 为 arm64 iOS 静态库（CI 用）
# 产出：third_party/openssl/arm64/lib/{libssl.a,libcrypto.a}
#
# 环境变量：
#   OPENSSL_VERSION  默认 3.5.0
#   OPENSSL_CACHE    可选的缓存目录（CodeMagic 用 $HOME/openssl-cache）
set -eu

VERSION=${OPENSSL_VERSION:-3.5.0}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST="$ROOT/third_party/openssl"
CACHE=${OPENSSL_CACHE:-$ROOT/build/openssl-cache}

mkdir -p "$DEST" "$CACHE"

# 已有产物直接退出（CI workflow 之间、重复构建都走这里）
if [ -f "$DEST/arm64/lib/libssl.a" ] && [ -f "$DEST/arm64/lib/libcrypto.a" ]; then
  echo "== OpenSSL 已存在：$DEST/arm64/lib"
  exit 0
fi

# 缓存命中
if [ -f "$CACHE/arm64/lib/libssl.a" ] && [ -f "$CACHE/arm64/lib/libcrypto.a" ]; then
  echo "== 命中缓存，复制到 $DEST"
  mkdir -p "$DEST"
  cp -R "$CACHE/arm64" "$DEST/"
  exit 0
fi

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
MIN_IOS=15.0
WORK="$ROOT/build/openssl-$VERSION"

echo "== 编译 OpenSSL $VERSION (min iOS $MIN_IOS)"
echo "   SDK: $SDK"

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

if [ ! -f "openssl-$VERSION.tar.gz" ]; then
  curl -fL --retry 3 -o "openssl-$VERSION.tar.gz" \
    "https://github.com/openssl/openssl/releases/download/openssl-$VERSION/openssl-$VERSION.tar.gz"
fi
tar xzf "openssl-$VERSION.tar.gz"
cd "openssl-$VERSION"

export CC="$(xcrun -f clang)"
export CROSS_TOP="$(dirname "$SDK")/.."
export CROSS_SDK="$(basename "$SDK")"

# no-asm: 避免汇编器依赖；no-tests/no-apps: 缩短构建时间
./Configure ios64-cross no-shared no-tests no-asm no-docs no-apps \
  no-deprecated no-legacy \
  --prefix="$CACHE/arm64" --openssldir="$CACHE/arm64/ssl"

make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" build_libs
make install_sw

# 验证产物确实是为 iOS 构建的
if ! file "$CACHE/arm64/lib/libcrypto.a" | grep -qi "arm64\|Mach-O"; then
  echo "!! 产出的库看起来不是 iOS arm64：" >&2
  file "$CACHE/arm64/lib/libcrypto.a" >&2
  exit 1
fi

mkdir -p "$DEST"
cp -R "$CACHE/arm64" "$DEST/"
echo "== 完成"
ls -lh "$DEST/arm64/lib/libssl.a" "$DEST/arm64/lib/libcrypto.a"
