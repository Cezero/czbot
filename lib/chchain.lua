-- CHChain (Complete Heal chain) logic. Uses globals set by commands.cmd_chchain:
-- dochchain, chchaincurtank, chchainpause, chchaintank, chtanklist, chnextclr

local mq = require('mq')
local state = require('lib.state')
local targeting = require('lib.targeting')
local spellutils = require('lib.spellutils')
local hookregistry = require('lib.hookregistry')

local chchain = {}

function chchain.OnGo(line, arg1)
    if string.lower(arg1) ~= string.lower(mq.TLO.Me.Name()) then return false end
    if not dochchain then return false end
    chchaincurtank = 1
    local chtimer = (chchainpause * 100) + mq.gettime()
    if debug then print(chtimer, ' ', mq.gettime()) end
    local tankid = mq.TLO.Spawn('=' .. chchaintank).ID()
    if debug then print(tankid, chchaintank) end
    if not tankid or tankid == 0 or mq.TLO.Spawn(tankid).Type() == 'Corpse' then
        chchaincurtank = chchaincurtank + 1
        if chtanklist[chchaincurtank] and mq.TLO.Spawn('=' .. chtanklist[chchaincurtank]).Type() == 'PC' and mq.TLO.Spawn('=' .. chtanklist[chchaincurtank]).ID() then
            mq.cmdf('/rs Tank DIED or ZONED, moving to tank %s, %s', chchaincurtank, chtanklist[chchaincurtank])
            chchaintank = chtanklist[chchaincurtank]
            tankid = mq.TLO.Spawn('=' .. chchaintank).ID()
        else
            mq.cmdf('/rs Tank %s is not in zone or dead, skipping', chchaincurtank)
            -- Defer /rs <<Go>> until chchainpause expires; chchainTick will do it.
            state.setRunState('chchain', { deadline = mq.gettime() + (chchainpause or 0) * 100, chnextclr = chnextclr })
            return
        end
    end
    if chchaintank and mq.TLO.Target.ID() ~= tankid then
        targeting.SetTarget(tankid, 500)
        state.setRunState('chchain', { waitingForTarget = true, deadline = chtimer, chnextclr = chnextclr })
        return
    end
    if (mq.TLO.Me.CurrentMana() - (mq.TLO.Me.ManaRegen() * 2)) < 400 then
        mq.cmdf('/rs SKIP ME (out of mana)')
        state.setRunState('chchain', { deadline = mq.gettime() + (chchainpause or 0) * 100, chnextclr = chnextclr })
        return
    end
    if not spellutils.DistanceCheck('complete heal', 0, tankid) then
        mq.cmdf(
            '/rs Tank %s is out of range of complete heal!', chchaintank)
    end
    mq.cmdf('/multiline ; /cast "Complete Heal" ; /rs CH >> %s << (pause:%s mana:%s)', chchaintank, chchainpause,
        mq.TLO.Me.PctMana())
    state.setRunState('chchain', { deadline = chtimer, chnextclr = chnextclr })
end

hookregistry.registerMainloopHook('chchainTick', function()
    if state.getRunState() ~= 'chchain' then return end
    local p = state.getRunStatePayload()
    if not p or not p.chnextclr then state.clearRunState() return end
    if p.waitingForTarget then
        if not targeting.IsActive() then
            state.setRunState('chchain', { deadline = p.deadline, chnextclr = p.chnextclr })
            mq.cmdf('/multiline ; /cast "Complete Heal" ; /rs CH >> %s << (pause:%s mana:%s)', chchaintank, chchainpause, mq.TLO.Me.PctMana())
        end
        return
    end
    if mq.TLO.Cast.Result() == 'CAST_FIZZLE' then
        mq.cmdf('/cast "Complete Heal"')
        return
    end
    if mq.TLO.Me.CastTimeLeft() and mq.TLO.Me.CastTimeLeft() > 0 and mq.TLO.Target.Type() == 'Corpse' then
        mq.cmdf('/multiline ; /rs CHChain: Target died, interrupting cast ; /interrupt')
        mq.cmdf('/rs <<Go %s>>', p.chnextclr)
        state.clearRunState()
        return
    end
    if mq.gettime() >= (p.deadline or 0) then
        mq.cmdf('/rs <<Go %s>>', p.chnextclr)
        state.clearRunState()
        return
    end
    if not mq.TLO.Me.Sitting() and not mq.TLO.Me.CastTimeLeft() then
        mq.cmd('/sit on')
    end
end, 500)

return chchain
