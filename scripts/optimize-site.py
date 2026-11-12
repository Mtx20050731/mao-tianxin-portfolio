#!/usr/bin/env python3
"""Extract embedded images without changing their bytes and add missing previews."""
import base64
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import sys

from PIL import Image, ImageOps

root = Path(__file__).resolve().parent.parent
page = root / "index.html"
html = page.read_text(encoding="utf-8")
originals = {p: hashlib.sha256(p.read_bytes()).hexdigest()
             for p in (root / "assets").rglob("*")
             if p.suffix.lower() in {".png", ".jpg", ".jpeg"}}

def extract_image(match):
    data = base64.b64decode(match[2], validate=True)
    suffix = "jpg" if match[1] == "jpeg" else "png"
    key = f"assets/inline/{hashlib.sha256(data).hexdigest()}.{suffix}"
    target = root / key
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.read_bytes() != data:
        raise RuntimeError(f"Existing image collision: {key}")
    target.write_bytes(data)
    return key

html = re.sub(r"data:image/(png|jpeg);base64,([A-Za-z0-9+/=]+)", extract_image, html)
marker = "var previewSets="
start = html.index(marker) + len(marker)
previews, used = json.JSONDecoder().raw_decode(html[start:])
references = set(re.findall(r"assets/[A-Za-z0-9_./-]+\.(?:png|jpg|jpeg)", html))
# Windows authors must emit POSIX URL separators as well.
references = {key.replace("\\", "/") for key in references}
for key in sorted(references):
    target = root / key
    if key in previews or not target.is_file() or target.stat().st_size <= 300 * 1024:
        continue
    if "qr-" in key or "/resume/" in key:
        continue
    with Image.open(target) as image:
        image = ImageOps.exif_transpose(image)
        image = image.convert("RGBA" if "A" in image.getbands() else "RGB")
        variants = []
        for width in sorted({min(image.width, 640), min(image.width, 1440)}):
            height = max(1, round(image.height * width / image.width))
            resized = image.resize((width, height), Image.Resampling.LANCZOS)
            output = io.BytesIO()
            options = {"icc_profile": image.info["icc_profile"]} if image.info.get("icc_profile") else {}
            resized.save(output, "WEBP", quality=92, method=4, **options)
            data = output.getvalue()
            preview_key = f"assets/previews/{hashlib.sha256(data).hexdigest()}.webp"
            preview_path = root / preview_key
            preview_path.parent.mkdir(parents=True, exist_ok=True)
            preview_path.write_bytes(data)
            variants.append(f"{preview_key} {width}w")
        previews[key] = ", ".join(variants)

html = html[:start] + json.dumps(previews, separators=(",", ":")) + html[start + used:]
def static_preview(match):
    tag = match[0]
    source = re.search(r'\bsrc="([^"]+)"', tag)
    if not source or "srcset=" in tag or source[1] not in previews:
        return tag
    return tag.replace(" src=", f' sizes="80vw" srcset="{previews[source[1]]}" src=', 1)
html = re.sub(r"<img\b[^>]*>", static_preview, html)
for path, digest in originals.items():
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise RuntimeError(f"Original changed: {path}")
temporary = page.with_suffix(".html.tmp")
temporary.write_text(html, encoding="utf-8", newline="")
temporary.replace(page)
subprocess.run([sys.executable, str(root / "scripts/validate-site.py"), str(root)], check=True)
print(f"Originals retained: {len(originals)}; previews configured: {len(previews)}")
