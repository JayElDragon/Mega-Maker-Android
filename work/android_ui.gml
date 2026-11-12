
// ---- Android UI helpers (main menu taps, text boxes, soft keyboard) ----
global.androidKbdOpen = false;

global.androidPadPressed = function(button)
{
    for (var pad = 0; pad < 12; pad++)
    {
        if (gamepad_is_connected(pad) && gamepad_button_check_pressed(pad, button))
        {
            return true;
        }
    }
    return false;
};

// One tap selects a main-menu button, including the palette and quit icons
// that the desktop hover logic never highlighted for touch.
// Menus decide a click with the hover state from the previous frame, and on a
// touch screen the "mouse" jumps straight to the new finger position. A tap on
// a new spot is therefore replayed one frame later, after Draw has moved the
// highlight under the finger. The menu code calls androidMousePressed().
global.androidTapDeferred = false;
global.androidTapReplay = false;
global.androidLastTapX = -9999;
global.androidLastTapY = -9999;

global.androidMousePressed = function()
{
    return global.androidTapReplay || (mouse_check_button_pressed(mb_left) && !global.androidTapDeferred);
};

global.androidMainMenuTap = function()
{
    global.androidTapReplay = global.androidTapDeferred;
    global.androidTapDeferred = false;
    if (mouse_check_button_pressed(mb_left))
    {
        var moved = point_distance(mouse_x, mouse_y, global.androidLastTapX, global.androidLastTapY) > 3;
        global.androidLastTapX = mouse_x;
        global.androidLastTapY = mouse_y;
        if (moved && !(instance_exists(objMainMenu) && objMainMenu.menuPhase == 1))
        {
            global.androidTapDeferred = true;
            with (objMainMenu)
            {
                prevMouseX = -9999;
                prevMouseY = -9999;
            }
        }
    }
    if (room != rmMainMenu || !instance_exists(objMainMenu) || instance_exists(objMessageBox)
        || !mouse_check_button_pressed(mb_left))
    {
        return;
    }
    with (objMainMenu)
    {
        if (menuPhase != 1 || !canUseMenu || buttonXOffset != round(room_width / 2))
        {
            break;
        }
        // Touch: forget the hover state left behind by the previous touch.
        mouseOnOption = false;
        var bigW = mmm_sprite_get_width(getMainMenuThemeSprite(sprMenuButton));
        var bigH = mmm_sprite_get_height(getMainMenuThemeSprite(sprMenuButton));
        var iconY = 90 + (3 * (bigH + 5));
        var iconX = room_width - round((room_width / 2) * 0.215);
        for (var i = 0; i <= 5; i++)
        {
            var bx, by, bw, bh;
            if (i < 4)
            {
                bx = ((i % 2) == 0) ? buttonXOffset : room_width - buttonXOffset;
                by = 90 + (i * (bigH + 5));
                bw = bigW;
                bh = bigH;
            }
            else
            {
                bx = (i == 5) ? iconX - 200 : iconX;
                by = iconY;
                bw = mmm_sprite_get_width(sprMenuTheme);
                bh = mmm_sprite_get_height(sprMenuTheme);
            }
            if (abs(mouse_x - bx) <= bw / 2 && abs(mouse_y - by) <= bh / 2)
            {
                if (i < 4)
                {
                    prevMenuOption = i;
                }
                menuOption = i;
                mouseOnOption = true;
                selectedWithMouse = true;
                break;
            }
        }
    }
};

global.androidCancelMessage = function()
{
    if (room == rmMainMenu)
    {
        with (objMainMenu)
        {
            createdMessageName = false;
            createdMessagePassword = false;
            menuOption = 0;
            prevMenuOption = 0;
            menuPhase = 1;
            nextPhase = 1;
            moveButtons = true;
            moveButtonsOnScreen = true;
            buttonXOffset = -ceil(mmm_sprite_get_width(getMainMenuThemeSprite(sprMenuButton)) / 2);
            canUseMenu = true;
        }
    }
    else if (room == rmCreateProfile)
    {
        room_goto(rmMainMenu);
    }
    else if (room == rmBuilder)
    {
        global.canUseEditor = true;
    }
};

global.androidShowKeyboard = function(nameType)
{
    var kind = kbv_type_default;
    if (nameType == "email" || nameType == "emailchange" || nameType == "passwordreset")
    {
        kind = kbv_type_email;
    }
    keyboard_virtual_show(kind, kbv_returnkey_done, kbv_autocapitalize_none, false);
    global.androidKbdOpen = true;
};

// Called from objMessageBox Draw for text-entry boxes (type 3). Returns true
// when the box was closed so the caller can stop drawing it.
global.androidMessageBoxInput = function(box, xx, yy)
{
    var closeX = xx + 90;
    var closeY = yy - 64;
    var tap = device_mouse_check_button_pressed(0, mb_left);
    var mx = device_mouse_x(0);
    var my = device_mouse_y(0);
    var onClose = abs(mx - closeX) <= 9 && abs(my - closeY) <= 9;
    var outside = abs(mx - xx) > 102 || my < yy - 78 || my > yy + 78;

    if (keyboard_check_pressed(vk_escape) || global.androidPadPressed(gp_face2) || (tap && (onClose || outside)))
    {
        keyboard_virtual_hide();
        global.androidKbdOpen = false;
        playSFX(sfxMenuSelect);
        global.androidCancelMessage();
        with (box)
        {
            instance_destroy();
        }
        return true;
    }

    with (box)
    {
        if (!variable_instance_exists(id, "androidKbdShown") || (tap && !onClose))
        {
            androidKbdShown = true;
            global.androidShowKeyboard(nameType);
        }
    }

    var alpha = draw_get_alpha();
    var color = draw_get_color();
    var halign = draw_get_halign();
    var valign = draw_get_valign();
    draw_set_alpha(1);
    draw_set_color(c_black);
    draw_rectangle(closeX - 8, closeY - 8, closeX + 8, closeY + 8, false);
    draw_set_color(c_white);
    draw_rectangle(closeX - 8, closeY - 8, closeX + 8, closeY + 8, true);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_set_font(global.MM3font);
    draw_text(closeX + 1, closeY + 1, "X");

    // The soft keyboard covers the input field: mirror the text at the top.
    if (keyboard_virtual_status())
    {
        var shown = box.inputString;
        if (box.password)
        {
            shown = string_repeat("*", string_length(shown));
        }
        if (string_length(shown) > 28)
        {
            shown = string_copy(shown, string_length(shown) - 27, 28);
        }
        var top = global.viewY + 2;
        draw_set_color(c_black);
        draw_rectangle(global.viewX + 8, top, global.viewX + global.viewWidth - 8, top + 16, false);
        draw_set_color(c_white);
        draw_rectangle(global.viewX + 8, top, global.viewX + global.viewWidth - 8, top + 16, true);
        draw_set_halign(fa_left);
        draw_text(global.viewX + 13, top + 9, shown + (((current_time div 400) mod 2) ? "|" : ""));
    }
    draw_set_halign(halign);
    draw_set_valign(valign);
    draw_set_alpha(alpha);
    draw_set_color(color);
    return false;
};

// ---- Screen modes (Settings.ini ScreenSize 1..4), gameplay only ----
// 1 ORIGINAL (8:7)  2 4:3  3 16:9  4 FULL (whole device screen). 2-4 stretch
// the 256x224 picture. Menus and the editor always use ORIGINAL (the editor
// panels live in the side bars).
global.androidScreenNames = ["", "ORIGINAL", "4:3", "16:9", "FULL"];
ini_open("Settings/Settings.ini");
global.androidScreenMode = clamp(ini_read_real("Settings", "ScreenSize", 4), 1, 4);
ini_close();
global.androidWideActive = false;

global.androidScreenName = function()
{
    return global.androidScreenNames[global.androidScreenMode];
};

global.androidNextScreen = function()
{
    global.androidScreenMode = (global.androidScreenMode mod 4) + 1;
    return global.androidScreenMode;
};

global.androidWindowNoop = function() {};
global.androidBlurSurf = -1;

// Replaces camera_set_view_pos(global.view, ...). The game keeps a 256-wide
// logical screen (global.viewX/viewWidth: section grid). In WIDE the render
// camera is wider: it stays inside the current section like a real wider
// screen, and slides smoothly when that target changes.
global.androidViewL = 0;
global.androidViewW = 256;
global.androidCamOffset = 0;
global.androidCurtainL = -1;
global.androidCurtainR = -1;

global.androidSetViewPos = function(cam, xx, yy)
{
    var camW = camera_get_view_width(cam);
    var extra = floor((camW - global.viewWidth) / 2);
    var target = 0;
    global.androidCurtainL = -1;
    global.androidCurtainR = -1;
    // Pause screen (and anything drawn at the logical screen) needs the
    // camera centred on it: snap back immediately while paused.
    if (instance_exists(objPauseMenu))
    {
        global.androidCamOffset = 0;
    }
    // User preference: keep Mega Man centred like the original camera (no
    // clamping of the wider view to the section edges).
    else if (false)
    {
        var sl = objMegaman.sectionLeft;
        var sr = objMegaman.sectionRight;
        // Only while the logical screen sits inside the section (not mid-transition).
        if (xx >= sl - 1 && xx + global.viewWidth <= sr + 1)
        {
            var want;
            if (sr - sl >= camW)
            {
                want = clamp(xx - extra, sl, sr - camW);
            }
            else
            {
                want = sl - floor((camW - (sr - sl)) / 2);
                global.androidCurtainL = sl;
                global.androidCurtainR = sr;
            }
            target = want - (xx - extra);
        }
    }
    if (extra <= 0)
    {
        global.androidCamOffset = 0;
    }
    else
    {
        var diff = target - global.androidCamOffset;
        global.androidCamOffset += clamp(diff, -6, 6);
    }
    var cx = floor(xx - max(0, extra) + global.androidCamOffset);
    camera_set_view_pos(cam, cx, yy);
    global.androidViewL = cx;
    global.androidViewW = camW;
};

// Black outside a section that is narrower than the WIDE screen.
global.androidDrawCurtains = function()
{
    if (global.androidCurtainL < 0 || room != rmPlayLevel)
    {
        return;
    }
    var cam = view_camera[0];
    var vx = camera_get_view_x(cam);
    var vy = camera_get_view_y(cam);
    var vw = camera_get_view_width(cam);
    var vh = camera_get_view_height(cam);
    draw_set_color(c_black);
    draw_set_alpha(1);
    if (global.androidCurtainL > vx)
    {
        draw_rectangle(vx - 1, vy - 1, global.androidCurtainL - 1, vy + vh + 1, false);
    }
    if (global.androidCurtainR < vx + vw)
    {
        draw_rectangle(global.androidCurtainR, vy - 1, vx + vw + 1, vy + vh + 1, false);
    }
};

global.androidDrawRect = [0, 0, 1, 1];
display_set_gui_maximize(1, 1, 0, 0);

// The runner draws the application surface inconsistently on Android (1:1 in
// some rooms), so the port always draws it itself in Draw GUI Begin. Menus and
// the editor always use FIT; the chosen SCREEN mode applies inside levels.
global.androidRoomMode = function()
{
    // Decision (2026-11-10): SCREEN modes apply to gameplay only; menus and
    // the editor stay ORIGINAL (8:7) with a blurred fill on the sides.
    return (room == rmPlayLevel) ? global.androidScreenMode : 1;
};

// Decision (2026-11-12): every SCREEN mode STRETCHES the 256x224 picture to
// its aspect ratio. The wider camera of the old 16:9/FULL modes showed parts
// of the level outside the section, early spawns and misplaced overlays.
global.androidApplyScreen = function()
{
    var camW = 256;
    if (camera_get_view_width(global.view) != camW || camera_get_view_height(global.view) != 224)
    {
        camera_set_view_size(global.view, camW, 224);
    }
    if (surface_exists(application_surface)
        && (surface_get_width(application_surface) != camW || surface_get_height(application_surface) != 224))
    {
        surface_resize(application_surface, camW, 224);
    }
    if (view_get_wport(0) != camW || view_get_hport(0) != 224)
    {
        view_set_xport(0, 0);
        view_set_yport(0, 0);
        view_set_wport(0, camW);
        view_set_hport(0, 224);
    }
    global.androidWideActive = false;
    application_surface_draw_enable(false);
};

// Picture size in window pixels for a SCREEN mode (stretching allowed).
global.androidScreenRect = function(mode, dw, dh)
{
    var aspect = 8 / 7;
    switch (mode)
    {
        case 2: aspect = 4 / 3; break;
        case 3: aspect = 16 / 9; break;
        case 4: aspect = dw / dh; break;
    }
    var w = dh * aspect;
    var h = dh;
    if (w > dw)
    {
        w = dw;
        h = dw / aspect;
    }
    w = round(w);
    h = round(h);
    return [floor((dw - w) / 2), floor((dh - h) / 2), w, h];
};

// Sharp scaling: blow the picture up by a whole number with hard pixels,
// then smooth-scale that down to the final size. Every pixel ends up the
// same size even when the stretch is not a whole number (e.g. 224 -> 1080).
global.androidSharpSurf = -1;

// Draw GUI Begin (GUI = window pixels): draw the game surface.
global.androidPostDraw = function()
{
    var dw = max(1, window_get_width());
    var dh = max(1, window_get_height());
    // Logical game size: the camera, whatever the surface resolution is.
    var r = global.androidScreenRect(global.androidRoomMode(), dw, dh);
    global.androidDrawRect = r;
    var rx = r[0];
    var ry = r[1];
    var w = r[2];
    var h = r[3];
    draw_set_color(c_black);
    draw_set_alpha(1);
    draw_rectangle(0, 0, dw, dh, false);
    // Black bars beside the picture (the blurred fill was rejected).
    if (surface_exists(application_surface))
    {
        var gw = surface_get_width(application_surface);
        var gh = surface_get_height(application_surface);
        var k = max(1, ceil(max(w / gw, h / gh)));
        gpu_set_blendenable(false);
        gpu_set_texfilter(false);
        if (k * gw == w && k * gh == h)
        {
            draw_surface_stretched(application_surface, rx, ry, w, h);
        }
        else
        {
            var sw_ = gw * k;
            var sh_ = gh * k;
            if (!surface_exists(global.androidSharpSurf)
                || surface_get_width(global.androidSharpSurf) != sw_
                || surface_get_height(global.androidSharpSurf) != sh_)
            {
                if (surface_exists(global.androidSharpSurf))
                {
                    surface_free(global.androidSharpSurf);
                }
                global.androidSharpSurf = surface_create(sw_, sh_);
            }
            surface_set_target(global.androidSharpSurf);
            draw_surface_stretched(application_surface, 0, 0, sw_, sh_);
            surface_reset_target();
            gpu_set_texfilter(true);
            draw_surface_stretched(global.androidSharpSurf, rx, ry, w, h);
            gpu_set_texfilter(false);
        }
        gpu_set_blendenable(true);
    }
    global.androidDrawEditorPanels();
};

// The desktop build stores the account password through MegaDLL.dll.
// REMEMBER ME (OPTIONS > OTHER): keep the account password between launches.
ini_open("Settings/AndroidAccount.ini");
global.androidRememberMe = ini_read_real("Account", "Remember", 1) != 0;
ini_close();

global.androidToggleRemember = function()
{
    global.androidRememberMe = !global.androidRememberMe;
    ini_open("Settings/AndroidAccount.ini");
    ini_write_real("Account", "Remember", global.androidRememberMe ? 1 : 0);
    if (!global.androidRememberMe)
    {
        ini_write_string("Account", "Password", "");
    }
    else if (variable_global_exists("password") && is_string(global.password))
    {
        ini_write_string("Account", "Password", base64_encode(global.password));
    }
    ini_close();
};

global.androidLoadPassword = function()
{
    ini_open("Settings/AndroidAccount.ini");
    var saved = global.androidRememberMe ? ini_read_string("Account", "Password", "") : "";
    ini_close();
    global.androidSavedPassword = (saved == "") ? "" : base64_decode(saved);
    return global.androidSavedPassword;
};

global.androidSavePassword = function()
{
    global.androidSavedPassword = global.password;
    if (!global.androidRememberMe)
    {
        return;
    }
    ini_open("Settings/AndroidAccount.ini");
    ini_write_string("Account", "Password", base64_encode(global.password));
    ini_close();
};
global.androidSavedPassword = "";

// Level files (.mmlv): the level card ini_opens TempLevels/<name>.mmlv before
// the download exists, and later ini_open calls on that path saw that empty
// copy, so the loader read no level name ("Undefined response from server").
// Read the real file contents and open the INI from memory instead.
global.androidIniOpenBuffer = function(src)
{
    var size = buffer_get_size(src);
    var text = buffer_create(size + 1, buffer_fixed, 1);
    buffer_copy(src, 0, size, text, 0);
    buffer_poke(text, size, buffer_u8, 0);
    var content = buffer_peek(text, 0, buffer_string);
    buffer_delete(text);
    ini_open_from_string(content);
};

global.androidIniOpen = function(path)
{
    if (is_string(path) && string_lower(string_copy(path, string_length(path) - 4, 5)) == ".mmlv")
    {
        var src = buffer_load(path);
        if (src != -1)
        {
            global.androidIniOpenBuffer(src);
            buffer_delete(src);
            return;
        }
        show_debug_message("MMM ini " + path + " not found");
    }
    ini_open(path);
};

// Profiles created while the old build skipped the login screen have no user
// ID (-1), so MY PROFILE asked the server for user -1. Look the ID up by name
// once logged in (same request the login screen uses) and store it.
global.androidIdState = 0; // 0 idle, 1 waiting for the reply, 2 done/failed
global.androidRepairUserId = function()
{
    if (global.androidIdState == 2 || !variable_global_exists("userID") || !variable_global_exists("profileName"))
    {
        return;
    }
    if (global.userID > 0 || global.profileName == "" || !variable_global_exists("accessToken") || global.accessToken == "N/A")
    {
        return;
    }
    if (global.androidIdState == 0)
    {
        if (!instance_exists(objHTTPControl))
        {
            global.currentUserID = -1;
            httpUserGetName(global.profileName);
            global.androidIdState = 1;
            show_debug_message("MMM id lookup for " + global.profileName);
        }
        return;
    }
    if (!instance_exists(objHTTPControl))
    {
        global.androidIdState = 2;
        show_debug_message("MMM id lookup result " + string(global.currentUserID));
        if (is_real(global.currentUserID) && global.currentUserID > 0)
        {
            global.userID = round(global.currentUserID);
            ini_open("Settings/Profile.ini");
            ini_write_real("Profile", "ID_DONOTCHANGE", global.userID);
            ini_close();
        }
    }
};

global.androidUiStep = function()
{
    global.androidRepairUserId();
    // No pointer on Android: OPTIONS > OTHER shows TOUCH instead of CURSOR.
    if (variable_global_exists("useCustomCursor"))
    {
        global.useCustomCursor = false;
    }
    global.androidApplyScreen();
    if (variable_global_exists("password") && is_string(global.password)
        && global.password != global.androidSavedPassword)
    {
        global.androidSavePassword();
    }
    if (global.androidKbdOpen && !instance_exists(objMessageBox))
    {
        keyboard_virtual_hide();
        global.androidKbdOpen = false;
    }
};
