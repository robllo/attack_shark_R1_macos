#!/bin/sh
# Builds the r1 CLI and "R1 Config.app" with the Swift compiler from Xcode's command-line tools.
set -e
cd "$(dirname "$0")"

swiftc -O R1Protocol.swift main.swift -o r1
./r1 selftest

APP="R1 Config.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -parse-as-library R1Protocol.swift R1App.swift -o "$APP/Contents/MacOS/R1Config"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>R1Config</string>
  <key>CFBundleIdentifier</key><string>local.r1config</string>
  <key>CFBundleName</key><string>R1 Config</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
EOF

# Optional icon: drop a square icon.png (1024x1024 is best) next to this script.
if [ -f icon.png ]; then
  ICONSET=$(mktemp -d)/AppIcon.iconset
  mkdir -p "$ICONSET" "$APP/Contents/Resources"
  for size in 16 32 128 256 512; do
    sips -z $size $size icon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) icon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - "$APP"
echo "built ./r1 and ./$APP"

# Install so it opens from Spotlight, Launchpad and the Dock like any other app.
rm -rf "/Applications/$APP"
cp -R "$APP" /Applications/
touch "/Applications/$APP" # nudges Finder/Dock to pick up a changed icon
echo "installed /Applications/$APP"
