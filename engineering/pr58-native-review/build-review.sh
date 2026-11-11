#!/bin/bash
set -eu
source_dir="$(cd "$(dirname "$0")" && pwd)"
review_dir="${1:?Specify an empty output directory for the native UI review}"
preview_app="$review_dir/Riftlet 界面预览.app"
if test -e "$preview_app"; then echo "Choose a fresh output directory." >&2; exit 1; fi
mkdir -p "$preview_app/Contents/MacOS" "$preview_app/Contents/Resources"
cp "$source_dir/../../Resources/Riftlet.icns" "$preview_app/Contents/Resources/AppIcon.icns"
for asset in riftlet.svg glass-study.png reading.svg error.svg; do
    cp "$source_dir/../../website-assets/$asset" "$preview_app/Contents/Resources/$asset"
done
cat > "$preview_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.riftlet.designreview.threeforms</string>
<key>CFBundleExecutable</key><string>Review</string><key>CFBundleName</key><string>Riftlet 界面预览</string>
<key>CFBundlePackageType</key><string>APPL</string><key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSPrincipalClass</key><string>NSApplication</string><key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleShortVersionString</key><string>1.0</string><key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
xcrun swiftc -parse-as-library -swift-version 5 -O "$source_dir/"*.swift -o "$preview_app/Contents/MacOS/Review"
/usr/bin/codesign --force --sign - "$preview_app"
/usr/bin/codesign --verify --strict "$preview_app"
