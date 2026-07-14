local mq = require('mq')
local botconfig = require('lib.config')
local spellbands = require('lib.spellbands')
local spellutils = require('lib.spellutils')
local state = require('lib.state')
local utils = require('lib.utils')
local charinfo = require('plugin.charinfo')
local charinfoutils = require('lib.charinfoutils')
local bothooks = require('lib.bothooks')
local castutils = require('lib.castutils')
local botmove = require('botmove')
local targeting = require('lib.targeting')
local czactor = require('lib.czactor')
local tickprof = require('lib.tickprof')

local pcphasethrottle = require('lib.pcphasethrottle')

local HEAL_UNAVAILABLE_PEER_STATES = { 'DEAD', 'FEIGN', 'HOVER' }

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
    local tank, tankid, bots, botcount, tanknbid, peerByName
    if shared then
        tank, tankid = shared.tank, shared.tankid
        bots, botcount = shared.bots, shared.botcount
        tanknbid = shared.tanknbid
        peerByName = shared.peerByName
    else
        tank, tankid = spellutils.GetTankInfo(false)
        bots, peerByName = spellutils.GetBotListOrderedWithPeers()
        botcount = bots and #bots or 0
        tanknbid = tank and ((peerByName and peerByName[tank]) or charinfo.GetInfo(tank)) ~= nil
    end
    local spellEntity = spellutils.GetSpellEntity(entry)
    if not spellEntity then
        local spell = spellutils.GetSpellInfo(entry)
        if not spell then return nil end
        return {
            entry = entry,
            gem = gem,
            spell = spell,
            spellrange = nil,
            spellrangeSq = nil,
            tank = tank,
            tankid = tankid,
            tanknbid = tanknbid,
            botcount = botcount,
            bots = bots,
            peerByName = peerByName,
        }
    end
    local spell = spellEntity.Name and spellEntity.Name() or entry.spell
    local spellrange = spellEntity.MyRange and spellEntity.MyRange() or nil
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
        peerByName = peerByName,
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
-- Pass-local memo: cleared at start of each HealCheck so hold/corpse paths share one scan.
local _corpseRezMemo = { valid = false, list = nil }

local function clearCorpseRezMemo()
    _corpseRezMemo.valid = false
    _corpseRezMemo.list = nil
end

local function _corpseRezCandidates()
    if _corpseRezMemo.valid then return _corpseRezMemo.list end
    local myconfig = botconfig.config
    local corpsecount = mq.TLO.SpawnCount('pccorpse radius ' .. myconfig.settings.acleash)()
    if not corpsecount or corpsecount == 0 then
        _corpseRezMemo.valid = true
        _corpseRezMemo.list = {}
        return _corpseRezMemo.list
    end
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
    _corpseRezMemo.valid = true
    _corpseRezMemo.list = candidates
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
    local tankinfo = charinfo.GetInfo(ctx.tank)
    local tankid = (tankinfo and tankinfo.ID) or ctx.tankid
    if not tankid or tankid <= 0 then return nil, nil end
    local meX = ctx.meX or mq.TLO.Me.X()
    local meY = ctx.meY or mq.TLO.Me.Y()
    local pct, distSq
    if tankinfo then
        pct = tankinfo.PctHPs
        local zone = tankinfo.Zone
        if zone and zone.X ~= nil and zone.Y ~= nil then
            distSq = utils.getDistanceSquared2D(meX, meY, zone.X, zone.Y)
        end
    end
    if pct == nil or distSq == nil then
        local tankspawn = mq.TLO.Spawn(tankid)
        if not tankspawn or not tankspawn.ID() or tankspawn.ID() == 0 then return nil, nil end
        if pct == nil then pct = tankspawn.PctHPs() end
        if distSq == nil then
            distSq = utils.getDistanceSquared2D(meX, meY, tankspawn.X(), tankspawn.Y())
        end
    end
    if not pct or not hpInBand(pct, AHThreshold[index].tank) then return nil, nil end
    if not (ctx.spellrangeSq and distSq and distSq <= ctx.spellrangeSq) then return nil, nil end
    if ctx.tanknbid or mq.TLO.Group.Member(ctx.tank).Index() then
        return tankid, 'tank'
    end
    return nil, nil
end

local function HPEvalOfftank(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].offtank then return nil, nil end
    local meX = ctx.meX or mq.TLO.Me.X()
    local meY = ctx.meY or mq.TLO.Me.Y()
    local czactor = require('lib.czactor')
    for _, ot in ipairs(czactor.getActiveOfftanks()) do
        local peer = charinfo.GetInfo(ot.name)
        local otid = peer and peer.ID
        local othp = peer and peer.PctHPs
        local distSq
        if peer and peer.Zone and peer.Zone.X ~= nil then
            distSq = utils.getDistanceSquared2D(meX, meY, peer.Zone.X, peer.Zone.Y)
        end
        if (not otid or otid <= 0) or othp == nil or distSq == nil then
            local sp = mq.TLO.Spawn('pc =' .. ot.name)
            if sp and sp.ID() and sp.ID() > 0 then
                otid = otid or sp.ID()
                if othp == nil then othp = sp.PctHPs() end
                if distSq == nil then
                    distSq = utils.getDistanceSquared2D(meX, meY, sp.X(), sp.Y())
                end
            end
        end
        if otid and otid > 0 and othp and hpInBand(othp, AHThreshold[index].offtank)
            and distSq and ctx.spellrangeSq and distSq <= ctx.spellrangeSq then
            return otid, 'offtank'
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
        local peer = charinfo.GetInfo(ctx.bots[i])
        local petid = peer and peer.PetID
        if (not petid or petid <= 0) and ctx.bots[i] then
            petid = mq.TLO.Spawn('pc =' .. ctx.bots[i]).Pet.ID()
        end
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
--- When no peer snap is in any heal band (and no groupheal/pet need), skip multi-target phases.
local HEAL_PHASE_ORDER_HP_URGENT = { 'self', 'tank' }

local function healRaidLooksHealthy(gate)
    if not gate then return false end
    return not gate.pc and not gate.groupmember and not gate.pet and not gate.groupheal
end

--- Prefer urgent self/tank-only pass when healthy; keep full order if resume needs a heavier phase.
local function healHpPhaseOrder(context, resumeCursor)
    if resumeCursor and resumeCursor.phase then
        local p = resumeCursor.phase
        if p ~= 'self' and p ~= 'tank' and p ~= 'corpse' then
            return HEAL_PHASE_ORDER_HP
        end
    end
    if healRaidLooksHealthy(context.healthyGate) then
        return HEAL_PHASE_ORDER_HP_URGENT
    end
    return HEAL_PHASE_ORDER_HP
end

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

--- Pass-local HP/dist snapshot by target id (shared across spells and phases in one HealCheck).
local function markHealSnapDead(snap)
    snap.dead = true
    snap.pct = nil
    return snap
end

local function ensureHealSnap(context, targetId, nameHint)
    if not context.healSnap then context.healSnap = {} end
    local snap = context.healSnap[targetId]
    if snap then
        -- fillHealPeerMaps may have cached this before death; re-check spawn Type.
        if not snap.dead then
            local sp = mq.TLO.Spawn(targetId)
            if sp and sp.ID() and sp.ID() > 0 and sp.Type() == 'Corpse' then
                return markHealSnapDead(snap)
            end
        end
        return snap
    end
    local meX = context.meX
    local meY = context.meY
    if meX == nil then
        meX = mq.TLO.Me.X()
        meY = mq.TLO.Me.Y()
        context.meX, context.meY = meX, meY
    end
    local name = nameHint or (context.peerNameById and context.peerNameById[targetId])
    local peer = (name and context.peerByName and context.peerByName[name])
        or (name and charinfo.GetInfo(name))
        or nil
    if not peer and not name then
        -- Try resolve peer by id once from already-filled maps.
        name = context.peerNameById and context.peerNameById[targetId]
        peer = name and context.peerByName and context.peerByName[name]
        if not peer and not name then
            local bots = context.bots
            if bots then
                local n = context.botcount or #bots
                for i = 1, n do
                    local nme = bots[i]
                    local p = (context.peerByName and context.peerByName[nme]) or charinfo.GetInfo(nme)
                    if p and p.ID == targetId then
                        name, peer = nme, p
                        if not context.peerNameById then context.peerNameById = {} end
                        context.peerNameById[targetId] = nme
                        break
                    end
                end
            end
        end
    end
    snap = { name = name, peer = peer, pct = nil, distSq = nil, dead = false }
    local sp = mq.TLO.Spawn(targetId)
    if sp and sp.ID() and sp.ID() > 0 and sp.Type() == 'Corpse' then
        context.healSnap[targetId] = markHealSnapDead(snap)
        return snap
    end
    if peer then
        snap.pct = peer.PctHPs
        local zone = peer.Zone
        if zone and zone.X ~= nil and zone.Y ~= nil then
            snap.distSq = utils.getDistanceSquared2D(meX, meY, zone.X, zone.Y)
        end
    end
    if snap.pct == nil or snap.distSq == nil then
        if sp and sp.ID() and sp.ID() > 0 then
            if not snap.name then snap.name = sp.CleanName() end
            if snap.pct == nil then snap.pct = sp.PctHPs and sp.PctHPs() end
            if snap.distSq == nil then
                snap.distSq = utils.getDistanceSquared2D(meX, meY, sp.X(), sp.Y())
            end
        end
    end
    context.healSnap[targetId] = snap
    return snap
end

local function pctInAnyHealBand(pct, phase)
    if pct == nil then return false end
    local count = botconfig.getSpellCount('heal')
    local bandKey = phase
    for i = 1, count do
        local th = AHThreshold[i]
        local band = th and th[bandKey]
        if band and hpInBand(pct, band) then return true end
    end
    return false
end

--- One GetInfo per peer for the HealCheck: fill healSnap, peerNameById, peerByName, healthyGate.
--- Reuses context.peerByName from GetBotListOrderedWithPeers when present (no second GetInfo pass).
local function fillHealPeerMaps(context)
    local meX = context.meX
    local meY = context.meY
    if meX == nil then
        meX = mq.TLO.Me.X()
        meY = mq.TLO.Me.Y()
        context.meX, context.meY = meX, meY
    end
    context.healSnap = context.healSnap or {}
    context.peerNameById = context.peerNameById or {}
    context.peerByName = context.peerByName or {}
    local bots = context.bots
    local n = context.botcount or (bots and #bots) or 0
    local gate = { pc = false, groupmember = false, pet = false, groupheal = false }

    local injuredSet = nil
    local injuredList = charinfo.GetInjuredPeers and charinfo.GetInjuredPeers() or nil
    if injuredList then
        injuredSet = {}
        for i = 1, #injuredList do
            local nm = injuredList[i]
            if nm then injuredSet[nm] = true end
        end
    end

    local myPct = mq.TLO.Me.PctHPs()
    local selfNeedsGroupheal = myPct and pctInAnyHealBand(myPct, 'groupheal')
    local injuredEmpty = injuredSet and next(injuredSet) == nil

    local function snapPeer(name, peer)
        context.peerByName[name] = peer
        local id = peer.ID
        if not id or id <= 0 then return nil end
        context.peerNameById[id] = name
        local distSq
        local zone = peer.Zone
        if zone and zone.X ~= nil and zone.Y ~= nil then
            distSq = utils.getDistanceSquared2D(meX, meY, zone.X, zone.Y)
        end
        local snap = {
            name = name,
            peer = peer,
            pct = peer.PctHPs,
            distSq = distSq,
            petId = peer.PetID,
            petHp = peer.PetHP,
            dead = false,
        }
        local sp = mq.TLO.Spawn(id)
        if sp and sp.ID() and sp.ID() > 0 and sp.Type() == 'Corpse' then
            markHealSnapDead(snap)
        elseif charinfoutils.peerHasAnyState(peer, HEAL_UNAVAILABLE_PEER_STATES)
            or (peer.PctHPs ~= nil and peer.PctHPs <= 0) then
            markHealSnapDead(snap)
        end
        context.healSnap[id] = snap
        return snap
    end

    -- Healthy fast path: no injured peers and self not in groupheal band.
    -- Do not snapPeer all bots (urgent pass only needs self/tank; ensureHealSnap fills on demand).
    -- Pets are not in GetInjuredPeers; probe PetHP from peers already on context.peerByName.
    if injuredEmpty and not selfNeedsGroupheal then
        for i = 1, n do
            local name = bots[i]
            if name then
                local peer = context.peerByName[name]
                if peer then
                    local petId = peer.PetID
                    local petHp = peer.PetHP
                    if petId and petId > 0 and petHp ~= nil and pctInAnyHealBand(petHp, 'pet') then
                        gate.pet = true
                    end
                end
            end
        end
        -- Non-Charinfo group members: probe real HP; do not treat "unknown" as injured.
        if mq.TLO.Group.Members() and mq.TLO.Group.Members() > 0 then
            for i = 1, mq.TLO.Group.Members() do
                local member = mq.TLO.Group.Member(i)
                local grpname = member and member.Name()
                if grpname and not context.peerByName[grpname] then
                    local pct = member.PctHPs and member.PctHPs()
                    if pct and pctInAnyHealBand(pct, 'groupmember') then
                        gate.groupmember = true
                        break
                    end
                end
            end
        end
        context.healthyGate = gate
        return
    end

    for i = 1, n do
        local name = bots[i]
        if name then
            local peer = context.peerByName[name] or charinfo.GetInfo(name)
            if peer then
                local snap = snapPeer(name, peer)
                if snap then
                    local checkBands = not injuredSet or injuredSet[name]
                    if checkBands and snap.pct ~= nil then
                        if pctInAnyHealBand(snap.pct, 'pc') then gate.pc = true end
                        if pctInAnyHealBand(snap.pct, 'groupmember') then gate.groupmember = true end
                        if pctInAnyHealBand(snap.pct, 'groupheal') then gate.groupheal = true end
                    end
                    if snap.petId and snap.petId > 0 and snap.petHp ~= nil then
                        if pctInAnyHealBand(snap.petHp, 'pet') then gate.pet = true end
                    end
                end
            end
        end
    end
    if selfNeedsGroupheal then gate.groupheal = true end
    -- Non-Charinfo group members: probe real HP; do not treat "unknown" as injured.
    if mq.TLO.Group.Members() and mq.TLO.Group.Members() > 0 then
        for i = 1, mq.TLO.Group.Members() do
            local member = mq.TLO.Group.Member(i)
            local grpname = member and member.Name()
            if grpname and not context.peerByName[grpname] then
                local pct = member.PctHPs and member.PctHPs()
                if pct and pctInAnyHealBand(pct, 'groupmember') then
                    gate.groupmember = true
                    break
                end
            end
        end
    end
    context.healthyGate = gate
end

local function filterCorpses(targets)
    if not targets or #targets == 0 then return targets end
    local out = {}
    for i = 1, #targets do
        local t = targets[i]
        if t and t.id and mq.TLO.Spawn(t.id).Type() ~= 'Corpse' then
            out[#out + 1] = t
        end
    end
    return out
end

local function healPrefilterByHp(phase, targets, context)
    if not targets or #targets == 0 then return targets end
    if phase ~= 'groupmember' and phase ~= 'pc' and phase ~= 'tank' and phase ~= 'offtank' and phase ~= 'pet' then
        return targets
    end
    local out = {}
    for i = 1, #targets do
        local t = targets[i]
        if t and t.id then
            if phase == 'pet' then
                -- Pet targets: match snap by petId or Spawn pct via ensureHealSnap.
                local pct
                for _, snap in pairs(context.healSnap or {}) do
                    if snap.petId == t.id then pct = snap.petHp break end
                end
                if pct == nil then
                    local snap = ensureHealSnap(context, t.id, t.name)
                    if not snap.dead then pct = snap.pct end
                end
                if pct ~= nil and pctInAnyHealBand(pct, 'pet') then
                    out[#out + 1] = t
                end
            else
                local snap = ensureHealSnap(context, t.id, t.name)
                if not snap.dead and snap.pct ~= nil and pctInAnyHealBand(snap.pct, phase) then
                    out[#out + 1] = t
                end
            end
        end
    end
    return out
end

local function peerNeedsHealFromSnap(snap, band, rangeSq, classOk, classHint)
    if not snap or not band then return false end
    if snap.dead then return false end
    if snap.peer and (
        charinfoutils.peerHasAnyState(snap.peer, HEAL_UNAVAILABLE_PEER_STATES)
        or (snap.peer.PctHPs ~= nil and snap.peer.PctHPs <= 0)
    ) then
        return false
    end
    if not snap.pct or not hpInBand(snap.pct, band) then return false end
    local cls = classHint
    if (not cls or cls == '') and snap.peer and snap.peer.Class and type(snap.peer.Class.ShortName) == 'string' then
        cls = snap.peer.Class.ShortName:lower()
    elseif cls then
        cls = cls:lower()
    end
    if classOk and not classOk(cls) then return false end
    return rangeSq and snap.distSq and snap.distSq <= rangeSq
end

local function healIndexPeerNames(targets, context)
    if not targets or #targets == 0 then return targets end
    local map = context.peerNameById
    if not map then
        map = {}
        context.peerNameById = map
    end
    for i = 1, #targets do
        local t = targets[i]
        if t and t.id and t.name then map[t.id] = t.name end
    end
    return targets
end

--- Peer HP/class/distance for heal cells. One GetInfo; distance from peer Zone.X/Y.
local function peerNeedsHeal(peer, band, rangeSq, meX, meY, classOk, classHint)
    if not peer or not band then return false end
    local pct = peer.PctHPs
    if not pct or not hpInBand(pct, band) then return false end
    local cls = classHint
    if (not cls or cls == '') and peer.Class and type(peer.Class.ShortName) == 'string' then
        cls = peer.Class.ShortName:lower()
    elseif cls then
        cls = cls:lower()
    end
    if classOk and not classOk(cls) then return false end
    local zone = peer.Zone
    if not zone or zone.X == nil or zone.Y == nil then return false end
    local distSq = utils.getDistanceSquared2D(meX, meY, zone.X, zone.Y)
    return rangeSq and distSq and distSq <= rangeSq
end

local function healGetTargetsForPhase(phase, context)
    local gate = context.healthyGate
    if gate and (phase == 'pc' or phase == 'groupmember' or phase == 'pet' or phase == 'groupheal') then
        if not gate[phase] then return {} end
    end
    local targets
    if phase == 'self' then
        targets = castutils.getTargetsSelf()
    elseif phase == 'tank' then
        targets = filterCorpses(castutils.getTargetsTank(context))
    elseif phase == 'offtank' then
        targets = filterCorpses(castutils.getTargetsOfftank(context))
    elseif phase == 'groupheal' then
        targets = castutils.getTargetsGroupCaster('groupheal')
    elseif phase == 'groupmember' then
        targets = healIndexPeerNames(filterCorpses(castutils.getTargetsGroupMember(context, { excludeSelfAndTank = true })), context)
    elseif phase == 'pc' then
        targets = healIndexPeerNames(filterCorpses(castutils.getTargetsPc(context, { excludeTank = true })), context)
    elseif phase == 'mypet' then
        targets = filterCorpses(castutils.getTargetsMypet())
    elseif phase == 'pet' then
        targets = filterCorpses(castutils.getTargetsPet(context))
    elseif phase == 'xtgt' and XTList then
        targets = {}
        local n = mq.TLO.Me.XTargetSlots() or 0
        for i = 1, n do
            if XTList[i] and mq.TLO.Me.XTarget(i)() then
                local xtid = mq.TLO.Me.XTarget(i).ID()
                if xtid and xtid > 0 then targets[#targets + 1] = { id = xtid, targethit = 'xtgt' } end
            end
        end
        targets = filterCorpses(targets)
    elseif phase == 'corpse' then
        if not healCorpsePending() then return {} end
        local cursor = spellutils.getResumeCursor('doHeal')
        if not pcphasethrottle.allow('heal', cursor, 'corpse') then return {} end
        local rezid = CorpseRezIdForFilter()
        if rezid then return { { id = rezid, targethit = 'corpse' } } end
        return {}
    else
        return {}
    end
    return healPrefilterByHp(phase, targets, context)
end

local function healBandHasPhase(spellIndex, phase)
    if not AHThreshold[spellIndex] then return false end
    if phase == 'corpse' then return AHThreshold[spellIndex].corpse end
    if phase == 'offtank' then return AHThreshold[spellIndex].offtank and true or false end
    return AHThreshold[spellIndex][phase] and true or false
end

--- Phases that have at least one mana-resource heal with that band (preserves HP order).
local function healManaPhaseOrder()
    local count = botconfig.getSpellCount('heal')
    local seen = {}
    for i = 1, count do
        if healSpellResource(i) == 'mana' then
            for _, phase in ipairs(HEAL_PHASE_ORDER_HP) do
                if healBandHasPhase(i, phase) then seen[phase] = true end
            end
        end
    end
    local ordered = {}
    for _, phase in ipairs(HEAL_PHASE_ORDER_HP) do
        if seen[phase] then ordered[#ordered + 1] = phase end
    end
    return ordered
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
    clearCorpseRezMemo()
    local ctx = tickprof.span('context', function()
        return healBuildContext()
    end)
    if not ctx then return false end
    tickprof.span('peer_maps', function()
        ctx.meX = mq.TLO.Me.X()
        ctx.meY = mq.TLO.Me.Y()
        ctx.healSnap = {}
        fillHealPeerMaps(ctx)
    end)

    local contextBySpell = { [1] = ctx }
    local entryValidCache = {}
    local sharedBots = {
        tank = ctx.tank,
        tankid = ctx.tankid,
        bots = ctx.bots,
        botcount = ctx.botcount,
        tanknbid = ctx.tanknbid,
        peerByName = ctx.peerByName,
    }
    local function cachedHealContext(spellIndex)
        local cached = contextBySpell[spellIndex]
        if cached ~= nil then
            cached.meX, cached.meY = ctx.meX, ctx.meY
            return cached
        end
        cached = HPEvalContext(spellIndex, sharedBots)
        if cached then
            cached.meX, cached.meY = ctx.meX, ctx.meY
        end
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
        local th = AHThreshold[spellIndex]

        if targethit == 'self' then
            local id, hit = HPEvalSelf(spellIndex, spellCtx)
            return rejectIfAlreadyHoT(spellCtx.entry, id, hit)
        end
        if targethit == 'tank' then
            if not th or not th.tank then return nil, nil end
            local snap = ensureHealSnap(context, targetId, context.tank or spellCtx.tank)
            if not peerNeedsHealFromSnap(snap, th.tank, spellCtx.spellrangeSq, nil, nil) then
                return nil, nil
            end
            if spellCtx.tanknbid or (spellCtx.tank and mq.TLO.Group.Member(spellCtx.tank).Index()) then
                return rejectIfAlreadyHoT(spellCtx.entry, targetId, 'tank')
            end
            return nil, nil
        end
        if targethit == 'offtank' then
            if not th or not th.offtank then return nil, nil end
            local snap = ensureHealSnap(context, targetId, nil)
            if peerNeedsHealFromSnap(snap, th.offtank, spellCtx.spellrangeSq, nil, nil) then
                return rejectIfAlreadyHoT(spellCtx.entry, targetId, 'offtank')
            end
            return nil, nil
        end
        if targethit == 'groupheal' then return HPEvalGrp(spellIndex, spellCtx) end
        if targethit == 'corpse' then
            local id, hit = HPEvalCorpse(spellIndex, spellCtx)
            if id == targetId then return id, hit end
            return nil, nil
        end
        if targethit == 'mypet' then
            if not th or not th.mypet then return nil, nil end
            if targetId ~= mq.TLO.Me.Pet.ID() then return nil, nil end
            local snap = ensureHealSnap(context, targetId, nil)
            local distOk = snap.distSq and spellCtx.spellrangeSq and snap.distSq <= spellCtx.spellrangeSq
            if snap.pct and hpInBand(snap.pct, th.mypet) and distOk then
                return rejectIfAlreadyHoT(spellCtx.entry, targetId, 'mypet')
            end
            return nil, nil
        end
        if targethit == 'pet' then
            if not th or not th.pet then return nil, nil end
            local snap = ensureHealSnap(context, targetId, nil)
            local distOk = spellCtx.spellrangeSq and snap.distSq and snap.distSq <= spellCtx.spellrangeSq
            if snap.pct and hpInBand(snap.pct, th.pet) and distOk then
                return rejectIfAlreadyHoT(spellCtx.entry, targetId, 'pet')
            end
            return nil, nil
        end
        if targethit == 'xtgt' then
            if not th or not th.xtgt then return nil, nil end
            local snap = ensureHealSnap(context, targetId, nil)
            local distOk = spellCtx.spellrangeSq and snap.distSq and snap.distSq <= spellCtx.spellrangeSq
            if snap.pct and hpInBand(snap.pct, th.xtgt) and distOk then
                return rejectIfAlreadyHoT(spellCtx.entry, targetId, 'xtgt')
            end
            return nil, nil
        end
        if th then
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
            local name = context.peerNameById and context.peerNameById[targetId]
            if phase == 'pc' and th.pc then
                if not name then return nil, nil end
                local snap = ensureHealSnap(context, targetId, name)
                if peerNeedsHealFromSnap(snap, th.pc, spellCtx.spellrangeSq, classOk, targethit) then
                    return rejectIfAlreadyHoT(spellCtx.entry, targetId, targethit)
                end
                return nil, nil
            end
            if phase == 'groupmember' and th.groupmember then
                local snap = ensureHealSnap(context, targetId, name)
                if snap.peer or name then
                    if peerNeedsHealFromSnap(snap, th.groupmember, spellCtx.spellrangeSq, classOk, targethit) then
                        return rejectIfAlreadyHoT(spellCtx.entry, targetId, targethit)
                    end
                    if snap.peer then return nil, nil end
                end
                -- Non-bot group member without peer: snap may still have Spawn-filled pct/dist.
                if peerNeedsHealFromSnap(snap, th.groupmember, spellCtx.spellrangeSq, classOk, targethit) then
                    return rejectIfAlreadyHoT(spellCtx.entry, targetId, targethit)
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
    local indicesCache = {}
    local function getSpellIndicesForResource(resource)
        return function(phase, _target)
            local key = resource .. ':' .. tostring(phase)
            local cached = indicesCache[key]
            if cached then return cached end
            cached = healFilterIndicesByResource(
                spellutils.getSpellIndicesForPhase(count, phase, healBandHasPhase), resource)
            indicesCache[key] = cached
            return cached
        end
    end
    if resumePass ~= 'mana' then
        local needCorpse = healCorpsePending()
            or (cursor and cursor.phase == 'corpse')
        if needCorpse then
            tickprof.span('pass_corpse', function()
                spellutils.RunPhaseFirstSpellCheck('heal', 'doHeal', HEAL_PHASE_ORDER_CORPSE, healGetTargetsForPhase,
                    getSpellIndicesForResource('hp'), cachedTargetNeedsSpell, ctx, options)
            end)
            if healPassStartedCast() then return false end
        end
        if healShouldHoldHealPass() then return false end
        local hpOrder = healHpPhaseOrder(ctx, cursor)
        tickprof.span('pass_hp', function()
            spellutils.RunPhaseFirstSpellCheck('heal', 'doHeal', hpOrder, healGetTargetsForPhase,
                getSpellIndicesForResource('hp'), cachedTargetNeedsSpell, ctx, options)
        end)
        if healPassStartedCast() then return false end
    end
    local manaPhases = healManaPhaseOrder()
    if #manaPhases > 0 then
        tickprof.span('pass_mana', function()
            spellutils.RunPhaseFirstSpellCheck('heal', 'doHeal', manaPhases, healGetTargetsForPhase,
                getSpellIndicesForResource('mana'), cachedTargetNeedsSpell, ctx, options)
        end)
    end
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
