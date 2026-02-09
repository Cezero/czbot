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

-- MT only: pick from MobList (closest LOS). Prefer Puller's target when present. Returns mtPick spawn, engageTargetRefound.
local function selectTankTarget(mainTankName)
    local mtPick = nil
    local engageTargetRefound = false
    if mainTankName ~= mq.TLO.Me.Name() then return nil, false end
    local gmt = mq.TLO.Group.MainTank
    local groupMTName = (gmt and gmt.Name) and gmt.Name() or nil
    if not (mq.TLO.Raid.Members() or not mq.TLO.Group() or groupMTName == mq.TLO.Me.Name()) then return nil, false end
    if mq.TLO.Me.Combat() then return nil, false end
    local pullerTarID = tankrole.GetPullerTargetID()
    local rc = state.getRunconfig()
    for _, v in ipairs(rc.MobList) do
        if v.LineOfSight() then
            if mtPick then
                if pullerTarID and v.ID() == pullerTarID then
                    mtPick = v
                elseif v.ID() == rc.engageTargetId then
                    mtPick = v
                    engageTargetRefound = true
                elseif not (pullerTarID and mtPick.ID() == pullerTarID) and v.Distance() < mtPick.Distance() then
                    mtPick = v
                end
            else
                mtPick = v
            end
        end
    end
    return mtPick, engageTargetRefound
end

-- Offtank: if MT target == MA target pick add (Nth other mob); if MT target != MA target tank MA's target (agro/taunt).
local function resolveOfftankTarget(assistName, mainTankName, assistpct)
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
        -- Same target: pick an add (Nth mob in MobList that is not that target).
        local actarid, acname
        local otcounter = 0
        for _, v in ipairs(rc.MobList) do
            if v.ID() ~= maTarId and not actarid then
                if otcounter == myconfig.melee.otoffset then
                    actarid = v.ID()
                    acname = v.CleanName()
                end
                otcounter = otcounter + 1
            end
        end
        if actarid then
            if actarid ~= mq.TLO.Target.ID() then
                printf('\ayCZBot:\ax\arOff-tanking\ax a \ag%s id %s', acname, actarid)
            end
            rc.engageTargetId = actarid
        elseif maInfo and maInfo.TargetHP and (maInfo.TargetHP <= assistpct) and maTarId and maTarId > 0 then
            rc.engageTargetId = maTarId
        end
    else
        -- Different targets: offtank tanks the MA's target (agro/taunt).
        if maTarId and maTarId > 0 then
            rc.engageTargetId = maTarId
        end
    end
end

-- DPS: sync engageTargetId to MA's target when MA is engaging.
local function resolveMeleeAssistTarget(assistName, assistpct)
    local rc = state.getRunconfig()
    local maInfo = charinfo.GetInfo(assistName)
    local maTarId = maInfo and maInfo.Target and maInfo.Target.ID or nil
    if maInfo and maInfo.ID and (rc.engageTargetId ~= maTarId) then rc.engageTargetId = nil end
    for _, v in ipairs(rc.MobList) do
        if v.ID() == maTarId and maInfo and maInfo.TargetHP and (maInfo.TargetHP <= assistpct) then
            rc.engageTargetId = maTarId
        end
    end
    if not (maInfo and maInfo.ID) then
        rc.engageTargetId = botmelee.GetPCTarget(assistName)
    end
end

-- MA bot only: choose target from MobList with priority (1) named, (2) MT's target. Sets engageTargetId.
local function selectMATarget(mainTankName)
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
                if not namedSpawn or v.Distance() < namedSpawn.Distance() then namedSpawn = v end
            end
            if mtTarId and v.ID() == mtTarId then mtTarSpawn = v end
        end
    end
    if namedSpawn then
        rc.engageTargetId = namedSpawn.ID()
    elseif mtTarSpawn then
        rc.engageTargetId = mtTarSpawn.ID()
    end
end

-- When engageTargetId is set: pet attack, target (blocking TargetAndWait), stand, attack on, stick. Uses melee phase moving_closer.
local function engageTarget()
    local engageTargetId = state.getRunconfig().engageTargetId
    if not engageTargetId then return end

    if state.getRunState() == 'melee' then
        local p = state.getRunStatePayload()
        if p and p.phase == 'moving_closer' then
            if mq.TLO.Target.Distance() and mq.TLO.Target.Distance() < mq.TLO.Target.MaxMeleeTo() then
                state.setRunState('melee', { phase = 'idle', priority = bothooks.getPriority('doMelee') })
                return
            end
            if p.deadline and mq.gettime() >= p.deadline then
                state.setRunState('melee', { phase = 'idle', priority = bothooks.getPriority('doMelee') })
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
        state.setRunState('melee', { phase = 'moving_closer', deadline = mq.gettime() + 5000, priority = bothooks.getPriority('doMelee') })
    end
end

-- When no engageTargetId: stick off, attack off, pet back, clear NPC target.
local function disengageCombat()
    state.getRunconfig().statusMessage = ''
    combat.ResetCombatState()
end

-- Resolve assistName (MA) and mainTankName (MT). MT picks from MobList (puller priority); MA bot picks named then MT target; offtank/DPS follow MA.
function botmelee.AdvCombat()
    local assistName = tankrole.GetAssistTargetName()
    local mainTankName = tankrole.GetMainTankName()
    local assistpct = myconfig.melee.assistpct or 99
    local rc = state.getRunconfig()

    if mainTankName == mq.TLO.Me.Name() and mq.TLO.Target.Master.Type() == 'PC' then
        clearTankCombatState()
    end

    if tankrole.AmIMainTank() then
        local mtPick, engageTargetRefound = selectTankTarget(mainTankName)
        if mtPick and mtPick.ID() then
            rc.engageTargetId = mtPick.ID()
        end
        if engageTargetRefound then
            botmove.StartReturnToFollowAfterEngage()
        end
    elseif tankrole.AmIMainAssist() then
        selectMATarget(mainTankName)
    else
        if myconfig.melee.offtank and assistName and mainTankName then
            resolveOfftankTarget(assistName, mainTankName, assistpct)
        end
        if not myconfig.melee.offtank and assistName then
            resolveMeleeAssistTarget(assistName, assistpct)
        end
    end

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
    mq.delay(500, function() return mq.TLO.Target.ID() end)
    state.getRunconfig().statusMessage = ''
    for _, v in ipairs(state.getRunconfig().MobList) do
        if mq.TLO.Target.ID() == v.ID() then return mq.TLO.Target.ID() end
    end
    return nil
end

function botmelee.getHookFn(name)
    if name == 'doMelee' then
        return function(hookName)
            if state.getRunState() == 'engage_return_follow' then
                botmove.TickReturnToFollowAfterEngage()
                return
            end
            if not myconfig.settings.domelee then return end
            if utils.isNonCombatZone(mq.TLO.Zone.ShortName()) then return end
            if not state.getRunconfig().MobList[1] then
                if state.getRunState() == 'melee' then state.clearRunState() end
                return
            end
            local payload = (state.getRunState() == 'melee') and state.getRunStatePayload() or nil
            state.setRunState('melee', payload and payload or { phase = 'idle', priority = bothooks.getPriority('doMelee') })
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
