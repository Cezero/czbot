-- CHChain (Complete Heal chain) logic. State in state.getRunconfig(): doChchain, chchainCurtank, chchainPause, chchainTank, chchainTanklist, chnextClr.
-- State diagram: OnGo (Go >>me<<) sets runState chchain with deadline; chchainTick either clears (pass Go) or re-sets state (fizzle/skip).

local mq = require('mq')
local state = require('lib.state')
local bothooks = require('lib.bothooks')
local targeting = require('lib.targeting')
local spellutils = require('lib.spellutils')
local command_dispatcher = require('lib.command_dispatcher')
local casting = require('lib.casting')
local utils = require('lib.utils')
local czactor = require('lib.czactor')
local czactor_dispatch = require('lib.czactor_dispatch')

local chchain = {}

--- Strip raid-chat punctuation from an mq.event capture (e.g. Buhmarez' -> Buhmarez).
local function cleanEventToken(s)
    if not s or s == '' then return nil end
    local token = s:match('%S+')
    if not token then return nil end
    return token:gsub("^['\"]+", ''):gsub("['\"]+$", '')
end

chchain.cleanEventToken = cleanEventToken

local function deferChchainGo(rc, deadline)
    state.setRunState(state.STATES.chchain, {
        deadline = deadline or chchain.getDeadline(rc),
        chnextclr = rc.chnextClr,
        priority = bothooks.getPriority('chchainTick'),
    })
end

local function castCompleteHeal(rc)
    spellutils.AutoinvIfCursorBlockingCast()
    mq.cmdf('/multiline ; /cast "Complete Heal" ; /rs CH >> %s << (pause:%s mana:%s)', rc.chchainTank, rc.chchainPause,
        mq.TLO.Me.PctMana())
end

local function isTankInCHRange(tankid)
    local spellRange = mq.TLO.Spell('Complete Heal').MyRange()
    if not spellRange or spellRange <= 0 then return true end
    local sp = mq.TLO.Spawn(tankid)
    if not sp or not sp.ID() or sp.ID() == 0 then return false end
    local distSq = utils.getDistanceSquared3D(mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z(), sp.X(), sp.Y(), sp.Z())
    return distSq and distSq <= (spellRange * spellRange)
end

--- Update curtank index/name when index >= current. Returns true if state changed forward.
local function advanceCurtank(rc, index, tankName)
    if not rc.doChchain then return false end
    if not index or not tankName or tankName == '' then return false end
    local cur = rc.chchainCurtank or 1
    if index < cur then return false end
    rc.chchainCurtank = index
    rc.chchainTank = tankName
    return true
end

local function applyCurtank(content, sender)
    local rc = state.getRunconfig()
    if not rc.doChchain then return end
    local idx = tonumber(content.index)
    local name = content.tank
    if not idx or not name or name == '' then return end
    local prev = rc.chchainCurtank or 1
    if idx < prev then
        printf('CHChain curtank ignored (stale) from %s: index=%s tank=%s', tostring(sender), tostring(idx), tostring(name))
        return
    end
    advanceCurtank(rc, idx, name)
end

--- First alive tank from chchainCurtank onward that is in Complete Heal range for this cleric.
local function selectHealTank(rc)
    local list = rc.chchainTanklist
    if not list or #list == 0 then return nil end
    local startIdx = rc.chchainCurtank or 1
    if startIdx < 1 then startIdx = 1 end

    for idx = startIdx, #list do
        local name = list[idx]
        if name and name ~= '' then
            local sp = mq.TLO.Spawn('=' .. name)
            if sp and sp.Type() == 'PC' and sp.ID() and sp.ID() > 0 then
                local tid = sp.ID()
                if isTankInCHRange(tid) then
                    local prev = rc.chchainCurtank or 1
                    if advanceCurtank(rc, idx, name) and idx > prev then
                        czactor.publish('chchain_curtank', { index = idx, tank = name })
                    end
                    return tid
                end
            end
        end
    end
    return nil
end

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
    local cleanname = cleanEventToken(arg1)
    if cleanname then command_dispatcher.Dispatch('chchain', 'start', cleanname) end
end

local function event_CHChainTank(line, arg1, argN)
    local cleanname = cleanEventToken(arg1)
    if cleanname and state.getRunconfig().doChchain then command_dispatcher.Dispatch('chchain', 'tank', cleanname) end
end

local function event_CHChainPause(line, arg1, argN)
    local cleanval = cleanEventToken(arg1) or arg1
    if cleanval and state.getRunconfig().doChchain then command_dispatcher.Dispatch('chchain', 'pause', cleanval) end
end

--- Deadline for current chchain round: chchainPause (tenths of sec) * 100 ms + now.
function chchain.getDeadline(rc)
    rc = rc or state.getRunconfig()
    return (rc.chchainPause or 0) * 100 + mq.gettime()
end

function chchain.registerEvents()
    mq.event('CHChain', "#*#Go #1#>>#*#", event_CHChain)
    mq.event('CHChainStop', "#*#chchain stop#*#", event_CHChainStop)
    mq.event('CHChainStart', "#*#chchain start #1#'", event_CHChainStart)
    mq.event('CHChainTank', "#*#chchain tank #1#'", event_CHChainTank)
    mq.event('CHChainPause', "#*#chchain pause #1#'", event_CHChainPause)
    mq.event('CHChainSetup', "#*#chchain #1# #2# #3# #4#", event_CHChainSetup)
end

function chchain.registerActorHandlers()
    czactor_dispatch.RegisterHandler('chchain_curtank', applyCurtank)
end

function chchain.OnGo(line, arg1)
    local rc = state.getRunconfig()
    local myName = mq.TLO.Me.Name()
    arg1 = cleanEventToken(arg1)
    if not arg1 or not myName or string.lower(arg1) ~= string.lower(myName) then return false end
    if not rc.doChchain then return false end
    local chtimer = chchain.getDeadline(rc)
    local tankid = selectHealTank(rc)
    if not tankid or tankid == 0 then
        mq.cmdf('/rs CHChain: No live tank in range, passing turn to %s', rc.chnextClr or '?')
        deferChchainGo(rc)
        return
    end
    if rc.chchainTank and mq.TLO.Target.ID() ~= tankid then
        targeting.TargetAndWait(tankid, 500)
    end
    if rc.chchainTank and mq.TLO.Target.ID() ~= tankid then
        mq.cmdf('/rs CHChain: Failed to target tank %s, passing turn to %s', rc.chchainTank, rc.chnextClr or '?')
        deferChchainGo(rc)
        return
    end
    if (mq.TLO.Me.CurrentMana() - (mq.TLO.Me.ManaRegen() * 2)) < 400 then
        mq.cmdf('/rs SKIP ME (out of mana)')
        deferChchainGo(rc, mq.gettime() + (rc.chchainPause or 0) * 100)
        return
    end
    castCompleteHeal(rc)
    state.setRunState(state.STATES.chchain, { deadline = chtimer, chnextclr = rc.chnextClr, priority = bothooks.getPriority('chchainTick') })
end

--- One tick of chchain state: fizzle handling, target-died interrupt, deadline (pass Go), sit when not casting.
function chchain.Tick()
    local p = state.getRunStatePayload()
    if not p or not p.chnextclr then state.clearRunState() return end
    if casting.result() == 'CAST_FIZZLE' then
        spellutils.AutoinvIfCursorBlockingCast()
        casting.clear()
        castCompleteHeal(state.getRunconfig())
        return
    end
    if mq.TLO.Me.CastTimeLeft() and mq.TLO.Me.CastTimeLeft() > 0 and mq.TLO.Target.Type() == 'Corpse' then
        mq.cmdf('/rs CHChain: Target died, interrupting cast')
        casting.interrupt()
        mq.cmdf('/rs <<Go %s>>', p.chnextclr)
        state.clearRunState()
        return
    end
    if mq.gettime() >= (p.deadline or 0) then
        mq.cmdf('/rs <<Go %s>>', p.chnextclr)
        state.clearRunState()
        return
    end
    if not mq.TLO.Me.Sitting() and (mq.TLO.Me.CastTimeLeft() or 0) == 0 then
        mq.cmd('/sit on')
    end
end

function chchain.getHookFn(name)
    if name == 'chchainTick' then
        return function(hookName)
            if state.getRunState() ~= state.STATES.chchain then return end
            chchain.Tick()
        end
    end
    return nil
end

return chchain
