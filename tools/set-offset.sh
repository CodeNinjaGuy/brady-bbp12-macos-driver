#!/bin/bash
#
# Brady BBP12 macOS driver
# Copyright (c) 2026 SeeBubble Media FlexCo - Martin Bundschuh
# MIT License - https://github.com/CodeNinjaGuy/brady-bbp12-macos-driver
#
# Setzt den Druckversatz in Millimetern.  Aufruf:
#   sudo ./tools/set-offset.sh <rechts_mm> <runter_mm> [Queue]
#
# Schreibt die Werte nach /Library/Printers/Brady/bbp12.conf.  Der Filter liest
# sie bei jedem Job -- unabhaengig davon, aus welcher Anwendung gedruckt wird.
# (lpadmin taugt dafuer nicht: CUPS verwirft PPD-Defaults, die nicht in der
# Auswahlliste stehen, kommentarlos.)
#
set -euo pipefail
export LC_ALL=C          # sonst kollidiert das deutsche Dezimalkomma mit awk

XMM="${1:?rechts in mm angeben}"
YMM="${2:?runter in mm angeben}"
QUEUE="${3:-Brady_BBP12}"
CONF="/Library/Printers/Brady/bbp12.conf"

if [ "$(id -u)" -ne 0 ]; then
  echo "Bitte mit sudo ausfuehren:  sudo $0 $XMM $YMM" >&2
  exit 1
fi

DPI=300
PPD="/etc/cups/ppd/${QUEUE}.ppd"
if [ -r "$PPD" ]; then
  case "$(awk -F': *' '/^\*DefaultResolution:/{print $2}' "$PPD")" in
    203dpi) DPI=203 ;;
  esac
fi

dots() { awk -v mm="$1" -v dpi="$DPI" 'BEGIN{printf "%.0f", mm * dpi / 25.4}'; }
XD="$(dots "$XMM")"
YD="$(dots "$YMM")"

install -d -m 755 -o root -g wheel "$(dirname "$CONF")"
cat > "$CONF" <<CONFEOF
# Brady BBP12 - Kalibrierung des Druckursprungs
# Erzeugt von set-offset.sh am $(date '+%Y-%m-%d %H:%M')
# Werte in Druckpunkten bei ${DPI} dpi (1 mm = $(awk -v d=$DPI 'BEGIN{printf "%.3f", d/25.4}') Punkte)
BradyXOffset ${XD}
BradyYOffset ${YD}
CONFEOF
chmod 644 "$CONF"

awk -v dpi="$DPI" 'BEGIN{printf "Auflösung %d dpi -> 1 mm = %.3f Punkte\n", dpi, dpi/25.4}'
echo "Versatz: ${XMM} mm rechts = ${XD} Punkte, ${YMM} mm runter = ${YD} Punkte"
echo "Geschrieben nach $CONF"
