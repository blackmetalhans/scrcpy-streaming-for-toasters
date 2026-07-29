@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

pushd "%~dp0" || exit /b 1

set "SCRCPY_DIR=%CD%"
set "SCRCPY_EXE=%SCRCPY_DIR%\scrcpy.exe"
set "ADB_EXE=%SCRCPY_DIR%\adb.exe"
set "ADB_SERIAL=ZY32M6CM7D"

set "CAM_FACING=front"
set "CAM_SIZE=854x480"
set "CAM_FPS=25"
set "VIDEO_BITRATE=1500K"
set "VIDEO_CODEC=h264"
set "RENDER_DRIVER=direct3d"
set "WINDOW_TITLE=BASS_CAM_RAW"
set "VIDEO_BUFFER=0"

set "MAX_RETRIES=5"
set "RETRY_WAIT_SECONDS=3"
set "CPU_AFFINITY_HEX=3"

if not exist "logs" mkdir "logs" >nul 2>&1
for /f "tokens=1-3 delims=/- " %%a in ("%date%") do set "D=%%c%%b%%a"
for /f "tokens=1-3 delims=:." %%a in ("%time%") do set "T=%%a%%b%%c"
set "T=%T: =0%"
set "LOG_FILE=%CD%\logs\bass_cam_%D%_%T%.log"

call :log "==================== INICIO BASS_CAM.BAT ===================="

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

taskkill /F /IM scrcpy.exe /T >nul 2>&1
taskkill /F /IM adb.exe /T >nul 2>&1
"%ADB_EXE%" kill-server >nul 2>&1

call :log "[ADB] Iniciando adb start-server..."
"%ADB_EXE%" start-server >nul 2>&1
if errorlevel 1 (
    call :log "[ERROR] adb start-server fallo. ERRORLEVEL=%errorlevel%"
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
goto :adb_retry_wait

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

call :log "[SCRCPY] Lanzando camara %CAM_SIZE% @ %CAM_FPS%fps, serial=%ADB_SERIAL%"

start "" /affinity %CPU_AFFINITY_HEX% "%SCRCPY_EXE%" ^
    --serial=%ADB_SERIAL% ^
    --video-source=camera ^
    --camera-facing=%CAM_FACING% ^
    --camera-size=%CAM_SIZE% ^
    --camera-fps=%CAM_FPS% ^
    --video-bit-rate=%VIDEO_BITRATE% ^
    --video-codec=%VIDEO_CODEC% ^
    --video-buffer=%VIDEO_BUFFER% ^
    --render-driver=%RENDER_DRIVER% ^
    --stay-awake ^
    --no-audio ^
    --no-control ^
    --window-title=%WINDOW_TITLE% ^
    --window-borderless

if errorlevel 1 (
    call :log "[ERROR] Fallo al lanzar scrcpy. ERRORLEVEL=%errorlevel%"
    goto :fatal_error_5
)

call :log "[OK] Stream activo. Pulsa una tecla para detenerlo."
pause >nul

taskkill /F /IM scrcpy.exe /T >nul 2>&1

set "KILL_ADB="
set /p "KILL_ADB=Matar tambien el servidor adb? (S/N): "
if /i "%KILL_ADB%"=="S" (
    "%ADB_EXE%" kill-server >nul 2>&1
    call :log "[CLEANUP] adb kill-server ejecutado por peticion del usuario."
)

call :log "==================== FIN BASS_CAM.BAT (OK) ===================="
popd
exit /b 0

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