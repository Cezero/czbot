-- Global always-autoinv item names (cz_common.autoinv_list). Shared across bots.

local botconfig = require('lib.config')

local autoinvlist = {}

local KEY = 'autoinv_list'

local function norm(name)
    if type(name) ~= 'string' then return '' end
    return (name:match('^%s*(.-)%s*$') or ''):lower()
end

local function trim(name)
    if type(name) ~= 'string' then return '' end
    return name:match('^%s*(.-)%s*$') or ''
end

function autoinvlist.getList()
    local list = botconfig.getCommon()[KEY]
    if type(list) ~= 'table' then return {} end
    return list
end

function autoinvlist.contains(name)
    local key = norm(name)
    if key == '' then return false end
    for _, item in ipairs(autoinvlist.getList()) do
        if norm(item) == key then return true end
    end
    return false
end

local function unionCaseInsensitive(diskList, memList)
    local out = {}
    local seen = {}
    local function take(list)
        if type(list) ~= 'table' then return end
        for _, item in ipairs(list) do
            local key = norm(item)
            if key ~= '' and not seen[key] then
                seen[key] = true
                out[#out + 1] = trim(item)
            end
        end
    end
    take(diskList)
    take(memList)
    return out
end

--- Persist a string array. replace=true writes memList as the full list (removals stick).
--- replace=false unions memList onto the disk list, case-insensitive.
function autoinvlist.save(memList, replace)
    local copy = botconfig.copyStringList(memList)
    botconfig.mutateCommon(function(common)
        if replace then
            common[KEY] = copy
        else
            common[KEY] = unionCaseInsensitive(common[KEY], copy)
        end
    end)
end

--- Returns true when the name was newly added.
function autoinvlist.add(name)
    name = trim(name)
    if name == '' then return false end
    local added = false
    local ran = botconfig.mutateCommon(function(common)
        local list = common[KEY]
        if type(list) ~= 'table' then list = {} end
        local key = norm(name)
        for _, item in ipairs(list) do
            if norm(item) == key then return end
        end
        local newList = botconfig.copyStringList(list)
        newList[#newList + 1] = name
        common[KEY] = newList
        added = true
    end)
    if not ran then return nil end
    return added
end

--- Returns true when a matching name was removed. Writes {} when the list becomes empty
--- so merge does not restore the disk copy.
function autoinvlist.remove(name)
    local key = norm(name)
    if key == '' then return false end
    local removed = false
    local ran = botconfig.mutateCommon(function(common)
        local list = common[KEY]
        if type(list) ~= 'table' then return end
        local newList = {}
        for _, item in ipairs(list) do
            if norm(item) ~= key then
                newList[#newList + 1] = item
            else
                removed = true
            end
        end
        if removed then
            common[KEY] = newList
        end
    end)
    if not ran then return nil end
    return removed
end

return autoinvlist
