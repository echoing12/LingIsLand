#!/bin/bash
# 从 Resources/AppIcon.svg 生成 Resources/AppIcon.icns（10 种尺寸）
# 依赖系统自带：qlmanage / sips / iconutil
set -euo pipefail
cd "$(dirname "$0")/.."

SVG="Resources/AppIcon.svg"
TMP_1024="$(mktemp -t AppIcon.XXXX).png"
ICONSET="$(mktemp -d -t AppIcon.XXXX).iconset"

echo "==> 渲染 SVG → 1024px PNG…"
qlmanage -t -s 1024 -o "$(dirname "$TMP_1024")" "$SVG" >/dev/null 2>&1
cp "$(dirname "$TMP_1024")/$(basename "$SVG").png" "$TMP_1024"

echo "==> 生成 iconset 各尺寸…"
mkdir -p "$ICONSET"
sips -z 16 16   "$TMP_1024" --out "$ICONSET/icon_16x16.png"       >/dev/null 2>&1
sips -z 32 32   "$TMP_1024" --out "$ICONSET/icon_16x16@2x.png"     >/dev/null 2>&1
sips -z 32 32   "$TMP_1024" --out "$ICONSET/icon_32x32.png"        >/dev/null 2>&1
sips -z 64 64   "$TMP_1024" --out "$ICONSET/icon_32x32@2x.png"      >/dev/null 2>&1
sips -z 128 128 "$TMP_1024" --out "$ICONSET/icon_128x128.png"      >/dev/null 2>&1
sips -z 256 256 "$TMP_1024" --out "$ICONSET/icon_128x128@2x.png"    >/dev/null 2>&1
sips -z 256 256 "$TMP_1024" --out "$ICONSET/icon_256x256.png"      >/dev/null 2>&1
sips -z 512 512 "$TMP_1024" --out "$ICONSET/icon_256x256@2x.png"    >/dev/null 2>&1
sips -z 512 512 "$TMP_1024" --out "$ICONSET/icon_512x512.png"      >/dev/null 2>&1
cp "$TMP_1024" "$ICONSET/icon_512x512@2x.png"

echo "==> 打包 .icns…"
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns

rm -rf "$ICONSET" "$TMP_1024" "$(dirname "$TMP_1024")/$(basename "$SVG").png"
echo "==> 完成: Resources/AppIcon.icns"
