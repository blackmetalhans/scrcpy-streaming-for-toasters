# scrcpy-bass-cam

Pipeline de streaming de baja latencia: **Moto G06 (Android 15, cámara frontal HAL) → scrcpy → OBS Studio**, con audio de bajo eléctrico sincronizado vía **Reaper + ASIO4ALL + ReaStream**.

Origen: refactor del script `BASS_CAM.bat` original (carpeta de Google Drive `scrcpy-streaming-for-toasters`). Ver [`informe_optimizacion.md`](./informe_optimizacion.md) para el análisis técnico completo (flags, latencias por etapa, calibración de sync offset).

## Estructura de carpetas sugerida para el repo

```
scrcpy-bass-cam/
├── README.md
├── LICENSE
├── .gitignore
├── informe_optimizacion.md
├── scrcpy_bass_cam.bat              # script principal (camara vía USB/HAL)
├── scrcpy_bass_cam_fallback_tcp.bat # variante "solo pantalla" / TCP-RNDIS
├── bin/                             # binarios de scrcpy (NO versionar, ver .gitignore)
│   ├── scrcpy.exe
│   ├── adb.exe
│   ├── scrcpy-server
│   ├── *.dll
│   └── LICENSE.txt                  # licencia propia de scrcpy (Apache 2.0)
└── logs/                            # logs timestamped generados en cada corrida
```

## Requisitos

- Windows 10/11.
- [scrcpy](https://github.com/Genymobile/scrcpy) v3.0+ (probado con v4.1) — Apache License 2.0.
- Android 12+ en el dispositivo para mirroring de cámara (`--video-source=camera`); Moto G06 con Android 15 cumple sin problema ([doc/camera.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/camera.md)).
- Depuración USB habilitada en el teléfono.
- OBS Studio con soporte de Window Capture / Windows Graphics Capture (Windows 10 1903+).
- Reaper + ASIO4ALL + interfaz de audio USB (para la ruta de audio, fuera del alcance de este script).

## Uso

1. Conectar el teléfono por USB, autorizar el diálogo de depuración si aparece.
2. Ejecutar `scrcpy_bass_cam.bat`.
3. En OBS, agregar/confirmar la fuente **Window Capture** apuntando a la ventana `BASS_CAM_RAW`, método de captura **Windows Graphics Capture (WGC)**.
4. Calibrar el **Sync Offset** de la fuente de audio (ReaStream) una vez, siguiendo la receta de claqueta en `informe_optimizacion.md` sección 4.2.
5. Al terminar, cerrar la consola del .bat (o Ctrl+C) para disparar la limpieza automática de procesos.

Si el USB falla o necesitás mirroring de pantalla completa como respaldo, usar `scrcpy_bass_cam_fallback_tcp.bat` (requiere haber emparejado el teléfono por USB al menos una vez para activar el listener TCP, y conocer la IP RNDIS del hotspot — ver comentarios en el propio script).

## Configuración editable

Todas las variables relevantes (rutas, tamaño/fps de cámara, bitrate, máscara de afinidad de CPU, reintentos ADB) están centralizadas al inicio de `scrcpy_bass_cam.bat` — no hace falta tocar el resto del script para ajustes de uso normal.

### Afinidad de CPU

El script fija afinidad de proceso para que scrcpy no compita por core con el hilo de callback de ASIO4ALL ni con el encoder de OBS. Ver la tabla completa de máscaras hexadecimales dentro de `scrcpy_bass_cam.bat` (sección 7). Regla general: reservar cores separados para scrcpy, Reaper/ASIO y OBS en máquinas de 6+ cores físicos.

## Tabla de latencias (referencia, ver informe completo para detalle y fuentes)

| Etapa | Latencia estimada |
|---|---|
| Captura + encoder HW (Moto G06) | ~15-40 ms |
| Transporte USB (scrcpy-server → PC) | ~5-15 ms |
| Decode en PC (scrcpy.exe) | ~10-25 ms |
| Render ventana (direct3d) + WGC | ~1 frame de composición (~16.6 ms a 60Hz) |
| **Total video** | **~55-115 ms** |
| ASIO4ALL @ 512 samples / 48kHz | ~10.7 ms |
| Reaper (limitador) + ReaStream (loopback UDP) | ~2-8 ms |
| Buffer interno de audio en OBS | ~10-20 ms |
| **Total audio** | **~25-40 ms** |

El video llega sistemáticamente más tarde que el audio; corregir con **Sync Offset positivo** sobre la fuente de audio en OBS (no con `--video-buffer`, que no soluciona offset ni drift — ver `informe_optimizacion.md`).

## Troubleshooting

| Síntoma | Causa probable | Fix |
|---|---|---|
| El script se cuelga en "esperando dispositivo" | Depuración USB no autorizada, cable de solo carga, o driver USB del teléfono no instalado | Revisar el diálogo de autorización en la pantalla del teléfono; probar otro cable/puerto |
| `adb devices` muestra `unauthorized` | Diálogo de autorización RSA no aceptado | Aceptar el diálogo en el teléfono; si no aparece, revocar autorizaciones USB en Opciones de desarrollador y reconectar |
| `adb devices` muestra `offline` | Estado inconsistente del daemon | El script reintenta automáticamente; si persiste, desconectar/reconectar el cable físicamente |
| Video con jitter/microcortes en sesiones largas | Throttling térmico del SoC por hotspot + encoder simultáneos | Ver `informe_optimizacion.md` sección 5.3; monitorear con `scrcpy --print-fps` |
| Audio se desincroniza progresivamente (no es un offset fijo) | Mismatch de sample rate/clock entre PCM2902, Windows y OBS | Igualar todo a 48kHz (interfaz, Windows, Reaper, OBS) — ver sección 4.1 del informe |
| `--camera-size=854x480` no inicia o da error | Tamaño no soportado por el sensor en ese modo | Correr `scrcpy --list-camera-sizes` y ajustar, o usar `--camera-ar` + `-m` (nunca junto con `--camera-size`) |
| Ventana no aparece en Window Capture de OBS | Ventana cerrada antes de que OBS refresque la lista, o filtro de cursor activo con foco robado | Reabrir el picker de fuente en OBS; confirmar `--window-title` coincide exactamente |
| `--display-buffer` no reconocido / error de flag | Flag obsoleto desde scrcpy v3.0 | Usar `--video-buffer` (ver [changelog scrcpy](https://github.com/Genymobile/scrcpy/releases)) |

## .gitignore sugerido

```gitignore
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
```

## Licencia

Este repo (scripts `.bat` y documentación) se publica bajo **MIT License** — libre uso, modificación y redistribución con atribución.

scrcpy en sí (binarios en `bin/`) se distribuye bajo **Apache License 2.0** ([Genymobile/scrcpy](https://github.com/Genymobile/scrcpy)); el archivo `LICENSE.txt` dentro de la carpeta de binarios corresponde a esa licencia y debe mantenerse junto a los ejecutables si se redistribuyen.

## Fuentes técnicas

Ver la lista completa de fuentes primarias citadas (documentación oficial de scrcpy y OBS Studio, foros de Cockos/ASIO4ALL) en [`informe_optimizacion.md`](./informe_optimizacion.md#fuentes-primarias-consultadas).
