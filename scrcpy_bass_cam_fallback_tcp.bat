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
