#!/usr/bin/env python3
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent / "build" / "web"
out = Path(__file__).resolve().parent.parent / "build" / "InjectionTycoonMVP-web.zip"
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for p in root.rglob("*"):
        if p.is_file():
            z.write(p, p.relative_to(root.parent))
print(out, out.stat().st_size)
for name in ["index.html", "index.wasm", "index.pck", "index.js"]:
    f = root / name
    print(f"{name}: {f.stat().st_size}")
