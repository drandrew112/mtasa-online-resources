-- All creator keys go through one onClientKey handler while a session is open.

Keys = {}

local K = CREATOR.KEYS
local bound = false

local function onKey(key, press)
    if not press or not Editor.active then return end
    if inputBlocked() then return end

    if Editor.photo then
        if Photo.key(key) then cancelEvent() end
        return
    end
    if Editor.testing then
        if key == K.testStop then Test.stop() end
        return
    end

    if key == K.menu then
        if Menus.isOpen() then Menus.close() return end
        if Editor.doc then Menus.openHub() else Menus.openStart() end
        return
    end
    -- the open temp menu owns arrows / Enter / Backspace
    if Menus.isOpen() then return end

    if key == K.camera then
        if not Editor.doc then return end
        Freecam.toggle()
        return
    end
    if not Editor.doc then return end

    if getKeyState("lctrl") or getKeyState("rctrl") then
        if key == K.undo then Editor.undoStep() return end
        if key == K.redo then Editor.redoStep() return end
    end

    if Tools.current then
        if key == K.place then Tools.click() return end
        if key == K.confirm or key == "num_enter" then Tools.confirm() return end
        if key == K.cancel then Tools.cancel() return end
        if Tools.key(key) then cancelEvent() end
        return
    end

    if key == K.place and Editor.camMode == "free" and isCursorShowing() then
        local item = View.pick(Tools.screenPoint())
        if item then Menus.openItem(item) else Editor.selected = nil end
        return
    end
    if key == K.cancel then Editor.selected = nil return end
    if key == "delete" and Editor.selected then Ops.delete(Editor.selected) return end
end

function Keys.bind()
    if bound then return end
    bound = true
    addEventHandler("onClientKey", root, onKey)
end

function Keys.unbind()
    if not bound then return end
    bound = false
    removeEventHandler("onClientKey", root, onKey)
end

-- hover box under the cursor (freecam)
addEventHandler("onClientPreRender", root, function()
    if not Editor.active or not Editor.doc or Editor.camMode ~= "free" or Tools.current or not isCursorShowing() or Menus.isOpen() then
        View.hovered = nil
        return
    end
    View.hovered = View.pick(Tools.screenPoint())
end)
