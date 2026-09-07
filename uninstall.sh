#!/bin/bash
#
# Brady BBP12 macOS driver
# Copyright (c) 2026 SeeBubble Media FlexCo - Martin Bundschuh
# MIT License - https://github.com/CodeNinjaGuy/brady-bbp12-macos-driver
#
# Entfernt den Brady-BBP12-Treiber.  Aufruf:  sudo ./uninstall.sh [Queue-Name]
#
set -uo pipefail
QUEUE="${1:-Brady_BBP12}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Bitte mit sudo ausfuehren:  sudo $0" >&2
  exit 1
fi

lpadmin -x "$QUEUE" 2>/dev/null && echo "Warteschlange $QUEUE entfernt."
rm -f /Library/Printers/Brady/Filters/rastertobradybbp12
rmdir /Library/Printers/Brady/Filters /Library/Printers/Brady 2>/dev/null
rm -f /Library/Printers/PPDs/Contents/Resources/BradyBBP12.ppd
echo "Treiberdateien entfernt."
