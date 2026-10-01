-- Keys: Q/E switch between nearby menus, X opens/closes, 1-9 pick an option, 0 turns the page,
-- Backspace goes up a submenu level or closes.

function playUISound(name)
    if not IO.SOUNDS then return end
    local sound = playSound("assets/sounds/" .. name .. ".wav")
    if sound then setSoundVolume(sound, 0.5) end
end

local function keysUsable()
    return not (isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() or isCursorShowing())
end

local function selectEntry(index)
    local view = buildView()
    local entry = view and view.entries[index]
    if not entry then return end
    local item = entry.item

    if item.disabled then
        playUISound("btnfail")
        return
    end

    if item.items then
        State.stack[#State.stack + 1] = { menuId = entry.menu.id, path = entry.path }
        State.page = 1
        playUISound("click")
        return
    end

    local target = State.focus
    if entry.menu.remote then
        triggerServerEvent("io:select", resourceRoot, entry.menu.id, entry.path, target)
    else
        triggerEvent("onClientInteractMenuSelect", localPlayer, entry.menu.id, item.value, target, entry.path)
    end
    playUISound("select")
    if item.closeOnSelect then closeMenu() end
end

local function onCycle(direction)
    if not keysUsable() then return end
    if cycleFocus(direction) then playUISound("click") end
end

local function onOpen()
    if not keysUsable() then return end
    if State.open then
        closeMenu()
        playUISound("click")
    elseif getFocusCandidate() then
        openMenu()
        playUISound("click")
    end
end

local function onBack()
    if not State.open or not keysUsable() then return end
    if #State.stack > 0 then
        State.stack[#State.stack] = nil
        State.page = 1
    else
        closeMenu()
    end
    playUISound("click")
end

local function onPage()
    if not State.open or not keysUsable() then return end
    local view = buildView()
    if not view or view.pages < 2 then return end
    State.page = State.page % view.pages + 1
    playUISound("click")
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey(IO.KEY_PREV, "down", function() onCycle(-1) end)
    bindKey(IO.KEY_NEXT, "down", function() onCycle(1) end)
    bindKey(IO.KEY_OPEN, "down", onOpen)
    bindKey(IO.KEY_BACK, "down", onBack)
    bindKey(IO.KEY_PAGE, "down", onPage)
    bindKey("num_0", "down", onPage)
    for i = 1, IO.ITEMS_PER_PAGE do
        local function pick()
            if State.open and keysUsable() then selectEntry(i) end
        end
        bindKey(tostring(i), "down", pick)
        bindKey("num_" .. i, "down", pick)
    end
end)
