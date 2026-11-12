
// ---- Touch editor (rmBuilder) --------------------------------------------
// The desktop editor reads left (place), right (erase) and middle (drag the
// map) mouse buttons. On Android every builder read goes through
// global.androidMB / MBP / MBR, which turn the finger into the button for the
// tool picked on the side panels (the black bars beside the 8:7 editor).
//   Left  panel: TOOLS (PLACE / ERASE / MOVE / SELECT), RECENT, FAVORITES
//   Right panel: PLAY, UNDO / REDO, SAVE, gesture help
// Gestures: one finger draws with the tool, two fingers drag the map, pinch
// opens/closes the level map, holding still with PLACE erases (right click).
// A new touch waits a few frames before it becomes a click, so a second
// finger can turn it into a drag without placing anything, and the editor's
// hover state catches up with the finger.
global.androidEditTool = 0; // 0 place, 1 erase, 2 move, 3 select
global.androidEditBtn = -1;
global.androidEditPrevBtn = -1;
global.androidEditState = 0; // 0 none, 1 panel, 2 pending, 3 active, 4 pan, 5 tap release, 6 tap queued
global.androidEditFrames = 0;
global.androidEditActiveBtn = -1;
global.androidEditStartX = 0;
global.androidEditStartY = 0;
global.androidPinchStart = -1;
global.androidPinchDone = false;
global.androidPanelHit = "";
global.androidPanelFrames = 0;
global.androidEditOnUI = false;
global.androidEditLastDt = -1;
global.androidLongPressFrames = 28;

// ---- Recent / favourite pieces ----
global.androidRecent = [];
global.androidLastPiece = [-1, -1];
global.androidFavorites = [[-1, -1], [-1, -1], [-1, -1]];
ini_open("Settings/AndroidEditor.ini");
for (var _f = 0; _f < 3; _f++)
{
    global.androidFavorites[_f] = [ini_read_real("Favorites", "Cat" + string(_f), -1), ini_read_real("Favorites", "Opt" + string(_f), -1)];
}
ini_close();

global.androidSaveFavorites = function()
{
    ini_open("Settings/AndroidEditor.ini");
    for (var i = 0; i < 3; i++)
    {
        ini_write_real("Favorites", "Cat" + string(i), global.androidFavorites[i][0]);
        ini_write_real("Favorites", "Opt" + string(i), global.androidFavorites[i][1]);
    }
    ini_close();
};

global.androidCurrentPiece = function()
{
    var cat = global.selectedCategory;
    if (cat < 3 || cat > 8)
    {
        return [-1, -1];
    }
    return [cat, global.categorySelection[cat]];
};

// Same icon the editor's category bar shows: [sprite, frame] or [-1, 0].
global.androidPieceSprite = function(piece)
{
    if (piece[0] < 0)
    {
        return [-1, 0];
    }
    var spr = -1;
    var idx = 0;
    try
    {
        spr = getIconSpriteFromEnum(piece[0], piece[1]);
        idx = getIconIndexFromEnum(piece[0], piece[1]);
    }
    catch (e)
    {
        spr = -1;
    }
    if (!(is_numeric(spr) || is_handle(spr)) || !sprite_exists(spr))
    {
        return [-1, 0];
    }
    return [spr, idx];
};

global.androidTrackRecent = function()
{
    var piece = global.androidCurrentPiece();
    if (piece[0] < 0 || (piece[0] == global.androidLastPiece[0] && piece[1] == global.androidLastPiece[1]))
    {
        return;
    }
    global.androidLastPiece = piece;
    for (var i = array_length(global.androidRecent) - 1; i >= 0; i--)
    {
        var r = global.androidRecent[i];
        if (r[0] == piece[0] && r[1] == piece[1])
        {
            array_delete(global.androidRecent, i, 1);
        }
    }
    array_insert(global.androidRecent, 0, piece);
    if (array_length(global.androidRecent) > 3)
    {
        array_resize(global.androidRecent, 3);
    }
};

global.androidSelectPiece = function(piece)
{
    if (piece[0] < 0)
    {
        return;
    }
    global.categorySelection[piece[0]] = piece[1];
    global.selectedCategory = piece[0];
    global.selectedOptionPrev = global.selectedOption;
    global.selectedOption = piece[1];
    with (objBuilderGlobal)
    {
        changeCategory();
        changeCategoryOption();
    }
    if (global.androidEditTool == 1 || global.androidEditTool == 2)
    {
        global.androidSetTool(0);
    }
    playSFX(sfxMenuMove);
};

global.androidSetTool = function(tool)
{
    global.androidEditTool = tool;
    with (objBuilderGlobal)
    {
        editorTools.selectTool(tool == 3 ? 1 : 0);
    }
};

// ---- Undo / redo (one step per touch stroke, like Undodog) ----
global.androidUndoStack = [];
global.androidRedoStack = [];
global.androidUndoCurrent = [];
global.androidUndoRecording = false;
global.androidUndoFields = ["placedXscale", "placedYscale", "placedColor", "placedAngle", "placedNumber",
    "placedWeapon", "placedSpeed", "placedParameter1", "placedParameter2", "placedParameter3"];

global.androidUndoBegin = function()
{
    global.androidUndoCurrent = [];
    global.androidUndoRecording = true;
};

global.androidUndoEnd = function()
{
    global.androidUndoRecording = false;
    if (array_length(global.androidUndoCurrent) > 0)
    {
        array_push(global.androidUndoStack, global.androidUndoCurrent);
        if (array_length(global.androidUndoStack) > 60)
        {
            array_delete(global.androidUndoStack, 0, 1);
        }
        global.androidRedoStack = [];
    }
    global.androidUndoCurrent = [];
};

// From objBuilderPlacedObject's Create event.
global.androidUndoNoteAdd = function(inst)
{
    if (!global.androidUndoRecording || !instance_exists(inst))
    {
        return;
    }
    array_push(global.androidUndoCurrent, {kind: 0, inst: inst, x: inst.x, y: inst.y});
};

// From objBuilderPlacedObject's Destroy event.
global.androidUndoNoteDelete = function(inst)
{
    if (!global.androidUndoRecording || room != rmBuilder)
    {
        return;
    }
    with (inst)
    {
        if (!variable_instance_exists(id, "Data") || !is_struct(Data))
        {
            break;
        }
        var d = Data;
        var saved = {};
        for (var i = 0; i < array_length(global.androidUndoFields); i++)
        {
            var f = global.androidUndoFields[i];
            if (variable_struct_exists(d, f))
            {
                variable_struct_set(saved, f, variable_struct_get(d, f));
            }
        }
        array_push(global.androidUndoCurrent, {kind: 1, x: xstart, y: ystart, cat: d.placedCategory,
            opt: d.placedCategorySelection, msk: d.placedMask, fields: saved});
    }
};

// Reverts a recorded step and returns the step that reverts it back.
global.androidApplyStep = function(steps)
{
    global.androidUndoCurrent = [];
    global.androidUndoRecording = true;
    for (var i = array_length(steps) - 1; i >= 0; i--)
    {
        var a = steps[i];
        if (a.kind == 0)
        {
            if (instance_exists(a.inst))
            {
                var lay = 50;
                if (variable_instance_exists(a.inst, "Data") && is_struct(a.inst.Data) && variable_struct_exists(a.inst.Data, "lay"))
                {
                    lay = a.inst.Data.lay;
                }
                with (objBuilderGlobal)
                {
                    bldDelObject(a.x, a.y, true, true, a.inst, lay);
                }
            }
        }
        else
        {
            var made = noone;
            with (objBuilderGlobal)
            {
                if (a.cat == 3)
                {
                    // Tiles, spikes and ladders have their own add functions.
                    if (global.optionIsSpike[3][a.opt] == true)
                    {
                        bldAddSpike(a.x, a.y, a.opt, a.opt, a.msk);
                    }
                    else if (global.optionIsLadder[3][a.opt] == true)
                    {
                        bldAddLadder(a.x, a.y, a.opt, a.opt, a.msk);
                    }
                    else
                    {
                        bldAddTile(a.x, a.y, a.opt, a.msk);
                    }
                }
                else
                {
                    made = bldAddObject(a.x, a.y, a.cat, a.opt, a.msk);
                }
            }
            if (!is_bool(made) && !is_undefined(made) && instance_exists(made))
            {
                var keys = variable_struct_get_names(a.fields);
                for (var k = 0; k < array_length(keys); k++)
                {
                    setPlacedInstance(keys[k], made, variable_struct_get(a.fields, keys[k]));
                }
                made.xscale = made.Data.placedXscale;
                made.yscale = made.Data.placedYscale;
                made.number = made.Data.placedNumber;
                made.weapon = made.Data.placedWeapon;
                made.spdOpt = made.Data.placedSpeed;
                made.param1 = made.Data.placedParameter1;
                made.param2 = made.Data.placedParameter2;
            }
        }
    }
    global.androidUndoRecording = false;
    var inverse = global.androidUndoCurrent;
    global.androidUndoCurrent = [];
    return inverse;
};

global.androidUndo = function()
{
    var n = array_length(global.androidUndoStack);
    if (n == 0)
    {
        return;
    }
    var undoStep = global.androidUndoStack[n - 1];
    array_delete(global.androidUndoStack, n - 1, 1);
    array_push(global.androidRedoStack, global.androidApplyStep(undoStep));
    playSFX(sfxMenuSelect);
};

global.androidRedo = function()
{
    var n = array_length(global.androidRedoStack);
    if (n == 0)
    {
        return;
    }
    var redoStep = global.androidRedoStack[n - 1];
    array_delete(global.androidRedoStack, n - 1, 1);
    array_push(global.androidUndoStack, global.androidApplyStep(redoStep));
    playSFX(sfxMenuSelect);
};

global.androidSaveLevel = function()
{
    with (objBuilderGlobal)
    {
        if (catMenuOpen == false && (!variable_instance_exists(id, "canUseSave") || canUseSave == true))
        {
            saveLevelInit();
        }
    }
};

// ---- Mouse wrappers used by the builder code ----
global.androidMB = function(button)
{
    if (room != rmBuilder)
    {
        return mouse_check_button(button);
    }
    return global.androidEditBtn == button;
};

global.androidMBP = function(button)
{
    if (room != rmBuilder)
    {
        return mouse_check_button_pressed(button);
    }
    return global.androidEditBtn == button && global.androidEditPrevBtn != button;
};

global.androidMBR = function(button)
{
    if (room != rmBuilder)
    {
        return mouse_check_button_released(button);
    }
    return global.androidEditPrevBtn == button && global.androidEditBtn != button;
};

// ---- Panel layout (window pixels) ----
global.androidEditPanelsShown = function()
{
    return room == rmBuilder && global.androidDrawRect[0] >= 120;
};

// Returns an array of {id, x, y, w, h, side} for every panel control.
global.androidEditLayout = function()
{
    var r = global.androidDrawRect;
    var dw = window_get_width();
    var dh = window_get_height();
    var items = [];
    var lw = r[0];
    var rw = dw - (r[0] + r[2]);
    var lm = round(lw * 0.08);
    var rm = round(rw * 0.08);
    var lx = lm;
    var lwid = lw - lm * 2;
    var rx = r[0] + r[2] + rm;
    var rwid = rw - rm * 2;
    var tools = ["place", "erase", "move", "select"];
    for (var i = 0; i < 4; i++)
    {
        array_push(items, {id: tools[i], x: lx, y: round(dh * (0.06 + i * 0.131)), w: lwid, h: round(dh * 0.113)});
    }
    var slot = min(round(dh * 0.08), floor((lwid - 24) / 3));
    var gap = floor((lwid - slot * 3) / 2);
    for (var j = 0; j < 3; j++)
    {
        array_push(items, {id: "rec" + string(j), x: lx + j * (slot + gap), y: round(dh * 0.635), w: slot, h: slot});
        array_push(items, {id: "fav" + string(j), x: lx + j * (slot + gap), y: round(dh * 0.772), w: slot, h: slot});
    }
    array_push(items, {id: "play", x: rx, y: round(dh * 0.06), w: rwid, h: round(dh * 0.175)});
    var half = floor((rwid - 16) / 2);
    array_push(items, {id: "undo", x: rx, y: round(dh * 0.26), w: half, h: round(dh * 0.11)});
    array_push(items, {id: "redo", x: rx + half + 16, y: round(dh * 0.26), w: half, h: round(dh * 0.11)});
    array_push(items, {id: "save", x: rx, y: round(dh * 0.393), w: rwid, h: round(dh * 0.11)});
    return items;
};

global.androidEditPanelHit = function(px, py)
{
    var items = global.androidEditLayout();
    for (var i = 0; i < array_length(items); i++)
    {
        var b = items[i];
        if (px >= b.x && px <= b.x + b.w && py >= b.y && py <= b.y + b.h)
        {
            return b.id;
        }
    }
    return "";
};

// Panel press (finger down). Favourites act on release / long hold instead.
global.androidEditPanelPress = function(hit)
{
    switch (hit)
    {
        case "place": global.androidSetTool(0); playSFX(sfxMenuMove); break;
        case "erase": global.androidSetTool(1); playSFX(sfxMenuMove); break;
        case "move": global.androidSetTool(2); playSFX(sfxMenuMove); break;
        case "select": global.androidSetTool(3); playSFX(sfxMenuMove); break;
        case "play":
            with (objBuilderGlobal)
            {
                forcePlay = true;
            }
            break;
        case "undo": global.androidUndo(); break;
        case "redo": global.androidRedo(); break;
        case "save": global.androidSaveLevel(); break;
        default:
            if (string_copy(hit, 1, 3) == "rec")
            {
                var k = real(string_char_at(hit, 4));
                if (k < array_length(global.androidRecent))
                {
                    global.androidSelectPiece(global.androidRecent[k]);
                }
            }
    }
};

global.androidEditPanelRelease = function(hit, held)
{
    if (string_copy(hit, 1, 3) != "fav")
    {
        return;
    }
    var k = real(string_char_at(hit, 4));
    var fav = global.androidFavorites[k];
    if (held)
    {
        if (fav[0] >= 0)
        {
            global.androidFavorites[k] = [-1, -1];
            global.androidSaveFavorites();
            playSFX(sfxMenuMove);
        }
    }
    else if (fav[0] >= 0)
    {
        global.androidSelectPiece(fav);
    }
    else
    {
        var piece = global.androidCurrentPiece();
        if (piece[0] >= 0)
        {
            global.androidFavorites[k] = piece;
            global.androidSaveFavorites();
            playSFX(sfxMenuSelect);
        }
    }
};

global.androidInPanels = function(px)
{
    var r = global.androidDrawRect;
    return global.androidEditPanelsShown() && (px < r[0] || px > r[0] + r[2]);
};

// ---- Touch → mouse buttons. Called at the start of objBuilderGlobal's Step.
global.androidBuilderInput = function()
{
    // Only once per game frame, or a "pressed" would vanish before Draw.
    if (global.androidEditLastDt == global.roomDt)
    {
        return;
    }
    global.androidEditLastDt = global.roomDt;
    global.androidEditPrevBtn = global.androidEditBtn;
    global.androidTrackRecent();
    with (objBuilderGlobal)
    {
        var gameSelect = editorTools.is("selection");
        if (gameSelect && global.androidEditTool != 3)
        {
            global.androidEditTool = 3;
        }
        else if (!gameSelect && global.androidEditTool == 3)
        {
            global.androidEditTool = 0;
        }
    }
    var f0 = device_mouse_check_button(0, mb_left);
    var f1 = device_mouse_check_button(1, mb_left);
    if (!f0 && !f1)
    {
        // A tap that went down and up inside one frame.
        if (global.androidEditState == 0 && device_mouse_check_button_pressed(0, mb_left))
        {
            var tx = device_mouse_raw_x(0);
            var ty = device_mouse_raw_y(0);
            if (global.androidInPanels(tx))
            {
                var quick = global.androidEditPanelHit(tx, ty);
                global.androidEditPanelPress(quick);
                global.androidEditPanelRelease(quick, false);
                global.androidEditBtn = -1;
                return;
            }
            // Let Draw see the new finger position once, click next frame.
            global.androidEditState = 6;
            global.androidEditBtn = -1;
            return;
        }
        if (global.androidEditState == 1)
        {
            global.androidEditPanelRelease(global.androidPanelHit, false);
        }
        if (global.androidEditState == 6)
        {
            global.androidEditState = 2;
        }
        // A quick tap ended while still waiting: deliver it as a click now
        // (press this frame, release next frame).
        if (global.androidEditState == 2)
        {
            var tapButton = global.androidEditChooseButton(false);
            if (tapButton == mb_left || tapButton == mb_right)
            {
                global.androidUndoBegin();
                global.androidEditState = 5;
                global.androidEditBtn = tapButton;
                return;
            }
        }
        if (global.androidUndoRecording)
        {
            global.androidUndoEnd();
        }
        global.androidEditState = 0;
        global.androidEditBtn = -1;
        global.androidPinchStart = -1;
        return;
    }
    if (global.androidEditState == 0)
    {
        var px = device_mouse_raw_x(0);
        var py = device_mouse_raw_y(0);
        if (global.androidInPanels(px))
        {
            global.androidEditState = 1;
            global.androidPanelHit = global.androidEditPanelHit(px, py);
            global.androidPanelFrames = 0;
            global.androidEditPanelPress(global.androidPanelHit);
        }
        else
        {
            global.androidEditState = 2;
            global.androidEditFrames = 0;
            global.androidEditStartX = px;
            global.androidEditStartY = py;
        }
    }
    if (global.androidEditState == 1)
    {
        global.androidPanelFrames++;
        if (global.androidPanelFrames == 40 && string_copy(global.androidPanelHit, 1, 3) == "fav")
        {
            global.androidEditPanelRelease(global.androidPanelHit, true);
            global.androidPanelHit = "";
        }
        global.androidEditBtn = -1;
        return;
    }
    if (f1 && global.androidEditState != 4)
    {
        global.androidEditState = 4;
    }
    if (global.androidEditState == 4)
    {
        // Two fingers drag the map; pinching in/out opens/closes the level map.
        if (f0 && f1)
        {
            var dist = point_distance(device_mouse_raw_x(0), device_mouse_raw_y(0), device_mouse_raw_x(1), device_mouse_raw_y(1));
            if (global.androidPinchStart < 0)
            {
                global.androidPinchStart = dist;
                global.androidPinchDone = false;
            }
            else if (!global.androidPinchDone && global.androidPinchStart > 0)
            {
                var ratio = dist / global.androidPinchStart;
                if ((ratio < 0.6 && !global.mapOpen) || (ratio > 1.6 && global.mapOpen))
                {
                    global.mapOpen = !global.mapOpen;
                    global.androidPinchDone = true;
                    playSFX(sfxMenuMove);
                }
            }
        }
        global.androidEditBtn = mb_middle;
        return;
    }
    if (global.androidEditState == 2)
    {
        global.androidEditFrames++;
        if (global.androidEditFrames < 4)
        {
            global.androidEditBtn = -1;
            return;
        }
        var longPress = false;
        if (global.androidEditTool == 0)
        {
            // PLACE: drawing starts once the finger moves; holding still is a
            // long press (right click = erase), like the PC right button.
            var moved = point_distance(device_mouse_raw_x(0), device_mouse_raw_y(0), global.androidEditStartX, global.androidEditStartY) > 14;
            if (!moved)
            {
                if (global.androidEditFrames < global.androidLongPressFrames)
                {
                    global.androidEditBtn = -1;
                    return;
                }
                longPress = true;
            }
        }
        global.androidEditActiveBtn = global.androidEditChooseButton(longPress);
        global.androidEditState = 3;
        global.androidUndoBegin();
    }
    global.androidEditBtn = global.androidEditActiveBtn;
};

// Which mouse button the current touch stands for, given the picked tool.
// Editor UI (bars, menus, buttons) always gets a plain left click.
global.androidEditChooseButton = function(longPress)
{
    var onUI = true;
    with (objBuilderGlobal)
    {
        onUI = isMouseOnUI() || catMenuOpen || menuOpen || !global.canUseEditor;
    }
    global.androidEditOnUI = onUI;
    if (onUI)
    {
        return mb_left;
    }
    if (longPress || global.androidEditTool == 1)
    {
        return mb_right;
    }
    if (global.androidEditTool == 2)
    {
        return mb_middle;
    }
    return mb_left;
};

// ---- Drawing ----
global.androidPanelColors = function(active)
{
    return active ? [make_color_rgb(40, 120, 230), c_white] : [make_color_rgb(22, 28, 60), make_color_rgb(150, 190, 255)];
};

global.androidDrawBox = function(b, fill, edge, radius)
{
    draw_set_alpha(1);
    draw_set_color(fill);
    draw_roundrect_ext(b.x, b.y, b.x + b.w, b.y + b.h, radius, radius, false);
    draw_set_color(edge);
    draw_roundrect_ext(b.x, b.y, b.x + b.w, b.y + b.h, radius, radius, true);
    draw_roundrect_ext(b.x + 1, b.y + 1, b.x + b.w - 1, b.y + b.h - 1, radius, radius, true);
};

global.androidDrawIcon = function(spr, cx, cy, size, alpha, frame = 0)
{
    if (spr < 0)
    {
        return;
    }
    var iw = sprite_get_width(spr);
    var ih = sprite_get_height(spr);
    var k = max(1, floor(size / max(iw, ih)));
    if (max(iw, ih) * k > size * 1.05)
    {
        k = size / max(iw, ih);
    }
    draw_sprite_ext(spr, frame, cx - (iw * k) / 2 + sprite_get_xoffset(spr) * k,
        cy - (ih * k) / 2 + sprite_get_yoffset(spr) * k, k, k, 0, c_white, alpha);
};

global.androidDrawLabel = function(text, x, y, maxW, maxH, color)
{
    draw_set_color(color);
    var s = clamp(floor(min(maxW / max(1, string_width(text)), maxH / 8)), 2, 5);
    draw_text_transformed(x, y, text, s, s, 0);
};

global.androidDrawSlot = function(b, piece, isFav)
{
    var c = global.androidPanelColors(false);
    global.androidDrawBox(b, c[0], c[1], 20);
    var icon = global.androidPieceSprite(piece);
    if (icon[0] >= 0)
    {
        global.androidDrawIcon(icon[0], b.x + b.w / 2, b.y + b.h / 2, b.w * 0.72, 1, icon[1]);
    }
    else if (isFav)
    {
        draw_set_halign(fa_center);
        global.androidDrawLabel("+", b.x + b.w / 2, b.y + b.h / 2, b.w * 0.5, b.h * 0.5, c[1]);
    }
};

global.androidDrawArrow = function(cx, cy, size, flip)
{
    var d = flip ? -1 : 1;
    draw_set_color(c_white);
    draw_triangle(cx - d * size * 0.5, cy, cx - d * size * 0.05, cy - size * 0.35, cx - d * size * 0.05, cy + size * 0.35, false);
    draw_rectangle(min(cx - d * size * 0.1, cx + d * size * 0.45), cy - size * 0.12, max(cx - d * size * 0.1, cx + d * size * 0.45), cy + size * 0.12, false);
};

// Window-pixel overlay, drawn right after the game surface.
global.androidDrawEditorPanels = function()
{
    if (!global.androidEditPanelsShown())
    {
        return;
    }
    var font = draw_get_font();
    draw_set_font(global.MM3font);
    draw_set_valign(fa_middle);
    var dh = window_get_height();
    var items = global.androidEditLayout();
    var headColor = make_color_rgb(140, 160, 210);
    var toolIcons = {place: sprEditorToolPencil, erase: sprTrashIcon, move: sprCursorHand, select: sprEditorToolSelection};
    var toolNames = {place: "PLACE", erase: "ERASE", move: "MOVE", select: "SELECT"};
    var toolIds = {place: 0, erase: 1, move: 2, select: 3};
    // One text size for every tool label, fitted to the longest ("SELECT").
    var t0 = items[0];
    var toolScale = clamp(floor(min((t0.w - t0.h * 1.05) / string_width("SELECT"), t0.h * 0.32 / 8)), 2, 5);
    for (var i = 0; i < array_length(items); i++)
    {
        var b = items[i];
        var id_ = b.id;
        if (variable_struct_exists(toolIds, id_))
        {
            var on = global.androidEditTool == variable_struct_get(toolIds, id_);
            var c = global.androidPanelColors(on);
            global.androidDrawBox(b, c[0], c[1], 26);
            global.androidDrawIcon(variable_struct_get(toolIcons, id_), b.x + b.h * 0.5, b.y + b.h / 2, b.h * 0.55, 1);
            draw_set_halign(fa_left);
            draw_set_color(c_white);
            draw_text_transformed(b.x + b.h * 0.95, b.y + b.h / 2, variable_struct_get(toolNames, id_), toolScale, toolScale, 0);
        }
        else if (string_copy(id_, 1, 3) == "rec")
        {
            var k = real(string_char_at(id_, 4));
            global.androidDrawSlot(b, (k < array_length(global.androidRecent)) ? global.androidRecent[k] : [-1, -1], false);
        }
        else if (string_copy(id_, 1, 3) == "fav")
        {
            global.androidDrawSlot(b, global.androidFavorites[real(string_char_at(id_, 4))], true);
        }
        else if (id_ == "play")
        {
            global.androidDrawBox(b, make_color_rgb(60, 170, 90), make_color_rgb(200, 255, 210), 30);
            global.androidDrawIcon(sprPlayButton, b.x + b.h * 0.42, b.y + b.h / 2, b.h * 0.5, 1);
            draw_set_halign(fa_left);
            draw_set_color(c_white);
            var ps = clamp(floor((b.w - b.h * 0.85) / string_width("PLAY")), 2, 6);
            draw_text_transformed(b.x + b.h * 0.8, b.y + b.h / 2, "PLAY", ps, ps, 0);
        }
        else if (id_ == "undo" || id_ == "redo")
        {
            var can = (id_ == "undo") ? array_length(global.androidUndoStack) > 0 : array_length(global.androidRedoStack) > 0;
            var cc = global.androidPanelColors(false);
            global.androidDrawBox(b, cc[0], can ? cc[1] : c_dkgray, 26);
            draw_set_alpha(can ? 1 : 0.35);
            global.androidDrawArrow(b.x + b.w / 2, b.y + b.h * 0.38, b.h * 0.42, id_ == "redo");
            draw_set_halign(fa_center);
            global.androidDrawLabel(string_upper(id_), b.x + b.w / 2, b.y + b.h * 0.78, b.w * 0.8, b.h * 0.2, c_white);
            draw_set_alpha(1);
        }
        else if (id_ == "save")
        {
            var cs = global.androidPanelColors(false);
            global.androidDrawBox(b, cs[0], cs[1], 26);
            var ds = b.h * 0.5;
            var dx = b.x + b.h * 0.35;
            var dy = b.y + (b.h - ds) / 2;
            draw_set_color(make_color_rgb(120, 170, 255));
            draw_rectangle(dx, dy, dx + ds, dy + ds, false);
            draw_set_color(make_color_rgb(230, 240, 255));
            draw_rectangle(dx + ds * 0.22, dy, dx + ds * 0.78, dy + ds * 0.36, false);
            draw_set_color(make_color_rgb(40, 60, 120));
            draw_rectangle(dx + ds * 0.18, dy + ds * 0.58, dx + ds * 0.82, dy + ds, false);
            draw_set_halign(fa_left);
            draw_set_color(c_white);
            draw_text_transformed(b.x + b.h * 1.1, b.y + b.h / 2, "SAVE", toolScale, toolScale, 0);
        }
    }
    // Section headers and gesture help.
    var r = global.androidDrawRect;
    var lx = round(r[0] * 0.08) + 4;
    var rx = r[0] + r[2] + round((window_get_width() - r[0] - r[2]) * 0.08) + 4;
    draw_set_halign(fa_left);
    var hs = max(2, floor(dh / 400));
    draw_set_color(headColor);
    draw_text_transformed(lx, dh * 0.035, "TOOLS", hs, hs, 0);
    draw_text_transformed(lx, dh * 0.61, "RECENT", hs, hs, 0);
    draw_text_transformed(lx, dh * 0.747, "FAVORITES", hs, hs, 0);
    draw_text_transformed(rx, dh * 0.035, "LEVEL", hs, hs, 0);
    draw_text_transformed(rx, dh * 0.545, "GESTURES", hs, hs, 0);
    draw_set_color(make_color_rgb(200, 210, 240));
    var tips = ["1 FINGER : DRAW", "2 FINGERS: SCROLL", "PINCH    : MAP", "HOLD     : ERASE"];
    for (var t = 0; t < 4; t++)
    {
        draw_text_transformed(rx, dh * (0.6 + t * 0.045), tips[t], hs, hs, 0);
    }
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
    draw_set_font(font);
};
