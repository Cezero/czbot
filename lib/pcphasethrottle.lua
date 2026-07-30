-- Throttle expensive multi-target phase scans (cure/heal). Buff phases are not throttled
-- (peer need is on CharInfo watches; non-peer work is gated separately).

local mq = require('mq')

local pcphasethrottle = {}

local INTERVAL_MS = 2000

--- Phases that are rate-limited per section. Others always allowed.
local THROTTLED = {
    cure = { pc = true, priority = true },
    -- Heal: corpse/rez only. Do not throttle groupmember, pc, or pet.
    heal = { corpse = true },
}

--- nextAt[section][phase] = mq.gettime() when next allow is ok
local nextAt = {}

---@param section string 'buff'|'cure'|'heal'
---@param resumeCursor table|nil spellutils.getResumeCursor(hookName)
---@param phase string|nil phase being requested (default 'pc' for cure backward compat)
---@return boolean
function pcphasethrottle.allow(section, resumeCursor, phase)
    phase = phase or 'pc'
    if resumeCursor and resumeCursor.phase then
        local p = resumeCursor.phase
        if p == phase then return true end
        -- cure resume on priority also allows pc scans mid-resume
        if section == 'cure' and phase == 'pc' and p == 'priority' then return true end
    end
    local throttled = THROTTLED[section]
    if not throttled or not throttled[phase] then return true end

    local bucket = nextAt[section]
    if not bucket then
        bucket = {}
        nextAt[section] = bucket
    end
    local now = mq.gettime()
    local due = bucket[phase] or 0
    if now < due then return false end
    bucket[phase] = now + INTERVAL_MS
    return true
end

return pcphasethrottle
