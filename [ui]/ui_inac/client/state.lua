MenuState = {
    open = false,
    current = "main",
    selected = 1
}

function MenuState:getMenu()
    return MenuRegistry:get(self.current)
end

function MenuState:resetSelection()
    self.selected = 1
end
