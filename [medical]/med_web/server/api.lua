-- med_web :: server/api.lua
-- The http="true" exports of the web pages (POST /med_web/call/<fn>, in game relayed by
-- web_api). The dispatcher / tablet / admin calls are only forwarded: the logic and the
-- sessions live in med_erm, reached through its webCall export, which also gets the caller id
-- (HTTP address or "player:<serial>") for its login throttles - `hostname` is a global of
-- this resource only.

local UNAVAILABLE = { ok = false, error = "The dispatch system (med_erm) is not running." }

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function forward(fn)
    return function(...)
        if not running("med_erm") then return UNAVAILABLE end
        local result = exports.med_erm:webCall(exports.web_api:getCallerId(hostname), fn, ...)
        return result == nil and { ok = false, error = "Server error" } or result
    end
end

-- dispatcher console (web/dispatch.html), first argument = session token
for _, fn in ipairs({
    "ermLogin", "ermLogout", "ermGetState", "ermSetPriority", "ermAssign", "ermUnassign",
    "ermCloseTask", "ermCreateTask", "ermSendMessage",
    -- unit tablet (web/tablet.html)
    "ermTabletLogin", "ermTabletLogout", "ermTabletState", "ermTabletCaseAction",
    "ermTabletLeaveCase", "ermTabletCloseCase", "ermTabletSendMessage", "ermTabletEndShift",
    -- ERM admin (web/admin.html)
    "ermAdminLogin", "ermAdminLogout", "ermAdminQuery", "ermAdminAuto", "ermAdminAutoSet",
}) do
    _G[fn] = forward(fn)
end

---------------------------------------------------------------- landing page

-- Public, anonymous figures for the landing page (web/index.html): no names, no task details.
local CACHE_MS = 3000
local cache, cacheAt = nil, -CACHE_MS

local function buildPublicState()
    local out = {
        ok = true, time = getRealTime().timestamp, online = running("med_erm"),
        units = 0, byStatus = { available = 0, enroute = 0, onscene = 0, handover = 0 },
        tasks = 0, hospitals = {},
    }
    if out.online then
        local units = exports.med_erm:getUnits() or {}
        out.units = #units
        for _, u in ipairs(units) do
            if out.byStatus[u.status] then out.byStatus[u.status] = out.byStatus[u.status] + 1 end
        end
        out.tasks = #(exports.med_erm:getTasks() or {})
    end
    if running("med_hospitals") then
        for _, h in ipairs(exports.med_hospitals:getHospitals() or {}) do
            if (h.interior or 0) == 0 and (h.dimension or 0) == 0 then
                out.hospitals[#out.hospitals + 1] = { name = h.name, x = h.x, y = h.y, bays = h.bays }
            end
        end
    end
    return out
end

function medWebPublic()
    local t = getTickCount()
    if not cache or t - cacheAt > CACHE_MS then
        local ok, state = pcall(buildPublicState)
        cache = ok and state or { ok = false, error = "Unavailable" }
        cacheAt = t
    end
    return cache
end
