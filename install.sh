#!/bin/bash
#
# Brady BBP12 macOS driver
# Copyright (c) 2026 SeeBubble Media FlexCo - Martin Bundschuh
# MIT License - https://github.com/CodeNinjaGuy/brady-bbp12-macos-driver
#
# Installiert den Brady-BBP12-Treiber (CUPS-Filter + PPD) und richtet die
# Druckwarteschlange ein.  Aufruf:  sudo ./install.sh
#
set -euo pipefail

QUEUE="${1:-Brady_BBP12}"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
FILTER_DIR="/Library/Printers/Brady/Filters"
PPD_DIR="/Library/Printers/PPDs/Contents/Resources"

if [ "$(id -u)" -ne 0 ]; then
  echo "Bitte mit sudo ausfuehren:  sudo $0" >&2
  exit 1
fi

echo "==> Filter kompilieren"
cc -arch arm64 -arch x86_64 -O2 -Wall -Wno-deprecated-declarations \
   -o "$SRC_DIR/build/rastertobradybbp12" \
   "$SRC_DIR/src/rastertobradybbp12.c" -lcups

echo "==> Filter installieren nach $FILTER_DIR"
install -d -m 755 -o root -g wheel "$FILTER_DIR"
install -m 755 -o root -g wheel "$SRC_DIR/build/rastertobradybbp12" "$FILTER_DIR/rastertobradybbp12"

echo "==> PPD installieren nach $PPD_DIR"
install -d -m 755 -o root -g wheel "$PPD_DIR"
install -m 644 -o root -g wheel "$SRC_DIR/ppd/BradyBBP12.ppd" "$PPD_DIR/BradyBBP12.ppd"

echo "==> USB-Geraet suchen"
DEVICE="$(lpinfo -v 2>/dev/null | awk '/usb:\/\/.*BBP12/ {print $2; exit}')"
if [ -z "$DEVICE" ]; then
  DEVICE="$(lpinfo -v 2>/dev/null | awk '/BBP12/ {print $2; exit}')"
fi
if [ -z "$DEVICE" ]; then
  echo "Kein BBP12 gefunden. Drucker einschalten und USB pruefen." >&2
  exit 1
fi
echo "    $DEVICE"

echo "==> Warteschlange \"$QUEUE\" einrichten"
lpadmin -p "$QUEUE" -E -v "$DEVICE" -P "$PPD_DIR/BradyBBP12.ppd" \
        -D "Brady BBP12 (TSPL)" -L "" -o printer-is-shared=false
cupsenable "$QUEUE"
cupsaccept "$QUEUE"

echo
echo "Fertig. Warteschlange: $QUEUE"
lpstat -p "$QUEUE"
