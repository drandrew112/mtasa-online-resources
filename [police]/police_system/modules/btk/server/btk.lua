-- police_system / modules/btk/server/btk.lua
-- The penal code (BTK): shared/btk.json holds the defaults; the government's overrides live in the gov_core setting
-- police.btk ({ [id] = amount }), the default always stays (/gov "Reset to default"). The fine income goes to the
-- state account of the setting police.fine_target (a state account code, default the treasury).

local B = POL.module("btk", { items = {}, byId = {}, categories = {} })

local function load()
    local f = fileExists("shared/btk.json") and fileOpen("shared/btk.json", true)
    if not f then outputDebugString("[police_system] shared/btk.json missing", 1) return end
    local data = fromJSON(fileRead(f, fileGetSize(f)))
    fileClose(f)
    B.items, B.byId, B.categories = {}, {}, {}
    for _, cat in ipairs(type(data) == "table" and data.categories or {}) do
        local c = { id = cat.id, warning = cat.warning == true, items = {} }
        B.categories[#B.categories + 1] = c
        for _, it in ipairs(cat.items or {}) do
            local e = {
                id = it.id, cat = cat.id, default = tonumber(it.amount) or 0, warning = cat.warning == true,
                warningId = it.warning, arrestable = it.arrestable == true, warrant = it.warrant == true,
                wanted = tonumber(it.wanted), minutes = tonumber(it.minutes) or 0,
            }
            B.items[#B.items + 1] = e
            B.byId[e.id] = e
            c.items[#c.items + 1] = e
        end
    end
end

local function overrides()
    if not POL.running("gov_core") then return {} end
    local ok, v = pcall(function() return exports.gov_core:getSetting("police.btk") end)
    return ok and type(v) == "table" and v or {}
end

-- current amount (government override or default)
function B.amount(id)
    local e = B.byId[id]
    if not e then return 0 end
    local o = tonumber(overrides()[id])
    return o and math.max(0, math.floor(o)) or e.default
end

function B.get(id) return B.byId[id] end

-- the code list with the current amounts (MDC Penal code, stop menus, police_web)
function B.list()
    local o = overrides()
    local out = {}
    for _, c in ipairs(B.categories) do
        local cat = { id = c.id, warning = c.warning, items = {} }
        for _, e in ipairs(c.items) do
            local cur = tonumber(o[e.id])
            cat.items[#cat.items + 1] = { id = e.id, amount = cur and math.floor(cur) or e.default, default = e.default,
                warning = e.warning, arrestable = e.arrestable, warrant = e.warrant, minutes = e.minutes }
        end
        out[#out + 1] = cat
    end
    return out
end

-- warrant reasons: the BTK items marked "warrant" + the extra ones (unpaid_fines, escape_custody, evading_arrest)
function B.warrantReasons()
    local out = {}
    for _, e in ipairs(B.items) do
        if e.warrant then out[#out + 1] = { id = e.id, minutes = e.minutes } end
    end
    for _, x in ipairs(WARRANT_EXTRA) do out[#out + 1] = { id = x.id, minutes = x.minutes } end
    return out
end

function B.reasonMinutes(id)
    local e = B.byId[id]
    if e then return e.minutes end
    for _, x in ipairs(WARRANT_EXTRA) do if x.id == id then return x.minutes end end
    return 0
end

-- v_bank account id the fines go to (nil = the treasury default of the bank key)
function B.fineTarget()
    if not POL.running("v_bank") then return nil end
    local code = "treasury"
    if POL.running("gov_core") then
        local ok, v = pcall(function() return exports.gov_core:getSetting("police.fine_target") end)
        if ok and type(v) == "string" and v ~= "" then code = v end
    end
    local ok, id = pcall(function() return exports.v_bank:getStateAccount(code) end)
    if ok and id then return id end
    local ok2, tid = pcall(function() return exports.v_bank:getStateAccount("treasury") end)
    return ok2 and tid or nil
end

function B.start() load() end
