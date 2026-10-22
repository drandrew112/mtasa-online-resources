-- Stat trackers: labelled values stacked in the bottom-right corner (e.g. "Enemies left  6").
--
-- Retained mode: the caller adds a row once and updates it on change, ui_core draws it every
-- frame. When a timer (drawTimer) was drawn in the last TIMER_GRACE ms the stack sits above it.
-- Rows belong to the resource that added them and go away when it stops.
--
--   exports.ui_core:addStatTracker("gw_left", "Enemies left", 6, { order = 2 })
--   exports.ui_core:updateStatTracker("gw_left", 5)
--   exports.ui_core:removeStatTracker("gw_left")
--   optional bar under a row: opts.progress (0..1) + opts.barColor, or updateStatTracker(id, value, nil, progress)

local TIMER_GRACE = 250

UI.stats = {
    rows = {},          -- id -> { id, label, value, order, seq, color, progress, barColor, owner }
    list = {},          -- sorted rows (bottom first)
    seq = 0,
    timerTick = 0,      -- set by UI:drawTimer
}

local S = UI.stats

local function rebuild()
    local list = {}
    for _, row in pairs(S.rows) do list[#list + 1] = row end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.seq < b.seq
    end)
    S.list = list
end

function UI.stats:set(id, label, value, opts, owner)
    local row = self.rows[id]
    if not row then
        self.seq = self.seq + 1
        row = { id = id, seq = self.seq }
        self.rows[id] = row
    end
    row.label = tostring(label or "")
    row.value = tostring(value == nil and "" or value)
    row.order = tonumber(opts and opts.order) or row.order or 0
    row.color = opts and type(opts.color) == "table" and opts.color or row.color
    row.progress = opts and tonumber(opts.progress) or nil
    row.barColor = opts and type(opts.barColor) == "table" and opts.barColor or row.barColor
    row.owner = owner or row.owner
    rebuild()
    return true
end

function UI.stats:update(id, value, label, progress)
    local row = self.rows[id]
    if not row then return false end
    if value ~= nil then row.value = tostring(value) end
    if label ~= nil then row.label = tostring(label) end
    if progress == false then row.progress = nil
    elseif progress ~= nil then row.progress = tonumber(progress) or row.progress end
    return true
end

function UI.stats:remove(id)
    if not self.rows[id] then return false end
    self.rows[id] = nil
    rebuild()
    return true
end

-- every row of one owner (resource)
function UI.stats:clearOwner(owner)
    local changed = false
    for id, row in pairs(self.rows) do
        if row.owner == owner then
            self.rows[id] = nil
            changed = true
        end
    end
    if changed then rebuild() end
    return changed
end

function UI.stats:draw()
    local list = self.list
    if #list == 0 then return end

    local scale = ui(1.7)
    local h = 25 * scale
    local gap = ui(4)
    local pad = 5

    -- one column width for every row, so labels and values line up
    local w = 0
    for _, row in ipairs(list) do
        local rw = L.width(row.label, scale, "default", true) + L.width(row.value, scale, "default-bold", true) + pad * 2 + ui(30)
        if rw > w then w = rw end
    end

    local x = UI.slots.bottomRight.x - w
    local y = UI.slots.bottomRight.y
    if getTickCount() - self.timerTick < TIMER_GRACE then y = y - h - gap end

    for _, row in ipairs(list) do
        y = y - h
        dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 160))
        local c = row.color
        local col = c and tocolor(c[1] or 255, c[2] or 255, c[3] or 255) or tocolor(255, 255, 255)
        dxDrawText(row.label, x + pad, y, x + w - pad, y + h, tocolor(200, 200, 200), scale, "default", "left", "center", false, false, false, true)
        dxDrawText(row.value, x + pad, y, x + w - pad, y + h, col, scale, "default-bold", "right", "center", false, false, false, true)
        if row.progress then
            local p = math.max(0, math.min(1, row.progress))
            local bh = math.max(2, ui(4))
            local bc = row.barColor or c or { 0, 170, 220 }
            dxDrawRectangle(x, y + h - bh, w, bh, tocolor(255, 255, 255, 40))
            dxDrawRectangle(x, y + h - bh, w * p, bh, tocolor(bc[1] or 255, bc[2] or 255, bc[3] or 255, 230))
        end
        y = y - gap
    end
end

addEventHandler("onClientResourceStop", root, function(res)
    if res ~= resource then UI.stats:clearOwner(res) end
end)
