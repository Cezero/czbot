-- Generic helpers (table copy, list membership, distance).

local utils = {}

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

function utils.calcDist3D(x1, y1, z1, x2, y2, z2)
    if x1 and y1 and x2 and y2 and z1 and z2 then return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2 + (z2 - z1) ^ 2) end
end

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
