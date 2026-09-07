#!/bin/bash
#
# Brady BBP12 macOS driver
# Copyright (c) 2026 SeeBubble Media FlexCo - Martin Bundschuh
# MIT License - https://github.com/CodeNinjaGuy/brady-bbp12-macos-driver
#
# Baut das Installationsprogramm BradyBBP12-<version>.pkg.
# Der Filter liegt fertig kompiliert darin -- auf dem Zielrechner wird kein
# Compiler und kein Xcode gebraucht.
#
set -euo pipefail
VERSION="${1:-1.0}"
ID="com.seebubble.bradybbp12"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/BradyBBP12-$VERSION.pkg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Filter kompilieren (universal)"
mkdir -p "$ROOT/build"
cc -arch arm64 -arch x86_64 -O2 -Wall -Wno-deprecated-declarations \
   -o "$ROOT/build/rastertobradybbp12" "$ROOT/src/rastertobradybbp12.c" -lcups

echo "==> Konfigurations-App bauen"
"$ROOT/gui/build.sh" >/dev/null

echo "==> Nutzlast zusammenstellen"
PAY="$STAGE/root"
install -d "$PAY/Library/Printers/Brady/Filters"
install -d "$PAY/Library/Printers/Brady/tools"
install -d "$PAY/Library/Printers/PPDs/Contents/Resources"
install -d "$PAY/Applications"

install -m 755 "$ROOT/build/rastertobradybbp12" "$PAY/Library/Printers/Brady/Filters/"
install -m 644 "$ROOT/ppd/BradyBBP12.ppd"       "$PAY/Library/Printers/PPDs/Contents/Resources/"
install -m 755 "$ROOT/tools/label-size.py"      "$PAY/Library/Printers/Brady/tools/"
install -m 755 "$ROOT/tools/set-offset.sh"      "$PAY/Library/Printers/Brady/tools/"
install -m 755 "$ROOT/tools/selftest.sh"        "$PAY/Library/Printers/Brady/tools/"
install -m 755 "$ROOT/uninstall.sh"             "$PAY/Library/Printers/Brady/tools/"
install -m 755 "$ROOT/test/make_calibration.py" "$PAY/Library/Printers/Brady/tools/"
install -m 644 "$ROOT/LICENSE"                  "$PAY/Library/Printers/Brady/"
cp -R "$ROOT/build/Brady BBP12 Konfiguration.app" "$PAY/Applications/"

# bbp12.conf ist bewusst NICHT in der Nutzlast: sie enthaelt die Kalibrierung
# des jeweiligen Geraets und darf bei einem Update nicht ueberschrieben werden.

echo "==> Komponentenpaket"
pkgbuild --root "$PAY" \
         --scripts "$ROOT/pkg/scripts" \
         --identifier "$ID" \
         --version "$VERSION" \
         --install-location / \
         "$STAGE/component.pkg" >/dev/null

echo "==> Installationsprogramm"
cat > "$STAGE/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Brady BBP12 Druckertreiber</title>
    <organization>com.seebubble</organization>
    <domains enable_localSystem="true" enable_anywhere="false" enable_currentUserHome="false"/>
    <options customize="never" require-scripts="true" hostArchitectures="arm64,x86_64"/>
    <welcome file="welcome.html" mime-type="text/html"/>
    <license file="license.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <choices-outline><line choice="default"/></choices-outline>
    <choice id="default" title="Brady BBP12 Druckertreiber">
        <pkg-ref id="$ID"/>
    </choice>
    <pkg-ref id="$ID" version="$VERSION" onConclusion="none">component.pkg</pkg-ref>
</installer-gui-script>
XML

productbuild --distribution "$STAGE/distribution.xml" \
             --resources "$ROOT/pkg/resources" \
             --package-path "$STAGE" \
             "$OUT" >/dev/null

echo
echo "Fertig: $OUT"
echo "Groesse: $(du -h "$OUT" | cut -f1)"
echo
echo "Hinweis: Das Paket ist nicht signiert. Beim ersten Oeffnen muss der Nutzer"
echo "         Rechtsklick -> Oeffnen verwenden (einmalig)."
