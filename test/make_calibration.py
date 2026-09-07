#!/usr/bin/env python3
#
# Brady BBP12 macOS driver
# Copyright (c) 2026 SeeBubble Media FlexCo - Martin Bundschuh
# MIT License - https://github.com/CodeNinjaGuy/brady-bbp12-macos-driver
#
"""Erzeugt ein Kalibrier-Etikett mit Rahmen und mm-Skala.

    make_calibration.py [breite_mm] [hoehe_mm] [ausgabe.pdf]

Der Rahmen liegt genau auf der Etikettenkante, die Skala beginnt bei 0.
Was fehlt, laesst sich damit direkt in Millimetern ablesen -> daraus ergibt
sich der Druckversatz.
"""
import sys

MM = 72.0 / 25.4


def build(wmm, hmm):
    W, H = round(wmm * MM), round(hmm * MM)
    p = ["q", "0 0 0 rg", "0 G", "0.8 w"]
    p.append(f"0.4 0.4 {W-0.8:.2f} {H-0.8:.2f} re S")

    c = min(6.0, W / 6, H / 6)
    for cx, cy, dx, dy in ((0, 0, 1, 1), (W, 0, -1, 1), (0, H, 1, -1), (W, H, -1, -1)):
        p.append(f"{cx+dx*1.5:.2f} {cy+dy*1.5:.2f} m {cx+dx*(1.5+c):.2f} {cy+dy*1.5:.2f} l S")
        p.append(f"{cx+dx*1.5:.2f} {cy+dy*1.5:.2f} m {cx+dx*1.5:.2f} {cy+dy*(1.5+c):.2f} l S")

    step = 5 if wmm <= 120 else 10
    for mm in range(0, int(wmm) + 1, step):
        x = min(max(mm * MM, 0.4), W - 0.4)
        p.append(f"{x:.2f} 1 m {x:.2f} 7 l S")
        p.append(f"BT /F1 4.5 Tf {x+1:.2f} 8.5 Td ({mm}) Tj ET")
    for mm in range(0, int(hmm) + 1, step):
        y = min(max(mm * MM, 0.4), H - 0.4)
        p.append(f"1 {y:.2f} m 7 {y:.2f} l S")

    p.append(f"{W/2:.2f} {H/2-5:.2f} m {W/2:.2f} {H/2+5:.2f} l S")
    p.append(f"{W/2-5:.2f} {H/2:.2f} m {W/2+5:.2f} {H/2:.2f} l S")

    if H >= 34:
        p.append(f"BT /F1 6 Tf 20 {H/2+2:.2f} Td (KALIBRIERUNG {wmm:g} x {hmm:g} mm) Tj ET")
        p.append(f"BT /F1 5 Tf 20 {H/2-6:.2f} Td (Rahmen muss rundum sichtbar sein) Tj ET")
    p.append("Q")
    return W, H, "\n".join(p)


def write_pdf(path, W, H, content):
    objs = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {W} {H}] "
        f"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        f"<< /Length {len(content)} >>\nstream\n{content}\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out, offsets = "%PDF-1.4\n", []
    for i, o in enumerate(objs, 1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n{o}\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objs)+1}\n0000000000 65535 f \n"
    for o in offsets:
        out += f"{o:010d} 00000 n \n"
    out += f"trailer\n<< /Size {len(objs)+1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n"
    with open(path, "wb") as fh:
        fh.write(out.encode("latin-1"))


if __name__ == "__main__":
    wmm = float(sys.argv[1].replace(",", ".")) if len(sys.argv) > 1 else 85.0
    hmm = float(sys.argv[2].replace(",", ".")) if len(sys.argv) > 2 else 20.0
    path = sys.argv[3] if len(sys.argv) > 3 else f"calibration_{wmm:g}x{hmm:g}.pdf"
    W, H, content = build(wmm, hmm)
    write_pdf(path, W, H, content)
    print(f"{path} erzeugt ({W} x {H} pt = {wmm:g} x {hmm:g} mm)")
