-- Reusable modal text-input overlay.
--
-- Other resources open it through the exports below and get the result back as
-- an event (MTA cannot pass functions across a resource boundary):
--
--   local token = exports.ui_core:openTextInput("License plate", 8, "OLD PLATE")
--   addEvent("ui_core:textInputResult")
--   addEventHandler("ui_core:textInputResult", root, function(t, text)
--       if t ~= token then return end
--       -- text == false  -> cancelled
--   end)
--
-- While it is open a focused guiCreateEdit holds the keyboard with
-- guiSetInputMode("no_binds_when_editing"), so every bindKey handler on the
-- client (interaction menu, phone, pause, ...) is dead until it closes.
-- "textInputOpen" element data is also set for panels that gate on flags.

UI.textInput = {
    active   = false,
    title    = "",
    token    = nil,
    edit     = nil,
    maxLen   = 32,
}

addEvent("ui_core:textInputResult")

local function finish(text)
    local ti = UI.textInput
    if not ti.active then return end

    local token = ti.token

    if isElement(ti.edit) then destroyElement(ti.edit) end
    ti.edit   = nil
    ti.active = false
    ti.token  = nil

    guiSetInputMode("allow_binds")
    showCursor(false)
    setElementData(localPlayer, "textInputOpen", false)

    triggerEvent("ui_core:textInputResult", root, token, text ~= nil and text or false)
end

-- Enter inside the edit -> confirm.
addEventHandler("onClientGUIAccepted", guiRoot, function(element)
    if UI.textInput.active and element == UI.textInput.edit then
        finish(guiGetText(element))
    end
end)

-- Escape -> cancel. (onClientKey still fires while an edit holds the keyboard.)
addEventHandler("onClientKey", root, function(button, press)
    if not UI.textInput.active or not press then return end
    if button == "escape" then
        finish(false)
    elseif button == "enter" or button == "num_enter" then
        local edit = UI.textInput.edit
        finish(isElement(edit) and guiGetText(edit) or "")
    end
end)

-- exports.ui_core:openTextInput(title, maxLength, defaultText)
--   -> token (string) on success, false if one is already open
function openTextInput(title, maxLength, defaultText)
    local ti = UI.textInput
    if ti.active then return false end

    ti.maxLen = tonumber(maxLength) or 32
    ti.title  = tostring(title or "")
    ti.token  = "ti_" .. tostring(getTickCount()) .. "_" .. tostring(math.random(1000, 9999))
    ti.active = true

    local w, h = ui(420), ui(34)
    local x = (UI.sw - w) / 2
    local y = (UI.sh - h) / 2

    ti.edit = guiCreateEdit(x, y, w, h, tostring(defaultText or ""), false)
    guiEditSetMaxLength(ti.edit, ti.maxLen)
    guiBringToFront(ti.edit)
    guiEditSetCaretIndex(ti.edit, ti.maxLen)
    guiSetInputMode("no_binds_when_editing")
    setElementData(localPlayer, "textInputOpen", true)
    showCursor(true)

    return ti.token
end

-- exports.ui_core:closeTextInput()  - cancels (fires the result event with false)
function closeTextInput()
    if not UI.textInput.active then return false end
    finish(false)
    return true
end

-- exports.ui_core:isTextInputOpen()
function isTextInputOpen()
    return UI.textInput.active == true
end

function UI.textInput:draw()
    if not self.active then return end

    local w, h = ui(420), ui(34)
    local x = (UI.sw - w) / 2
    local y = (UI.sh - h) / 2

    -- dim the screen behind the field
    dxDrawRectangle(0, 0, UI.sw, UI.sh, tocolor(0, 0, 0, 140))

    -- title bar above the edit
    dxDrawRectangle(x, y - ui(30), w, ui(28), tocolor(0, 0, 0, 220))
    dxDrawText(self.title, x + ui(12), y - ui(30), x + w - ui(12), y - ui(2),
        tocolor(0, 170, 220, 255), ui(1.5), "default-bold", "left", "center")

    -- hint under the edit
    dxDrawRectangle(x, y + h + ui(2), w, ui(24), tocolor(20, 20, 20, 200))
    dxDrawText("Enter - confirm     Esc - cancel     (max " .. self.maxLen .. ")",
        x + ui(12), y + h + ui(2), x + w - ui(12), y + h + ui(26),
        tocolor(200, 200, 200, 255), ui(1.1), "default", "left", "center")
end

addEventHandler("onClientResourceStop", resourceRoot, function()
    if UI.textInput.active then finish(false) end
end)
