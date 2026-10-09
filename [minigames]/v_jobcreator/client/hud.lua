-- Key help at the bottom of the screen, depending on what the editor is doing.

local sw, sh = guiGetScreenSize()
local KEY = CREATOR.KEYS.menu:upper()

local function hint()
    local tool = Tools.current
    if tool and tool.type == "place" then
        return "PLACING " .. (tool.kind == "object" and (CATALOG.objectName[tool.model] or "object") or Kinds[tool.kind].label):upper()
            .. "   LMB place   ·   Wheel rotate (Shift faster, Alt finer)   ·   Backspace stop"
    elseif tool and tool.type == "move" then
        return "MOVING   " .. (tool.follow and "follows the cursor   ·   " or "")
            .. "Arrows / PgUp / PgDn move   ·   Num 4/6 8/2 7/9 rotate   ·   Wheel turn   ·   G follow   ·   End to ground   ·   Shift x8, Alt fine   ·   Enter / LMB drop   ·   Backspace cancel"
    end
    if Editor.camMode == "free" then
        return KEY .. " menu   ·   F5 on foot   ·   WASD / Q / E fly, Shift fast, Alt slow   ·   hold RMB look   ·   LMB select   ·   Del delete   ·   Ctrl+Z / Y undo / redo"
    end
    return KEY .. " menu   ·   F5 free camera   ·   X on an element: edit (Q/E switch)   ·   Ctrl+Z / Y undo / redo"
end

addEventHandler("onClientRender", root, function()
    if not Editor.active or Editor.photo or Editor.testing then return end
    if not Editor.doc then
        if not Menus.isOpen() then
            dxDrawText("JOB CREATOR   ·   " .. KEY .. " menu", 0, sh - 34, sw, sh - 8, tocolor(255, 255, 255, 220), 1, "default-bold", "center", "center")
        end
        return
    end
    local text = hint()
    local w = dxGetTextWidth(text, 1, "default-bold") + 24
    dxDrawRectangle((sw - w) / 2, sh - 34, w, 26, tocolor(0, 0, 0, 170))
    dxDrawText(text, 0, sh - 34, sw, sh - 8, tocolor(255, 255, 255, 230), 1, "default-bold", "center", "center")

    -- object counter + crosshair for on-foot placing
    local doc = Editor.doc
    dxDrawText(doc.name .. (Editor.dirty and "  *" or "") .. "\nObjects " .. #doc.objects .. " / " .. CREATOR.LIMITS.objects
        .. "   ·   Spawns " .. #Editor.spawnList() .. " / " .. doc.maxPlayers,
        20, sh - 110, sw, sh - 40, tocolor(255, 255, 255, 200), 1, "default-bold", "left", "bottom")
    if Tools.current and not (Editor.camMode == "free" and isCursorShowing()) then
        dxDrawRectangle(sw / 2 - 2, sh / 2 - 2, 4, 4, tocolor(255, 255, 255, 230))
    end
end)
