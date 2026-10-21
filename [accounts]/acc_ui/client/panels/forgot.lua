if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Forgotten password, two steps on one panel (only reachable from the normal
-- login form, never from the "Continue as" panel):
--   "email"  email -> Send code      (acc_auth:requestPasswordReset)
--   "code"   code + new password ×2  (acc_auth:confirmPasswordReset), Resend after a wait
-- "Back to login" always returns to the normal login form.

ForgotPanel = {}

local RESEND_WAIT = 60 -- s; the server enforces its own limit too

function ForgotPanel:create()
    local self = {}

    local W = ui(360)
    local X = math.floor(sw / 2 - W / 2)
    local Y = math.floor(sh * 0.30)
    local pad = ui(22)
    local headerH = ui(46)
    local fieldW = W - pad * 2
    local fieldH = ui(38)
    local btnH = ui(40)
    local cx = X + pad

    -- step "email"
    local infoY      = Y + headerH + ui(14)
    local mailLabelY = infoY + ui(44)
    local mailY      = mailLabelY + ui(20)
    local sendY      = mailY + fieldH + ui(18)
    local back1Y     = sendY + btnH + ui(10)
    local emailH     = (back1Y + btnH) - Y + pad

    -- step "code"
    local codeLabelY = infoY + ui(44)
    local codeY      = codeLabelY + ui(20)
    local passLabelY = codeY + fieldH + ui(12)
    local passY      = passLabelY + ui(20)
    local confLabelY = passY + fieldH + ui(12)
    local confY      = confLabelY + ui(20)
    local setY       = confY + fieldH + ui(18)
    local rowY       = setY + btnH + ui(10)
    local halfW      = math.floor((fieldW - ui(10)) / 2)
    local codeH      = (rowY + btnH) - Y + pad

    self.X, self.Y, self.W = X, Y, W
    self.step = "email"
    self.visible = false
    self.maskedEmail = ""
    self.sentAt = 0

    local function edit(y)
        return DGS:dgsCreateEdit(cx, y, fieldW, fieldH, "", false, false, tocolor(255,255,255), 1,1, _, Theme.fieldBG, false)
    end
    local function primary(x, y, w, text)
        return DGS:dgsCreateButton(x, y, w, btnH, text, false, _, tocolor(255,255,255,255), 1,1, _,_,_, Theme.btnPrimary[1], Theme.btnPrimary[2], Theme.btnPrimary[3])
    end
    local function ghost(x, y, w, text)
        return DGS:dgsCreateButton(x, y, w, btnH, text, false, _, tocolor(255,255,255,255), 1,1, _,_,_, Theme.btnGhost[1], Theme.btnGhost[2], Theme.btnGhost[3])
    end

    self.email = {
        mail = edit(mailY),
        send = primary(cx, sendY, fieldW, L("acc_ui.forgot.send_code")),
        back = ghost(cx, back1Y, fieldW, L("acc_ui.forgot.back_to_login")),
    }
    DGS:dgsSetProperty(self.email.mail, "maxLength", 254)

    self.code = {
        code   = edit(codeY),
        pass   = edit(passY),
        conf   = edit(confY),
        set    = primary(cx, setY, fieldW, L("acc_ui.forgot.set_password")),
        resend = ghost(cx, rowY, halfW, L("acc_ui.forgot.resend")),
        back   = ghost(cx + halfW + ui(10), rowY, halfW, L("acc_ui.forgot.back_to_login")),
    }
    DGS:dgsSetProperty(self.code.code, "maxLength", 6)
    DGS:dgsSetProperty(self.code.pass, "masked", true)
    DGS:dgsSetProperty(self.code.conf, "masked", true)

    local function showGroup(group, state)
        for _, e in pairs(group) do
            if isElement(e) then DGS:dgsSetVisible(e, state) end
        end
    end

    function self:setVisible(state)
        self.visible = state
        showGroup(self.email, state and self.step == "email")
        showGroup(self.code, state and self.step == "code")
    end

    function self:setStep(step)
        self.step = step
        if step == "email" then
            DGS:dgsSetText(self.code.code, "")
            DGS:dgsSetText(self.code.pass, "")
            DGS:dgsSetText(self.code.conf, "")
        end
        self:setVisible(self.visible)
    end

    local function resendLeft()
        return math.max(0, RESEND_WAIT - math.floor((getTickCount() - self.sentAt) / 1000))
    end

    function self:draw()
        if self.step == "email" then
            self.H = emailH
            drawPanelFrame(X, Y, W, emailH, L("acc_ui.forgot.title"))
            dxDrawText(L("acc_ui.forgot.email_info"), cx, infoY, cx + fieldW, infoY + ui(40),
                Theme.label, ui(1.05), "default", "left", "top", true, true)
            drawFieldLabel(L("acc_ui.forgot.email"), cx, mailLabelY, fieldW)
        else
            self.H = codeH
            drawPanelFrame(X, Y, W, codeH, L("acc_ui.forgot.title"))
            dxDrawText(L("acc_ui.forgot.code_info", { email = self.maskedEmail }), cx, infoY, cx + fieldW, infoY + ui(40),
                Theme.label, ui(1.05), "default", "left", "top", true, true)
            drawFieldLabel(L("acc_ui.forgot.code"), cx, codeLabelY, fieldW)
            drawFieldLabel(L("acc_ui.forgot.new_password"), cx, passLabelY, fieldW)
            drawFieldLabel(L("acc_ui.forgot.confirm_new_password"), cx, confLabelY, fieldW)
            local left = resendLeft()
            local text = left > 0 and L("acc_ui.forgot.resend_in", { seconds = left }) or L("acc_ui.forgot.resend")
            if DGS:dgsGetText(self.code.resend) ~= text then DGS:dgsSetText(self.code.resend, text) end
        end
    end

    local function onClick(el, fn)
        addEventHandler("onDgsMouseClick", el, function(_, state)
            if state ~= "down" then return end
            uiSound("audio/ui_btn_click.mp3")
            fn()
        end, false)
        addEventHandler("onDgsMouseEnter", el, function() uiSound("audio/ui_btn_hover.mp3") end, false)
    end

    local function back()
        self:setStep("email")
        setPanel("login")
        if Panels.login then Panels.login:setMode("form") end
    end

    onClick(self.email.send, function()
        local mail = DGS:dgsGetText(self.email.mail)
        if mail == "" then return uicore:setInfobox(L("acc_ui.forgot.email_missing")) end
        exports.acc_auth:requestPasswordReset(mail)
    end)
    onClick(self.email.back, back)
    onClick(self.code.back, back)

    onClick(self.code.resend, function()
        if resendLeft() > 0 then return end
        exports.acc_auth:requestPasswordReset(DGS:dgsGetText(self.email.mail))
    end)

    onClick(self.code.set, function()
        local code = DGS:dgsGetText(self.code.code):upper():gsub("%s", "")
        local p = DGS:dgsGetText(self.code.pass)
        local c = DGS:dgsGetText(self.code.conf)
        if #code ~= 6 then return uicore:setInfobox(L("acc_ui.forgot.code_missing")) end
        if p == "" then return uicore:setInfobox(L("acc_ui.login.password_missing")) end
        if p ~= c then return uicore:setInfobox(L("acc_ui.register.passwords_do_not_match")) end
        if #p < 5 then return uicore:setInfobox(L("acc_ui.register.password_too_short")) end
        exports.acc_auth:confirmPasswordReset(code, p)
    end)

    -- the code is shown upper-case while typing
    addEventHandler("onDgsTextChange", self.code.code, function()
        local t = DGS:dgsGetText(self.code.code)
        if t ~= t:upper() then DGS:dgsSetText(self.code.code, t:upper()) end
    end, false)

    function self:refreshTexts()
        DGS:dgsSetText(self.email.send, L("acc_ui.forgot.send_code"))
        DGS:dgsSetText(self.email.back, L("acc_ui.forgot.back_to_login"))
        DGS:dgsSetText(self.code.set, L("acc_ui.forgot.set_password"))
        DGS:dgsSetText(self.code.back, L("acc_ui.forgot.back_to_login"))
    end

    -- acc_auth answers
    addEvent("acc_auth:onClientResetState", true)
    addEventHandler("acc_auth:onClientResetState", localPlayer, function(step, info)
        if step == "code" then
            self.maskedEmail = type(info) == "table" and tostring(info.email or "") or ""
            self.sentAt = getTickCount()
            self:setStep("code")
            uicore:setInfobox(L("acc_ui.forgot.code_sent"), 255, 255, 255)
        elseif step == "failed" then
            if info then uicore:setInfobox(info, 255, 255, 255) end
        elseif step == "done" then
            self:setStep("email")
            setPanel("login")
            if Panels.login then LoginPanel.prefill(Panels.login, info) end
            uicore:setInfobox(L("acc_ui.forgot.password_changed"), 255, 255, 255)
        end
    end)

    self:setVisible(false)
    return self
end
