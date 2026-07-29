@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

pushd "%~dp0" || exit /b 1

:: ============================================================================
:: scrcpy_bass_cam.bat — CONFIGURACION OPTIMIZADA (480p @ 30fps)
:: Pipeline: Moto G06 (Cámara frontal HAL + Micrófono) -> scrcpy -> OBS
:: Audio: Captura de micrófono del teléfono SIN reproducción en parlantes PC (--no-audio-playback)
:: ============================================================================

set "SCRCPY_EXE=%~dp0scrcpy.exe"
if not exist "%SCRCPY_EXE%" set "SCRCPY_EXE=%~dp0bin\scrcpy.exe"

set "ADB_EXE=%~dp0adb.exe"
if not exist "%ADB_EXE%" set "ADB_EXE=adb"

set "CAM_FACING=front"
set "CAM_SIZE=720x480"
set "CAM_FPS=30"

set "VIDEO_BITRATE=1500K"
set "VIDEO_CODEC=h264"
set "AUDIO_SOURCE=mic"
set "RENDER_DRIVER=direct3d"
set "WINDOW_TITLE=BASS_CAM_RAW"
set "VIDEO_BUFFER=0"

set "MAX_RETRIES=5"
set "RETRY_WAIT_SECONDS=3"
set "CPU_AFFINITY_HEX=3"

:: --- LOGGING ---
if not exist "logs" mkdir "logs" >nul 2>&1
for /f "tokens=1-3 delims=/- " %%a in ("%date%") do set "D=%%c%%b%%a"
for /f "tokens=1-3 delims=:." %%a in ("%time%") do set "T=%%a%%b%%c"
set "T=%T: =0%"
set "LOG_FILE=%~dp0logs\bass_cam_%D%_%T%.log"

call :log "==================== INICIO scrcpy_bass_cam.bat ===================="

:: --- VALIDACION DE BINARIOS ---
if exist "%SCRCPY_EXE%" (
    call :log "[OK] scrcpy.exe encontrado: %SCRCPY_EXE%"
) else (
    call :log "[ERROR] No se encontro scrcpy.exe."
    popd
    exit /b 2
)

:: --- LIMPIEZA DE PROCESOS HUERFANOS ---
call :log "[LIMPIEZA] Purgando procesos previos de scrcpy y adb..."
taskkill /F /IM scrcpy.exe /T >nul 2>&1
taskkill /F /IM adb.exe /T >nul 2>&1
"%ADB_EXE%" kill-server >nul 2>&1

:: --- INICIO ADB Y DETECCION DE DISPOSITIVO ---
call :log "[ADB] Iniciando adb start-server..."
"%ADB_EXE%" start-server >nul 2>&1
if errorlevel 1 (
    call :log "[ERROR] adb start-server fallo."
    popd
    exit /b 3
)

set "RETRY_COUNT=0"
set "DEVICE_READY=0"
set "ADB_SERIAL="

:retry_adb_devices
set /a RETRY_COUNT+=1
call :log "[ADB] Verificando dispositivo (intento !RETRY_COUNT! de %MAX_RETRIES%)..."

set "ADB_OUT=%TEMP%\bass_cam_adb_out.txt"
"%ADB_EXE%" devices > "%ADB_OUT%" 2>&1

set "TARGET_LINE="
for /f "usebackq tokens=1,2" %%a in ("%ADB_OUT%") do (
    if "%%b"=="device" (
        set "ADB_SERIAL=%%a"
        set "TARGET_LINE=%%a device"
    )
    if "%%b"=="unauthorized" set "TARGET_LINE=%%a unauthorized"
    if "%%b"=="offline" set "TARGET_LINE=%%a offline"
)
del "%ADB_OUT%" >nul 2>&1

if not defined TARGET_LINE (
    call :log "[AVISO] No se detecto ningún dispositivo ADB."
    goto :adb_retry_wait
)

echo !TARGET_LINE! | findstr /C:"unauthorized" >nul
if not errorlevel 1 (
    call :log "[AVISO] Dispositivo UNAUTHORIZED. Revisa la pantalla del teléfono y acepta la depuración USB."
    goto :adb_retry_wait
)

echo !TARGET_LINE! | findstr /C:"offline" >nul
if not errorlevel 1 (
    call :log "[AVISO] Dispositivo OFFLINE. Reintentando..."
    goto :adb_retry_wait
)

echo !TARGET_LINE! | findstr /C:"device" >nul
if not errorlevel 1 (
    call :log "[OK] Dispositivo conectado: !TARGET_LINE!"
    set "DEVICE_READY=1"
    goto :adb_ready
)

:adb_retry_wait
if !RETRY_COUNT! geq %MAX_RETRIES% (
    call :log "[ERROR] Se agotaron los reintentos de conexion ADB."
    popd
    exit /b 4
)
timeout /t %RETRY_WAIT_SECONDS% /nobreak >nul
goto :retry_adb_devices

:adb_ready
if "!DEVICE_READY!"=="0" (
    call :log "[ERROR] Dispositivo no verificado."
    popd
    exit /b 4
)

:: --- LANZAMIENTO DE SCRCPY ---
call :log "[SCRCPY] Lanzando captura de cámara frontal %CAM_SIZE% @ %CAM_FPS%fps (audio=%AUDIO_SOURCE%, sin playback local)..."

start "BASS_CAM_DECODER" /affinity %CPU_AFFINITY_HEX% /high "%SCRCPY_EXE%" ^
    --serial=%ADB_SERIAL% ^
    --video-source=camera ^
    --camera-facing=%CAM_FACING% ^
    --camera-size=%CAM_SIZE% ^
    --camera-fps=%CAM_FPS% ^
    --audio-source=%AUDIO_SOURCE% ^
    --no-audio-playback ^
    --video-bit-rate=%VIDEO_BITRATE% ^
    --video-codec=%VIDEO_CODEC% ^
    --video-buffer=%VIDEO_BUFFER% ^
    --render-driver=%RENDER_DRIVER% ^
    --no-control ^
    --window-title="%WINDOW_TITLE%" ^
    --window-borderless

if errorlevel 1 (
    call :log "[ERROR] Fallo al lanzar scrcpy."
    popd
    exit /b 5
)

call :log "[OK] Stream activo. Ventana '%WINDOW_TITLE%' lista para captura en OBS."
call :log "==================== scrcpy_bass_cam.bat ACTIVO ===================="
pause >nul

:: --- LIMPIEZA ---
call :log "[CLEANUP] Cerrando scrcpy..."
taskkill /F /IM scrcpy.exe /T >nul 2>&1

call :log "==================== FIN scrcpy_bass_cam.bat (OK) ===================="
popd
exit /b 0

:log
set "MSG=%~1"
set "TS=%date% %time%"
>>"%LOG_FILE%" echo [%TS%] %MSG%
echo [%TS%] %MSG%
goto :eof