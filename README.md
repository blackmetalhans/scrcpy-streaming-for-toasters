# scrcpy-bass-cam

Pipeline de streaming de baja latencia: Moto G06 (Android 15, cámara frontal HAL) → scrcpy → OBS Studio. Sincronización de audio vía Reaper + ASIO4ALL + ReaStream.

## Stack
- Lenguajes: Batch (Windows .bat) y Shell (scripts de instalación)
- Herramientas: scrcpy (Genymobile), adb, OBS Studio, Reaper, ASIO4ALL

## Qué hay aquí / Organización
```
README.md                         # Esta guía (actualizada)
LICENSE                            # MIT para scripts y docs
.gitignore                         # bin/ y logs/ ignorados
informe_optimizacion.md            # Análisis y pruebas detalladas
scrcpy_bass_cam.bat                # Script principal (USB / cámara via HAL)
scrcpy_bass_cam_fallback_tcp.bat   # Fallback: mirroring por TCP/RNDIS
archive/                           # Archivos históricos y variantes
setup_repo.sh                      # Script de bootstrap (Git Bash)
get_scrcpy_release.ps1             # PowerShell helper para descargar scrcpy
get_scrcpy_release.sh              # Shell helper para descargar scrcpy (Git Bash)
VERSION                            # Número de versión del release
CHANGELOG.md                       # Historial de cambios
bin/                               # (no versionar) scrcpy.exe, adb.exe, DLLs
logs/                              # generados en la ejecución
```

Cómo encaja: El script principal es `scrcpy_bass_cam.bat`. `setup_repo.sh` es un ayudante para inicializar el repo en Git Bash y puede generar los `.bat` desde plantillas. Los binarios de scrcpy y adb se descargan con los helpers a `bin/`.

## Requisitos
- Windows 10/11 (para el flujo principal con Window Capture / WGC en OBS).
- scrcpy v3.0+ (probado con v4.1). Los binarios se descargan desde https://github.com/Genymobile/scrcpy/releases
- Habilitar Depuración USB en Android. Un Moto G06 con Android 15 fue el dispositivo de referencia.
- OBS Studio con Window Capture (WGC) y Reaper + ASIO4ALL si vas a enrutar audio profesionalmente.

## Instalación rápida (desde terminal)
1) Clona el repo:

```bash
git clone https://github.com/blackmetalhans/scrcpy-streaming-for-toasters.git
cd scrcpy-streaming-for-toasters
```

2) Descarga los binarios oficiales de scrcpy y colócalos en `bin/` automáticamente (elige la opción que prefieras):

- En PowerShell (Windows):

```powershell
# Ejecutar desde la raíz del repo
pwsh .\get_scrcpy_release.ps1 -OutDir bin
# o con parámetros: pwsh .\get_scrcpy_release.ps1 -OutDir bin
```

- En Git Bash / Linux/macOS (requiere curl + python):

```bash
./get_scrcpy_release.sh
```

3) Verifica que `bin/scrcpy.exe` y `bin/adb.exe` estén presentes (Windows) o que `scrcpy` esté en PATH en Linux.

4) Ejecuta (desde cmd.exe o usando cmd.exe /C desde Git Bash):

```powershell
# Windows (CMD):
cd C:\Users\<tu_usuario>\Desktop\Codes\scrcpy-streaming-for-toasters
scrcpy_bass_cam.bat
```

> Nota importante: ejecuta el .bat desde cmd.exe (o prefija con cmd.exe /C desde Git Bash) para asegurar que los comandos nativos de Windows (findstr, timeout, taskkill) funcionen correctamente.

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
- Si ejecutas desde Git Bash y ves errores de "find" o "timeout", ejecuta el script con `cmd.exe /C scrcpy_bass_cam.bat`.

## Cómo contribuir
- Añade issues para bugs o mejoras. Pull requests bienvenidos; usa CRLF en .bat si editas en Windows.

---

## Recursos
- Informe técnico: `informe_optimizacion.md` (pruebas, mediciones y recomendaciones avanzadas)
