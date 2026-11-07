MenuState = {
    open = false,
    current = "main",
    selected = 1,
    mouse = true,        -- false: no cursor, mouse ignored (createTempMenu{ mouse = false })
    mouseScroll = false, -- true: the row window stays put (the mouse moved the selection)
    firstRow = nil,      -- first shown row of a long list (render.lua)
}

function MenuState:getMenu()
    return MenuRegistry:get(self.current)
end

function MenuState:resetSelection()
    self.selected = 1
    self.mouseScroll = false
end
