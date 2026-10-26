if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
BannedPanel = {}

function BannedPanel:create()
    local self = {}

    function self:draw()
        local W = ui(560)
        local H = ui(300)
        local X = math.floor(sw / 2 - W / 2)
        local Y = math.floor(sh / 2 - H / 2)
        self.X, self.Y, self.W, self.H = X, Y, W, H -- anchor for the settings card
        local cx = X + ui(24)
        local right = X + W - ui(24)

        drawPanelFrame(X, Y, W, H, L("v_accounts.ui.banned.account_banned"))

        local date   = getElementData(localPlayer, "banned_date")   or "n/a"
        local admin  = getElementData(localPlayer, "banned_admin")  or "n/a"
        local reason = getElementData(localPlayer, "banned_reason") or L("v_accounts.ui.banned.n")

        local top = Y + ui(64)
        dxDrawText(L("v_accounts.ui.banned.start_date_admin_expires_never", { date = date, admin = admin }),
            cx, top, right, top + ui(84),
            Theme.text, ui(1.3), "default", "left", "top")

        -- Reason on its own line, with automatic word wrapping inside the card.
        local reasonTop = top + ui(96)
        dxDrawText(L("v_accounts.ui.banned.reason"), cx, reasonTop, right, reasonTop + ui(16),
            Theme.label, ui(1.2), "default-bold", "left", "top")
        dxDrawText(reason,
            cx, reasonTop + ui(22), right, Y + H - ui(18),
            Theme.danger, ui(1.35), "default", "left", "top", true, true)
    end

    -- No interactive elements.
    function self:setVisible(state)
    end

    return self
end
