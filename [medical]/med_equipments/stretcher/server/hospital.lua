-- Hospital stretchers: free stretchers without a vehicle (med_hospitals requests and removes them
-- at a hospital's stretcher point and parks them in bays / ward spots). Same object, push and patient
-- handling as the ambulance stretcher (server/stretcher.lua createFreeStretcher), but never stowed or
-- loaded. At most HOSPITAL_STRETCHER.MAX_PER_HOSPITAL per hospital; an empty one that nobody touched
-- for IDLE_REMOVE seconds is removed. A stretcher with a patient (alive or dead) is never removed.

local H = HOSPITAL_STRETCHER

local function listOf(hospitalId)
    local out = {}
    for obj, s in pairs(Stretchers) do
        if s.hospital and not s.fixed and (hospitalId == nil or s.hospital == hospitalId) then out[#out + 1] = obj end
    end
    return out
end

-- Exports --------------------------------------------------------------------------------------

-- -> object | false, "limit"
function createHospitalStretcher(hospitalId, x, y, floorZ, rz, dim, int)
    if type(hospitalId) ~= "string" then return false, "hospital" end
    if #listOf(hospitalId) >= H.MAX_PER_HOSPITAL then return false, "limit" end
    return createFreeStretcher(x, y, floorZ, rz, dim, int, { hospital = hospitalId, model = H.OBJECT_MODEL })
end

-- -> true | false, "patient" | "pushing" | "not_hospital"
-- allowPushing: an empty stretcher may be removed while it is pushed (the pusher hands it back at
-- the stretcher point); the pusher lets go first.
function destroyHospitalStretcher(obj, allowPushing)
    local s = Stretchers[obj]
    if not s or not s.hospital or s.fixed then return false, "not_hospital" end
    if s.patient then return false, "patient" end
    if (s.state == "pushing" and not allowPushing) or s.state == "moving" then return false, "pushing" end
    return destroyFreeStretcher(obj)
end

function getHospitalStretchers(hospitalId) return listOf(hospitalId) end

-- The player starts pushing a hospital stretcher that stands on the ground (e.g. one just requested).
function pushHospitalStretcher(obj, player)
    local s = Stretchers[obj]
    if not s or not s.hospital or s.fixed then return false, "not_hospital" end
    if not isElement(player) or getPusherStretcher(player) then return false, "busy" end
    if s.state ~= "ground" then return false, "state" end
    return startPushing(s, player) == true
end

-- The pusher lets go of a pushed hospital stretcher (med_hospitals: 3 s in a handover marker). It is put
-- down as with the "release" menu item, so onStretcherSettled fires with the pusher.
function releaseHospitalStretcher(obj)
    local s = Stretchers[obj]
    if not s or not s.hospital or s.fixed or s.state ~= "pushing" then return false end
    return releaseStretcher(s) == true
end

-- A fixed bed (ward / ICU): a free stretcher object that cannot be pushed or removed
function createHospitalBed(hospitalId, x, y, floorZ, rz, dim, int)
    return createFreeStretcher(x, y, floorZ, rz, dim, int, { hospital = hospitalId, fixed = true, model = H.BED_MODEL or H.OBJECT_MODEL })
end

function destroyHospitalBed(obj)
    local s = Stretchers[obj]
    if not s or not s.fixed then return false end
    destroyFreeStretcher(obj)
    return true
end

function isHospitalStretcher(obj)
    local s = Stretchers[obj]
    return s and s.hospital and true or false
end

function getStretcherHospital(obj)
    local s = Stretchers[obj]
    return s and s.hospital or false
end

function parkHospitalStretcher(obj, x, y, floorZ, rz)
    return parkFreeStretcher(obj, x, y, floorZ, rz)
end

-- Lays the ped on the stretcher (from anywhere: another stretcher, the floor, a vehicle seat).
function putPatientOnStretcher(obj, ped)
    local s = Stretchers[obj]
    if not s or s.patient or not isElement(ped) then return false end
    local old = getPatientStretcher(ped)
    if old and Stretchers[old] then removePatient(Stretchers[old], false) end
    putPatient(s, ped)
    return true
end

-- Seconds since the stretcher was last moved / got or lost a patient
function getStretcherIdleTime(obj)
    local s = Stretchers[obj]
    if not s then return false end
    return (getTickCount() - (s.lastUsed or getTickCount())) / 1000
end

-- Cleanup ---------------------------------------------------------------------------------------

setTimer(function()
    local now = getTickCount()
    for _, obj in ipairs(listOf(nil)) do
        local s = Stretchers[obj]
        if s and not s.patient and s.state == "ground" and now - (s.lastUsed or now) >= H.IDLE_REMOVE * 1000 then
            destroyFreeStretcher(obj)
        end
    end
end, H.CLEANUP_INTERVAL * 1000, 0)
