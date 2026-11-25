#!/bin/sh
# 交叉编译 OpenSSL 3.x 为 arm64 iOS 静态库（CI 用，结果缓存到 third_party/openssl）
#
# 用法：sh scripts/build-openssl-ios.sh
# 产出：third_party/openssl/arm64/lib/{libssl.a,libcrypto.a}
set -eux

VERSION=${OPENSSL_VERSION:-3.5.0}
WORK=${PWD}/build/openssl
DEST=${PWD}/third_party/openssl
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
MIN_IOS=15.0

if [ -f "$DEST/arm64/lib/libssl.a" ]; then
  echo "== OpenSSL 已存在，跳过"
  exit 0
fi

mkdir -p "$WORK" "$DEST"
cd "$WORK"

if [ ! -f "openssl-$VERSION.tar.gz" ]; then
  curl -fL -o "openssl-$VERSION.tar.gz" "https://github.com/openssl/openssl/releases/download/openssl-$VERSION/openssl-$VERSION.tar.gz"
fi
rm -rf "openssl-$VERSION"
tar xzf "openssl-$VERSION.tar.gz"
cd "openssl-$VERSION"

# iOS 交叉编译环境
export CROSS_TOP="$(dirname "$SDK")/.."
export CROSS_SDK="$(basename "$SDK")"
export CC="$(xcrun -f clang)"
export CFLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=$MIN_IOS -O2"
export LDFLAGS="-arch arm64 -isysroot $SDK -miphoneos-version-min=$MIN_IOS"

./Configure ios64-cross no-shared no-tests no-asm no-docs no-apps \
  --prefix="$DEST/arm64" --openssldir="$DEST/arm64/ssl"

make -j"$(sysctl -n hw.ncpu)"
make install_sw

echo "== 产出"
ls -lh "$DEST/arm64/lib/libssl.a" "$DEST/arm64/lib/libcrypto.a"
