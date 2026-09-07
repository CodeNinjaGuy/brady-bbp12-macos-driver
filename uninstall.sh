#!/bin/bash
#
# Brady BBP12 macOS driver
# Copyright (c) 2026 SeeBubble Media FlexCo - Martin Bundschuh
# MIT License - https://github.com/CodeNinjaGuy/brady-bbp12-macos-driver
#
# Entfernt den Treiber vollstaendig.  Aufruf:  sudo ./uninstall.sh [Queue-Name]
#
set -uo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Bitte mit sudo ausfuehren:  sudo $0" >&2
  exit 1
fi

# Alle Warteschlangen entfernen, die diesen Treiber benutzen
for f in /etc/cups/ppd/*.ppd; do
  [ -e "$f" ] || continue
  if grep -q "Brady BBP12 TSPL" "$f" 2>/dev/null; then
    q="$(basename "$f" .ppd)"
    lpadmin -x "$q" 2>/dev/null && echo "Warteschlange $q entfernt."
  fi
done
# Falls explizit ein Name angegeben wurde
[ $# -ge 1 ] && lpadmin -x "$1" 2>/dev/null && echo "Warteschlange $1 entfernt."

rm -f  /Library/Printers/PPDs/Contents/Resources/BradyBBP12.ppd
rm -rf "/Applications/Brady BBP12 Konfiguration.app"

if [ -f /Library/Printers/Brady/bbp12.conf ]; then
  echo "Hinweis: /Library/Printers/Brady/bbp12.conf enthaelt die Kalibrierung"
  echo "         dieses Geraets und wird mit entfernt."
fi
rm -rf /Library/Printers/Brady

pkgutil --forget com.seebubble.bradybbp12 >/dev/null 2>&1

echo "Treiber vollstaendig entfernt."
