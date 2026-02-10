local mq = require('mq')
local botconfig = require('lib.config')
local combat = require('lib.combat')
local state = require('lib.state')
local bothooks = require('lib.bothooks')
local spawnutils = require('lib.spawnutils')
local botmelee = require('botmelee')
local botmove = require('botmove')
local utils = require('lib.utils')
local charinfo = require("mqcharinfo")
local myconfig = botconfig.config

local botpull = {}
local bardtwist = require('lib.bardtwist')

local function clearPullState()
    local rc = state.getRunconfig()
    rc.pullState = nil
    rc.pullAPTargetID = nil
    rc.pullTagTimer = nil
    rc.pullReturnTimer = nil
    rc.pullPhase = nil
    rc.pullDeadline = nil
    rc.statusMessage = ''
    state.clearRunState()
    if mq.TLO.Me.Class.ShortName() == 'BRD' then
        bardtwist.EnsureTwistForMode('combat')
    end
end

function botpull.LoadPullConfig()
    state.getRunconfig().pulledmob = nil
    state.getRunconfig().pullreturntimer = nil
    if not state.getRunconfig().pullarc then state.getRunconfig().pullarc = nil end
end

botconfig.RegisterConfigLoader(function() if botconfig.config.settings.dopull then botpull.LoadPullConfig() end end)

function botpull.TagTimeCalc(trip, spawnId, x, y, z)
    if trip == 'pull' and spawnId then
        return (((mq.TLO.Navigation.PathLength('id ' .. spawnId)() + 100) / 100) * 9000) + mq.gettime()
    end
    if trip == 'return' and x and y and z then
        return (((mq.TLO.Navigation.PathLength('locxyz ' .. x .. ',' .. y .. ',' .. z)() + 100) / 100) * 18000) +
        mq.gettime()
    end
    return mq.gettime() + 60000
end

function botpull.SetPullArc(arc)
    local rc = state.getRunconfig()
    if not arc and rc.pullarc then
        mq.cmd('/echo \arTurning off Directional Pulling.')
        rc.pullarc = 0
    else
        rc.pullarc = tonumber(arc)
    end
    if arc then printf('Setting Pull Arc to %s at heading %s', arc, mq.TLO.Me.Heading.Degrees()) end -- not debug, keep
end

function botpull.FTECheck(spawnid)
    return spawnutils.FTECheck(spawnid, state.getRunconfig())
end

function botpull.EngageCheck()
    local target = mq.TLO.Target.CleanName()
    local targetid = mq.TLO.Target.ID()
    local tartar = mq.TLO.Me.TargetOfTarget()
    local tartarid = mq.TLO.Me.TargetOfTarget.ID()
    local tartartype = mq.TLO.Spawn(tartarid).Type()
    local info = tartar and charinfo.GetInfo(tartar)
    local bot = info and info.ID
    local rc = state.getRunconfig()
    if bot then
        local targetdist = utils.calcDist3D(mq.TLO.Spawn(targetid).X(), mq.TLO.Spawn(targetid).Y(),
            mq.TLO.Spawn(targetid).Z(), rc.makecamp.x, rc.makecamp.y, rc.makecamp.z)
        if targetdist and targetdist > 200 and not myconfig.pull.hunter then return false end
    end
    if tartarid and tartarid > 0 and tartarid ~= mq.TLO.Me.ID() and (mq.TLO.Spawn(tartarid).Type() ~= 'NPC') and tartartype ~= 'Corpse' then
        printf('\ayCZBot:\ax\arUh Oh, \ag%s\ax is \arengaged\ax by someone else! Returning to camp!', target)
        rc.engagetracker[targetid] = (mq.gettime() + 60000)
        mq.cmd('/multiline ; /squelch /target clear ; /nav stop log=off')
        return true
    end
    return false
end

-- Pre-checks: return false if we should not start a pull.
local function canStartPull(rc)
    if rc.pulledmob and mq.TLO.Spawn(rc.pulledmob).Distance3D() and mq.TLO.Spawn(rc.pulledmob).Distance3D() >= myconfig.settings.acleash then
        if rc.pullreturntimer and rc.pullreturntimer >= mq.gettime() then return false end
        rc.pulledmob = nil
    end
    if MasterPause then return false end
    if mq.TLO.Me.PctHPs() and mq.TLO.Me.PctHPs() <= 45 then return false end
    if not mq.TLO.Navigation.MeshLoaded() then
        printf(
        '\ayCZBot:\axI have DoPull set TRUE but have \arno MQ2Nav Mesh loaded\ax, please generate a NavMesh before using DoPull, \arsetting DoPull to FALSE\ax')
        myconfig.settings.dopull = false
        return false
    end
    if mq.TLO.Group() then
        for iter = 1, mq.TLO.Group() do
            local grpname = mq.TLO.Group.Member(iter)
            if grpname.Type() and string.lower(grpname.Type()) == 'corpse' then return false end
            if myconfig.pull.mana and grpname.Class.ShortName() and string.find(myconfig.pull.manaclass, string.lower(grpname.Class.ShortName())) then
                if grpname.PctMana() and myconfig.pull.mana > grpname.PctMana() then return false end
            end
        end
    end
    return true
end

-- Camp/hunter setup and mapfilter; no mq.delay.
local function ensureCampAndAnchor(rc)
    mq.cmdf('/squelch /mapfilter SpellRadius %s', myconfig.pull.radius)
    mq.cmdf('/squelch /mapfilter CastRadius %s', mq.TLO.Spell(myconfig.pull.pullability).MyRange())
    if not myconfig.pull.hunter and not rc.campstatus then botmove.MakeCamp('on') end
    if myconfig.pull.hunter and (not rc.makecamp.x or not rc.makecamp.y) then
        mq.cmd('/echo setting HunterMode anchor')
        botmove.SetCampHere()
        if rc.campstatus then botmove.MakeCamp('off') end
    end
    if myconfig.pull.hunter and rc.campstatus then
        print('Disabling makecamp because dopull is on with HunterMode enabled') -- not debug, real error message
        botmove.MakeCamp('off')
    end
end

-- Pick one spawn from list (closest by path length; priority list if usepriority).
local function selectPullTarget(apmoblist, rc)
    if not apmoblist or not apmoblist[1] then return nil end
    local pathlengthlist = {}
    for _, v in ipairs(apmoblist) do
        pathlengthlist[v.ID()] = mq.TLO.Navigation.PathLength('id ' .. v.ID())()
    end
    local pulltar, pulltardist = nil, nil
    for k, v in pairs(pathlengthlist) do
        if v and v > 0 and (not pulltardist or pulltardist >= v) then
            pulltardist = v
            pulltar = k
        end
    end
    if not pulltar then return nil end
    local pullindex = nil
    for k, v in ipairs(apmoblist) do
        if v.ID() == pulltar then
            pullindex = k
            break
        end
    end
    if not pullindex then return nil end
    local chosen = apmoblist[pullindex]
    if myconfig.pull.usepriority and rc.PriorityList and #rc.PriorityList > 0 then
        for _, v in ipairs(apmoblist) do
            local name = v.CleanName()
            for _, n in ipairs(rc.PriorityList) do
                if n == name then return v end
            end
        end
    end
    return chosen
end

function botpull.StartPull()
    local rc = state.getRunconfig()
    if not canStartPull(rc) then return end
    ensureCampAndAnchor(rc)
    local apmoblist = spawnutils.buildPullMobList(rc)
    local spawn = selectPullTarget(apmoblist, rc)
    if not spawn then return end

    local distance = spawn.Distance() and math.floor(spawn.Distance()) or 0
    printf('\ayCZBot:\axAttempting to pull \ar%s \arid %s \auat %s', spawn.Name(), spawn.ID(), distance)
    mq.cmd('/multiline ; /attack off ; /stick off ; /squelch /target clear')
    mq.cmdf('/nav id %s dist= 7 log=off los=on', spawn.ID())
    if string.lower(myconfig.pull.pullability) == 'warp' then mq.cmdf('/warp id %s', spawn.ID()) end

    rc.pullAPTargetID = spawn.ID()
    rc.pullTagTimer = botpull.TagTimeCalc('pull', spawn.ID())
    rc.pullReturnTimer = botpull.TagTimeCalc('return', nil, rc.makecamp.x, rc.makecamp.y, rc.makecamp.z)
    rc.pullState = 'navigating'
    rc.pullPhase = nil
    rc.pullDeadline = nil
    state.setRunState('pulling', { priority = bothooks.getPriority('doPull') })
    rc.statusMessage = string.format('Pulling %s (%s)', spawn.Name(), spawn.ID())
    if mq.TLO.Me.Class.ShortName() == 'BRD' then
        bardtwist.EnsureTwistForMode('pull')
    end
end

-- One tick of navigating state.
local function tickNavigating(rc, spawn)
    if rc.pullTagTimer and mq.gettime() >= rc.pullTagTimer then
        printf('\ayCZBot:\ax\arI have timed out trying to pull \ay%s', spawn.Name())
        if string.lower(myconfig.pull.pullability) == 'warp' then
            mq.cmdf('/warp loc %s %s %s', rc.makecamp.y, rc.makecamp.x, rc.makecamp.z)
        end
        clearPullState()
        return
    end
    if mq.TLO.Me.PctHPs() and mq.TLO.Me.PctHPs() <= 45 then
        clearPullState()
        return
    end
    if rc.campstatus and utils.calcDist3D(rc.makecamp.x, rc.makecamp.y, rc.makecamp.z, mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()) > (myconfig.pull.radius + 40) then
        clearPullState()
        return
    end
    if (spawn.Distance() and spawn.Distance() <= 200 and spawn.LineOfSight()) or (mq.TLO.Target.ID() == rc.pullAPTargetID) then
        if mq.TLO.Target.ID() ~= rc.pullAPTargetID then
            mq.cmdf('/squelch /tar id %s', rc.pullAPTargetID)
        end
        if mq.TLO.Me.TargetOfTarget.ID() and mq.TLO.Target.ID() and mq.TLO.Target.Type() == 'NPC' and spawn.Distance() and spawn.Distance() <= 200 then
            if botpull.EngageCheck() then
                clearPullState()
                return
            end
        end
        if spawn.Distance() and spawn.Distance() < myconfig.pull.abilityrange and spawn.LineOfSight() then
            rc.pullState = 'aggroing'
            rc.pullPhase = 'aggro_wait_target'
            rc.pullDeadline = mq.gettime() + 1000
            mq.cmd('/nav stop log=off')
            mq.cmdf('/squelch /tar id %s', rc.pullAPTargetID)
            if mq.TLO.Me.Class.ShortName() == 'BRD' then
                local eg = bardtwist.GetEngageGem()
                if eg then bardtwist.SetTwistOnceGem(eg) end
            end
            return
        end
    end
    if not mq.TLO.Navigation.Active() and spawn.Distance() and spawn.Distance() > myconfig.pull.abilityrange then
        mq.cmdf('/nav id %s dist= 7 log=off los=on', rc.pullAPTargetID)
    end
end

-- One tick of aggroing state (with sub-phases aggro_wait_target, aggro_wait_cast, aggro_wait_stop_moving).
local function tickAggroing(rc, spawn)
    if rc.pullPhase == 'aggro_wait_target' then
        if mq.gettime() >= (rc.pullDeadline or 0) then
            clearPullState()
            return
        end
        if mq.TLO.Target.ID() ~= rc.pullAPTargetID then return end
        rc.pullPhase = nil
    end
    if rc.pullPhase == 'aggro_wait_cast' then
        if mq.TLO.Me.CastTimeLeft() and mq.TLO.Me.CastTimeLeft() > 0 then return end
        rc.pullPhase = nil
    end
    if rc.pullPhase == 'aggro_wait_stop_moving' then
        if mq.gettime() >= (rc.pullDeadline or 0) or not mq.TLO.Me.Moving() then
            rc.pullPhase = nil
        else
            return
        end
    end

    if spawn.Aggressive() then
        rc.pullState = 'returning'
        rc.pullPhase = nil
        rc.pulledmob = rc.pullAPTargetID
        rc.pullreturntimer = mq.gettime() + 60000
        combat.ResetCombatState({ clearTarget = false, clearPet = false })
        botmove.NavToCamp({ dist = 0, echoMsg = '\\ayReturning to camp' })
        return
    end

    local pullab = myconfig.pull.pullability
    if rc.pullPhase then return end

    if mq.TLO.Me.CombatAbilityReady(pullab)() then
        mq.cmdf('/multiline ; /nav stop log=off ; /disc %s', pullab)
        if not mq.TLO.Stick.Active() then mq.cmdf('/stick 5 uw moveback id %s', spawn.ID()) end
        return
    end
    if mq.TLO.Me.AbilityReady(pullab)() then
        mq.cmdf('/multiline ; /nav stop log=off ; /attack on ; /doability %s', pullab)
        if not mq.TLO.Stick.Active() then mq.cmdf('/stick 5 uw moveback id %s', spawn.ID()) end
        return
    end
    if mq.TLO.Me.AltAbilityReady(pullab)() then
        mq.cmd('/nav stop log=off')
        if mq.TLO.Me.Moving() then
            rc.pullPhase = 'aggro_wait_stop_moving'
            rc.pullDeadline = mq.gettime() + 2000
            return
        end
        mq.cmdf('/multiline ; /nav stop log=off ; /alt act %s', mq.TLO.Me.AltAbility(pullab)())
        rc.pullPhase = 'aggro_wait_cast'
        rc.pullDeadline = mq.gettime() + 8000
        return
    end
    if mq.TLO.Me.Gem(pullab)() and mq.TLO.Me.SpellReady(pullab)() then
        mq.cmd('/nav stop log=off')
        if mq.TLO.Me.Moving() then
            rc.pullPhase = 'aggro_wait_stop_moving'
            rc.pullDeadline = mq.gettime() + 2000
            return
        end
        mq.cmdf('/multiline ; /nav stop log=off ; /casting "%s"', pullab or 'melee')
        rc.pullPhase = 'aggro_wait_cast'
        rc.pullDeadline = mq.gettime() + 8000
        return
    end
    if string.lower(pullab or '') == 'ranged' then
        mq.cmdf('/multiline ; /squelch /nav stop log=off ; /face fast ; /squelch attack off ; /ranged on')
        return
    end
    if string.lower(pullab or '') == 'melee' or string.lower(pullab or '') == 'warp' then
        mq.cmd('/multiline ; /squelch /nav stop log=off ; /attack on')
        if not mq.TLO.Stick.Active() then mq.cmdf('/stick 5 uw moveback id %s', tostring(spawn.ID())) end
        return
    end
    if not spawn.Aggressive() and mq.TLO.Target.ID() == spawn.ID() and (not mq.TLO.Stick.Active() or not spawn.LineOfSight()) then
        mq.cmdf('/nav id %s dist=5 log=off los=on', tostring(spawn.ID()))
    end
end

-- One tick of returning state.
local function tickReturning(rc, spawn)
    if not mq.TLO.Navigation.Active() then
        rc.pullState = 'waiting_combat'
        return
    end
    if rc.pullReturnTimer and mq.gettime() >= rc.pullReturnTimer then
        clearPullState()
        return
    end
    if myconfig.pull.pullability == 'warp' then
        mq.cmdf('/warp loc %s %s %s', rc.makecamp.y, rc.makecamp.x, rc.makecamp.z)
        clearPullState()
        return
    end
    if spawn.Distance() and spawn.Distance() > myconfig.pull.leash and not mq.TLO.Navigation.Paused() then
        mq.cmd('/nav pause on log=off')
    elseif spawn.Distance() and spawn.Distance() < myconfig.pull.leash and mq.TLO.Navigation.Paused() then
        mq.cmd('/nav pause off log=off')
    end
    if mq.TLO.Me.CombatState() == 'COMBAT' then
        rc.pullState = 'waiting_combat'
    end
end

-- One tick of waiting_combat state.
local function tickWaitingCombat(rc)
    local function isAPTarInCamp()
        for _, v in ipairs(rc.MobList or {}) do
            if v.ID() == rc.pullAPTargetID then return true end
        end
        return false
    end
    if (rc.MobList and rc.MobList[1]) and myconfig.settings.domelee then botmelee.AdvCombat() end
    if isAPTarInCamp() or (rc.pullReturnTimer and mq.gettime() >= rc.pullReturnTimer) then
        clearPullState()
    end
end

function botpull.PullTick()
    local rc = state.getRunconfig()
    if not rc.pullState or not rc.pullAPTargetID then return end
    local spawn = mq.TLO.Spawn(rc.pullAPTargetID)
    if not spawn or not spawn.ID() or spawn.Type() == 'Corpse' then
        clearPullState()
        return
    end
    if MasterPause then
        clearPullState()
        return
    end

    if rc.pullState == 'navigating' then
        tickNavigating(rc, spawn)
        return
    end
    if rc.pullState == 'aggroing' then
        tickAggroing(rc, spawn)
        return
    end
    if rc.pullState == 'returning' then
        tickReturning(rc, spawn)
        return
    end
    if rc.pullState == 'waiting_combat' then
        tickWaitingCombat(rc)
    end
end

function botpull.getHookFn(name)
    if name == 'doPull' then
        return function(hookName)
            if not myconfig.settings.dopull then return end
            if utils.isNonCombatZone(mq.TLO.Zone.ShortName()) then return end
            if state.getRunState() == 'raid_mechanic' then return end
            if state.getRunState() == 'pulling' then
                botpull.PullTick()
                return
            end
            if state.getRunconfig().MobCount <= myconfig.pull.chainpullcnt or myconfig.pull.chainpullcnt == 0 then
                if mq.TLO.Spawn(state.getRunconfig().engageTargetId).PctHPs() then
                    local tempcnt = myconfig.pull.chainpullcnt == 0 and (myconfig.pull.chainpullcnt + 1) or
                    myconfig.pull.chainpullcnt
                    if (tonumber(mq.TLO.Spawn(state.getRunconfig().engageTargetId).PctHPs()) <= myconfig.pull.chainpullhp) and state.getRunconfig().MobCount <= tempcnt then
                        botpull.StartPull()
                    end
                end
            end
            if (state.getRunconfig().MobCount < myconfig.pull.chainpullcnt) then botpull.StartPull() end
            if (state.getRunconfig().MobCount == 0) and not state.getRunconfig().engageTargetId then botpull.StartPull() end
        end
    end
    return nil
end

return botpull
