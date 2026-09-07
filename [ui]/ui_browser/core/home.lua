-- ui_browser :: core/home.lua
-- Builds the markup for the home page ("Open SE"), the Liberty Bank page and
-- the error page. These all go through the shared layout engine; only their
-- markup is generated.

local function esc(s)
    return tostring(s or "")
        :gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end

local function money(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(math.abs(n))
    s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (n < 0 and "-$" or "$") .. s
end
BR.formatMoney = money

local function siteCardMarkup(s)
    local logo = BR.siteLogo(s)
    return ('<sitecard href="%s" title="%s" url="%s"%s>%s</sitecard>'):format(
        esc(s.url), esc(s.title), esc(s.url),
        logo and (' logo="' .. esc(logo) .. '"') or "",
        esc(s.desc))
end

--------------------------------------------------------------------------------
-- Home page
--------------------------------------------------------------------------------

function BR.buildHome(query)
    local cat = query and query.cat
    local b = {}

    b[#b + 1] = '<page bg="#0c1521" text="#e8eef5" heading="#ffffff" muted="#8fa0b3" ' ..
        'link="#5aa9ff" accent="#1a73e8" card="#161f2e" cardline="#2b3a4f">'
    b[#b + 1] = '<space h="48" />'
    b[#b + 1] = '<brand href="home">Open SE</brand>'
    b[#b + 1] = '<p align="center" class="muted">The virtual web, all in one place</p>'
    b[#b + 1] = '<space h="14" />'
    b[#b + 1] = '<searchbox placeholder="Search the virtual web or type an address" />'
    b[#b + 1] = '<space h="26" />'

    b[#b + 1] = '<row gap="10">'
    for _, c in ipairs(BR.categories) do
        local sel = (c.id == cat) and ' sel="1"' or ''
        b[#b + 1] = ('<catbtn href="home?cat=%s" cat="%s"%s>%s</catbtn>')
            :format(c.id, c.id, sel, esc(c.label))
    end
    b[#b + 1] = '</row>'
    b[#b + 1] = '<space h="26" />'

    if cat then
        local c = BR.getCategory(cat)
        local list = BR.sitesByCategory(cat)
        b[#b + 1] = '<card>'
        b[#b + 1] = ('<h2>%s</h2>'):format(esc(c and c.label or cat))
        if #list == 0 then
            b[#b + 1] = '<p class="muted">No websites in this category yet.</p>'
        else
            b[#b + 1] = '<grid cols="3" gap="16">'
            for _, s in ipairs(list) do b[#b + 1] = siteCardMarkup(s) end
            b[#b + 1] = '</grid>'
        end
        b[#b + 1] = '</card>'
    else
        b[#b + 1] = '<h2 align="center">AI picks for you</h2>'
        b[#b + 1] = '<space h="4" />'
        b[#b + 1] = '<grid cols="3" gap="16">'
        for _, s in ipairs(BR.recommendations(3)) do b[#b + 1] = siteCardMarkup(s) end
        b[#b + 1] = '</grid>'
        b[#b + 1] = '<space h="6" />'
        b[#b + 1] = '<p align="center" class="muted">Pick a category above to see every site</p>'
    end

    b[#b + 1] = '</page>'
    return table.concat(b, "\n")
end

--------------------------------------------------------------------------------
-- Search results
--------------------------------------------------------------------------------

function BR.buildSearch(term)
    term = tostring(term or "")
    local low = term:lower()
    local hits = {}
    for _, s in ipairs(BR.allSites()) do
        local hay = ((s.title or "") .. " " .. (s.desc or "") .. " " .. (s.url or "")):lower()
        if low == "" or hay:find(low, 1, true) then
            hits[#hits + 1] = s
        end
    end

    local b = {}
    b[#b + 1] = '<page bg="#f4f5f7">'
    b[#b + 1] = '<space h="16" />'
    b[#b + 1] = ('<h2>Results for "%s"</h2>'):format(esc(term))
    b[#b + 1] = ('<p class="muted">%d site(s) found</p>'):format(#hits)
    b[#b + 1] = '<space h="8" />'
    if #hits == 0 then
        b[#b + 1] = '<card><p>No sites matched your search. Try a category from the home page.</p></card>'
    else
        b[#b + 1] = '<grid cols="3" gap="16">'
        for _, s in ipairs(hits) do b[#b + 1] = siteCardMarkup(s) end
        b[#b + 1] = '</grid>'
    end
    b[#b + 1] = '<link href="home">Back to search</link>'
    b[#b + 1] = '</page>'
    return table.concat(b, "\n")
end

--------------------------------------------------------------------------------
-- Product detail page
--------------------------------------------------------------------------------

local COLORS = {
    black  = { "#141414", "Black" },
    white  = { "#f2f2f2", "White" },
    silver = { "#c4c8cc", "Silver" },
    grey   = { "#7d838a", "Grey" },
    red    = { "#c0392b", "Red" },
    blue   = { "#2563eb", "Blue" },
    green  = { "#1e8e3e", "Green" },
    yellow = { "#e6b800", "Yellow" },
    orange = { "#e67e22", "Orange" },
    purple = { "#7c3aed", "Purple" },
}

-- pageAttrs: the <page> attributes of the site (so the detail page keeps the
-- same theme). product: the parsed <product> node. selColor: chosen colour id.
function BR.buildProduct(pageAttrs, site, product, selColor)
    local pa = pageAttrs or {}
    local name = product.attrs.name or "Product"
    local price = product.attrs.price or ""
    local img = product.attrs.img or product.attrs.src or ""
    local desc = BR.nodeText(product)
    local colours = product.attrs.colors

    local pageOpen = "<page"
    for _, k in ipairs({ "bg", "text", "heading", "muted", "link", "accent", "card", "cardline" }) do
        if pa[k] then pageOpen = pageOpen .. (' %s="%s"'):format(k, pa[k]) end
    end
    pageOpen = pageOpen .. ">"

    local b = { pageOpen, '<space h="8" />', '<row gap="28">' }
    b[#b + 1] = ('<productimage src="%s" alt="%s" />'):format(esc(img), esc(name))
    b[#b + 1] = '<col>'
    b[#b + 1] = ('<h1>%s</h1>'):format(esc(name))
    if desc ~= "" then b[#b + 1] = ('<p class="muted">%s</p>'):format(esc(desc)) end
    b[#b + 1] = ('<h2>%s</h2>'):format(esc(price))

    local buyArg = product.attrs.id or ""
    if colours and colours ~= "" then
        local first, chosen
        b[#b + 1] = '<swatches label="Colour">'
        for cname in colours:gmatch("[^,%s]+") do
            local key = cname:lower()
            local info = COLORS[key] or { "#999999", cname }
            if not first then first = key end
            local isSel = (selColor and selColor:lower() == key) or (not selColor and not chosen)
            if isSel then chosen = key end
            b[#b + 1] = ('<swatch color="%s" val="%s"%s />'):format(info[1], key, isSel and ' sel="1"' or '')
        end
        b[#b + 1] = '</swatches>'
        buyArg = buyArg .. ":" .. (chosen or first or "")
    end

    b[#b + 1] = ('<button class="btn-cta" block="1" action="buy:%s">BUY for %s</button>')
        :format(esc(buyArg), esc(price))
    b[#b + 1] = '<space h="10" />'
    b[#b + 1] = ('<link href="%s">Back to %s</link>'):format(esc(site.url), esc(site.title or site.url))
    b[#b + 1] = '</col>'
    b[#b + 1] = '</row>'
    b[#b + 1] = '</page>'
    return table.concat(b, "\n")
end

--------------------------------------------------------------------------------
-- Liberty Bank
--------------------------------------------------------------------------------

function BR.buildBank(query)
    local bankMoney = tonumber(getElementData(localPlayer, "bank_money")) or 0
    local cash = getPlayerMoney(localPlayer) or 0

    local b = {}
    b[#b + 1] = '<page bg="#0a1a3a" text="#e8f0fc" heading="#ffffff" muted="#9ab5d8" ' ..
        'link="#7cc4ff" accent="#38bdf8" card="#12244a" cardline="#2a3f66">'
    b[#b + 1] = '<siteheader title="Liberty Bank" tagline="Personal current account" accent="#38bdf8" />'

    b[#b + 1] = '<row gap="16">'
    b[#b + 1] = ('<card accent="#0891b2"><small class="muted">BANK BALANCE</small><h1>%s</h1></card>')
        :format(esc(money(bankMoney)))
    b[#b + 1] = ('<card><small class="muted">CASH ON HAND</small><h1>%s</h1></card>')
        :format(esc(money(cash)))
    b[#b + 1] = '</row>'
    b[#b + 1] = '<space h="6" />'

    b[#b + 1] = '<card>'
    b[#b + 1] = '<h3>Deposit cash</h3>'
    b[#b + 1] = '<p class="muted">Move money from your pocket into the bank.</p>'
    b[#b + 1] = '<buttons gap="10">'
    for _, amt in ipairs({ 100, 500, 1000, 5000 }) do
        b[#b + 1] = ('<button class="btn-primary" action="bank_deposit:%d">%s</button>')
            :format(amt, esc(money(amt)))
    end
    b[#b + 1] = ('<button class="btn-dark" action="bank_deposit:all">Deposit all</button>')
    b[#b + 1] = '</buttons>'
    b[#b + 1] = '</card>'

    b[#b + 1] = '<card>'
    b[#b + 1] = '<h3>Withdraw cash</h3>'
    b[#b + 1] = '<p class="muted">Move money from the bank into your pocket.</p>'
    b[#b + 1] = '<buttons gap="10">'
    for _, amt in ipairs({ 100, 500, 1000, 5000 }) do
        b[#b + 1] = ('<button class="btn-buy" action="bank_withdraw:%d">%s</button>')
            :format(amt, esc(money(amt)))
    end
    b[#b + 1] = ('<button class="btn-dark" action="bank_withdraw:all">Withdraw all</button>')
    b[#b + 1] = '</buttons>'
    b[#b + 1] = '</card>'

    b[#b + 1] = '<link href="home">Back to search</link>'
    b[#b + 1] = '</page>'
    return table.concat(b, "\n")
end

--------------------------------------------------------------------------------
-- Error page
--------------------------------------------------------------------------------

function BR.buildErrorPage(path, message)
    return table.concat({
        '<page bg="#f4f5f7">',
        '<space h="30" />',
        '<card>',
        '<h1>This page could not be opened</h1>',
        ('<p class="muted">%s</p>'):format(esc(message or "Unknown error.")),
        ('<p class="muted">Address: %s</p>'):format(esc(path or "")),
        '<space h="8" />',
        '<button class="btn-primary" href="home">Back to the home page</button>',
        '</card>',
        '</page>',
    }, "\n")
end
