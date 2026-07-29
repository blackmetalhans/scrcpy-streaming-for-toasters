# Informe de optimización — pipeline scrcpy (cámara) + OBS + Reaper/ReaStream para "BASS_CAM"

**Fecha:** 29 de julio de 2026
**Alcance:** auditoría técnica del pipeline de video (Moto G06, Android 15, scrcpy vía USB) y audio (Reaper/ASIO4ALL/ReaStream) hacia OBS Studio, con foco en latencia, sync offset y estabilidad USB.

---

## 0. Lo que había en tu Google Drive

Se localizó la carpeta `scrcpy-streaming-for-toasters` en tu Drive y se leyó el contenido completo. Contiene el binario portable de scrcpy (v4.1, `scrcpy.exe`, `adb.exe`, DLLs de FFmpeg/SDL3, `scrcpy-server`) y **dos scripts reales**, no uno:

**`BASS_CAM.bat`** (el que describiste, 1.3 KB) — ya bastante más maduro de lo que el prompt original sugiere: ya hace `taskkill` de procesos huérfanos, `adb kill-server`/`start-server`, `adb wait-for-device`, lanza scrcpy con `start "BASS_CAM_DECODER" /high`, y **ya intenta fijar afinidad de CPU** a los cores 0-1 vía PowerShell (`$Process.ProcessorAffinity=3`) parseando el PID con `tasklist`. Los flags de scrcpy son exactamente los que describiste en el contexto: `--video-source=camera --camera-facing=front --camera-size=854x480 --camera-fps=25 --video-bit-rate=1500K --video-codec=h264 --render-driver=direct3d --stay-awake --no-audio --no-control --no-clipboard --window-title="BASS_CAM_RAW" --window-borderless`. Nota: `--stay-awake` no estaba en el resumen que diste pero sí está en el .bat real.

**`open_a_terminal_here.bat`** (504 B) — variante alternativa por TCP/IP: hace `adb kill-server`/`start-server`, `adb tcpip 5555`, `adb connect 10.72.11.235:5555` (IP fija de la interfaz RNDIS del hotspot) y lanza `scrcpy -e --max-size=1024 --video-codec=h264` sobre ese transporte. Esto confirma que ya probaste la vía TCP/RNDIS como respaldo — la referencio en la variante "fallback" del script final.

El archivo `Nuevo documento de texto.txt` está vacío (0 bytes) — no había notas adicionales. No se encontró ningún README dentro de la carpeta.

**Conclusión clave de este hallazgo:** tu script base ya resuelve el 70% de los puntos "básicos" del entregable B (kill de huérfanos, afinidad, `/high`). Lo que falta y se corrige abajo: validación de rutas/binarios, parseo real de `adb devices` (hoy el script confía ciegamente en `wait-for-device`, que se cuelga indefinidamente si el estado es `unauthorized` u `offline`), reintentos con backoff, logging a archivo, códigos de salida (`errorlevel`/`exit /b`), UTF-8, y — crítico — el flag `--video-buffer=0` explícito y el cálculo correcto de la máscara de afinidad para no pisar el hilo de ASIO ni el encoder de OBS.

---

## 1. Diagrama del pipeline con latencia por etapa

```
┌───────────────────────────── RUTA DE VIDEO ─────────────────────────────┐
│                                                                          │
│ [Sensor cámara frontal Moto G06]                                       │
│        │  captura HAL Camera2 (854x480@25fps)                          │
│        ▼                                                                │
│ [Encoder HW MediaTek H.264] ......................  ~15-40 ms          │
│   (sube con carga térmica: hotspot Wi-Fi + USB debug + captura activa) │
│        │                                                                │
│        ▼                                                                │
│ [scrcpy-server → socket ADB sobre USB] ............  ~5-15 ms          │
│   (USB 2.0 full pipe: video + adb shell + MTP compitiendo por ancho    │
│    de banda; empeora si hay hotspot RNDIS simultáneo)                  │
│        │                                                                │
│        ▼                                                                │
│ [scrcpy.exe: demux + decode H.264 (D3D11VA/HW)] ...  ~10-25 ms         │
│        │                                                                │
│        ▼                                                                │
│ [--video-buffer, default=0] .......................  +0 ms (si no se  │
│                                                        toca; NO subir)  │
│        │                                                                │
│        ▼                                                                │
│ [Render SDL --render-driver=direct3d, ventana BASS_CAM_RAW] .. ~5-16ms │
│        │  (depende de vsync del compositor de Windows)                 │
│        ▼                                                                │
│ [OBS: Window Capture vía WGC (Windows Graphics Capture)] ..... ~1 frame│
│   composited por DWM (~16.6 ms a 60Hz) + su propio pipeline de render  │
│        │                                                                │
│        ▼                                                                │
│ [Composición de escena OBS → encoder de salida]                        │
│                                                                          │
│   LATENCIA TOTAL DE VIDEO ESTIMADA: ~55-115 ms  (variable, con jitter  │
│   por USB compartido y throttling térmico del SoC)                     │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────── RUTA DE AUDIO ─────────────────────────────┐
│                                                                          │
│ [Bajo → PCM2902 USB interface] .................... conversión A/D     │
│        │                                                                │
│        ▼                                                                │
│ [ASIO4ALL, buffer=512 samples @48kHz] .............  ~10.7 ms (I/O     │
│                                                        ida, ver §4.1)   │
│        │                                                                │
│        ▼                                                                │
│ [Reaper: limitador de transitorios] ...............  ~1-3 ms (latency │
│                                                        del plugin)      │
│        │                                                                │
│        ▼                                                                │
│ [ReaStream TX → UDP 127.0.0.1, id "bass"] .........  ~1-5 ms (loopback,│
│                                                        overhead de red  │
│                                                        casi nulo en     │
│                                                        localhost)       │
│        │                                                                │
│        ▼                                                                │
│ [OBS: fuente ReaStream/audio, buffer interno de OBS] .. ~10-20 ms      │
│                                                                          │
│   LATENCIA TOTAL DE AUDIO ESTIMADA: ~25-40 ms                          │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

DESAJUSTE (drift/offset) = Latencia_video − Latencia_audio ≈ +30 a +75 ms
→ el VIDEO llega más tarde que el audio. Hay que RETRASAR el audio en OBS
  con Sync Offset POSITIVO (no negativo) para empatarlo con el video tardío.
```

Este orden de magnitud es consistente con la arquitectura documentada: scrcpy no aplica buffer de video por defecto ([doc/video.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/video.md)), mientras que ASIO4ALL a 512 samples/48kHz agrega ~10.7 ms de latencia de una vía según la propia documentación del proyecto ([ASIO4ALL — ASIO Buffer Size](https://asio4all.org/asio-buffer-size/)), y ReaStream sobre loopback UDP normalmente introduce retardo bajo pero no cero, según reportes de usuarios en el foro oficial de Cockos ([foro Cockos — ReaStream](https://forums.cockos.com/showthread.php?t=142183)).

---

## 2. Auditoría de flags de scrcpy: vigentes, obsoletos y mal usados

### 2.1 Buffering — el nombre correcto es `--video-buffer`

Tu prompt pregunta explícitamente cuál es el flag vigente entre `--video-buffer` y `--display-buffer`. Está confirmado en fuente primaria: **`--display-buffer` fue renombrado a `--video-buffer` en scrcpy v3.0** ([issue #5403 "Rename --XXX-buffer options"](https://github.com/Genymobile/scrcpy/issues/5403), [release notes v3.0](https://github.com/Genymobile/scrcpy/releases)). Como estás en v4.1 (según el .zip en tu Drive), **`--display-buffer` ya no existe**; usar `--video-buffer`.

Por defecto scrcpy **no aplica buffer de video** ("By default, there is no video buffering, to get the lowest possible latency" — [doc/video.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/video.md)). Es decir, tu configuración actual ya está en el mínimo de latencia posible en esa etapa; no hace falta setear `--video-buffer=0` porque es el default, pero es buena práctica dejarlo explícito en el script para que quede documentado y a prueba de cambios de default en futuras versiones.

### 2.2 Tabla de flags: válido / obsoleto / recomendado

| Flag | Estado en v4.1 | Nota | Fuente |
|---|---|---|---|
| `--video-source=camera` | ✅ Vigente | Requiere Android ≥12 (tenés Android 15, OK) | [doc/camera.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/camera.md) |
| `--camera-facing=front` | ✅ Vigente | — | [doc/camera.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/camera.md) |
| `--camera-size=854x480` | ⚠️ Vigente pero sin verificar | El valor puede no estar entre los tamaños declarados por el sensor; correr `--list-camera-sizes` primero (ver §2.3) | [doc/camera.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/camera.md) |
| `--camera-fps=25` | ✅ Vigente | Default es 30fps si se omite | [doc/camera.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/camera.md) |
| `--video-bit-rate=1500K` | ✅ Vigente | Default general es 8 Mbps; 1500K es razonable para 480p25 sobre USB compartido | [doc/video.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/video.md) |
| `--video-codec=h264` | ✅ Vigente (y es el default) | H264 da menor latencia que H265; correcto para este caso | [doc/video.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/video.md) |
| `--render-driver=direct3d` | ✅ Vigente | Valores válidos SDL: `direct3d`, `opengl`, `opengles2`, `opengles`, `metal`, `software`. **No existe `direct3d11`** como valor de este flag (es solo un hint a SDL) | [manpage Debian scrcpy](https://manpages.debian.org/unstable/scrcpy/scrcpy.1.en.html), [issue #1422](https://github.com/Genymobile/scrcpy/issues/1422) |
| `--stay-awake` | ✅ Vigente (está en tu .bat real, no en el resumen del prompt) | Solo mantiene despierto el device mientras está enchufado por USB — no funciona vía TCP/IP puro | [CHANGELOG histórico](https://github.com/Genymobile/scrcpy/releases) |
| `--no-audio` | ✅ Vigente | Correcto: el audio va por Reaper/ReaStream, no por scrcpy | [doc/camera.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/camera.md) |
| `--no-control` | ✅ Vigente | Reduce overhead de input, correcto para cámara de solo lectura | — |
| `--no-clipboard` | ❌ **NO EXISTE** — flag inválido | Verificado contra el manpage oficial: el único flag de clipboard es `--no-clipboard-autosync`. Además, con `--no-control` activo el clipboard ya está fuera de juego, así que el flag es **redundante y se elimina** del script | [scrcpy.1 (manpage oficial en el repo)](https://raw.githubusercontent.com/Genymobile/scrcpy/master/app/scrcpy.1) |
| `--window-title="BASS_CAM_RAW"` | ✅ Vigente | — | [doc/window.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/window.md) |
| `--window-borderless` | ✅ Vigente | Confirmado en doc/window.md actual | [doc/window.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/window.md) |
| `--display-buffer=N` | ❌ **Obsoleto desde v3.0** | Renombrado a `--video-buffer=N` | [issue #5403](https://github.com/Genymobile/scrcpy/issues/5403) |
| `--lock-video-orientation` | ❌ **Obsoleto desde v3.0** | Reemplazado por `--capture-orientation` (más robusto en Android ≥14) | [release notes v3.0](https://github.com/Genymobile/scrcpy/releases) |
| `--v4l2-sink` / `--v4l2-buffer` | ⚠️ Solo Linux | No aplica en Windows — requiere el módulo kernel `v4l2loopback`, inexistente en Windows | [doc/v4l2.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/v4l2.md) |
| `--no-video-playback` | ✅ Vigente, pero no aplica a tu caso | Solo tiene sentido combinado con `--record` o `--v4l2-sink`; si lo activás sin eso, no verías nada y OBS (con Window Capture) tampoco tendría ventana que capturar | [doc/video.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/video.md) |
| `--max-fps` | ✅ Vigente para display mirroring | Para cámara, el flag de frecuencia es `--camera-fps`, no `--max-fps` — usarlos juntos no tiene efecto documentado en modo cámara | [doc/camera.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/camera.md) |
| `--camera-high-speed` | ✅ Vigente, no recomendado aquí | Solo para combos resolución/fps específicos de "high speed capture" (p. ej. 1080p@240fps); tu sensor a 854x480/25fps no lo necesita | [doc/camera.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/camera.md) |
| `--capture-orientation` | ✅ Vigente | No usado en tu script; útil solo si necesitás espejar o rotar sin afectar el recorte | [doc/video.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/video.md) |
| `--angle` | ✅ Vigente | Rotación arbitraria en grados; no aplica a tu caso | [doc/video.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/video.md) |
| `--print-fps` | ✅ Vigente | Útil para diagnóstico de frame drops por throttling térmico (ver §4) | [doc/video.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/video.md) |
| `--time-limit` | ✅ Vigente | No aplica a un stream continuo; solo relevante para grabaciones acotadas | — |

### 2.3 `--camera-size=854x480`: verificar antes de asumir

El doc oficial es explícito: los tamaños que reporta la cámara son **declarativos, no garantizados** — "some of them are declared but not supported, while some others are not declared but supported" ([doc/camera.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/camera.md)). Antes de asumir que 854×480 funciona, correr:

```bat
scrcpy.exe --list-camera-sizes
```

Si 854×480 no aparece en la lista pero el stream igual funciona, no hay drama (el doc dice que tamaños arbitrarios pueden funcionar en algunos devices). Si falla o hay artefactos, usar en su lugar `--camera-ar=16:9 -m854` (selección automática por aspecto + ancho máximo) en vez de forzar el tamaño exacto — **pero atención**: `--camera-size` y `-m`/`--camera-ar` son **mutuamente excluyentes** ("If `--camera-size` is specified, then `-m`/`--max-size` and `--camera-ar` are forbidden" — [doc/camera.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/camera.md)). El script refactorizado incluye un modo de diagnóstico para esto.

---

## 3. Alternativas a la ventana de scrcpy + Window Capture

| Método | Latencia estimada | Costo CPU | Costo USB | Viable en Windows | Comentario |
|---|---|---|---|---|---|
| **scrcpy ventana + OBS Window Capture (WGC)** (actual) | Media (~55-115 ms, ver §1) | Medio (decode + render SDL + WGC) | Medio | ✅ | Buen balance; WGC es más eficiente que BitBlt y soporta HW-accel ([OBS KB — Window Capture Sources](https://obsproject.com/kb/window-capture-sources)) |
| `scrcpy --no-window` + pipe a ffmpeg/dshow virtual cam | Similar o algo menor (se ahorra un blit de ventana) | Similar | Igual | ⚠️ Complejo | scrcpy no expone un pipe de video nativo en Windows (eso es la función de `--v4l2-sink`, exclusivo de Linux — [doc/v4l2.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/v4l2.md)). Se necesitaría un fork/wrapper o herramienta de terceros; no vale la complejidad para el beneficio marginal |
| `adb exec-out screenrecord` + ffmpeg | Alta (varios cientos de ms) | Alto | Alto | ✅ pero mala idea | `screenrecord` es MediaRecorder de Android, pensado para grabar, no para baja latencia en vivo; además no soporta cámara, solo pantalla |
| DroidCam OBS plugin / Iriun | Media-alta, dependiente de red/USB del propio producto | Bajo-medio (delegan a su propio driver) | Variable | ✅ | Terceros, no auditables en código; pierdes el control fino de flags de scrcpy (bitrate, fps, HAL directo) que ya tenés funcionando |
| `adb forward` + ffmpeg dshow | Similar a la ventana pero sin el paso de renderizado SDL | Similar | Igual + overhead del forward | ⚠️ | `adb forward` añade otro salto TCP local sobre el mismo socket USB; no elimina el cuello de botella real que es el encoder HW + USB compartido |

**Recomendación:** mantener la arquitectura actual (scrcpy ventana + WGC). El cuello de botella real no es el "extra hop" de la ventana — es el encoder HW del teléfono y el bus USB compartido con hotspot. Cambiar de método de captura en el lado PC no ataca la causa raíz.

---

## 4. Causas del drift/desajuste y cómo corregirlo

### 4.1 Offset constante vs. drift acumulativo — son dos problemas distintos

Esto es lo más importante del informe y hay que separarlo bien:

**Offset constante:** un desfase fijo en ms que no cambia con el tiempo. Causa: suma de latencias fijas de cada etapa del pipeline (decode, render, composición). Se corrige una sola vez con **Sync Offset** en OBS y queda resuelto mientras no cambie la configuración de hardware/flags.

**Drift acumulativo (progresivo):** el desfase crece con el tiempo — a los 2 minutos están sincronizados, a los 20 minutos el audio ya se adelantó medio segundo. Esto **no se arregla con Sync Offset** (que es un valor fijo) porque la causa es un **mismatch de clock/sample rate entre dos relojes independientes que no están genlockeados**. Concretamente: si el PCM2902 corre su reloj interno a 44.1kHz (o a un 48kHz levemente desviado por su propio cristal) y OBS/Windows están trabajando el mixer a 48kHz, cada segundo real se acumula un pequeño error de resampleo. Con un audio interface USB clase barata (el PCM2902 es un chip genérico, no tiene reloj de precisión de estudio), esto es *exactamente* el patrón esperado. Evidencia de usuarios reportando el mismo síntoma con ReaStream+OBS en foros de Cockos, resuelto igualando sample rate en ambos lados ([Reddit r/obs — ReaStream crackling/latency issue](https://www.reddit.com/r/obs/comments/mw1k29/reastream_cracklinglatency_issue_with_obs/)).

**Fix del drift (no es Sync Offset, es configuración de sample rate):**
1. Reaper: Preferences → Audio → Device → confirmar que el proyecto y el ASIO device corren a **48000 Hz** (no 44100).
2. Windows: Panel de sonido → Propiedades del dispositivo PCM2902 → pestaña Avanzado → forzar **48000 Hz, 16 o 24 bit** como formato predeterminado (evita que el mixer de Windows resample por su cuenta).
3. OBS: Configuración → Audio → **Sample Rate = 48 kHz** (tiene que matchear con lo anterior).
4. Si el drift persiste después de igualar todos los sample rates nominales, el problema es el reloj físico del PCM2902 (jitter de cristal barato) — ahí no hay fix de software, solo mitigación: reiniciar la sesión de streaming cada X minutos, o migrar a una interfaz con reloj más preciso a mediano plazo.

### 4.2 Offset constante — receta de calibración empírica

Método de claqueta (clap test), adaptado a tu setup:

```
PASO 1 — Generar un evento sincronizable
  Con el stream de video y audio ya corriendo en OBS, dar una palmada frente
  a la cámara O tocar una nota de bajo muy corta y percusiva (transitorio de
  slap es ideal, ya lo tenés en el pipeline) mientras estás en el encuadre.

PASO 2 — Grabar unos segundos en OBS (Start Recording, no streaming)
  Grabar 10-15 segundos con 3-4 eventos de claqueta/slap espaciados.

PASO 3 — Analizar el archivo grabado cuadro por cuadro
  Abrir el .mkv/.mp4 resultante en cualquier editor con timeline por frame
  (DaVinci Resolve, o incluso VLC con avance cuadro a cuadro con la tecla E).
  Ubicar el frame exacto donde se ve el impacto visual (mano tocando cuerda /
  palmas juntándose) y el punto exacto de la forma de onda donde arranca el
  transitorio de audio.

PASO 4 — Calcular el delta en ms
  delta_ms = (frame_audio - frame_video) * (1000 / fps_de_grabación)
  Si el AUDIO aparece ANTES que el VIDEO (que es lo esperado en este pipeline,
  porque el video tiene que pasar por encoder HW + USB + decode + WGC, y el
  audio es casi directo), el delta es positivo.

PASO 5 — Aplicar en OBS
  Clic derecho sobre la fuente de audio (ReaStream) en el Mixer → Propiedades
  de Audio Avanzadas → Sync Offset (ms) → ingresar el delta calculado en
  PASO 4 como valor POSITIVO. Un Sync Offset positivo en OBS RETRASA esa
  fuente de audio — que es justo lo que necesitás porque el audio llega
  antes que el video tardío.

PASO 6 — Verificar
  Repetir la grabación de claqueta con el offset aplicado; el delta debería
  acercarse a 0 ms. Si sobra o falta, ajustar en pasos de 5-10 ms.
```

Nota sobre la dirección del offset: en la documentación de OBS, el campo **Sync Offset (ms)** en Advanced Audio Properties es específico por fuente y un valor positivo demora esa fuente — confirmado en múltiples hilos del foro oficial de OBS sobre su comportamiento y troubleshooting ([OBS Forums — Audio Sync Offset](https://obsproject.com/forum/threads/audio-sync-offset-not-working.125660/), [OBS Forums — tag sync-offset](https://obsproject.com/forum/tags/sync-offset/)). Como en tu pipeline el video es la señal tardía, **la fuente que hay que retrasar es el audio**, con offset positivo — exactamente lo que pide la tarea.

### 4.3 Alternativa: retrasar el video en vez del audio

Si por algún motivo preferís no tocar el offset de audio (p. ej. porque el mismo ReaStream alimenta otra escena donde el timing sí importa), OBS tiene un filtro dedicado a esto que se aplica **sobre la fuente de video**, no de audio:

- **Render Delay** (antes conocido informalmente como "Video Delay") — filtro que retrasa el renderizado de una fuente en ms, pensado explícitamente para sincronizar webcam con micrófono ("Useful for getting webcam image in sync with microphone audio" — [OBS KB — Render Delay Filter](https://obsproject.com/kb/render-delay-filter)). Se agrega como filtro sobre la fuente Window Capture (BASS_CAM_RAW) → Delay en ms.

En tu caso concreto, como el video es la señal *tardía*, retrasar el video con Render Delay **no soluciona nada** — empeoraría el desfase. Este filtro sería útil solo si en algún momento cambiás de arquitectura y el audio pasa a llegar más tarde que el video (por ejemplo si metés más procesamiento de Reaper en la cadena). Se documenta acá para que quede claro cuál filtro usar según el escenario, tal como pide la tarea.

### 4.4 Por qué NO conviene subir `--video-buffer`

Subir `--video-buffer` (por ejemplo a 50-200ms) fue diseñado para **compensar jitter de red/USB y suavizar reproducción** cuando hay variabilidad de llegada de paquetes ("Buffering can be added to delay the video stream and compensate for jitter to get a smoother playback" — [doc/video.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/video.md), issue original [#2464](https://github.com/Genymobile/scrcpy/issues/2464)). Pero:

1. **No corrige lip-sync** — solo agrega latencia fija adicional a una señal que ya llega tarde respecto al audio. Empeora el offset, no lo arregla.
2. **No corrige drift** — el drift es un problema de clocks, no de buffering; un buffer fijo en ms no puede compensar una deriva progresiva de sample rate.
3. Es una herramienta para **jitter**, no para **sync**. Tu USB ya es relativamente estable (conexión física, no wifi), así que el jitter no es tu problema principal — tu problema es offset (arreglable con Sync Offset) y potencial drift térmico (arreglable con sample rate + gestión térmica, ver §5).

La única razón legítima para tocar `--video-buffer` en tu setup sería si `--print-fps` muestra micro-cortes/jitter visibles por saturación momentánea del bus USB (hotspot + MTP + scrcpy compitiendo) — en ese caso un buffer pequeño (20-40ms) puede suavizar sin agregar demasiada latencia. Pero el fix correcto de raíz es reducir la carga del bus (ver §5), no enmascararla con buffer.

---

## 5. USB, MTP, hotspot y throttling térmico

### 5.1 MTP vs "Solo carga" con depuración USB

MTP (Media Transfer Protocol) mantiene un canal adicional de transferencia de archivos activo sobre el mismo bus USB, con su propio overhead de protocolo (enumeración de "dispositivo de almacenamiento", polling de metadata). Como scrcpy/adb ya usan el bus para el socket de control + video, tener MTP activo simultáneamente compite por el mismo ancho de banda y puede introducir micro-stalls. **Recomendación: cambiar el modo de conexión USB del teléfono a "Solo carga" (o "Sin transferencia de datos") con la depuración USB igual activa** — el modo de conexión de archivos (MTP/PTP) es independiente del daemon ADB, que corre sobre su propio interfaz USB (adb interface), así que apagar MTP no afecta la depuración ni scrcpy, solo libera ancho de banda del bus para el stream de cámara.

### 5.2 USB 2.0 vs 3.0

A 854×480@25fps con bitrate de 1500 Kbps, el consumo real de ancho de banda del stream de video es trivial (~190 KB/s) comparado con la capacidad de USB 2.0 (~35-40 MB/s efectivos). El cuello de botella **no es ancho de banda de bus** en este perfil de bitrate — es la combinación de: overhead de protocolo ADB (empaquetado en chunks, ACKs), MTP si está activo, y la interfaz RNDIS del hotspot compartiendo el mismo controlador físico USB si el teléfono está en modo "hotspot vía USB" además de cable de datos. Confirmá con el Administrador de Dispositivos de Windows si el teléfono aparece bajo un controlador USB 3.0 (azul) — si no, no hay ganancia práctica en forzarlo dado el bitrate bajo que usás.

### 5.3 Efecto térmico del hotspot sobre el encoder HW

Este es el punto más importante de esta sección y el que más probablemente explica variabilidad/drift que observás en sesiones largas: el hotspot Wi-Fi usa el mismo SoC (radio + CPU) que corre el encoder de hardware de video. Bajo carga combinada (hotspot activo + encoder H.264 corriendo + depuración USB + posible carga del cable), es común que el gobernador térmico de un MediaTek de gama media reduzca el clock del bloque de video (throttling), lo que se traduce en **frame drops intermitentes** — y frame drops irregulares en el origen son percibidos aguas abajo como jitter/drift, aunque el reloj de audio esté perfecto. Diagnóstico: correr `scrcpy --print-fps` y loguear la salida; si el FPS reportado cae por debajo de 25 en sesiones largas (>15-20 min) de forma correlacionada con el uso del hotspot, es throttling térmico, no un problema de OBS ni de ReaStream.

**Mitigaciones prácticas:**
- Bitrate/fps realistas para este SoC en esas condiciones: mantener 854×480@25fps con 1500 Kbps es razonable; **no subir a 30fps ni a 720p** mientras el hotspot esté activo simultáneamente — la carga combinada crece más que linealmente.
- Ventilación física del teléfono (evitar carcasas gruesas, no dejarlo en superficie que retenga calor).
- Si el throttling persiste, considerar reservar el hotspot para el momento de setup y luego, si el flujo de trabajo lo permite, apagarlo durante el stream (reduce la carga del SoC significativamente).

---

## 6. Configuración de OBS para baja latencia — checklist exacto

| Ajuste | Ubicación en OBS | Valor recomendado | Motivo |
|---|---|---|---|
| Capture Method | Window Capture (BASS_CAM_RAW) → Propiedades | **Windows Graphics Capture (WGC)**, no BitBlt | WGC soporta HW-accel y es más eficiente para ventanas con render Direct3D como scrcpy; BitBlt es legado y no funciona bien con contenido acelerado por GPU ([OBS KB — Window Capture Sources](https://obsproject.com/kb/window-capture-sources), [OBS Forums — BitBlt vs WGC](https://obsproject.com/forum/threads/for-capture-method-whats-the-difference-between-bitblt-and-windows-graphics-capture.127687/)) |
| Capture Cursor | Window Capture → Propiedades | **Off** | No hay cursor de mouse relevante en la ventana de cámara; ahorra trabajo de composición ([OBS KB — Window Capture Sources](https://obsproject.com/kb/window-capture-sources), default es On, así que hay que desactivarlo explícitamente) |
| "Use Buffering" | Solo existe en fuentes **Video Capture Device** (webcams UVC), no en Window Capture | N/D para tu setup | Tu fuente es Window Capture, no Video Capture Device — esta opción no aplica; si en el futuro migrás a una virtual cam expuesta como "device", ahí sí revisar este toggle y dejarlo OFF para mínima latencia |
| Sync Offset (ms) | Mixer → fuente de audio ReaStream → ⚙ → Advanced Audio Properties | **Valor positivo calibrado empíricamente** (ver §4.2) | Retrasa el audio para empatar con el video tardío |
| Monitoring | Advanced Audio Properties → fuente ReaStream | **Monitor Off** (o "Monitor Only" solo si necesitás cue en vivo, nunca "Monitor and Output" para evitar eco doble) | Evita duplicar la señal y latencia añadida por el monitor de OBS |
| Sample Rate | Configuración → Audio → Sample Rate | **48 kHz**, igual que Windows y Reaper | Evita resampleo cruzado que causa drift acumulativo (ver §4.1) |
| Render Delay filter | Filtros de la fuente Window Capture | **No aplicar** en este pipeline (el video ya es la señal tardía) | Ver §4.3 — usar solo si el escenario se invierte |
| Force SDR / color space | Configuración de la fuente de video / Advanced | Sin cambios necesarios para este caso (cámara SDR estándar) | No hay indicios de que el sensor entregue HDR; no aplica |

---

## 7. Resumen ejecutivo de recomendaciones

1. **Renombrar `--display-buffer` → `--video-buffer`** si en algún momento agregás ese flag (hoy no está en tu script, pero quedó aclarado por si lo viste en foros viejos).
2. **Agregar `--video-buffer=0` explícito** al .bat como documentación de intención, aunque sea el default.
3. **Correr `scrcpy --list-camera-sizes` una vez** para confirmar que 854×480 es válido para el sensor del Moto G06; si no aparece, usar `--camera-ar=16:9 -m854` en su lugar (nunca junto con `--camera-size`).
4. **Igualar sample rate a 48kHz en Windows, Reaper y OBS** — esto es más importante que cualquier ajuste de buffer para el problema de drift.
5. **Calibrar Sync Offset con clap test**, aplicando un valor **positivo** sobre la fuente de audio ReaStream (retrasa el audio, que llega antes que el video).
6. **Desactivar MTP, dejar "Solo carga" + depuración USB.**
7. **Monitorear con `--print-fps`** para detectar throttling térmico correlacionado con el hotspot.
8. **Mantener WGC como capture method**, Capture Cursor off.
9. **Eliminar `--no-clipboard`** del .bat: no existe en scrcpy (el flag real es `--no-clipboard-autosync`) y con `--no-control` es redundante de todas formas. Según cómo parsee tu build, un flag desconocido puede hacer que scrcpy aborte al arranque.
10. **Usar `start /affinity <hex>` nativo** en vez del parche por PID con PowerShell: elimina la race condition del script original (si scrcpy moría en el handshake de cámara, la afinidad nunca se aplicaba y no te enterabas).
11. **Afinidad de CPU**: separar scrcpy de los hilos de ASIO/Reaper y del encoder de OBS (detalle completo y tabla de máscaras en el script — ver `scrcpy_bass_cam.bat`).

---

### Fuentes primarias consultadas

- [scrcpy — doc/video.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/video.md)
- [scrcpy — doc/camera.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/camera.md)
- [scrcpy — doc/window.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/window.md)
- [scrcpy — doc/audio.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/audio.md)
- [scrcpy — doc/v4l2.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/v4l2.md)
- [scrcpy — doc/connection.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/connection.md)
- [scrcpy — doc/shortcuts.md](https://raw.githubusercontent.com/Genymobile/scrcpy/master/doc/shortcuts.md)
- [scrcpy — Releases (GitHub)](https://github.com/Genymobile/scrcpy/releases)
- [scrcpy — issue #5403, rename de flags de buffer](https://github.com/Genymobile/scrcpy/issues/5403)
- [scrcpy — issue #2464, origen del buffering](https://github.com/Genymobile/scrcpy/issues/2464)
- [scrcpy — issue #1422, render-driver direct3d vs opengl uso de CPU](https://github.com/Genymobile/scrcpy/issues/1422)
- [manpage Debian de scrcpy — valores válidos de --render-driver](https://manpages.debian.org/unstable/scrcpy/scrcpy.1.en.html)
- [OBS KB — Window Capture Sources](https://obsproject.com/kb/window-capture-sources)
- [OBS KB — Render Delay Filter](https://obsproject.com/kb/render-delay-filter)
- [OBS KB — Filters Guide](https://obsproject.com/kb/filters-guide)
- [OBS Forums — BitBlt vs WGC](https://obsproject.com/forum/threads/for-capture-method-whats-the-difference-between-bitblt-and-windows-graphics-capture.127687/)
- [OBS Forums — Audio Sync Offset behavior](https://obsproject.com/forum/threads/audio-sync-offset-not-working.125660/)
- [OBS Forums — tag sync-offset](https://obsproject.com/forum/tags/sync-offset/)
- [Reddit r/obs — ReaStream crackling/latency con OBS](https://www.reddit.com/r/obs/comments/mw1k29/reastream_cracklinglatency_issue_with_obs/)
- [Foro Cockos — ReaStream, latencia y uso](https://forums.cockos.com/showthread.php?t=142183)
- [ASIO4ALL — ASIO Buffer Size](https://asio4all.org/asio-buffer-size/)
- [Stack Overflow — start /AFFINITY, máscara hexadecimal](https://stackoverflow.com/questions/7759948/set-affinity-with-start-affinity-command-on-windows-7)
