-- ui_browser :: core/registry.lua
-- Registry of virtual websites. Every site has an address (e.g. lvcars.vm), a
-- category, a short description, and a folder under sites/ that holds its markup
-- (page.vhtml), its logo (logo.png) and any images it uses. A site may instead
-- provide a builder(query) function that produces the markup at runtime.

BR.categories = {
    { id = "entertainment", label = "Entertainment" },
    { id = "finance",       label = "Finance" },
    { id = "business",      label = "Business" },
    { id = "vehicles",      label = "Vehicles" },
    { id = "realestate",    label = "Property" },
}

BR.sites = {}

function BR.registerSite(url, def)
    if type(url) ~= "string" or type(def) ~= "table" then return false end
    url = BR.parseUrl(url).path
    def.url = url
    BR.sites[url] = def
    return true
end

function BR.getSite(path)
    return BR.sites[path]
end

function BR.getCategory(id)
    for _, c in ipairs(BR.categories) do
        if c.id == id then return c end
    end
    return nil
end

function BR.sitesByCategory(cat)
    local t = {}
    for _, s in pairs(BR.sites) do
        if s.category == cat then t[#t + 1] = s end
    end
    table.sort(t, function(a, b) return (a.title or a.url) < (b.title or b.url) end)
    return t
end

function BR.allSites()
    local t = {}
    for _, s in pairs(BR.sites) do t[#t + 1] = s end
    table.sort(t, function(a, b) return (a.title or a.url) < (b.title or b.url) end)
    return t
end

-- Logo path if the file is present, otherwise nil.
function BR.siteLogo(site)
    if site and site.logo and fileExists(site.logo) then return site.logo end
    return nil
end

-- 3 random sites for the home page "AI picks" section.
function BR.recommendations(count)
    count = count or 3
    local all = BR.allSites()
    for i = #all, 2, -1 do
        local j = math.random(i)
        all[i], all[j] = all[j], all[i]
    end
    local out = {}
    for i = 1, math.min(count, #all) do out[i] = all[i] end
    return out
end

--------------------------------------------------------------------------------
-- Default sites
--------------------------------------------------------------------------------

local function site(url, folder, category, title, desc, extra)
    local dir = "sites/" .. folder
    local def = {
        title = title, category = category, desc = desc,
        dir = dir, logo = dir .. "/logo.png",
    }
    if extra then
        for k, v in pairs(extra) do def[k] = v end
    end
    if not def.builder then def.markup = dir .. "/page.vhtml" end
    BR.registerSite(url, def)
end

site("lvcars.eu", "lvcars", "vehicles", "Las Venturas Cars",
    "Certified used cars with warranty, ready to drive away today.")

site("legendary.eu", "legendary", "vehicles", "Legendary Wheels",
    "Sport and luxury cars and bikes from the biggest showroom in the state.")

site("vizair.eu", "vizair", "vehicles", "VizAir",
    "Private aircraft: helicopters, light planes and jets.")

site("cityhomes.eu", "cityhomes", "realestate", "CityHomes",
    "Apartments and houses downtown and in the outer districts.")

site("bizmarket.eu", "bizmarket", "business", "BizMarket",
    "Running businesses for sale: shops, car washes, gas stations.")

site("fiero.eu", "fiero", "business", "Fiero Markets",
    "Private stakes in the city's bars, clubs and late-night venues.")

site("diamond.eu", "diamond", "entertainment", "Diamond Casino",
    "The Diamond: slots, tables and high-limit rooms. Opening soon.")

site("libertybank.eu", "bank", "finance", "Liberty Bank",
    "Deposit and withdraw cash, check your account balance.",
    { builder = function(query) return BR.buildBank(query) end })
