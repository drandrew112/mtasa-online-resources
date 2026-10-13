if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Sign-in screen: unit type, auto plate, crew list (add / remove).

Login = {
    vehicle  = nil,
    unitType = nil,
    members  = {},
    selected = nil,
    picker   = false,
}

local s = Gfx.s

local TYPE_HINTS = {}
local function build_TYPE_HINTS()
TYPE_HINTS = {
    SOLO = L("med_erm.login.single_responder"),
    DOC  = L("med_erm.login.physician_unit"),
    BLS  = L("med_erm.login.basic_life_support"),
    ALS  = L("med_erm.login.advanced_life_support"),
    HELI = L("med_erm.login.air_ambulance"),
}
end

function Login.reset(vehicle)
    Login.vehicle  = vehicle
    Login.members  = { localPlayer }
    Login.unitNumber = ""
    Login.selected = nil
    Login.picker   = false
end

local function nearbyPlayers()
    local out = {}
    local px, py, pz = getElementPosition(localPlayer)
    for _, p in ipairs(getElementsByType("player", root, true)) do
        if p ~= localPlayer then
            local x, y, z = getElementPosition(p)
            local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            local added = false
            for _, m in ipairs(Login.members) do if m == p then added = true end end
            if d <= Config.ADD_MEMBER_RADIUS and not added and Tablet.hasMedicRole(p) then
                out[#out + 1] = { player = p, dist = d }
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end

-- Unit number input (ui_core text input). Empty = assigned by the server.
local numberToken

local function editUnitNumber()
    local res = getResourceFromName("ui_core")
    if not res or getResourceState(res) ~= "running" then return end
    numberToken = exports.ui_core:openTextInput(L("med_erm.login.unit_number_empty_automatic"), 3, Login.unitNumber)
end

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    if token ~= numberToken then return end
    numberToken = nil
    if not text then return end
    text = text:gsub("%s", "")
    if text ~= "" and not text:match("^%d+$") then
        State.notify(L("med_erm.case.ems_tablet"), L("med_erm.login.unit_number_can_only_contain_digits"))
        return
    end
    Login.unitNumber = text
end)

local function field(label, value, x, y, w, tag)
    Gfx.label(label, x, y, w)
    Gfx.round(x, y + s(18), w, s(34), s(6), Theme.panel)
    Gfx.text(value, x + s(12), y + s(18), w - s(70), s(34), Theme.text, Gfx.font(11, true))
    if tag then
        local tw = L.width(tag, 1, Gfx.font(7, true)) + s(12)
        Gfx.round(x + w - tw - s(8), y + s(27), tw, s(16), s(8), Theme.panel2)
        Gfx.text(tag, x + w - tw - s(8), y + s(27), tw, s(16), Theme.dim, Gfx.font(7, true), "center")
    end
end

function Login.draw(x, y, w, h)
    -- drop members that left the server
    for i = #Login.members, 1, -1 do
        if not isElement(Login.members[i]) then table.remove(Login.members, i) end
    end
    if Login.selected and not isElement(Login.selected) then Login.selected = nil end

    local pad = s(20)
    local ix, iy, iw = x + pad, y + s(14), w - pad * 2
    Gfx.text(L("med_erm.login.unit_sign_in"), ix, iy, iw, s(26), Theme.text, Gfx.font(15, true))
    Gfx.text(L("med_erm.login.register_your_crew_to_start_shift"), ix, iy + s(24), iw, s(18), Theme.dim, Gfx.font(9))

    local colY = iy + s(56)
    local lw = iw * 0.47
    local rx, rw = ix + lw + s(20), iw - lw - s(20)

    -- left column ---------------------------------------------------------
    local veh = Login.vehicle
    field(L("med_erm.login.vehicle_plate"), isElement(veh) and getVehiclePlateText(veh) or "-", ix, colY, lw, L("med_erm.login.badge_auto"))
    local ny = colY + s(62)
    local nhov = Gfx.hover(ix, ny + s(18), lw, s(34))
    field(L("med_erm.login.unit_number"), Login.unitNumber ~= "" and Login.unitNumber or "", ix, ny, lw, L("med_erm.login.badge_edit"))
    if Login.unitNumber == "" then
        Gfx.text(L("med_erm.login.automatic"), ix + s(12), ny + s(18), lw - s(70), s(34), Theme.faint, Gfx.font(11))
    end
    if nhov then Gfx.round(ix, ny + s(50), lw, s(2), s(1), Theme.accent) end
    Gfx.hit(ix, ny + s(18), lw, s(34), editUnitNumber)

    local ty = colY + s(124)
    Gfx.label(L("med_erm.login.unit_type"), ix, ty, lw)
    local n = #Config.UNIT_TYPES
    local gap = s(6)
    local bw = (lw - gap * (n - 1)) / n
    for i, t in ipairs(Config.UNIT_TYPES) do
        local selected = Login.unitType == t
        Gfx.button(ix + (i - 1) * (bw + gap), ty + s(18), bw, s(36), t, {
            color = selected and { 224, 60, 49 } or { 39, 46, 55 },
            textColor = selected and Theme.text or Theme.dim,
        }, function() Login.unitType = t end)
    end
    Gfx.text(Login.unitType and TYPE_HINTS[Login.unitType] or L("med_erm.login.select_type_of_your_unit"),
        ix, ty + s(58), lw, s(18), Theme.dim, Gfx.font(9))

    -- right column: crew ----------------------------------------------------
    Gfx.label(L("med_erm.detail.crew", { members = #Login.members }), rx, colY, rw)
    local listY, rowH = colY + s(18), s(32)
    local listH = s(150)
    Gfx.round(rx, listY, rw, listH, s(6), Theme.panel)

    local visible = math.floor((listH - s(8)) / rowH)
    local offset = Gfx.getScroll("crew", #Login.members - visible)
    Gfx.scrollArea("crew", rx, listY, rw, listH)
    for i = 1 + offset, math.min(#Login.members, offset + visible) do
        local p = Login.members[i]
        local ry = listY + s(4) + (i - 1 - offset) * rowH
        local sel = Login.selected == p
        local hov = Gfx.hover(rx + s(4), ry, rw - s(8), rowH)
        if sel then
            Gfx.round(rx + s(4), ry, rw - s(8), rowH, s(4), tocolor(224, 60, 49, 90))
        elseif hov then
            Gfx.round(rx + s(4), ry, rw - s(8), rowH, s(4), Theme.panel2)
        end
        local name = getPlayerName(p):gsub("#%x%x%x%x%x%x", "")
        Gfx.text(Gfx.fit(name, rw - s(80), Gfx.font(10)), rx + s(14), ry, rw - s(80), rowH, Theme.text, Gfx.font(10))
        if p == localPlayer then
            Gfx.text(L("med_erm.login.you"), rx, ry, rw - s(16), rowH, Theme.faint, Gfx.font(8, true), "right")
        end
        Gfx.hit(rx + s(4), ry, rw - s(8), rowH, function() Login.selected = p end)
    end

    local by = listY + listH + s(8)
    local hbw = (rw - s(8)) / 2
    Gfx.button(rx, by, hbw, s(34), L("med_erm.login.add"), {}, function() Login.picker = true end)
    Gfx.button(rx + hbw + s(8), by, hbw, s(34), L("med_erm.login.remove"), {
        disabled = not Login.selected or Login.selected == localPlayer,
    }, function()
        for i, m in ipairs(Login.members) do
            if m == Login.selected then table.remove(Login.members, i) break end
        end
        Login.selected = nil
    end)

    -- footer ----------------------------------------------------------------
    local fy = y + h - s(58)
    dxDrawRectangle(ix, fy - s(10), iw, 1, Theme.line)
    Gfx.text(L("med_erm.login.only_on_duty_medics_within_m", { add_member_radius = Config.ADD_MEMBER_RADIUS }),
        ix, fy, iw - s(170), s(42), Theme.faint, Gfx.font(9))
    Gfx.button(ix + iw - s(160), fy, s(160), s(42), L("med_erm.login.sign_in"), {
        color = { 46, 160, 67 },
        font = Gfx.font(11, true),
        disabled = not Login.unitType,
    }, function()
        Tablet.send("erm:signIn", Login.unitType, Login.members, Login.unitNumber)
    end)
end

function Login.drawPicker(sx, sy, sw, sh)
    Gfx.hit(0, 0, Gfx.screenW, Gfx.screenH, function() Login.picker = false end)
    Gfx.round(sx, sy, sw, sh, s(8), Theme.shade)

    local list = nearbyPlayers()
    local rowH = s(36)
    local w = s(340)
    local visible = math.min(math.max(#list, 1), 5)
    local h = s(64) + visible * rowH + s(58)
    local x, y = sx + (sw - w) / 2, sy + (sh - h) / 2

    Gfx.round(x, y, w, h, s(10), Theme.panel)
    Gfx.hit(x, y, w, h, function() end)       -- clicks inside don't close
    Gfx.text(L("med_erm.login.add_crew_member"), x + s(18), y + s(14), w - s(36), s(24), Theme.text, Gfx.font(13, true))
    Gfx.text(L("med_erm.login.on_duty_medics_near_you"), x + s(18), y + s(36), w - s(36), s(18), Theme.dim, Gfx.font(9))

    local ly = y + s(64)
    if #list == 0 then
        Gfx.text(L("med_erm.login.no_medics_nearby"), x + s(18), ly, w - s(36), rowH, Theme.faint, Gfx.font(10))
    end
    local offset = Gfx.getScroll("picker", #list - visible)
    Gfx.scrollArea("picker", x, ly, w, visible * rowH)
    for i = 1 + offset, math.min(#list, offset + visible) do
        local e = list[i]
        local ry = ly + (i - 1 - offset) * rowH
        local name = getPlayerName(e.player):gsub("#%x%x%x%x%x%x", "")
        Gfx.button(x + s(12), ry + s(2), w - s(24), rowH - s(4), Gfx.fit(name, w - s(110), Gfx.font(10)),
            { color = { 39, 46, 55 }, align = "left", font = Gfx.font(10) }, function()
                Login.members[#Login.members + 1] = e.player
                Login.picker = false
            end)
        Gfx.text(string.format("%.1f m", e.dist), x + s(12), ry, w - s(36), rowH, Theme.faint, Gfx.font(9), "right")
    end

    Gfx.button(x + w - s(112), y + h - s(48), s(96), s(34), L("common.cancel"), {}, function() Login.picker = false end)
end

-- Texts load only once the player is loaded (v_accounts loading gate).
local textsLoaded = false
local function loadTexts()
    if textsLoaded then return end
    textsLoaded = true
    build_TYPE_HINTS()
    exports.v_accounts:resourceReady()
end
addEvent("onClientLoadingStarted", true)
addEventHandler("onClientLoadingStarted", root, loadTexts)
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then loadTexts() end
end)
