if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Client exports. Topics / categories added by another resource are removed
-- when that resource stops.
--
--   openHelp([topicId])        -> bool   opens the panel (on that page)
--   closeHelp() / toggleHelp() -> bool
--   isHelpOpen()               -> bool
--   addHelpCategory(id, { title, order })                                  -> bool
--   addHelpTopic(id, { category, order, title, text | file, keywords, related, hidden }) -> bool
--       title / text / keywords: string, { en = "...", hu = "..." } or a v_locals message
--       file: path under content/<lang>/ of ui_help (text from another resource goes in `text`)
--   removeHelpTopic(id) / removeHelpCategory(id) -> bool
--   getHelpTopics() -> { { id, category, title, hidden }, ... }
--
-- event "ui_help:onClientHelpToggle" (open)  source = localPlayer

local function owner()
    local res = sourceResource
    if res and res ~= getThisResource() then return res end
    return nil
end

function openHelp(topicId)
    return HelpPanel_open(type(topicId) == "string" and topicId or nil)
end

function closeHelp()
    return HelpPanel_close()
end

function toggleHelp()
    return HelpPanel_toggle()
end

function isHelpOpen()
    return HelpPanel_isOpen()
end

function addHelpCategory(id, def)
    return Help.addCategory(id, def, owner())
end

function removeHelpCategory(id)
    return Help.removeCategory(id)
end

function addHelpTopic(id, def)
    return Help.addTopic(id, def, owner())
end

function removeHelpTopic(id)
    return Help.removeTopic(id)
end

function getHelpTopics()
    local out = {}
    for id, t in pairs(Help.topics) do
        out[#out + 1] = { id = id, category = t.category, title = Help.topicData(t).title, hidden = t.hidden }
    end
    return out
end

addEvent("ui_help:open", true)
addEventHandler("ui_help:open", resourceRoot, function(topicId)
    openHelp(topicId)
end)

addEventHandler("onClientResourceStop", root, function(res)
    if res ~= getThisResource() then Help.removeOwned(res) end
end)
