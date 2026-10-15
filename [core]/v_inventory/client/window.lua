-- The inventory window (cursor mode). Left: the player's slots and the open container (a container
-- in a slot). Right: the other side (port, trunk, a container) or, in the own inventory, the details
-- of the selected item. Moves: drag & drop, double click (quick move), the » / « buttons; Shift
-- moves one piece of a stack; dropping a slot item outside the window puts it down.
-- The server sends whole views (inv:open / inv:view); every move is a request it checks.

WindowOpen = false
local View            -- the last view
local byUid = {}      -- uid -> { v, side = "slot" | "left" | "right", slot }
local st = { openSlot = nil, sel = nil, press = nil, drag = nil, scroll = { left = 0, right = 0 }, regions = {} }
local cursorX, cursorY = 0, 0
local WindowLayout = false   -- the last drawn frame's rectangles (getUiLayout)

addEvent("inv:open", true)
addEvent("inv:view", true)
addEvent("inv:closed", true)

-- ---------------------------------------------------------------------------------------------
-- View bookkeeping
-- ---------------------------------------------------------------------------------------------

local function index()
    byUid = {}
    if not View then return end
    for _, slot in ipairs(INV.SLOTS) do
        local v = View.slots[slot]
        if v then
            byUid[v.u] = { v = v, side = "slot", slot = slot }
            for _, it in ipairs(v.items or {}) do byUid[it.u] = { v = it, side = "left", container = v.u } end
        end
    end
    for _, it in ipairs(View.other and View.other.items or {}) do byUid[it.u] = { v = it, side = "right" } end
end

-- The slot whose container is shown on the left
local function openContainer()
    if not View then return nil end
    local v = st.openSlot and View.slots[st.openSlot]
    if v and v.cap then return v end
    for _, slot in ipairs(INV.SLOTS) do
        local c = View.slots[slot]
        if c and c.cap then
            st.openSlot = slot
            return c
        end
    end
    return nil
end

local function setView(view)
    View = view
    if type(View.slots) ~= "table" then View.slots = {} end
    index()
    if st.sel and not byUid[st.sel] then st.sel = nil end
    openContainer()
end

local closedTick = 0

local function close(tellServer)
    if not WindowOpen then return end
    WindowOpen = false
    closedTick = getTickCount()
    View, st.press, st.drag, st.sel = nil, nil, nil, nil
    showCursor(false)
    setElementData(localPlayer, INV_DATA.OPEN, false, false)
    if tellServer then triggerServerEvent("inv:close", resourceRoot) end
end

addEventHandler("inv:open", resourceRoot, function(view)
    if not TextsLoaded then return triggerServerEvent("inv:close", resourceRoot) end
    if type(view) ~= "table" then return end
    st.openSlot, st.sel, st.scroll = nil, nil, { left = 0, right = 0 }
    setView(view)
    if not WindowOpen then
        WindowOpen = true
        showCursor(true)
        setElementData(localPlayer, INV_DATA.OPEN, true, false)
    end
end)

addEventHandler("inv:view", resourceRoot, function(view)
    if WindowOpen then setView(view) end
end)

addEventHandler("inv:closed", resourceRoot, function() close(false) end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if WindowOpen then
        showCursor(false)
        setElementData(localPlayer, INV_DATA.OPEN, false, false)
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Requests
-- ---------------------------------------------------------------------------------------------

local function freeSlotFor(v)
    local def = ITEMS[v.d]
    if not def then return nil end
    if def.back and not def.holdable then return not View.slots.back and "back" or nil end
    if not def.holdable then return nil end
    local first = def.hand == "right" and "right" or "left"
    local second = first == "left" and "right" or "left"
    if not View.slots[first] then return first end
    if not View.slots[second] then return second end
    return nil
end

local function requestMove(uid, target, one)
    if not View or View.readOnly or not target then return end
    local info = byUid[uid]
    if not info then return end
    triggerServerEvent("inv:move", resourceRoot, uid, target, one and 1 or nil)
end

-- Where a double click / the arrow buttons send the item
local function quickTarget(uid)
    local info = byUid[uid]
    if not info then return nil end
    local container = openContainer()
    if info.side == "right" then
        if container then return { kind = "container", uid = container.u } end
        local slot = freeSlotFor(info.v)
        return slot and { kind = "slot", slot = slot } or nil
    end
    if View.other then return { kind = "other" } end
    if info.side == "left" then
        local slot = freeSlotFor(info.v)
        return slot and { kind = "slot", slot = slot } or nil
    end
    return nil
end

-- ---------------------------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------------------------

local function region(x, y, w, h, kind, data)
    local r = { x = x, y = y, w = w, h = h, kind = kind }
    if data then for k, v in pairs(data) do r[k] = v end end
    st.regions[#st.regions + 1] = r
    return r
end

local function hitAt(px, py)
    for i = #st.regions, 1, -1 do
        local r = st.regions[i]
        if px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h then return r end
    end
    return nil
end

local function isHover(x, y, w, h)
    return cursorX >= x and cursorX <= x + w and cursorY >= y and cursorY <= y + h
end

local TAGS = {
    ["in"] = { "v_inventory.ui.tag_put_in", "warn" },
    out = { "v_inventory.ui.tag_take", "warn" },
    lockIn = { "v_inventory.ui.tag_not_accepted", "off" },
    lockOut = { "v_inventory.ui.tag_cannot_take", "off" },
}

-- One item row. compact: the two-column own inventory
local function drawRow(v, x, y, w, h, side, compact)
    local dragging = st.drag and st.drag.uid == v.u
    local selected = st.sel == v.u
    local suggest = v.st == "in" or v.st == "out"
    local locked = v.st == "lockIn" or v.st == "lockOut"
    local bg = suggest and tocolor(44, 40, 28, 255) or ((selected or isHover(x, y, w, h)) and C.tile2 or C.tile)
    Round(x, y, w, h, S(5), bg)
    if suggest then Outline(x, y, w, h, S(2), C.warn)
    elseif selected then Outline(x, y, w, h, S(2), C.accent) end
    local isz = h - S(compact and 12 or 16)
    DrawIcon(v.d, x + S(6), y + (h - isz) / 2, isz, (locked or dragging) and 120 or 255)
    local tx = x + S(6) + isz + S(10)
    local textCol = (locked or dragging) and C.off or C.text
    local amount = AmountText(v)
    local rightW = S(compact and 120 or 110)
    if compact then
        Text(Fit(ItemName(v.d), x + w - rightW - tx, 12, true), tx, y, w, h, textCol, 12, true)
        Text(amount or "", x + w - rightW, y, S(60), h, textCol, 12, true, "right")
        Text(WeightText(v.w), x + w - S(54), y, S(48), h, C.muted, 9, false, "right")
    else
        local lines = DisplayLines(v)
        local sub = lines[1] and (lines[1][1] .. ": " .. lines[1][2]) or ItemDesc(v.d)
        local tag = TAGS[v.st]
        local tagW = 0
        if tag then
            local label = L(tag[1])
            tagW = TextW(label, 9, true) + S(16)
            local col = C[tag[2]]
            local tgx = x + w - rightW - tagW
            Round(tgx, y + S(9), tagW, S(20), S(4), tocolor(255, 255, 255, 18))
            Outline(tgx, y + S(9), tagW, S(20), 1, col)
            Text(label, tgx, y + S(9), tagW, S(20), col, 9, true, "center")
        end
        local textW = x + w - rightW - tagW - tx - S(8)
        Text(Fit(ItemName(v.d), textW, 13, true), tx, y + S(4), w, h * 0.5, textCol, 13, true)
        Text(Fit(sub, textW, 10), tx, y + h * 0.5 - S(2), w, h * 0.5 - S(2), C.muted, 10)
        Text(amount or "", x + w - S(14) - S(60), y + S(4), S(60), h * 0.5, textCol, 13, true, "right")
        Text(WeightText(v.w), x + w - S(14) - S(80), y + h * 0.5 - S(2), S(80), h * 0.5 - S(2), C.muted, 10, false, "right")
    end
    region(x, y, w, h, "row", { uid = v.u, side = side })
end

-- A list of rows with scrolling; returns nothing (regions for the rows are added)
local function drawList(items, x, y, w, h, side, compact)
    local rowH, gap = S(compact and 40 or 54), S(6)
    local cols = compact and 2 or 1
    local colW = (w - (cols - 1) * S(14)) / cols
    local rowsTotal = math.ceil(#items / cols)
    local visible = math.max(1, math.floor((h + gap) / (rowH + gap)))
    local maxScroll = math.max(0, rowsTotal - visible)
    st.scroll[side] = math.max(0, math.min(st.scroll[side] or 0, maxScroll))
    local first = st.scroll[side] * cols
    for i = first + 1, math.min(#items, first + visible * cols) do
        local idx = i - first - 1
        local col, row = idx % cols, math.floor(idx / cols)
        drawRow(items[i], x + col * (colW + S(14)), y + row * (rowH + gap), colW, rowH, side, compact)
    end
    if maxScroll > 0 then
        local bh = h * visible / rowsTotal
        local by = y + (h - bh) * (st.scroll[side] / maxScroll)
        dxDrawRectangle(x + w + S(4), by, S(3), bh, C.muted)
    end
end

local function weightHeader(x, y, w, used, cap)
    if not cap then
        Text(WeightText(used), x, y, w, S(20), C.text, 11, true, "right")
        return
    end
    local frac = used / math.max(0.01, cap)
    Text(L("v_inventory.ui.used_of", { used = ("%.1f"):format(used), cap = ("%g"):format(cap) }), x, y, w, S(18), C.text, 11, true, "right")
    Bar(x + w - S(200), y + S(22), S(200), S(7), frac, frac < 0.75 and C.good or C.warn)
end

local SLOT_LABEL = { left = "v_inventory.ui.left_hand", right = "v_inventory.ui.right_hand", back = "v_inventory.ui.back" }

local function drawSlotCard(slot, x, y, w, h)
    local v = View.slots[slot]
    local selected = v and v.cap and st.openSlot == slot
    Round(x, y, w, h, S(7), (v and isHover(x, y, w, h)) and C.tile2 or C.tile)
    if selected then Outline(x, y, w, h, S(2), C.accent) end
    if v and st.sel == v.u and not selected then Outline(x, y, w, h, S(2), C.blue) end
    Text(L(SLOT_LABEL[slot]), x + S(12), y + S(4), w, S(22), C.muted, 9, true)
    if v then
        local dragging = st.drag and st.drag.uid == v.u
        DrawIcon(v.d, x + S(12), y + S(30), S(36), dragging and 120 or 255)
        local info = v.cap and L("v_inventory.ui.used_of", { used = ("%.1f"):format(v.used or 0), cap = ("%g"):format(v.cap) }) or WeightText(v.w)
        Text(Fit(ItemName(v.d), w - S(66), 12, true), x + S(56), y + S(30), w, S(20), dragging and C.off or C.text, 12, true)
        Text(info, x + S(56), y + S(50), w, S(18), C.muted, 10)
    else
        Outline(x + S(12), y + S(30), S(36), S(36), 1, C.off)
        local note = slot == "back" and L("v_inventory.ui.backpacks_only") or L("v_inventory.ui.empty")
        Text(note, x + S(56), y + S(30), w, S(36), C.off, 11)
    end
    region(x, y, w, h, "slot", { slot = slot, uid = v and v.u or nil })
end

local function drawDetails(x, y, w, h)
    Round(x, y, w, h, S(7), C.tile)
    Text(L("v_inventory.ui.selected"), x + S(16), y + S(8), w, S(22), C.muted, 9, true)
    local info = st.sel and byUid[st.sel]
    if not info then
        Text(L("v_inventory.ui.select_item"), x + S(16), y + S(40), w - S(32), S(22), C.off, 11)
        return
    end
    local v = info.v
    DrawIcon(v.d, x + S(16), y + S(36), S(54))
    Text(Fit(ItemName(v.d), w - S(100), 16, true), x + S(84), y + S(38), w, S(26), C.text, 16, true)
    local desc = ItemDesc(v.d)
    Text(Fit(desc, w - S(100), 10), x + S(84), y + S(64), w, S(20), C.muted, 10)
    local ly = y + S(108)
    if type(v.bar) == "table" then
        local max = math.max(1, tonumber(v.bar.max) or 100)
        local val = tonumber(v.bar.value) or 0
        Text(L.upper(L.resolve(v.bar.label or "")), x + S(16), ly, w, S(20), C.muted, 9, true)
        Text(("%d%%"):format(math.floor(val / max * 100 + 0.5)), x + S(16), ly, w - S(32), S(20), C.text, 12, true, "right")
        Bar(x + S(16), ly + S(24), w - S(32), S(9), val / max, C.blue)
        ly = ly + S(48)
    end
    local def = ITEMS[v.d] or {}
    local rows = DisplayLines(v)
    local amount = AmountText(v)
    if amount then rows[#rows + 1] = { L("v_inventory.ui.amount"), amount } end
    rows[#rows + 1] = { L("v_inventory.ui.weight"), WeightText(v.w) }
    if v.cap then rows[#rows + 1] = { L("v_inventory.ui.capacity"), L("v_inventory.ui.used_of", { used = ("%.1f"):format(v.used or 0), cap = ("%g"):format(v.cap) }) } end
    local where = def.holdable and L("v_inventory.ui.where_hand") or (def.back and L("v_inventory.ui.where_back")) or L("v_inventory.ui.where_container")
    rows[#rows + 1] = { L("v_inventory.ui.carried_in"), where }
    for _, r in ipairs(rows) do
        Text(Fit(r[1], w * 0.45, 11), x + S(16), ly, w, S(24), C.muted, 11)
        Text(Fit(r[2], w * 0.5, 11, true), x + S(16), ly, w - S(32), S(24), C.text, 11, true, "right")
        ly = ly + S(26)
        if ly > y + h - S(30) then break end
    end
end

local function drawTooltip(v)
    local lines = DisplayLines(v)
    local amount = AmountText(v)
    if amount then lines[#lines + 1] = { L("v_inventory.ui.amount"), amount } end
    lines[#lines + 1] = { L("v_inventory.ui.weight"), WeightText(v.w) }
    local w, lh = S(320), S(22)
    local h = S(42) + #lines * lh + S(8)
    local x, y = math.min(cursorX + S(18), SW - w - S(8)), math.min(cursorY + S(18), SH - h - S(8))
    Round(x, y, w, h, S(7), tocolor(10, 12, 16, 245))
    Outline(x, y, w, h, 1, tocolor(70, 76, 90))
    Text(Fit(ItemName(v.d), w - S(28), 13, true), x + S(14), y + S(8), w, S(26), C.text, 13, true)
    for i, l in ipairs(lines) do
        local ly = y + S(36) + (i - 1) * lh
        Text(Fit(l[1], S(110), 11), x + S(14), ly, w, lh, C.muted, 11)
        Text(Fit(l[2], w - S(150), 11, true), x + S(130), ly, w, lh, C.text, 11, true)
    end
end

-- ---------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------

local function headerTexts()
    local o = View.other
    if not o then return L("v_inventory.ui.inventory"), getPlayerName(localPlayer):gsub("#%x%x%x%x%x%x", "") end
    if o.kind == "port" then
        local sub = o.sub and L.upper(L.resolve(o.sub)) or ""
        return L.resolve(o.title or L.msg("v_inventory.ui.storage")), L("v_inventory.ui.port_sub", { name = sub })
    elseif o.kind == "trunk" then
        return L.resolve(o.title), o.sub and L("v_inventory.ui.trunk_sub", { plate = o.sub }) or L.upper(L("v_inventory.ui.trunk"))
    end
    return ItemName(o.def), View.readOnly and L("v_inventory.ui.view_only") or L("v_inventory.ui.container_sub")
end

local function drawWindow()
    st.regions = {}
    local W, H = S(1420), S(840)
    local X, Y = (SW - W) / 2, (SH - H) / 2
    region(X, Y, W, H, "window")
    Round(X, Y, W, H, S(9), C.bg)
    Round(X, Y, W, S(66), S(9), C.head)
    dxDrawRectangle(X, Y + S(56), W, S(10), C.head)
    dxDrawRectangle(X + S(4), Y, W - S(8), S(4), C.accent)
    local title, sub = headerTexts()
    Text(sub, X + S(24), Y + S(12), W - S(200), S(20), C.muted, 9, true)
    Text(title, X + S(24), Y + S(30), W - S(200), S(30), C.text, 16, true)
    local cx = X + W - S(24) - S(110)
    KeyChip(cx, Y + S(21), "ESC", L("v_inventory.ui.close"))
    region(cx, Y + S(21), S(110), S(24), "close")

    local y = Y + S(84)
    local bannerRect
    if View.banner then
        local bw = W - S(48)
        bannerRect = { X + S(24), y, bw, S(36) }
        Round(X + S(24), y, bw, S(36), S(6), tocolor(255, 185, 60, 40))
        Outline(X + S(24), y, bw, S(36), 1, C.warn)
        Text(Fit(L.resolve(View.banner), bw - S(32), 11, true), X + S(40), y, bw, S(36), C.warn, 11, true)
        y = y + S(52)
    end

    local other = View.other
    local LX = X + S(24)
    local LW = other and S(640) or S(960)
    local bottom = Y + H - S(64)

    -- left: slots
    if other then
        Text(L("v_inventory.ui.you"), LX, y, LW, S(18), C.muted, 9, true)
        y = y + S(20)
    end
    local cw = (LW - 2 * S(14)) / 3
    for i, slot in ipairs(INV.SLOTS) do drawSlotCard(slot, LX + (i - 1) * (cw + S(14)), y, cw, S(80)) end
    local cy = y + S(98)

    -- left: the open container
    local container = openContainer()
    if container then
        Text(L("v_inventory.ui.open_container"), LX, cy, LW, S(18), C.muted, 9, true)
        Text(Fit(ItemName(container.d), LW - S(230), 14, true), LX, cy + S(18), LW, S(26), C.text, 14, true)
        weightHeader(LX + LW - S(220), cy, S(220), container.used or 0, container.cap)
        local lines = DisplayLines(container)
        local ly = cy + S(48)
        if #lines > 0 then
            local parts = {}
            for i, l in ipairs(lines) do
                if i > 3 then break end
                parts[#parts + 1] = l[1] .. "  " .. l[2]
            end
            Text(Fit(table.concat(parts, "   ·   "), LW, 10), LX, ly, LW, S(18), C.muted, 10)
            ly = ly + S(24)
        end
        local areaY, areaH = ly, bottom - ly
        region(LX, areaY, LW, areaH, "leftArea", { uid = container.u })
        if #(container.items or {}) == 0 then
            Text(L("v_inventory.ui.container_empty"), LX, areaY, LW, S(40), C.off, 11, false, "center")
        end
        drawList(container.items or {}, LX, areaY, LW, areaH, "left", not other)
    else
        Text(L("v_inventory.ui.no_container"), LX, cy, LW, S(40), C.off, 11)
    end

    -- right
    if other then
        local RX, RW = X + W - S(24) - S(640), S(640)
        local mx = (LX + LW + RX) / 2
        for i, b in ipairs({ { "»", "btnRight" }, { "«", "btnLeft" } }) do
            local by = Y + H / 2 - S(50) + (i - 1) * S(60)
            Round(mx - S(22), by, S(44), S(44), S(6), isHover(mx - S(22), by, S(44), S(44)) and C.tile2 or C.tile)
            Text(b[1], mx - S(22), by, S(44), S(44), C.text, 18, true, "center")
            region(mx - S(22), by, S(44), S(44), b[2])
        end
        local ry = Y + S(84) + (View.banner and S(52) or 0)
        Text(L(other.kind == "port" and "v_inventory.ui.port" or (other.kind == "trunk" and "v_inventory.ui.trunk_upper" or "v_inventory.ui.container")),
            RX, ry, RW, S(18), C.muted, 9, true)
        weightHeader(RX + RW - S(220), ry, S(220), other.used or 0, other.cap)
        local lines = DisplayLines(other)
        if #lines > 0 then
            local parts = {}
            for i, l in ipairs(lines) do
                if i > 3 then break end
                parts[#parts + 1] = l[1] .. "  " .. l[2]
            end
            Text(Fit(table.concat(parts, "   ·   "), RW - S(230), 10), RX, ry + S(20), RW - S(230), S(18), C.muted, 10)
        end
        local areaY = ry + S(48)
        local areaH = bottom - areaY
        region(RX, areaY, RW, areaH, "rightArea")
        local items = other.items or {}
        drawList(items, RX, areaY, RW, areaH, "right", false)
        local used = math.min(#items, math.floor((areaH + S(6)) / S(60))) * S(60)
        if not View.readOnly and areaH - used > S(70) then
            local dy = areaY + used + S(4)
            local dh = math.min(S(100), areaH - used - S(8))
            Outline(RX, dy, RW, dh, 1, tocolor(80, 86, 100))
            Text(L("v_inventory.ui.drop_here"), RX, dy, RW, dh, C.off, 11, false, "center")
        end
    else
        local DX = LX + LW + S(24)
        drawDetails(DX, Y + S(84), X + W - S(24) - DX, bottom - Y - S(84))
    end

    -- footer
    local fy = Y + H - S(44)
    dxDrawRectangle(X, fy - S(8), W, 1, tocolor(255, 255, 255, 18))
    if View.readOnly then
        Text(L("v_inventory.ui.view_only_hint"), X + S(24), fy, W, S(24), C.off, 11)
    else
        local kx = X + S(24)
        kx = KeyChip(kx, fy, L("v_inventory.ui.key_drag"), L("v_inventory.ui.hint_move"))
        kx = KeyChip(kx, fy, L("v_inventory.ui.key_double_click"), L("v_inventory.ui.hint_quick_move"))
        kx = KeyChip(kx, fy, "Shift", L("v_inventory.ui.hint_one_piece"))
        KeyChip(kx, fy, L("v_inventory.ui.key_drag_out"), L("v_inventory.ui.hint_put_down"))
    end

    -- layout for other resources (tutorials): the regions of this frame
    local layout = { rect = { X, Y, W, H }, kind = other and other.kind or "own", banner = bannerRect or false,
        slots = {}, rows = {} }
    for _, r in ipairs(st.regions) do
        local rect = { r.x, r.y, r.w, r.h }
        if r.kind == "slot" then
            local v = View.slots[r.slot]
            layout.slots[r.slot] = { rect = rect, d = v and v.d or false, cap = v and v.cap and true or false }
        elseif r.kind == "row" then
            local info = byUid[r.uid]
            layout.rows[#layout.rows + 1] = { rect = rect, side = r.side, d = info and info.v.d or false }
        elseif r.kind == "leftArea" or r.kind == "rightArea" or r.kind == "btnRight" or r.kind == "btnLeft" then
            layout[r.kind] = rect
        end
    end
    WindowLayout = layout

    -- dragged item / tooltip
    if st.drag then
        local info = byUid[st.drag.uid]
        if info then
            DrawIcon(info.v.d, cursorX - S(22), cursorY - S(22), S(44), 220)
            if getKeyState("lshift") or getKeyState("rshift") then
                Text("x1", cursorX + S(24), cursorY - S(10), S(40), S(20), C.warn, 12, true)
            end
        end
    elseif other then
        local hit = hitAt(cursorX, cursorY)
        local info = hit and hit.kind == "row" and byUid[hit.uid]
        if info then drawTooltip(info.v) end
    end
end

addEventHandler("onClientRender", root, function()
    WindowLayout = false
    if not WindowOpen or not View then return end
    if isPedDead(localPlayer) or isPedInVehicle(localPlayer) then return close(true) end
    local o = View.origin
    if o and o[1] then
        local x, y, z = getElementPosition(localPlayer)
        if getDistanceBetweenPoints3D(x, y, z, o[1], o[2], o[3]) > (View.range or INV.SESSION_RANGE) then return close(true) end
    end
    if not isCursorShowing() then showCursor(true) end
    local cx, cy = getCursorPosition()
    if cx then cursorX, cursorY = cx * SW, cy * SH end
    drawWindow()
end, true, "low-5")

-- ---------------------------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------------------------

local function dropTarget(hit, uid)
    local info = byUid[uid]
    if not info then return nil end
    if not hit then
        -- outside the window: put down (slot items only)
        return info.side == "slot" and { kind = "ground" } or nil
    end
    if hit.kind == "slot" then
        local target = View.slots[hit.slot]
        if target and target.cap and target.u ~= uid then return { kind = "container", uid = target.u } end
        if target and target.u == uid then return nil end
        return { kind = "slot", slot = hit.slot }
    elseif hit.kind == "leftArea" then
        if info.side == "left" and info.container == hit.uid then return nil end
        return { kind = "container", uid = hit.uid }
    elseif hit.kind == "row" then
        if hit.side == "left" then
            local c = openContainer()
            if not c or (info.side == "left" and info.container == c.u) then return nil end
            return { kind = "container", uid = c.u }
        elseif hit.side == "right" and info.side ~= "right" then
            return { kind = "other" }
        end
    elseif hit.kind == "rightArea" then
        if info.side == "right" then return nil end
        return { kind = "other" }
    end
    return nil
end

local function shiftDown() return getKeyState("lshift") or getKeyState("rshift") end

addEventHandler("onClientClick", root, function(button, state, ax, ay)
    if not WindowOpen or not View or button ~= "left" then return end
    cursorX, cursorY = ax, ay
    local hit = hitAt(ax, ay)
    if state == "down" then
        st.press, st.drag = nil, nil
        if not hit then return end
        if hit.kind == "close" then return close(true) end
        if hit.kind == "btnRight" or hit.kind == "btnLeft" then
            local info = st.sel and byUid[st.sel]
            if info and ((hit.kind == "btnRight") == (info.side ~= "right")) then
                requestMove(st.sel, quickTarget(st.sel), shiftDown())
            end
            return
        end
        if hit.kind == "slot" then
            local v = View.slots[hit.slot]
            if v and v.cap then st.openSlot = hit.slot end
        end
        if (hit.kind == "row" or hit.kind == "slot") and hit.uid then
            st.sel = hit.uid
            if not View.readOnly then st.press = { uid = hit.uid, x = ax, y = ay } end
        end
    else
        local drag = st.drag
        st.press, st.drag = nil, nil
        if drag then requestMove(drag.uid, dropTarget(hit, drag.uid), shiftDown()) end
    end
end)

addEventHandler("onClientCursorMove", root, function(_, _, ax, ay)
    if not WindowOpen then return end
    cursorX, cursorY = ax, ay
    local p = st.press
    if p and not st.drag and (math.abs(ax - p.x) > 6 or math.abs(ay - p.y) > 6) then
        st.drag = { uid = p.uid }
    end
end)

addEventHandler("onClientDoubleClick", root, function(button, ax, ay)
    if not WindowOpen or not View or View.readOnly or button ~= "left" then return end
    local hit = hitAt(ax, ay)
    if hit and (hit.kind == "row" or hit.kind == "slot") and hit.uid then
        st.press, st.drag = nil, nil
        requestMove(hit.uid, quickTarget(hit.uid), shiftDown())
    end
end)

addEventHandler("onClientKey", root, function(key, press)
    if not WindowOpen then return end
    if key == "mouse_wheel_up" or key == "mouse_wheel_down" then
        cancelEvent()
        local hit = hitAt(cursorX, cursorY)
        local side = hit and ((hit.kind == "rightArea" or (hit.kind == "row" and hit.side == "right")) and "right"
            or ((hit.kind == "leftArea" or (hit.kind == "row" and hit.side == "left")) and "left"))
        if side then st.scroll[side] = (st.scroll[side] or 0) + (key == "mouse_wheel_up" and -1 or 1) end
        return
    end
    if not press then return end
    if key == "escape" or key == INV.KEY_INVENTORY then
        cancelEvent()
        close(true)
    end
end)

-- The own inventory key
bindKey(INV.KEY_INVENTORY, "down", function()
    if WindowOpen or not TextsLoaded or getTickCount() - closedTick < 300 then return end
    if isCursorShowing() or OtherPanelOpen() or isPedDead(localPlayer) or isPedInVehicle(localPlayer) then return end
    triggerServerEvent("inv:openOwn", resourceRoot)
end)

-- ---------------------------------------------------------------------------------------------
-- Layout export (e.g. the blood transport tutorial highlights parts of the window and the HUD)
-- ---------------------------------------------------------------------------------------------

-- -> { window = false | { rect, kind = "own" | "port" | "trunk" | "container", banner = rect | false,
--        slots = { left/right/back = { rect, d, cap } }, rows = { { rect, side = "left" | "right", d } },
--        leftArea, rightArea, btnRight, btnLeft = rect },
--      hud = rect | false }      rect = { x, y, w, h }, d = item definition id
function getUiLayout()
    return { window = WindowOpen and WindowLayout or false, hud = HudRect or false }
end
