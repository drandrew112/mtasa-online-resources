if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
LoginPanel = {}

-- Account name of the saved remember-me token ("<name>=<hash>"), or nil.
local function savedTokenName()
    return UserData.get("token"):match("^([^=]+)=%x+$")
end

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
        login = DGS:dgsCreateButton(cx, btnY, btnW, btnH, L("v_accounts.login.login"), false, _, tocolor(255,255,255,255), 1,1, _,_,_, Theme.btnPrimary[1], Theme.btnPrimary[2], Theme.btnPrimary[3]),
        reg   = DGS:dgsCreateButton(cx + btnW + ui(10), btnY, btnW, btnH, L("v_accounts.login.register"), false, _, tocolor(255,255,255,255), 1,1, _,_,_, Theme.btnGhost[1], Theme.btnGhost[2], Theme.btnGhost[3]),
        remember = DGS:dgsCreateCheckBox(cx, remY, fieldW, ui(18), L("v_accounts.login.remember_me"), false, _, Theme.text),
    }
    DGS:dgsSetProperty(self.form.pass, "masked", true)

    self.quick = {
        cont  = DGS:dgsCreateButton(cx, contY, fieldW, btnH, "", false, _, tocolor(255,255,255,255), 1,1, _,_,_, Theme.btnPrimary[1], Theme.btnPrimary[2], Theme.btnPrimary[3]),
        other = DGS:dgsCreateButton(cx, otherY, fieldW, btnH, L("v_accounts.login.other_account"), false, _, tocolor(255,255,255,255), 1,1, _,_,_, Theme.btnGhost[1], Theme.btnGhost[2], Theme.btnGhost[3]),
    }

    function self:draw()
        if self.mode == "quick" then
            drawPanelFrame(X, Y, W, quickH, L("v_accounts.login.title"))
        else
            drawPanelFrame(X, Y, W, formH, L("v_accounts.login.title"))
            drawFieldLabel(L("v_accounts.login.username"), cx, userLabelY, fieldW)
            drawFieldLabel(L("v_accounts.login.password"), cx, passLabelY, fieldW)
        end
    end

    addEventHandler("onDgsMouseClick", self.form.login, function(_, state)
        if state ~= "down" then return end

        local u = DGS:dgsGetText(self.form.user)
        local p = DGS:dgsGetText(self.form.pass)

        if u == "" then return uicore:setInfobox(L("v_accounts.login.username_missing")) end
        if p == "" then return uicore:setInfobox(L("v_accounts.login.password_missing")) end

        -- the server answers a remembered login with a token (acc:rememberToken)
        local remember = DGS:dgsCheckBoxGetSelected(self.form.remember) == true
        if not remember then UserData.set("token", "") end

        uiSound("audio/ui_btn_click.mp3")
        triggerServerEvent("login_player", localPlayer, u, p, remember)
    end)

    addEventHandler("onDgsMouseClick", self.form.reg, function(_, state)
        if state == "down" then
            uiSound("audio/ui_btn_click.mp3")
            setPanel("register")
        end
    end)

    addEventHandler("onDgsMouseClick", self.quick.cont, function(_, state)
        if state ~= "down" then return end
        local token = UserData.get("token")
        if token == "" then return self:setMode("form") end
        uiSound("audio/ui_btn_click.mp3")
        triggerServerEvent("login_token", localPlayer, token)
    end)

    addEventHandler("onDgsMouseClick", self.quick.other, function(_, state)
        if state == "down" then
            uiSound("audio/ui_btn_click.mp3")
            self:setMode("form")
        end
    end)

    for _, btn in ipairs({ self.form.login, self.form.reg, self.quick.cont, self.quick.other }) do
        addEventHandler("onDgsMouseEnter", btn, function() uiSound("audio/ui_btn_hover.mp3") end)
    end

    function self:refreshTexts()
        DGS:dgsSetText(self.form.login, L("v_accounts.login.login"))
        DGS:dgsSetText(self.form.reg, L("v_accounts.login.register"))
        DGS:dgsSetText(self.form.remember, L("v_accounts.login.remember_me"))
        DGS:dgsSetText(self.quick.cont, L("v_accounts.login.continue_as", { name = savedTokenName() or "" }))
        DGS:dgsSetText(self.quick.other, L("v_accounts.login.other_account"))
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

-- The server verified a remembered password login: keep only the token.
addEvent("acc:rememberToken", true)
addEventHandler("acc:rememberToken", root, function(token)
    if type(token) == "string" then UserData.set("token", token) end
end)

-- The saved token was refused (password changed, other machine, ...): forget it.
addEvent("acc:tokenInvalid", true)
addEventHandler("acc:tokenInvalid", root, function()
    UserData.set("token", "")
    if Panels.login then Panels.login:setMode("form") end
end)
