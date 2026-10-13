if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
LoginPanel = {}

function LoginPanel:create()
    local self = {}

    -- Layout
    local W = ui(360)
    local X = math.floor(sw / 2 - W / 2)
    local Y = math.floor(sh * 0.24)
    local pad = ui(22)
    local headerH = ui(46)

    local fieldW = W - pad * 2
    local fieldH = ui(38)
    local cx = X + pad

    local userLabelY = Y + headerH + ui(16)
    local userY      = userLabelY + ui(20)
    local passLabelY = userY + fieldH + ui(12)
    local passY      = passLabelY + ui(20)
    local btnY       = passY + fieldH + ui(20)
    local btnH       = ui(40)
    local btnW       = math.floor((fieldW - ui(10)) / 2)
    local remY       = btnY + btnH + ui(16)
    local H          = (remY + ui(18)) - Y + pad

    self.user = DGS:dgsCreateEdit(cx, userY, fieldW, fieldH, "", false, false, tocolor(255,255,255), 1,1, _, Theme.fieldBG, false)
    self.pass = DGS:dgsCreateEdit(cx, passY, fieldW, fieldH, "", false, false, tocolor(255,255,255), 1,1, _, Theme.fieldBG, false)
    DGS:dgsSetProperty(self.pass, "masked", true)

    self.login = DGS:dgsCreateButton(cx, btnY, btnW, btnH, L("v_accounts.login.login"), false, _, tocolor(255,255,255,255), 1,1, _,_,_, Theme.btnPrimary[1], Theme.btnPrimary[2], Theme.btnPrimary[3])
    self.reg   = DGS:dgsCreateButton(cx + btnW + ui(10), btnY, btnW, btnH, L("v_accounts.login.register"), false, _, tocolor(255,255,255,255), 1,1, _,_,_, Theme.btnGhost[1], Theme.btnGhost[2], Theme.btnGhost[3])
    self.remember = DGS:dgsCreateCheckBox(cx, remY, fieldW, ui(18), L("v_accounts.login.remember_me"), false, _, Theme.text)

    function self:draw()
        drawPanelFrame(X, Y, W, H, L("v_accounts.login.title"))
        drawFieldLabel(L("v_accounts.login.username"), cx, userLabelY, fieldW)
        drawFieldLabel(L("v_accounts.login.password"), cx, passLabelY, fieldW)
    end

    addEventHandler("onDgsMouseClick", self.login, function(_, state)
        if state ~= "down" then return end

        local u = DGS:dgsGetText(self.user)
        local p = DGS:dgsGetText(self.pass)

        if u == "" then return uicore:setInfobox(L("v_accounts.login.username_missing")) end
        if p == "" then return uicore:setInfobox(L("v_accounts.login.password_missing")) end

        local remember = DGS:dgsCheckBoxGetSelected(self.remember)
        UserData.set("username", remember and u or "")
        UserData.set("password", remember and p or "")

        uiSound("audio/ui_btn_click.mp3")
        triggerServerEvent("login_player", localPlayer, u, p)
    end)

    addEventHandler("onDgsMouseClick", self.reg, function(_, state)
        if state == "down" then
            uiSound("audio/ui_btn_click.mp3")
            setPanel("register")
        end
    end)

    addEventHandler("onDgsMouseEnter", self.login, function() uiSound("audio/ui_btn_hover.mp3") end)
    addEventHandler("onDgsMouseEnter", self.reg, function() uiSound("audio/ui_btn_hover.mp3") end)

    function self:refreshTexts()
        DGS:dgsSetText(self.login, L("v_accounts.login.login"))
        DGS:dgsSetText(self.reg, L("v_accounts.login.register"))
        DGS:dgsSetText(self.remember, L("v_accounts.login.remember_me"))
    end

    function self:setVisible(state)
        for _, e in pairs(self) do
            if isElement(e) then
                DGS:dgsSetVisible(e, state)
            end
        end
    end

    -- init: prefill saved credentials
    local savedUser = UserData.get("username")
    DGS:dgsSetText(self.user, savedUser)
    DGS:dgsSetText(self.pass, UserData.get("password"))
    DGS:dgsCheckBoxSetSelected(self.remember, savedUser ~= "")

    return self
end
