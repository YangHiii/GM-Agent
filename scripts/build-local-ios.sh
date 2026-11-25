#!/bin/sh
# 本地 macOS 构建 ipa（需 Xcode + 命令行工具）
# 用法：sh scripts/build-local-ios.sh
set -eu
cd "$(dirname "$0")/.."

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
echo "== SDK: $SDK"

if [ ! -f third_party/openssl/arm64/lib/libssl.a ]; then
  echo "== 编译 OpenSSL（首次约 8 分钟）"
  sh scripts/build-openssl-ios.sh
fi

mkdir -p build
echo "== 编译引擎"
clang -target arm64-apple-ios15.0 -isysroot "$SDK" -O2 -std=gnu99 \
  -Iengine -Ithird_party/openssl/arm64/include \
  engine/json.c engine/session.c engine/tool.c engine/sse.c \
  engine/http.c engine/provider.c engine/turn.c engine/main.c \
  third_party/openssl/arm64/lib/libssl.a \
  third_party/openssl/arm64/lib/libcrypto.a \
  -framework Security -framework Foundation -lz \
  -o build/gm-engine

APP=build/GMAgent.app
rm -rf "$APP"; mkdir -p "$APP"
echo "== 编译 App"
clang -target arm64-apple-ios15.0 -isysroot "$SDK" -O2 -fobjc-arc -fblocks \
  -Iapp -Iapp/Core -Iapp/UI -Iapp/Agent \
  app/main.m app/GMAppDelegate.m app/GMLog.m app/Core/*.m app/UI/*.m app/Agent/*.m \
  -framework UIKit -framework Foundation -framework CoreGraphics \
  -framework QuartzCore -framework WebKit -framework Security \
  -o "$APP/GMAgent"

cp app/Resources/Info.plist "$APP/Info.plist"
cp build/gm-engine "$APP/gm-engine"
chmod +x "$APP/gm-engine"

echo "== 签名"
codesign --force --sign - "$APP/gm-engine"
codesign --force --sign - --entitlements app/Resources/entitlements.plist --deep "$APP"

echo "== 打包"
rm -rf build/pkg; mkdir -p build/pkg/Payload
cp -R "$APP" build/pkg/Payload/
( cd build/pkg && zip -qry ../GMAgent.ipa Payload )
ls -lh build/GMAgent.ipa
echo "== 完成: $(pwd)/build/GMAgent.ipa"
