-- v_modloader (client): asks the server which mods exist and replaces the models in time slices.
-- Every mod is loaded inside pcall; a broken file is skipped and reported, never blocks the rest.

local loading = false

local function loadMod(category, id, codes, errors)
    local base = category .. "/" .. id
    local steps = {
        { "t", ".txd", engineLoadTXD, engineImportTXD },
        { "d", ".dff", engineLoadDFF, engineReplaceModel },
        { "c", ".col", engineLoadCOL, engineReplaceCOL },
    }
    local ok = true
    for _, step in ipairs(steps) do
        if codes:find(step[1], 1, true) then
            local path = base .. step[2]
            local element
            if not fileExists(path) then
                errors[#errors + 1] = path .. ": file was not downloaded"
                ok = false
            else
                local loaded, result = pcall(step[3], path)
                element = loaded and result or nil
                if not element then
                    errors[#errors + 1] = path .. ": cannot be loaded" .. (loaded and "" or (" (" .. tostring(result) .. ")"))
                    ok = false
                else
                    local applied, success = pcall(step[4], element, id)
                    if not applied or not success then
                        errors[#errors + 1] = path .. ": cannot be applied to model " .. id
                        pcall(destroyElement, element)
                        ok = false
                    end
                end
            end
        end
    end
    return ok
end

addEvent("modloader:mods", true)
addEventHandler("modloader:mods", resourceRoot, function(list)
    if loading or type(list) ~= "table" then return end
    loading = true

    local queue = {}
    for _, cat in ipairs(MODLOADER.categories) do
        local ids = {}
        for id in pairs(list[cat.name] or {}) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do queue[#queue + 1] = { cat.name, id, list[cat.name][id] } end
    end

    local index, okCount, errors = 1, 0, {}

    local function slice()
        local started = getTickCount()
        while index <= #queue and getTickCount() - started < MODLOADER.SLICE_MS do
            local item = queue[index]
            index = index + 1
            local called, result = pcall(loadMod, item[1], item[2], item[3], errors)
            if not called then
                errors[#errors + 1] = ("%s/%s: unexpected error (%s)"):format(item[1], item[2], tostring(result))
            elseif result then
                okCount = okCount + 1
            end
        end

        if index <= #queue then
            setTimer(slice, MODLOADER.SLICE_PAUSE, 1)
            return
        end

        outputDebugString(("[modloader] %d/%d mod(s) loaded, %d error(s)"):format(okCount, #queue, #errors), 3)
        for _, line in ipairs(errors) do outputDebugString("[modloader] " .. line, 1) end
        if #errors > 0 then triggerServerEvent("modloader:report", resourceRoot, errors) end
        loading = false
    end

    slice()
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("modloader:request", resourceRoot)
end)
