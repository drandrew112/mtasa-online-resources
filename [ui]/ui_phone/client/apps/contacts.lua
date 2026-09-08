--[[
    ui_phone / client/apps/contacts.lua
    Contact list. Enter "calls" a contact: 2s of ringing, then a menu of the
    things that contact can do. The server performs and pays for the action.

    A contact with `dynamic = "<channel>"` (config) has no fixed action list:
    when called, the client asks the server (`contacts:dynPull`) and the reply
    (`contacts:dyn`) fills the menu. If that list comes back empty the call is
    never answered - it rings out and drops back to the contact list.
]]

local u = PhoneUI.u
local WHITE = PhoneShader.WHITE

local call = nil   -- { key, phase = "ring"|"menu", start, sel }

-- dynamicRows[contactKey]: nil = not fetched yet, table (maybe empty) = known.
local dynamicRows = {}

local WAIT_EXTRA_MS = 3000   -- keep ringing at most this long past callRingMs
                             -- while still waiting for a dynamic reply

local function contactIsDynamic(key)
    local c = PHONE_CONFIG.contactByKey(key)
    return c and c.dynamic or nil
end

local function actionsFor(key)
    local c = PHONE_CONFIG.contactByKey(key)
    if not c then return {} end
    if c.dynamic then return dynamicRows[key] or {} end
    return c.actions or {}
end

local function endCall()
    call = nil
    PhoneSound.ringStop()
end

local function answerCall()
    call.phase, call.sel = "menu", 1
    PhoneSound.ringStop()
end

phoneOnServer("contacts:dyn", function(contactKey, rows)
    dynamicRows[contactKey] = type(rows) == "table" and rows or {}
    if call and call.key == contactKey then
        local n = #dynamicRows[contactKey]
        if call.phase == "menu" and n == 0 then
            endCall()                       -- claimed the last one -> hang up
        else
            call.sel = math.max(1, math.min(call.sel, math.max(1, n)))
        end
    end
end)

PhoneApp.register({
    id    = "contacts",
    name  = "Contacts",
    order = 30,

    open  = function() endCall() end,
    close = function() endCall() end,

    items = function()
        local rows = {}
        for _, c in ipairs(PHONE_CONFIG.contacts) do
            rows[#rows + 1] = { title = c.name, image = c.photo, circle = true, _key = c.key }
        end
        return rows
    end,
    hint = "[Enter] call",

    -- Pressing Enter on a contact should only start the ring, no select blip.
    selectSound = false,

    onSelect = function(_, row)
        call = { key = row._key, phase = "ring", start = getTickCount(), sel = 1 }
        local channel = contactIsDynamic(row._key)
        if channel then
            dynamicRows[row._key] = nil          -- forget the old list, re-ask
            phoneRPC("contacts:dynPull", row._key)
        end
        PhoneSound.ringStart()
    end,

    -- Intercept keys only while a call is on screen.
    key = function(_, key)
        if not call then return false end

        if key == "backspace" then
            endCall()
            PhoneSound.select()
            return true
        end

        if call.phase == "menu" then
            local n = #actionsFor(call.key)
            if key == "arrow_u" then
                call.sel = call.sel > 1 and call.sel - 1 or n
                PhoneSound.click()
            elseif key == "arrow_d" then
                call.sel = call.sel < n and call.sel + 1 or 1
                PhoneSound.click()
            elseif key == "enter" then
                local a = actionsFor(call.key)[call.sel]
                if a then
                    PhoneSound.select()
                    phoneRPC("contacts:action", call.key, a.key)
                end
            end
        end
        return true   -- swallow every nav key while calling
    end,

    render = function(_, scr)
        if not call then return end
        local contact = PHONE_CONFIG.contactByKey(call.key)
        if not contact then endCall() return end

        PhoneUI.rounded("call_bg", scr.x, scr.y, scr.w, scr.h, u(4), WHITE, 0, 0, 0, 185)

        -- Ring -> menu (or ring -> hang up for a dynamic contact with no rows).
        if call.phase == "ring" and getTickCount() - call.start >= PHONE_CONFIG.callRingMs then
            if contact.dynamic then
                local rows = dynamicRows[call.key]
                if rows == nil then
                    if getTickCount() - call.start >= PHONE_CONFIG.callRingMs + WAIT_EXTRA_MS then
                        endCall()
                    end
                elseif #rows == 0 then
                    endCall()                       -- nobody picks up
                else
                    answerCall()
                end
            else
                answerCall()
            end
            if not call then return end
        end

        local photo = u(96)
        local px = scr.x + scr.w / 2 - photo / 2
        local py = scr.y + u(28)
        PhoneUI.rounded("call_photo", px, py, photo, photo, photo * 0.5, contact.photo, 255, 255, 255, 255)
        PhoneUI.text(contact.name, scr.x, py + photo + u(10), scr.w, u(24),
            PhoneUI.C.white, u(1.4), "default-bold", "center", "top")

        if call.phase == "ring" then
            local dots = ("."):rep(1 + math.floor((getTickCount() - call.start) / 400) % 3)
            PhoneUI.text("Calling" .. dots, scr.x, py + photo + u(38), scr.w, u(20),
                PhoneUI.C.dim, u(1.0), "default", "center", "top")
            PhoneUI.text("[Backspace] cancel", scr.x, scr.y + scr.h - u(22), scr.w, u(18),
                PhoneUI.C.faint, u(0.85), "default", "center", "top")
            return
        end

        local actions = actionsFor(call.key)
        local top = py + photo + u(48)
        local rowH = PhoneUI.rowH
        local x, w = scr.x + u(16), scr.w - u(32)
        for i, a in ipairs(actions) do
            local y = top + (i - 1) * rowH
            if call.sel == i then PhoneUI.selection("call_row_" .. i, x, y, w, rowH - u(6)) end
            PhoneUI.text(a.label, x + u(14), y, w - u(24), rowH - u(6),
                PhoneUI.C.white, u(1.05), "default-bold", "left", "center")
        end
        PhoneUI.text("[Backspace] back", scr.x, scr.y + scr.h - u(22), scr.w, u(18),
            PhoneUI.C.faint, u(0.85), "default", "center", "top")
    end,
})
