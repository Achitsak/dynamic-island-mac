#!/bin/bash
# Builds "Dynamic Island.app" into ./build
#
#   ./build.sh           build for this Mac
#   ./build.sh run       build, then (re)launch
#   ./build.sh install   build, copy to /Applications, then (re)launch
#   ./build.sh dist      universal build + build/DynamicIsland.zip for a release
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Dynamic Island"
APP="build/$APP_NAME.app"
CONTENTS="$APP/Contents"
MODE="${1:-}"

mkdir -p build

if [ "$MODE" = "dist" ]; then
  echo "▸ Compiling (arm64 + x86_64)…"
  swift build -c release --triple arm64-apple-macosx14.0
  swift build -c release --triple x86_64-apple-macosx14.0
  lipo -create -output build/DynamicIsland \
    "$(swift build -c release --triple arm64-apple-macosx14.0 --show-bin-path)/DynamicIsland" \
    "$(swift build -c release --triple x86_64-apple-macosx14.0 --show-bin-path)/DynamicIsland"
else
  echo "▸ Compiling…"
  swift build -c release
  cp "$(swift build -c release --show-bin-path)/DynamicIsland" build/DynamicIsland
fi

echo "▸ Compiling media bridge…"
clang -dynamiclib -fobjc-arc -O2 -arch arm64 -arch x86_64 \
  -mmacosx-version-min=14.0 \
  -framework Foundation \
  -o build/libMediaBridge.dylib MediaBridge/MediaBridge.m

if [ ! -f build/AppIcon.icns ]; then
  echo "▸ Rendering app icon…"
  swift scripts/make-icon.swift build/AppIcon.iconset >/dev/null
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
mv build/DynamicIsland "$CONTENTS/MacOS/DynamicIsland"
cp build/libMediaBridge.dylib build/AppIcon.icns "$CONTENTS/Resources/"
cp Resources/Info.plist "$CONTENTS/Info.plist"

echo "▸ Signing (ad-hoc)…"
codesign --force --sign - "$CONTENTS/Resources/libMediaBridge.dylib"
codesign --force --sign - "$APP"

relaunch() {
  pkill -x DynamicIsland 2>/dev/null || true
  # The app refuses to start while another copy is alive, so wait for it to exit.
  for _ in {1..50}; do pgrep -x DynamicIsland >/dev/null || break; sleep 0.1; done
  open "$1"
}

case "$MODE" in
  run)
    relaunch "$APP"
    ;;
  install)
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/"
    relaunch "/Applications/$APP_NAME.app"
    echo "✓ Installed to /Applications/$APP_NAME.app"
    ;;
  dist)
    rm -f build/DynamicIsland.zip
    ditto -c -k --keepParent "$APP" build/DynamicIsland.zip
    echo "✓ build/DynamicIsland.zip"
    shasum -a 256 build/DynamicIsland.zip
    ;;
esac

echo "✓ Built $APP"
