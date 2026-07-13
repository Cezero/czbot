-- Throttle expensive multi-target phase scans (buff/cure/heal).

local mq = require('mq')

local pcphasethrottle = {}

-- Wall-clock belt; pass cooldown is the main light/heavy spacer at ~1Hz BuffCheck.
local INTERVAL_MS = 2000
--- After a heavy RR grant, force this many following BuffChecks to stay light (self/tank only).
local BUFF_HEAVY_SKIP_PASSES = 2

--- Phases that are rate-limited per section. Others always allowed.
local THROTTLED = {
    buff = { pc = true, groupmember = true, pet = true, mypet = true, byname = true, groupbuff = true },
    cure = { pc = true, priority = true },
    -- Heal: corpse/rez only. Do not throttle groupmember, pc, or pet.
    heal = { corpse = true },
}

--- Buff: at most one of these per INTERVAL_MS wall-clock (shared token), round-robin.
local BUFF_RR_ORDER = { 'groupbuff', 'byname', 'groupmember', 'pc', 'mypet', 'pet' }
local buffRrNext = 1
--- Phase granted for the current buff pass (nil = none yet).
local buffPassGrant = nil
--- Shared wall-clock: next time any RR heavy phase may be granted.
local buffHeavyNextAt = 0
--- Remaining BuffChecks that must stay light after a heavy grant.
local buffHeavySkipRemaining = 0
--- True for this pass when skip countdown consumed a light pass at beginBuffPass.
local buffHeavyBlockedThisPass = false
--- True if any throttled RR phase called allow() this pass.
local buffRrAsked = false
--- First deny reason seen this pass when an RR phase was asked but not granted: cooldown|interval.
local buffDenyReason = nil

--- nextAt[section][phase] = mq.gettime() when next allow is ok
local nextAt = {}

--- Call at start of each BuffCheck so only one RR phase may run this pass.
function pcphasethrottle.beginBuffPass()
    buffPassGrant = nil
    buffRrAsked = false
    buffDenyReason = nil
    buffHeavyBlockedThisPass = buffHeavySkipRemaining > 0
    if buffHeavyBlockedThisPass then
        buffHeavySkipRemaining = buffHeavySkipRemaining - 1
    end
end

--- RR phase granted this BuffCheck (nil if light / self+tank only).
function pcphasethrottle.getBuffPassGrant()
    return buffPassGrant
end

--- Summarize this BuffCheck after spellcheck: mode=heavy|light and phase or reason.
--- @return string mode
--- @return string|nil detail phase name (heavy) or reason (light)
function pcphasethrottle.noteBuffPassEnd()
    if buffPassGrant then
        return 'heavy', buffPassGrant
    end
    if not buffRrAsked then
        return 'light', 'no_rr_phase'
    end
    return 'light', buffDenyReason or 'denied'
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
        buffRrAsked = true
        if buffPassGrant == phase then return true end
        if buffPassGrant ~= nil then return false end
        if buffHeavyBlockedThisPass then
            if not buffDenyReason then buffDenyReason = 'cooldown' end
            return false
        end
        if now < buffHeavyNextAt then
            if not buffDenyReason then buffDenyReason = 'interval' end
            return false
        end

        local n = #BUFF_RR_ORDER
        local chosenIdx = ((buffRrNext - 1) % n) + 1
        local chosen = BUFF_RR_ORDER[chosenIdx]
        if chosen ~= phase then return false end

        buffPassGrant = chosen
        buffHeavyNextAt = now + INTERVAL_MS
        buffHeavySkipRemaining = BUFF_HEAVY_SKIP_PASSES
        buffRrNext = (chosenIdx % n) + 1
        return true
    end

    local due = bucket[phase] or 0
    if now < due then return false end
    bucket[phase] = now + INTERVAL_MS
    return true
end

return pcphasethrottle
