#!/bin/sh
# Builds VietIME.app without Xcode: release build + hand-made bundle + code signature.
set -e
cd "$(dirname "$0")"

swift build -c release
APP=build/VietIME.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/VietIME "$APP/Contents/MacOS/VietIME"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.local.vietime</string>
    <key>CFBundleName</key><string>VietIME</string>
    <key>CFBundleExecutable</key><string>VietIME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

KEYCHAIN="$HOME/Library/Keychains/vietime-dev.keychain-db"
if [ -f "$KEYCHAIN" ]; then
    security unlock-keychain -p vietime-dev "$KEYCHAIN"
    codesign --force --sign "VietIME Dev" "$APP"
else
    echo "warning: ad-hoc signing; run ./setup-signing.sh once so Accessibility permission survives rebuilds"
    codesign --force --sign - "$APP"
fi
echo "Built $APP"
