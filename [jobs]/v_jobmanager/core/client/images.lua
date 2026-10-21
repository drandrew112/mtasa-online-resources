-- Community game thumbnails (see core/community.lua). Their `image` path points
-- into this resource's client folder ("community_img/<id>_<version>.jpg"); the
-- file is fetched from the server the first time a job list / lobby mentions it.
-- Every consumer already falls back to the default image while it is missing.

local pending = {}

local function ensureImage(path)
    if type(path) ~= "string" or not path:find("^community_img/") then return end
    if pending[path] or fileExists(path) then return end
    pending[path] = true
    triggerServerEvent("jobmanager:requestImage", resourceRoot, path)
end

local function scan(list)
    if type(list) ~= "table" then return end
    if list.image then ensureImage(list.image) end
    for _, entry in ipairs(list) do
        if type(entry) == "table" then ensureImage(entry.image) end
    end
end

for _, eventName in ipairs({ "jobmanager:jobs", "jobmanager:lobbies", "jobmanager:lobby" }) do
    addEvent(eventName, true)
    addEventHandler(eventName, resourceRoot, scan)
end

addEvent("jobmanager:image", true)
addEventHandler("jobmanager:image", resourceRoot, function(path, data)
    if type(path) ~= "string" or not path:find("^community_img/[%w_]+_%d+%.jpg$") or type(data) ~= "string" then return end
    pending[path] = nil
    -- older versions of the same game are dropped
    local prefix = path:match("^(community_img/[%w_]+_)%d+%.jpg$")
    for version = 1, tonumber(path:match("_(%d+)%.jpg$")) - 1 do
        local old = prefix .. version .. ".jpg"
        if fileExists(old) then fileDelete(old) end
    end
    local file = fileCreate(path)
    if not file then return end
    fileWrite(file, data)
    fileClose(file)
end)
