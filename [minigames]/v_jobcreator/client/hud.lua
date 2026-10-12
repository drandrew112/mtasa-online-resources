if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Key help at the bottom of the screen, depending on what the editor is doing.

local sw, sh = guiGetScreenSize()
local KEY = CREATOR.KEYS.menu:upper()

local function hint()
    local tool = Tools.current
    if tool and tool.type == "place" then
        return L("v_jobcreator.hud.placing_lmb_place_wheel_rotate_shift", { label = (tool.kind == "object" and (CATALOG.objectName[tool.model] or "object") or Kinds[tool.kind].label):upper() })
    elseif tool and tool.type == "move" then
        return L("v_jobcreator.hud.moving_arrows_pgup_pgdn_move_num", { follow = (tool.follow and L("v_jobcreator.hud.follows_cursor") or "") })
    end
    if Editor.camMode == "free" then
        return L("v_jobcreator.hud.menu_f5_on_foot_wasd_q", { key = KEY })
    end
    return L("v_jobcreator.hud.menu_f5_free_camera_x_on", { key = KEY })
end

addEventHandler("onClientRender", root, function()
    if not Editor.active or Editor.photo or Editor.testing then return end
    if not Editor.doc then
        if not Menus.isOpen() then
            dxDrawText(L("v_jobcreator.hud.job_creator_menu", { key = KEY }), 0, sh - 34, sw, sh - 8, tocolor(255, 255, 255, 220), 1, "default-bold", "center", "center")
        end
        return
    end
    local text = hint()
    local w = L.width(text, 1, "default-bold") + 24
    dxDrawRectangle((sw - w) / 2, sh - 34, w, 26, tocolor(0, 0, 0, 170))
    dxDrawText(text, 0, sh - 34, sw, sh - 8, tocolor(255, 255, 255, 230), 1, "default-bold", "center", "center")

    -- object counter + crosshair for on-foot placing
    local doc = Editor.doc
    dxDrawText(L("v_jobcreator.hud.objects_spawns", { name = doc.name, dirty = (Editor.dirty and "  *" or ""), objects = #doc.objects, objects2 = CREATOR.LIMITS.objects, spawn_list = #Editor.spawnList(), max_players = doc.maxPlayers }),
        20, sh - 110, sw, sh - 40, tocolor(255, 255, 255, 200), 1, "default-bold", "left", "bottom")
    if Tools.current and not (Editor.camMode == "free" and isCursorShowing()) then
        dxDrawRectangle(sw / 2 - 2, sh / 2 - 2, 4, 4, tocolor(255, 255, 255, 230))
    end
end)
