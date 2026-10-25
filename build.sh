#!/bin/bash
# 构建 LinuxDo 2：原生 AppKit 窗口、侧栏、Liquid Glass 提示和 WKWebView 内容。
# 用法：./build.sh [release|debug|test]
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-release}"
MIN_OS="12.0"
BUILD="build"
APP="$BUILD/LinuxDo.app"
MODULE_CACHE="${LINUXDO_MODULE_CACHE:-${TMPDIR:-/tmp}/LinuxDoModuleCache}"
SOURCES=(Sources/*.swift)

case "$MODE" in release|debug|test) ;; *) echo "未知模式：$MODE" >&2; exit 2 ;; esac
mkdir -p "$BUILD" "$MODULE_CACHE"

if [[ "$MODE" == "test" ]]; then
  echo "==> 运行核心测试"
  xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos${MIN_OS}" -module-cache-path "$MODULE_CACHE" \
    Sources/Core.swift Tests/CoreTests.swift -o "$BUILD/CoreTests"
  "$BUILD/CoreTests"
  exit 0
fi

echo "==> 清理应用产物"
rm -rf "$APP" "$BUILD/LinuxDo.dmg" "$BUILD/dmg" "$BUILD/AppIcon.iconset"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 生成图标"
xcrun swiftc -O -module-cache-path "$MODULE_CACHE" Tools/make_icon.swift -o "$BUILD/make_icon"
"$BUILD/make_icon" "$BUILD/AppIcon-1024.png"
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$BUILD/AppIcon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$BUILD/AppIcon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
if ! iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  echo "    iconutil 不可用，使用仓库内 AppIcon.icns"
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

if [[ "$MODE" == "debug" ]]; then
  echo "==> 编译调试版（当前 Mac 架构）"
  ARCH="$(uname -m)"
  xcrun swiftc -Onone -g -D DEBUG -swift-version 5 -target "${ARCH}-apple-macos${MIN_OS}" \
    -module-cache-path "$MODULE_CACHE" "${SOURCES[@]}" -o "$APP/Contents/MacOS/LinuxDo"
else
  echo "==> 编译发布版（arm64 + x86_64）"
  for arch in arm64 x86_64; do
    xcrun swiftc -O -swift-version 5 -target "${arch}-apple-macos${MIN_OS}" \
      -module-cache-path "$MODULE_CACHE" "${SOURCES[@]}" -o "$BUILD/LinuxDo-${arch}"
  done
  lipo -create "$BUILD/LinuxDo-arm64" "$BUILD/LinuxDo-x86_64" -output "$APP/Contents/MacOS/LinuxDo"
fi

echo "==> 打包与签名"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Preview.html "$APP/Contents/Resources/Preview.html"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

if [[ "$MODE" == "release" ]]; then
  echo "==> 生成 DMG"
  STAGE="$BUILD/dmg"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "LinuxDo" -srcfolder "$STAGE" -ov -format UDZO "$BUILD/LinuxDo.dmg" >/dev/null
  rm -rf "$STAGE" "$BUILD/LinuxDo-arm64" "$BUILD/LinuxDo-x86_64"
fi
rm -rf "$BUILD/make_icon" "$ICONSET"
echo "==> 完成：$(pwd)/$APP"
