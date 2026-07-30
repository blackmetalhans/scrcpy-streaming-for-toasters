#!/usr/bin/env bash

# ==============================================================================
# publish_release.sh — Script de automatización de commit, push y release
# Repositorio: scrcpy-streaming-for-toasters
# ==============================================================================

set -euo pipefail

echo "=============================================================================="
echo "    AUTOMATIZACIÓN DE COMMIT, TAG Y PUSH EN GIT BASH"
echo "=============================================================================="

echo ""
echo "===> 1. Verificando estado del repositorio Git..."
git status

echo ""
echo "===> 2. Actualizando versión a v0.2.0..."
NEW_VERSION="0.2.0"
echo "${NEW_VERSION}" > VERSION

echo ""
echo "===> 3. Preparando archivos corregidos y estructura (git add)..."
git add scrcpy_bass_cam.bat
git add scrcpy_bass_cam_fallback_tcp.bat
git add README.md
git add informe_optimizacion.md
git add VERSION
git add CHANGELOG.md 2>/dev/null || true
git add .gitignore 2>/dev/null || true

if [ -d "archive" ]; then
    git add archive/
fi

echo ""
echo "===> 4. Creando commit con mensajes de parches detallados..."
COMMIT_MSG="fix(script): repair ADB device loop syntax, enable phone mic audio, and remove stay-awake conflict

- Fix 'usebackq' single-quote syntax bug in CMD for/f loop parsing ADB device output
- Restore '--camera-facing=front' for reliable HAL camera selection on Moto G06
- Enable '--audio-source=mic' and remove '--no-audio' to route phone mic into OBS
- Remove '--stay-awake' to eliminate conflict with '--no-control' in scrcpy 4.1
- Update VERSION to 0.2.0"

git commit -m "${COMMIT_MSG}"

echo ""
echo "===> 5. Creando etiqueta de Release v${NEW_VERSION}..."
TAG_NAME="v${NEW_VERSION}"
if git rev-parse "${TAG_NAME}" >/dev/null 2>&1; then
    echo "[AVISO] La etiqueta ${TAG_NAME} ya existe. Reemplazando..."
    git tag -d "${TAG_NAME}"
fi
git tag -a "${TAG_NAME}" -m "Release ${TAG_NAME}: Corrección de scrcpy_bass_cam.bat (Cámara frontal + Micrófono)"

echo ""
echo "===> 6. Enviando cambios y etiquetas a GitHub..."
BRANCH=$(git branch --show-current)
if [ -z "${BRANCH}" ]; then
    BRANCH="main"
fi

git push origin "${BRANCH}"
git push origin "${TAG_NAME}"

echo ""
echo "=============================================================================="
echo " ¡ÉXITO! Cambios y Release v${NEW_VERSION} enviados a GitHub en la rama '${BRANCH}'."
echo "=============================================================================="

