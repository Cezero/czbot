-- Throttle expensive multi-target phase scans (buff/cure/heal).

local mq = require('mq')

local pcphasethrottle = {}

local INTERVAL_MS = 1000

--- Phases that are rate-limited per section. Others always allowed.
local THROTTLED = {
    buff = { pc = true, groupmember = true, pet = true, mypet = true, byname = true, groupbuff = true },
    cure = { pc = true, priority = true },
    -- Heal: corpse/rez only. Do not throttle groupmember, pc, or pet.
    heal = { corpse = true },
}

--- Buff: one of these per BuffCheck, round-robin among due phases (breaks 1s stampede).
local BUFF_RR_ORDER = { 'groupbuff', 'byname', 'groupmember', 'pc', 'mypet', 'pet' }
local buffRrNext = 1
--- Phase granted for the current buff pass (nil = none yet).
local buffPassGrant = nil

--- nextAt[section][phase] = mq.gettime() when next allow is ok
local nextAt = {}

--- Call at start of each BuffCheck so only one RR phase may run this pass.
function pcphasethrottle.beginBuffPass()
    buffPassGrant = nil
end

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
        -- buff resume on a throttled phase allows that phase mid-resume
        if section == 'buff' and THROTTLED.buff and THROTTLED.buff[p] and p == phase then return true end
    end
    local throttled = THROTTLED[section]
    if not throttled or not throttled[phase] then return true end

    local bucket = nextAt[section]
    if not bucket then
        bucket = {}
        nextAt[section] = bucket
    end
    local now = mq.gettime()

    if section == 'buff' then
        if buffPassGrant == phase then return true end
        if buffPassGrant ~= nil then return false end

        local n = #BUFF_RR_ORDER
        local chosen, chosenIdx = nil, nil
        for offset = 0, n - 1 do
            local i = ((buffRrNext - 1 + offset) % n) + 1
            local p = BUFF_RR_ORDER[i]
            if (bucket[p] or 0) <= now then
                chosen, chosenIdx = p, i
                break
            end
        end
        if not chosen or chosen ~= phase then return false end
        buffPassGrant = chosen
        bucket[chosen] = now + INTERVAL_MS
        buffRrNext = (chosenIdx % n) + 1
        return true
    end

    local due = bucket[phase] or 0
    if now < due then return false end
    bucket[phase] = now + INTERVAL_MS
    return true
end

return pcphasethrottle
