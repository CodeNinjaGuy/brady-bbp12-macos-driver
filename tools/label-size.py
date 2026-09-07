#!/usr/bin/env python3
#
# Brady BBP12 macOS driver
# Copyright (c) 2026 SeeBubble Media FlexCo - Martin Bundschuh
# MIT License - https://github.com/CodeNinjaGuy/brady-bbp12-macos-driver
#
"""Etikettengroessen im PPD verwalten.

    label-size.py list
    label-size.py add <breite_mm> <hoehe_mm>
    label-size.py remove <name>
    label-size.py default <name>

Ohne --ppd wird das installierte PPD bearbeitet.  Aendern erfordert root.
"""
import argparse
import os
import re
import subprocess
import sys

INSTALLED_PPD = "/Library/Printers/PPDs/Contents/Resources/BradyBBP12.ppd"
MM = 72.0 / 25.4

BLOCKS = ("PageSize", "PageRegion", "ImageableArea", "PaperDimension")


def body(kind, name, wpt, hpt):
    if kind in ("PageSize", "PageRegion"):
        return f'"<</PageSize[{wpt} {hpt}]/ImagingBBox null>>setpagedevice"'
    if kind == "ImageableArea":
        return f'"0 0 {wpt} {hpt}"'
    return f'"{wpt} {hpt}"'


def entries(text):
    """Vorhandene Groessen als {name: (label, wpt, hpt)}."""
    found = {}
    for m in re.finditer(r'^\*PaperDimension (\S+)/([^:]*): "(\d+) (\d+)"', text, re.M):
        found[m.group(1)] = (m.group(2), int(m.group(3)), int(m.group(4)))
    return found


def cmd_list(text):
    found = entries(text)
    if not found:
        print("(keine)")
        return
    m = re.search(r"^\*DefaultPageSize: (\S+)", text, re.M)
    default = m.group(1) if m else ""
    for name, (label, wpt, hpt) in sorted(found.items(), key=lambda kv: kv[1][1]):
        flag = "*" if name == default else ""
        print(f"{name}\t{label}\t{wpt}x{hpt}pt\t{wpt/MM:.1f} x {hpt/MM:.1f} mm\t{flag}")


def cmd_add(text, wmm, hmm):
    wpt, hpt = round(wmm * MM), round(hmm * MM)
    if wpt < 12 or hpt < 12:
        sys.exit("Fehler: Etikett zu klein (mindestens 4 x 4 mm).")
    name = f"w{wpt}h{hpt}"
    if name in entries(text):
        sys.exit(f"Fehler: Groesse {name} ({wmm:g} x {hmm:g} mm) ist bereits vorhanden.")
    label = f"{wmm:g} x {hmm:g} mm"

    lines = text.split("\n")
    for kind in BLOCKS:
        pat = re.compile(rf"^\*{kind} \S+/")
        last = max(i for i, l in enumerate(lines) if pat.match(l))
        lines.insert(last + 1, f"*{kind} {name}/{label}: {body(kind, name, wpt, hpt)}")
    print(f"Hinzugefuegt: {name}  ({label})", file=sys.stderr)
    return "\n".join(lines), name


def set_default(text, name):
    for key in BLOCKS:
        text = re.sub(rf"^\*Default{key}: .*$", f"*Default{key}: {name}", text, flags=re.M)
    return text


def cmd_default(text, name):
    if name not in entries(text):
        sys.exit(f"Fehler: Groesse {name} gibt es nicht.")
    print(f"Standardformat ist jetzt {name}", file=sys.stderr)
    return set_default(text, name), name


def cmd_remove(text, name):
    found = entries(text)
    if name not in found:
        sys.exit(f"Fehler: Groesse {name} gibt es nicht.")
    if len(found) <= 1:
        sys.exit("Fehler: Die letzte Etikettengroesse laesst sich nicht entfernen.")

    default = re.search(r"^\*DefaultPageSize: (\S+)", text, re.M).group(1)
    lines = [l for l in text.split("\n")
             if not any(l.startswith(f"*{k} {name}/") for k in BLOCKS)]
    text = "\n".join(lines)

    if default == name:                       # neuen Standard waehlen
        rest = sorted(k for k in found if k != name)[0]
        text = set_default(text, rest)
        print(f"Standardformat war {name}, jetzt {rest}", file=sys.stderr)
    print(f"Entfernt: {name}", file=sys.stderr)
    return text, name


def main():
    ap = argparse.ArgumentParser(description="Etikettengroessen im PPD verwalten")
    ap.add_argument("action", choices=("list", "add", "remove", "default"))
    ap.add_argument("args", nargs="*")
    ap.add_argument("--ppd", default=INSTALLED_PPD)
    ap.add_argument("--queue", default="Brady_BBP12")
    ap.add_argument("--no-apply", action="store_true",
                    help="PPD nur aendern, Warteschlange nicht aktualisieren")
    opt = ap.parse_args()

    if not os.path.exists(opt.ppd):
        sys.exit(f"Fehler: PPD nicht gefunden: {opt.ppd}")
    text = open(opt.ppd).read()

    if opt.action == "list":
        cmd_list(text)
        return

    if opt.action == "default":
        if len(opt.args) != 1:
            sys.exit("Aufruf: label-size.py default <name>")
        text, _ = cmd_default(text, opt.args[0])

    elif opt.action == "add":
        if len(opt.args) != 2:
            sys.exit("Aufruf: label-size.py add <breite_mm> <hoehe_mm>")
        text, _ = cmd_add(text, float(opt.args[0].replace(",", ".")),
                                float(opt.args[1].replace(",", ".")))
    else:
        if len(opt.args) != 1:
            sys.exit("Aufruf: label-size.py remove <name>")
        text, _ = cmd_remove(text, opt.args[0])

    try:
        open(opt.ppd, "w").write(text)
    except PermissionError:
        sys.exit(f"Fehler: keine Schreibrechte auf {opt.ppd} -- mit sudo ausfuehren.")

    if not opt.no_apply:
        r = subprocess.run(["lpadmin", "-p", opt.queue, "-P", opt.ppd],
                           capture_output=True, text=True)
        if r.returncode:
            sys.exit(f"lpadmin fehlgeschlagen: {r.stderr.strip()}")
        print(f"Warteschlange {opt.queue} aktualisiert", file=sys.stderr)


if __name__ == "__main__":
    main()
