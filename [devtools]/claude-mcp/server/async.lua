-- Jobs: every API request runs in its own coroutine.
--
-- A handler that never waits finishes inside the HTTP call and its result is
-- returned directly. A handler that waits (probe client reply, timer, screenshot)
-- yields; the HTTP call then returns { pending = true, job = id } and the result
-- is delivered later:
--   * pushed to the Node server (meta.callback URL, fetchRemote POST), and
--   * kept for JOB_KEEP ms so it can be polled with jobs("poll", { ids }).
--
-- Lua 5.1 cannot yield across pcall, so handlers must not wrap yielding calls
-- in pcall; errors are caught at coroutine.resume.

Async = { jobs = {}, seq = 0, FAIL = {}, coroutines = setmetatable({}, { __mode = "k" }) }

function Async.isJobCoroutine(co)
    return Async.coroutines[co] ~= nil
end

local function now() return getTickCount() end

local function finish(job, ok, value)
    if job.done then return end
    job.done = true
    job.finishedAt = now()
    if job.watchdog and isTimer(job.watchdog) then killTimer(job.watchdog) end
    if ok then
        job.envelope = { ok = true, result = Util.jsonSafe(value), job = job.id, ms = job.finishedAt - job.startedAt }
    else
        local err = Util.toError(value)
        job.envelope = { ok = false, error = err, job = job.id, ms = job.finishedAt - job.startedAt }
        Util.addLog("warning", "api", job.category .. "." .. job.action .. " failed: " .. tostring(err.code) .. " " .. tostring(err.message))
    end
    if job.cleanup then
        for i = #job.cleanup, 1, -1 do pcall(job.cleanup[i]) end
    end
    if job.async and job.callback then
        local body = toJSON({ job = job.id, envelope = job.envelope }, true)
        if body then
            body = body:sub(2, -2) -- toJSON wraps the value in [ ]
            fetchRemote(job.callback, {
                method = "POST", postData = body, connectionAttempts = 1, connectTimeout = 3000,
                headers = { ["Content-Type"] = "application/json" },
            }, function() end)
        end
    end
end

function Async.resume(job, ...)
    if job.done then return end
    local ok, value, failErr = coroutine.resume(job.co, ...)
    if ok and value == Async.FAIL then
        finish(job, false, failErr)
    elseif not ok then
        finish(job, false, value)
    elseif coroutine.status(job.co) == "dead" then
        finish(job, true, value)
    end
end

-- Runs handler(params, job) as a job -> envelope (finished) or pending envelope
function Async.run(category, action, handler, params, meta)
    Async.seq = Async.seq + 1
    local job = {
        id = "j" .. Async.seq, category = category, action = action,
        startedAt = now(), callback = type(meta) == "table" and type(meta.callback) == "string" and meta.callback or nil,
        cleanup = {},
    }
    job.co = coroutine.create(function() return handler(params or {}, job) end)
    Async.coroutines[job.co] = job
    Async.current = job
    Async.resume(job)
    Async.current = nil
    if job.done then
        return job.envelope
    end
    job.async = true
    Async.jobs[job.id] = job
    job.watchdog = setTimer(function()
        if not job.done then
            finish(job, false, { __cmcp = true, code = "JOB_TIMEOUT", message = "The request did not finish within " .. CMCP.JOB_MAX_RUNTIME .. " ms.", retryable = true })
        end
    end, CMCP.JOB_MAX_RUNTIME, 1)
    return { ok = true, pending = true, job = job.id }
end

-- the job of the running coroutine (or nil when not inside a job)
function Async.self()
    local co = coroutine.running()
    if not co then return nil end
    for _, job in pairs(Async.jobs) do
        if job.co == co then return job end
    end
    if Async.current and Async.current.co == co then return Async.current end
    return nil
end

-- registers a function to run when the job ends (success or failure)
function Async.defer(fn)
    local job = Async.self()
    if job then job.cleanup[#job.cleanup + 1] = fn end
end

-- Suspends the running job until wake(...) is called; returns wake's arguments.
-- Usage: local wake = Async.waker(); someCallback(function(...) wake(...) end); return Async.wait()
function Async.waker()
    local job = Async.self()
    if not job then fail("INTERNAL_ERROR", "Async.waker outside a job") end
    local fired = false
    return function(...)
        if fired then return end
        fired = true
        -- always resume from a fresh stack frame (never inside the yielding call itself)
        local args = { ... }
        local n = select("#", ...)
        setTimer(function() Async.resume(job, unpack(args, 1, n)) end, 50, 1)
    end
end

function Async.wait()
    return coroutine.yield()
end

function Async.sleep(ms)
    local wake = Async.waker()
    setTimer(wake, math.max(50, ms), 1)
    Async.wait()
end

function Async.poll(ids)
    local out = {}
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        local job = Async.jobs[tostring(id)]
        if not job then
            out[tostring(id)] = { ok = false, error = { code = "JOB_NOT_FOUND", message = "Unknown or expired job " .. tostring(id) .. ".",
                suggestion = "The bridge may have restarted; re-run the request." } }
        elseif job.done then
            out[tostring(id)] = job.envelope
        else
            out[tostring(id)] = { ok = true, pending = true, job = job.id, runningMs = now() - job.startedAt }
        end
    end
    return out
end

function Async.stats()
    local running, done = 0, 0
    for _, job in pairs(Async.jobs) do
        if job.done then done = done + 1 else running = running + 1 end
    end
    return { running = running, finishedKept = done, total = Async.seq }
end

-- purge old finished jobs
setTimer(function()
    local t = now()
    for id, job in pairs(Async.jobs) do
        if job.done and t - job.finishedAt > CMCP.JOB_KEEP then Async.jobs[id] = nil end
    end
end, 10000, 0)
