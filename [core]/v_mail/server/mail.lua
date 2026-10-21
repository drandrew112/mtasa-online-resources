-- Email sending for other resources, through the Brevo transactional email API.
--
-- sendMail(mail, eventName, requestId) -> true | false, error
--   mail = {
--       to       = "a@b.c"  or  { { email = "a@b.c", name = "Name" }, ... },
--       toName   = "Name",          -- optional, with a string `to`
--       subject  = "...",
--       text     = "...",           -- plain text body   (text and/or html)
--       html     = "...",           -- html body
--       template = { ... },         -- instead of text/html: the house layout, see server/template.lua
--       replyTo  = "x@y.z",         -- optional
--       senderName = "...",         -- optional, the sender address stays MAIL.SENDER_EMAIL
--       bulk     = true,            -- optional: waits behind single mails (circulars)
--       log      = { kind, group, account, language, sender } -- optional, for the `mails` table
--                  (default kind/sender = the calling resource, account = toName); false = not stored
--   }
-- A callback function cannot cross an export call, so the answer arrives as an
-- event on the caller's resource root (the caller must addEvent(eventName)):
--   triggerEvent(eventName, <caller resourceRoot>, requestId, ok, info)
--   ok = true: info = Brevo messageId; ok = false: info = error text.
-- A false return means nothing was queued and no event follows.
--
-- Every mail waits in one queue (MAIL.SEND_INTERVAL, MAIL.MAX_IN_FLIGHT).

local urgent, bulk = {}, {}   -- { { body, logName, onDone }, ... } FIFO
local inFlight = 0
local worker = nil

local function configured()
    return type(MAIL.BREVO_API_KEY) == "string" and MAIL.BREVO_API_KEY ~= ""
        and not MAIL.BREVO_API_KEY:find("^CHANGE_ME")
end

function isMailConfigured()
    return configured()
end

function validEmail(email)
    return type(email) == "string" and #email <= 254 and email:match("^[^@%s]+@[^@%s]+%.[^@%s]+$") ~= nil
end

function queuedMailCount()
    return #urgent + #bulk + inFlight
end

-- { { email, name }, ... } | nil
local function recipients(mail)
    if type(mail.to) == "string" then
        if not validEmail(mail.to) then return nil end
        local name = type(mail.toName) == "string" and mail.toName ~= "" and mail.toName or nil
        return { { email = mail.to, name = name } }
    end
    if type(mail.to) ~= "table" or #mail.to == 0 then return nil end
    local list = {}
    for _, r in ipairs(mail.to) do
        if type(r) ~= "table" or not validEmail(r.email) then return nil end
        list[#list + 1] = { email = r.email, name = type(r.name) == "string" and r.name ~= "" and r.name or nil }
    end
    return list
end

local function post(job)
    inFlight = inFlight + 1
    local queued = fetchRemote(MAIL.BREVO_URL, {
        method = "POST",
        postData = toJSON(job.body, true):gsub("^%[(.*)%]$", "%1"),
        headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json",
            ["api-key"] = MAIL.BREVO_API_KEY,
        },
        connectTimeout = MAIL.HTTP_TIMEOUT,
        connectionAttempts = 2,
    }, function(response, info)
        inFlight = inFlight - 1
        -- Brevo answers 201 {"messageId": "..."} when the mail is accepted
        local status = type(info) == "table" and tonumber(info.statusCode) or 0
        local messageId = tostring(response):match('"messageId"%s*:%s*"([^"]+)"')
        if type(info) == "table" and info.success == true and status >= 200 and status < 300 and messageId then
            return job.onDone(true, messageId)
        end
        local err = ("HTTP %s %s"):format(tostring(status), tostring(response):sub(1, 200))
        outputServerLog(("[v_mail] mail from %s to account '%s' failed: %s"):format(job.from, job.logName, err))
        job.onDone(false, err)
    end)
    if not queued then
        inFlight = inFlight - 1
        outputServerLog("[v_mail] fetchRemote refused the request (ACL: v_mail needs function.fetchRemote)")
        job.onDone(false, "fetchRemote refused")
    end
end

local function tick()
    if inFlight >= MAIL.MAX_IN_FLIGHT then return end
    local job = table.remove(urgent, 1) or table.remove(bulk, 1)
    if job then post(job) end
    if #urgent == 0 and #bulk == 0 and isTimer(worker) then
        killTimer(worker)
        worker = nil
    end
end

-- Checks and queues one mail; onDone(ok, messageId | error) runs once later.
-- Returns true | false, error (false: onDone never runs).
function queueMail(mail, onDone, from)
    if type(mail) ~= "table" then return false, "mail is not a table" end
    if not configured() then return false, "MAIL.BREVO_API_KEY in v_mail/config.lua is not set" end
    local to = recipients(mail)
    if not to then return false, "invalid recipient" end
    if type(mail.subject) ~= "string" or mail.subject == "" then return false, "missing subject" end
    local text = type(mail.text) == "string" and mail.text ~= "" and mail.text or nil
    local html = type(mail.html) == "string" and mail.html ~= "" and mail.html or nil
    local stored = text   -- the text kept in the `mails` table
    if type(mail.template) == "table" then
        text, html = renderTemplate(mail.template)
        stored = text
        if mail.template.code then
            -- a code (password reset) must not be readable in the history
            local masked = {}
            for k, v in pairs(mail.template) do masked[k] = v end
            masked.code = "******"
            stored = renderTemplate(masked)
        end
    end
    if not text and not html then return false, "missing body" end
    stored = stored or html:gsub("<br>", "\n"):gsub("</p>", "\n\n"):gsub("<[^>]+>", "")
    if #urgent + #bulk >= MAIL.MAX_QUEUE then
        outputServerLog(("[v_mail] mail from %s dropped: queue full (%d)"):format(from or "v_mail", MAIL.MAX_QUEUE))
        return false, "queue full"
    end

    -- every mail gets a row in the `mails` table (server/store.lua) once Brevo answered;
    -- log.rowId = the row exists already (a pending update mail) and only gets the answer
    local log = type(mail.log) == "table" and mail.log or {}
    local done = type(onDone) == "function" and onDone or function() end
    local function answered(ok, info)
        if mail.log ~= false then
            if tonumber(log.rowId) then
                MAILDB.finish(tonumber(log.rowId), ok and "sent" or "failed", info)
            else
                MAILDB.record({
                    group = type(log.group) == "string" and log.group or nil,
                    kind = type(log.kind) == "string" and log.kind or (from or "v_mail"),
                    sender = type(log.sender) == "string" and log.sender or (from or "v_mail"),
                    account = type(log.account) == "string" and log.account or to[1].name,
                    language = type(log.language) == "string" and log.language or "",
                    subject = mail.subject,
                    body = stored,
                }, ok, info)
            end
        end
        done(ok, info)
    end

    local job = {
        from = from or "v_mail",
        logName = to[1].name or "?",   -- logs name the account, never the address
        onDone = answered,
        body = {
            sender = { name = type(mail.senderName) == "string" and mail.senderName ~= "" and mail.senderName or MAIL.SENDER_NAME,
                       email = MAIL.SENDER_EMAIL },
            to = to,
            subject = mail.subject,
            textContent = text,
            htmlContent = html,
            replyTo = validEmail(mail.replyTo) and { email = mail.replyTo } or nil,
        },
    }
    local list = mail.bulk == true and bulk or urgent
    list[#list + 1] = job
    if not isTimer(worker) then
        worker = setTimer(tick, MAIL.SEND_INTERVAL, 0)
        tick()
    end
    return true
end

function sendMail(mail, eventName, requestId)
    local caller = sourceResource
    local target = caller and getResourceRootElement(caller)
    return queueMail(mail, function(ok, info)
        if type(eventName) == "string" and isElement(target) then
            triggerEvent(eventName, target, requestId, ok, info)
        end
    end, caller and getResourceName(caller))
end

addEventHandler("onResourceStart", resourceRoot, function()
    if not configured() then
        outputServerLog("[v_mail] MAIL.BREVO_API_KEY in config.lua is not set: no email can be sent")
    end
end)
