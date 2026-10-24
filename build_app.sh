#!/bin/bash
# FluxStudio 原生 macOS App 建置腳本 (安全隔離編譯快取於 /tmp，避免 iCloud 雲端同步衝突)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRATCH_DIR="/tmp/FluxStudio-build"
APP_NAME="FluxStudio"
APP_DEST="/Applications/${APP_NAME}.app"

echo "🔨 [1/4] 開始編譯 Swift 專案 (Release 模式)..."
mkdir -p "$SCRATCH_DIR"
cd "$DIR"

swift build --scratch-path "$SCRATCH_DIR" -c release

BIN_PATH="$SCRATCH_DIR/release/$APP_NAME"
if [ ! -f "$BIN_PATH" ]; then
    echo "❌ 找不到編譯產出之二進位檔：$BIN_PATH"
    exit 1
fi

echo "📦 [2/4] 建立 App Bundle 架構..."
STAGE="$(mktemp -d)/${APP_NAME}.app"
mkdir -p "$STAGE/Contents/MacOS"
mkdir -p "$STAGE/Contents/Resources"

cp "$BIN_PATH" "$STAGE/Contents/MacOS/$APP_NAME"
chmod +x "$STAGE/Contents/MacOS/$APP_NAME"

echo "📝 [3/4] 寫入 Info.plist..."
cat << 'PLIST' > "$STAGE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_TW</string>
    <key>CFBundleExecutable</key>
    <string>FluxStudio</string>
    <key>CFBundleIdentifier</key>
    <string>com.fluxstudio.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>FluxStudio</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

echo "🚀 [4/4] 安裝至 $APP_DEST..."
rm -rf "$APP_DEST"
cp -R "$STAGE" "$APP_DEST"
xattr -cr "$APP_DEST" 2>/dev/null || true
touch "$APP_DEST"

echo "=========================================================="
echo "🎉 建置成功！已安裝至：$APP_DEST"
echo "您可以直接從 Spotlight 或 Finder 開啟 FluxStudio。"
echo "=========================================================="
