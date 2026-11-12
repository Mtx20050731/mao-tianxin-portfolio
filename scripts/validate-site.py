#!/usr/bin/env python3
"""Validate the static entry point and its locally referenced resources."""
import json
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
page = root / "index.html"
html = page.read_text(encoding="utf-8")
refs = set(re.findall(r"assets/[A-Za-z0-9_./-]+\.[A-Za-z0-9]+", html))
missing = sorted(key for key in refs if not (root / key).is_file())
if missing:
    raise SystemExit("Missing referenced assets: " + ", ".join(missing))
# Check catalogue data too, including the images used by the original-image viewer.
marker = "var categories="
start = html.index(marker) + len(marker)
categories, _ = json.JSONDecoder().raw_decode(html[start:])
def check(node):
    if isinstance(node, dict):
        source = node.get("src", "")
        if source.startswith("assets/projects/") and source.endswith(".webp"):
            raise SystemExit("Project original replaced by preview: " + source)
        for value in node.values():
            check(value)
    elif isinstance(node, list):
        for value in node:
            check(value)
check(categories)
if page.stat().st_size >= 2_000_000:
    raise SystemExit("index.html exceeds 2MB; run scripts/optimize-site.sh")
print(f"Validated {len(refs)} asset references")
