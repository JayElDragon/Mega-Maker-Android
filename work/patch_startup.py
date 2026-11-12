"""Prepare the first Android-only GameMaker startup changes."""

import argparse
import re
from pathlib import Path

source = Path("work/decompiled/CodeEntries")
target = Path("work/android-gml")
target.mkdir(exist_ok=True)
# Start clean: later passes read files patched earlier in THIS run, never
# leftovers from a previous run (that stacked repeated prepends).
for stale in target.glob("*.gml"):
    stale.unlink()


def write(name, code):
    (target / (name + ".gml")).write_text(code, encoding="utf-8")


def replace(name, changes):
    code = (source / (name + ".gml")).read_text(encoding="utf-8-sig")
    for old, new in changes:
        if code.count(old) != 1:
            raise ValueError(f"Unexpected original code for {name}: {old}")
        code = code.replace(old, new)
    write(name, code)


# Keep crash diagnostics local while the Android startup is under test.
write("gml_GlobalScript_crashHandler", """exception_unhandled_handler(function(error)
{
    show_debug_message("MMM Android: " + string(error.longMessage));
});
""")
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--touch", action="store_true")
args = parser.parse_args()

# zlib comes from the Android extension (MMZ_Inflate); the desktop DLL handles
# stay defined so nothing reads an unset global.
startup = ("global.buffer_zlib_available = true;\nglobal.buffer_zlib_chunk_size = 16384;\n"
           + "".join(f"global.bufferZlib{n} = -1;\n" for n in
                     ["InitRaw", "GetStatus", "DeflateRaw1", "DeflateRaw2", "InflateRaw1", "InflateRaw2"]))
if args.touch:
    startup += Path("work/android_touch.gml").read_text(encoding="utf-8")
    startup += Path("work/android_ui.gml").read_text(encoding="utf-8")
    startup += Path("work/android_editor.gml").read_text(encoding="utf-8")
write("gml_GlobalScript_gzip_startup", startup)
replace("gml_Object_objGlobalControl_Alarm_3", [
    ('external_call(external_define("DLL/MegaDLL.dll", "Uri", dll_cdecl, ty_real, 0));', ''),
    ('global.password = external_call(external_define("DLL/MegaDLL.dll", "LoadPassword", dll_cdecl, ty_string, 0));',
     'global.password = global.androidLoadPassword();'),
])
replace("gml_Object_objGlobalControl_Other_3", [
    ('external_call(external_define("DLL/MegaDLL.dll", "SavePassword", dll_cdecl, ty_real, 1, ty_string), global.password);',
     'global.androidSavePassword();'),
])

netcode = (source / "gml_GlobalScript_initNetcodeVariables.gml").read_text(encoding="utf-8-sig")
netcode = netcode.replace('        external_free("DLL/RollMQTT.dll");\n', "")
netcode, count = re.subn(
    r'(?m)^(    global\.intermediary\w+ = )external_define\("DLL/RollMQTT\.dll",[^\n]+;',
    r'\g<1>-1;',
    netcode,
)
if count != 7:
    raise ValueError(f"Unexpected RollMQTT function count: {count}")
write("gml_GlobalScript_initNetcodeVariables", netcode)

# Music: GameMusicEmu runs through the Java/JNI extension in work/music, so
# forcePlayNSF keeps its original code. Drop the stub older builds wrote.
(target / "gml_GlobalScript_forcePlayNSF.gml").unlink(missing_ok=True)

if args.touch:
    # Account login/registration screen is kept (it used to be skipped).
    (target / "gml_Object_objFlashWarning_Step_0.gml").unlink(missing_ok=True)
    replace("gml_Object_objGlobalControl_Step_1", [
        ("globalBeginStep();", "if (room != rmInit) { global.androidTouchStep(); global.androidUiStep(); }\nglobalBeginStep();"),
    ])
    replace("gml_Object_objGlobalControl_Draw_73", [
        ("if (global.gifRecording == true)", "global.androidDrawCurtains();\nglobal.androidTouchDraw();\nif (global.gifRecording == true)"),
    ])
    replace("gml_Object_objTitleScreen_Step_0", [
        ("global.keyPausePressed && canProceed == true",
         "(global.keyPausePressed || device_mouse_check_button_pressed(0, mb_left)) && canProceed == true"),
    ])


def replace_ws(name, changes):
    """Like replace(), but matches the old text with any whitespace layout."""
    code = (source / (name + ".gml")).read_text(encoding="utf-8-sig")
    for old, new in changes:
        pattern = r"\s+".join(re.escape(part) for part in old.split())
        found = re.findall(pattern, code)
        if len(found) != 1:
            raise ValueError(f"Expected one match in {name} for: {old} (got {len(found)})")
        code = re.sub(pattern, lambda _: new, code)
    write(name, code)


MENU_SCREEN = [
    # REMEMBER ME: with a saved password go straight to "connecting" (login).
    ('if (global.accessToken == "N/A" || global.password == "")',
     'if (global.password == "")'),
    # OPTIONS > OTHER: third entry REMEMBER ME, BACK moves to the fourth.
    ("""buttonName[41][1] = "LEVEL TIMER: " + timerString;
    buttonName[41][2] = "BACK";
    buttonCount[41] = 2;""",
     """buttonName[41][1] = "LEVEL TIMER: " + timerString;
    buttonName[41][2] = "REMEMBER ME: " + (global.androidRememberMe ? "ON" : "OFF");
    buttonName[41][3] = "BACK";
    buttonCount[41] = 3;"""),
    ("""case 2:
                                    if (global.useCustomCursor == false)
                                    {
                                        moveButtons = true;
                                        moveButtonsOnScreen = false;
                                        nextPhase = 2;
                                    }""",
     """case 2:
                                    if (global.useCustomCursor == false)
                                    {
                                        global.androidToggleRemember();
                                    }"""),
    ('buttonName[41][0] = "CURSOR: " + mouseString;',
     'buttonName[41][0] = "TOUCH: " + (global.androidTouchEnabled ? "ON" : "OFF");'),
    ("""global.useCustomCursor = !global.useCustomCursor;
                                    with (objGlobalControl)
                                    {
                                        event_user(1);
                                    }""",
     "global.androidToggleTouch();"),
    ("""var screenSizeString = "";
if (window_get_fullscreen() == true)
{
    screenSizeString = "FULL";
}
switch (window_get_width())
{
    case 256:
        screenSizeString = "1x";
        break;
    case 512:
        screenSizeString = "2x";
        break;
    case 768:
        screenSizeString = "3x";
        break;
    case 1024:
        screenSizeString = "4x";
        break;
}
buttonName[40][2] = "SCREEN SIZE: " + screenSizeString;""",
     'buttonName[40][2] = "SCREEN: " + global.androidScreenName();'),
    ("var sizeToWrite = 3; if (window_get_fullscreen() == false)",
     "var sizeToWrite = global.androidNextScreen(); if (false)"),
    ("""else
                                    {
                                        window_set_fullscreen(false);
                                        window_set_size(256, 224);
                                        sizeToWrite = 1;
                                    }
                                    canSelectOptionMouse = false;""",
     "canSelectOptionMouse = false;"),
]

if args.touch:
    # Text boxes: X / B / tap outside closes, soft keyboard opens on show/tap.
    replace_ws("gml_Object_objMessageBox_Draw_0", [
        ("else if (type == 3) {",
         "else if (type == 3) {\nif (global.androidMessageBoxInput(id, xx, yy)) exit;"),
    ])
    # Gamepad: left goes to the palette button, right to quit.
    # Touch: resolve the tapped main-menu button before the menu reads it.
    replace_ws("gml_Object_objMainMenu_Step_0", [
        ("switch (menuPhase) { case 0: var logoTimerDo1 = 5;",
         "global.androidMainMenuTap();\nswitch (menuPhase)\n{\n    case 0:\n        var logoTimerDo1 = 5;"),
        ("""if (global.keyLeftPressed || global.keyRightPressed || keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_right))
            {
                playSFX(sfxMenuMove);
                if (menuOption == 4)
                {
                    menuOption = prevMenuOption;
                }
                else
                {
                    prevMenuOption = menuOption;
                    menuOption = 4;
                }
            }""",
         """var androidGoLeft = global.keyLeftPressed || keyboard_check_pressed(vk_left);
            if (androidGoLeft || global.keyRightPressed || keyboard_check_pressed(vk_right))
            {
                playSFX(sfxMenuMove);
                if (menuOption == 4) menuOption = androidGoLeft ? prevMenuOption : 5;
                else if (menuOption == 5) menuOption = androidGoLeft ? 4 : prevMenuOption;
                else { prevMenuOption = menuOption; menuOption = androidGoLeft ? 5 : 4; }
            }"""),
    ] + MENU_SCREEN)
    # Menus: taps on a new spot are replayed after the highlight moves there.
    step = (target / "gml_Object_objMainMenu_Step_0.gml").read_text(encoding="utf-8")
    step = step.replace("mouse_check_button_pressed(mb_left)", "global.androidMousePressed()")
    write("gml_Object_objMainMenu_Step_0", step)
    draw = (source / "gml_Object_objMainMenu_Draw_0.gml").read_text(encoding="utf-8-sig")
    draw = draw.replace("mouse_check_button_pressed(mb_left)", "global.androidMousePressed()")
    # WIDE menus: continue the menu background with mirrored copies.
    bg = "draw_sprite(menuBackground, 0, 0, 0);"
    assert draw.count(bg) == 1
    draw = draw.replace(bg, bg + " draw_sprite_ext(menuBackground, 0, 0, 0, -1, 1, 0, c_white, 1);"
                        " draw_sprite_ext(menuBackground, 0, 2 * sprite_get_width(menuBackground), 0, -1, 1, 0, c_white, 1);")
    write("gml_Object_objMainMenu_Draw_0", draw)
    # Options > SCREEN: Android display modes instead of desktop window sizes.
    # (patched together with the gamepad change above, see MENU_SCREEN)
    (target / "gml_GlobalScript_playerCamera.gml").unlink(missing_ok=True)
    # WIDE: water surfaces restore the camera; restore size first, then the
    # centred position.
    replace_ws("gml_Object_objWaterTileDrawController_Draw_0", [
        ("""camera_set_view_pos(view_camera[0], global.viewX, global.viewY);
            camera_set_view_size(view_camera[0], cameraWidth, cameraHeight);""",
         """camera_set_view_size(view_camera[0], cameraWidth, cameraHeight);
            global.androidSetViewPos(view_camera[0], global.viewX, global.viewY);"""),
    ])
    # Post Draw event (new): draws the game surface for the gameplay screen modes.
    (target / "gml_Object_objGlobalControl_Draw_77.gml").unlink(missing_ok=True)
    # Draw GUI Begin (new event): GUI is 1:1 with the window and is drawn after
    # the point where the runner would have drawn the application surface.
    write("gml_Object_objGlobalControl_Draw_74", "global.androidPostDraw();\n")
    # Touch screen: no mouse pointer.
    code = (source / "gml_Object_objCursor_Draw_0.gml").read_text(encoding="utf-8-sig")
    write("gml_Object_objCursor_Draw_0", "if (os_type == os_android) exit;\n" + code)


# Desktop window sizing changes the draw size on Android: make it a no-op.
WINDOW_CALLS = re.compile(r"(?<![\w.])window_(set_size|set_fullscreen|center)\(")
for code_file in sorted(source.glob("*.gml")):
    original = code_file.read_text(encoding="utf-8-sig")
    if not WINDOW_CALLS.search(original):
        continue
    patched_file = target / code_file.name
    code = patched_file.read_text(encoding="utf-8") if patched_file.exists() else original
    write(code_file.stem, WINDOW_CALLS.sub("global.androidWindowNoop(", code))


# WIDE mode: the render camera is centred on the 256-wide logical screen.
VIEW_POS = re.compile(r"camera_set_view_pos\(global\.view,")
for code_file in sorted(source.glob("*.gml")):
    original = code_file.read_text(encoding="utf-8-sig")
    if not VIEW_POS.search(original):
        continue
    patched_file = target / code_file.name
    code = patched_file.read_text(encoding="utf-8") if patched_file.exists() else original
    write(code_file.stem, VIEW_POS.sub("global.androidSetViewPos(global.view,", code))


# WIDE: full-screen fades/overlays cover the whole render camera, not 256 px.
FULL_RECTS = {
    "draw_rectangle(global.viewX, global.viewY, global.viewX + global.viewWidth, global.viewY + global.viewHeight, false);":
    "draw_rectangle(camera_get_view_x(view_camera[0]), global.viewY, camera_get_view_x(view_camera[0]) + camera_get_view_width(view_camera[0]), global.viewY + global.viewHeight, false);",
    "draw_rectangle(global.viewX, global.viewY, global.viewX + 256, global.viewY + 224, false);":
    "draw_rectangle(camera_get_view_x(view_camera[0]), global.viewY, camera_get_view_x(view_camera[0]) + camera_get_view_width(view_camera[0]), global.viewY + 224, false);",
}
for code_file in sorted(source.glob("*.gml")):
    original = code_file.read_text(encoding="utf-8-sig")
    if not any(old in original for old in FULL_RECTS):
        continue
    patched_file = target / code_file.name
    code = patched_file.read_text(encoding="utf-8") if patched_file.exists() else original
    for old, new in FULL_RECTS.items():
        code = code.replace(old, new)
    write(code_file.stem, code)


# WIDE: "on screen" means the real (wider) visible area, and the HUD hugs
# the real left edge. androidViewL/W equal viewX/256 outside WIDE.
VIEW_CHECKS = ["insideView", "insideViewBox", "insideViewBbox", "insideViewBeam", "insideViewBoxBeam",
               "insideViewPoint", "outsideViewBox", "setVisibleIfOnScreen"]
for name in ["gml_GlobalScript_" + n for n in VIEW_CHECKS] + ["gml_Object_objHealthWeaponBar_Draw_0"]:
    code = (source / (name + ".gml")).read_text(encoding="utf-8-sig")
    code = code.replace("global.viewX", "global.androidViewL")
    if "HealthWeaponBar" not in name:
        code = code.replace("global.viewWidth", "global.androidViewW")
    write(name, code)

# Pause menu: black behind the 256-wide pause screen in WIDE.
pause = (target / "gml_Object_objPauseMenu_Draw_0.gml").read_text(encoding="utf-8")
PAUSE_BG = "draw_sprite(sprPauseMenuBG, global.playLevelThroughChallenge, global.viewX, global.viewY);"
assert pause.count(PAUSE_BG) == 1
pause = pause.replace(PAUSE_BG, "draw_set_color(c_black);\n"
                      "draw_rectangle(camera_get_view_x(view_camera[0]) - 1, global.viewY - 1, "
                      "camera_get_view_x(view_camera[0]) + camera_get_view_width(view_camera[0]) + 1, global.viewY + 225, false);\n"
                      # Fill the WIDE sides with the pause screen's own edge strips.
                      "var androidPauseL = camera_get_view_x(view_camera[0]);\n"
                      "var androidPauseR = androidPauseL + camera_get_view_width(view_camera[0]);\n"
                      "for (var androidPx = global.viewX - 32; androidPx > androidPauseL - 32; androidPx -= 32) "
                      "draw_sprite_part(sprPauseMenuBG, global.playLevelThroughChallenge, 0, 0, 32, 224, androidPx, global.viewY);\n"
                      "for (var androidPx2 = global.viewX + 256; androidPx2 < androidPauseR; androidPx2 += 32) "
                      "draw_sprite_part(sprPauseMenuBG, global.playLevelThroughChallenge, 224, 0, 32, 224, androidPx2, global.viewY);\n"
                      + PAUSE_BG)
write("gml_Object_objPauseMenu_Draw_0", pause)



# Touch editor: builder mouse reads go through the tool-aware wrappers.
MOUSE_CALLS = re.compile(r"(?<![\w.])mouse_check_button(_pressed|_released)?\(")
WRAPPER = {None: "global.androidMB(", "_pressed": "global.androidMBP(", "_released": "global.androidMBR("}
def builder_file(stem):
    if stem.startswith("gml_Object_objBuilder"):
        return True
    if stem.startswith("gml_GlobalScript_"):
        name = stem[len("gml_GlobalScript_"):]
        if name.startswith("__input") or name.startswith("input_") or name == "menuDebug":
            return False
        return name.startswith(("menu", "draw", "builder", "handleMultiEditing"))
    return False
for code_file in sorted(source.glob("*.gml")):
    if not builder_file(code_file.stem):
        continue
    original = code_file.read_text(encoding="utf-8-sig")
    if not MOUSE_CALLS.search(original):
        continue
    patched_file = target / code_file.name
    code = patched_file.read_text(encoding="utf-8") if patched_file.exists() else original
    code = MOUSE_CALLS.sub(lambda m: WRAPPER[m.group(1)], code)
    if code_file.stem == "gml_Object_objBuilderGlobal_Step_0":
        code = "global.androidBuilderInput();\n" + code
    write(code_file.stem, code)


# Touch editor undo: record what a stroke adds and removes
# (objBuilderPlacedObject Create / Destroy).
create = (source / "gml_Object_objBuilderPlacedObject_Create_0.gml").read_text(encoding="utf-8-sig")
write("gml_Object_objBuilderPlacedObject_Create_0", "global.androidUndoNoteAdd(id);\n" + create)
destroy = (source / "gml_Object_objBuilderPlacedObject_Destroy_0.gml").read_text(encoding="utf-8-sig")
write("gml_Object_objBuilderPlacedObject_Destroy_0", "global.androidUndoNoteDelete(id);\n" + destroy)


# zlib: downloaded levels (online, Wily Challenge) are gzip files that the PC
# build inflates with buffer_zlib_x64.dll. On Android the GameMusicEmu Java/JNI
# extension inflates with system zlib, reached through GameMusicEmu_Read
# with a "Z:"/"C:" command prefix (the compiler can't see new functions).
write("gml_GlobalScript_bufferInflate", """function bufferInflate()
{
    var l_source = argument[0];
    var l_length = buffer_get_size(l_source);
    var l_offset = clamp(argument[1], 0, l_length);
    var l_total = clamp(argument[1] + argument[2], 0, l_length) - l_offset;
    var l_size = GameMusicEmu_Read("Z:" + string(buffer_get_address(l_source)) + ":" + string(l_offset) + ":" + string(l_total));
    if (l_size < 0)
    {
        return -1;
    }
    var l_result;
    if (argument_count <= 3)
    {
        // buffer_fixed: the native copy writes straight into memory, and a
        // grow buffer would keep a "used size" of 0 (buffer_copy copies zeros).
        l_result = buffer_create(max(1, l_size), buffer_fixed, 1);
        if (GameMusicEmu_Read("C:" + string(buffer_get_address(l_result))) != l_size)
        {
            buffer_delete(l_result);
            return -1;
        }
        buffer_set_used_size(l_result, l_size);
        buffer_seek(l_result, buffer_seek_start, l_size);
        return l_result;
    }
    l_result = argument[3];
    var l_start = buffer_tell(l_result);
    if (buffer_get_size(l_result) < l_start + l_size)
    {
        buffer_resize(l_result, l_start + l_size);
    }
    var l_tmp = buffer_create(max(1, l_size), buffer_fixed, 1);
    if (GameMusicEmu_Read("C:" + string(buffer_get_address(l_tmp))) != l_size)
    {
        buffer_delete(l_tmp);
        return -1;
    }
    buffer_set_used_size(l_tmp, l_size);
    buffer_copy(l_tmp, 0, l_size, l_result, l_start);
    buffer_delete(l_tmp);
    buffer_seek(l_result, buffer_seek_start, l_start + l_size);
    return l_result;
}
""")


# http_get_file reports an absolute path; buffer_load/save on the Android
# runner want the save-area relative one.
replace_ws("gml_Object_objHTTPControl_Other_62", [
    ('var fileName = ds_map_find_value(async_load, "result"); var saveFileName',
     'var fileName = ds_map_find_value(async_load, "result");\n'
     'var androidFilesPos = string_pos("/files/", fileName);\n'
     'if (androidFilesPos > 0) fileName = string_delete(fileName, 1, androidFilesPos + 6);\n'
     'var saveFileName'),
    ("unzippingGZIP = true;", "unzippingGZIP = false;"),
    ("var gzipCallbackID = gzip_unzip(fileName, saveFileName);",
     'var gzipCallbackID = gzip_unzip(fileName, saveFileName);\n'
     'if (gzipCallbackID == -1) global.httpError = "Could not unpack or save the downloaded level";'),
    ('drawMessageOK("The downloaded level file could not be found.");',
     'global.httpError = "The downloaded level file could not be found";'),
])


# Load the saved password at startup: the desktop build only did it when
# MegaDLL's CloseOldInstance said so (never true on Android).
alarm3 = (target / "gml_Object_objGlobalControl_Alarm_3.gml").read_text(encoding="utf-8")
guarded = re.compile(r"if \(autoPassword == true\)\s*\{\s*global\.password = global\.androidLoadPassword\(\);\s*\}")
assert len(guarded.findall(alarm3)) == 1
write("gml_Object_objGlobalControl_Alarm_3", guarded.sub("global.password = global.androidLoadPassword();", alarm3))


# Online downloads (gzip_unzip): Android-safe save + diagnostics.
write("gml_GlobalScript_gzip_unzip", """function gzip_unzip(arg0, arg1)
{
    show_debug_message("MMM gz in=" + string(arg0) + " out=" + string(arg1) + " exists=" + string(file_exists(arg0)));
    var b0 = buffer_load(arg0);
    show_debug_message("MMM gz b0=" + string(b0) + " size=" + string((b0 == -1) ? -1 : buffer_get_size(b0)));
    if (b0 == -1)
    {
        return -1;
    }
    buffer_seek(b0, buffer_seek_start, 0);
    var b1 = bufferInflate(b0, 0, buffer_get_size(b0));
    show_debug_message("MMM gz b1=" + string(b1) + " size=" + string((b1 == -1) ? -1 : buffer_get_size(b1)));
    if (b1 == -1)
    {
        buffer_delete(b0);
        return -1;
    }
    var b1Size = buffer_get_size(b1);
    buffer_save(b1, arg1);
    var saved = buffer_load(arg1);
    var savedSize = (saved == -1) ? -1 : buffer_get_size(saved);
    var matches = savedSize == b1Size && b1Size > 0
        && buffer_md5(saved, 0, savedSize) == buffer_md5(b1, 0, b1Size);
    if (saved != -1) buffer_delete(saved);
    show_debug_message("MMM gz verified " + string(arg1) + " expected=" + string(b1Size)
        + " read=" + string(savedSize) + " matches=" + string(matches));
    buffer_delete(b0);
    buffer_delete(b1);
    return matches ? -999 : -1;
}
""")

replace_ws("gml_Object_objLevelLoader_Create_0", [
    ("""var file = file_bin_open(filenameLoading, 0);
        var size = file_bin_size(file);
        file_bin_close(file);
        loadid = buffer_load_async(buffer, filenameLoading, 0, size);
        status = 1;""",
     """if (buffer_exists(buffer)) buffer_delete(buffer);
        buffer = buffer_load(filenameLoading);
        loadid = undefined;
        size = (buffer == -1) ? 0 : buffer_get_size(buffer);
        show_debug_message("MMM loader " + string(filenameLoading) + " bytes=" + string(size));
        if (size < 7)
        {
            global.httpError = "Could not read the level file";
            status = 6;
            completeFrames = 1;
            loadingIsDone = false;
            isInit = true;
            return;
        }
        buffer_seek(buffer, buffer_seek_start, 0);
        bufferLoaded = true;
        status = 2;"""),
    ("ini_open(loadFileName); initIsOpen = true;",
     """global.androidIniOpenBuffer(buffer);
            buffer_delete(buffer);
            buffer = -1;
            initIsOpen = true;
            if (string_pos("TempLevels/", loadFileName) == 1 && ini_read_string("Level", "1a", "") == "")
            {
                ini_close();
                initIsOpen = false;
                global.httpError = "The downloaded level has no [Level] metadata";
                status = 6;
                completeFrames = 1;
                return;
            }"""),
    ("buffer_delete(buffer); status = 3;", "status = 3;"),
])


# Level files: variable-path ini_open (always .mmlv levels, read-only) goes
# through global.androidIniOpen (see android_ui.gml).
INI_VAR = re.compile(r'(?<![\w.])ini_open\((?!")')
for code_file in sorted(source.glob("*.gml")):
    original = code_file.read_text(encoding="utf-8-sig")
    if not INI_VAR.search(original):
        continue
    patched_file = target / code_file.name
    code = patched_file.read_text(encoding="utf-8") if patched_file.exists() else original
    write(code_file.stem, INI_VAR.sub("global.androidIniOpen(", code))
