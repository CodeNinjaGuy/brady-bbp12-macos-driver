#!/usr/bin/env python3
"""Erzeugt ein Kalibrier-Etikett 85 x 20 mm mit Rahmen und mm-Skala.

Was fehlt oder abgeschnitten ist, laesst sich damit direkt in Millimetern
ablesen -> daraus ergeben sich BradyXOffset / BradyYOffset.
"""
MM = 72.0 / 25.4          # Punkte je Millimeter
WMM, HMM = 85.0, 20.0
W, H = round(WMM * MM), round(HMM * MM)      # 241 x 57 pt

p = ["q", "0 0 0 rg", "0 G", "0.8 w"]

# Aussenrahmen genau auf der Etikettenkante
p.append(f"0.4 0.4 {W-0.8:.2f} {H-0.8:.2f} re S")

# Eckwinkel, damit ein Beschnitt sofort auffaellt
c = 6
for (cx, cy, dx, dy) in ((0,0,1,1), (W,0,-1,1), (0,H,1,-1), (W,H,-1,-1)):
    p.append(f"{cx+dx*1.5:.2f} {cy+dy*1.5:.2f} m {cx+dx*(1.5+c):.2f} {cy+dy*1.5:.2f} l S")
    p.append(f"{cx+dx*1.5:.2f} {cy+dy*1.5:.2f} m {cx+dx*1.5:.2f} {cy+dy*(1.5+c):.2f} l S")

# mm-Skala unten: Strich alle 5 mm, beschriftet
for mm in range(0, int(WMM) + 1, 5):
    x = mm * MM
    x = min(max(x, 0.4), W - 0.4)
    p.append(f"{x:.2f} 1 m {x:.2f} 7 l S")
    p.append(f"BT /F1 4.5 Tf {x + 1:.2f} 8.5 Td ({mm}) Tj ET")

# mm-Skala links: Strich alle 5 mm
for mm in range(0, int(HMM) + 1, 5):
    y = mm * MM
    y = min(max(y, 0.4), H - 0.4)
    p.append(f"1 {y:.2f} m 7 {y:.2f} l S")

# Mittenkreuz
p.append(f"{W/2:.2f} {H/2-5:.2f} m {W/2:.2f} {H/2+5:.2f} l S")
p.append(f"{W/2-5:.2f} {H/2:.2f} m {W/2+5:.2f} {H/2:.2f} l S")

p.append(f"BT /F1 6 Tf 20 {H/2+2:.2f} Td (KALIBRIERUNG 85 x 20 mm) Tj ET")
p.append(f"BT /F1 5 Tf 20 {H/2-6:.2f} Td (Rahmen muss rundum sichtbar sein) Tj ET")
p.append("Q")
content = "\n".join(p)

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
for off in offsets:
    out += f"{off:010d} 00000 n \n"
out += f"trailer\n<< /Size {len(objs)+1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n"

with open("calibration_85x20.pdf", "wb") as fh:
    fh.write(out.encode("latin-1"))
print(f"calibration_85x20.pdf erzeugt ({W} x {H} pt = 85 x 20 mm)")
