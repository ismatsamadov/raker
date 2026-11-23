#!/usr/bin/env bash
# Builds the SwiftUI shell, wraps it in an app bundle and opens it.
# Temporary: the Xcode project replaces this once full Xcode is installed.
#
#   CONFIG=release     build optimized (default: debug)
#   SIGN_IDENTITY=...  sign with this identity (default: the one Scripts/setup-dev-signing.sh
#                      creates, else ad hoc)
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
cp "Sources/RakerDevApp/Resources/Raker.icns" "$app/Contents/Resources/Raker.icns"
# Resource bundles, such as the baseline rule pack.
for bundle in "$bin_dir"/*.bundle; do
    # The runner's icon already has its required location in the main bundle.
    [[ "$(basename "$bundle")" == "RakerKit_RakerDevApp.bundle" ]] && continue
    [[ -e "$bundle" ]] && cp -R "$bundle" "$app/Contents/Resources/"
done

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
    <key>CFBundleIconFile</key>
    <string>Raker.icns</string>
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

# Privacy answers, such as access to Downloads, are tied to the signature. An ad-hoc
# signature is new on every build, so macOS would ask again after each rebuild.
signing="${RAKER_SIGNING_DIR:-$HOME/Library/Developer/Raker}"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" "$app"
elif [[ -f "$signing/signing.keychain-db" && -f "$signing/password" ]]; then
    security unlock-keychain -p "$(cat "$signing/password")" "$signing/signing.keychain-db"
    codesign --force --sign "Raker Development" --keychain "$signing/signing.keychain-db" "$app"
else
    echo "warning: signing ad hoc, so macOS asks for folder access again after every build." >&2
    echo "         Run Scripts/setup-dev-signing.sh once to keep the answers." >&2
    codesign --force --sign - "$app"
fi
echo "Built $app"

if [[ "${NO_LAUNCH:-0}" != "1" ]]; then
    open "$app"
fi
