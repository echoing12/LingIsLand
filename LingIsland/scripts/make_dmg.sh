#!/bin/bash
# 把 LingIsland.app 打包成可拖拽安装的 DMG（内含 /Applications 快捷方式）
# 依赖：make_app.sh 产出的 dist/LingIsland.app + 系统自带 hdiutil / osascript
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="LingIsland"
VOL_NAME="灵岛"

# 清理历史遗留挂载（避免卷忙导致 attach/detach 卡住）
hdiutil detach "/Volumes/${VOL_NAME}" -force 2>/dev/null || true

APP_BUNDLE="dist/${APP_NAME}.app"
STAGING_DIR="dist/staging"
DMG_TMP="dist/${APP_NAME}-tmp.dmg"
DMG_FINAL="dist/${APP_NAME}.dmg"

# 1. 先构建并组装 .app
echo "==> 构建 .app…"
./scripts/make_app.sh
test -d "$APP_BUNDLE"

# 版本号从 Info.plist 读取，避免和 make_app.sh 里的硬编码漂移
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist")
DMG_TMP="dist/${APP_NAME}-${VERSION}-tmp.dmg"
DMG_FINAL="dist/${APP_NAME}-${VERSION}.dmg"

# 2. 组装暂存目录（.app + Applications 软链接）
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# 3. 创建可写 DMG（UDRW，之后排版完再压缩成只读）
rm -f "$DMG_TMP" "$DMG_FINAL"
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDRW \
    "$DMG_TMP"

# 4. 挂载，用 Finder 设置窗口布局（图标大小 / 位置），再卸载
MOUNT_POINT="/Volumes/${VOL_NAME}"
hdiutil attach "$DMG_TMP" -mountpoint "$MOUNT_POINT" -nobrowse

# CI（无 GUI / Finder 不可靠）时跳过排版，只做基础布局
if [ -z "${CI:-}" ]; then
    if ! osascript <<EOS
tell application "Finder"
    activate
    open (POSIX file "$MOUNT_POINT" as alias)
    delay 2
    tell window 1 of disk "$VOL_NAME"
        set current view to icon view
        set toolbar visible to false
        set statusbar visible to false
        set the bounds to {200, 120, 640, 400}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 120
        set position of item "$APP_NAME.app" of container window to {120, 150}
        set position of item "Applications" of container window to {420, 150}
    end tell
end tell
EOS
    then
        echo "!! Finder 布局未生效（无桌面会话?），跳过排版，仍会产出可用 DMG"
    fi

    osascript -e "tell application \"Finder\" to close window \"$VOL_NAME\"" 2>/dev/null || true
    sleep 2
fi
hdiutil detach "$MOUNT_POINT" -quiet

# 5. 压缩为只读 DMG（UDZO，zlib 最高压缩）
hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL"
rm -f "$DMG_TMP"
rm -rf "$STAGING_DIR"

echo "==> 完成: $DMG_FINAL"
