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
