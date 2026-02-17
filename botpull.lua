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

local PULLEDMOB_NO_CLOSER_MS = 10000

--- Returns effective pull range in units for the given pull spell entry.
local function getPullRange(entry)
    if not entry then return 50 end
    if entry.range and type(entry.range) == 'number' and entry.range > 0 then return entry.range end
    local gem = entry.gem
    local spell = entry.spell
    if gem == 'melee' then return 10 end
    if gem == 'ranged' then
        if spell and spell ~= '' and mq.TLO.FindItem(spell)() then
            local r = mq.TLO.FindItem(spell).Range()
            if r and r > 0 then return r end
        end
        return entry.range and entry.range > 0 and entry.range or 200
    end
    if type(gem) == 'number' and gem >= 1 and gem <= 12 then
        local name = spell or (mq.TLO.Me.Gem(gem)())
        if name and name ~= '' then
            local r = mq.TLO.Spell(name).MyRange()
            if r and r > 0 then return math.max(0, r - 5) end
        end
    end
    if gem == 'item' and spell and mq.TLO.FindItem(spell)() then
        local r = mq.TLO.FindItem(spell).Spell.MyRange()
        if r and r > 0 then return r end
    end
    if gem == 'alt' and spell and mq.TLO.Me.AltAbility(spell)() then
        local r = mq.TLO.Me.AltAbility(spell).Spell.MyRange()
        if r and r > 0 then return r end
    end
    if gem == 'ability' then
        return entry.range and entry.range > 0 and entry.range or 10
    end
    if gem == 'disc' then
        if spell and spell ~= '' then
            local r = mq.TLO.Spell(spell).MyRange()
            if r and r > 0 then return r end
        end
        return entry.range and entry.range > 0 and entry.range or 50
    end
    if gem == 'script' then
        return entry.range and entry.range > 0 and entry.range or 50
    end
    return 50
end

local function getEffectiveAbilityRange()
    local entry = botpull.GetPullSpell()
    return getPullRange(entry)
end

local function clearPullState(reason)
    if reason then printf('\ayCZBot:\ax [Pull] clearPullState: %s', reason) else printf('\ayCZBot:\ax [Pull] clearPullState: (no reason)') end
    local rc = state.getRunconfig()
    rc.pullState = nil
    rc.pullAPTargetID = nil
    rc.pullTagTimer = nil
    rc.pullReturnTimer = nil
    rc.pullPhase = nil
    rc.pullDeadline = nil
    rc.statusMessage = ''
    rc.pullHealerManaWait = nil
    rc.pulledmobLastDistSq = nil
    rc.pulledmobLastCloserTime = nil
    rc.pullNavStartHP = nil
    rc.pullAggroingStartTime = nil
    state.clearRunState()
    if mq.TLO.Me.Class.ShortName() == 'BRD' then
        bardtwist.EnsureTwistForMode('combat')
    end
end

function botpull.LoadPullConfig()
    local rc = state.getRunconfig()
    rc.pulledmob = nil
    rc.pullreturntimer = nil
    rc.pulledmobLastDistSq = nil
    rc.pulledmobLastCloserTime = nil
    if not rc.pullarc then rc.pullarc = nil end
end

botconfig.RegisterConfigLoader(function() botpull.LoadPullConfig() end)

--- Returns the single pull spell block from config, or nil if missing/empty (treat as melee).
function botpull.GetPullSpell()
    local pull = myconfig.pull
    if not pull or not pull.spell or type(pull.spell) ~= 'table' then return nil end
    local ps = pull.spell
    if not ps or (ps.gem == nil and ps.spell == nil) then return nil end
    return ps
end

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
    local tarSpawn = mq.TLO.Target

    local target = tarSpawn.CleanName()
    local targetid = tarSpawn.ID()
    if not targetid or targetid == 0 then return false end
    if not mq.TLO.Me.TargetOfTarget.ID() or mq.TLO.Me.TargetOfTarget.ID() == 0 then return false end
    local totSpawn = mq.TLO.Me.TargetOfTarget
    local totID = totSpawn.ID()
    local totType = totSpawn.Type()
    local info = totSpawn and charinfo.GetInfo(totID)
    local bot = info and info.ID
    local rc = state.getRunconfig()
    if bot then
        local tspawn = mq.TLO.Spawn(targetid)
        local targetDistSq = utils.getDistanceSquared3D(tspawn.X(), tspawn.Y(), tspawn.Z(), rc.makecamp.x, rc.makecamp.y, rc.makecamp.z)
        local range = getEffectiveAbilityRange()
        local rangeSq = range and (range * range) or nil
        if targetDistSq and rangeSq and targetDistSq > rangeSq and not myconfig.pull.hunter then return false end
    end
    if totID and totID > 0 and totID ~= mq.TLO.Me.ID() and (totType ~= 'NPC') and totType ~= 'Corpse' then
        printf('\ayCZBot:\ax\arUh Oh, \ag%s\ax is \arengaged\ax by someone else! Returning to camp!', target)
        rc.engagetracker[targetid] = (mq.gettime() + 60000)
        mq.cmd('/multiline ; /squelch /target clear ; /nav stop log=off')
        return true
    end
    return false
end

-- Pre-checks: return false if we should not start a pull.
local function canStartPull(rc)
    rc.pullHealerManaWait = nil
    if rc.pulledmob then
        local pmob = mq.TLO.Spawn(rc.pulledmob)
        if not pmob or not pmob.ID() or pmob.Type() == 'Corpse' then
            rc.pulledmob = nil
            rc.pulledmobLastDistSq = nil
            rc.pulledmobLastCloserTime = nil
        else
            local pulledDistSq = utils.getDistanceSquared3D(mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z(), pmob.X(), pmob.Y(), pmob.Z())
            if not pulledDistSq or not myconfig.settings.acleashSq then
                -- no distance or no acleash, clear and continue
                rc.pulledmob = nil
                rc.pulledmobLastDistSq = nil
                rc.pulledmobLastCloserTime = nil
            elseif pulledDistSq < myconfig.settings.acleashSq then
                -- inside acleash: mob at camp, clear and allow pull (hook decides if StartPull or doMelee)
                rc.pulledmob = nil
                rc.pulledmobLastDistSq = nil
                rc.pulledmobLastCloserTime = nil
            else
                -- outside acleash: only clear if mob hasn't gotten closer for 10s
                local lastDistSq = rc.pulledmobLastDistSq or math.huge
                if pulledDistSq < lastDistSq then
                    rc.pulledmobLastDistSq = pulledDistSq
                    rc.pulledmobLastCloserTime = mq.gettime()
                    return false
                end
                if rc.pulledmobLastDistSq == nil then
                    rc.pulledmobLastDistSq = pulledDistSq
                    rc.pulledmobLastCloserTime = mq.gettime()
                    return false
                end
                local now = mq.gettime()
                if (now - (rc.pulledmobLastCloserTime or 0)) > PULLEDMOB_NO_CLOSER_MS then
                    rc.pulledmob = nil
                    rc.pulledmobLastDistSq = nil
                    rc.pulledmobLastCloserTime = nil
                else
                    return false
                end
            end
        end
    end
    if MasterPause then return false end
    if mq.TLO.Me.PctHPs() and mq.TLO.Me.PctHPs() <= 45 then return false end
    if not mq.TLO.Navigation.MeshLoaded() then
        printf(
            '\ayCZBot:\axI have DoPull set TRUE but have \arno MQ2Nav Mesh loaded\ax, please generate a NavMesh before using DoPull, \arsetting DoPull to FALSE\ax')
        state.getRunconfig().dopull = false
        return false
    end
    if mq.TLO.Group() then
        for iter = 1, mq.TLO.Group() do
            local grpSpawn = mq.TLO.Group.Member(iter).Spawn
            if not grpSpawn.ID() or grpSpawn.ID() == 0 then return false end
            local grpType = grpSpawn.Type()
            if grpType and string.lower(grpType) == 'corpse' then return false end
            if myconfig.pull.mana and grpSpawn.Class.ShortName() and type(myconfig.pull.manaclass) == 'table' then
                local grpClass = string.upper(grpSpawn.Class.ShortName() or '')
                for _, entry in ipairs(myconfig.pull.manaclass) do
                    if string.upper(tostring(entry)) == grpClass then
                        if grpSpawn.PctMana() and myconfig.pull.mana > grpSpawn.PctMana() then
                            rc.pullHealerManaWait = { name = grpSpawn.CleanName() or 'healer', pct = myconfig.pull.mana }
                            return false
                        end
                        break
                    end
                end
            end
        end
    end
    return true
end



-- Camp/hunter setup and mapfilter; no mq.delay.
local function ensureCampAndAnchor(rc)
    mq.cmdf('/squelch /mapfilter SpellRadius %s', myconfig.pull.radius)
    local castRadius = getEffectiveAbilityRange()
    mq.cmdf('/squelch /mapfilter CastRadius %s', castRadius)
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

    local entry = botpull.GetPullSpell()
    local isWarp = entry and entry.gem == 'script' and entry.spell and string.lower(tostring(entry.spell)) == 'warp'

    local distance = spawn.Distance() and math.floor(spawn.Distance()) or 0
    printf('\ayCZBot:\axAttempting to pull \ar%s \arid %s \auat %s', spawn.Name(), spawn.ID(), distance)
    mq.cmd('/multiline ; /attack off ; /stick off ; /squelch /target clear')
    mq.cmdf('/nav id %s dist= 7 log=off los=on', spawn.ID())
    if isWarp then mq.cmdf('/warp id %s', spawn.ID()) end

    rc.pullAPTargetID = spawn.ID()
    rc.pullTagTimer = botpull.TagTimeCalc('pull', spawn.ID())
    rc.pullReturnTimer = botpull.TagTimeCalc('return', nil, rc.makecamp.x, rc.makecamp.y, rc.makecamp.z)
    rc.pullState = 'navigating'
    rc.pullPhase = nil
    rc.pullDeadline = nil
    rc.pullNavStartHP = mq.TLO.Me.PctHPs()
    state.setRunState('pulling', { priority = bothooks.getPriority('doPull') })
    rc.statusMessage = string.format('Pulling %s (%s)', spawn.Name(), spawn.ID())
    if mq.TLO.Me.Class.ShortName() == 'BRD' then
        bardtwist.EnsureTwistForMode('pull')
    end
end

local function isPullWarp()
    local entry = botpull.GetPullSpell()
    return entry and entry.gem == 'script' and entry.spell and string.lower(tostring(entry.spell)) == 'warp'
end

local function abortPullAndReturnToCamp(reason)
    mq.cmd('/multiline ; /squelch /target clear ; /nav stop log=off')
    botmove.NavToCamp({ dist = 0, echoMsg = '\\ayAdd aggro, returning to camp' })
    clearPullState(reason or 'abort')
    if reason then printf('\ayCZBot:\ax [Pull] abort: %s', reason) end
end

-- One tick of navigating state.
local function tickNavigating(rc, spawn)
    local spawnDistSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), spawn.X(), spawn.Y())
    local range = getEffectiveAbilityRange() or 0
    local rangeSq = range * range
    local inRange2D = spawnDistSq and rangeSq and spawnDistSq <= rangeSq
    local spawnLoS = spawn.LineOfSight()
    local haveTarget = (mq.TLO.Target.ID() == rc.pullAPTargetID)
    local outsideCamp = nil
    if rc.campstatus then
        local meToCampSq = utils.getDistanceSquared3D(rc.makecamp.x, rc.makecamp.y, rc.makecamp.z, mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z())
        outsideCamp = meToCampSq and myconfig.pull.radiusPlus40Sq and meToCampSq > myconfig.pull.radiusPlus40Sq
    end
    printf('\ayCZBot:\ax [Pull] navigating: distSq=%s rangeSq=%s inRange=%s los=%s haveTar=%s camp=%s outCamp=%s',
        tostring(spawnDistSq), tostring(rangeSq), tostring(inRange2D), tostring(spawnLoS), tostring(haveTarget),
        tostring(rc.campstatus and true or false), tostring(outsideCamp))

    -- Add-abort: HP dropped (we took damage)
    if rc.pullNavStartHP and mq.TLO.Me.PctHPs() and mq.TLO.Me.PctHPs() < rc.pullNavStartHP then
        printf('\ayCZBot:\ax [Pull] navigating: CLEAR/ABORT -> Add aggro / took damage, returning to camp.')
        abortPullAndReturnToCamp('Add aggro / took damage, returning to camp.')
        return
    end
    -- Add-abort: nearby NPC (not pull target, not grey, Aggressive) with LoS
    local addRadius = myconfig.pull.addAbortRadius or 50
    local addFilter = 'npc radius ' .. addRadius
    local ncount = mq.TLO.SpawnCount(addFilter)()
    if ncount and ncount > 0 then
        for i = 1, ncount do
            local sid = mq.TLO.NearestSpawn(i, addFilter).ID()
            if sid and sid ~= rc.pullAPTargetID and mq.TLO.NearestSpawn(i, addFilter).Aggressive() then
                local conName = mq.TLO.NearestSpawn(i, addFilter).ConColor()
                local conId = conName and botconfig.ConColorsNameToId[conName:upper()] or 0
                if conId ~= 1 and mq.TLO.NearestSpawn(i, addFilter).LineOfSight() then -- not Grey, has LoS
                    printf('\ayCZBot:\ax [Pull] navigating: CLEAR/ABORT -> Add aggro, returning to camp.')
                    abortPullAndReturnToCamp('Add aggro, returning to camp.')
                    return
                end
            end
        end
    end

    if rc.pullTagTimer and mq.gettime() >= rc.pullTagTimer then
        printf('\ayCZBot:\ax\arI have timed out trying to pull \ay%s', spawn.Name())
        if isPullWarp() then
            mq.cmdf('/warp loc %s %s %s', rc.makecamp.y, rc.makecamp.x, rc.makecamp.z)
        end
        printf('\ayCZBot:\ax [Pull] navigating: CLEAR/ABORT -> navigating: tag timeout')
        clearPullState('navigating: tag timeout')
        return
    end
    if mq.TLO.Me.PctHPs() and mq.TLO.Me.PctHPs() <= 45 then
        printf('\ayCZBot:\ax [Pull] navigating: CLEAR/ABORT -> navigating: low HP')
        clearPullState('navigating: low HP')
        return
    end
    if rc.campstatus then
        local meToCampSq = utils.getDistanceSquared3D(rc.makecamp.x, rc.makecamp.y, rc.makecamp.z, mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z())
        if meToCampSq and myconfig.pull.radiusPlus40Sq and meToCampSq > myconfig.pull.radiusPlus40Sq then
            printf('\ayCZBot:\ax [Pull] navigating: CLEAR/ABORT -> navigating: outside camp radius')
            clearPullState('navigating: outside camp radius')
            return
        end
    end
    if (spawnDistSq and rangeSq and spawnDistSq <= rangeSq and spawn.LineOfSight()) or (mq.TLO.Target.ID() == rc.pullAPTargetID) then
        if mq.TLO.Target.ID() ~= rc.pullAPTargetID then
            mq.cmdf('/squelch /tar id %s', rc.pullAPTargetID)
        end
        if mq.TLO.Me.TargetOfTarget.ID() and mq.TLO.Target.ID() and mq.TLO.Target.Type() == 'NPC' and spawnDistSq and spawnDistSq <= rangeSq then
            if botpull.EngageCheck() then
                printf('\ayCZBot:\ax [Pull] navigating: CLEAR/ABORT -> navigating: EngageCheck (mob engaged by other)')
                clearPullState('navigating: EngageCheck (mob engaged by other)')
                return
            end
        end
        if spawnDistSq and rangeSq and spawnDistSq < rangeSq and spawn.LineOfSight() then
            rc.pullState = 'aggroing'
            rc.pullAggroingStartTime = mq.gettime()
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
    if not mq.TLO.Navigation.Active() and spawnDistSq and rangeSq and spawnDistSq > rangeSq then
        mq.cmdf('/nav id %s dist= 7 log=off los=on', rc.pullAPTargetID)
    end
end

-- Returns true when we have clear line of sight to spawn (spawn check + coordinate ray). Used to avoid agro through walls/tents.
local function pullHasLoS(spawn)
    if not spawn or not spawn.LineOfSight() then return false end
    local mx, my, mz = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
    local sx, sy, sz = spawn.X(), spawn.Y(), spawn.Z()
    if not mx or not sx then return false end
    local losStr = string.format('%s,%s,%s:%s,%s,%s', mx, my, mz, sx, sy, sz)
    return mq.TLO.LineOfSight(losStr)()
end

-- Returns true when the pull target's current target is the player (confirmed agro). Nil-safe.
-- Uses spawn.Target when available; fallback to Me.TargetOfTarget when we have the pull mob targeted.
local function pullMobHasAgroOnMe(spawn)
    local meId = mq.TLO.Me.ID()
    if not meId then return false end
    if mq.TLO.Target.ID() == spawn.ID() then
        local totId = mq.TLO.Me.TargetOfTarget.ID()
        return totId and totId == meId
    end
    return false
end

-- One tick of aggroing state (with sub-phases aggro_wait_target, aggro_wait_cast, aggro_wait_stop_moving).
local function tickAggroing(rc, spawn)
    if rc.pullPhase == 'aggro_wait_target' then
        if mq.gettime() >= (rc.pullDeadline or 0) then
            clearPullState('aggroing: aggro_wait_target timeout')
            return
        end
        if not pullHasLoS(spawn) then
            mq.cmdf('/nav id %s dist=5 log=off los=on', tostring(rc.pullAPTargetID))
            return
        end
        if mq.TLO.Target.ID() ~= rc.pullAPTargetID then
            mq.cmdf('/squelch /tar id %s', rc.pullAPTargetID)
            return
        end
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

    -- Aggroing timeout: no agro after 15s -> abort and return to camp
    local aggroingElapsed = mq.gettime() - (rc.pullAggroingStartTime or 0)
    if aggroingElapsed > 15000 and not pullMobHasAgroOnMe(spawn) then
        abortPullAndReturnToCamp('No agro after 15s, returning to camp.')
        return
    end
    -- Only transition to returning when mob has agro on me and min wait (1.5s) has passed
    if spawn.Aggressive() and pullMobHasAgroOnMe(spawn) and aggroingElapsed >= 1500 then
        rc.pullState = 'returning'
        rc.pullPhase = nil
        rc.pulledmob = rc.pullAPTargetID
        rc.pullreturntimer = mq.gettime() + 60000
        rc.pulledmobLastDistSq = utils.getDistanceSquared3D(mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z(), spawn.X(), spawn.Y(), spawn.Z())
        rc.pulledmobLastCloserTime = mq.gettime()
        if rc.pullRangedStoredItem and rc.pullRangedStoredItem ~= '' then
            mq.cmdf('/exchange "%s" Ranged', rc.pullRangedStoredItem)
            rc.pullRangedStoredItem = nil
        end
        combat.ResetCombatState({ clearTarget = false, clearPet = false })
        botmove.NavToCamp({ dist = 0, echoMsg = '\\ayReturning to camp' })
        return
    end

    local entry = botpull.GetPullSpell()
    local gem = entry and entry.gem
    local spell = entry and entry.spell and tostring(entry.spell) or ''
    if rc.pullPhase then return end

    -- Require LoS before any agro (targeting/melee/cast); nav closer if blocked (spawn + coordinate check for walls/tents)
    if not pullHasLoS(spawn) then
        mq.cmdf('/nav id %s dist=5 log=off los=on', tostring(spawn.ID()))
        return
    end

    -- Melee (default or explicit)
    if not entry or gem == 'melee' then
        if mq.TLO.Target.ID() ~= rc.pullAPTargetID then
            mq.cmdf('/squelch /tar id %s', rc.pullAPTargetID)
            return
        end
        mq.cmd('/multiline ; /squelch /nav stop log=off ; /attack on')
        if not mq.TLO.Stick.Active() then mq.cmdf('/stick 5 uw moveback id %s', tostring(spawn.ID())) end
        return
    end

    -- Ranged (bow): swap in bow if needed, ranged attack, swap back after (on returning)
    if gem == 'ranged' and spell ~= '' then
        local rangeSlotName = mq.TLO.Me.InvSlot('Ranged').Item.Name() and mq.TLO.Me.InvSlot('Ranged').Item.Name() or ''
        if rangeSlotName ~= spell then
            if rangeSlotName ~= '' then
                rc.pullRangedStoredItem = rangeSlotName
            else
                rc.pullRangedStoredItem = nil
            end
            mq.cmdf('/exchange "%s" Ranged', spell)
        end
        mq.cmdf('/multiline ; /squelch /nav stop log=off ; /face fast ; /squelch attack off ; /ranged on')
        return
    end

    -- Gem-based cast dispatch (numeric gem = spell slot)
    if type(gem) == 'number' and gem >= 1 and gem <= 12 then
        local spellName = (spell and spell ~= '') and spell or mq.TLO.Me.Gem(gem)() or ''
        if spellName ~= '' and mq.TLO.Me.SpellReady(spellName)() then
            mq.cmd('/nav stop log=off')
            if mq.TLO.Me.Moving() then
                rc.pullPhase = 'aggro_wait_stop_moving'
                rc.pullDeadline = mq.gettime() + 2000
                return
            end
            mq.cmdf('/multiline ; /nav stop log=off ; /casting "%s" %s', spellName, tostring(gem))
            rc.pullPhase = 'aggro_wait_cast'
            rc.pullDeadline = mq.gettime() + 8000
            if not mq.TLO.Stick.Active() then mq.cmdf('/stick 5 uw moveback id %s', spawn.ID()) end
            return
        end
    end
    if gem == 'disc' and spell ~= '' and mq.TLO.Me.CombatAbilityReady(spell)() then
        mq.cmdf('/multiline ; /nav stop log=off ; /disc %s', spell)
        if not mq.TLO.Stick.Active() then mq.cmdf('/stick 5 uw moveback id %s', spawn.ID()) end
        return
    end
    if gem == 'ability' and spell ~= '' and mq.TLO.Me.AbilityReady(spell)() then
        mq.cmdf('/multiline ; /nav stop log=off ; /attack on ; /doability %s', spell)
        if not mq.TLO.Stick.Active() then mq.cmdf('/stick 5 uw moveback id %s', spawn.ID()) end
        return
    end
    if gem == 'alt' and spell ~= '' and mq.TLO.Me.AltAbilityReady(spell)() then
        mq.cmd('/nav stop log=off')
        if mq.TLO.Me.Moving() then
            rc.pullPhase = 'aggro_wait_stop_moving'
            rc.pullDeadline = mq.gettime() + 2000
            return
        end
        mq.cmdf('/multiline ; /nav stop log=off ; /alt act %s', mq.TLO.Me.AltAbility(spell)())
        rc.pullPhase = 'aggro_wait_cast'
        rc.pullDeadline = mq.gettime() + 8000
        return
    end
    if gem == 'item' and spell ~= '' and mq.TLO.Me.ItemReady(spell)() then
        mq.cmd('/nav stop log=off')
        if mq.TLO.Me.Moving() then
            rc.pullPhase = 'aggro_wait_stop_moving'
            rc.pullDeadline = mq.gettime() + 2000
            return
        end
        mq.cmdf('/multiline ; /nav stop log=off ; /cast item "%s"', spell)
        rc.pullPhase = 'aggro_wait_cast'
        rc.pullDeadline = mq.gettime() + 8000
        return
    end
    if gem == 'script' and spell ~= '' then
        local spellutils = require('lib.spellutils')
        if spellutils.RunScript then
            mq.cmd('/nav stop log=off')
            spellutils.RunScript(spell, 'pull', spawn.ID())
        end
        return
    end

    if not spawn.Aggressive() and mq.TLO.Target.ID() == spawn.ID() and (not mq.TLO.Stick.Active() or not pullHasLoS(spawn)) then
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
        clearPullState('returning: return timer')
        return
    end
    if isPullWarp() then
        mq.cmdf('/warp loc %s %s %s', rc.makecamp.y, rc.makecamp.x, rc.makecamp.z)
        clearPullState('returning: warp')
        return
    end
    local retSpawnDistSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), spawn.X(), spawn.Y())
    if retSpawnDistSq and myconfig.pull.leashSq and retSpawnDistSq > myconfig.pull.leashSq and not mq.TLO.Navigation.Paused() then
        mq.cmd('/nav pause on log=off')
    elseif retSpawnDistSq and myconfig.pull.leashSq and retSpawnDistSq < myconfig.pull.leashSq and mq.TLO.Navigation.Paused() then
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
        clearPullState('waiting_combat: AP in camp or timer')
    end
end

function botpull.PullTick()
    local rc = state.getRunconfig()
    if not rc.pullState or not rc.pullAPTargetID then return end
    printf('\ayCZBot:\ax [Pull] tick state=%s id=%s', rc.pullState or 'nil', tostring(rc.pullAPTargetID))
    local spawn = mq.TLO.Spawn(rc.pullAPTargetID)
    if not spawn or not spawn.ID() or spawn.Type() == 'Corpse' then
        clearPullState('PullTick: no spawn or corpse')
        return
    end
    if MasterPause then
        clearPullState('PullTick: MasterPause')
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
            if not state.getRunconfig().dopull then return end
            if utils.isNonCombatZone(mq.TLO.Zone.ShortName()) then return end
            if state.getRunState() == 'raid_mechanic' then return end
            local rc = state.getRunconfig()
            if state.getRunState() == 'pulling' then
                printf('\ayCZBot:\ax [Pull] doPull: runState=pulling pullState=%s', tostring(rc.pullState))
                botpull.PullTick()
                return
            end
            if state.getRunconfig().MobCount <= myconfig.pull.chainpullcnt or myconfig.pull.chainpullcnt == 0 then
                if mq.TLO.Spawn(state.getRunconfig().engageTargetId).PctHPs() then
                    local tempcnt = myconfig.pull.chainpullcnt == 0 and (myconfig.pull.chainpullcnt + 1) or
                        myconfig.pull.chainpullcnt
                    if (tonumber(mq.TLO.Spawn(state.getRunconfig().engageTargetId).PctHPs()) <= myconfig.pull.chainpullhp) and state.getRunconfig().MobCount <= tempcnt then
                        printf('\ayCZBot:\ax [Pull] doPull: calling StartPull (chainpull PctHPs low MobCount=%s)', tostring(rc.MobCount))
                        botpull.StartPull()
                    end
                end
            end
            if (state.getRunconfig().MobCount < myconfig.pull.chainpullcnt) then
                printf('\ayCZBot:\ax [Pull] doPull: calling StartPull (MobCount=%s < chainpullcnt=%s)', tostring(rc.MobCount), tostring(myconfig.pull.chainpullcnt))
                botpull.StartPull()
            end
            if (state.getRunconfig().MobCount == 0) and not state.getRunconfig().engageTargetId then
                printf('\ayCZBot:\ax [Pull] doPull: calling StartPull (MobCount=0 no engageTargetId)')
                botpull.StartPull()
            end
        end
    end
    return nil
end

return botpull
