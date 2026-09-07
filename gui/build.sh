#!/bin/bash
#
# Brady BBP12 macOS driver
# Copyright (c) 2026 SeeBubble Media FlexCo - Martin Bundschuh
# MIT License - https://github.com/CodeNinjaGuy/brady-bbp12-macos-driver
#
# Baut "Brady BBP12 Konfiguration.app".  Aufruf:  ./gui/build.sh
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Brady BBP12 Konfiguration.app"
NAME="BradyBBP12Config"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Kompilieren"
swiftc -O -parse-as-library \
       -target arm64-apple-macos13.0 \
       -o "$APP/Contents/MacOS/$NAME" \
       "$ROOT/gui/BradyBBP12Config.swift"

echo "==> Werkzeuge und Vorlagen einbetten"
cp "$ROOT/tools/label-size.py"      "$APP/Contents/Resources/"
cp "$ROOT/test/make_calibration.py" "$APP/Contents/Resources/"
cp "$ROOT/test/make_testlabel.py"   "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Brady BBP12 Konfiguration</string>
    <key>CFBundleDisplayName</key>       <string>Brady BBP12 Konfiguration</string>
    <key>CFBundleIdentifier</key>        <string>com.seebubble.bradybbp12.config</string>
    <key>CFBundleExecutable</key>        <string>$NAME</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>NSHumanReadableCopyright</key>  <string>Copyright (c) 2026 SeeBubble Media FlexCo - Martin Bundschuh</string>
    <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo
echo "Fertig: $APP"
echo "Starten mit:  open \"$APP\""
