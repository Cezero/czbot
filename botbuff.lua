local mq = require('mq')
local botconfig = require('lib.config')
local spellbands = require('lib.spellbands')
local spellutils = require('lib.spellutils')
local state = require('lib.state')
local utils = require('lib.utils')
local charinfo = require('plugin.charinfo')
local bothooks = require('lib.bothooks')
local castutils = require('lib.castutils')
local buffphase = require('lib.buffphase')
local botmove = require('botmove')
local tickprof = require('lib.tickprof')

local charinfowatchers = require('lib.charinfowatchers')
local nonpeerraidbuff = require('lib.nonpeerraidbuff')

local botbuff = {}
local BuffClass = {}
local bardtwist = require('lib.bardtwist')
--- Module-level spell meta (id/range/ae) cleared on buff config reload.
local _buffSpellMeta = {}
--- Phase -> spell index lists; rebuilt on buff config reload (stable until then).
local _buffIndicesByPhase = {}
--- Assigned after buffBandHasPhase / getOrBuildSpellCache exist.
local rebuildBuffIndicesByPhase

local function defaultBuffEntry()
    return botconfig.getDefaultSpellEntry('buff')
end

function botbuff.LoadBuffConfig()
    _buffSpellMeta = {}
    _buffIndicesByPhase = {}
    spellutils.BuffSkipClearAll()
    castutils.LoadSpellSectionConfig('buff', {
        defaultEntry = defaultBuffEntry,
        bandsKey = 'buff',
        storeIn = BuffClass,
        perEntryAfterBands = function(entry, i)
            entry.spellicon = charinfowatchers.normalizeSpelliconList(entry.spellicon)
            BuffClass[i].petspell = spellutils.IsPetSummonSpell(entry) or BuffClass[i].petspell
            buffphase.sanitizeRuntimePhases(entry, BuffClass[i])
        end,
    })
    if rebuildBuffIndicesByPhase then
        rebuildBuffIndicesByPhase()
    end
    charinfowatchers.registerBuffWatchers()
end

castutils.RegisterSectionLoader('buff', 'dobuff', botbuff.LoadBuffConfig)

--- Resolve charinfo peer from pass cache, then GetInfo (memoized on hoist.peerResolveCache).
local function resolvePeer(name, context, hoist)
    if not name or name == '' then return nil end
    local cache = hoist and hoist.peerResolveCache
    if cache and cache[name] ~= nil then
        local v = cache[name]
        return v ~= false and v or nil
    end
    local map = (hoist and hoist.peerByName) or (context and context.peerByName)
    local peer = (map and map[name]) or charinfo.GetInfo(name)
    if cache then
        cache[name] = peer or false
    end
    return peer
end

local function IconCheck(index, EvalID, knownName, peerHint, context, hoist)
    local entry = botconfig.getSpellEntry('buff', index)
    if not entry then return true end
    local icons = charinfowatchers.normalizeSpelliconList(entry.spellicon)
    if #icons == 0 then return true end
    local botname = knownName
    if not botname or botname == '' then
        botname = mq.TLO.Spawn(EvalID).Name()
    end
    local info = peerHint or resolvePeer(botname, context, hoist)
    for _, spellicon in ipairs(icons) do
        if info and spellutils.PeerHasBuff(info, spellicon) then
            return false
        end
    end
    return true
end

--- Optional entry.height: cast only when spawn Height exceeds threshold (SPA 89 shrink). Nil/0 = no filter.
local function heightAllowsSpawn(entry, spawnId)
    local threshold = entry and tonumber(entry.height)
    if (not threshold or threshold <= 0) and spellutils.IsShrinkSpell(entry) then
        threshold = 2.4
    end
    if not threshold or threshold <= 0 then return true end
    if not spawnId or spawnId <= 0 then return false end
    local ht = mq.TLO.Spawn(spawnId).Height()
    return ht ~= nil and ht > threshold
end

local function heightAllowsMe(entry)
    local threshold = entry and tonumber(entry.height)
    if (not threshold or threshold <= 0) and spellutils.IsShrinkSpell(entry) then
        threshold = 2.4
    end
    if not threshold or threshold <= 0 then return true end
    local ht = mq.TLO.Me.Height()
    return ht ~= nil and ht > threshold
end

local function peerPetBuffStillUp(peerName, peer, spellid)
    local key = peerName and (peerName .. '#pet') or nil
    if not key or not peer or not spellid then return false end
    if spellutils.BuffSkipIsActive(key, spellid) then return true end
    local dur = spellutils.PeerGetPetBuffDuration(peer, spellid)
    if dur ~= nil then
        return spellutils.BuffSkipObserveDuration(key, spellid, dur)
    end
    if spellutils.PeerHasPetBuff(peer, spellid) then
        return spellutils.BuffSkipObservePresent(key, spellid)
    end
    spellutils.BuffSkipClear(key, spellid)
    return false
end

--- Peer cast gate after watchlist membership. Watch covers need/Stacks/slots; Lua: range only.
local function BuffEvalBotNeedsBuff(botid, botname, spellid, rangeSq, index, targethit, peerHint, context, hoist)
    if not botname or not spellid then return nil, nil end
    local peer = peerHint or resolvePeer(botname, context, hoist)
    if not peer then return nil, nil end
    local spawnid = peer.ID
    if not spawnid or spawnid <= 0 then
        spawnid = botid
    end
    if not spawnid or spawnid <= 0 then
        spellutils.BuffLog('skip %s [%s]: no spawn', botname, targethit)
        return nil, nil
    end
    local botdistSq
    local zone = peer.Zone
    if zone and zone.X ~= nil and zone.Y ~= nil then
        botdistSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), zone.X, zone.Y)
    else
        local botspawn = mq.TLO.Spawn(spawnid)
        botdistSq = botspawn and utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), botspawn.X(), botspawn.Y())
    end
    if rangeSq and botdistSq and botdistSq <= rangeSq then return spawnid, targethit end
    spellutils.BuffLog('skip %s [%s]: out of range', botname, targethit)
    return nil, nil
end

local function getMeBuffState(meBuffCache, spell)
    if not spell then return false, nil end
    if meBuffCache then
        local hit = meBuffCache[spell]
        if hit ~= nil then return hit.present, hit.duration end
    end
    local present = mq.TLO.Me.Buff(spell)() or mq.TLO.Me.Song(spell)()
    local duration = nil
    if present then
        duration = mq.TLO.Me.Buff(spell).Duration()
        if duration == nil and mq.TLO.Me.Song(spell).Duration then
            duration = mq.TLO.Me.Song(spell).Duration()
        end
    end
    if meBuffCache then
        meBuffCache[spell] = { present = present and true or false, duration = duration }
    end
    return present and true or false, duration
end

local function BuffEvalSelf(index, entry, spell, spellid, range, myid, myclass, tanktar, hoist, spellMeta)
    if not BuffClass[index] then return nil, nil end
    local selfKey = (hoist and hoist.selfKey) or (mq.TLO.Me.Name() or '__self__')
    local meBuffCache = hoist and hoist.meBuffCache
    if myclass ~= 'BRD' then
        local mypetid = hoist and hoist.myPetId
        if mypetid == nil then
            mypetid = mq.TLO.Me.Pet.ID()
            if hoist then hoist.myPetId = mypetid end
        end
        -- Pet summon / self icon checks use Me TLOs (self is not a charinfo peer).
        if BuffClass[index].petspell and mypetid == 0 then
            local petEntry = botconfig.getSpellEntry('buff', index)
            local spellicon = petEntry and petEntry.spellicon
            local iconBlocks = false
            local icons = type(spellicon) == 'table' and spellicon
                or ((spellicon and spellicon ~= 0) and { spellicon } or {})
            for _, iconId in ipairs(icons) do
                local iconSpell = mq.TLO.Spell(iconId).Name()
                if iconSpell and iconSpell ~= ''
                    and (mq.TLO.Me.Buff(iconSpell)() or mq.TLO.Me.Song(iconSpell)()) then
                    iconBlocks = true
                    break
                end
            end
            if not iconBlocks then
                local hasBuff = select(1, getMeBuffState(meBuffCache, spell))
                if not hasBuff then
                    return myid, 'petspell'
                end
            end
        end
        if BuffClass[index].petspell and mypetid > 0 then
            return nil, nil
        end
        if BuffClass[index].self then
            if not heightAllowsMe(entry) then
                spellutils.BuffLog('skip self %s: height at or below threshold', spell)
                return nil, nil
            end
            if spellid and spellutils.BuffSkipIsActive(selfKey, spellid) then
                spellutils.BuffLog('skip self %s: duration skip window', spell)
                return nil, nil
            end
            local buff, buffdur = getMeBuffState(meBuffCache, spell)
            if buff then
                if spellid and buffdur and spellutils.BuffSkipObserveDuration(selfKey, spellid, buffdur) then
                    spellutils.BuffLog('skip self %s: still up', spell)
                    return nil, nil
                end
                if buffdur and buffdur >= spellutils.BUFF_REFRESH_THRESHOLD_MS then
                    spellutils.BuffLog('skip self %s: still up', spell)
                    return nil, nil
                end
                -- Below refresh threshold: only recast if we have cast time + free slot.
                local mycasttime = spellMeta and spellMeta.myCastTime
                if mycasttime == nil then
                    mycasttime = mq.TLO.Spell(spell).MyCastTime()
                    if spellMeta then spellMeta.myCastTime = mycasttime end
                end
                local freebuffslots = hoist and hoist.freeBuffSlots
                if freebuffslots == nil then
                    freebuffslots = mq.TLO.Me.FreeBuffSlots()
                    if hoist then hoist.freeBuffSlots = freebuffslots end
                end
                if not (buffdur and buffdur < spellutils.BUFF_REFRESH_THRESHOLD_MS and mycasttime and mycasttime > 0 and freebuffslots and freebuffslots > 0) then
                    spellutils.BuffLog('skip self %s: still up', spell)
                    return nil, nil
                end
            elseif spellid then
                spellutils.BuffSkipClear(selfKey, spellid)
            end
            -- Defer Stacks until we know we may need to cast. Icon-equivalent: Me buff/song by spellicon name if set.
            local entry = botconfig.getSpellEntry('buff', index)
            local spellicon = entry and entry.spellicon
            local iconBlocks = false
            local icons = type(spellicon) == 'table' and spellicon
                or ((spellicon and spellicon ~= 0) and { spellicon } or {})
            for _, iconId in ipairs(icons) do
                local iconSpell = mq.TLO.Spell(iconId).Name()
                if iconSpell and iconSpell ~= ''
                    and (mq.TLO.Me.Buff(iconSpell)() or mq.TLO.Me.Song(iconSpell)()) then
                    iconBlocks = true
                    break
                end
            end
            if not iconBlocks then
                local stacks = spellMeta and spellMeta.stacks
                if stacks == nil then
                    stacks = mq.TLO.Spell(spell).Stacks()
                    if spellMeta then spellMeta.stacks = stacks end
                end
                if not stacks then
                    spellutils.BuffLog('skip self %s: will not stack', spell)
                    return nil, nil
                end
                return myid, 'self'
            else
                spellutils.BuffLog('skip self %s: already present (icon)', spell)
            end
        end
        return nil, nil
    end
    -- BRD: all self buffs are handled by twist (lib/bardtwist). No cast from buff hook; detrimental-on-tank removed.
    if myclass == 'BRD' and BuffClass[index].self then
        return nil, nil
    end
    return nil, nil
end

local function BuffEvalTank(index, entry, spell, spellid, rangeSq, tank, tankid, context, hoist)
    if not tank or not entry or not BuffClass[index].tank or not tankid or tankid <= 0 then return nil, nil end
    local peer = resolvePeer(tank, context, hoist)
    if peer then
        return BuffEvalBotNeedsBuff(tankid, tank, spellid, rangeSq, index, 'tank', peer, context, hoist)
    end
    if not IconCheck(index, tankid, tank, nil, context, hoist) then return nil, nil end
    local tankspawn = mq.TLO.Spawn(tankid)
    local tankdistSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), tankspawn.X(), tankspawn.Y())
    if not rangeSq or not tankdistSq or tankdistSq > rangeSq then return nil, nil end
    if not spellutils.EnsureSpawnBuffsPopulated(tankid, 'buff', index, 'tank', nil, 'after_tank', nil) then
        return nil, nil
    end
    if heightAllowsSpawn(entry, tankid) and spellutils.SpawnNeedsBuff(tankid, spell, entry.spellicon) then
        return tankid, 'tank'
    end
    return nil, nil
end

-- Avoid storing mq.TLO.Spell/FindItem.Spell proxy; use direct chains (TLO quirk).
local function getSpellRanges(entry)
    if not entry or not entry.spell then return nil, nil end
    if entry.gem == 'item' then
        if not mq.TLO.FindItem(entry.spell)() then return nil, nil end
        return mq.TLO.FindItem(entry.spell).Spell.MyRange(), mq.TLO.FindItem(entry.spell).Spell.AERange()
    end
    return mq.TLO.Spell(entry.spell).MyRange(), mq.TLO.Spell(entry.spell).AERange()
end

local function BuffEvalGroupBuff(index, entry, spell, spellid, range, aeRange, context, hoist)
    if not aeRange then
        local _
        _, aeRange = getSpellRanges(entry)
    end
    if not aeRange or aeRange <= 0 then return nil, nil end
    local sid = spellid or spellutils.GetSpellId(entry)
    if not sid then return nil, nil end

    local function selfPasses()
        local present = mq.TLO.Me.Buff(spell)() or mq.TLO.Me.Song(spell)()
        if not present then return true end
        local dur = mq.TLO.Me.Buff(spell).Duration() or mq.TLO.Me.Song(spell).Duration() or 0
        return dur < 20000
    end

    local nonPeerNeeds = 0
    if charinfowatchers.hasNonPeerGroupMembers() then
        for _, m in ipairs(charinfowatchers.getNonPeerGroupMembers()) do
            if m.id and m.id > 0
                and spellutils.EnsureSpawnBuffsPopulated(m.id, 'buff', index, 'groupbuff', nil, nil, nil)
                and heightAllowsSpawn(entry, m.id)
                and spellutils.SpawnNeedsBuff(m.id, spell, entry.spellicon) then
                nonPeerNeeds = nonPeerNeeds + 1
            end
        end
    end

    if not charinfowatchers.grpAggShouldCast('BUFF', sid, entry.tarcnt, selfPasses, nonPeerNeeds) then
        return nil, nil
    end
    local spellEnt = spellutils.GetSpellEntity(entry)
    local id = (spellEnt and spellEnt.TargetType() == 'Group v1') and 1 or mq.TLO.Me.ID()
    return id, 'groupbuff'
end

local function BuffEvalMyPet(index, entry, spell, spellid, rangeSq)
    if not BuffClass[index].mypet then return nil, nil end
    local mypetid = mq.TLO.Me.Pet.ID()
    if not mypetid or mypetid <= 0 then return nil, nil end
    local selfKey = mq.TLO.Me.Name() or '__self__'
    -- Self is not a charinfo peer; use Me.Pet buff TLOs only.
    local petbuff = mq.TLO.Me.Pet.Buff(spell)()
    if petbuff then
        if spellid then spellutils.BuffSkipObservePresent(selfKey .. '#pet', spellid) end
        return nil, nil
    end
    if spellid and spellutils.BuffSkipIsActive(selfKey .. '#pet', spellid) then
        return nil, nil
    end
    local mypetSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Pet.X(), mq.TLO.Me.Pet.Y())
    local petstacks = true
    if spellid and mq.TLO.Spell(spellid).StacksPet then
        petstacks = mq.TLO.Spell(spellid).StacksPet() and true or false
    end
    if petstacks and mypetSq and rangeSq and mypetSq <= rangeSq then
        return mypetid, 'mypet'
    end
    return nil, nil
end

--- Evaluate a single listed pet spawn (no full peer-pet rescan).
local function BuffEvalPetById(index, spellid, rangeSq, petId, context, hoist)
    if not BuffClass[index].pet or not petId or petId <= 0 then return nil, nil end
    local petSpawn = mq.TLO.Spawn(petId)
    if not petSpawn or not petSpawn.ID() or petSpawn.ID() == 0 then return nil, nil end
    local masterName = petSpawn.Master and (petSpawn.Master.CleanName() or petSpawn.Master.Name())
    if not masterName or masterName == '' then return nil, nil end
    local peer = resolvePeer(masterName, context, hoist)
    if not peer then return nil, nil end
    if peerPetBuffStillUp(masterName, peer, spellid) then return nil, nil end
    local petdistSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), petSpawn.X(), petSpawn.Y())
    local petstacks = peer:StacksPet(spellid)
    local ownerId = peer.ID
    if ownerId and ownerId > 0 and petstacks and IconCheck(index, ownerId, masterName, peer, context, hoist)
        and rangeSq and petdistSq and petdistSq <= rangeSq then
        return petId, 'pet'
    end
    return nil, nil
end

local BUFF_PHASE_ORDER = { 'self', 'tank', 'offtank', 'groupbuff', 'groupmember', 'pc', 'mypet', 'pet' }
local BUFF_PHASE_ORDER_LOCAL = { 'self', 'mypet' }
local BUFF_PHASE_ORDER_LOCAL_LIST = { 'self', 'tank', 'offtank', 'mypet' }
--- Single place for buff context: tank, tankid, buffCount. Peer roster not preloaded (PET watches + GetInfo on demand).
local function buffBuildContext()
    local tank, tankid = spellutils.GetTankInfo(false)
    local count = botconfig.getSpellCount('buff')
    return {
        tank = tank,
        tankid = tankid,
        buffCount = count,
        bots = {},
        botcount = 0,
        peerByName = {},
    }
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

local function buffBandHasPhase(spellIndex, phase)
    if phase == 'pet' or phase == 'mypet' then
        local meta = _buffSpellMeta[spellIndex]
        if meta and meta.isGroupAE then return false end
    end
    return castutils.bandHasPhaseSimple(BuffClass, spellIndex, phase)
end

local function buffPhaseOrderForPass()
    local listIds = charinfowatchers.spellIdsForPhases('buff', { 'tank', 'offtank' }, buffBandHasPhase)
    local otherIds = charinfowatchers.spellIdsForPhases(
        'buff', { 'groupbuff', 'groupmember', 'pc', 'pet' }, buffBandHasPhase)
    local hasNonPeerRaid = botconfig.config.settings.buffNonPeerRaid == true and nonpeerraidbuff.hasMembers()
    local hasList = charinfowatchers.anyWatchNonEmpty('BUFF', { 'LIST' }, listIds)
    local hasOther = charinfowatchers.anyWatchNonEmpty(
        'BUFF', { 'INGROUP', 'ALL', 'GRPAGG', 'PET' }, otherIds)
        or charinfowatchers.hasNonPeerGroupMembers()
        or hasNonPeerRaid
    local order
    if hasOther then
        order = BUFF_PHASE_ORDER
    elseif hasList then
        order = BUFF_PHASE_ORDER_LOCAL_LIST
    else
        order = BUFF_PHASE_ORDER_LOCAL
    end
    if not hasNonPeerRaid then return order end
    local out = {}
    local inserted = false
    for i = 1, #order do
        out[#out + 1] = order[i]
        if order[i] == 'pc' then
            out[#out + 1] = 'nonpeerraid'
            inserted = true
        end
    end
    if not inserted then
        out[#out + 1] = 'nonpeerraid'
    end
    return out
end

local function buffGetTargetsForPhase(phase, context, hoist)
    if phase == 'self' then return castutils.getTargetsSelf() end
    if phase == 'nonpeerraid' then
        local out = {}
        for _, m in ipairs(nonpeerraidbuff.getMembers()) do
            if m.id and m.id > 0 then
                out[#out + 1] = {
                    id = m.id,
                    name = m.name,
                    class = m.class,
                    targethit = 'pc',
                    nonPeerRaid = true,
                }
            end
        end
        return filterCorpses(out)
    end
    if phase == 'tank' or phase == 'offtank' or phase == 'groupmember' or phase == 'pc' then
        local count = botconfig.getSpellCount('buff')
        -- CharInfo watches already exclude corpses; skip Spawn.Type filter on watch unions.
        local out = charinfowatchers.unionTargetsForPhase('buff', phase, count, buffBandHasPhase)
        -- Non-peer group members are invisible to CharInfo watches; merge when flag is set.
        if phase == 'groupmember' and charinfowatchers.hasNonPeerGroupMembers() then
            local seen = {}
            for i = 1, #out do
                if out[i].id then seen[out[i].id] = true end
            end
            for _, m in ipairs(charinfowatchers.getNonPeerGroupMembers()) do
                if m.id and m.id > 0 and not seen[m.id] then
                    seen[m.id] = true
                    out[#out + 1] = { id = m.id, targethit = 'groupmember', name = m.name, nonPeer = true }
                end
            end
            out = filterCorpses(out)
        end
        return out
    end
    if phase == 'groupbuff' then
        return castutils.getTargetsGroupCaster('groupbuff')
    end
    if phase == 'mypet' then return castutils.getTargetsMypet() end
    if phase == 'pet' then
        local count = botconfig.getSpellCount('buff')
        return charinfowatchers.unionTargetsForPhase('buff', phase, count, buffBandHasPhase)
    end
    return {}
end

local function getOrBuildSpellCache(spellIndex, spellCache)
    local cached = spellCache and spellCache[spellIndex]
    if cached then return cached end
    cached = _buffSpellMeta[spellIndex]
    if cached then
        -- Refresh entry pointer from config; keep resolved meta.
        cached.entry = botconfig.getSpellEntry('buff', spellIndex) or cached.entry
        if spellCache then spellCache[spellIndex] = cached end
        return cached
    end
    local entry = botconfig.getSpellEntry('buff', spellIndex)
    if not entry or not BuffClass[spellIndex] then return nil end
    local spell, _, _, spellid = spellutils.GetSpellInfo(entry)
    if not spell or not spellid then return nil end
    local sid = (spellid == 1536) and 1538 or spellid
    local myRange, aeRange = getSpellRanges(entry)
    local range = (myRange and myRange > 0) and myRange or aeRange
    local rangeSq = range and (range * range) or nil
    cached = {
        entry = entry,
        spell = spell,
        sid = sid,
        myRange = myRange,
        aeRange = aeRange,
        range = range,
        rangeSq = rangeSq,
        isGroupAE = spellutils.IsGroupAEBuffEntry(entry),
        isGroupV2 = spellutils.IsGroupV2BuffEntry(entry),
    }
    _buffSpellMeta[spellIndex] = cached
    if spellCache then spellCache[spellIndex] = cached end
    return cached
end

--- One walk of 1..count fills all phase index lists (invalidated on LoadBuffConfig).
rebuildBuffIndicesByPhase = function()
    local count = botconfig.getSpellCount('buff')
    local byPhase = {}
    for _, p in ipairs(BUFF_PHASE_ORDER) do
        byPhase[p] = {}
    end
    for i = 1, count do
        -- Warm isGroupAE so pet/mypet band probes are correct without hot-path TLO.
        getOrBuildSpellCache(i, nil)
        for _, p in ipairs(BUFF_PHASE_ORDER) do
            if buffBandHasPhase(i, p) then
                byPhase[p][#byPhase[p] + 1] = i
            end
        end
    end
    _buffIndicesByPhase = byPhase
end
-- Config may have loaded before this assignment; rebuild if bands exist but cache empty.
if botconfig.getSpellCount('buff') > 0 and not next(_buffIndicesByPhase) then
    rebuildBuffIndicesByPhase()
end

--- phase must be the RunPhaseFirstSpellCheck phase (no groupmember→pc fallthrough).
local function buffTargetNeedsSpell(spellIndex, targetId, targethit, context, spellCache, phase, hoist)
    local bc = BuffClass[spellIndex]
    if not bc then return nil, nil end
    phase = phase or targethit
    local myclass = hoist and hoist.myclass or mq.TLO.Me.Class.ShortName()

    if phase == 'nonpeerraid' then
        local member
        for _, m in ipairs(nonpeerraidbuff.getMembers()) do
            if m.id == targetId then
                member = m
                break
            end
        end
        if not member then return nil, nil end
        local cached = getOrBuildSpellCache(spellIndex, spellCache)
        if not cached then return nil, nil end
        return nonpeerraidbuff.needsBuff(
            spellIndex, targetId, member, cached.entry, cached.spell, cached.sid, cached.rangeSq, bc)
    end

    -- BuffSkip fast-path for self only (peers use CharInfo watchlists).
    local preMeta = (spellCache and spellCache[spellIndex]) or _buffSpellMeta[spellIndex]
    local preSid = preMeta and preMeta.sid
    if preSid then
        if phase == 'self' and bc.self and not bc.petspell then
            local selfKey = (hoist and hoist.selfKey) or (mq.TLO.Me.Name() or '__self__')
            if spellutils.BuffSkipIsActive(selfKey, preSid) then
                return nil, nil
            end
        end
    end

    local cached = getOrBuildSpellCache(spellIndex, spellCache)
    if not cached then return nil, nil end
    local entry, spell, sid = cached.entry, cached.spell, cached.sid
    local myRange, aeRange, range, rangeSq = cached.myRange, cached.aeRange, cached.range, cached.rangeSq
    local tank = hoist and hoist.tank or context.tank
    local tankid = hoist and hoist.tankid or context.tankid
    local tanktar = hoist and hoist.tanktar
    local myid = hoist and hoist.myid or mq.TLO.Me.ID()

    if myclass == 'BRD' and type(entry.gem) == 'number' then
        return nil, nil
    end

    -- Phase target list is a union across spells; require this spell's watchlist for peers.
    -- Non-peers are never on CharInfo watches; phase handlers decide Spawn need.
    local watchScope = charinfowatchers.phaseToScope(phase)
    if watchScope and watchScope ~= 'GRPAGG' then
        local watchSid = spellutils.GetSpellId(entry) or sid
        if not charinfowatchers.watchListHas('BUFF', watchScope, watchSid, targetId) then
            local name = mq.TLO.Spawn(targetId).CleanName()
            if name and resolvePeer(name, context, hoist) then
                return nil, nil
            end
            if phase == 'groupmember' and not charinfowatchers.hasNonPeerGroupMembers() then
                return nil, nil
            end
        end
    end

    if phase == 'self' then
        return tickprof.span('self_eval', function()
            return BuffEvalSelf(spellIndex, entry, spell, sid, range, myid, myclass, tanktar, hoist, cached)
        end)
    end
    if phase == 'tank' then
        return tickprof.span('tank_eval', function()
            local id, hit = BuffEvalTank(spellIndex, entry, spell, sid, rangeSq, tank, tankid, context, hoist)
            if id == targetId then return id, hit end
            return nil, nil
        end)
    end
    if phase == 'offtank' then
        if not BuffClass[spellIndex].offtank then return nil, nil end
        local otname = mq.TLO.Spawn(targetId).CleanName()
        if not otname then return nil, nil end
        local peer = resolvePeer(otname, context, hoist)
        if peer then
            local id, hit = BuffEvalBotNeedsBuff(targetId, otname, sid, rangeSq, spellIndex, 'offtank', peer, context, hoist)
            if id == targetId then return id, hit end
            return nil, nil
        end
        if not IconCheck(spellIndex, targetId, otname, nil, context, hoist) then return nil, nil end
        local otspawn = mq.TLO.Spawn(targetId)
        local otdistSq = otspawn and utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), otspawn.X(), otspawn.Y())
        if not rangeSq or not otdistSq or otdistSq > rangeSq then return nil, nil end
        if not spellutils.EnsureSpawnBuffsPopulated(targetId, 'buff', spellIndex, 'offtank', nil, nil, nil) then
            return nil, nil
        end
        if heightAllowsSpawn(entry, targetId) and spellutils.SpawnNeedsBuff(targetId, spell, entry.spellicon) then
            return targetId, 'offtank'
        end
        return nil, nil
    end
    if phase == 'groupbuff' then
        return BuffEvalGroupBuff(spellIndex, entry, spell, sid, range, aeRange, context, hoist)
    end
    if phase == 'mypet' then
        if cached.isGroupAE then return nil, nil end
        local id, hit = BuffEvalMyPet(spellIndex, entry, spell, sid, rangeSq)
        if id == targetId then return id, hit end
        return nil, nil
    end
    if phase == 'pet' then
        if cached.isGroupAE then return nil, nil end
        if not BuffClass[spellIndex].pet then return nil, nil end
        local watchSid = spellutils.GetSpellId(entry) or sid
        if not charinfowatchers.watchListHas('BUFF', 'PET', watchSid, targetId) then
            return nil, nil
        end
        local petSpawn = mq.TLO.Spawn(targetId)
        if not petSpawn or not petSpawn.ID() or petSpawn.ID() == 0 then return nil, nil end
        local petdistSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), petSpawn.X(), petSpawn.Y())
        if rangeSq and petdistSq and petdistSq <= rangeSq then
            return targetId, 'pet'
        end
        return nil, nil
    end
    -- groupmember/pc (incl. Group v2 AE on ALL): peers = watchlist + range; non-peers = Spawn path when flagged.
    if phase == 'groupmember' then
        if not BuffClass[spellIndex].groupmember then return nil, nil end
        local grpname = mq.TLO.Spawn(targetId).CleanName()
        local peer = resolvePeer(grpname, context, hoist)
        if peer then
            return BuffEvalBotNeedsBuff(targetId, grpname, sid, rangeSq, spellIndex, 'groupmember', peer, context, hoist)
        end
        if not charinfowatchers.hasNonPeerGroupMembers() then
            return nil, nil
        end
        if IconCheck(spellIndex, targetId, grpname, nil, context, hoist) then
            if spellutils.EnsureSpawnBuffsPopulated(targetId, 'buff', spellIndex, 'groupmember', nil, nil, nil)
                and heightAllowsSpawn(entry, targetId)
                and spellutils.SpawnNeedsBuff(targetId, spell, entry.spellicon) then
                return targetId, 'groupmember'
            end
        end
        return nil, nil
    end
    if phase == 'pc' then
        if not BuffClass[spellIndex].pc then return nil, nil end
        local grpname = mq.TLO.Spawn(targetId).CleanName()
        if not grpname then return nil, nil end
        local peer = resolvePeer(grpname, context, hoist)
        if peer then
            return BuffEvalBotNeedsBuff(targetId, grpname, sid, rangeSq, spellIndex, 'pc', peer, context, hoist)
        elseif IconCheck(spellIndex, targetId, grpname, nil, context, hoist) then
            if spellutils.EnsureSpawnBuffsPopulated(targetId, 'buff', spellIndex, 'pc', nil, nil, nil)
                and heightAllowsSpawn(entry, targetId)
                and spellutils.SpawnNeedsBuff(targetId, spell, entry.spellicon) then
                return targetId, 'pc'
            end
        end
        return nil, nil
    end
    return nil, nil
end

function botbuff.BuffCheck(runPriority)
    local myconfig = botconfig.config
    local inCombatContext = state.isCombatContextForBuff()
    if mq.TLO.Me.Class.ShortName() == 'BRD' and myconfig.settings.dobuff and not utils.isNearPrimaryBindPoint() then
        bardtwist.EnsureDefaultTwistRunning()
    end
    local count = botconfig.getSpellCount('buff')
    if count <= 0 then return false end
    if myconfig.settings.buffNonPeerRaid == true then
        nonpeerraidbuff.beginBuffPass()
        nonpeerraidbuff.maybeRefreshRoster()
    end
    local ctx = tickprof.span('context', function()
        return buffBuildContext()
    end)
    local spellCache = {}
    local entryValidCache = {}
    local meBuffCache = {}
    local hoist = {
        tank = ctx.tank,
        tankid = ctx.tankid,
        tanktar = nil,
        myid = mq.TLO.Me.ID(),
        myclass = mq.TLO.Me.Class.ShortName(),
        selfKey = mq.TLO.Me.Name() or '__self__',
        meBuffCache = meBuffCache,
        myPetId = mq.TLO.Me.Pet.ID(),
        freeBuffSlots = mq.TLO.Me.FreeBuffSlots(),
        peerByName = ctx.peerByName,
        peerResolveCache = {},
    }
    local tankPeer = ctx.tank and resolvePeer(ctx.tank, ctx, hoist) or nil
    hoist.tanktar = tankPeer and tankPeer.Target and tankPeer.Target.ID or nil
    local function cachedEntryValid(i)
        local cached = entryValidCache[i]
        if cached ~= nil then return cached end
        local entry = botconfig.getSpellEntry('buff', i)
        if not entry then
            entryValidCache[i] = false
            return false
        end
        local gem = entry.gem
        if entry.enabled == false then
            entryValidCache[i] = false
            return false
        end
        if not ((type(gem) == 'number' and gem ~= 0) or type(gem) == 'string') then
            entryValidCache[i] = false
            return false
        end
        local bc = BuffClass[i]
        local ok
        if hoist.myclass == 'BRD' then
            if type(gem) ~= 'number' or gem == 0 then
                ok = (not inCombatContext) or (inCombatContext and bc and bc.inCombat == true)
            else
                local mode = inCombatContext and 'combat' or 'idle'
                ok = bardtwist.BuffEntryInModeTwist(entry, mode)
            end
        elseif bc and bc.combatOnly == true then
            ok = inCombatContext
        else
            ok = (not inCombatContext) or (inCombatContext and bc and bc.inCombat == true)
        end
        entryValidCache[i] = ok
        return ok
    end

    -- Pre-warm spell meta only when any valid entry lacks cached meta.
    local needPrewarm = false
    for i = 1, count do
        if cachedEntryValid(i) and not _buffSpellMeta[i] then
            needPrewarm = true
            break
        end
    end
    if needPrewarm then
        tickprof.span('prewarm', function()
            for i = 1, count do
                if cachedEntryValid(i) then
                    getOrBuildSpellCache(i, spellCache)
                end
            end
        end)
    end

    --- True when every valid self-band spell is inside BuffSkip (skip whole phase targets).
    local function allSelfBandSpellsBuffSkipped()
        local any = false
        for i = 1, count do
            if cachedEntryValid(i) and buffBandHasPhase(i, 'self') then
                local bc = BuffClass[i]
                local meta = spellCache[i] or getOrBuildSpellCache(i, spellCache)
                if not meta or not meta.sid then return false end
                if bc.petspell then return false end
                if bc.self then
                    any = true
                    if not spellutils.BuffSkipIsActive(hoist.selfKey, meta.sid) then return false end
                end
            end
        end
        return any
    end
    local skipSelfTargets = allSelfBandSpellsBuffSkipped()
    local skipTankTargets = false

    local function needsSpell(spellIndex, targetId, targethit, context, phase)
        return tickprof.span('needs', function()
            return buffTargetNeedsSpell(spellIndex, targetId, targethit, context, spellCache, phase, hoist)
        end)
    end
    local options = {
        skipInterruptForBRD = true,
        runPriority = runPriority,
        spellFirst = true,
        entryValid = cachedEntryValid,
    }
    if myconfig.settings.buffNonPeerRaid == true then
        options.afterCast = function(spellIndex, targetId, _targethit)
            if not targetId or not spellIndex then return end
            local isNonPeer = false
            for _, m in ipairs(nonpeerraidbuff.getMembers()) do
                if m.id == targetId then
                    isNonPeer = true
                    break
                end
            end
            if not isNonPeer then return end
            local meta = spellCache[spellIndex] or getOrBuildSpellCache(spellIndex, spellCache)
            local sid = meta and meta.sid
            if sid then nonpeerraidbuff.noteCast(targetId, sid) end
        end
    end
    if not next(_buffIndicesByPhase) then
        rebuildBuffIndicesByPhase()
    end
    local indicesByPhase = {}
    local function getSpellIndices(phase, _target)
        local indexPhase = (phase == 'nonpeerraid') and 'pc' or phase
        local cached = indicesByPhase[phase]
        if cached then return cached end
        return tickprof.span('indices', function()
            local list = {}
            for _, idx in ipairs(_buffIndicesByPhase[indexPhase] or {}) do
                if cachedEntryValid(idx) then
                    list[#list + 1] = idx
                end
            end
            indicesByPhase[phase] = list
            return list
        end)
    end
    local function getTargets(phase, context)
        if phase == 'self' and skipSelfTargets then return {} end
        if phase == 'tank' and skipTankTargets then return {} end
        return tickprof.span('targets', function()
            local targets = buffGetTargetsForPhase(phase, context, hoist)
            hoist.peerByName = context.peerByName
            return targets
        end)
    end
    return tickprof.span('spellcheck', function()
        return spellutils.RunPhaseFirstSpellCheck('buff', 'doBuff', buffPhaseOrderForPass(), getTargets, getSpellIndices,
            needsSpell, ctx, options)
    end)
end

--- True when a PC corpse within acleash belongs to a current group member (cleric defers buff for rez focus).
local function clericDeferBuffForGroupCorpse(acleash)
    if not mq.TLO.Group.Members() or mq.TLO.Group.Members() == 0 then
        return false
    end
    local count = mq.TLO.SpawnCount('pccorpse radius ' .. acleash)()
    if not count or count == 0 then return false end
    for i = 1, count do
        local spawn = mq.TLO.NearestSpawn(i, 'pccorpse radius ' .. acleash)
        local name = spawn.CleanName()
        if name then
            name = string.gsub(name, "'s corpse", "")
            if mq.TLO.Group.Member(name).Index() then
                return true
            end
        end
    end
    return false
end

function botbuff.getHookFn(name)
    if name == 'doBuff' then
        return function(hookName)
            if utils.isNearPrimaryBindPoint() then return end
            if state.isTravelMode() then return end
            if botmove.isBeyondFollowDistance() then return end
            local myconfig = botconfig.config
            local rc = state.getRunconfig()
            if not myconfig.settings.dobuff or not (myconfig.buff.spells and #myconfig.buff.spells > 0) then return end
            local pull = myconfig.pull
            if pull and pull.roam and rc.dopull and rc.roamNavTargetId then return end
            if mq.TLO.Me.Class.ShortName() == 'CLR' and clericDeferBuffForGroupCorpse(myconfig.settings.acleash or 75) then return end
            if state.getRunState() == state.STATES.idle then
                local msg = rc.statusMessage or ''
                local roamBuffWindow = pull and pull.roam and rc.dopull and rc.roamBuffCheckPending
                if roamBuffWindow or (not msg:find('Roaming to', 1, true) and not msg:find('No pull targets', 1, true)
                    and not msg:find('Waiting for pull', 1, true) and not msg:find('Pulling ', 1, true)) then
                    rc.statusMessage = 'Buff Check'
                end
            end
            botbuff.BuffCheck(bothooks.getPriority(hookName))
            if pull and pull.roam and rc.dopull and rc.roamBuffCheckPending then
                local rs = state.getRunState()
                if rs ~= state.STATES.casting and rs ~= state.STATES.resume_doBuff
                    and (mq.TLO.Me.CastTimeLeft() or 0) == 0 then
                    rc.roamBuffCheckPending = false
                end
            end
        end
    end
    return nil
end

return botbuff
