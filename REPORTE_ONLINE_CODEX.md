# Reporte para Codex: niveles ONLINE / Wily Challenge no cargan en Android

Proyecto: `Documents/Codex/2026-11-10/pod` · Build: `work/build_megamaker.ps1` (genera `work/ui-test.apk`)
Parches GML: `work/patch_startup.py` → `work/android-gml/*.gml` (se compilan con UTMT CLI sobre `work/windows-original/data.win`)
Helpers Android: `work/android_ui.gml`, `work/android_touch.gml`, `work/android_editor.gml`
Nativo (música + zlib): `work/music/gme_bridge.cpp`, `work/music/com/company/game/GameMusicEmu.java`
Dispositivo de prueba: AYN Odin 3 (adb serial `1234cf8d`). Logs: `adb logcat | grep "MMM "`

## Síntoma
ONLINE → FIND LEVELS → un nivel → PLAY (o Wily Challenge → PLAY):
"AN ERROR OCCURED: UNDEFINED RESPONSE FROM SERVER" (antes: "DOWNLOADED CORRUPT LEVEL FILE" o "LOADING LEVEL..." infinito).

## Lo que YA funciona (verificado con logs en la Odin)
1. Login, lista de niveles, perfil: OK.
2. `GET /level/download/<id>` → 200, `http_get_file(<cdn>.mmlv.gz)` → 200.
3. Descompresión gzip (la DLL de Windows se reemplazó por zlib nativo vía `GameMusicEmu_Read("Z:addr:off:len")` / `("C:addr")`): OK, p. ej. 27.963 → 191.773 bytes.
4. `buffer_save(b2, "TempLevels/<nombre>.mmlv")` síncrono: OK (log `MMM gz saved ... bytes=191773`).

## El fallo exacto (log real, 2026-11-10 08:10)
```
08:10:41.830  MMM gz saved TempLevels/swap on hornet roll -kaizo-.mmlv bytes=30332
08:10:42.195  MMM ini TempLevels/swap on hornet roll -kaizo-.mmlv bytes=1 1a=<none>
```
En 0,36 s el archivo del nivel pasa de **30.332 bytes a 1 byte**. Luego el cargador no encuentra la clave `1a` (nombre del nivel) y `objLevelLoader` pone `global.httpError = "Undefined response from server"` (Create_0, ~línea 688: nombre == "LEVEL NAME").

## Prueba de API de archivos en la Odin (descarta problemas de rutas)
Escribiendo con `buffer_save` y leyendo inmediatamente, **todo funciona** con espacios, mayúsculas y subcarpetas:
`file_exists=1  buffer_load=39  file_bin=39  file_text='[Level]'  ini=Diag Level`
=> No es un problema de rutas ni de mayúsculas. Algo **sobrescribe** el archivo después de guardarlo.

## Hipótesis principal (no probada todavía)
`objLevelLoader` Create_0, función `init`:
```gml
buffer = buffer_create(1, buffer_grow, 1);          // en Create
...
var file = file_bin_open(filenameLoading, 0);
var size = file_bin_size(file);
file_bin_close(file);
loadid = buffer_load_async(buffer, filenameLoading, 0, size);
```
El archivo queda en **1 byte** = el tamaño de ese `buffer`. Sospecha: en este runner Android (GameMaker 2024.14, `libyoyo.so`) `buffer_load_async` sobre ese buffer de 1 byte termina **escribiendo** el archivo (o lo trunca al tamaño del buffer) en vez de leerlo. Coincide con un intento anterior donde `buffer_save_async` también dejó el archivo en 1 byte.

### Corrección propuesta
Cargar síncrono en `objLevelLoader.init` y saltar el evento asíncrono:
```gml
buffer_delete(buffer);
buffer = buffer_load(filenameLoading);
bufferLoaded = true;
status = 2;            // igual que objLevelLoader_Other_72 en caso de éxito
loadid = undefined;
```
(En `patch_startup.py` añadir un `replace_ws("gml_Object_objLevelLoader_Create_0", ...)` sobre el bloque de `file_bin_open ... buffer_load_async`.)
Revisar también otros `buffer_load_async` / `buffer_save_async` del juego (p. ej. `gzip_create` para subir niveles) por el mismo problema.

## Cambios ya aplicados en este flujo (en `patch_startup.py`)
- `bufferInflate` reescrito: zlib nativo, resultado en `buffer_fixed` (con `buffer_grow` GameMaker lo daba por vacío y `buffer_copy` copiaba ceros).
- `gzip_unzip`: `buffer_save` síncrono, sin `buffer_save_async`; devuelve `-999`.
- `objHTTPControl_Other_62`: ruta del `.gz` recortada a relativa (Android devuelve `/data/user/0/.../files/...`); `unzippingGZIP = false` directo.
- `ini_open(<variable>)` de niveles → `global.androidIniOpen` (lee con `buffer_load` + `ini_open_from_string`) — puede revertirse si la hipótesis anterior lo resuelve.
- Perfil: el ID de usuario se recupera por nombre al conectarse (`global.androidRepairUserId`).
- Logs temporales: `MMM gz`, `MMM ini`, `MMM id` (quitar al terminar).

## Cómo reproducir
1. `powershell -ExecutionPolicy Bypass -File work\build_megamaker.ps1 -Out work\ui-test.apk`
2. `adb -s 1234cf8d install -r work\ui-test.apk`
3. En el juego: PLAY → ONLINE (inicia sesión solo si REMEMBER ME está activo) → PLAY → FIND LEVELS → cualquier nivel → PLAY.
4. `adb -s 1234cf8d logcat | grep "MMM "`
