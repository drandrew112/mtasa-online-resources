if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
RegisterPanel = {}

function RegisterPanel:create()
    local self = {}

    -- Layout
    local W = ui(360)
    local X = math.floor(sw / 2 - W / 2)
    local Y = math.floor(sh * 0.30)
    local pad = ui(22)
    local headerH = ui(46)

    local fieldW = W - pad * 2
    local fieldH = ui(38)
    local cx = X + pad

    local userLabelY = Y + headerH + ui(16)
    local userY      = userLabelY + ui(20)
    local passLabelY = userY + fieldH + ui(12)
    local passY      = passLabelY + ui(20)
    local confLabelY = passY + fieldH + ui(12)
    local confY      = confLabelY + ui(20)
    local mailLabelY = confY + fieldH + ui(12)
    local mailY      = mailLabelY + ui(20)
    local noteY      = mailY + fieldH + ui(6)
    local btnY       = noteY + ui(18) + ui(14)
    local btnH       = ui(40)
    local btnW       = math.floor((fieldW - ui(10)) / 2)
    local H          = (btnY + btnH + ui(8)) - Y + pad
    self.X, self.Y, self.W, self.H = X, Y, W, H -- anchor for the side cards

    self.user = DGS:dgsCreateEdit(cx, userY, fieldW, fieldH, "", false, false, tocolor(255,255,255), 1,1, _, Theme.fieldBG, false)
    self.pass = DGS:dgsCreateEdit(cx, passY, fieldW, fieldH, "", false, false, tocolor(255,255,255), 1,1, _, Theme.fieldBG, false)
    self.conf = DGS:dgsCreateEdit(cx, confY, fieldW, fieldH, "", false, false, tocolor(255,255,255), 1,1, _, Theme.fieldBG, false)
    self.mail = DGS:dgsCreateEdit(cx, mailY, fieldW, fieldH, "", false, false, tocolor(255,255,255), 1,1, _, Theme.fieldBG, false)
    DGS:dgsSetProperty(self.mail, "maxLength", 254)

    DGS:dgsSetProperty(self.pass, "masked", true)
    DGS:dgsSetProperty(self.conf, "masked", true)

    self.reg  = DGS:dgsCreateButton(cx, btnY, btnW, btnH, L("acc_ui.login.register"), false, _, tocolor(255,255,255,255), 1,1, _,_,_, Theme.btnPrimary[1], Theme.btnPrimary[2], Theme.btnPrimary[3])
    self.back = DGS:dgsCreateButton(cx + btnW + ui(10), btnY, btnW, btnH, L("acc_ui.login.login"), false, _, tocolor(255,255,255,255), 1,1, _,_,_, Theme.btnGhost[1], Theme.btnGhost[2], Theme.btnGhost[3])

    function self:draw()
        drawPanelFrame(X, Y, W, H, L("acc_ui.register.title"))
        drawFieldLabel(L("acc_ui.login.username"), cx, userLabelY, fieldW)
        drawFieldLabel(L("acc_ui.login.password"), cx, passLabelY, fieldW)
        drawFieldLabel(L("acc_ui.register.confirm_password"), cx, confLabelY, fieldW)
        drawFieldLabel(L("acc_ui.register.email_optional"), cx, mailLabelY, fieldW)
        dxDrawText(L("acc_ui.register.email_note"), cx, noteY, cx + fieldW, noteY + ui(18),
            Theme.label, ui(1.0), "default", "left", "center", true)
    end

    addEventHandler("onDgsMouseClick", self.reg, function(_, state)
        if state ~= "down" then return end

        local u = DGS:dgsGetText(self.user)
        local p = DGS:dgsGetText(self.pass)
        local c = DGS:dgsGetText(self.conf)
        local m = DGS:dgsGetText(self.mail)

        if u == "" then return uicore:setInfobox(L("acc_ui.login.username_missing")) end
        if p == "" then return uicore:setInfobox(L("acc_ui.login.password_missing")) end
        if p ~= c then return uicore:setInfobox(L("acc_ui.register.passwords_do_not_match")) end
        if #p < 5 then return uicore:setInfobox(L("acc_ui.register.password_too_short")) end

        uiSound("audio/ui_btn_click.mp3")
        exports.acc_auth:register(u, p, m)
    end)

    addEventHandler("onDgsMouseClick", self.back, function(_, state)
        if state == "down" then
            uiSound("audio/ui_btn_click.mp3")
            setPanel("login")
        end
    end)

    addEventHandler("onDgsMouseEnter", self.reg, function() uiSound("audio/ui_btn_hover.mp3") end)
    addEventHandler("onDgsMouseEnter", self.back, function() uiSound("audio/ui_btn_hover.mp3") end)

    function self:refreshTexts()
        DGS:dgsSetText(self.reg, L("acc_ui.login.register"))
        DGS:dgsSetText(self.back, L("acc_ui.login.login"))
    end

    function self:setVisible(state)
        for _, e in pairs(self) do
            if isElement(e) then
                DGS:dgsSetVisible(e, state)
            end
        end
    end

    return self
end
