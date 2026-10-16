-- Web API (dispatcher console here, unit tablet in server/webtablet.lua, ERM admin in
-- server/webadmin.lua).
--
-- The pages live in med_web, which exposes these functions over HTTP / in game and forwards
-- every call to the webCall export below. No MTA account is involved in the dispatcher
-- console: the first argument is always the session token from ermLogin
-- (see server/dispatchers.lua).

-- caller id of the running web call ("player:<serial>" in game, the HTTP address otherwise),
-- for the login throttles; set by webCall only
local webCaller = nil

Web = {}

function Web.callerId()
    return webCaller or "web"
end

local WEB_FUNCTIONS = {}
for _, fn in ipairs({
    "ermLogin", "ermLogout", "ermGetState", "ermSetPriority", "ermAssign", "ermUnassign",
    "ermCloseTask", "ermCreateTask", "ermSendMessage",
    "ermTabletLogin", "ermTabletLogout", "ermTabletState", "ermTabletCaseAction",
    "ermTabletLeaveCase", "ermTabletCloseCase", "ermTabletSendMessage", "ermTabletEndShift",
    "ermAdminLogin", "ermAdminLogout", "ermAdminQuery", "ermAdminAuto", "ermAdminAutoSet",
}) do WEB_FUNCTIONS[fn] = true end

-- webCall(callerId, fn, ...) -> the result of one web API function (med_web/server/api.lua)
function webCall(callerId, fn, ...)
    if not WEB_FUNCTIONS[fn] or type(_G[fn]) ~= "function" then return { ok = false, error = "Unknown function" } end
    webCaller = type(callerId) == "string" and callerId ~= "" and callerId:sub(1, 80) or nil
    local ok, res = pcall(_G[fn], ...)
    webCaller = nil
    if not ok then
        outputDebugString("[med_erm] web " .. fn .. ": " .. tostring(res), 1)
        return { ok = false, error = "Server error" }
    end
    return res
end

local function result(ok, err)
    if ok then return { ok = true } end
    return { ok = false, error = err or "Failed" }
end

local DENIED = { ok = false, error = "unauthorized" }

function ermLogin(_, code)
    local session, token = Dispatchers.login(code)
    if not session then return { ok = false, error = token } end
    return { ok = true, token = token, name = session.name, displayName = session.display }
end

function ermLogout(token)
    Dispatchers.logout(token)
    return { ok = true }
end

function ermGetState(token, lastMessageId)
    local s = Dispatchers.check(token)
    if not s then return DENIED end
    return {
        ok          = true,
        time        = now(),
        displayName = s.display,
        units       = Units.publicList(),
        tasks       = Tasks.publicActive(),
        closed      = Tasks.publicClosed(),
        messages    = Chat.since(tonumber(lastMessageId) or 0),
        auto        = AutoDispatch.state(),
    }
end

function ermSetPriority(token, taskId, priority)
    if not Dispatchers.check(token) then return DENIED end
    return result(Tasks.setPriority(taskId, priority))
end

function ermAssign(token, taskId, unitId)
    if not Dispatchers.check(token) then return DENIED end
    return result(Tasks.assign(taskId, unitId))
end

function ermUnassign(token, taskId, unitId)
    if not Dispatchers.check(token) then return DENIED end
    return result(Tasks.unassign(taskId, unitId))
end

function ermCloseTask(token, taskId, reason)
    local s = Dispatchers.check(token)
    if not s then return DENIED end
    return result(Tasks.close(taskId, (reason and reason ~= "") and reason or ("Closed by " .. s.display)))
end

function ermCreateTask(token, title, description, x, y, caller)
    local s = Dispatchers.check(token)
    if not s then return DENIED end
    local id, err = Tasks.create(title, description, x, y, 0, (caller and caller ~= "") and caller or s.display, "")
    if not id then return result(false, err) end
    return { ok = true, id = id }
end

-- The sender name always comes from the session: "Dispatcher <name>".
function ermSendMessage(token, channel, target, text)
    local s = Dispatchers.check(token)
    if not s then return DENIED end
    local id, err = Chat.post(channel, tonumber(target), s.display, true, text)
    return result(id, err)
end
