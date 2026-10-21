-- Hands & back HUD (bottom right): what the player holds and wears, the display lines of the held
-- items (meta.display, e.g. from / to of a blood box), a container summary and the keys.
-- The server sends the data (inv:hud) whenever any of it changes.

Hud = {}  -- slot -> item view
HudRect = false   -- where the last frame drew it (getUiLayout)

addEvent("inv:hud", true)
addEventHandler("inv:hud", resourceRoot, function(slots)
    Hud = type(slots) == "table" and slots or {}
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("inv:requestHud", resourceRoot)
end)

local SLOT_TAG = { left = "L", right = "R", back = "BACK" }
local MAX_LINES = 4

local function rowsOf()
    local rows = {}
    for _, slot in ipairs(INV.SLOTS) do
        local v = Hud[slot]
        local lines = {}
        if v then
            for i, line in ipairs(DisplayLines(v)) do
                if i > MAX_LINES then break end
                lines[#lines + 1] = line
            end
            if v.cap and #lines < MAX_LINES then
                lines[#lines + 1] = { L("v_inventory.ui.contents"), L("v_inventory.ui.n_items", { count = v.n or 0 }) }
            end
            if type(v.bar) == "table" and #lines < MAX_LINES then
                local bar = v.bar
                lines[#lines + 1] = { L.resolve(bar.label or ""), ("%d%%"):format(math.floor((tonumber(bar.value) or 0)
                    / math.max(1, tonumber(bar.max) or 100) * 100 + 0.5)) }
            end
        end
        rows[#rows + 1] = { slot = slot, v = v, lines = lines }
    end
    return rows
end

local function draw()
    if not (Hud.left or Hud.right or Hud.back) then return end
    local rows = rowsOf()
    local pad, rowH, lineH = S(14), S(40), S(19)
    local w = S(390)
    local h = pad + S(20)
    for _, r in ipairs(rows) do h = h + rowH + #r.lines * lineH end
    h = h + S(38) + pad * 0.5
    local x, y = SW - w - S(30), SH - h - S(230)
    HudRect = { x, y, w, h }

    Round(x, y, w, h, S(7), C.bg)
    dxDrawRectangle(x, y + S(4), S(4), h - S(8), C.accent)
    Text(L("v_inventory.ui.hands_and_back"), x + pad + S(4), y + pad * 0.5, w, S(22), C.muted, 10, true)
    local ry = y + pad + S(20)
    for _, r in ipairs(rows) do
        local tagW = r.slot == "back" and S(42) or S(24)
        local tx = x + pad + S(4)
        Round(tx, ry + S(8), tagW, rowH - S(16), S(4), C.tile)
        Text(SLOT_TAG[r.slot], tx, ry + S(8), tagW, rowH - S(16), C.text, 9, true, "center")
        local nx = tx + tagW + S(10)
        local v = r.v
        if v then
            local isz = rowH - S(14)
            DrawIcon(v.d, nx, ry + S(7), isz)
            local name = ItemName(v.d)
            local amount = AmountText(v)
            if amount then name = name .. "  " .. amount end
            local right = v.cap and L("v_inventory.ui.used_of", { used = ("%.1f"):format(v.used or 0), cap = ("%g"):format(v.cap) })
                or WeightText(v.w)
            local rw = TextW(right, 10) + S(4)
            Text(Fit(name, x + w - pad - rw - (nx + isz + S(8)) - S(8), 13, true), nx + isz + S(8), ry, w, rowH, C.text, 13, true)
            Text(right, x + w - pad - rw, ry, rw, rowH, C.muted, 10, false, "right")
        else
            Text(L("v_inventory.ui.empty"), nx, ry, w, rowH, C.off, 12)
        end
        ry = ry + rowH
        for _, line in ipairs(r.lines) do
            Text(Fit(line[1], S(84), 10), nx + S(4), ry, S(86), lineH, C.muted, 10)
            Text(Fit(line[2], x + w - pad - (nx + S(92)), 10, true), nx + S(92), ry, w, lineH, C.text, 10, true)
            ry = ry + lineH
        end
    end
    local kx, ky = x + pad + S(4), ry + S(8)
    if Hud.left or Hud.right then kx = KeyChip(kx, ky, INV.KEY_DROP:upper(), L("v_inventory.ui.put_down")) end
    KeyChip(kx, ky, INV.KEY_INVENTORY:upper(), L("v_inventory.ui.inventory"))
end

addEventHandler("onClientRender", root, function()
    HudRect = false
    if not TextsLoaded or WindowOpen or isPedInVehicle(localPlayer) then return end
    if getElementData(localPlayer, "hideHUD") or isPlayerMapVisible() then return end
    draw()
end)
