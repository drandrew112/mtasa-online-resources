-- police_system / modules/mdc/client/pages/signin.lua
-- The (smaller) unit sign-in window: type Adam (A-, 2-4 officers) / Lincoln (L-, alone), number (free / taken across
-- every server), officers (leader + invited with their answer), nearby officers to invite, Sign in.

local MDC = POL.mdc
local C = POL.colors

local function set(kind, number)
    MDC.call("signinSet", { type = kind, number = number }, function(d) if d then MDC.data.signin = d end end)
end

MDC.pages.signin = {
    load = function()
        MDC.call("signin", {}, function(d) if d then MDC.data.signin = d; W.fieldOf("si:num", { max = 3 }):setText(tostring(d.number)) end end)
    end,
    draw = function(x, y, w, h)
        local f = MDC.data.signin
        dxDrawRectangle(0, 0, w, POL.px(54), C.panel)
        dxDrawRectangle(0, POL.px(54), w, POL.px(2), C.accent)
        W.text(L("police_system.mdc.unit_signin"), POL.px(18), 0, w, POL.px(54), C.white, 14, true)
        W.button("close", w - POL.px(54), POL.px(11), POL.px(36), POL.px(32), "✕", function() MDC.close() end, "ghost")
        if not f then W.text(L("police_system.mdc.loading"), POL.px(18), POL.px(70), w, POL.px(30), C.dim, 11) return end
        local px = POL.px(24)
        local cy = POL.px(72)
        W.text(L("police_system.mdc.unit_type"), px, cy, POL.px(160), POL.px(30), C.dim, 10, true)
        W.button("si:adam", px + POL.px(160), cy, POL.px(200), POL.px(30), L("police_system.mdc.adam"), function() set("adam", f.number) end,
            f.type == "adam" and "active" or nil)
        W.button("si:lincoln", px + POL.px(364), cy, POL.px(200), POL.px(30), L("police_system.mdc.lincoln"), function() set("lincoln", f.number) end,
            f.type == "lincoln" and "active" or nil)
        cy = cy + POL.px(44)
        W.text(L("police_system.mdc.number"), px, cy, POL.px(160), POL.px(30), C.dim, 10, true)
        W.field("si:num", px + POL.px(160), cy, POL.px(80), POL.px(30), "1-" .. POLICE.UNITS.NUMBER_MAX, { max = 3, filter = function(ch) return ch:match("%d") ~= nil end })
        W.button("si:check", px + POL.px(250), cy, POL.px(110), POL.px(30), L("police_system.mdc.check"), function()
            set(f.type, tonumber(W.fields["si:num"]:getText()) or f.number)
        end)
        local tag = (f.type == "adam" and "A-" or "L-") .. f.number
        W.text(tag .. "  " .. (f.free and L("police_system.mdc.free") or L("police_system.mdc.taken")), px + POL.px(374), cy, POL.px(200), POL.px(30),
            f.free and C.green or C.red, 11, true)
        cy = cy + POL.px(48)
        W.text(L("police_system.mdc.col_officers"), px, cy, POL.px(160), POL.px(24), C.dim, 10, true)
        W.text(f.leader .. "  (" .. L("police_system.mdc.leader") .. ")", px + POL.px(160), cy, w, POL.px(24), C.white, 10, true)
        cy = cy + POL.px(26)
        for _, i in ipairs(f.invited or {}) do
            W.text(i.name .. "  · " .. L("police_system.mdc.invite_" .. i.state), px + POL.px(160), cy, w, POL.px(24),
                i.state == "accepted" and C.green or (i.state == "declined" and C.red or C.yellow), 10)
            cy = cy + POL.px(26)
        end
        if f.type == "adam" then
            cy = cy + POL.px(8)
            W.text(L("police_system.mdc.nearby_officers"), px, cy, POL.px(160), POL.px(24), C.dim, 10, true)
            if #(f.candidates or {}) == 0 then W.text(L("police_system.mdc.no_candidates"), px + POL.px(160), cy, w, POL.px(24), C.dim, 9) end
            for idx, cnd in ipairs(f.candidates or {}) do
                W.text(cnd.name, px + POL.px(160), cy, POL.px(220), POL.px(26), C.text, 10)
                W.button("si:inv" .. idx, px + POL.px(390), cy, POL.px(120), POL.px(24), L("police_system.mdc.invite"), function()
                    MDC.call("invite", { target = cnd.el }, function() MDC.load() end)
                end)
                cy = cy + POL.px(28)
            end
        end
        local accepted = 0
        for _, i in ipairs(f.invited or {}) do if i.state == "accepted" then accepted = accepted + 1 end end
        local ok = f.free and f.inVehicle and (f.type == "lincoln" or (accepted + 1 >= POLICE.UNITS.ADAM_MIN and accepted + 1 <= POLICE.UNITS.ADAM_MAX))
        local hint = not f.inVehicle and L("police_system.mdc.need_vehicle")
            or (f.type == "adam" and accepted < 1) and L("police_system.mdc.adam_needs_partner") or ""
        W.text(hint, px, h - POL.px(56), w - POL.px(240), POL.px(40), C.orange, 9)
        W.button("si:go", w - POL.px(200), h - POL.px(56), POL.px(176), POL.px(38), L("police_system.mdc.sign_in"), function()
            MDC.call("signinGo", {}, function(res) if res then MDC.go("overview") end end)
        end, "primary", not ok)
    end,
}

-- an invite answered / the form changed on the server
POL.on("unit", function(u) if u and MDC.open then MDC.go("overview") end end)
