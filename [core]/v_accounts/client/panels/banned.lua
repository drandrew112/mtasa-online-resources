BannedPanel = {}

function BannedPanel:create()
    local self = {}

    function self:draw()
        local W = ui(560)
        local H = ui(300)
        local X = math.floor(sw / 2 - W / 2)
        local Y = math.floor(sh / 2 - H / 2)
        local cx = X + ui(24)
        local right = X + W - ui(24)

        drawPanelFrame(X, Y, W, H, "ACCOUNT BANNED")

        local date   = getElementData(localPlayer, "banned_date")   or "n/a"
        local admin  = getElementData(localPlayer, "banned_admin")  or "n/a"
        local reason = getElementData(localPlayer, "banned_reason") or "n/a"

        local top = Y + ui(64)
        dxDrawText("Start date:  "..date.."\nAdmin:  "..admin.."\nExpires:  NEVER",
            cx, top, right, top + ui(84),
            Theme.text, ui(1.3), "default", "left", "top")

        -- Reason on its own line, with automatic word wrapping inside the card.
        local reasonTop = top + ui(96)
        dxDrawText("REASON", cx, reasonTop, right, reasonTop + ui(16),
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
