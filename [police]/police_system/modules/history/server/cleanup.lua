-- police_system / modules/history/server/cleanup.lua
-- Generated NPC data piles up (every queried / scanned ped and traffic car gets a row). NPC citizens and NPC vehicles
-- older than POLICE.HISTORY.NPC_KEEP (by created_at / last_seen) are deleted with their generated past (records /
-- warrants made by "SAPD Records", officer / issued_by empty). Kept: everything that has a player's note on it - a
-- record issued by an officer, a warrant issued / edited by one, a report naming it as a subject - and the rows of
-- peds / vehicles that are in the world on this instance right now (pol.cid / pol.vid). Player rows are never
-- touched. Runs a while after the start, then every NPC_CLEAN_EVERY ms, in batches of NPC_CLEAN_BATCH.

local H = POL.history
local C = POLICE.HISTORY

local function liveIds(key)
    local out = {}
    for _, t in ipairs({ "ped", "vehicle" }) do
        for _, el in ipairs(getElementsByType(t)) do
            local id = tonumber(getElementData(el, key))
            if id then out[id] = true end
        end
    end
    return out
end

local function idList(rows, live)
    local ids = {}
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        local id = tonumber(r.id)
        if id and not live[id] then ids[#ids + 1] = id end
    end
    return ids
end

local function inList(ids) return "(" .. table.concat(ids, ",") .. ")" end

local function cleanCitizens(cutoff, cb)
    POL.db.query(function(rows)
        local ids = idList(rows, liveIds("pol.cid"))
        if #ids == 0 then return cb(0) end
        local list = inList(ids)
        POL.db.exec("DELETE FROM pol_records WHERE citizen_id IN " .. list .. " AND is_pool = 0")
        POL.db.exec("DELETE FROM pol_warrants WHERE citizen_id IN " .. list .. " AND is_pool = 0")
        POL.db.exec("DELETE FROM pol_citizens WHERE id IN " .. list .. " AND kind = 'npc' AND is_pool = 0")
        for _, id in ipairs(ids) do POL.records.citizens[id] = nil end
        cb(#ids)
    end, [[SELECT c.id FROM pol_citizens c
        WHERE c.kind = 'npc' AND c.is_pool = 0 AND GREATEST(c.created_at, c.last_seen) < ?
          AND NOT EXISTS (SELECT 1 FROM pol_records r WHERE r.citizen_id = c.id AND r.is_pool = 0 AND COALESCE(r.officer, '') <> '')
          AND NOT EXISTS (SELECT 1 FROM pol_warrants w WHERE w.citizen_id = c.id AND w.is_pool = 0
                          AND (COALESCE(w.issued_by, '') <> '' OR COALESCE(w.updated_by, '') <> ''))
          AND NOT EXISTS (SELECT 1 FROM pol_reports p WHERE p.is_pool = 0 AND p.subjects LIKE CONCAT('%"c', c.id, '"%'))
        LIMIT ]] .. C.NPC_CLEAN_BATCH, cutoff)
end

local function cleanVehicles(cutoff, cb)
    POL.db.query(function(rows)
        local ids = idList(rows, liveIds("pol.vid"))
        if #ids == 0 then return cb(0) end
        local list = inList(ids)
        POL.db.exec("DELETE FROM pol_records WHERE vehicle_id IN " .. list .. " AND is_pool = 0")
        POL.db.exec("DELETE FROM pol_vehicles WHERE id IN " .. list .. " AND kind = 'npc' AND is_pool = 0")
        for _, id in ipairs(ids) do POL.records.vehicles[id] = nil end
        cb(#ids)
    end, [[SELECT v.id FROM pol_vehicles v
        WHERE v.kind = 'npc' AND v.is_pool = 0 AND v.created_at < ?
          AND NOT EXISTS (SELECT 1 FROM pol_records r WHERE r.vehicle_id = v.id AND r.is_pool = 0 AND COALESCE(r.officer, '') <> '')
          AND NOT EXISTS (SELECT 1 FROM pol_reports p WHERE p.is_pool = 0 AND p.subjects LIKE CONCAT('%"v', v.id, '"%'))
        LIMIT ]] .. C.NPC_CLEAN_BATCH, cutoff)
end

-- one round; a full batch goes on with the next one a little later
function H.cleanup()
    local cutoff = POL.now() - C.NPC_KEEP
    cleanVehicles(cutoff, function(nv)
        cleanCitizens(cutoff, function(nc)
            if nv + nc > 0 then
                outputDebugString(("[police_system] NPC cleanup: %d citizens, %d vehicles deleted"):format(nc, nv), 3)
            end
            if nv >= C.NPC_CLEAN_BATCH or nc >= C.NPC_CLEAN_BATCH then setTimer(H.cleanup, 5000, 1) end
        end)
    end)
end

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(H.cleanup, 60000, 1)
    setTimer(H.cleanup, C.NPC_CLEAN_EVERY, 0)
end)
