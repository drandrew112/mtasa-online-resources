if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Work multipliers (money / XP per work). Runtime only, never persisted: v_weekly sets them for
-- the running week (it clears and sets them again on every week change / restart), so other
-- resources should change them through v_weekly, not directly.
--
-- payWork() adds an extra receipt item for the money multiplier (total * (money - 1)), only
-- when the total is positive; giveWorkXp() multiplies the XP.

local multipliers = {}             -- workId -> { money, xp, label|nil }

-- setWorkMultiplier(workId, money, xp [, label]) -> true | false
-- money / xp default to 1; both 1 removes the entry. label: optional receipt item text.
function setWorkMultiplier(workId, money, xp, label)
    if type(workId) ~= "string" or workId == "" then return false end
    money, xp = tonumber(money) or 1, tonumber(xp) or 1
    if money < 0 or xp < 0 then return false end
    if money == 1 and xp == 1 then
        multipliers[workId] = nil
    else
        multipliers[workId] = { money = money, xp = xp,
            label = type(label) == "string" and label ~= "" and label or nil }
    end
    return true
end

-- -> money, xp, label|false
function getWorkMultiplier(workId)
    local m = multipliers[workId]
    if not m then return 1, 1, false end
    return m.money, m.xp, m.label or false
end

-- -> { [workId] = { money, xp, label } }
function getWorkMultipliers()
    local copy = {}
    for id, m in pairs(multipliers) do copy[id] = { money = m.money, xp = m.xp, label = m.label } end
    return copy
end

function clearWorkMultiplier(workId)
    multipliers[workId] = nil
    return true
end

function clearWorkMultipliers()
    multipliers = {}
    return true
end

-- "2x", "1.5x"
function formatMultiplier(n)
    return ("%sx"):format((("%.2f"):format(n):gsub("0+$", ""):gsub("%.$", "")))
end

-- The receipt item of the money multiplier for a payment total, or nil.
function workMultiplierItem(workId, total)
    local m = multipliers[workId]
    if not m or m.money == 1 or total <= 0 then return nil end
    local amount = math.floor(total * (m.money - 1) + 0.5)
    if amount == 0 then return nil end
    local mult = formatMultiplier(m.money)
    return {
        label = m.label and (m.label .. " (" .. mult .. ")") or L.msg("work_core.payment.weekly_bonus", { mult = mult }),
        amount = amount,
    }
end
