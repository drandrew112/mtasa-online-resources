-- Builds what the open menu shows right now: the focused element's merged root list (every menu on
-- it, grouped) or the current submenu, cut to the current page. Used by both render and input, so
-- the number on screen and the number key always point at the same entry.

local function rootEntries(candidate)
    local entries = {}
    for _, cached in ipairs(candidate.menus) do
        local menu = Menus[cached.id]
        if menu then
            for i, item in ipairs(menu.def.items) do
                entries[#entries + 1] = { item = item, menu = menu, path = { i }, group = menu.def.title }
            end
        end
    end
    return entries, candidate.menus[1] and candidate.menus[1].def.title or "Interact"
end

local function submenuEntries(top)
    local menu = Menus[top.menuId]
    if not menu then return nil end
    local parent, blocked = ioResolvePath(menu.def.items, top.path)
    if not parent or not parent.items or blocked then return nil end

    local entries = {}
    for i, item in ipairs(parent.items) do
        local path = ioShallowCopy(top.path)
        path[#path + 1] = i
        entries[#entries + 1] = { item = item, menu = menu, path = path }
    end
    return entries, parent.title
end

function buildView()
    local candidate = getFocusCandidate()
    if not candidate then return nil end

    local entries, title
    local top = State.stack[#State.stack]
    if top then
        entries, title = submenuEntries(top)
        if not entries then
            -- the submenu vanished (menu updated/removed): fall back to the root list
            State.stack, State.page = {}, 1
            top = nil
        end
    end
    if not top then entries, title = rootEntries(candidate) end

    local perPage = IO.ITEMS_PER_PAGE
    local pages = math.max(1, math.ceil(#entries / perPage))
    if State.page > pages then State.page = pages end

    local visible = {}
    local first = (State.page - 1) * perPage
    for i = first + 1, math.min(#entries, first + perPage) do
        visible[#visible + 1] = entries[i]
    end

    return {
        title = title,
        entries = visible,
        page = State.page,
        pages = pages,
        depth = #State.stack,
        grouped = not top and #candidate.menus > 1,
    }
end
