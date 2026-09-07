-- ui_browser :: core/styles.lua
-- The browser theme: colours, fonts and the named "class"-es the markup can
-- reference. This is a simplified browser, so there is no full CSS: pages only
-- reference these named classes (class="btn-buy" etc.).

local uicore = exports.ui_core

-- Shared scale factor (ui_core scale). BR.sc(px) -> screen-dependent pixel.
BR.S = (uicore:ui(1000) or 1000) / 1000
function BR.sc(v) return v * BR.S end

-- Font size multiplier: 1.0 is "normal" body text.
function BR.fscale(mult) return BR.S * 1.15 * (mult or 1) end

BR.fonts = {
    regular = "default",
    bold    = "default-bold",
    heading = "default-bold",
    clear   = "clear",
}

BR.theme = {
    dim         = tocolor(0, 0, 0, 170),
    window      = tocolor(244, 245, 247, 255),

    chrome      = tocolor(28, 30, 34, 255),
    chromeLine  = tocolor(255, 255, 255, 18),
    chromeBtn   = tocolor(255, 255, 255, 24),
    chromeBtnHi = tocolor(255, 255, 255, 52),
    chromeIcon  = tocolor(232, 234, 237, 255),
    urlBar      = tocolor(52, 55, 60, 255),
    urlText     = tocolor(206, 210, 216, 255),

    pageBg      = tocolor(244, 245, 247, 255),
    text        = tocolor(31, 35, 40, 255),
    heading     = tocolor(17, 21, 26, 255),
    muted       = tocolor(101, 109, 118, 255),
    link        = tocolor(37, 99, 235, 255),

    card        = tocolor(255, 255, 255, 255),
    cardLine    = tocolor(19, 24, 31, 28),
    cardHi      = tocolor(37, 99, 235, 22),

    primary     = tocolor(37, 99, 235, 255),
    primaryTxt  = tocolor(255, 255, 255, 255),
    buy         = tocolor(22, 128, 61, 255),
    danger      = tocolor(210, 45, 40, 255),
    dark        = tocolor(28, 30, 34, 255),

    hoverWash   = tocolor(37, 99, 235, 26),
    scrollTrack = tocolor(19, 24, 31, 22),
    scrollThumb = tocolor(19, 24, 31, 92),

    homeBg      = tocolor(26, 115, 232, 255),
    homeBg2     = tocolor(21, 87, 176, 255),
    onblue      = tocolor(255, 255, 255, 235),
}

-- Per-category accent colours (headers, badges, buttons).
BR.accents = {
    vehicles      = tocolor(37, 99, 235, 255),
    realestate    = tocolor(22, 163, 74, 255),
    business      = tocolor(217, 119, 6, 255),
    entertainment = tocolor(219, 39, 119, 255),
    finance       = tocolor(8, 145, 178, 255),
}

function BR.accentOf(catId)
    return BR.accents[catId] or BR.theme.primary
end

-- Named classes usable in markup.
--   fg = text colour, bg = fill (buttons), border = stroke, size = font mult,
--   bold = bold font.
BR.classes = {
    ["btn-primary"] = { bg = BR.theme.primary, fg = BR.theme.primaryTxt },
    ["btn-buy"]     = { bg = BR.theme.buy,     fg = tocolor(255, 255, 255, 255) },
    ["btn-danger"]  = { bg = BR.theme.danger,  fg = tocolor(255, 255, 255, 255) },
    ["btn-dark"]    = { bg = tocolor(64, 68, 76, 255), fg = tocolor(255, 255, 255, 255) },
    ["btn-ghost"]   = { bg = tocolor(0, 0, 0, 0), fg = BR.theme.primary, border = BR.theme.primary },
    -- The product "BUY for $..." call to action: always brownish-grey, darkens on hover.
    ["btn-cta"]     = { bg = tocolor(124, 114, 101, 255), fg = tocolor(255, 255, 255, 255) },

    ["muted"]       = { fg = BR.theme.muted },
    ["onblue"]      = { fg = BR.theme.onblue },
    ["price"]       = { fg = BR.theme.buy, size = 1.3, bold = true },
    ["big"]         = { size = 1.3 },
}

function BR.classStyle(name)
    return name and BR.classes[name] or nil
end
