#!/usr/bin/env bash
# setup_repo.sh — Ejecutar en Git Bash dentro de la carpeta del proyecto
# (C:\Users\Numpay\Desktop\Codes\scrcpy-streaming-for-toasters)
set -e

echo "=== Renombrando BASS_CAM.bat -> scrcpy_bass_cam.bat ==="
[ -f BASS_CAM.bat ] && mv BASS_CAM.bat BASS_CAM.bat.bak

echo "=== Escribiendo scrcpy_bass_cam.bat ==="
cat <<'BATFILE' > scrcpy_bass_cam.bat
@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

pushd "%~dp0" || exit /b 1

:: ============================================================================
:: scrcpy_bass_cam.bat
:: Pipeline: Moto G06 (Android 15, camara frontal via HAL) -> scrcpy -> OBS
:: Renombrado desde BASS_CAM.bat. scrcpy v4.1.
:: Fuentes: https://github.com/Genymobile/scrcpy/blob/master/doc/camera.md
:: ============================================================================

:: --- 1. VARIABLES DE CONFIGURACION ---

set "SCRCPY_DIR=%CD%"
set "SCRCPY_EXE=%SCRCPY_DIR%\scrcpy.exe"
set "ADB_EXE=%SCRCPY_DIR%\adb.exe"

:: Serial explicito: evita "Multiple ADB devices" cuando hay USB + TCP activos.
:: Cambiar a 10.72.11.235:5555 para usar TCP/IP en vez de USB.
set "ADB_SERIAL=ZY32M6CM7D"

:: Camara: camera-id=1 = frontal del Moto G06 (verificado con --list-cameras).
:: 720x480 = tamaño soportado nativamente (verificado con --list-camera-sizes).
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

:: --- 2. LOGGING ---

if not exist "logs" mkdir "logs" >nul 2>&1
for /f "tokens=1-3 delims=/- " %%a in ("%date%") do set "D=%%c%%b%%a"
for /f "tokens=1-3 delims=:." %%a in ("%time%") do set "T=%%a%%b%%c"
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
:: start /affinity aplica la mascara nativamente (sin race condition).
:: --stay-awake omitido: es incompatible con --no-control en scrcpy v4.1.

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
BATFILE

echo "=== Actualizando scrcpy_bass_cam_fallback_tcp.bat ==="
cat <<'BATFILE' > scrcpy_bass_cam_fallback_tcp.bat
@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

pushd "%~dp0" || exit /b 1

:: ============================================================================
:: scrcpy_bass_cam_fallback_tcp.bat
:: Variante fallback: mirroring de PANTALLA COMPLETA via TCP/RNDIS (no camara).
:: Usar cuando el USB da problemas de handshake o para testing de mirroring.
:: ============================================================================

set "SCRCPY_EXE=%CD%\scrcpy.exe"
set "ADB_EXE=%CD%\adb.exe"

:: IP del gateway RNDIS del telefono en modo hotspot USB.
:: Verificar con "ipconfig" (adaptador Ethernet RNDIS) si cambia.
set "PHONE_IP=10.72.11.235"
set "PHONE_PORT=5555"

set "MAX_SIZE=1024"
set "VIDEO_CODEC=h264"

if not exist "logs" mkdir "logs" >nul 2>&1
for /f "tokens=1-3 delims=/- " %%a in ("%date%") do set "D=%%c%%b%%a"
for /f "tokens=1-3 delims=:." %%a in ("%time%") do set "T=%%a%%b%%c"
set "T=%T: =0%"
set "LOG_FILE=%CD%\logs\bass_cam_fallback_%D%_%T%.log"

call :log "==================== INICIO FALLBACK TCP/RNDIS ===================="

if not exist "%SCRCPY_EXE%" (
    call :log "[ERROR] No se encontro scrcpy.exe en %SCRCPY_EXE%"
    popd
    exit /b 2
)
if not exist "%ADB_EXE%" (
    call :log "[AVISO] No se encontro adb.exe local, se usara el del PATH."
    set "ADB_EXE=adb"
)

call :log "[ADB] Reseteando daemon..."
"%ADB_EXE%" kill-server >nul 2>&1
"%ADB_EXE%" start-server >nul 2>&1

call :log "[ADB] Activando listener TCP en puerto %PHONE_PORT%..."
"%ADB_EXE%" tcpip %PHONE_PORT% >nul 2>&1
timeout /t 2 /nobreak >nul

call :log "[ADB] Conectando a %PHONE_IP%:%PHONE_PORT% via RNDIS..."
set "CONNECT_RETRIES=0"

:retry_connect
set /a CONNECT_RETRIES+=1
"%ADB_EXE%" connect %PHONE_IP%:%PHONE_PORT% > "%TEMP%\bass_cam_connect_result.txt" 2>&1
set "CONNECT_RESULT="
for /f "usebackq delims=" %%r in ("%TEMP%\bass_cam_connect_result.txt") do set "CONNECT_RESULT=%%r"
del "%TEMP%\bass_cam_connect_result.txt" >nul 2>&1

echo !CONNECT_RESULT! | find "connected" >nul
if not errorlevel 1 (
    call :log "[OK] !CONNECT_RESULT!"
    goto :connected
)

call :log "[AVISO] Intento !CONNECT_RETRIES! fallido: !CONNECT_RESULT!"
if !CONNECT_RETRIES! geq 5 (
    call :log "[ERROR] No se pudo conectar via TCP/RNDIS tras 5 intentos."
    popd
    exit /b 4
)
timeout /t 3 /nobreak >nul
goto :retry_connect

:connected
call :log "[SCRCPY] Iniciando mirroring de pantalla (max-size=%MAX_SIZE%, codec=%VIDEO_CODEC%)..."
call :log "[AVISO] Este modo NO usa --video-source=camera: es mirroring de pantalla completo."

"%SCRCPY_EXE%" -e --max-size=%MAX_SIZE% --video-codec=%VIDEO_CODEC%

call :log "==================== FIN FALLBACK TCP/RNDIS ===================="
popd
exit /b 0

:log
set "MSG=%~1"
set "TS=%date% %time%"
>>"%LOG_FILE%" echo [%TS%] %MSG%
echo [%TS%] %MSG%
goto :eof
BATFILE

echo "=== Creando .gitignore ==="
cat <<'EOF' > .gitignore
# Binarios y libs de scrcpy (se descargan del release oficial, no se versionan)
*.exe
*.dll
scrcpy-server
scrcpy-server.zip
scrcpy-noconsole.vbs
scrcpy.png
disconnected.png
LICENSE.txt

# Logs generados en cada corrida
logs/
*.log

# Temporales de Windows/PowerShell
*.tmp
Thumbs.db
desktop.ini
Nuevo documento de texto.txt
BASS_CAM.bat.bak
EOF

echo "=== Creando LICENSE ==="
cat <<'EOF' > LICENSE
MIT License

Copyright (c) 2026 Hans

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

------------------------------------------------------------------------------

NOTA: Los binarios de scrcpy (scrcpy.exe, adb.exe, DLLs, scrcpy-server) que se
descargan por separado desde https://github.com/Genymobile/scrcpy/releases se
distribuyen bajo Apache License 2.0. Este archivo LICENSE (MIT) cubre unicamente
los scripts .bat y la documentacion de este repositorio.
EOF

echo "=== Limpiando archivo vacio ==="
rm -f "Nuevo documento de texto.txt"

echo "=== Inicializando repo git ==="
git init
git add -A
git commit -m "refactor: rename BASS_CAM.bat -> scrcpy_bass_cam.bat, fix all scrcpy v4.1 flags

- camera-id=1 + 720x480 + 30fps (validated via --list-camera-sizes)
- removed --stay-awake (incompatible with --no-control)
- start /affinity native (no PowerShell PID race condition)
- pushd/popd instead of cd /d
- :log with goto :eof (fixes label error)
- ADB_SERIAL fixed to avoid Multiple ADB devices
- temp file for adb devices parsing (fixes pipe/quoting errors)
- added .gitignore, LICENSE (MIT)
- cleaned up empty files"

echo ""
echo "=== Listo. Para subir a GitHub: ==="
echo "git remote add origin https://github.com/TU_USUARIO/scrcpy-bass-cam.git"
echo "git branch -M main"
echo "git push -u origin main"
echo ""
echo "O crea el repo desde GitHub CLI si la tienes:"
echo "gh repo create scrcpy-bass-cam --public --source=. --push"
