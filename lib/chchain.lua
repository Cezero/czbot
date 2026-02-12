-- CHChain (Complete Heal chain) logic. State in state.getRunconfig(): doChchain, chchainCurtank, chchainPause, chchainTank, chchainTanklist, chnextClr.

local mq = require('mq') ---@cast mq mq
local state = require('lib.state')
local bothooks = require('lib.bothooks')
local targeting = require('lib.targeting')
local spellutils = require('lib.spellutils')
local command_dispatcher = require('lib.command_dispatcher')

local chchain = {}

local function event_CHChain(line, arg1)
    return chchain.OnGo(line, arg1)
end

local function event_CHChainSetup(line, arg1, arg2, arg3, arg4)
    if arg1 == 'setup' then command_dispatcher.Dispatch('chchain', 'setup', arg2, arg3, arg4) end
end

local function event_CHChainStop(line)
    if string.find(line, 'stop') then command_dispatcher.Dispatch('chchain', 'stop') end
end

local function event_CHChainStart(line, arg1, argN)
    local cleanname = arg1 and arg1:match("%S+")
    if arg1 then command_dispatcher.Dispatch('chchain', 'start', cleanname) end
end

local function event_CHChainTank(line, arg1, argN)
    local cleanname = arg1 and arg1:match("%S+")
    if arg1 and state.getRunconfig().doChchain then command_dispatcher.Dispatch('chchain', 'tank', cleanname) end
end

local function event_CHChainPause(line, arg1, argN)
    if arg1 and state.getRunconfig().doChchain then command_dispatcher.Dispatch('chchain', 'pause', arg1) end
end

function chchain.registerEvents()
    mq.event('CHChain', "#*#Go #1#>>#*#", event_CHChain)
    mq.event('CHChainStop', "#*#chchain stop#*#", event_CHChainStop)
    mq.event('CHChainStart', "#*#chchain start #1#'", event_CHChainStart)
    mq.event('CHChainTank', "#*#chchain tank #1#'", event_CHChainTank)
    mq.event('CHChainPause', "#*#chchain pause #1#'", event_CHChainPause)
    mq.event('CHChainSetup', "#*#chchain #1# #2# #3# #4#", event_CHChainSetup)
end

function chchain.OnGo(line, arg1)
    local rc = state.getRunconfig()
    local myName = mq.TLO.Me.Name()
    if not myName or string.lower(arg1) ~= string.lower(myName) then return false end
    if not rc.doChchain then return false end
    rc.chchainCurtank = 1
    local chtimer = (rc.chchainPause * 100) + mq.gettime()
    local tankid = mq.TLO.Spawn('=' .. rc.chchainTank).ID()
    if not tankid or tankid == 0 or mq.TLO.Spawn(tankid).Type() == 'Corpse' then
        rc.chchainCurtank = rc.chchainCurtank + 1
        if rc.chchainTanklist[rc.chchainCurtank] and mq.TLO.Spawn('=' .. rc.chchainTanklist[rc.chchainCurtank]).Type() == 'PC' and mq.TLO.Spawn('=' .. rc.chchainTanklist[rc.chchainCurtank]).ID() then
            mq.cmdf('/rs Tank DIED or ZONED, moving to tank %s, %s', rc.chchainCurtank, rc.chchainTanklist[rc.chchainCurtank])
            rc.chchainTank = rc.chchainTanklist[rc.chchainCurtank]
            tankid = mq.TLO.Spawn('=' .. rc.chchainTank).ID()
        else
            mq.cmdf('/rs Tank %s is not in zone or dead, skipping', rc.chchainCurtank)
            -- Defer /rs <<Go>> until chchainpause expires; chchainTick will do it.
            state.setRunState('chchain', { deadline = mq.gettime() + (rc.chchainPause or 0) * 100, chnextclr = rc.chnextClr, priority = bothooks.getPriority('chchainTick') })
            return
        end
    end
    if not tankid or tankid == 0 then return end
    if rc.chchainTank and mq.TLO.Target.ID() ~= tankid then
        targeting.TargetAndWait(tankid, 500)
    end
    if rc.chchainTank and mq.TLO.Target.ID() ~= tankid then
        return
    end
    if (mq.TLO.Me.CurrentMana() - (mq.TLO.Me.ManaRegen() * 2)) < 400 then
        mq.cmdf('/rs SKIP ME (out of mana)')
        state.setRunState('chchain', { deadline = mq.gettime() + (rc.chchainPause or 0) * 100, chnextclr = rc.chnextClr, priority = bothooks.getPriority('chchainTick') })
        return
    end
    if not spellutils.DistanceCheck('complete heal', 0, tankid) then
        mq.cmdf(
            '/rs Tank %s is out of range of complete heal!', rc.chchainTank)
    end
    mq.cmdf('/multiline ; /cast "Complete Heal" ; /rs CH >> %s << (pause:%s mana:%s)', rc.chchainTank, rc.chchainPause,
        mq.TLO.Me.PctMana())
    state.setRunState('chchain', { deadline = chtimer, chnextclr = rc.chnextClr, priority = bothooks.getPriority('chchainTick') })
end

function chchain.getHookFn(name)
    if name == 'chchainTick' then
        return function(hookName)
            if state.getRunState() ~= 'chchain' then return end
            local p = state.getRunStatePayload()
            if not p or not p.chnextclr then state.clearRunState() return end
            if mq.TLO.Cast.Result() == 'CAST_FIZZLE' then
                mq.cmdf('/casting "Complete Heal" 5')
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
        end
    end
    return nil
end

return chchain
