MenuRegistry = {
    menus = {}
}

function MenuRegistry:register(menu)
    assert(menu.id, "Menu must have id")
    self.menus[menu.id] = menu
end

function MenuRegistry:get(id)
    return self.menus[id]
end
