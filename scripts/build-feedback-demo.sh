#!/bin/bash
set -euo pipefail
swift build -c release --product RiftletFeedbackDemo
bin="$(swift build -c release --show-bin-path)/RiftletFeedbackDemo"
mkdir -p build
stage="$(mktemp -d build/.feedback-demo.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
app="$stage/Riftlet Feedback Demo.app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/RiftletFeedbackDemo"
chmod 755 "$app/Contents/MacOS/RiftletFeedbackDemo"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.riftlet.feedback.offline-demo' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string Riftlet Feedback Demo' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string RiftletFeedbackDemo' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 0.1.0' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 13.0' "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" build/Riftlet-Feedback-Demo.zip
printf '%s\n' 'FEEDBACK_DEMO_BUILD_PASS; OFFLINE_SYNTHETIC; CLOUD_NOT_RUN; PHYSICAL_GUI_NOT_RUN; NOT_NOTARIZED'
