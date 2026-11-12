# Mega Maker Android — Pendientes

Build actual: `outputs/Mega Maker.apk` · Compilar: `work/build_megamaker.ps1`

## 2026-11-12: SCREEN con estirado (hecho, falta probar en un nivel)
- [x] ORIGINAL / 4:3 / 16:9 / FULL estiran la imagen de 256×224 (`global.androidScreenRect` en `work/android_ui.gml`). La cámara ya no se ensancha, así que desaparecen los errores del modo ancho.
- [x] Escalado nítido (entero + suavizado) para que los píxeles salgan parejos (`global.androidSharpSurf`).
- [x] Menús y editor siguen en 8:7 (los paneles del editor viven en las barras laterales).
- [x] Icono: el launcher del Odin lo recorta en círculo; arte al 58/108 sobre fondo de rayas, sin cortar las letras (`work/apply_launcher_icon.py`, aplicado también a `work/base-v1.apk`; original en `work/base-v1-before-icon72.apk`).
- [ ] Probar los 4 modos dentro de un nivel en el Odin (y controles táctiles en FULL).
- Código para GitHub: JayElDragon/Mega-Maker-Android (lista blanca en `.gitignore`).

## 0. Decisión tomada (2026-11-10): widescreen solo en el gameplay (sustituido por el estirado del 2026-11-12)
FULL WIDE se queda como opción de SCREEN, pero **solo para jugar los niveles**.
Menús y editor vuelven a 8:7 con relleno difuminado a los lados (sin bordes negros).
Cómo hacerlo (no aplicado todavía):
- [ ] En `work/android_ui.gml`, `global.androidRoomMode`: quitar el bloque `if (global.androidScreenMode == 4) return 4;` para que todos los modos apliquen solo en `rmPlayLevel`.
- [ ] En `work/patch_startup.py`: quitar el bloque final "FULL WIDE menus: draw the menu's grid background" (ya no hace falta).
- [ ] Compilar, probar menú y nivel en FULL WIDE y copiar a `outputs/`.
- [ ] Enfocar el tiempo en Online, Wily Challenge y guardar/cargar en el editor.
- [ ] Editor ancho: mejora futura (es donde el espacio extra sí sirve).

### SCREEN con relaciones de aspecto (pedido 2026-11-10)
En OPTIONS → VIDEO/SOUND → SCREEN, **solo estas cuatro opciones** (reemplazan PIXEL / 4:3 / FIT / FULL WIDE / STRETCH):
- [ ] **ORIGINAL**: proporción original del juego (8:7, 256×224), centrada.
- [ ] **4:3**: formato clásico.
- [ ] **16:9**: widescreen.
- [ ] **FULL**: se adapta a toda la pantalla del dispositivo.
- [ ] Se permite estirar la imagen para llegar a cada proporción (lo confirmó el usuario).
- [ ] Guardar la opción en `Settings.ini` (`ScreenSize`) y mostrar el nombre en el menú (en `work/android_ui.gml`: `global.androidScreenNames`, `androidNextScreen`, `androidPostDraw`).

### Revertir cambios (pedido 2026-11-10)
- [ ] Revertir los cambios de widescreen en los menús (FULL WIDE en menús, relleno del fondo del menú) para volver a la versión de menús en 8:7. Confirmar con el usuario qué cambios exactamente antes de hacerlo.

Con esta decisión, del punto 1 solo siguen vigentes: pausa a pantalla completa y layout de los niveles en las distintas proporciones.

## 1. Widescreen (plan original, sustituido por el punto 0)
- [ ] **Bordes del menú en FULL WIDE**: el cuadriculado (`getBgTitle()`) ya se dibuja a los lados desde `objMainMenu` Draw, pero las estrellas/decoraciones de la intro siguen asomando porque esos objetos se dibujan encima. Falta averiguar qué los dibuja y taparlos u ocultarlos en el menú.
- [ ] **No usar `draw_clear` en Draw Begin**: deja toda la pantalla negra en este runner. Buscar otra forma de limpiar restos de menús anteriores (p. ej. una capa de fondo de color sólido por sala).
- [ ] **Revisar que no queden menús anteriores** en todas las transiciones: Main Menu → Load Level → Online → Back → My Levels → Back → Examples → Back → New Level → Editor → Pausa → Main Menu.
- [ ] **Pantallas de carga y submenús** (Options, Online, My Levels, Examples) a pantalla completa.
- [ ] **Pausa a pantalla completa**: implementada (lados rellenos con los bordes del fondo de pausa), sin confirmar en la Odin.
- [ ] **Editor en widescreen** (según tus instrucciones):
  - cámara ancha (más nivel visible);
  - permitir colocar piezas en los lados (la condición de colocación usa `global.viewX + global.viewWidth`);
  - `builderDeactivateOutOfView` con el ancho real;
  - paneles táctiles como overlay en los bordes.
- [ ] **Layout responsivo** para 16:9, 19.5:9, 20:9, 21:9 (respetando cutouts y barra de navegación).

## 2. Online y Wily Challenge
- [x] Descompresión gzip: reemplacé la DLL de Windows por zlib de Android (vía `GameMusicEmu_Read` con prefijos `Z:` / `C:`).
- [x] Ruta del archivo descargado: se pasa relativa en lugar de absoluta.
- [ ] **El nivel se queda en "LOADING LEVEL…"**: el `.mmlv` descomprimido nunca aparece en `TempLevels/`. Siguiente paso: poner registros dentro de `gzip_unzip` y `bufferInflate` para ver si falla la lectura, la descompresión o el guardado (`buffer_save_async`).
- [ ] Subir niveles (`gzip_create` usa deflate de la DLL; falta reemplazarlo).

## 2b. Perfil del usuario
- [ ] **El perfil del usuario da error** (EXTRAS → PROFILE). Reportado el 2026-11-10, sin investigar. Siguiente paso: abrirlo en la Odin, capturar la pantalla y revisar el log (`adb logcat | grep "MMM Android"`).

## 3. Editor táctil (sin probar)
- [ ] SAVE (corregido el error de `canUseSave`, falta probarlo).
- [ ] SELECT.
- [ ] Mantener presionado = borrar.
- [ ] Arrastrar con dos dedos y pellizcar para el mapa.
- [ ] Probar guardar y cargar un nivel propio y abrir niveles del PC.

## Ya funciona
Música, icono, login, REMEMBER ME, teclado Android, X para salir de cuadros, paleta, toques de menú, FULL WIDE en niveles, cámara centrada, TOUCH ON/OFF, editor táctil (PLACE/ERASE/MOVE/PLAY/UNDO/REDO/RECENT/FAVORITES).
