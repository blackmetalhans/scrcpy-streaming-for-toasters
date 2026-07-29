#!/usr/bin/env bash
set -e

# get_scrcpy_release.sh
# Downloads the latest scrcpy release asset (Windows .zip when available) and extracts to ./bin
# Requires: curl, unzip or bsdtar, python3 (used for JSON parsing fallback)

REPO_API="https://api.github.com/repos/Genymobile/scrcpy/releases/latest"
OUTDIR="bin"
TMPZIP="/tmp/scrcpy_release.zip"

mkdir -p "$OUTDIR"

ASSET_URL=$(curl -s "$REPO_API" | python3 - <<'PY'
import sys, json
r=json.load(sys.stdin)
assets=r.get('assets',[])
# prefer windows zip
for a in assets:
    name=a.get('name','').lower()
    if 'win' in name and name.endswith('.zip'):
        print(a.get('browser_download_url'))
        sys.exit(0)
# fallback: first zip
for a in assets:
    if a.get('name','').endswith('.zip'):
        print(a.get('browser_download_url'))
        sys.exit(0)
print('')
PY
)

if [ -z "$ASSET_URL" ]; then
  echo "No suitable asset found in scrcpy release. Open the releases page: https://github.com/Genymobile/scrcpy/releases"
  exit 2
fi

echo "Downloading $ASSET_URL..."
curl -L -o "$TMPZIP" "$ASSET_URL"

if command -v unzip >/dev/null 2>&1; then
  unzip -o "$TMPZIP" -d "$OUTDIR"
elif command -v bsdtar >/dev/null 2>&1; then
  bsdtar -xvf "$TMPZIP" -C "$OUTDIR"
else
  echo "No unzip tool found. Please extract $TMPZIP into $OUTDIR manually."
  exit 3
fi

echo "Extracted into $OUTDIR"
rm -f "$TMPZIP"
