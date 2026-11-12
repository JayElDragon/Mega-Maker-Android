# Mega Maker para Android

Port no oficial de **Mega Man Maker 1.10.5.4** (GameMaker) a Android, hecho para la AYN Odin 3.

El APK se descarga de la sección **Releases** del repositorio.

## Qué incluye el port
- Controles táctiles en pantalla (se apagan en OPTIONS > OTHER > TOUCH) y soporte para mando de Xbox.
- Editor de niveles táctil: PLACE / ERASE / MOVE / SELECT, UNDO / REDO, recientes y favoritos.
- Música NSF con GameMusicEmu (extensión JNI).
- Login, REMEMBER ME, niveles online y Wily Challenge (gzip con zlib de Android).
- OPTIONS > VIDEO/SOUND > SCREEN: ORIGINAL (8:7), 4:3, 16:9 y FULL. Los modos estiran la imagen con escalado nítido. Los menús y el editor se quedan en 8:7.

## Este repositorio no incluye el juego
Solo están los parches y herramientas del port. Para compilar necesitas tu propia copia de Mega Man Maker 1.10.5.4:
`data.win` en `work/windows-original/` y su código decompilado (UndertaleModTool) en `work/decompiled/CodeEntries/`.

## Compilar
Requisitos: Android SDK (build-tools 36, NDK), Python 3 con Pillow, UndertaleModTool CLI en `work/tools/utmt/`, el APK base del runner en `work/base-v1.apk` y una llave de firma propia en `work/probe-key.jks`.

```powershell
.\work\build_megamaker.ps1 -Out 'outputs\Mega Maker.apk'
```

| Archivo | Para qué sirve |
|---|---|
| `work/patch_startup.py` | Genera los parches GML en `work/android-gml/` |
| `work/android_ui.gml` | Menús, teclado, modos de pantalla, cuenta y archivos de nivel |
| `work/android_touch.gml` | Controles táctiles del juego |
| `work/android_editor.gml` | Capa táctil del editor |
| `work/music/` | Puente JNI de GameMusicEmu y zlib |
| `work/apply_launcher_icon.py` | Icono del launcher |
