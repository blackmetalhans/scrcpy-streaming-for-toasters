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
BASS_CAM_final.bat                 # (duplicado histórico — considerar eliminar)
BASS_Cam_min.bat                   # (variantes, histórico)
setup_repo.sh                      # Script de bootstrap (Git Bash)
bin/                               # (no versionar) scrcpy.exe, adb.exe, DLLs
logs/                              # generados en la ejecución
```

Cómo encaja: El script principal es `scrcpy_bass_cam.bat`. `setup_repo.sh` es un ayudante para inicializar el repo en Git Bash y puede generar los `.bat` desde plantillas. Los binarios de scrcpy NO están versionados: se descargan en `bin/`.

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
pwsh .\\get_scrcpy_release.ps1
# o con parámetros: pwsh .\get_scrcpy_release.ps1 -OutDir bin
```

- En Git Bash / Linux/macOS (requiere curl + python):

```bash
./get_scrcpy_release.sh
```

3) Verifica que `bin/scrcpy.exe` y `bin/adb.exe` estén presentes (Windows) o que `scrcpy` esté en PATH en Linux.

4) Ejecuta:

```powershell
# Windows (desde Git Bash o CMD):
./scrcpy_bass_cam.bat
```

El script lanzará scrcpy apuntando a la cámara frontal (configurable al inicio del .bat). Cuando la ventana `BASS_CAM_RAW` esté activa, añádela a OBS como Window Capture → Windows Graphics Capture (WGC).

## Descargar scrcpy desde terminal (qué hace el helper)
He añadido dos utilidades:
- `get_scrcpy_release.ps1` — PowerShell: consulta la API de GitHub, descarga el release de scrcpy (asset Windows cuando exista) y lo extrae en `bin/`.
- `get_scrcpy_release.sh` — Shell: hace lo mismo usando curl + python.

Ambas scripts intentan resolver automáticamente el asset más apropiado y descomprimirlo en `bin/` para que `scrcpy_bass_cam.bat` funcione sin cambios.

## Configuración rápida (variables importantes)
Abre `scrcpy_bass_cam.bat` y revisa al inicio:
- `ADB_SERIAL` — serial del dispositivo o IP:PORT para TCP/IP
- `CAMERA_ID`, `CAM_SIZE`, `CAM_FPS` — parámetros de cámara
- `VIDEO_BITRATE`, `VIDEO_CODEC` — calidad de stream
- `CPU_AFFINITY_HEX` — máscara de afinidad de CPU

No es necesario editar el cuerpo del script: las variables principales están centralizadas.

## Sugerencias para limpieza del repo antes del primer release
- Eliminar o mover a `archive/` los archivos históricos/duplicados: `BASS_CAM_final.bat`, `BASS_Cam_min.bat` si no son necesarios.
- Asegurarse de que `bin/` no esté versionado y que `.gitignore` lo excluya (ya está configurado).
- Establecer `VERSION` (archivo añadido) y actualizar `CHANGELOG.md`.

## Preparar el primer release (manual)
1. Actualiza `VERSION` con el número (por ejemplo `0.1.0`).
2. Commit y push: `git add VERSION CHANGELOG.md README.md` → `git commit -m "chore: prepare v0.1.0"` → `git push`.
3. Crear la release en GitHub (UI o CLI): `gh release create v0.1.0 --title "v0.1.0" --notes-file CHANGELOG.md`.

Si quieres que yo cree los archivos de release (tag o changelog) automáticamente, puedo hacerlo si me das permiso para ejecutar operaciones adicionales o me indicas cómo quieres el versionado.

## Troubleshooting rápido
- Si `adb` no lista el dispositivo: revisa el diálogo de autenticación RSA en el teléfono y usa un cable USB que soporte datos.
- Si la ventana no aparece en OBS: confirma que `BASS_CAM_RAW` está abierta y que usas Window Capture → WGC.

---

Cambios realizados en el repo por mí:
- README.md actualizado para flujo de instalación y uso desde terminal.
- Añadidos: `get_scrcpy_release.ps1`, `get_scrcpy_release.sh`, `VERSION`, `CHANGELOG.md`.

Próximo paso: sugerirme si quieres que archive o elimine archivos concretos (`BASS_CAM_final.bat`, `BASS_Cam_min.bat`) y si quieres que cree la release en GitHub (necesitaré autorización o usarás `gh` localmente).
