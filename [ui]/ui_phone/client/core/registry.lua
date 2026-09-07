--[[
    ui_phone / client/core/registry.lua
    The app registry. Every file in client/apps/ calls PhoneApp.register{...}.

    App definition (all optional except id + name):

      id        unique string
      name      shown in the header bar
      icon      home-grid icon path (img/apps/<id>.png)
      order     home-grid sort key (lower = earlier); defaults to file load order

      open(self)            called when the app is entered. Return false to
                            refuse entry (e.g. Browser).
      close(self)           called when the app is left.

      items(self)           -> array of rows for the standard list. Row fields:
                               { title, subtitle, image, circle, swatch, right, ... }
                               items() may return different lists over time
                               (e.g. a sub-screen) - see client/apps/settings.lua
      empty                 text shown when items() is empty
      hint                  footer text, or a function returning it
      headerTitle(self)     -> string overriding the header bar text
      selectSound = false   suppress the default Enter "select" blip
      onSelect(self,row,i)  Enter pressed on a row

      render(self, screen)  extra drawing on top of the standard list
                            (screen = PhoneUI.SCREEN rect)
      key(self, key)        custom key handling; return true if consumed
                            (checked before the default list navigation)
      badge(self)           -> number shown as a red bubble on the home icon
]]

PhoneApp = {}

local byId, orderList = {}, {}
local autoOrder = 0

function PhoneApp.register(def)
    assert(type(def) == "table" and def.id and def.name, "PhoneApp.register: id + name required")
    assert(not byId[def.id], "PhoneApp.register: duplicate id " .. tostring(def.id))

    autoOrder = autoOrder + 10
    def.order = def.order or autoOrder
    def.icon  = def.icon or ("img/apps/" .. def.id .. ".png")

    byId[def.id] = def
    orderList[#orderList + 1] = def.id
    table.sort(orderList, function(a, b) return byId[a].order < byId[b].order end)
end

function PhoneApp.get(id)
    return byId[id]
end

function PhoneApp.list()
    local out = {}
    for _, id in ipairs(orderList) do out[#out + 1] = byId[id] end
    return out
end
