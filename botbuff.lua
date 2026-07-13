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
local pcphasethrottle = require('lib.pcphasethrottle')
local tickprof = require('lib.tickprof')
local log = require('lib.log')

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
    castutils.LoadSpellSectionConfig('buff', {
        defaultEntry = defaultBuffEntry,
        bandsKey = 'buff',
        storeIn = BuffClass,
        perEntryAfterBands = function(entry, i)
            BuffClass[i].petspell = spellutils.IsPetSummonSpell(entry) or BuffClass[i].petspell
            buffphase.sanitizeRuntimePhases(entry, BuffClass[i])
        end,
    })
    if rebuildBuffIndicesByPhase then
        rebuildBuffIndicesByPhase()
    end
end

castutils.RegisterSectionLoader('buff', 'dobuff', botbuff.LoadBuffConfig)

local function IconCheck(index, EvalID, knownName)
    local entry = botconfig.getSpellEntry('buff', index)
    if not entry then return true end
    local spellicon = entry.spellicon
    if not spellicon or spellicon == 0 then return true end
    local botname = knownName
    if not botname or botname == '' then
        botname = mq.TLO.Spawn(EvalID).Name()
    end
    local info = charinfo.GetInfo(botname)
    local hasIcon = info and spellutils.PeerHasBuff(info, spellicon)
    return not hasIcon
end

--- Peer needs this buff? Duration skip → PeerHasBuff → Stacks/range. Spawn only if casting path needed.
local function peerBuffStillUp(peerName, peer, spellid)
    if not peerName or not peer or not spellid then return false end
    if spellutils.BuffSkipIsActive(peerName, spellid) then return true end
    local dur = spellutils.PeerGetBuffDuration(peer, spellid)
    if dur ~= nil then
        return spellutils.BuffSkipObserveDuration(peerName, spellid, dur)
    end
    if spellutils.PeerHasBuff(peer, spellid) then
        return spellutils.BuffSkipObservePresent(peerName, spellid)
    end
    spellutils.BuffSkipClear(peerName, spellid)
    return false
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

local function BuffEvalBotNeedsBuff(botid, botname, spellid, rangeSq, index, targethit)
    if not botname or not spellid then return nil, nil end
    local peer = charinfo.GetInfo(botname)
    if not peer then return nil, nil end
    local entry = botconfig.getSpellEntry('buff', index)
    local spellicon = entry and entry.spellicon

    if peerBuffStillUp(botname, peer, spellid) then
        spellutils.BuffLog('skip %s [%s]: already has it', botname, targethit)
        return nil, nil
    end
    if spellicon and spellicon ~= 0 and peerBuffStillUp(botname, peer, spellicon) then
        spellutils.BuffLog('skip %s [%s]: already has it (icon)', botname, targethit)
        return nil, nil
    end

    local botbuffstack = peer:Stacks(spellid)
    local botfreebuffslots = peer.FreeBuffSlots
    local spawnid = peer.ID
    if not spawnid or spawnid <= 0 then
        spawnid = botid
    end
    local botdistSq
    local zone = peer.Zone
    if zone and zone.X ~= nil and zone.Y ~= nil then
        botdistSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), zone.X, zone.Y)
    else
        local botspawn = spawnid and mq.TLO.Spawn(spawnid)
        botdistSq = botspawn and utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), botspawn.X(), botspawn.Y())
    end
    if not (spawnid and botbuffstack and botfreebuffslots and botfreebuffslots > 0) then
        spellutils.BuffLog('skip %s [%s]: %s', botname, targethit,
            (not spawnid) and 'no spawn' or (not botbuffstack) and 'will not stack' or 'no free buff slots')
        return nil, nil
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
        if BuffClass[index].petspell and IconCheck(index, myid, selfKey) and mypetid == 0 then
            local hasBuff = select(1, getMeBuffState(meBuffCache, spell))
            if not hasBuff then
                return myid, 'petspell'
            end
        end
        if BuffClass[index].petspell and mypetid > 0 then
            return nil, nil
        end
        if BuffClass[index].self then
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
            -- Defer Stacks until we know we may need to cast.
            if IconCheck(index, myid, selfKey) then
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

local function BuffEvalTank(index, entry, spell, spellid, rangeSq, tank, tankid)
    if not tank or not entry or not BuffClass[index].tank or not tankid or tankid <= 0 then return nil, nil end
    local peer = charinfo.GetInfo(tank)
    if peer then
        return BuffEvalBotNeedsBuff(tankid, tank, spellid, rangeSq, index, 'tank')
    end
    if not IconCheck(index, tankid) then return nil, nil end
    local tankspawn = mq.TLO.Spawn(tankid)
    local tankdistSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), tankspawn.X(), tankspawn.Y())
    if not rangeSq or not tankdistSq or tankdistSq > rangeSq then return nil, nil end
    if not spellutils.EnsureSpawnBuffsPopulated(tankid, 'buff', index, 'tank', nil, 'after_tank', nil) then
        return nil, nil
    end
    if spellutils.SpawnNeedsBuff(tankid, spell, entry.spellicon) then return tankid, 'tank' end
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

local function BuffEvalGroupBuff(index, entry, spell, spellid, range, aeRange)
    if not aeRange then
        local _
        _, aeRange = getSpellRanges(entry)
    end
    if not aeRange or aeRange <= 0 then return nil, nil end
    local aeRangeSq = aeRange * aeRange
    local function needBuff(grpmember, grpid, grpname, peer)
        if peer then
            if peerBuffStillUp(grpname, peer, spellid) then return false end
            local stacks = peer:Stacks(spellid)
            local free = peer.FreeBuffSlots
            return stacks and free and free > 0
        end
        return spellutils.SpawnNeedsBuff(grpid, spell, entry.spellicon)
    end
    return castutils.evalGroupAECount(entry, 'groupbuff', index, BuffClass, 'groupbuff', needBuff,
        { aeRangeSq = aeRangeSq, includeMemberZero = true })
end

local function resolveMemberClassShortName(grpmember, grpname, peer)
    if grpmember and grpmember.Class then
        return grpmember.Class.ShortName()
    end
    local info = peer or (grpname and charinfo.GetInfo(grpname))
    if info and info.Class then
        local sn = info.Class.ShortName
        if type(sn) == 'string' then return sn end
    end
    if grpname then
        local sp = mq.TLO.Spawn('pc =' .. grpname)
        if sp and sp.Class then return sp.Class.ShortName() end
    end
    return nil
end

local function buffMemberClassAllowed(spellIndex, grpname, grpmember, peer)
    if BuffClass[spellIndex].classes == 'all' then return true end
    local classes = BuffClass[spellIndex].classes
    if not classes then return false end
    local className = resolveMemberClassShortName(grpmember, grpname, peer)
    return className and classes[className:lower()] or false
end

local function buffGroupNeedFn(spellIndex, spell, spellid, entry)
    return function(grpmember, grpid, grpname, peer)
        if not buffMemberClassAllowed(spellIndex, grpname, grpmember, peer) then return false end
        if peer then
            if peerBuffStillUp(grpname, peer, spellid) then return false end
            local stacks = peer:Stacks(spellid)
            local free = peer.FreeBuffSlots
            return stacks and free and free > 0
        end
        return spellutils.SpawnNeedsBuff(grpid, spell, entry.spellicon)
    end
end

local function peerPersonallyNeedsBuff(spellIndex, grpname, spellid, peer)
    if not peer then return false end
    if not buffMemberClassAllowed(spellIndex, grpname, nil, peer) then return false end
    if peerBuffStillUp(grpname, peer, spellid) then return false end
    local stacks = peer:Stacks(spellid)
    local free = peer.FreeBuffSlots
    return stacks and free and free > 0
end

--- First peer in bot order for groupKey who personally needs the buff; else first peer in that group (remote only).
local function getGroupV2PcAnchorForGroup(groupKey, bots, spellIndex, spellid)
    local firstInGroup = nil
    local firstNeeding = nil
    for i = 1, #bots do
        local name = bots[i]
        if castutils.getPeerGroupKey(name) == groupKey and groupKey ~= 'mine' and not mq.TLO.Group.Member(name).Index() then
            if not firstInGroup then firstInGroup = name end
            if not firstNeeding then
                local peer = charinfo.GetInfo(name)
                if peer and peerPersonallyNeedsBuff(spellIndex, name, spellid, peer) then
                    firstNeeding = name
                end
            end
        end
    end
    return firstNeeding or firstInGroup
end

local function BuffEvalGroupV2Pc(spellIndex, entry, spell, spellid, targetId, anchorName, aeRangeSq, myRangeSq, context)
    if not BuffClass[spellIndex].pc or not spellutils.IsGroupV2BuffEntry(entry) then return nil, nil end
    if not charinfo.GetInfo(anchorName) then return nil, nil end
    if mq.TLO.Group.Member(anchorName).Index() then return nil, nil end
    local bots = context and context.bots
    if not bots then return nil, nil end
    local groupKey = castutils.getPeerGroupKey(anchorName)
    local preferred = getGroupV2PcAnchorForGroup(groupKey, bots, spellIndex, spellid)
    if not preferred or anchorName ~= preferred then return nil, nil end
    local needBuff = buffGroupNeedFn(spellIndex, spell, spellid, entry)
    local id = castutils.evalGroupV2OnPeer(entry, targetId, anchorName, needBuff,
        { aeRangeSq = aeRangeSq, myRangeSq = myRangeSq })
    if id then
        local cls = mq.TLO.Spawn(targetId).Class.ShortName()
        return id, cls and cls:lower() or nil
    end
    return nil, nil
end

local function BuffEvalMyPet(index, entry, spell, spellid, rangeSq)
    if not BuffClass[index].mypet then return nil, nil end
    local mypetid = mq.TLO.Me.Pet.ID()
    if not mypetid or mypetid <= 0 then return nil, nil end
    local selfKey = mq.TLO.Me.Name() or '__self__'
    local myPeer = charinfo.GetInfo(selfKey)
    if myPeer and peerPetBuffStillUp(selfKey, myPeer, spellid) then return nil, nil end
    local petbuff = mq.TLO.Me.Pet.Buff(spell)()
    if petbuff then
        if spellid then spellutils.BuffSkipObservePresent(selfKey .. '#pet', spellid) end
        return nil, nil
    end
    local mypetSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Pet.X(), mq.TLO.Me.Pet.Y())
    local petstacks = myPeer and myPeer:StacksPet(spellid)
    if petstacks and mypetSq and rangeSq and mypetSq <= rangeSq then
        return mypetid, 'mypet'
    end
    return nil, nil
end

local function BuffEvalPets(index, entry, spellid, rangeSq, bots, botcount)
    if not BuffClass[index].pet then return nil, nil end
    for i = 1, botcount do
        if bots[i] then
            local peer = charinfo.GetInfo(bots[i])
            if peer then
                local petid = peer.PetID
                local spawnid = peer.ID
                if petid and petid > 0 and spawnid and spawnid > 0 then
                    if peerPetBuffStillUp(bots[i], peer, spellid) then
                        -- skip
                    else
                        local petSpawn = mq.TLO.Spawn(petid)
                        local petdistSq = petSpawn and utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), petSpawn.X(), petSpawn.Y())
                        local petstacks = peer:StacksPet(spellid)
                        if petstacks and IconCheck(index, spawnid, bots[i]) and rangeSq and petdistSq and petdistSq <= rangeSq then
                            return petid, 'pet'
                        end
                    end
                end
            end
        end
    end
    return nil, nil
end

--- Evaluate a single listed pet spawn (no full peer-pet rescan).
local function BuffEvalPetById(index, spellid, rangeSq, petId)
    if not BuffClass[index].pet or not petId or petId <= 0 then return nil, nil end
    local petSpawn = mq.TLO.Spawn(petId)
    if not petSpawn or not petSpawn.ID() or petSpawn.ID() == 0 then return nil, nil end
    local masterName = petSpawn.Master and (petSpawn.Master.CleanName() or petSpawn.Master.Name())
    if not masterName or masterName == '' then return nil, nil end
    local peer = charinfo.GetInfo(masterName)
    if not peer then return nil, nil end
    if peerPetBuffStillUp(masterName, peer, spellid) then return nil, nil end
    local petdistSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), petSpawn.X(), petSpawn.Y())
    local petstacks = peer:StacksPet(spellid)
    local ownerId = peer.ID
    if ownerId and ownerId > 0 and petstacks and IconCheck(index, ownerId, masterName)
        and rangeSq and petdistSq and petdistSq <= rangeSq then
        return petId, 'pet'
    end
    return nil, nil
end

local BUFF_PHASE_ORDER = { 'self', 'byname', 'tank', 'groupbuff', 'groupmember', 'pc', 'mypet', 'pet' }
--- Light-locked passes: self+tank only (all RR phases denied by cooldown/interval).
local BUFF_PHASE_ORDER_LIGHT = { 'self', 'tank' }

--- Single place for buff context: tank, tankid, class-ordered bots, botcount, buffCount. Used by BuffCheck and getTargets/needsSpell.
local function buffBuildContext()
    local tank, tankid = spellutils.GetTankInfo(false)
    local bots = spellutils.GetBotListOrdered()
    local count = botconfig.getSpellCount('buff')
    return { tank = tank, tankid = tankid, bots = bots, botcount = #bots, buffCount = count }
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

local function buffGetTargetsForPhase(phase, context)
    if phase == 'self' then return castutils.getTargetsSelf() end
    if phase == 'tank' then return filterCorpses(castutils.getTargetsTank(context)) end
    if phase == 'groupbuff' then return castutils.getTargetsGroupCaster('groupbuff') end
    if phase == 'groupmember' then return filterCorpses(castutils.getTargetsGroupMember(context, { excludeSelfAndTank = true })) end
    if phase == 'pc' then return filterCorpses(castutils.getTargetsPc(context, { excludeTank = true })) end
    if phase == 'mypet' then return castutils.getTargetsMypet() end
    if phase == 'pet' then return castutils.getTargetsPet(context) end
    if phase == 'byname' and context.buffCount then
        if context.bynameTargets then return context.bynameTargets end
        local out = {}
        local seen = {}
        local function addByName(name)
            local n = type(name) == 'string' and (name:match('^%s*(.-)%s*$') or '') or ''
            if n == '' or seen[n] then return end
            seen[n] = true
            local peer = charinfo.GetInfo(n)
            local botid = peer and peer.ID
            if (not botid or botid <= 0) then
                botid = mq.TLO.Spawn('pc =' .. n).ID()
            end
            if botid and botid > 0 then out[#out + 1] = { id = botid, targethit = 'byname', name = n } end
        end
        for idx = 1, context.buffCount do
            -- Managed per-buff name list (clean UI). Resolved by spawn name, so it covers PCs that are
            -- NOT in the bot network (e.g. guildmates) as well as networked characters.
            local entry = botconfig.getSpellEntry('buff', idx)
            if entry and type(entry.buffNames) == 'table' then
                for _, name in ipairs(entry.buffNames) do addByName(name) end
            end
            -- Legacy key-based byname (backward compat): network peers only.
            if BuffClass[idx] and BuffClass[idx].name then
                for name, c in pairs(BuffClass[idx]) do
                    if name ~= 'name' and name ~= 'classes' and name ~= 'classesAll' and type(name) == 'string' and charinfo.GetInfo(name) then
                        addByName(name)
                    end
                end
            end
        end
        local filtered = filterCorpses(out)
        context.bynameTargets = filtered
        return filtered
    end
    return {}
end

local function buffHasNameList(spellIndex)
    local entry = botconfig.getSpellEntry('buff', spellIndex)
    return entry and type(entry.buffNames) == 'table' and #entry.buffNames > 0 or false
end

--- Throttled multi-target buff phases (mirrors pcphasethrottle THROTTLED.buff).
local BUFF_RR_THROTTLED = {
    byname = true,
    groupbuff = true,
    groupmember = true,
    pc = true,
    mypet = true,
    pet = true,
}

local function buffBandHasPhase(spellIndex, phase)
    if phase == 'byname' then
        if buffHasNameList(spellIndex) then return true end
        return BuffClass[spellIndex] and BuffClass[spellIndex].name and true or false
    end
    if phase == 'pet' or phase == 'mypet' then
        -- Prewarmed meta only — no IsGroupAEBuffEntry TLO in the phase probe hot path.
        local meta = _buffSpellMeta[spellIndex]
        if meta and meta.isGroupAE then return false end
    end
    return castutils.bandHasPhaseSimple(BuffClass, spellIndex, phase)
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

    -- BuffSkip fast-path (meta pre-warmed): no Me.Buff / peer / Stacks.
    local preMeta = (spellCache and spellCache[spellIndex]) or _buffSpellMeta[spellIndex]
    local preSid = preMeta and preMeta.sid
    if preSid then
        if phase == 'self' and bc.self and not bc.petspell then
            local selfKey = (hoist and hoist.selfKey) or (mq.TLO.Me.Name() or '__self__')
            if spellutils.BuffSkipIsActive(selfKey, preSid) then
                return nil, nil
            end
        elseif phase == 'tank' and bc.tank and hoist and hoist.tank then
            if spellutils.BuffSkipIsActive(hoist.tank, preSid) then
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

    if phase == 'self' then
        return tickprof.span('self_eval', function()
            return BuffEvalSelf(spellIndex, entry, spell, sid, range, myid, myclass, tanktar, hoist, cached)
        end)
    end
    if phase == 'tank' then
        return tickprof.span('tank_eval', function()
            local id, hit = BuffEvalTank(spellIndex, entry, spell, sid, rangeSq, tank, tankid)
            if id == targetId then return id, hit end
            return nil, nil
        end)
    end
    if phase == 'groupbuff' then
        return BuffEvalGroupBuff(spellIndex, entry, spell, sid, range, aeRange)
    end
    if phase == 'mypet' then
        if cached.isGroupAE then return nil, nil end
        local id, hit = BuffEvalMyPet(spellIndex, entry, spell, sid, rangeSq)
        if id == targetId then return id, hit end
        return nil, nil
    end
    if phase == 'pet' then
        if cached.isGroupAE then return nil, nil end
        return BuffEvalPetById(spellIndex, sid, rangeSq, targetId)
    end
    if phase == 'byname' then
        local name = mq.TLO.Spawn(targetId).CleanName()
        if not name then return nil, nil end
        if charinfo.GetInfo(name) then
            local id, hit = BuffEvalBotNeedsBuff(targetId, name, sid, rangeSq, spellIndex, 'byname')
            if id then return id, hit end
        elseif IconCheck(spellIndex, targetId)
            and spellutils.EnsureSpawnBuffsPopulated(targetId, 'buff', spellIndex, 'byname', nil, nil, nil)
            and spellutils.SpawnNeedsBuff(targetId, spell, entry.spellicon) then
            local sp = mq.TLO.Spawn(targetId)
            local dSq = sp and utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), sp.X(), sp.Y())
            if not rangeSq or (dSq and dSq <= rangeSq) then
                return targetId, 'byname'
            end
        end
        return nil, nil
    end
    if phase == 'groupmember' then
        if not BuffClass[spellIndex].groupmember then return nil, nil end
        local grpname = mq.TLO.Spawn(targetId).CleanName()
        local lc = targethit
        if not (BuffClass[spellIndex].classes == 'all' or (BuffClass[spellIndex].classes and BuffClass[spellIndex].classes[lc])) then
            return nil, nil
        end
        local peer = charinfo.GetInfo(grpname)
        if peer then
            return BuffEvalBotNeedsBuff(targetId, grpname, sid, rangeSq, spellIndex, lc)
        elseif IconCheck(spellIndex, targetId) then
            if spellutils.EnsureSpawnBuffsPopulated(targetId, 'buff', spellIndex, lc, nil, nil, nil) and spellutils.SpawnNeedsBuff(targetId, spell, entry.spellicon) then
                return targetId, lc
            end
        end
        return nil, nil
    end
    if phase == 'pc' then
        if not BuffClass[spellIndex].pc then return nil, nil end
        local grpname = mq.TLO.Spawn(targetId).CleanName()
        if not grpname then return nil, nil end
        local lc = targethit
        if not (BuffClass[spellIndex].classes == 'all' or (BuffClass[spellIndex].classes and BuffClass[spellIndex].classes[lc])) then
            return nil, nil
        end
        if cached.isGroupV2 then
            local myRangeOnly = myRange and myRange > 0 and myRange or nil
            local myRangeSq = myRangeOnly and (myRangeOnly * myRangeOnly) or rangeSq
            local aeRangeSq = aeRange and aeRange > 0 and (aeRange * aeRange) or nil
            return BuffEvalGroupV2Pc(spellIndex, entry, spell, sid, targetId, grpname, aeRangeSq, myRangeSq, context)
        end
        if cached.isGroupAE then
            local peer = charinfo.GetInfo(grpname)
            if not peer then return nil, nil end
            return BuffEvalBotNeedsBuff(targetId, grpname, sid, rangeSq, spellIndex, lc)
        end
        local peer = charinfo.GetInfo(grpname)
        if peer then
            return BuffEvalBotNeedsBuff(targetId, grpname, sid, rangeSq, spellIndex, lc)
        elseif IconCheck(spellIndex, targetId) then
            if spellutils.EnsureSpawnBuffsPopulated(targetId, 'buff', spellIndex, lc, nil, nil, nil) and spellutils.SpawnNeedsBuff(targetId, spell, entry.spellicon) then
                return targetId, lc
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
    local ctx = tickprof.span('context', function()
        return buffBuildContext()
    end)
    local count = ctx.buffCount
    if count <= 0 then return false end
    pcphasethrottle.beginBuffPass()
    local spellCache = {}
    local entryValidCache = {}
    local meBuffCache = {}
    local tankPeer = ctx.tank and charinfo.GetInfo(ctx.tank) or nil
    local tanktar = tankPeer and tankPeer.Target and tankPeer.Target.ID or nil
    local hoist = {
        tank = ctx.tank,
        tankid = ctx.tankid,
        tanktar = tanktar,
        myid = mq.TLO.Me.ID(),
        myclass = mq.TLO.Me.Class.ShortName(),
        selfKey = mq.TLO.Me.Name() or '__self__',
        meBuffCache = meBuffCache,
        myPetId = mq.TLO.Me.Pet.ID(),
        freeBuffSlots = mq.TLO.Me.FreeBuffSlots(),
    }
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

    --- True when every valid self/tank-band spell is inside BuffSkip (skip whole phase targets).
    local function allBandSpellsBuffSkipped(phase)
        local any = false
        for i = 1, count do
            if cachedEntryValid(i) and buffBandHasPhase(i, phase) then
                local bc = BuffClass[i]
                local meta = spellCache[i] or getOrBuildSpellCache(i, spellCache)
                if not meta or not meta.sid then return false end
                if phase == 'self' then
                    if bc.petspell then return false end
                    if bc.self then
                        any = true
                        if not spellutils.BuffSkipIsActive(hoist.selfKey, meta.sid) then return false end
                    end
                elseif phase == 'tank' then
                    if bc.tank then
                        if not hoist.tank then return false end
                        any = true
                        if not spellutils.BuffSkipIsActive(hoist.tank, meta.sid) then return false end
                    end
                end
            end
        end
        return any
    end
    local skipSelfTargets = allBandSpellsBuffSkipped('self')
    local skipTankTargets = allBandSpellsBuffSkipped('tank')

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
    local cursor = spellutils.getResumeCursor('doBuff')
    local phaseOrder = BUFF_PHASE_ORDER
    if pcphasethrottle.buffPassIsLightLocked() then
        local resumeThrottled = cursor and cursor.phase and BUFF_RR_THROTTLED[cursor.phase]
        if not resumeThrottled then
            phaseOrder = BUFF_PHASE_ORDER_LIGHT
            pcphasethrottle.markBuffPassLightLocked()
        end
    end
    -- Pass-local deny/grant overlay; module cache supplies the real index lists.
    local indicesByPhase = {}
    local rrAllowByPhase = {}
    if not next(_buffIndicesByPhase) then
        rebuildBuffIndicesByPhase()
    end
    local function filterIndicesEntryValid(list)
        local filtered = {}
        for _, idx in ipairs(list) do
            if cachedEntryValid(idx) then
                filtered[#filtered + 1] = idx
            end
        end
        return filtered
    end
    -- Pre-mark empty RR phases so tip-strict can skip before byname asks (phase order ≠ RR order).
    for _, phase in ipairs(pcphasethrottle.BUFF_RR_ORDER) do
        local list = filterIndicesEntryValid(_buffIndicesByPhase[phase] or {})
        if #list == 0 then
            pcphasethrottle.noteBuffPhaseEmpty(phase)
        end
    end
    local function getSpellIndices(phase, _target)
        local cached = indicesByPhase[phase]
        if cached then return cached end
        return tickprof.span('indices', function()
            -- Light / already-granted: deny via allow() without grant work.
            if BUFF_RR_THROTTLED[phase] and rrAllowByPhase[phase] ~= true
                and (rrAllowByPhase[phase] == false or pcphasethrottle.buffRrWouldDeny(phase)) then
                if rrAllowByPhase[phase] == nil then
                    rrAllowByPhase[phase] = pcphasethrottle.allow('buff', cursor, phase)
                end
                indicesByPhase[phase] = {}
                return indicesByPhase[phase]
            end
            local list = filterIndicesEntryValid(_buffIndicesByPhase[phase] or {})
            -- Empty after entryValid filter: tip-strict RR may skip this tip.
            if #list == 0 then
                if BUFF_RR_THROTTLED[phase] then
                    pcphasethrottle.noteBuffPhaseEmpty(phase)
                end
                indicesByPhase[phase] = list
                return list
            end
            if BUFF_RR_THROTTLED[phase] then
                local allowed = rrAllowByPhase[phase]
                if allowed == nil then
                    allowed = pcphasethrottle.allow('buff', cursor, phase)
                    rrAllowByPhase[phase] = allowed
                end
                if not allowed then
                    -- Has spells but not tip / denied — do not mark empty.
                    indicesByPhase[phase] = {}
                    return indicesByPhase[phase]
                end
            end
            indicesByPhase[phase] = list
            return list
        end)
    end
    local function getTargets(phase, context)
        if phase == 'self' and skipSelfTargets then return {} end
        if phase == 'tank' and skipTankTargets then return {} end
        if BUFF_RR_THROTTLED[phase] then
            local allowed = rrAllowByPhase[phase]
            if allowed == nil then
                allowed = pcphasethrottle.allow('buff', cursor, phase)
                rrAllowByPhase[phase] = allowed
            end
            if not allowed then return {} end
            return tickprof.span('targets', function()
                return buffGetTargetsForPhase(phase, context)
            end)
        end
        if not pcphasethrottle.allow('buff', cursor, phase) then return {} end
        return tickprof.span('targets', function()
            return buffGetTargetsForPhase(phase, context)
        end)
    end
    local result = tickprof.span('spellcheck', function()
        return spellutils.RunPhaseFirstSpellCheck('buff', 'doBuff', phaseOrder, getTargets, getSpellIndices,
            needsSpell, ctx, options)
    end)
    if tickprof.IsDebug() and tickprof.IsSpans() then
        local mode, detail = pcphasethrottle.noteBuffPassEnd()
        if mode == 'heavy' then
            log.say('[tick] buff.pass mode=heavy phase=%s', detail)
        else
            log.say('[tick] buff.pass mode=light reason=%s', detail)
        end
    end
    return result
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
