local mq = require('mq')
local botconfig = require('lib.config')
local combat = require('lib.combat')
local state = require('lib.state')
local bothooks = require('lib.bothooks')
local targeting = require('lib.targeting')
local botmove = require('botmove')
local utils = require('lib.utils')
local charinfo = require("mqcharinfo")
local tankrole = require('lib.tankrole')
local spawnutils = require('lib.spawnutils')
local myconfig = botconfig.config
local botmelee = {}

function botmelee.LoadMeleeConfig()
end

botconfig.RegisterConfigLoader(function() if botconfig.config.settings.domelee then botmelee.LoadMeleeConfig() end end)

state.getRunconfig().mobprobtimer = 0

-- When I am MT and my target is a PC: clear combat state.
local function clearTankCombatState()
    state.getRunconfig().engageTargetId = nil
    combat.ResetCombatState()
end

-- MT only: pick from MobList (closest LOS). Prefer Puller's target when present. Skip mezzed; if all mezzed, return closest.
-- Returns mtPick spawn, engageTargetRefound.
local function selectTankTarget(mainTankName)
    if mainTankName ~= mq.TLO.Me.Name() then return nil, false end
    local gmt = mq.TLO.Group.MainTank
    local groupMTName = (gmt and gmt.Name) and gmt.Name() or nil
    if not (mq.TLO.Raid.Members() or not mq.TLO.Group() or groupMTName == mq.TLO.Me.Name()) then return nil, false end
    if mq.TLO.Me.Combat() then return nil, false end
    local pullerTarID = tankrole.GetPullerTargetID()
    local rc = state.getRunconfig()
    local losList = {}
    for _, v in ipairs(rc.MobList) do
        if v.LineOfSight() then table.insert(losList, v) end
    end
    if #losList == 0 then return nil, false end
    local meX, meY = mq.TLO.Me.X(), mq.TLO.Me.Y()
    table.sort(losList, function(a, b)
        local aId, bId = a.ID(), b.ID()
        if aId == pullerTarID and bId ~= pullerTarID then return true end
        if aId ~= pullerTarID and bId == pullerTarID then return false end
        if aId == rc.engageTargetId and bId ~= rc.engageTargetId then return true end
        if aId ~= rc.engageTargetId and bId == rc.engageTargetId then return false end
        local da = utils.getDistanceSquared2D(meX, meY, a.X(), a.Y())
        local db = utils.getDistanceSquared2D(meX, meY, b.X(), b.Y())
        return (da or 0) < (db or 0)
    end)
    for _, spawn in ipairs(losList) do
        if targeting.TargetAndWaitBuffsPopulated(spawn.ID(), 1000) then
            if not mq.TLO.Target.Mezzed() then
                return spawn.ID(), (spawn.ID() == rc.engageTargetId)
            end
        end
    end
    local first = losList[1]
    return first and first.ID() or nil, (first and first.ID() == rc.engageTargetId)
end

-- Offtank: if MT target == MA target pick add (Nth other mob); else tank MA's target. Returns chosen id or nil.
local function resolveOfftankTarget(assistName, mainTankName, assistpct)
    if not mainTankName or mainTankName == '' then return nil end
    local rc = state.getRunconfig()
    local maInfo = charinfo.GetInfo(assistName)
    local maTarId = (maInfo and maInfo.ID and maInfo.Target) and maInfo.Target.ID or nil
    if not maTarId and mq.TLO.Spawn('pc =' .. assistName).ID() then
        maTarId = botmelee.GetPCTarget(assistName)
    end
    local mtInfo = charinfo.GetInfo(mainTankName)
    local mtTarId = (mtInfo and mtInfo.ID and mtInfo.Target) and mtInfo.Target.ID or nil
    if not mtTarId and mq.TLO.Spawn('pc =' .. mainTankName).ID() then
        mtTarId = botmelee.GetPCTarget(mainTankName)
    end
    if mtTarId == maTarId then
        local otoffset = myconfig.melee.otoffset or 0
        local nthSpawn = spawnutils.selectNthAdd(rc.MobList, maTarId, otoffset + 1)
        if nthSpawn then
            local actarid = nthSpawn.ID()
            if actarid ~= mq.TLO.Target.ID() then
                printf('\ayCZBot:\ax\arOff-tanking\ax a \ag%s id %s', nthSpawn.CleanName(), actarid)
            end
            return actarid
        end
        if maInfo and maInfo.TargetHP and (maInfo.TargetHP <= assistpct) and maTarId and maTarId > 0 then
            return maTarId
        end
    elseif maTarId and maTarId > 0 then
        return maTarId
    end
    return nil
end

-- DPS: return MA's target when MA is engaging and in MobList at assistpct; else GetPCTarget. Returns id or nil.
local function resolveMeleeAssistTarget(assistName, assistpct)
    local rc = state.getRunconfig()
    local maInfo = charinfo.GetInfo(assistName)
    local maTarId = maInfo and maInfo.Target and maInfo.Target.ID or nil
    if maInfo and maInfo.ID then
        for _, v in ipairs(rc.MobList) do
            if v.ID() == maTarId and maInfo.TargetHP and (maInfo.TargetHP <= assistpct) then
                return maTarId
            end
        end
        return nil
    end
    return botmelee.GetPCTarget(assistName)
end

-- MA bot only: choose target from MobList (1) named, (2) MT's target. Returns chosen id or nil.
local function selectMATarget(mainTankName)
    if not mainTankName or mainTankName == '' then return nil end
    local rc = state.getRunconfig()
    local mtTarId = nil
    local mtInfo = charinfo.GetInfo(mainTankName)
    if mtInfo and mtInfo.Target then mtTarId = mtInfo.Target.ID end
    if not mtTarId and mq.TLO.Spawn('pc =' .. mainTankName).ID() then
        mtTarId = botmelee.GetPCTarget(mainTankName)
    end
    local namedSpawn = nil
    local mtTarSpawn = nil
    for _, v in ipairs(rc.MobList) do
        if v.LineOfSight() then
            if v.Named() then
                if not namedSpawn then
                    namedSpawn = v
                else
                    local vDistSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), v.X(), v.Y())
                    local nDistSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), namedSpawn.X(), namedSpawn.Y())
                    if vDistSq and nDistSq and vDistSq < nDistSq then namedSpawn = v end
                end
            end
            if mtTarId and v.ID() == mtTarId then mtTarSpawn = v end
        end
    end
    if namedSpawn then return namedSpawn.ID() end
    if mtTarSpawn then return mtTarSpawn.ID() end
    return nil
end

-- When engageTargetId is set: pet attack, target (blocking TargetAndWait), stand, attack on, stick. Uses melee phase moving_closer.
local function engageTarget()
    local engageTargetId = state.getRunconfig().engageTargetId
    if not engageTargetId then return end

    if state.getRunState() == state.STATES.melee then
        local p = state.getRunStatePayload()
        if p and p.phase == 'moving_closer' then
            local targetDistSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Target.X(), mq.TLO.Target.Y())
            local maxMeleeTo = mq.TLO.Target.MaxMeleeTo()
            if targetDistSq and maxMeleeTo and targetDistSq < (maxMeleeTo * maxMeleeTo) then
                if state.canStartBusyState(state.STATES.melee) then
                    state.setRunState(state.STATES.melee, { phase = 'idle', priority = bothooks.getPriority('doMelee') })
                end
                return
            end
            if p.deadline and mq.gettime() >= p.deadline then
                if state.canStartBusyState(state.STATES.melee) then
                    state.setRunState(state.STATES.melee, { phase = 'idle', priority = bothooks.getPriority('doMelee') })
                end
                return
            end
            return
        end
    end

    if mq.TLO.Me.Pet.ID() and myconfig.settings.petassist and not mq.TLO.Pet.Aggressive() then
        mq.cmdf('/pet attack %s', engageTargetId)
    end

    if not myconfig.settings.domelee then return end

    if mq.TLO.Target.ID() ~= engageTargetId then
        targeting.TargetAndWait(engageTargetId, 500)
    end

    if mq.TLO.Navigation.Active() then mq.cmd('/nav stop') end
    if mq.TLO.Me.Sitting() then mq.cmd('/stand on') end
    if not mq.TLO.Me.Combat() then mq.cmd('/squelch /attack on') end
    if not mq.TLO.Stick.Active() or (mq.TLO.Stick.StickTarget() ~= engageTargetId) then
        mq.cmdf('/squelch /multiline ; /attack on ; /stick %s', myconfig.melee.stickcmd)
    end

    if mq.TLO.Me.Class.ShortName() ~= 'BRD' then
        if state.canStartBusyState(state.STATES.melee) then
            state.setRunState(state.STATES.melee, { phase = 'moving_closer', deadline = mq.gettime() + 5000, priority = bothooks.getPriority('doMelee') })
        end
    end
end

-- When no engageTargetId: stick off, attack off, pet back, clear NPC target.
local function disengageCombat()
    state.getRunconfig().statusMessage = ''
    combat.ResetCombatState()
    if state.getRunState() == state.STATES.melee then state.clearRunState() end
end

-- Resolve engageTargetId from role (MT/MA/OT/DPS), then engage or disengage. Only sets melee busy state via canStartBusyState.
function botmelee.AdvCombat()
    local assistName = tankrole.GetAssistTargetName()
    local mainTankName = tankrole.GetMainTankName()
    local assistpct = myconfig.melee.assistpct or 99
    local rc = state.getRunconfig()

    if mainTankName == mq.TLO.Me.Name() and mq.TLO.Target.Master.Type() == 'PC' then
        clearTankCombatState()
    end

    local id = nil
    local engageTargetRefound = false
    if tankrole.AmIMainTank() then
        id, engageTargetRefound = selectTankTarget(mainTankName)
        -- When MT is in combat, selectTankTarget returns nil; preserve engageTargetId so we don't call disengageCombat and clear target.
        if id == nil and mq.TLO.Me.Combat() and rc.engageTargetId and rc.MobList then
            for _, v in ipairs(rc.MobList) do
                if v.ID() == rc.engageTargetId then
                    id = rc.engageTargetId
                    break
                end
            end
        end
        if engageTargetRefound then
            botmove.StartReturnToFollowAfterEngage()
        end
    elseif tankrole.AmIMainAssist() then
        id = selectMATarget(mainTankName)
    else
        if myconfig.melee.offtank and assistName and mainTankName then
            id = resolveOfftankTarget(assistName, mainTankName, assistpct)
        elseif assistName then
            id = resolveMeleeAssistTarget(assistName, assistpct)
        end
    end
    rc.engageTargetId = id

    if rc.engageTargetId then
        local name = mq.TLO.Spawn(rc.engageTargetId).CleanName() or tostring(rc.engageTargetId)
        if tankrole.AmIMainTank() then
            rc.statusMessage = string.format('Tanking %s (%s)', name, rc.engageTargetId)
        elseif myconfig.melee.offtank then
            rc.statusMessage = string.format('Off-tanking %s (%s)', name, rc.engageTargetId)
        else
            rc.statusMessage = string.format('Assisting on %s (%s)', name, rc.engageTargetId)
        end
        engageTarget()
    else
        disengageCombat()
    end
end

-- Return target ID of PC pcName (used for MA's or MT's target depending on caller). Uses charinfo when peer, else /assist + blocking delay until target set.
function botmelee.GetPCTarget(pcName)
    if not pcName or not mq.TLO.Spawn('pc =' .. pcName).ID() then return nil end

    if mq.TLO.Me.Assist() then mq.cmd('/squelch /assist off') end
    mq.cmdf('/assist %s', pcName)
    state.getRunconfig().statusMessage = string.format('Waiting for assist target (%s)', pcName)
    mq.delay(500, function()
        local id = mq.TLO.Target.ID()
        return id ~= nil and id ~= 0
    end)
    state.getRunconfig().statusMessage = ''
    for _, v in ipairs(state.getRunconfig().MobList) do
        if mq.TLO.Target.ID() == v.ID() then return mq.TLO.Target.ID() end
    end
    return nil
end

function botmelee.getHookFn(name)
    if name == 'doMelee' then
        return function(hookName)
            if state.isTravelMode() and not state.isTravelAttackOverriding() then return end
            if state.getRunState() == state.STATES.engage_return_follow then
                botmove.TickReturnToFollowAfterEngage()
                return
            end
            if state.getRunState() == state.STATES.pulling then return end
            if not (myconfig.settings.domelee or state.isTravelAttackOverriding()) then
                if state.getRunState() == state.STATES.melee then state.clearRunState() end
                state.getRunconfig().engageTargetId = nil
                state.getRunconfig().statusMessage = ''
                return
            end
            if utils.isNonCombatZone(mq.TLO.Zone.ShortName()) then return end
            if not state.getRunconfig().MobList[1] then
                if state.getRunState() == state.STATES.melee then state.clearRunState() end
                state.getRunconfig().engageTargetId = nil
                state.getRunconfig().statusMessage = ''
                return
            end
            local payload = (state.getRunState() == state.STATES.melee) and state.getRunStatePayload() or nil
            state.setRunState(state.STATES.melee, payload and payload or { phase = 'idle', priority = bothooks.getPriority('doMelee') })
            if tankrole.AmIMainTank() or tankrole.AmIMainAssist() then
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
        end
    end
    return nil
end

return botmelee
