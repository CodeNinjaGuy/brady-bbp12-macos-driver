#!/bin/bash
#
# Brady BBP12 macOS driver
# Copyright (c) 2026 SeeBubble Media FlexCo - Martin Bundschuh
# MIT License - https://github.com/CodeNinjaGuy/brady-bbp12-macos-driver
#
# Laesst den BBP12 sein eigenes Konfigurationsetikett drucken.  Darauf stehen
# Modell, Aufloesung (dpi), Druckbreite und Sensoreinstellungen -- damit ist
# die Auflösung zweifelsfrei geklaert.  Verbraucht ein bis zwei Etiketten.
#
QUEUE="${1:-Brady_BBP12}"
TMP="$(mktemp -t bbp12selftest)"
printf 'SELFTEST\r\n' > "$TMP"
echo "Sende SELFTEST an Warteschlange \"$QUEUE\" ..."
lp -d "$QUEUE" -o raw "$TMP" && echo "Gesendet."
rm -f "$TMP"
