// Android test overlay. Positions are fractions of the active camera view.
ini_open("AndroidControls.ini");
global.androidTouchEnabled = ini_read_real("Controls", "Visible", 1) != 0;
ini_close();

global.androidTouchButtons = [
    ["keyLeft", "<", 0.08, 0.83, 0.065, 0.07],
    ["keyRight", ">", 0.34, 0.83, 0.065, 0.07],
    ["keyUp", "^", 0.21, 0.69, 0.065, 0.07],
    ["keyDown", "v", 0.21, 0.90, 0.065, 0.07],
    ["keyJump", "JUMP", 0.89, 0.88, 0.092, 0.09],
    ["keyShoot", "FIRE", 0.70, 0.78, 0.092, 0.09],
    ["keySlide", "SLIDE", 0.89, 0.67, 0.092, 0.07],
    ["keyWeaponSwitchLeft", "L", 0.08, 0.10, 0.065, 0.067],
    ["keyWeaponSwitchRight", "R", 0.89, 0.10, 0.065, 0.067],
    ["keyPause", "II", 0.50, 0.08, 0.045, 0.055]
];
global.androidTouchOption = ["", "", 0.50, 0.93, 0.40, 0.058];
global.androidTouchHeld = array_create(array_length(global.androidTouchButtons), false);

global.androidTouchIsOptions = function()
{
    // Replaced by OPTIONS > OTHER > TOUCH (see android_ui.gml).
    return false;
};

global.androidTouchHit = function(button, finger)
{
    var r = global.androidDrawRect;
    var px = (device_mouse_raw_x(finger) - r[0]) / r[2];
    var py = (device_mouse_raw_y(finger) - r[1]) / r[3];
    // Button widths are authored for the 256-wide screen; keep their size
    // when the camera is wider (WIDE mode), positions stay edge-relative.
    var sx = 256 / max(256, camera_get_view_width(view_camera[0]));
    return abs(px - button[2]) <= button[4] * sx && abs(py - button[3]) <= button[5];
};

global.androidTouchStep = function()
{
    if (global.androidTouchIsOptions() && device_mouse_check_button_pressed(0, mb_left)
        && global.androidTouchHit(global.androidTouchOption, 0))
    {
        global.androidTouchEnabled = !global.androidTouchEnabled;
        ini_open("AndroidControls.ini");
        ini_write_real("Controls", "Visible", global.androidTouchEnabled ? 1 : 0);
        ini_close();
        playSFX(sfxMenuSelect);
    }

    var showPad = room == rmPlayLevel && global.androidTouchEnabled;
    for (var buttonIndex = 0; buttonIndex < array_length(global.androidTouchButtons); buttonIndex++)
    {
        var button = global.androidTouchButtons[buttonIndex];
        var down = false;
        if (showPad)
        {
            for (var finger = 0; finger < 5; finger++)
            {
                if (device_mouse_check_button(finger, mb_left) && global.androidTouchHit(button, finger))
                {
                    down = true;
                    break;
                }
            }
        }

        var before = global.androidTouchHeld[buttonIndex];
        global.androidTouchHeld[buttonIndex] = down;
        if (!down && !before)
        {
            continue;
        }

        var key = button[0];
        var physical = variable_global_get(key);
        if (down)
        {
            variable_global_set(key, true);
            variable_global_set(key + "Released", false);
            if (!before && !physical)
            {
                variable_global_set(key + "Pressed", true);
            }
        }
        else if (!physical)
        {
            variable_global_set(key + "Released", true);
        }
    }
};

global.androidTouchDrawButton = function(button, label, held)
{
    var cam = view_camera[0];
    var bx = camera_get_view_x(cam) + button[2] * camera_get_view_width(cam);
    var by = camera_get_view_y(cam) + button[3] * camera_get_view_height(cam);
    var bw = button[4] * 256 * camera_get_view_width(cam) / max(256, camera_get_view_width(cam));
    var bh = button[5] * camera_get_view_height(cam);
    draw_set_alpha(held ? 0.84 : 0.54);
    draw_set_color(make_color_rgb(10, 23, 48));
    draw_roundrect(bx - bw, by - bh, bx + bw, by + bh, false);
    draw_set_alpha(0.88);
    draw_set_color(make_color_rgb(190, 225, 255));
    draw_roundrect(bx - bw, by - bh, bx + bw, by + bh, true);
    draw_text(bx, by, label);
};

global.androidTouchDraw = function()
{
    var showOption = global.androidTouchIsOptions();
    var showPad = room == rmPlayLevel && global.androidTouchEnabled;
    if (!showOption && !showPad)
    {
        return;
    }

    var alpha = draw_get_alpha();
    var color = draw_get_color();
    var font = draw_get_font();
    var halign = draw_get_halign();
    var valign = draw_get_valign();
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_set_font(global.MM3font);
    if (showOption)
    {
        global.androidTouchDrawButton(global.androidTouchOption,
            global.androidTouchEnabled ? "TOUCH CONTROLS ON" : "TOUCH CONTROLS OFF", false);
    }
    if (showPad)
    {
        for (var buttonIndex = 0; buttonIndex < array_length(global.androidTouchButtons); buttonIndex++)
        {
            var button = global.androidTouchButtons[buttonIndex];
            global.androidTouchDrawButton(button, button[1], global.androidTouchHeld[buttonIndex]);
        }
    }
    draw_set_halign(halign);
    draw_set_valign(valign);
    draw_set_font(font);
    draw_set_alpha(alpha);
    draw_set_color(color);
};

global.androidToggleTouch = function()
{
    global.androidTouchEnabled = !global.androidTouchEnabled;
    ini_open("AndroidControls.ini");
    ini_write_real("Controls", "Visible", global.androidTouchEnabled ? 1 : 0);
    ini_close();
};
