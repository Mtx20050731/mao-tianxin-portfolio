#!/bin/bash
# Deploy one exact GitHub commit. Advance state only after successful validation.
set -euo pipefail

REPO_NAME="${REPO_NAME:-Mtx20050731/mao-tianxin-portfolio}"
SITE_DIR="${SITE_DIR:-/opt/www/host/mao-portfolio}"
STATE_DIR="${STATE_DIR:-$HOME/.sites}"
KEEP_RELEASES="${KEEP_RELEASES:-3}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-}"
RELEASES="$SITE_DIR/releases"
STATE="$STATE_DIR/.portfolio-sha"

mkdir -p "$STATE_DIR" "$RELEASES"
exec 9>"$STATE_DIR/.portfolio-deploy.lock"
flock -n 9 || exit 0
STAGE=$(mktemp -d "$STATE_DIR/staging-portfolio.XXXXXX")
trap 'rm -rf -- "$STAGE"' EXIT

# Fail before changing a live directory that has not been migrated to a symlink.
if [ -e "$SITE_DIR/webroot" ] && [ ! -L "$SITE_DIR/webroot" ]; then
  echo "webroot must be absent or a symlink to a release" >&2
  exit 1
fi

# Prefer GitHub itself; mirrors provide transport fallback for the same pinned SHA.
MIRRORS=("" "https://gh-proxy.com/" "https://ghproxy.net/" "https://ghfast.top/")
latest=""
for prefix in "${MIRRORS[@]}"; do
  candidate=$(timeout 45 git ls-remote "${prefix}https://github.com/$REPO_NAME.git" refs/heads/main 2>/dev/null | awk '{print $1}') || continue
  if [[ "$candidate" =~ ^[0-9a-f]{40}$ ]]; then latest="$candidate"; break; fi
done
[[ "$latest" =~ ^[0-9a-f]{40}$ ]] || { echo "Cannot resolve main" >&2; exit 1; }
current=$(cat "$STATE" 2>/dev/null || true)
if [ "$latest" = "$current" ] && [ "${1:-}" != "--force" ]; then exit 0; fi

downloaded=false
for prefix in "${MIRRORS[@]}"; do
  if curl -fsSL --retry 2 --retry-delay 2 --max-time 600     "${prefix}https://codeload.github.com/$REPO_NAME/tar.gz/$latest" -o "$STAGE/source.tar.gz"; then
    downloaded=true
    break
  fi
done
[ "$downloaded" = true ] || { echo "Download failed" >&2; exit 1; }
mkdir "$STAGE/tree"

# Check archive identity, paths and links before extraction.
python3 - "$STAGE/source.tar.gz" "$latest" <<'PY'
import pathlib, sys, tarfile
archive, sha = sys.argv[1:]
with tarfile.open(archive, "r:gz") as source:
    entries = source.getmembers()
    if not entries:
        raise SystemExit("Empty archive")
    for item in entries:
        path = pathlib.PurePosixPath(item.name)
        if path.is_absolute() or ".." in path.parts or not path.parts[0].endswith("-" + sha):
            raise SystemExit("Archive path or commit mismatch")
        if not (item.isfile() or item.isdir()):
            raise SystemExit("Archive links and special files are not supported")
PY
tar -xzf "$STAGE/source.tar.gz" --strip-components=1 -C "$STAGE/tree"
python3 "$STAGE/tree/scripts/validate-site.py" "$STAGE/tree"

# Never transform source assets during deployment.
release="$RELEASES/$latest"
if [ -e "$release" ]; then
  # A failed attempt can already have this release; verify it before reuse.
  diff -qr "$STAGE/tree" "$release" >/dev/null
else
  mv "$STAGE/tree" "$release"
fi
previous=$(readlink "$SITE_DIR/webroot" 2>/dev/null || true)
ln -sfn "releases/$latest" "$SITE_DIR/webroot.new"
mv -Tf "$SITE_DIR/webroot.new" "$SITE_DIR/webroot"

if [ -n "$HEALTHCHECK_URL" ]; then
  if ! curl -fsS --retry 2 --max-time 20 "$HEALTHCHECK_URL" -o /dev/null; then
    if [ -n "$previous" ]; then
      ln -sfn "$previous" "$SITE_DIR/webroot.new"
      mv -Tf "$SITE_DIR/webroot.new" "$SITE_DIR/webroot"
    else
      rm -- "$SITE_DIR/webroot"
    fi
    echo "Health check failed; previous release restored, state unchanged" >&2
    exit 1
  fi
fi
printf '%s\n' "$latest" > "$STATE.tmp"
mv -f "$STATE.tmp" "$STATE"

python3 - "$RELEASES" "$KEEP_RELEASES" "$latest" "$previous" <<'PY'
from pathlib import Path
import shutil, sys
root = Path(sys.argv[1]).resolve()
keep_count = max(2, int(sys.argv[2]))
protected = {sys.argv[3], Path(sys.argv[4]).name}
releases = sorted((p for p in root.iterdir() if p.is_dir() and not p.is_symlink()),
                  key=lambda p: p.stat().st_mtime, reverse=True)
keep = protected | {p.name for p in releases[:keep_count]}
for release in releases:
    if release.name not in keep:
        shutil.rmtree(release)
PY
echo "Deployed $latest"
