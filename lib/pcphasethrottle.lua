-- Throttle expensive pc-phase peer scans (buff IconCheck / cure detrimentals) to once per second.

local mq = require('mq')

local pcphasethrottle = {}

local INTERVAL_MS = 1000
local nextAt = { buff = 0, cure = 0 }

---@param key 'buff'|'cure'
---@param resumeCursor table|nil spellutils.getResumeCursor(hookName)
---@return boolean
function pcphasethrottle.allow(key, resumeCursor)
    if resumeCursor and resumeCursor.phase then
        local p = resumeCursor.phase
        if p == 'pc' or p == 'priority' then return true end
    end
    local now = mq.gettime()
    if now < nextAt[key] then return false end
    nextAt[key] = now + INTERVAL_MS
    return true
end

return pcphasethrottle
