if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- shader_colors / c_api.lua
--
-- Exports. Persistence is owned by ui_pause (gfx_colorpreset / gfx_colorintensity);
-- this resource only holds the live values.
--
-- Overrides let other resources temporarily bend the image (e.g. blood loss
-- desaturation) on top of the player's preset:
--   pushColorOverride("bloodloss", { saturation = 0.3, contrast = 0.4 }, 10, 1500)
--   removeColorOverride("bloodloss", 3000)
-- Only the given keys are touched; higher priority is applied last (wins).
-- Overrides of a stopped resource are removed automatically.

local orderCounter = 0

local function sanitize(params)
    local out = {}
    for k, v in pairs(NEUTRAL) do
        local src = params[k]
        if type(v) == "table" then
            if type(src) == "table" then
                out[k] = { tonumber(src[1]), tonumber(src[2]), tonumber(src[3]) }
            end
        elseif tonumber(src) then
            out[k] = tonumber(src)
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- status / settings
--------------------------------------------------------------------------------

function isColorGradingSupported()
    return Status ~= "unsupported" and Status ~= "lowmem"
end

-- "active" | "idle" | "unsupported" | "lowmem"
function getColorGradingStatus()
    return Status
end

function getColorPresets()
    local list = {}
    for i, p in ipairs(PRESETS) do
        list[i] = { id = p.id, label = p.label }
    end
    return list
end

function getColorPreset()
    return Settings.preset
end

function setColorPreset(id)
    if not PRESET_BY_ID[id] then return false end
    retryAvailability()
    if id ~= Settings.preset then
        beginFade()
        Settings.preset = id
    end
    refresh()
    return true
end

function getColorIntensity()
    return Settings.intensity
end

function setColorIntensity(value)
    value = tonumber(value)
    if not value then return false end
    value = math.max(0, math.min(100, math.floor(value + 0.5)))
    retryAvailability()
    if value ~= Settings.intensity then
        beginFade(PRESET_FADE_MS / 2)
        Settings.intensity = value
    end
    refresh()
    return true
end

--------------------------------------------------------------------------------
-- overrides
--------------------------------------------------------------------------------

function pushColorOverride(id, params, priority, fadeMs)
    if type(id) ~= "string" or type(params) ~= "table" then return false end
    local o = Overrides[id]
    if o then
        if o.weight >= 1 then beginFade(fadeMs) end
        o.params = sanitize(params)
        o.priority = tonumber(priority) or o.priority
        rebuildOverrideOrder()
        startOverrideFade(o, 1, fadeMs)
    else
        orderCounter = orderCounter + 1
        o = {
            params = sanitize(params), priority = tonumber(priority) or 0,
            order = orderCounter, resource = sourceResource, weight = 0,
        }
        Overrides[id] = o
        rebuildOverrideOrder()
        startOverrideFade(o, 1, fadeMs)
    end
    refresh()
    return true
end

function removeColorOverride(id, fadeMs)
    local o = Overrides[id]
    if not o then return false end
    startOverrideFade(o, 0, fadeMs)
    refresh()
    return true
end

function hasColorOverride(id)
    return Overrides[id] ~= nil and Overrides[id].to == 1
end

addEventHandler("onClientResourceStop", root, function(res)
    if res == resource then return end
    for id, o in pairs(Overrides) do
        if o.resource == res then
            removeColorOverride(id, 300)
        end
    end
end)

--------------------------------------------------------------------------------
-- /colorgrade [split | info | <preset> | <0-100>]  (testing, not saved)
--------------------------------------------------------------------------------

addCommandHandler("colorgrade", function(_, arg)
    local prefix = L("shader_colors.api.color_grading")
    if arg == "split" then
        setSplit(not Split)
        outputChatBox(L("shader_colors.api.split_view", { prefix = prefix, split = (Split and L("shader_colors.api.be") or L("shader_colors.api.ki")) }), 255, 255, 255, true)
    elseif arg and PRESET_BY_ID[arg] then
        setColorPreset(arg)
        outputChatBox(L("shader_colors.api.preset_not_saved", { prefix = prefix, arg = arg }), 255, 255, 255, true)
    elseif tonumber(arg) then
        setColorIntensity(arg)
        outputChatBox(L("shader_colors.api.intensity_not_saved", { prefix = prefix, intensity = Settings.intensity }), 255, 255, 255, true)
    elseif arg == "info" or not arg then
        local n = 0
        for _ in pairs(Overrides) do n = n + 1 end
        outputChatBox(prefix .. L("shader_colors.api.status_preset_intensity_technique_night_override", { status = Status, preset = Settings.preset, intensity = Settings.intensity, technique = tostring(Technique), night_weight = NightWeight, n = n }), 255, 255, 255, true)
        outputChatBox(L("shader_colors.api.usage_colorgrade_split_info_off_natural", { prefix = prefix }), 255, 255, 255, true)
    else
        outputChatBox(L("shader_colors.api.unknown_parameter", { prefix = prefix, arg = tostring(arg) }), 255, 255, 255, true)
    end
end)
