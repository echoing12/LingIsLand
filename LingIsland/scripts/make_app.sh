#!/bin/bash
# 把 SPM 构建产物组装成 LingIsland.app
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="LingIsland"
VERSION="0.1.0"
BUILD_DIR=".build/release"
APP_BUNDLE="dist/${APP_NAME}.app"

echo "==> 构建 release…"
swift build -c release

echo "==> 组装 .app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/PrivateFrameworks"

# 主程序
cp "$BUILD_DIR/${APP_NAME}" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"

# 媒体适配器 perl 脚本：经 /usr/bin/perl 运行（bundle id com.apple.perl5 才可读 Now Playing）
cp "Resources/mediaremote.pl" "$APP_BUNDLE/Contents/Resources/mediaremote.pl"

# 应用图标（.icns 由 Resources/AppIcon.svg 生成）
cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# MediaRemoteAdapter.framework
cp -R "Resources/MediaRemoteAdapter.framework" "$APP_BUNDLE/Contents/PrivateFrameworks/"

# Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.lingisland.app</string>
    <key>CFBundleName</key>
    <string>灵岛</string>
    <key>CFBundleDisplayName</key>
    <string>灵岛</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# 签名（临时 ad-hoc）
codesign --force --sign - "$APP_BUNDLE"

echo "==> 完成: $APP_BUNDLE"
