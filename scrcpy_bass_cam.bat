@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

pushd "%~dp0" || exit /b 1

:: ============================================================================
:: scrcpy_bass_cam.bat - robustado para autodetección y ejecución desde Windows cmd.exe
:: Pipeline: Android phone (front camera) -> scrcpy -> OBS::
:: NOTE: Run this script from native cmd.exe for correct behavior. If you run it
:: from Git Bash / MSYS, please invoke it with:  cmd.exe /C scrcpy_bass_cam.bat
:: ============================================================================

:: --- 1. VARIABLES DE CONFIGURACION ---
set "SCRCPY_DIR=%CD%"
set "SCRCPY_EXE=%SCRCPY_DIR%\scrcpy.exe"
set "ADB_EXE=%SCRCPY_DIR%\adb.exe"

:: ADB_SERIAL: leave empty for autodetection; set manually if you have multiple devices.
:: Do NOT overwrite an externally provided ADB_SERIAL environment variable.
if not defined ADB_SERIAL set "ADB_SERIAL="

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

:: Afinidad CPU: cores 0-1 (mascara hex 3). Ajustar segun necesidad.
set "CPU_AFFINITY_HEX=3"

:: --- Helpers para localizar binarios ---
if not exist "%SCRCPY_EXE%" (
  if exist "%~dp0bin\scrcpy.exe" (
    set "SCRCPY_EXE=%~dp0bin\scrcpy.exe"
    call :log "[INFO] scrcpy.exe localizado en %SCRCPY_EXE%"
  ) else (
    where scrcpy >nul 2>&1
    if not errorlevel 1 (
      set "SCRCPY_EXE=scrcpy"
      call :log "[INFO] scrcpy disponible en PATH"
    )
  )
)

if not exist "%SCRCPY_EXE%" (
  call :log "[ERROR] No se encontro scrcpy.exe en: %SCRCPY_EXE%"
  goto :fatal_error_2
)

if not exist "%ADB_EXE%" (
  where adb >nul 2>&1
  if errorlevel 1 (
    set "ADB_EXE=adb"
  ) else (
    set "ADB_EXE=adb"
  )
)

:: --- Intentar autodetectar dispositivo ADB si ADB_SERIAL vacío ---
if "%ADB_SERIAL%"=="" (
  set "DEVICE_COUNT=0"
  set "FIRST_SERIAL="
  for /f "skip=1 tokens=1,2" %%a in ('%ADB_EXE% devices') do (
    if "%%b"=="device" (
      if not defined FIRST_SERIAL set "FIRST_SERIAL=%%a"
      set /a DEVICE_COUNT+=1
    )
  )
  if "%DEVICE_COUNT%"=="1" (
    set "ADB_SERIAL=%FIRST_SERIAL%"
    call :log "[AUTODETECT] Se detectó 1 dispositivo ADB: %ADB_SERIAL%"
  ) else if "%DEVICE_COUNT%"=="0" (
    call :log "[AVISO] No se detectaron dispositivos ADB en la primera comprobación."
  ) else (
    call :log "[AVISO] Se detectaron %DEVICE_COUNT% dispositivos ADB. Dejar ADB_SERIAL vacío y especificarlo manualmente si es necesario."
  )
)

:: --- 2. LOGGING ---
if not exist "logs" mkdir "logs" >nul 2>&1
for /f "tokens=1-3 delims=/- " %%a in ("%date%") do set "D=%%c%%b%%a"
for /f "tokens=1-3 delims=:." %%a in ("%time%") do set "T=%%a%%b%%c"
set "T=%T: =0%"
set "LOG_FILE=%CD%\logs\bass_cam_%D%_%T%.log"

call :log "==================== INICIO scrcpy_bass_cam.bat ===================="

:: --- 3. VALIDACION DE BINARIOS ---
if exist "%SCRCPY_EXE%" (
  call :log "[OK] scrcpy.exe encontrado: %SCRCPY_EXE%"
) else (
  call :log "[ERROR] No se encontro scrcpy.exe en: %SCRCPY_EXE%"
  goto :fatal_error_2
)

where adb >nul 2>&1
if errorlevel 1 (
  call :log "[ERROR] adb no disponible ni local ni en PATH."
  goto :fatal_error_2
) else (
  call :log "[OK] adb disponible."
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
for /f "usebackq tokens=1,2" %%a in ('type "%ADB_OUT%"') do (
  if "%%b"=="device" (
    if defined ADB_SERIAL (
      if "%%a"=="%ADB_SERIAL%" set "TARGET_LINE=%%a device"
    ) else (
      if not defined TARGET_LINE set "TARGET_LINE=%%a device"
    )
  )
  if "%%b"=="unauthorized" (
    if defined ADB_SERIAL (
      if "%%a"=="%ADB_SERIAL%" set "TARGET_LINE=%%a unauthorized"
    ) else (
      if not defined TARGET_LINE set "TARGET_LINE=%%a unauthorized"
    )
  )
  if "%%b"=="offline" (
    if defined ADB_SERIAL (
      if "%%a"=="%ADB_SERIAL%" set "TARGET_LINE=%%a offline"
    ) else (
      if not defined TARGET_LINE set "TARGET_LINE=%%a offline"
    )
  )
)

del "%ADB_OUT%" >nul 2>&1

if not defined TARGET_LINE (
  call :log "[AVISO] No se encontro el serial %ADB_SERIAL%."
  goto :adb_retry_wait
)

if defined TARGET_LINE (
  echo !TARGET_LINE! | findstr /C:"unauthorized" >nul
  if not errorlevel 1 (
    call :log "[AVISO] Dispositivo UNAUTHORIZED. Acepta depuracion USB."
    goto :adb_retry_wait
  )

  echo !TARGET_LINE! | findstr /C:"offline" >nul
  if not errorlevel 1 (
    call :log "[AVISO] Dispositivo OFFLINE. Reintentando..."
    goto :adb_retry_wait
  )

  echo !TARGET_LINE! | findstr /C:"device" >nul
  if not errorlevel 1 (
    call :log "[OK] Dispositivo listo: !TARGET_LINE!"
    set "DEVICE_READY=1"
    goto :adb_ready
  )
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
