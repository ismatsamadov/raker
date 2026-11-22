#!/usr/bin/env bash
# Builds the SwiftUI shell, wraps it in an app bundle and opens it.
# Temporary: the Xcode project replaces this once full Xcode is installed.
#
#   CONFIG=release     build optimized (default: debug)
#   SIGN_IDENTITY=...  sign with a stable identity so privacy grants survive rebuilds
#   NO_LAUNCH=1        build the bundle without opening it
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
config="${CONFIG:-debug}"
app="$root/build/Raker.app"

cd "$root/Packages/RakerKit"
swift build -c "$config" --product RakerDevApp
bin_dir="$(swift build -c "$config" --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/RakerDevApp" "$app/Contents/MacOS/Raker"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>app.raker.dev</string>
    <key>CFBundleName</key>
    <string>Raker</string>
    <key>CFBundleDisplayName</key>
    <string>Raker</string>
    <key>CFBundleExecutable</key>
    <string>Raker</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Raker looks for large and old files in Downloads.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Raker looks for large and old files on your Desktop.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Raker looks for large and old files in Documents.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>Raker shows what uses space on external drives you choose.</string>
    <key>NSNetworkVolumesUsageDescription</key>
    <string>Raker shows what uses space on network volumes you choose.</string>
</dict>
</plist>
PLIST

# Ad-hoc by default. Privacy grants are tied to the signature, so with ad-hoc signing
# macOS asks again after every rebuild.
codesign --force --sign "${SIGN_IDENTITY:--}" "$app"
echo "Built $app"

if [[ "${NO_LAUNCH:-0}" != "1" ]]; then
    open "$app"
fi
