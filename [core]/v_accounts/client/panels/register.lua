RegisterPanel = {}

function RegisterPanel:create()
    local self = {}

    -- Layout
    local W = ui(360)
    local X = math.floor(sw / 2 - W / 2)
    local Y = math.floor(sh * 0.22)
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
    local btnY       = confY + fieldH + ui(20)
    local btnH       = ui(40)
    local btnW       = math.floor((fieldW - ui(10)) / 2)
    local H          = (btnY + btnH + ui(8)) - Y + pad

    self.user = DGS:dgsCreateEdit(cx, userY, fieldW, fieldH, "", false, false, tocolor(255,255,255), 1,1, _, Theme.fieldBG, false)
    self.pass = DGS:dgsCreateEdit(cx, passY, fieldW, fieldH, "", false, false, tocolor(255,255,255), 1,1, _, Theme.fieldBG, false)
    self.conf = DGS:dgsCreateEdit(cx, confY, fieldW, fieldH, "", false, false, tocolor(255,255,255), 1,1, _, Theme.fieldBG, false)

    DGS:dgsSetProperty(self.pass, "masked", true)
    DGS:dgsSetProperty(self.conf, "masked", true)

    self.reg  = DGS:dgsCreateButton(cx, btnY, btnW, btnH, "Register", false, _, tocolor(255,255,255,255), 1,1, _,_,_, Theme.btnPrimary[1], Theme.btnPrimary[2], Theme.btnPrimary[3])
    self.back = DGS:dgsCreateButton(cx + btnW + ui(10), btnY, btnW, btnH, "Login", false, _, tocolor(255,255,255,255), 1,1, _,_,_, Theme.btnGhost[1], Theme.btnGhost[2], Theme.btnGhost[3])

    function self:draw()
        drawPanelFrame(X, Y, W, H, "REGISTER")
        drawFieldLabel("USERNAME", cx, userLabelY, fieldW)
        drawFieldLabel("PASSWORD", cx, passLabelY, fieldW)
        drawFieldLabel("CONFIRM PASSWORD", cx, confLabelY, fieldW)
    end

    addEventHandler("onDgsMouseClick", self.reg, function(_, state)
        if state ~= "down" then return end

        local u = DGS:dgsGetText(self.user)
        local p = DGS:dgsGetText(self.pass)
        local c = DGS:dgsGetText(self.conf)

        if u == "" then return uicore:setInfobox("Username missing") end
        if p == "" then return uicore:setInfobox("Password missing") end
        if p ~= c then return uicore:setInfobox("Passwords do not match") end
        if #p < 5 then return uicore:setInfobox("Password too short") end

        uiSound("audio/ui_btn_click.mp3")
        triggerServerEvent("register_player", localPlayer, u, p)
    end)

    addEventHandler("onDgsMouseClick", self.back, function(_, state)
        if state == "down" then
            uiSound("audio/ui_btn_click.mp3")
            setPanel("login")
        end
    end)

    addEventHandler("onDgsMouseEnter", self.reg, function() uiSound("audio/ui_btn_hover.mp3") end)
    addEventHandler("onDgsMouseEnter", self.back, function() uiSound("audio/ui_btn_hover.mp3") end)

    function self:setVisible(state)
        for _, e in pairs(self) do
            if isElement(e) then
                DGS:dgsSetVisible(e, state)
            end
        end
    end

    return self
end
