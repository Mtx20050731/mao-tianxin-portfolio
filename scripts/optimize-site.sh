#!/bin/bash
# Offline authoring step. Original image bytes are retained.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/optimize-site.py
