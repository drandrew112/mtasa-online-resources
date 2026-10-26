if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
LoginPanel = {}

local savedTokenName = getSavedAccountName -- auth/client/token.lua

function LoginPanel:create()
    local self = {}

    -- Layout
    local W = ui(360)
    local X = math.floor(sw / 2 - W / 2)
    local Y = math.floor(sh * 0.18)
    local pad = ui(22)
    local headerH = ui(46)

    local fieldW = W - pad * 2
    local fieldH = ui(38)
    local cx = X + pad

    -- form mode (username + password)
    local userLabelY = Y + headerH + ui(16)
    local userY      = userLabelY + ui(20)
    local passLabelY = userY + fieldH + ui(12)
    local passY      = passLabelY + ui(20)
    local btnY       = passY + fieldH + ui(20)
    local btnH       = ui(40)
    local btnW       = math.floor((fieldW - ui(10)) / 2)
    local remY       = btnY + btnH + ui(16)
    local formH      = (remY + ui(18)) - Y + pad

    -- quick mode (Continue as ... / another account)
    local contY  = Y + headerH + ui(22)
    local otherY = contY + btnH + ui(10)
    local quickH = (otherY + btnH) - Y + pad

    self.X, self.Y, self.W = X, Y, W -- anchor for the weekly card
    self.mode = savedTokenName() and "quick" or "form"
    self.visible = false

    self.form = {
        user = DGS:dgsCreateEdit(cx, userY, fieldW, fieldH, "", false, false, tocolor(255,255,255), 1,1, _, Theme.fieldBG, false),
        pass = DGS:dgsCreateEdit(cx, passY, fieldW, fieldH, "", false, false, tocolor(255,255,255), 1,1, _, Theme.fieldBG, false),
        login = DGS:dgsCreateButton(cx, btnY, btnW, btnH, L("v_accounts.ui.login.login"), false, _, tocolor(255,255,255,255), 1,1, _,_,_, Theme.btnPrimary[1], Theme.btnPrimary[2], Theme.btnPrimary[3]),
        reg   = DGS:dgsCreateButton(cx + btnW + ui(10), btnY, btnW, btnH, L("v_accounts.ui.login.register"), false, _, tocolor(255,255,255,255), 1,1, _,_,_, Theme.btnGhost[1], Theme.btnGhost[2], Theme.btnGhost[3]),
        remember = DGS:dgsCreateCheckBox(cx, remY, math.floor(fieldW / 2), ui(18), L("v_accounts.ui.login.remember_me"), false, _, Theme.text),
        -- link-styled button; only in form mode (never on the "Continue as" panel)
        forgot = DGS:dgsCreateButton(cx + math.floor(fieldW / 2), remY - ui(4), fieldW - math.floor(fieldW / 2), ui(26), L("v_accounts.ui.login.forgot_password"), false, _, Theme.accent, 1,1, _,_,_, tocolor(0,0,0,0), tocolor(255,255,255,14), tocolor(255,255,255,24)),
    }
    DGS:dgsSetProperty(self.form.pass, "masked", true)

    self.quick = {
        cont  = DGS:dgsCreateButton(cx, contY, fieldW, btnH, "", false, _, tocolor(255,255,255,255), 1,1, _,_,_, Theme.btnPrimary[1], Theme.btnPrimary[2], Theme.btnPrimary[3]),
        other = DGS:dgsCreateButton(cx, otherY, fieldW, btnH, L("v_accounts.ui.login.other_account"), false, _, tocolor(255,255,255,255), 1,1, _,_,_, Theme.btnGhost[1], Theme.btnGhost[2], Theme.btnGhost[3]),
    }

    DGS:dgsSetProperty(self.form.forgot, "alignment", { "right", "center" })

    function self:draw()
        self.H = self.mode == "quick" and quickH or formH -- anchor for the settings card
        if self.mode == "quick" then
            drawPanelFrame(X, Y, W, quickH, L("v_accounts.ui.login.title"))
        else
            drawPanelFrame(X, Y, W, formH, L("v_accounts.ui.login.title"))
            drawFieldLabel(L("v_accounts.ui.login.username"), cx, userLabelY, fieldW)
            drawFieldLabel(L("v_accounts.ui.login.password"), cx, passLabelY, fieldW)
        end
    end

    addEventHandler("onDgsMouseClick", self.form.login, function(_, state)
        if state ~= "down" then return end

        local u = DGS:dgsGetText(self.form.user)
        local p = DGS:dgsGetText(self.form.pass)

        if u == "" then return uicore:setInfobox(L("v_accounts.ui.login.username_missing")) end
        if p == "" then return uicore:setInfobox(L("v_accounts.ui.login.password_missing")) end

        -- the server answers a remembered login with a token (v_accounts:rememberToken)
        local remember = DGS:dgsCheckBoxGetSelected(self.form.remember) == true

        uiSound("ui/audio/ui_btn_click.mp3")
        login(u, p, remember)
    end)

    addEventHandler("onDgsMouseClick", self.form.reg, function(_, state)
        if state == "down" then
            uiSound("ui/audio/ui_btn_click.mp3")
            setPanel("register")
        end
    end)

    addEventHandler("onDgsMouseClick", self.form.forgot, function(_, state)
        if state ~= "down" then return end
        uiSound("ui/audio/ui_btn_click.mp3")
        setPanel("forgot")
    end)

    addEventHandler("onDgsMouseClick", self.quick.cont, function(_, state)
        if state ~= "down" then return end
        if not savedTokenName() then return self:setMode("form") end
        uiSound("ui/audio/ui_btn_click.mp3")
        loginWithToken()
    end)

    addEventHandler("onDgsMouseClick", self.quick.other, function(_, state)
        if state == "down" then
            uiSound("ui/audio/ui_btn_click.mp3")
            self:setMode("form")
        end
    end)

    for _, btn in ipairs({ self.form.login, self.form.reg, self.form.forgot, self.quick.cont, self.quick.other }) do
        addEventHandler("onDgsMouseEnter", btn, function() uiSound("ui/audio/ui_btn_hover.mp3") end)
    end

    function self:refreshTexts()
        DGS:dgsSetText(self.form.login, L("v_accounts.ui.login.login"))
        DGS:dgsSetText(self.form.reg, L("v_accounts.ui.login.register"))
        DGS:dgsSetText(self.form.remember, L("v_accounts.ui.login.remember_me"))
        DGS:dgsSetText(self.form.forgot, L("v_accounts.ui.login.forgot_password"))
        DGS:dgsSetText(self.quick.cont, L("v_accounts.ui.login.continue_as", { name = savedTokenName() or "" }))
        DGS:dgsSetText(self.quick.other, L("v_accounts.ui.login.other_account"))
    end

    local function showGroup(group, state)
        for _, e in pairs(group) do
            if isElement(e) then DGS:dgsSetVisible(e, state) end
        end
    end

    function self:setVisible(state)
        self.visible = state
        showGroup(self.form, state and self.mode == "form")
        showGroup(self.quick, state and self.mode == "quick")
    end

    -- "quick" needs a saved token; falls back to the form without one
    function self:setMode(mode)
        if mode == "quick" and not savedTokenName() then mode = "form" end
        self.mode = mode
        if mode == "quick" then self:refreshTexts() end
        self:setVisible(self.visible)
    end

    -- init
    self:refreshTexts()
    DGS:dgsCheckBoxSetSelected(self.form.remember, true) -- opt-out: untick to forget the saved login
    self:setVisible(false)

    return self
end

-- the password reset finished: back to the form with the name filled in
function LoginPanel.prefill(panel, name)
    panel:setMode("form")
    DGS:dgsSetText(panel.form.user, tostring(name or ""))
    DGS:dgsSetText(panel.form.pass, "")
end
