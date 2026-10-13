if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / client/panel/commands.lua
--  Commands tab: the v_admin command reference (ADMIN.commands in
--  config.lua) with the level each command needs.
-- ============================================================

local S, F, C = AP.S, AP.F, AP.C

local scroll = 0

AP.addTab({
    id = "commands", label = function() return L("v_admin.commands.commands") end, perm = "panel", order = 4,
    draw = function(x, y, w, h)
        local cmdW, lvlW = w * 0.3, S(250)
        local descX = x + cmdW + lvlW + S(20)
        AP.text(L("v_admin.commands.command"), x + S(14), y, cmdW, S(32), C.dim, 0.9, "default-bold")
        AP.text(L("v_admin.commands.level"), x + cmdW + S(10), y, lvlW, S(32), C.dim, 0.9, "default-bold")
        AP.text(L("v_admin.commands.description"), descX, y, w, S(32), C.dim, 0.9, "default-bold")
        y = y + S(38)
        h = h - S(38)

        local rowH = S(46)
        local list = ADMIN.commands
        local visible = math.max(1, math.floor((h - S(30)) / rowH))
        scroll = math.max(0, math.min(scroll, #list - visible))
        AP.scrollArea(x, y, w, h, function(dir) scroll = scroll + dir end)

        for i = 1, visible do
            local c = list[scroll + i]
            if not c then break end
            local ry = y + (i - 1) * rowH
            local rh = rowH - S(4)
            local need = c.perm and AP.permLevel(c.perm) or 0
            local allowed = AP.myLevel >= need
            dxDrawRectangle(x, ry, w, rh, C.row)
            AP.text(c.cmd, x + S(14), ry, cmdW - S(14), rh, allowed and C.text or C.off, 1.0, "default-bold")
            AP.text(need == 0 and "everyone" or (need .. "+  " .. AP.rankName(need)),
                x + cmdW + S(10), ry, lvlW, rh, allowed and C.head or C.off, 0.95, "default-bold")
            AP.text(c.desc, descX, ry, x + w - descX - S(10), rh, allowed and C.dim or C.off, 0.9)
        end

        if #list > visible then
            AP.text(L("v_admin.commands.of_mouse_wheel", { scroll = scroll + 1, visible = math.min(#list, scroll + visible), list = #list }),
                x, y + visible * rowH, w, S(28), C.dim, 0.85, "default", "right")
        end
    end,
})
