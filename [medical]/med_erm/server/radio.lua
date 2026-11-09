if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Radio messages: fixed name ids that do exactly what the tablet buttons do (Active Case >
-- Request Backup / Request Agency). The voice radio (v_voiceclient_connector) sends them through
-- the radioCommand export; the result is the same as if the player pressed the button, the error
-- also appears on the tablet the same way.
--
--   radioCommand(player, id, args) -> true | false, errorText (in the player's language), errorCode
--   getRadioCodes()                -> { { id, category, label, args }, ... }
--
-- args: { note = "..." } for AGENCY_POLICE_OTHER (the free text the tablet asks for).

Radio = {}

-- id -> { category, label (v_locals key), run(u, player, args) }
Radio.CODES = {}
Radio.ORDER = {}

local function add(id, category, label, run, argSpec)
    Radio.CODES[id] = { id = id, category = category, label = label, run = run, args = argSpec }
    Radio.ORDER[#Radio.ORDER + 1] = id
end

-- backup: one per Config.BACKUP_OPTIONS entry (AMB -> BACKUP_AMBULANCE, others BACKUP_<id>)
for _, opt in ipairs(Config.BACKUP_OPTIONS) do
    local id = opt.id == "AMB" and "BACKUP_AMBULANCE" or ("BACKUP_" .. opt.id)
    local optionId = opt.id
    add(id, "backup", opt.label, function(u) return Backup.request(u, optionId) end)
end

-- request agency (police) with each reason of Config.AGENCY_REASONS
for _, r in ipairs(Config.AGENCY_REASONS) do
    local reasonId = r.id
    add("AGENCY_POLICE_" .. r.id:upper(), "agency", r.label, function(u, _, args)
        return Agency.request(u, "pd", reasonId, args.note or "")
    end, r.note and { note = "required" } or nil)
end

-- -> true | false, errorText, errorCode
function Radio.handle(player, id, args)
    if not isElement(player) or getElementType(player) ~= "player" then return false, "bad player", "bad_player" end
    local def = type(id) == "string" and Radio.CODES[id]
    if not def then return false, L.forPlayer(player, "med_erm.radio.unknown_code"), "unknown_code" end
    args = type(args) == "table" and args or {}
    local u = Units.ofPlayer(player)
    if not u then
        local err = L.forPlayer(player, "med_erm.tablet.you_are_not_signed_in")
        triggerClientEvent(player, "erm:notify", resourceRoot, L.msg("med_erm.case.ems_tablet"), err)
        return false, err, "not_in_unit"
    end
    local ok, err = def.run(u, player, args)
    if ok then
        Events.fire("onErmRadioCommand", player, id, u.id)
        return true
    end
    -- same feedback as a tablet button (server/tablet.lua reply)
    if err then triggerClientEvent(player, "erm:notify", resourceRoot, L.msg("med_erm.case.ems_tablet"), err) end
    local text = err and L.resolveFor(player, err) or L.forPlayer(player, "med_erm.radio.failed")
    return false, tostring(text), "failed"
end

---------------------------------------------------------------- exports

function radioCommand(player, id, args)
    return Radio.handle(player, id, args)
end

function getRadioCodes()
    local list = {}
    for _, id in ipairs(Radio.ORDER) do
        local d = Radio.CODES[id]
        list[#list + 1] = { id = id, category = d.category, label = d.label, args = d.args }
    end
    return list
end
