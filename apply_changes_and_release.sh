#!/usr/bin/env bash
set -euo pipefail

# apply_changes_and_release.sh
# Ejecutar desde la raíz del repo local (Git Bash)
# Requiere: git, curl, tar. gh y zip opcionales (gh para publicar release automáticamente).
# Asegúrate de tener git autenticado y gh auth login si quieres crear la release por CLI.

REPO_NWO="blackmetalhans/scrcpy-streaming-for-toasters"
TAG="v0.1.1"
NEW_VERSION="0.1.1"
BACKUP_BRANCH="backup/pre-change-$(date +%Y%m%d%H%M%S)"

# Check tools
for cmd in git curl tar; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: '$cmd' is required but not found in PATH." >&2
    exit 1
  fi
done

HAS_ZIP=0
if command -v zip >/dev/null 2>&1; then HAS_ZIP=1; fi

HAS_GH=0
if command -v gh >/dev/null 2>&1; then HAS_GH=1; fi

echo "Repo: $REPO_NWO"
echo "Tag to create: $TAG (VERSION -> $NEW_VERSION)"
echo "zip available: $HAS_ZIP"
echo "gh available: $HAS_GH"
echo

# Ensure we're inside the repo
if [ ! -d ".git" ]; then
  echo "This script must be run from the root of the git repository." >&2
  exit 1
fi

# Ensure on main and up-to-date
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "Current branch: $CURRENT_BRANCH"
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo "Switching to main..."
  git checkout main
fi

echo "Fetching origin..."
git fetch origin main
git pull origin main

# Ensure clean tree
if [ -n "$(git status --porcelain)" ]; then
  echo "Working tree not clean. Commit or stash changes before running this script." >&2
  git status --porcelain
  exit 1
fi

# Create backup branch
echo "Creating backup branch: $BACKUP_BRANCH"
git branch "$BACKUP_BRANCH"
git push -u origin "$BACKUP_BRANCH"

echo
echo "ABOUT TO MODIFY FILES LOCALLY:"
echo " - README.md"
echo " - scrcpy_bass_cam.bat"
echo " - get_scrcpy_release.sh"
echo " - get_scrcpy_release.ps1"
echo " - .gitattributes"
echo " - .gitignore"
echo " - archive/README.md"
echo " - .github/workflows/release.yml"
echo " - VERSION (set to $NEW_VERSION)"
echo " - CHANGELOG.md (prepend entry for $NEW_VERSION)"
echo
read -p "If you want to proceed and commit these changes to main, type YES: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
  echo "Aborting."
  exit 0
fi

# Ensure directories
mkdir -p archive
mkdir -p .github/workflows

# --- WRITE FILES ---
# README.md (updated)
cat > README.md <<'README_EOF'
# scrcpy-bass-cam

Pipeline de streaming de baja latencia: Moto G06 (Android 15, cámara frontal HAL) → scrcpy → OBS Studio. Diseñado para músicos y creadores que necesitan transmitir cámara frontal y audio en tiempo real con la mínima latencia posible.

**Descripción corta (campo de repositorio):** Streaming de baja latencia desde cámara frontal Android a OBS usando scrcpy — scripts y guía para sincronizar audio profesionalmente.

## ¿Para quién es esto?
- Músicos/streamers que quieren usar la cámara frontal de su teléfono como cámara de directo.
- Técnicos de sonido que sincronizan audio profesional vía Reaper + ASIO4ALL + ReaStream.
- Usuarios con PCs de gama baja que necesitan una ruta optimizada y parámetros por defecto adecuados.

## Aplicaciones prácticas
- Transmisión de ensayos o conciertos con un móvil como cámara PTZ económica.
- Streaming de tutoriales o lecciones donde se requiere baja latencia entre audio y vídeo.
- Integración de la cámara del teléfono en escenarios de producción con OBS, con control de bitrate y afinidad CPU para evitar contención.

---
## Estructura del repositorio (actualizada)
```
scrcpy-bass-cam/
├── README.md
├── LICENSE
├── .gitignore
├── .gitattributes
├── informe_optimizacion.md   # informe técnico y pruebas
├── scrcpy_bass_cam.bat       # script principal (USB / cámara via HAL)
├── scrcpy_bass_cam_fallback_tcp.bat # fallback: mirroring por TCP/RNDIS
├── get_scrcpy_release.ps1    # PowerShell helper para descargar scrcpy
├── get_scrcpy_release.sh     # Shell helper para descargar scrcpy (Git Bash)
├── setup_repo.sh             # generador/ayudante (Git Bash)
├── VERSION
├── CHANGELOG.md
└── archive/                  # archivos históricos y variantes (no parte del flujo principal)
    ├── BASS_CAM_final.bat
    └── BASS_Cam_min.bat
```

**Nota:** Los binarios de scrcpy (scrcpy.exe, adb.exe, DLLs, scrcpy-server) NO están versionados; colócalos en `bin/` o usa los helpers para descargarlos.

## Requisitos
- Windows 10/11 para el flujo principal (Window Capture/WGC en OBS).
- scrcpy v3.0+ (probado con v4.1). Descarga desde https://github.com/Genymobile/scrcpy/releases — usa los helpers incluidos.
- Depuración USB habilitada en Android. El Moto G06 con Android 15 fue el dispositivo de referencia.
- OBS Studio con soporte Window Capture (WGC). Para audio profesional: Reaper + ASIO4ALL o interfaz ASIO dedicada.

## Instalación rápida
1. Clona el repo:
```bash
git clone https://github.com/blackmetalhans/scrcpy-streaming-for-toasters.git
cd scrcpy-streaming-for-toasters
```
2. Descargar scrcpy automáticamente:
- En PowerShell (Windows):
```powershell
pwsh .\get_scrcpy_release.ps1 -OutDir bin
```
- En Git Bash:
```bash
./get_scrcpy_release.sh
```
3. Ejecuta desde la raíz del repo (Windows):
```powershell
./scrcpy_bass_cam.bat
```

## Uso y ajustes para PCs de baja gama
- Valores por defecto: el script usa resoluciones y bitrate moderados (720x480, 1500K) y aplica afinidad de CPU para reservar cores al encoder. Estos ajustes priorizan estabilidad y baja carga en CPUs con pocos núcleos.
- Si la CPU se saturase: reduce `CAM_FPS` a 15 o `CAM_SIZE` a 480x270 y disminuye `VIDEO_BITRATE` a 800K.
- Evita ejecutar procesos pesados en paralelo (navegador, DAW con muchos plugins) durante streaming.
- Usa `--render-driver=direct3d` (valor por defecto) para menor uso de CPU en Windows.

## Configuración destacada
- `ADB_SERIAL`: por defecto el script intenta autodetectar el dispositivo ADB conectado; si tienes varios dispositivos, establece manualmente `ADB_SERIAL` en la parte inicial del .bat.
- `CAM_SIZE`, `CAM_FPS`, `VIDEO_BITRATE`, `CPU_AFFINITY_HEX`: variables centralizadas al inicio del script.

## Troubleshooting rápido
- adb devices muestra `unauthorized`: acepta el diálogo RSA en el teléfono.
- La ventana `BASS_CAM_RAW` no aparece en OBS: abre el picker y selecciona Window Capture → Windows Graphics Capture.
- Si experimentas jitter en sesiones largas: baja `CAM_FPS` y `VIDEO_BITRATE`, monitoriza con `scrcpy --print-fps`.

## Cómo contribuir
- Añade issues para bugs o mejoras. Pull requests bienvenidos; usa CRLF en .bat si editas en Windows.

---
## Recursos
- Informe técnico: `informe_optimizacion.md` (pruebas, mediciones y recomendaciones avanzadas)
README_EOF

# scrcpy_bass_cambat (refactor with autodetect)
cat > scrcpy_bass_cam.bat <<'BAT_EOF'
@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

pushd "%~dp0" || exit /b 1

:: ============================================================================
:: scrcpy_bass_cam.bat
:: Pipeline: Moto G06 (Android 15, camara frontal via HAL) -> scrcpy -> OBS
:: ============================================================================
:: --- 1. VARIABLES DE CONFIGURACION ---
set "SCRCPY_DIR=%CD%"
set "SCRCPY_EXE=%SCRCPY_DIR%\scrcpy.exe"
set "ADB_EXE=%SCRCPY_DIR%\adb.exe"

:: ADB_SERIAL: dejar vacío para autodetección. Si tienes >1 device, definir manualmente.
set "ADB_SERIAL="

:: Camara:
set "CAMERA_ID=1"
set "CAM_SIZE=720x480"
set "CAM_FPS=30"
set "VIDEO_BITRATE=1500K"
set "VIDEO_CODEC=h264"
set "RENDER_DRIVER=direct3d"
set "WINDOW_TITLE=BASS_CAM_RAW"
set "VIDEO_BUFFER=0"

set "MAX_RETRIES=5"
set "RETRY_WAIT_SECONDS=3"

:: Afinidad CPU: cores 0-1 (mascara hex 3). No solapar con ASIO/Reaper ni OBS.
set "CPU_AFFINITY_HEX=3"

:: --- Autodetección de ADB_SERIAL si está vacío ---
if "%ADB_SERIAL%"=="" (
    if exist "%ADB_EXE%" (
        set "ADB_CMD=%ADB_EXE%"
    ) else (
        where adb >nul 2>&1
        if errorlevel 1 (
            set "ADB_CMD=adb"
        ) else (
            set "ADB_CMD=adb"
        )
    )
    set "DETECTED_SERIAL="
    for /f "usebackq tokens=1,2" %%A in (`%ADB_CMD% devices ^| findstr /R /C:"device$"`) do (
        if not defined DETECTED_SERIAL set "DETECTED_SERIAL=%%A"
    )
    if defined DETECTED_SERIAL (
        set "ADB_SERIAL=%DETECTED_SERIAL%"
        echo [AUTODETECT] Usando ADB serial: %ADB_SERIAL%
    ) else (
        echo [AVISO] No se pudo autodetectar un dispositivo ADB. Define ADB_SERIAL manualmente si tienes multiples dispositivos.
    )
)

:: --- 2. LOGGING ---
if not exist "logs" mkdir "logs" >nul 2>&1
for /f "tokens=1-3 delims=/- " %%a in ("%date%") do set "D=%%c%%b%%a"
for /f "tokens=1-3 delims=:. " %%a in ("%time%") do set "T=%%a%%b%%c"
set "T=%T: =0%"
set "LOG_FILE=%CD%\logs\bass_cam_%D%_%T%.log"

call :log "==================== INICIO scrcpy_bass_cam.bat ===================="

:: --- 3. VALIDACION DE BINARIOS ---
if not exist "%SCRCPY_EXE%" (
    call :log "[ERROR] No se encontro scrcpy.exe en: %SCRCPY_EXE%"
    goto :fatal_error_2
)
call :log "[OK] scrcpy.exe encontrado."

if not exist "%ADB_EXE%" (
    where adb >nul 2>&1
    if errorlevel 1 (
        call :log "[ERROR] adb no disponible ni local ni en PATH."
        goto :fatal_error_2
    ) else (
        set "ADB_EXE=adb"
        call :log "[OK] Se usara adb.exe del PATH."
    )
) else (
    call :log "[OK] adb.exe encontrado junto a scrcpy."
)

:: --- 4. LIMPIEZA DE PROCESOS ---
taskkill /F /IM scrcpy.exe /T >nul 2>&1
taskkill /F /IM adb.exe /T >nul 2>&1
"%ADB_EXE%" kill-server >nul 2>&1

:: --- 5. ADB + VALIDACION DE DISPOSITIVO (con reintentos) ---
call :log "[ADB] Iniciando adb start-server..."
"%ADB_EXE%" start-server >nul 2>&1
if errorlevel 1 (
    call :log "[ERROR] adb start-server fallo."
    goto :fatal_error_3
)

set "RETRY_COUNT=0"
set "DEVICE_READY=0"

:retry_adb_devices
set /a RETRY_COUNT+=1
call :log "[ADB] Verificando dispositivo (intento !RETRY_COUNT! de %MAX_RETRIES%)..."

set "ADB_OUT=%TEMP%\bass_cam_adb_out.txt"
"%ADB_EXE%" devices > "%ADB_OUT%" 2>&1

set "TARGET_LINE="
for /f "usebackq delims=" %%L in ("%ADB_OUT%") do (
    echo %%L | findstr /C:"%ADB_SERIAL%" >nul
    if not errorlevel 1 set "TARGET_LINE=%%L"
)
del "%ADB_OUT%" >nul 2>&1

if not defined TARGET_LINE (
    call :log "[AVISO] No se encontro el serial %ADB_SERIAL%."
    goto :adb_retry_wait
)

echo !TARGET_LINE! | find "unauthorized" >nul
if not errorlevel 1 (
    call :log "[AVISO] Dispositivo UNAUTHORIZED. Acepta depuracion USB."
    goto :adb_retry_wait
)

echo !TARGET_LINE! | find "offline" >nul
if not errorlevel 1 (
    call :log "[AVISO] Dispositivo OFFLINE. Reintentando..."
    goto :adb_retry_wait
)

echo !TARGET_LINE! | find "device" >nul
if not errorlevel 1 (
    call :log "[OK] Dispositivo listo: !TARGET_LINE!"
    set "DEVICE_READY=1"
    goto :adb_ready
)

call :log "[AVISO] Estado no reconocido."

:adb_retry_wait
if !RETRY_COUNT! geq %MAX_RETRIES% (
    call :log "[ERROR] Se agotaron los reintentos de conexion ADB."
    goto :fatal_error_4
)
timeout /t %RETRY_WAIT_SECONDS% /nobreak >nul
goto :retry_adb_devices

:adb_ready
if "!DEVICE_READY!"=="0" (
    call :log "[ERROR] Estado 'device' no confirmado."
    goto :fatal_error_4
)

:: --- 6. LANZAMIENTO DE SCRCPY ---
call :log "[SCRCPY] Lanzando camara id=%CAMERA_ID% %CAM_SIZE% @ %CAM_FPS%fps, serial=%ADB_SERIAL%"

start "" /affinity %CPU_AFFINITY_HEX% "%SCRCPY_EXE%" ^
    --serial=%ADB_SERIAL% ^
    --video-source=camera ^
    --camera-id=%CAMERA_ID% ^
    --camera-size=%CAM_SIZE% ^
    --camera-fps=%CAM_FPS% ^
    --video-bit-rate=%VIDEO_BITRATE% ^
    --video-codec=%VIDEO_CODEC% ^
    --video-buffer=%VIDEO_BUFFER% ^
    --render-driver=%RENDER_DRIVER% ^
    --no-audio ^
    --no-control ^
    --window-title=%WINDOW_TITLE% ^
    --window-borderless

if errorlevel 1 (
    call :log "[ERROR] Fallo al lanzar scrcpy."
    goto :fatal_error_5
)

call :log "[OK] Stream activo. Ventana '%WINDOW_TITLE%' lista para OBS (Window Capture/WGC)."
call :log "==================== scrcpy_bass_cam.bat ACTIVO ===================="
call :log "Pulsa una tecla para detener el stream."

pause >nul

:: --- 7. LIMPIEZA AL SALIR ---
call :log "[CLEANUP] Cerrando scrcpy..."
taskkill /F /IM scrcpy.exe /T >nul 2>&1

set "KILL_ADB="
set /p "KILL_ADB=Matar tambien el servidor adb? (S/N): "
if /i "%KILL_ADB%"=="S" (
    "%ADB_EXE%" kill-server >nul 2>&1
    call :log "[CLEANUP] adb kill-server ejecutado."
)

call :log "==================== FIN scrcpy_bass_cam.bat (OK) ===================="
popd
exit /b 0

:: ==================== SUBRUTINAS ====================
:log
set "MSG=%~1"
set "TS=%date% %time%"
>>"%LOG_FILE%" echo [%TS%] %MSG%
echo [%TS%] %MSG%
goto :eof

:fatal_error_2
call :log "==================== FIN (ERROR: BINARIOS FALTANTES) ===================="
popd
exit /b 2

:fatal_error_3
call :log "==================== FIN (ERROR: ADB START-SERVER) ===================="
popd
exit /b 3

:fatal_error_4
call :log "==================== FIN (ERROR: DISPOSITIVO NO DISPONIBLE) ===================="
popd
exit /b 4

:fatal_error_5
call :log "==================== FIN (ERROR: FALLO AL LANZAR SCRCPY) ===================="
popd
exit /b 5
BAT_EOF

# get_scrcpy_release.sh (hardened)
cat > get_scrcpy_release.sh <<'SH_EOF'
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
SH_EOF
chmod +x get_scrcpy_release.sh

# get_scrcpy_release.ps1 (hardened)
cat > get_scrcpy_release.ps1 <<'PS_EOF'
<# get_scrcpy_release.ps1 #>
param(
    [string]$OutDir = "bin"
)

$api = 'https://api.github.com/repos/Genymobile/scrcpy/releases/latest'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

Write-Host "Querying $api ..."
try {
    $rel = Invoke-RestMethod -Uri $api -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Error "Failed to query GitHub API: $_"
    exit 2
}

$asset = $null
foreach ($a in $rel.assets) {
    $name = $a.name.ToLower()
    if ($name -like '*win*' -and $name -like '*.zip') { $asset = $a; break }
}
if (-not $asset) {
    foreach ($a in $rel.assets) { if ($a.name -like '*.zip') { $asset = $a; break } }
}
if (-not $asset) { Write-Error "No zip asset found in release. Visit https://github.com/Genymobile/scrcpy/releases"; exit 2 }

$url = $asset.browser_download_url
$zip = Join-Path $env:TEMP "scrcpy_release.zip"
Write-Host "Downloading $($asset.name) ..."
try {
    Invoke-WebRequest -Uri $url -OutFile $zip -ErrorAction Stop
} catch {
    Write-Error "Download failed: $_"
    exit 3
}

Write-Host "Extracting to $OutDir ..."
try {
    Expand-Archive -Path $zip -DestinationPath $OutDir -Force -ErrorAction Stop
    Remove-Item $zip -Force
} catch {
    Write-Error "Extraction failed: $_"
    exit 4
}
Write-Host "Done. Files in: $OutDir"
PS_EOF

# .gitattributes
cat > .gitattributes <<'GA_EOF'
*.bat text eol=crlf
*.ps1 text eol=crlf
*.sh text eol=lf
*.md text
GA_EOF

# .gitignore (improved)
cat > .gitignore <<'GI_EOF'
# Binarios y libs de scrcpy (se descargan del release oficial, no se versionan)
bin/
*.exe
*.dll
scrcpy-server

# Logs generados en cada corrida
logs/
*.log

# Temporales de Windows/PowerShell
*.tmp
Thumbs.db
desktop.ini

# Release assets
*.zip
*.tar.gz
*.tgz

# Editor temp files
*.swp
*~
GI_EOF

# archive/README.md
cat > archive/README.md <<'ARC_EOF'
Archivos históricos

- BASS_CAM_final.bat — versión final previa al refactor.
- BASS_Cam_min.bat — versión minimalista.

Para restaurar una versión: copiar el archivo desde archive/ a la raíz del proyecto y verificar las variables (especialmente ADB_SERIAL).
ARC_EOF

# GitHub Actions workflow
cat > .github/workflows/release.yml <<'WF_EOF'
name: Create release asset
on:
  push:
    tags:
      - 'v*'

jobs:
  build-and-release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Create release archive
        run: |
          RELEASE_NAME="scrcpy-bass-cam-${GITHUB_REF#refs/tags/}"
          tar -czf "${RELEASE_NAME}.tar.gz" \
            scrcpy_bass_cam.bat scrcpy_bass_cam_fallback_tcp.bat README.md LICENSE VERSION CHANGELOG.md get_scrcpy_release.ps1 get_scrcpy_release.sh setup_repo.sh archive
          echo "release_asset=${RELEASE_NAME}.tar.gz" >> $GITHUB_OUTPUT
      - name: Create GitHub release
        id: create_release
        uses: actions/create-release@v1
        with:
          tag_name: ${{ github.ref_name }}
          release_name: ${{ github.ref_name }}
          body_path: CHANGELOG.md
          draft: false
          prerelease: false
          token: ${{ secrets.GITHUB_TOKEN }}
      - name: Upload release asset
        uses: actions/upload-release-asset@v1
        with:
          upload_url: ${{ steps.create_release.outputs.upload_url }}
          asset_path: ${{ steps.create_release.outputs.release_asset }}
          asset_name: ${{ steps.create_release.outputs.release_asset }}
          asset_content_type: application/gzip
WF_EOF

#  Update VERSION
echo "$NEW_VERSION" > VERSION

# Prepend CHANGELOG
if [ ! -f CHANGELOG.md ]; then
  cat > CHANGELOG.md <<'CH_EOF'
# Changelog

All notable changes to this project.

CH_EOF
fi

TMP_CHANGELOG="$(mktemp)"
cat > "$TMP_CHANGELOG" <<CH_EOF
## [${NEW_VERSION}] - $(date +%F)
- Refactor: README expanded with practical uses and low-end PC tips.
- Behavior: Autodetect ADB_SERIAL when empty; safer device selection.
- Helpers: Hardened get_scrcpy_release.sh and get_scrcpy_release.ps1 with better fallbacks.
- Repo metadata: .gitattributes and .gitignore improved.
- archive/: added README explaining archived files.
- CI: Add basic GitHub Actions workflow to build release asset on tag.
- Misc: prepare for v${NEW_VERSION} release.
CH_EOF

cat CHANGELOG.md >> "$TMP_CHANGELOG"
mv "$TMP_CHANGELOG" CHANGELOG.md

# Stage and commit
git add README.md scrcpy_bass_cam.bat get_scrcpy_release.sh get_scrcpy_release.ps1 .gitattributes .gitignore archive/README.md .github/workflows/release.yml VERSION CHANGELOG.md || true

git commit -m "chore(release): refactor README, autodetect ADB_SERIAL, harden helpers, add gitattributes, update gitignore, add workflow, bump VERSION to ${NEW_VERSION}" || {
  echo "Nothing to commit or commit failed."
}

# Push changes
read -p "Push changes to origin/main now? (type YES to push): " PUSHCONF
if [ "$PUSHCONF" != "YES" ]; then
  echo "Changes are committed locally. Exiting."
  exit 0
fi

git push origin main

# Create tag
git tag -a "${TAG}" -m "Release ${TAG}"
git push origin "${TAG}"

# Build release asset locally (prefer zip, else tar.gz)
RELEASE_NAME="scrcpy-bass-cam-${NEW_VERSION}"
ASSET_FILE=""
if [ $HAS_ZIP -eq 1 ]; then
  zip -r "${RELEASE_NAME}.zip" \
    scrcpy_bass_cam.bat scrcpy_bass_cam_fallback_tcp.bat README.md LICENSE VERSION CHANGELOG.md get_scrcpy_release.ps1 get_scrcpy_release.sh setup_repo.sh archive
  ASSET_FILE="${RELEASE_NAME}.zip"
else
  tar -czf "${RELEASE_NAME}.tar.gz" \
    scrcpy_bass_cam.bat scrcpy_bass_cam_fallback_tcp.bat README.md LICENSE VERSION CHANGELOG.md get_scrcpy_release.ps1 get_scrcpy_release.sh setup_repo.sh archive
  ASSET_FILE="${RELEASE_NAME}.tar.gz"
fi

echo "Prepared asset: $ASSET_FILE"

# Create release with gh if available
if [ $HAS_GH -eq 1 ]; then
  echo "Creating GitHub release ${TAG} and uploading asset via gh..."
  gh auth status >/dev/null 2>&1 || { echo "Please run 'gh auth login' first."; exit 1; }
  gh release create "${TAG}" "$ASSET_FILE" --title "${TAG}" --notes-file CHANGELOG.md --repo "${REPO_NWO}"
  # Update repo description
  gh repo edit "${REPO_NWO}" --description "Streaming de baja latencia desde cámara frontal Android a OBS usando scrcpy — scripts y guía para sincronizar audio profesionalmente."
  echo "Release created: https://github.com/${REPO_NWO}/releases/tag/${TAG}"
else
  echo "gh CLI not found. Release not created automatically. Use the following command to create the release:"
  echo "gh release create ${TAG} ${ASSET_FILE} --title \"${TAG}\" --notes-file CHANGELOG.md --repo ${REPO_NWO}"
fi

echo "Done. Local changes committed and pushed. Tag ${TAG} created and pushed."
