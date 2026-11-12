# ONLINE y Wily Challenge: PC vs Android

## Flujo del juego (igual para ONLINE → PLAY y Wily Challenge)
1. `httpLevelGet(id, "TempLevels/<nombre>.mmlv")` → `GET /level/download/<id>` (con token) → el servidor responde con `location` (URL del CDN).
2. `httpLevelFileGet` → `http_get_file(location, "TempLevels/<nombre>.mmlv.gz")` descarga el nivel comprimido.
3. `objHTTPControl` (evento HTTP) → `gzip_unzip(gz, mmlv)`:
   `buffer_load` del `.gz` → `bufferInflate` (descomprimir) → `buffer_save_async` del `.mmlv`.
4. Validación: `ini_open(mmlv)` + `ini_read_string("Level", "1a")`. Si sale vacío → "DOWNLOADED CORRUPT LEVEL FILE".
5. `objLevelLoader.init`: tamaño con `file_bin_open/file_bin_size` → `buffer_load_async` → parseo → `ini_open` para los datos del nivel.
6. Subir niveles: `file_text_open_read` del `.mmlv` línea por línea.

`TempLevels/` es temporal: el juego la borra al arrancar (igual que en PC). Para conservar un nivel se usa **DOWNLOAD** en la tarjeta, que lo guarda en `Levels/` (MY LEVELS).

## Por qué falla en Android (comprobado con registros en la Odin)
| # | Paso | En PC | En Android | Corrección |
|---|------|-------|------------|------------|
| 1 | Descomprimir | `buffer_zlib_x64.dll` | La DLL no existe → "bufferZlibInflateRaw1 not set" | zlib nativo en `libmmgme.so`, llamado vía `GameMusicEmu_Read("Z:…")` |
| 2 | Ruta de la descarga | `async_load[?"result"]` relativa | Llega **absoluta** (`/data/user/0/…/files/…`) y `buffer_load` no la resuelve | Se recorta a ruta relativa en `objHTTPControl` |
| 3 | Buffer descomprimido | — | Mi buffer `buffer_grow` recibía los datos por memoria nativa y GameMaker lo daba por **vacío** → `buffer_copy` copiaba ceros → el `.mmlv` quedaba vacío | `buffer_fixed` del tamaño exacto |
| 4 | Guardado | `buffer_save_async` y luego `buffer_delete` | Borrar el buffer antes de terminar cancela el guardado y su evento | `buffer_save` síncrono + se mantiene vivo el buffer del guardado asíncrono |
| 5 | Leer INI del nivel | `ini_open` ve el archivo | `ini_open`, `file_text_*` y `file_bin_*` **transforman la ruta** (minúsculas, espacios→`_`) y no ven los archivos escritos con `buffer_*` | Niveles `.mmlv`: `buffer_load` + `ini_open_from_string` (`global.androidIniOpen`) |
| 6 | Tamaño en el cargador | `file_bin_size` | Devuelve 0 por el punto 5 → el nivel nunca termina de cargar | Tamaño con `buffer_load` |
| 7 | Subir nivel | `file_text_open_read` | Mismo problema del punto 5 | Lectura con `buffer_load` y separación de líneas |
| 8 | Perfil (MY PROFILE) | ID guardado al hacer login | El perfil se creó con el login saltado → ID = -1 → "user does not exist" | Se busca el ID por nombre al conectarse y se guarda en `Profile.ini` (ya funciona) |

## Pendiente de verificar
- Jugar un nivel de ONLINE y del Wily Challenge de principio a fin.
- DOWNLOAD a MY LEVELS y abrirlo desde la lista (`file_find_first` en `Levels/`).
- Subir un nivel.
- Quitar los registros temporales (`MMM gz`, `MMM loader`) cuando todo funcione.
