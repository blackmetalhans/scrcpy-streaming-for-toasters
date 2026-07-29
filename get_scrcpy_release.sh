#!/usr/bin/env bash
set -euo pipefail

REPO_API="https://api.github.com/repos/Genymobile/scrcpy/releases/latest"
OUTDIR="bin"
TMPZIP="/tmp/scrcpy_release.zip"

mkdir -p "$OUTDIR"

echo "Resolving latest scrcpy release asset..."
ASSET_URL=""
if command -v python3 >/dev/null 2>&1; then
  ASSET_URL=$(curl -s "$REPO_API" | python3 - <<'PY'
import sys,json
r=json.load(sys.stdin)
assets=r.get('assets',[])
for a in assets:
    name=a.get('name','').lower()
    if 'win' in name and name.endswith('.zip'):
        print(a.get('browser_download_url'))
        sys.exit(0)
for a in assets:
    if a.get('name','').endswith('.zip'):
        print(a.get('browser_download_url'))
        sys.exit(0)
print('')
PY
)
elif command -v jq >/dev/null 2>&1; then
  ASSET_URL=$(curl -s "$REPO_API" | jq -r '.assets[] | select(.name|test("(?i)win")) | select(.name|test("\\.zip$")) | .browser_download_url' | head -n1)
  if [ -z "$ASSET_URL" ]; then
    ASSET_URL=$(curl -s "$REPO_API" | jq -r '.assets[] | select(.name|test("\\.zip$")) | .browser_download_url' | head -n1)
  fi
else
  echo "Warning: neither python3 nor jq found; attempting naive grep fallback."
  ASSET_URL=$(curl -s "$REPO_API" | grep -o 'https://[^"]*\.zip' | head -n1)
fi

if [ -z "$ASSET_URL" ]; then
  echo "No suitable asset found. Visit https://github.com/Genymobile/scrcpy/releases"
  exit 2
fi

echo "Downloading $ASSET_URL ..."
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
