local mq = require('mq')
local botconfig = require('lib.config')
local combat = require('lib.combat')
local state = require('lib.state')
local targeting = require('lib.targeting')
local botmove = require('botmove')
local charinfo = require('actornet.charinfo')
local myconfig = botconfig.config
local botmelee = {}

function botmelee.LoadMeleeConfig()
    if (myconfig.melee.stickcmd == nil) then myconfig.melee.stickcmd = 'hold uw 7' end
    if (myconfig.melee.offtank == nil) then myconfig.melee.offtank = false end
    if (myconfig.melee.otoffset == nil) then myconfig.melee.otoffset = 0 end
    if (myconfig.melee.minmana == nil) then myconfig.melee.minmana = 0 end
    if (myconfig.melee.assistpct == nil) then myconfig.melee.assistpct = 99 end
end

botconfig.RegisterConfigLoader(function() if botconfig.config.settings.domelee then botmelee.LoadMeleeConfig() end end)

mobprobtimer = 0

-- When I am tank and my target is a PC: clear combat state.
local function clearTankCombatState()
    state.getRunconfig().acmatarget = nil
    combat.ResetCombatState()
end

-- When I am tank (and raid/group/MT): pick target from MobList. Returns tanktar, newacmafound.
local function selectTankTarget(tank)
    local tanktar = nil
    local newacmafound = false
    if tank ~= mq.TLO.Me.Name() then return nil, false end
    if not (mq.TLO.Raid.Members() or not mq.TLO.Group() or mq.TLO.Group.MainTank() == mq.TLO.Me.Name()) then return nil, false end
    if mq.TLO.Me.Combat() then return nil, false end
    if debug then print('tanklogic') end
    for _, v in ipairs(state.getRunconfig().MobList) do
        if v.LineOfSight() then
            if tanktar then
                if v.ID() == state.getRunconfig().acmatarget then
                    tanktar = v
                    newacmafound = true
                end
                if v.Distance() < tanktar.Distance() then
                    tanktar = v
                end
            else
                tanktar = v
            end
        end
    end
    return tanktar, newacmafound
end

-- Offtank: get tank's target; choose Nth non-tank target or assist tank. Sets acmatarget.
local function resolveOfftankTarget(tank, assistpct)
    if debug then print('offtank logic') end
    local actarid
    local acname
    local tanktarid = nil
    local tankinfo = charinfo.GetInfo(tank)
    if tankinfo and tankinfo.ID then
        tanktarid = tankinfo.Target and tankinfo.Target.ID or nil
    elseif mq.TLO.Spawn('pc =' .. tank).ID() then
        tanktarid = botmelee.GetTankTar(tank)
    end
    local otcounter = 0
    for _, v in ipairs(state.getRunconfig().MobList) do
        if v.ID() ~= tanktarid and not actarid then
            if otcounter == myconfig.melee.otoffset then
                actarid = v.ID()
                acname = v.CleanName()
            end
            otcounter = otcounter + 1
        end
    end
    if debug then print('offtank target: ', actarid) end
    if actarid then
        if actarid ~= mq.TLO.Target.ID() then
            printf('\ayCZBot:\ax\arOff-tanking\ax a \ag%s id %s', acname, actarid)
        end
        state.getRunconfig().acmatarget = actarid
    elseif tankinfo and tankinfo.TargetHP and (tankinfo.TargetHP <= assistpct) then
        if tanktarid > 0 then state.getRunconfig().acmatarget = tanktarid else state.getRunconfig().acmatarget = nil end
        if debug then print('nothing to offtank, acmatarget: ', state.getRunconfig().acmatarget) end
    end
end

-- Melee assist: sync acmatarget to tank's target when tank is engaging.
local function resolveMeleeAssistTarget(tank, assistpct)
    if debug then print('meleelogic') end
    local info = charinfo.GetInfo(tank)
    local tanktarid = info and info.Target and info.Target.ID or nil
    if info and info.ID and (state.getRunconfig().acmatarget ~= tanktarid) then state.getRunconfig().acmatarget = nil end
    for _, v in ipairs(state.getRunconfig().MobList) do
        if v.ID() == tanktarid and info and info.TargetHP and (info.TargetHP <= assistpct) then
            state.getRunconfig().acmatarget = tanktarid
        end
    end
    if not (info and info.ID) then
        state.getRunconfig().acmatarget = botmelee.GetTankTar(tank)
    end
end

-- When acmatarget is set: pet attack, target (via targeting lib), stand, attack on, stick. Uses targeting state + melee phase moving_closer; no mq.delay.
local function engageTarget()
    local acmatarget = state.getRunconfig().acmatarget
    if not acmatarget then return end

    if targeting.IsActive() then
        return
    end

    if state.getRunState() == 'melee' then
        local p = state.getRunStatePayload()
        if p and p.phase == 'moving_closer' then
            if mq.TLO.Target.Distance() and mq.TLO.Target.Distance() < mq.TLO.Target.MaxMeleeTo() then
                state.setRunState('melee', { phase = 'idle' })
                return
            end
            if p.deadline and mq.gettime() >= p.deadline then
                state.setRunState('melee', { phase = 'idle' })
                return
            end
            return
        end
    end

    if mq.TLO.Me.Pet.ID() and myconfig.settings.petassist and not mq.TLO.Pet.Aggressive() then
        mq.cmdf('/pet attack %s', acmatarget)
    end

    if not myconfig.settings.domelee then return end

    if mq.TLO.Target.ID() ~= acmatarget then
        targeting.SetTarget(acmatarget, 500)
        return
    end

    if mq.TLO.Navigation.Active() then mq.cmd('/nav stop') end
    if mq.TLO.Me.Sitting() then mq.cmd('/stand on') end
    if not mq.TLO.Me.Combat() then mq.cmd('/squelch /attack on') end
    if not mq.TLO.Stick.Active() or (mq.TLO.Stick.StickTarget() ~= acmatarget) then
        mq.cmdf('/squelch /multiline ; /attack on ; /stick %s', myconfig.melee.stickcmd)
    end

    if mq.TLO.Me.Class.ShortName() ~= 'BRD' then
        state.setRunState('melee', { phase = 'moving_closer', deadline = mq.gettime() + 5000 })
    end
end

-- When no acmatarget: stick off, attack off, pet back, clear NPC target.
local function disengageCombat()
    combat.ResetCombatState()
end

function botmelee.AdvCombat()
    if debug then print('melee called') end
    local tank = state.getRunconfig().TankName
    local assistpct = myconfig.melee.assistpct or 99

    if tank == mq.TLO.Me.Name() and mq.TLO.Target.Master.Type() == 'PC' then
        clearTankCombatState()
    end

    local tanktar, newacmafound = selectTankTarget(tank)
    if tanktar then
        if tanktar.ID() then
            state.getRunconfig().acmatarget = tanktar.ID()
        end
    end

    if newacmafound then
        botmove.StartReturnToFollowAfterACMA()
    end

    if (myconfig.melee.offtank and tank ~= mq.TLO.Me.Name()) then
        resolveOfftankTarget(tank, assistpct)
    end

    if not myconfig.melee.offtank and not (tank == mq.TLO.Me.Name()) then
        resolveMeleeAssistTarget(tank, assistpct)
    end

    if state.getRunconfig().acmatarget then
        engageTarget()
    else
        disengageCombat()
    end
end

-- Get tank's target when tank is not on actornet: use /assist, wait (melee phase targeting), then return
-- target ID only if it's in MobList (camp/acleash valid mobs). Uses melee state + phase; no mq.delay.
function botmelee.GetTankTar(tank)
    if debug then print('gettanktar sub called') end
    if not tank or not mq.TLO.Spawn('pc =' .. tank).ID() then return nil end

    if state.getRunState() == 'melee' then
        local p = state.getRunStatePayload()
        if p and p.phase == 'targeting' and p.tank then
            if p.tank ~= tank then
                state.setRunState('melee', { phase = 'idle' })
                return nil
            end
            if p.deadline and mq.gettime() < p.deadline then
                return nil
            end
            state.setRunState('melee', { phase = 'idle' })
            for _, v in ipairs(state.getRunconfig().MobList) do
                if mq.TLO.Target.ID() == v.ID() then return mq.TLO.Target.ID() end
            end
            return nil
        end
    end

    if mq.TLO.Me.Assist() then mq.cmd('/squelch /assist off') end
    mq.cmdf('/assist %s', tank)
    state.setRunState('melee', { phase = 'targeting', tank = tank, deadline = mq.gettime() + 500 })
    return nil
end

do
    local hookregistry = require('lib.hookregistry')
    hookregistry.registerMainloopHook('doMelee', function()
        if state.getRunState() == 'acma_return_follow' then
            botmove.TickReturnToFollowAfterACMA()
            return
        end
        if not myconfig.settings.domelee or not state.getRunconfig().MobList[1] then
            state.clearRunState()
            return
        end
        local payload = (state.getRunState() == 'melee') and state.getRunStatePayload() or nil
        state.setRunState('melee', payload and payload or { phase = 'idle' })
        if state.getRunconfig().TankName == mq.TLO.Me.Name() then
            botmelee.AdvCombat()
            return
        end
        if myconfig.melee.minmana == 0 then
            botmelee.AdvCombat()
            return
        end
        if (tonumber(myconfig.melee.minmana) < mq.TLO.Me.PctMana() or mq.TLO.Me.MaxMana() == 0) then
            botmelee.AdvCombat()
        end
    end, 600)
end

return botmelee
