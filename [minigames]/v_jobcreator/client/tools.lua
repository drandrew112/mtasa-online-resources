-- Placing (ghost follows the surface under the cursor / crosshair) and moving
-- (pick up and drop, then fine-tune with keys), plus the item operations the
-- menus call.

Tools = { current = nil }

local L = CREATOR.LIMITS
local M = CREATOR.MOVE
local sw, sh = guiGetScreenSize()

function Tools.screenPoint()
    if Editor.camMode == "free" and isCursorShowing() then
        local cx, cy = getCursorPosition()
        if cx then return cx * sw, cy * sh end
    end
    return sw / 2, sh / 2
end

local function stepMul()
    if getKeyState("lshift") then return M.fastMul end
    if getKeyState("lalt") then return M.slowMul end
    return 1
end

local function restoreRef(ref, orig)
    for k in pairs(ref) do ref[k] = nil end
    for k, v in pairs(orig) do ref[k] = v end
end

local function applyItem(item)
    Kinds[item.kind].apply(item.element, item.ref, item.extra)
end

--------------------------------------------------------------------------------
-- placing
--------------------------------------------------------------------------------

local function listFor(kind)
    local doc = Editor.doc
    if kind == "object" then return doc.objects, L.objects end
    if kind == "spawn" then return Editor.spawnList(), L.spawnpoints end
    if kind == "checkpoint" then return doc.race.checkpoints, L.checkpoints end
end

local function createGhost(kind, model)
    local el
    if kind == "object" then
        el = createObject(model, 0, 0, -50)
    elseif kind == "spawn" then
        if Editor.doc.type == "race" then
            el = createVehicle(Editor.doc.race.vehicles[1] or 411, 0, 0, -50)
        else
            el = createPed(getElementModel(localPlayer), 0, 0, -50)
        end
    else
        el = createObject(Kinds[kind].model(), 0, 0, -50)
    end
    if not el then return end
    setElementDimension(el, Editor.info.dimension)
    setElementCollisionsEnabled(el, false)
    setElementFrozen(el, true)
    setElementAlpha(el, 160)
    return el
end

-- opts: { model (objects), insertAt (checkpoints) }
function Tools.place(kind, opts)
    Tools.cancel()
    opts = opts or {}
    local list, max = listFor(kind)
    if list and #list >= max then notify("Limit reached (" .. max .. ").") return end
    local ghost = createGhost(kind, opts.model)
    if not ghost then notify("This model cannot be created.") return end
    Tools.current = { type = "place", kind = kind, model = opts.model, insertAt = opts.insertAt, ghost = ghost, rz = 0 }
    Editor.selected = nil
end

local function placeFrame(tool)
    local sx, sy = Tools.screenPoint()
    local hx, hy, hz = View.trace(sx, sy)
    if not hx then
        setElementAlpha(tool.ghost, 0)
        tool.valid = false
        return
    end
    setElementAlpha(tool.ghost, 160)
    setElementRotation(tool.ghost, 0, 0, tool.rz)
    local offset = Kinds.surfaceOffset(tool.kind, tool.ghost)
    setElementPosition(tool.ghost, hx, hy, hz + offset)
    tool.valid, tool.x, tool.y, tool.z = true, hx, hy, hz + offset
end

local function round3(v) return math.floor(v * 1000 + 0.5) / 1000 end

local function commitPlace(tool)
    if not tool.valid then return end
    local x, y, z, rz = round3(tool.x), round3(tool.y), round3(tool.z), tool.rz % 360
    local kind, done = tool.kind, false
    local list, max = listFor(kind)
    if list and #list >= max then notify("Limit reached (" .. max .. ").") Tools.cancel() return end
    Editor.change(function(doc)
        if kind == "object" then
            table.insert(doc.objects, { model = tool.model, x = x, y = y, z = z, rz = rz ~= 0 and rz or nil })
        elseif kind == "spawn" then
            table.insert(Editor.spawnList(), { x, y, z, rz })
        elseif kind == "checkpoint" then
            local cps = doc.race.checkpoints
            local size = (cps[#cps] and cps[#cps][4]) or 5
            if tool.insertAt then
                table.insert(cps, tool.insertAt, { x, y, z, size })
                tool.insertAt = tool.insertAt + 1
            else
                table.insert(cps, { x, y, z, size })
            end
        elseif kind == "finish" then
            doc.race.finish = { x, y, z, doc.race.finish and doc.race.finish[4] or 5 }
            done = true
        elseif kind == "marker" then
            doc.marker = { x, y, z }
            done = true
        end
    end)
    playSoundFrontEnd(41)
    if done then Tools.cancel() end
end

--------------------------------------------------------------------------------
-- moving
--------------------------------------------------------------------------------

function Tools.move(item)
    Tools.cancel()
    if not item or Kinds[item.kind].fixed or not isElement(item.element) then return end
    Tools.current = {
        type = "move", item = item, follow = true,
        snapshot = deepCopy(Editor.doc), orig = deepCopy(item.ref),
    }
    Editor.selected = item
    setElementCollisionsEnabled(item.element, false)
end

local function setItem(item, x, y, z, rx, ry, rz)
    local K = Kinds[item.kind]
    K.set(item.ref, round3(x), round3(y), round3(z), rx and (rx % 360) or 0, ry and (ry % 360) or 0, rz and (rz % 360) or 0)
    applyItem(item)
    setElementCollisionsEnabled(item.element, false)
end

local function moveFrame(tool)
    if not tool.follow then return end
    local item = tool.item
    local sx, sy = Tools.screenPoint()
    local hx, hy, hz = View.trace(sx, sy)
    if not hx then return end
    local _, _, _, rx, ry, rz = Kinds[item.kind].get(item.ref)
    setItem(item, hx, hy, hz + Kinds.surfaceOffset(item.kind, item.element), rx, ry, rz)
end

local function nudge(tool, dx, dy, dz, drx, dry, drz)
    local item = tool.item
    local K = Kinds[item.kind]
    local x, y, z, rx, ry, rz = K.get(item.ref)
    if dx ~= 0 or dy ~= 0 then
        -- arrows are relative to where the camera looks
        local cx, cy, _, lx, ly = getCameraMatrix()
        local yaw = math.atan2(ly - cy, lx - cx)
        x = x + math.cos(yaw) * dy + math.cos(yaw - math.pi / 2) * dx
        y = y + math.sin(yaw) * dy + math.sin(yaw - math.pi / 2) * dx
    end
    z = z + dz
    if K.rotate == "xyz" then
        rx, ry = rx + drx, ry + dry
    end
    if K.rotate then rz = rz + drz end
    setItem(item, x, y, z, rx, ry, rz)
end

local function finishMove(tool, keep)
    local item = tool.item
    if keep then
        Editor.pushUndo(tool.snapshot)
    else
        restoreRef(item.ref, tool.orig)
    end
    if isElement(item.element) then applyItem(item) end
    if Kinds[item.kind].helper and isElement(item.element) then setElementCollisionsEnabled(item.element, false) end
end

--------------------------------------------------------------------------------
-- dispatch (called by client/keys.lua)
--------------------------------------------------------------------------------

function Tools.cancel()
    local tool = Tools.current
    if not tool then return end
    Tools.current = nil
    if tool.type == "place" then
        if isElement(tool.ghost) then destroyElement(tool.ghost) end
    elseif tool.type == "move" then
        finishMove(tool, false)
    end
end

function Tools.confirm()
    local tool = Tools.current
    if not tool then return end
    if tool.type == "move" then
        Tools.current = nil
        finishMove(tool, true)
        playSoundFrontEnd(41)
    end
end

function Tools.click()
    local tool = Tools.current
    if not tool then return false end
    if tool.type == "place" then commitPlace(tool) else Tools.confirm() end
    return true
end

-- Keys while a tool is active. Returns true when the key was used.
function Tools.key(key)
    local tool = Tools.current
    if not tool then return false end
    local mul = stepMul()
    local step, rot = M.step * mul, M.rotStep * mul
    if tool.type == "place" then
        if key == "mouse_wheel_up" then tool.rz = tool.rz + rot * 3 return true end
        if key == "mouse_wheel_down" then tool.rz = tool.rz - rot * 3 return true end
        return false
    end
    local moves = {
        arrow_u = { 0, step, 0, 0, 0, 0 }, arrow_d = { 0, -step, 0, 0, 0, 0 },
        arrow_r = { step, 0, 0, 0, 0, 0 }, arrow_l = { -step, 0, 0, 0, 0, 0 },
        pgup = { 0, 0, step, 0, 0, 0 }, pgdn = { 0, 0, -step, 0, 0, 0 },
        num_4 = { 0, 0, 0, 0, 0, rot }, num_6 = { 0, 0, 0, 0, 0, -rot },
        mouse_wheel_up = { 0, 0, 0, 0, 0, rot * 3 }, mouse_wheel_down = { 0, 0, 0, 0, 0, -rot * 3 },
        num_8 = { 0, 0, 0, rot, 0, 0 }, num_2 = { 0, 0, 0, -rot, 0, 0 },
        num_7 = { 0, 0, 0, 0, rot, 0 }, num_9 = { 0, 0, 0, 0, -rot, 0 },
    }
    local m = moves[key]
    if m then
        if not key:find("wheel") then tool.follow = false end
        nudge(tool, unpack(m))
        return true
    end
    if key == "g" then
        tool.follow = not tool.follow
        return true
    end
    if key == "num_5" then
        local x, y, z = Kinds[tool.item.kind].get(tool.item.ref)
        setItem(tool.item, x, y, z, 0, 0, 0)
        return true
    end
    if key == "end" then
        local item = tool.item
        local x, y, z, rx, ry, rz = Kinds[item.kind].get(item.ref)
        local hit, _, _, hz = processLineOfSight(x, y, z + 1, x, y, z - 300, true, true, false, true, false, false, false, false, item.element)
        if hit then
            tool.follow = false
            setItem(item, x, y, hz + Kinds.surfaceOffset(item.kind, item.element), rx, ry, rz)
        end
        return true
    end
    return false
end

addEventHandler("onClientPreRender", root, function()
    local tool = Tools.current
    if not tool or not Editor.active then return end
    if tool.type == "place" then
        if isElement(tool.ghost) then placeFrame(tool) else Tools.current = nil end
    elseif tool.type == "move" then
        if isElement(tool.item.element) then moveFrame(tool) else Tools.current = nil end
    end
end)

--------------------------------------------------------------------------------
-- item operations
--------------------------------------------------------------------------------

Ops = {}

function Ops.delete(item)
    if not item then return end
    Tools.cancel()
    local kind, index = item.kind, item.index
    Editor.change(function(doc)
        if kind == "object" then table.remove(doc.objects, index)
        elseif kind == "spawn" then table.remove(Editor.spawnList(), index)
        elseif kind == "checkpoint" then table.remove(doc.race.checkpoints, index)
        elseif kind == "finish" then doc.race.finish = nil
        elseif kind == "camera" then doc.race.finishCamera = nil
        elseif kind == "marker" then doc.marker = nil
        end
    end)
    Editor.selected = nil
end

-- Copy next to the original, picked up straight away.
function Ops.duplicate(item)
    if not item or (item.kind ~= "object" and item.kind ~= "spawn") then return end
    local list, max = listFor(item.kind)
    if #list >= max then notify("Limit reached (" .. max .. ").") return end
    Editor.change(function()
        table.insert(list, item.index + 1, deepCopy(item.ref))
    end)
    local newItem = View.groups[item.kind == "object" and "objects" or "spawns"][item.index + 1]
    Tools.move(newItem)
end

function Ops.setField(item, key, value)
    Editor.change(function() item.ref[key] = value end)
end

-- finishCamera from the current camera view
function Ops.setFinishCamera()
    local cx, cy, cz, lx, ly, lz = getCameraMatrix()
    Editor.change(function(doc)
        doc.race.finishCamera = { pos = { round3(cx), round3(cy), round3(cz) }, lookAt = { round3(lx), round3(ly), round3(lz) }, roll = 0, fov = 70 }
    end)
    notify("Finish camera set to the current view.")
end

function Ops.previewCamera(cam)
    if not cam then return end
    local matrix = { cam.pos[1], cam.pos[2], cam.pos[3], cam.lookAt[1], cam.lookAt[2], cam.lookAt[3], 0, cam.fov or 70 }
    if Editor.camMode == "free" then
        Freecam.hold = { matrix = matrix, untilTick = getTickCount() + 3000 }
        return
    end
    setCameraMatrix(unpack(matrix))
    setTimer(function()
        if Editor.active and Editor.camMode == "foot" and not Editor.testing then setCameraTarget(localPlayer) end
    end, 3000, 1)
end
