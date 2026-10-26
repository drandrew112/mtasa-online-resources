if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Registration runs without blocking the server (PERF-01):
--   1. acc_auth:register        name / email checks, name lookup (async)
--   2. acc_auth:registerName    bcrypt hash (async)
--   3. createAccountRowPooled   takes a reserved pool row (pool.lua) or inserts;
--                               the UNIQUE account_name / email decide a race
--   4. acc_auth:registerRow     log in as the new account (onPlayerAccountLogin, isNew = true)

local registerPending = {} -- [player] = { id, username, password, email, timer } until step 4 or an error
local registerById    = {} -- [id] = player
local registerSeq     = 0

local function clearRegister(player)
    local p = registerPending[player]
    if not p then return end
    registerPending[player] = nil
    registerById[p.id] = nil
    if isTimer(p.timer) then killTimer(p.timer) end
end

local function registerError(player, key)
    clearRegister(player)
    authError(player, key)
end

-- the pending registration of a request id, if the player can still use it
local function registerOf(id)
    local player = registerById[id]
    if not player then return nil end
    local p = registerPending[player]
    if not p or p.id ~= id then return nil end
    if not isElement(player) or getElementData(player, "isLogged") == true then
        clearRegister(player)
        return nil
    end
    return player, p
end

-- Lower-cased, trimmed email, nil when empty; false when invalid.
function normalizeEmail(email)
    if type(email) ~= "string" then return nil end
    email = email:gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if email == "" then return nil end
    if #email > AUTH.EMAIL_MAX then return false end
    local localPart, domain = email:match("^([^@%s]+)@([^@%s]+)$")
    if not localPart or not domain:find("^[%w%-]+%.[%w%.%-]+$") or domain:find("%.%.") or domain:find("%.$") then
        return false
    end
    return email
end

local function finishRegister(player, username, id)
    clearRegister(player)
    markLoggedIn(player, username, id, true)
end

-- Step 4: the row was inserted (or not).
addEvent("acc_auth:registerRow")
addEventHandler("acc_auth:registerRow", resourceRoot, function(id, newId, err)
    local player, p = registerOf(id)
    if not player then return end
    if type(newId) ~= "number" then
        local e = tostring(err):lower()
        if e:find("duplicate", 1, true) then
            if e:find("email", 1, true) then return registerError(player, "acc_auth.server.email_in_use") end
            return registerError(player, "acc_auth.server.account_already_exists")
        end
        return registerError(player, "acc_auth.server.registration_failed")
    end
    accountRowCreated(p.username)
    finishRegister(player, p.username, newId)
end)

-- Step 2: the name check answered -> hash the password -> step 3.
addEvent("acc_auth:registerName")
addEventHandler("acc_auth:registerName", resourceRoot, function(id, rows)
    local player, p = registerOf(id)
    if not player then return end
    if type(rows) ~= "table" then
        return registerError(player, "acc_auth.server.registration_failed")
    end
    if rows[1] then
        rememberAccountName(rows[1].account_name)
        return registerError(player, "acc_auth.server.account_already_exists")
    end

    local password = p.password
    p.password = nil
    passwordHash(password, "bcrypt", {}, function(hashed)
        if registerOf(id) ~= player then return end -- timed out, quit or logged in meanwhile
        if type(hashed) ~= "string" then
            return registerError(player, "acc_auth.server.registration_failed")
        end
        if not createAccountRowPooled(p.username, hashed, p.email, "acc_auth:registerRow", id) then
            -- No answer is coming (v_mysql stopped): without a database connection
            -- the answer already came and cleared the request.
            if registerOf(id) ~= player then return end
            local newId = createAccountRow(p.username, hashed, p.email)
            if not newId then
                return registerError(player, "acc_auth.server.registration_failed")
            end
            finishRegister(player, p.username, newId)
        end
    end)
end)

-- Step 1: the client asks to register. email may be empty.
addEvent("acc_auth:register", true)
addEventHandler("acc_auth:register", root, function(username, password, email)
    local player = client
    if not isElement(player) then return end
    if getElementData(player, "banned") == true then return end
    if getElementData(player, "isLogged") == true then return end
    if registerPending[player] or loginPending[player] then return end

    local tick = getTickCount()
    if lastAttempt[player] and tick - lastAttempt[player] < AUTH.REGISTER_MIN_INTERVAL then return end
    lastAttempt[player] = tick

    if type(username) ~= "string" or type(password) ~= "string" then return end
    if not username:find("^[%w_%-%.]+$") or #username < 3 or #username > 30 then
        return authError(player, "acc_auth.server.username_must_be_3_30_chars")
    end
    if #password > 128 then return end
    if #password < AUTH.PASSWORD_MIN then
        return authError(player, "acc_auth.server.password_too_short")
    end
    local mail = normalizeEmail(email)
    if mail == false then
        return authError(player, "acc_auth.server.invalid_email")
    end
    if knownAccountName(username) then
        return authError(player, "acc_auth.server.account_already_exists")
    end

    registerSeq = registerSeq + 1
    local id = registerSeq
    registerPending[player] = {
        id = id, username = username, password = password, email = mail,
        timer = setTimer(function()
            if registerOf(id) == player then
                registerError(player, "acc_auth.server.registration_failed")
            end
        end, AUTH.REGISTER_TIMEOUT, 1),
    }
    registerById[id] = player

    if not fetchAccountNameAsync(username, "acc_auth:registerName", id) then
        -- without a DB connection acc_auth:registerName may already have answered
        if registerOf(id) == player then
            registerError(player, "acc_auth.server.registration_failed")
        end
    end
end)

addEventHandler("onPlayerQuit", root, function()
    clearRegister(source)
end)
