-- Generic helpers (table copy, list membership, distance).
-- Non-combat zones: hooks (AddSpawnCheck, doPull, doMelee, etc.) can skip combat logic when zone is in this list.

local utils = {}

local NONCOMBAT_ZONES = { 'GuildHall', 'GuildLobby', 'PoKnowledge', 'Nexus', 'Bazaar', 'AbysmalSea', 'potranquility' }

function utils.getNonCombatZones()
    return NONCOMBAT_ZONES
end

---@param zone string|nil Zone short name (e.g. mq.TLO.Zone.ShortName()). If nil, returns false.
function utils.isNonCombatZone(zone)
    if not zone then return false end
    local z = string.lower(zone)
    for _, v in ipairs(NONCOMBAT_ZONES) do
        if z == string.lower(v) then return true end
    end
    return false
end

-- Create full copy of a table instead of a reference (recursive, including metatable).
function utils.DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[utils.DeepCopy(orig_key)] = utils.DeepCopy(orig_value)
        end
        setmetatable(copy, utils.DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

function utils.isInList(value, list)
    for _, v in ipairs(list) do
        if value == v then
            return true
        end
    end
    return false
end

--- Squared distance (no sqrt) for fast comparisons. Returns nil if any coord missing.
--- @return number|nil (x2-x1)^2 + (y2-y1)^2
function utils.getDistanceSquared2D(x1, y1, x2, y2)
    if x1 == nil or y1 == nil or x2 == nil or y2 == nil then return nil end
    return (x2 - x1) ^ 2 + (y2 - y1) ^ 2
end

--- Squared distance 3D (no sqrt) for fast comparisons. Returns nil if any coord missing.
--- @return number|nil (x2-x1)^2 + (y2-y1)^2 + (z2-z1)^2
function utils.getDistanceSquared3D(x1, y1, z1, x2, y2, z2)
    if x1 == nil or y1 == nil or z1 == nil or x2 == nil or y2 == nil or z2 == nil then return nil end
    return (x2 - x1) ^ 2 + (y2 - y1) ^ 2 + (z2 - z1) ^ 2
end

--- Actual distance (sqrt). Use only for display or when an API requires real distance.
--- For all normal comparisons (range checks, sorting) use getDistanceSquared2D/getDistanceSquared3D instead.
function utils.calcDist3D(x1, y1, z1, x2, y2, z2)
    if x1 and y1 and x2 and y2 and z1 and z2 then return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2 + (z2 - z1) ^ 2) end
end

--- Actual distance (sqrt). Use only for display or when an API requires real distance.
--- For all normal comparisons (range checks, sorting) use getDistanceSquared2D instead.
function utils.calcDist2D(x1, y1, x2, y2)
    if x1 and y1 and x2 and y2 then return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) end
end

-- Split string on delimiter, trim whitespace from each segment, return array of strings.
function utils.splitString(str, delim)
    local result = {}
    for match in (str .. delim):gmatch("(.-)" .. delim) do
        table.insert(result, match:match("^%s*(.-)%s*$"))
    end
    return result
end

return utils
