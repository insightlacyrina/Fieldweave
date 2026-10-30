#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"
mkdir -p .build/ModuleCache dist
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/ModuleCache"
swift build -c release --disable-sandbox --product FieldWeave
BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox)"
APP_DIR="$PROJECT_ROOT/dist/FieldWeave.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/FieldWeave" "$APP_DIR/Contents/MacOS/FieldWeave"
for resource in "$BIN_DIR"/*.bundle(N); do
  ditto "$resource" "$APP_DIR/Contents/Resources/${resource:t}"
done
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>FieldWeave</string>
<key>CFBundleDisplayName</key><string>FieldWeave</string>
<key>CFBundleExecutable</key><string>FieldWeave</string>
<key>CFBundleIdentifier</key><string>app.fieldweave.desktop</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>NSMicrophoneUsageDescription</key><string>FieldWeave captures the BlackHole virtual audio device to process system playback and send it to your selected headphones. It does not record the physical microphone.</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>FieldWeave</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.music</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSSupportsAutomaticGraphicsSwitching</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
swift scripts/make-icon.swift "$APP_DIR/Contents/Resources/FieldWeave.icns"
plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR"
echo "Built: $APP_DIR"
