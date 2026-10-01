-- Test module menu (ui_inac temp menu). Opened by the server after the admin check;
-- every selection is checked again on the server.

if not MEDIC_TEST.ENABLED then return end

addEvent("medic:testMenu", true)
addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuClose")

local menuId

local function buildItems()
    local scenarios = {}
    for i, scenario in ipairs(MEDIC_TEST.SCENARIOS) do
        scenarios[i] = { label = scenario.label, desc = scenario.desc, value = { scenario = scenario.id }, closeOnSelect = false }
    end

    local injuries = {}
    for _, injuryType in ipairs({ "gunshot", "fracture", "burn", "suffocation" }) do
        local def = MEDIC_INJURIES[injuryType]
        local severities = {}
        for severity = 1, 3 do
            severities[severity] = {
                label = MEDIC_SEVERITY[severity],
                desc = ("%s, %s"):format(def.label, MEDIC_SEVERITY[severity]:lower()),
                value = { injury = injuryType, severity = severity },
                closeOnSelect = false,
            }
        end
        injuries[#injuries + 1] = { label = def.label, title = def.label, desc = "Choose the severity", items = severities }
    end

    return {
        { label = "Scenarios", title = "Scenarios", desc = "Predefined emergency cases", items = scenarios },
        { label = "Single injury", title = "Single injury", desc = "One injury of a chosen severity", items = injuries },
        { label = "Remove my test peds", desc = "Destroys every ped you spawned", value = { clear = true }, closeOnSelect = false },
    }
end

addEventHandler("medic:testMenu", resourceRoot, function()
    local uiInac = getResourceFromName("ui_inac")
    if not uiInac or not getResourceRootElement(uiInac) then
        outputChatBox(("[MEDTEST] ui_inac is not running, use /%s list and /%s <scenario>")
            :format(MEDIC_TEST.COMMAND, MEDIC_TEST.COMMAND), 255, 90, 90)
        return
    end
    if exports.ui_inac:isTempMenuOpen() then return end
    menuId = exports.ui_inac:createTempMenu({ title = "Medical test", items = buildItems() })
end)

addEventHandler("ui_inac:tempMenuSelect", root, function(rootMenuId, value)
    if not menuId or rootMenuId ~= menuId or type(value) ~= "table" then return end
    if value.clear then
        triggerServerEvent("medic:testClear", resourceRoot)
    else
        triggerServerEvent("medic:testSpawn", resourceRoot, value)
    end
end)

addEventHandler("ui_inac:tempMenuClose", root, function(rootMenuId)
    if rootMenuId == menuId then menuId = nil end
end)
