-- CHChain (Complete Heal chain) logic. Uses globals set by commands.cmd_chchain:
-- dochchain, chchaincurtank, chchainpause, chchaintank, chtanklist, chnextclr

local mq = require('mq')
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
    if arg1 and dochchain then command_dispatcher.Dispatch('chchain', 'tank', cleanname) end
end

local function event_CHChainPause(line, arg1, argN)
    if arg1 and dochchain then command_dispatcher.Dispatch('chchain', 'pause', arg1) end
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
    if string.lower(arg1) ~= string.lower(mq.TLO.Me.Name()) then return false end
    if not dochchain then return false end
    chchaincurtank = 1
    local chtimer = (chchainpause * 100) + mq.gettime()
    local tankid = mq.TLO.Spawn('=' .. chchaintank).ID()
    if not tankid or tankid == 0 or mq.TLO.Spawn(tankid).Type() == 'Corpse' then
        chchaincurtank = chchaincurtank + 1
        if chtanklist[chchaincurtank] and mq.TLO.Spawn('=' .. chtanklist[chchaincurtank]).Type() == 'PC' and mq.TLO.Spawn('=' .. chtanklist[chchaincurtank]).ID() then
            mq.cmdf('/rs Tank DIED or ZONED, moving to tank %s, %s', chchaincurtank, chtanklist[chchaincurtank])
            chchaintank = chtanklist[chchaincurtank]
            tankid = mq.TLO.Spawn('=' .. chchaintank).ID()
        else
            mq.cmdf('/rs Tank %s is not in zone or dead, skipping', chchaincurtank)
            -- Defer /rs <<Go>> until chchainpause expires; chchainTick will do it.
            state.setRunState('chchain', { deadline = mq.gettime() + (chchainpause or 0) * 100, chnextclr = chnextclr, priority = bothooks.getPriority('chchainTick') })
            return
        end
    end
    if chchaintank and mq.TLO.Target.ID() ~= tankid then
        targeting.TargetAndWait(tankid, 500)
    end
    if chchaintank and mq.TLO.Target.ID() ~= tankid then
        return
    end
    if (mq.TLO.Me.CurrentMana() - (mq.TLO.Me.ManaRegen() * 2)) < 400 then
        mq.cmdf('/rs SKIP ME (out of mana)')
        state.setRunState('chchain', { deadline = mq.gettime() + (chchainpause or 0) * 100, chnextclr = chnextclr, priority = bothooks.getPriority('chchainTick') })
        return
    end
    if not spellutils.DistanceCheck('complete heal', 0, tankid) then
        mq.cmdf(
            '/rs Tank %s is out of range of complete heal!', chchaintank)
    end
    mq.cmdf('/multiline ; /cast "Complete Heal" ; /rs CH >> %s << (pause:%s mana:%s)', chchaintank, chchainpause,
        mq.TLO.Me.PctMana())
    state.setRunState('chchain', { deadline = chtimer, chnextclr = chnextclr, priority = bothooks.getPriority('chchainTick') })
end

function chchain.getHookFn(name)
    if name == 'chchainTick' then
        return function(hookName)
            if state.getRunState() == 'loading_gem' then
                local p = state.getRunStatePayload()
                if p and p.source == 'chchain_setup' then
                    local result = spellutils.LoadingGemComplete(p)
                    if result == 'still_waiting' then return end
                    state.getRunconfig().statusMessage = ''
                    state.clearRunState()
                    if result == 'done_ok' then
                        local commands = require('lib.commands')
                        commands.chchainSetupContinuation(p.setupArgs)
                    else
                        printf('\ayCZBot:\ax CHChain: Complete Heal could not be memorized in gem %s', p.gem or 5)
                    end
                    return
                end
            end
            if state.getRunState() ~= 'chchain' then return end
            local p = state.getRunStatePayload()
            if not p or not p.chnextclr then state.clearRunState() return end
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
        end
    end
    return nil
end

return chchain
