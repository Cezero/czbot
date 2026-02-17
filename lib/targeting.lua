-- Blocking "wait for /tar id to populate" via mq.delay(duration, condition).
-- Call TargetAndWait(id, timeoutMs): issues /tar, delays until Target.ID() == id or timeout, returns success.

local mq = require('mq')
local state = require('lib.state')

local targeting = {}

--- Issue /tar id and block until target is set or timeout. Returns true if Target.ID() == id.
---@param id number Spawn ID to target
---@param timeoutMs number? Max ms to wait (default 500)
---@return boolean ok True if mq.TLO.Target.ID() == id after wait
function targeting.TargetAndWait(id, timeoutMs)
    if not id or id == 0 then return false end
    mq.cmdf('/tar id %s', id)
    state.getRunconfig().statusMessage = string.format('Waiting for target (id %s)', id)
    mq.delay(timeoutMs or 500, function() return mq.TLO.Target.ID() == id end)
    state.getRunconfig().statusMessage = ''
    return mq.TLO.Target.ID() == id
end

--- Target spawn by id and block until Target.BuffsPopulated() or timeout. Returns true if targeted and buffs populated.
---@param id number Spawn ID to target
---@param timeoutMs number? Max ms to wait (default 1000)
---@return boolean ok True if mq.TLO.Target.ID() == id and mq.TLO.Target.BuffsPopulated() after wait
function targeting.TargetAndWaitBuffsPopulated(id, timeoutMs)
    if not id or id == 0 then return false end
    mq.cmdf('/tar id %s', id)
    local ms = timeoutMs or 1000
    mq.delay(ms, function() return mq.TLO.Target.ID() == id and mq.TLO.Target.BuffsPopulated() end)
    return mq.TLO.Target.ID() == id and mq.TLO.Target.BuffsPopulated()
end

return targeting
