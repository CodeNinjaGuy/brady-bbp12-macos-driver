#!/usr/bin/env python3
"""Erzeugt ein 85 x 20 mm Testetikett (241 x 57 pt) als PDF."""
W, H = 241, 57   # 85 x 20 mm in PostScript-Punkten

content = f"""q
0 0 0 rg
2 2 {W-4} 1.5 re f
2 {H-3.5} {W-4} 1.5 re f
BT /F1 13 Tf 8 32 Td (BRADY BBP12) Tj ET
BT /F1 7.5 Tf 8 20 Td (Testetikett 85 x 20 mm - 203 dpi) Tj ET
BT /F1 6 Tf 8 10 Td (TSPL Treiber - ohne Wasserzeichen) Tj ET
{W-46} 8 12 12 re f
{W-30} 8 3 12 re f
{W-25} 8 6 12 re f
{W-17} 8 2 12 re f
{W-13} 8 8 12 re f
Q"""

objs = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {W} {H}] "
    f"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
    f"<< /Length {len(content)} >>\nstream\n{content}\nendstream",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>",
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

with open("testlabel_85x20.pdf", "wb") as f:
    f.write(out.encode("latin-1"))
print("testlabel_85x20.pdf erzeugt (85 x 20 mm)")
