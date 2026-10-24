if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- SETTINGS: the pause menu's settings through the ui_pause Settings API, plus
-- Preferences (acc_savesys, through the server).
-- Category tiles on the page; a category opens as a view: Up / Down pick a
-- setting, Left / Right (or Enter / click) change it right away.

local categories = nil   -- cached ui_pause categories (refreshed on change)

local function pauseRunning()
    local res = getResourceFromName("ui_pause")
    return res and getResourceState(res) == "running"
end

local function refresh()
    categories = pauseRunning() and exports.ui_pause:getSettingsCategories() or {}
end

addEvent("ui_pause:onClientSettingChanged")
addEventHandler("ui_pause:onClientSettingChanged", localPlayer, function()
    if Menu.open then refresh() end
end)

-- Settings > Models: the download state shown in the rows / description changed
addEvent("onClientModelStatusChange")
addEventHandler("onClientModelStatusChange", localPlayer, function()
    if Menu.open and categories then refresh() end
end)

-- our own categories, after the ui_pause ones
local function ownCategories()
    local prefs = (Menu.data.profile or {}).preferences or {}
    return {
        {
            id = "preferences", label = L("acc_menu.settings.preferences"), own = true,
            items = {
                { id = "spawnLocation", label = L("acc_menu.prefs.spawn_location"), desc = L("acc_menu.prefs.spawn_desc"),
                  type = "choice", available = true,
                  valueText = prefs.spawnLocation == "random" and L("acc_menu.prefs.random") or L("acc_menu.prefs.last"),
                  step = function() togglePreference("spawnLocation") end },
            },
        },
    }
end

local function allCategories()
    if not categories then refresh() end
    local out = {}
    for _, c in ipairs(categories) do out[#out + 1] = c end
    for _, c in ipairs(ownCategories()) do out[#out + 1] = c end
    return out
end

local function categoryById(id)
    for _, c in ipairs(allCategories()) do
        if c.id == id then return c end
    end
end

local function stepItem(cat, item, dir)
    if not item.available then return end
    if cat.own then
        item.step()
    else
        exports.ui_pause:stepSetting(item.id, dir)
        refresh()
    end
end

PAGES.defs.settings = {
    label = "acc_menu.page.settings",
    onShow = refresh,
    onMenuOpen = function() categories = nil end,
    draw = function(x, y, w, h)
        local cats = allCategories()
        local cols = math.min(4, #cats)
        local rows = math.max(1, math.ceil(#cats / cols))
        local at = Grid(x, y, w, math.min(h, rows * S(190) + (rows - 1) * S(14)), cols, rows)
        for i, cat in ipairs(cats) do
            local c = (i - 1) % cols + 1
            local r = math.floor((i - 1) / cols) + 1
            local tx, ty, tw, th = at(c, r)
            local names = {}
            for j, item in ipairs(cat.items) do
                if j > 3 then names[#names + 1] = "…" break end
                names[#names + 1] = item.label
            end
            tile("page", "set_" .. cat.id, tx, ty, tw, th, cat.label, nil, function(cx, cy, cw, ch)
                text(table.concat(names, ", "), cx, cy + ch - S(48), cw, S(48), C.dim, 0.9, FONT.row, "left", "bottom", true, true)
            end, function() Menu.openView("settings_cat", { id = cat.id }) end)
        end
    end,
}

VIEWS.settings_cat = {
    title = function(args)
        local cat = categoryById(args.id)
        return cat and cat.label or ""
    end,
    onOpen = refresh,
    draw = function(x, y, w, h, args)
        local cat = categoryById(args.id)
        if not cat then return end
        local lw = math.floor(w * 0.62)
        local rh = S(54)
        local focusedItem
        for i, item in ipairs(cat.items) do
            local ry = y + (i - 1) * rh
            if ry + rh > y + h then break end
            local isAction = item.type == "action"
            local focused = row("view", "si_" .. tostring(item.id), x, ry, lw, rh - S(4), {
                activate = function() stepItem(cat, item, 1) end,
                -- an action only runs on Enter / click, the arrows move the focus
                left = (not isAction) and function() stepItem(cat, item, -1) end or nil,
                right = (not isAction) and function() stepItem(cat, item, 1) end or nil,
            })
            if focused then focusedItem = item end
            local color = item.available and C.white or C.dim
            text(item.label, x + S(20), ry, lw * 0.55, rh - S(4), color, 1.0, FONT.rowB)

            local vx, vw = x + lw * 0.5, lw * 0.5 - S(20)
            if not item.available then
                text(L("acc_menu.settings.unavailable"), vx, ry, vw, rh - S(4), C.dim, 0.95, FONT.row, "right")
            elseif item.type == "range" then
                local frac = ((tonumber(item.value) or item.min) - item.min) / math.max(1, item.max - item.min)
                bar(vx + vw - S(300), ry + (rh - S(4)) / 2 - S(3), S(180), S(6), frac)
                text(item.valueText, vx + vw - S(110), ry, S(110), rh - S(4), C.white, 0.95, FONT.rowB, "right")
            elseif item.type == "toggle" then
                chip(item.valueText, vx + vw - textW(item.valueText, 0.85, FONT.rowB) - S(14), ry + (rh - S(4)) / 2 - S(11),
                    item.value and C.money or C.dim, item.value and tocolor(110, 220, 130, 40) or nil)
            elseif item.type == "action" then
                -- Enter / click runs it (Settings > Models > Download)
                local label = tostring(item.valueText or "") .. "   ›"
                chip(label, vx + vw - textW(label, 0.85, FONT.rowB) - S(14), ry + (rh - S(4)) / 2 - S(11), C.white, C.accentDim)
            else
                text("‹   " .. tostring(item.valueText) .. "   ›", vx, ry, vw, rh - S(4), C.white, 1.0, FONT.rowB, "right")
            end
        end
        -- description of the focused setting
        local dx, dw = x + lw + S(14), w - lw - S(14)
        panelBox(dx, y, dw, S(200))
        if focusedItem then
            text(focusedItem.label, dx + S(22), y + S(18), dw - S(44), S(28), C.white, 1.1, FONT.head)
            text(focusedItem.desc or "", dx + S(22), y + S(56), dw - S(44), S(130), C.dim, 0.95, FONT.row, "left", "top", true, true)
        end
    end,
}
