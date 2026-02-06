-- Shared "wait for /tar id to populate" state and timer. No mq.delay.
-- Call SetTarget(id, timeoutMs); on a later tick TickTargeting() clears state when Target.ID() == id or timeout.

local mq = require('mq')
local state = require('lib.state')

local targeting = {}

function targeting.SetTarget(id, timeoutMs)
    if not id or id == 0 then return end
    mq.cmdf('/tar id %s', id)
    state.setRunState('targeting', { targetID = id, deadline = mq.gettime() + (timeoutMs or 500) })
end

function targeting.TickTargeting()
    if state.getRunState() ~= 'targeting' then return end
    local p = state.getRunStatePayload()
    if not p then state.clearRunState() return end
    local now = mq.gettime()
    if now >= (p.deadline or 0) or (p.targetID and mq.TLO.Target.ID() == p.targetID) then
        state.getRunconfig().targetingResult = (mq.TLO.Target.ID() == p.targetID)
        state.clearRunState()
    end
end

function targeting.IsActive()
    return state.getRunState() == 'targeting'
end

do
    local hookregistry = require('lib.hookregistry')
    hookregistry.registerMainloopHook('tickTargeting', targeting.TickTargeting, 100)
end

return targeting
