local mq = require('mq')
local botconfig = require('lib.config')
local spellbands = require('lib.spellbands')
local spellutils = require('lib.spellutils')
local state = require('lib.state')
local utils = require('lib.utils')
local charinfo = require('plugin.charinfo')
local bothooks = require('lib.bothooks')
local castutils = require('lib.castutils')
local botmove = require('botmove')
local targeting = require('lib.targeting')
local czactor = require('lib.czactor')
local tickprof = require('lib.tickprof')

local botheal = {}
local AHThreshold = {}
local XTList = {}

local function defaultHealEntry()
    return botconfig.getDefaultSpellEntry('heal')
end

function botheal.LoadHealConfig()
    local myconfig = botconfig.config
    castutils.LoadSpellSectionConfig('heal', {
        defaultEntry = defaultHealEntry,
        bandsKey = 'heal',
        storeIn = AHThreshold,
        postLoad = function()
            if myconfig.heal.xttargets then
                for num in string.gmatch(tostring(myconfig.heal.xttargets), "%d+") do
                    local n = tonumber(num)
                    if n then XTList[n] = n end
                end
            end
            _G.AHThreshold = AHThreshold
            _G.XTList = XTList
        end,
    })
end

castutils.RegisterSectionLoader('heal', 'doheal', botheal.LoadHealConfig)

local function hpInBand(pct, th)
    return spellbands.hpInBand(pct, th)
end

-- Returns (id, targethit) if band allows phase, pct in band, and (distOk is nil or true); else (nil, nil).
local function hpEvalReturn(index, phaseKey, pct, id, targethit, distOk)
    if not AHThreshold[index] or not AHThreshold[index][phaseKey] then return nil, nil end
    if not pct or not hpInBand(pct, AHThreshold[index][phaseKey]) then return nil, nil end
    if distOk ~= nil and not distOk then return nil, nil end
    return id, targethit
end

local function HPEvalContext(index, shared)
    local entry = botconfig.getSpellEntry('heal', index)
    if not entry then return nil end
    local gem = entry.gem
    local tank, tankid, bots, botcount, botstr, tanknbid
    if shared then
        tank, tankid = shared.tank, shared.tankid
        bots, botcount = shared.bots, shared.botcount
        tanknbid = shared.tanknbid
    else
        tank, tankid = spellutils.GetTankInfo(false)
        botcount = charinfo.GetPeerCnt()
        bots = spellutils.GetBotListOrdered()
        botstr = table.concat(charinfo.GetPeers(), " ")
        -- Whole-token match: botstr is space-joined peer names, so wrap both sides in spaces and search
        -- plain (4th arg true). Prevents tank "Bob" from matching peer "Bobby" and mis-routing the heal.
        tanknbid = tank and string.find(' ' .. botstr .. ' ', ' ' .. tank .. ' ', 1, true)
    end
    local spell, spellrange = spellutils.GetSpellInfo(entry)
    if not spell then return nil end
    local spellEntity = spellutils.GetSpellEntity(entry)
    if spellEntity then spellrange = spellEntity.MyRange() end
    local spellrangeSq = spellrange and (spellrange * spellrange) or nil
    return {
        entry = entry,
        gem = gem,
        spell = spell,
        spellrange = spellrange,
        spellrangeSq = spellrangeSq,
        tank = tank,
        tankid = tankid,
        tanknbid = tanknbid,
        botcount = botcount,
        bots = bots,
    }
end

--- Single place for heal hook context: tank, class-ordered bots, spell/range for index 1. Built once and passed through RunPhaseFirstSpellCheck.
local function healBuildContext()
    return HPEvalContext(1)
end

local function corpsePlayerName(spawn)
    local name = spawn.CleanName()
    if not name then return nil end
    return string.gsub(name, "'s corpse", "")
end

local function corpseClassForName(name)
    if not name or name == '' then return nil end
    local peer = charinfo.GetInfo(name)
    if peer and peer.Class then return peer.Class.ShortName end
    if mq.TLO.Group.Member(name).Index() then
        return mq.TLO.Group.Member(name).Class.ShortName()
    end
    local raidMembers = mq.TLO.Raid.Members()
    if raidMembers and raidMembers > 0 then
        for k = 1, raidMembers do
            if mq.TLO.Raid.Member(k).Name() == name then
                return mq.TLO.Raid.Member(k).Class.ShortName()
            end
        end
    end
    return mq.TLO.Spawn('pc =' .. name).Class.ShortName()
end

local function isCorpseRezEligible(name)
    if not name or name == '' then return false end
    if charinfo.GetInfo(name) then return true end
    if mq.TLO.Group.Member(name).Index() then return true end
    local raidMembers = mq.TLO.Raid.Members()
    if raidMembers and raidMembers > 0 then
        for k = 1, raidMembers do
            if mq.TLO.Raid.Member(k).Name() == name then return true end
        end
    end
    local myGuild = mq.TLO.Me.Guild()
    if myGuild and myGuild ~= '' then
        local theirGuild = mq.TLO.Spawn('pc =' .. name).Guild()
        if theirGuild and theirGuild ~= '' and myGuild == theirGuild then return true end
    end
    return false
end

-- Build list of matching corpses with class priority for rez order (healers first: clr, shm, dru, etc.).
local function _corpseRezCandidates()
    local myconfig = botconfig.config
    local corpsecount = mq.TLO.SpawnCount('pccorpse radius ' .. myconfig.settings.acleash)()
    if not corpsecount or corpsecount == 0 then return {} end
    local corpsedist = myconfig.settings.acleash
    local candidates = {}
    for i = 1, corpsecount do
        local spawn = mq.TLO.NearestSpawn(i, 'pccorpse radius ' .. corpsedist)
        local playerName = corpsePlayerName(spawn)
        local rezid = spawn.ID()
        if playerName and rezid and isCorpseRezEligible(playerName) then
            local class = corpseClassForName(playerName)
            local priority = spellutils.GetClassOrderPriority(class)
            candidates[#candidates + 1] = { rezid = rezid, priority = priority }
        end
    end
    table.sort(candidates, function(a, b) return (a.priority or 9999) < (b.priority or 9999) end)
    return candidates
end

local function CorpseRezIdForFilter()
    local candidates = _corpseRezCandidates()
    if #candidates == 0 then return nil end
    for _, c in ipairs(candidates) do
        if not czactor.isCorpseRezClaimedByOther(c.rezid) then
            czactor.syncRezClaim(c.rezid)
            return c.rezid
        end
    end
    return nil
end

local function healHasCorpseSpellConfigured()
    local count = botconfig.getSpellCount('heal')
    for idx = 1, count do
        local entry = botconfig.getSpellEntry('heal', idx)
        if entry and entry.enabled ~= false and entry.gem ~= 0
            and AHThreshold[idx] and AHThreshold[idx].corpse then
            return true
        end
    end
    return false
end

local function healCorpsePending()
    if not healHasCorpseSpellConfigured() then return false end
    return #_corpseRezCandidates() > 0
end

local function healCorpseSpellBlockedByCombat(index)
    if not AHThreshold[index] then return false end
    if AHThreshold[index].inCombat then return false end
    local rc = state.getRunconfig()
    return rc.MobList and rc.MobList[1] ~= nil
end

local function healCorpseAllSpellsCombatBlocked()
    local count = botconfig.getSpellCount('heal')
    local hasCorpseSpell = false
    for idx = 1, count do
        local entry = botconfig.getSpellEntry('heal', idx)
        if entry and entry.enabled ~= false and entry.gem ~= 0
            and AHThreshold[idx] and AHThreshold[idx].corpse then
            hasCorpseSpell = true
            if not healCorpseSpellBlockedByCombat(idx) then
                return false
            end
        end
    end
    return hasCorpseSpell
end

local function healShouldHoldHealPass()
    if not healCorpsePending() then return false end
    if healCorpseAllSpellsCombatBlocked() then return false end
    return true
end

local function HPEvalCorpse(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].corpse then return nil, nil end
    if healCorpseSpellBlockedByCombat(index) then return nil, nil end
    local rezid = CorpseRezIdForFilter()
    if rezid then return rezid, 'corpse' end
    return nil, nil
end

local function HPEvalSelf(index, ctx)
    if ctx.entry.healResource == 'mana' then
        local minmanapct = ctx.entry.minmanapct
        local maxmanapct = ctx.entry.maxmanapct
        if minmanapct == nil then minmanapct = 0 end
        if maxmanapct == nil then maxmanapct = 100 end
        local mymana = mq.TLO.Me.PctMana()
        if not mymana or mymana < minmanapct or mymana > maxmanapct then return nil, nil end
        if not AHThreshold[index] or not AHThreshold[index].self then return nil, nil end
        local spellEntity = spellutils.GetSpellEntity(ctx.entry)
        local id = (spellEntity and spellEntity.TargetType() == 'Self') and 1 or mq.TLO.Me.ID()
        return id, 'self'
    end
    local pct = mq.TLO.Me.PctHPs()
    local spellEntity = spellutils.GetSpellEntity(ctx.entry)
    local id = (spellEntity and spellEntity.TargetType() == 'Self') and 1 or mq.TLO.Me.ID()
    return hpEvalReturn(index, 'self', pct, id, 'self', nil)
end

local function HPEvalGrp(index, ctx)
    local spellEntity = spellutils.GetSpellEntity(ctx.entry)
    local aeRange = spellEntity and spellEntity.AERange()
    if not aeRange or aeRange <= 0 then return nil, nil end
    local aeRangeSq = aeRange * aeRange
    local spellIdForBuff = spellEntity and spellEntity.ID()
    local function needHeal(grpmember, grpid, grpname, peer)
        local grpspawn = grpmember.Spawn
        if not grpspawn then return false end
        local grpmempcthp = grpspawn.PctHPs()
        if not (grpmember.Present() and grpmempcthp and hpInBand(grpmempcthp, AHThreshold[index].groupheal) and grpspawn.Type() ~= 'Corpse') then
            return false
        end
        if spellutils.IsHoTSpell(ctx.entry) then
            if grpid == mq.TLO.Me.ID() then
                if mq.TLO.Me.FindBuff(ctx.entry.spell)() then return false end
            elseif peer and spellIdForBuff then
                if spellutils.PeerHasBuff(peer, spellIdForBuff) then return false end
            end
        end
        return true
    end
    return castutils.evalGroupAECount(ctx.entry, 'groupheal', index, AHThreshold, 'groupheal', needHeal, { aeRangeSq = aeRangeSq, includeMemberZero = true })
end

local function HPEvalTank(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].tank or not ctx.tank then return nil, nil end
    local tankspawn = mq.TLO.Spawn(ctx.tankid)
    local tankdistSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), tankspawn.X(), tankspawn.Y())
    local tankinfo = charinfo.GetInfo(ctx.tank)
    local tanknbhp = tankinfo and tankinfo.PctHPs or nil
    if not ctx.tanknbid and ctx.tankid and mq.TLO.Group.Member(ctx.tank).Index() then
        if mq.TLO.Spawn(ctx.tankid).Type() == 'PC' and castutils.hpEvalSpawn(ctx.tankid, AHThreshold[index].tank) and tankdistSq and ctx.spellrangeSq and tankdistSq <= ctx.spellrangeSq then
            return mq.TLO.Group.Member(ctx.tank).ID(), 'tank'
        end
    elseif ctx.tanknbid then
        if mq.TLO.Spawn(ctx.tankid).Type() == 'PC' and tanknbhp and hpInBand(tanknbhp, AHThreshold[index].tank) and tankdistSq and ctx.spellrangeSq and tankdistSq <= ctx.spellrangeSq then
            return mq.TLO.Spawn('pc =' .. ctx.tank).ID(), 'tank'
        end
    end
    return nil, nil
end

local function HPEvalOfftank(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].offtank then return nil, nil end
    local czactor = require('lib.czactor')
    for _, ot in ipairs(czactor.getActiveOfftanks()) do
        local sp = mq.TLO.Spawn('pc =' .. ot.name)
        if sp and sp.ID() and sp.ID() > 0 then
            local otid = sp.ID()
            local distSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), sp.X(), sp.Y())
            local peer = charinfo.GetInfo(ot.name)
            local othp = peer and peer.PctHPs or sp.PctHPs()
            if othp and hpInBand(othp, AHThreshold[index].offtank) and distSq and ctx.spellrangeSq and distSq <= ctx.spellrangeSq then
                return otid, 'offtank'
            end
        end
    end
    return nil, nil
end

local function HPEvalMyPet(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].mypet then return nil, nil end
    local mypetid = mq.TLO.Me.Pet.ID()
    local mypetdistSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Pet.X(), mq.TLO.Me.Pet.Y())
    if mypetid and mypetid > 0 then
        local distOk = mypetdistSq and ctx.spellrangeSq and mypetdistSq <= ctx.spellrangeSq
        if castutils.hpEvalSpawn(mypetid, AHThreshold[index].mypet) and distOk then return mypetid, 'mypet' end
    end
    return nil, nil
end

local function HPEvalPets(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].pet or not ctx.botcount then return nil, nil end
    for i = 1, ctx.botcount do
        local petid = mq.TLO.Spawn('pc =' .. ctx.bots[i]).Pet.ID()
        local petspawn = petid and mq.TLO.Spawn(petid)
        local petdistSq = petspawn and utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), petspawn.X(), petspawn.Y())
        if petid and petid > 0 then
            local distOk = ctx.spellrangeSq and petdistSq and petdistSq <= ctx.spellrangeSq
            if castutils.hpEvalSpawn(petid, AHThreshold[index].pet) and distOk then return petid, 'pet' end
        end
    end
    return nil, nil
end

local function HPEvalXtgt(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].xtgt then return nil, nil end
    local xtslots = mq.TLO.Me.XTargetSlots() or 0
    for i = 1, xtslots do
        if XTList[i] then
            local xtar = mq.TLO.Me.XTarget(i)()
            if xtar then
                local xtid = mq.TLO.Me.XTarget(i).ID() or 0
                if xtid and xtid > 0 then
                    local xtspawn = mq.TLO.Spawn(xtid)
                    local xtdistSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), xtspawn.X(), xtspawn.Y())
                    local distOk = ctx.spellrangeSq and xtdistSq and xtdistSq <= ctx.spellrangeSq
                    if castutils.hpEvalSpawn(xtid, AHThreshold[index].xtgt) and distOk then return xtid, 'xtgt' end
                end
            end
        end
    end
    return nil, nil
end

local HEAL_PHASE_ORDER_CORPSE = { 'corpse' }
local HEAL_PHASE_ORDER_HP = { 'self', 'groupheal', 'tank', 'offtank', 'groupmember', 'pc', 'mypet', 'pet', 'xtgt' }

local function healSpellResource(spellIndex)
    local entry = botconfig.getSpellEntry('heal', spellIndex)
    return (entry and entry.healResource) or 'hp'
end

local function healFilterIndicesByResource(indices, resource)
    local out = {}
    for _, i in ipairs(indices) do
        if healSpellResource(i) == resource then out[#out + 1] = i end
    end
    return out
end

local function healPassStartedCast()
    local cs = state.getRunconfig().CurSpell
    return cs and cs.sub == 'heal' and cs.spell
end

local function healEntryValid(spellIndex)
    local entry = botconfig.getSpellEntry('heal', spellIndex)
    if not entry then return false end
    if entry.enabled == false or entry.gem == 0 then return false end
    local minmanapct = entry.minmanapct
    local maxmanapct = entry.maxmanapct
    if minmanapct == nil then minmanapct = 0 end
    if maxmanapct == nil then maxmanapct = 100 end
    local mymana = mq.TLO.Me.PctMana()
    if mymana and (mymana < minmanapct or mymana > maxmanapct) then return false end
    return spellutils.SpellCheck('heal', spellIndex)
end

local function healGetTargetsForPhase(phase, context)
    if phase == 'self' then return castutils.getTargetsSelf() end
    if phase == 'tank' then return castutils.getTargetsTank(context) end
    if phase == 'offtank' then return castutils.getTargetsOfftank(context) end
    if phase == 'groupheal' then return castutils.getTargetsGroupCaster('groupheal') end
    if phase == 'groupmember' then return castutils.getTargetsGroupMember(context, { excludeSelfAndTank = true }) end
    if phase == 'pc' then return castutils.getTargetsPc(context, { excludeTank = true }) end
    if phase == 'mypet' then return castutils.getTargetsMypet() end
    if phase == 'pet' then return castutils.getTargetsPet(context) end
    if phase == 'xtgt' and XTList then
        local out = {}
        local n = mq.TLO.Me.XTargetSlots() or 0
        for i = 1, n do
            if XTList[i] and mq.TLO.Me.XTarget(i)() then
                local xtid = mq.TLO.Me.XTarget(i).ID()
                if xtid and xtid > 0 then out[#out + 1] = { id = xtid, targethit = 'xtgt' } end
            end
        end
        return out
    end
    if phase == 'corpse' then
        if not healCorpsePending() then return {} end
        local rezid = CorpseRezIdForFilter()
        if rezid then return { { id = rezid, targethit = 'corpse' } } end
        return {}
    end
    return {}
end

local function healBandHasPhase(spellIndex, phase)
    if not AHThreshold[spellIndex] then return false end
    if phase == 'corpse' then return AHThreshold[spellIndex].corpse end
    if phase == 'offtank' then return AHThreshold[spellIndex].offtank and true or false end
    return AHThreshold[spellIndex][phase] and true or false
end

local function rejectIfAlreadyHoT(entry, id, hit)
    if not id then return nil, nil end
    if spellutils.IsHoTSpell(entry) and spellutils.TargetHasHealSpell(entry, id) then return nil, nil end
    return id, hit
end

spellutils.setPrepareImmediateCastFn(function(sub, _index, evalId, targethit)
    if sub ~= 'heal' or targethit ~= 'corpse' or not evalId then return end
    if mq.TLO.Me.CastTimeLeft() > 0 then return end
    tickprof.span('corpse_TargetAndWait', function()
        targeting.TargetAndWait(evalId, 500)
    end, 'id=' .. tostring(evalId))
    mq.cmd('/corpse')
    tickprof.span('corpse_delay100', function()
        mq.delay(100)
    end)
end)

function botheal.HealCheck(runPriority)
    local count = botconfig.getSpellCount('heal')
    if count <= 0 then return false end
    local ctx = tickprof.span('context', function()
        return healBuildContext()
    end)
    if not ctx then return false end

    local contextBySpell = { [1] = ctx }
    local entryValidCache = {}
    local sharedBots = {
        tank = ctx.tank,
        tankid = ctx.tankid,
        bots = ctx.bots,
        botcount = ctx.botcount,
        tanknbid = ctx.tanknbid,
    }
    local function cachedHealContext(spellIndex)
        local cached = contextBySpell[spellIndex]
        if cached ~= nil then return cached end
        cached = HPEvalContext(spellIndex, sharedBots)
        contextBySpell[spellIndex] = cached
        return cached
    end
    local function cachedEntryValid(spellIndex)
        local cached = entryValidCache[spellIndex]
        if cached ~= nil then return cached end
        cached = healEntryValid(spellIndex)
        entryValidCache[spellIndex] = cached
        return cached
    end
    local function cachedTargetNeedsSpell(spellIndex, targetId, targethit, context, phase)
        local spellCtx = cachedHealContext(spellIndex)
        if not spellCtx then return nil, nil end
        if targethit == 'self' then
            local id, hit = HPEvalSelf(spellIndex, spellCtx)
            return rejectIfAlreadyHoT(spellCtx.entry, id, hit)
        end
        if targethit == 'tank' then
            local id, hit = HPEvalTank(spellIndex, spellCtx)
            if id == targetId then return rejectIfAlreadyHoT(spellCtx.entry, id, hit) end
            return nil, nil
        end
        if targethit == 'offtank' then
            local id, hit = HPEvalOfftank(spellIndex, spellCtx)
            if id == targetId then return rejectIfAlreadyHoT(spellCtx.entry, id, hit) end
            return nil, nil
        end
        if targethit == 'groupheal' then return HPEvalGrp(spellIndex, spellCtx) end
        if targethit == 'corpse' then
            local id, hit = HPEvalCorpse(spellIndex, spellCtx)
            if id == targetId then return id, hit end
            return nil, nil
        end
        if targethit == 'mypet' then
            local id, hit = HPEvalMyPet(spellIndex, spellCtx)
            if id == targetId then return rejectIfAlreadyHoT(spellCtx.entry, id, hit) end
            return nil, nil
        end
        if targethit == 'pet' then
            local id, hit = HPEvalPets(spellIndex, spellCtx)
            if id == targetId then return rejectIfAlreadyHoT(spellCtx.entry, id, hit) end
            return nil, nil
        end
        if targethit == 'xtgt' then
            local id, hit = HPEvalXtgt(spellIndex, spellCtx)
            if id == targetId then return rejectIfAlreadyHoT(spellCtx.entry, id, hit) end
            return nil, nil
        end
        if AHThreshold[spellIndex] then
            local th = AHThreshold[spellIndex]
            local classesForPhase = (phase == 'groupmember' and th.groupmember_classes) or (phase == 'pc' and th.pc_classes)
            local classOk
            if classesForPhase == nil then
                classOk = function() return true end
            else
                classOk = function(cls)
                    if not cls then return false end
                    local c = cls:lower()
                    if classesForPhase == 'all' then return true end
                    return classesForPhase and classesForPhase[c] == true
                end
            end
            local sp = mq.TLO.Spawn(targetId)
            if sp and sp.ID() == targetId and mq.TLO.Spawn(targetId).Type() == 'PC' then
                local distSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), sp.X(), sp.Y())
                if phase == 'groupmember' and th.groupmember
                    and castutils.hpEvalSpawn(targetId, th.groupmember)
                    and spellCtx.spellrangeSq and distSq and distSq <= spellCtx.spellrangeSq and classOk(targethit) then
                    return rejectIfAlreadyHoT(spellCtx.entry, targetId, targethit)
                end
                if phase == 'pc' and th.pc and context.botcount then
                    local peer = charinfo.GetInfo(mq.TLO.Spawn(targetId).CleanName())
                    local bothp = peer and peer.PctHPs or nil
                    if bothp and hpInBand(bothp, th.pc) and distSq and spellCtx.spellrangeSq and distSq <= spellCtx.spellrangeSq and classOk(targethit) then
                        return rejectIfAlreadyHoT(spellCtx.entry, targetId, targethit)
                    end
                end
            end
        end
        return nil, nil
    end

    local options = {
        runPriority = runPriority,
        entryValid = cachedEntryValid,
    }
    local cursor = spellutils.getResumeCursor('doHeal')
    if healCorpsePending() and cursor and cursor.phase and cursor.phase ~= 'corpse' then
        state.clearRunState()
        cursor = nil
    end
    local resumePass
    if cursor and cursor.spellIndex then
        resumePass = healSpellResource(cursor.spellIndex) == 'mana' and 'mana' or 'hp'
    end
    local function getSpellIndicesForResource(resource)
        return function(phase, _target)
            return healFilterIndicesByResource(
                spellutils.getSpellIndicesForPhase(count, phase, healBandHasPhase), resource)
        end
    end
    if resumePass ~= 'mana' then
        tickprof.span('pass_corpse', function()
            spellutils.RunPhaseFirstSpellCheck('heal', 'doHeal', HEAL_PHASE_ORDER_CORPSE, healGetTargetsForPhase,
                getSpellIndicesForResource('hp'), cachedTargetNeedsSpell, ctx, options)
        end)
        if healPassStartedCast() then return false end
        if healShouldHoldHealPass() then return false end
        tickprof.span('pass_hp', function()
            spellutils.RunPhaseFirstSpellCheck('heal', 'doHeal', HEAL_PHASE_ORDER_HP, healGetTargetsForPhase,
                getSpellIndicesForResource('hp'), cachedTargetNeedsSpell, ctx, options)
        end)
        if healPassStartedCast() then return false end
    end
    tickprof.span('pass_mana', function()
        spellutils.RunPhaseFirstSpellCheck('heal', 'doHeal', HEAL_PHASE_ORDER_HP, healGetTargetsForPhase,
            getSpellIndicesForResource('mana'), cachedTargetNeedsSpell, ctx, options)
    end)
    return false
end

function botheal.getHookFn(name)
    if name == 'doHeal' then
        return function(hookName)
            local myconfig = botconfig.config
            if state.isTravelMode() and not state.isTravelAttackOverriding() then return end
            if botmove.isBeyondFollowDistance() then return end
            if not (myconfig.settings.doheal or state.isTravelAttackOverriding()) or not (myconfig.heal.spells and #myconfig.heal.spells > 0) then return end
            if state.getRunState() == state.STATES.idle then state.getRunconfig().statusMessage = 'Heal Check' end
            botheal.HealCheck(bothooks.getPriority(hookName))
        end
    end
    return nil
end

--- Same predicate as pre-cast group heal (HPEvalGrp + evalGroupAECount). Used by spellutils mid-cast interrupt.
--- @param spellIndex number heal.spells index
--- @return number|nil id, string|nil targethit
function botheal.EvalGroupHealIfNeeded(spellIndex)
    local ctx = HPEvalContext(spellIndex)
    if not ctx then return nil, nil end
    return HPEvalGrp(spellIndex, ctx)
end

return botheal
