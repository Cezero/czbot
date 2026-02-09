local mq = require('mq')
local botconfig = require('lib.config')
local charm = require('lib.charm')
local spellbands = require('lib.spellbands')
local spellutils = require('lib.spellutils')
local spellstates = require('lib.spellstates')
local state = require('lib.state')
local utils = require('lib.utils')
local charinfo = require("mqcharinfo")
local bothooks = require('lib.bothooks')
local myconfig = botconfig.config

local botcast = {}

-- Module-level state for buff/cure/heal/debuff (used by evals and spellutils globals)
-- Runconfig fields used by botcast: engageTargetId (set in ADSpawnCheck when clearing invalid spawn, and in DebuffOnBeforeCast for tanktar);
-- charmid (set in charm.EvalTarget and spellutils on cast); MobList, MobCount (set in ADSpawnCheck); CurSpell (read-only here, set in spellutils).
local BuffClass = {}
local CureClass = {}
local CureType = {}
local AHThreshold = {}
local XTList = {}
local DebuffBands = {}

-- Normalize spell entry: script gem handling and enabled default. Used by LoadSpellSectionConfig.
local function normalizeSpellEntry(entry)
    if entry.gem == 'script' then
        if not myconfig.script[entry.spell] then
            print('making script ', entry.spell)
            myconfig.script[entry.spell] = "test"
        end
        table.insert(state.getRunconfig().ScriptList, entry.spell)
    end
    if entry.enabled == nil then entry.enabled = true end
end

-- Generic spell-section config loader. opts: defaultEntry(), bandsKey, storeIn, preLoad?, postLoad?, perEntryNormalize?(entry), perEntryAfterBands?(entry, i).
function botcast.LoadSpellSectionConfig(section, opts)
    if opts.preLoad then opts.preLoad() end
    local spells = myconfig[section].spells
    if not spells then
        myconfig[section].spells = {}; spells = myconfig[section].spells
    end
    while #spells < 2 do
        table.insert(spells, opts.defaultEntry())
    end
    for i = 1, #spells do
        local entry = spells[i]
        if not entry then
            spells[i] = opts.defaultEntry()
            entry = spells[i]
        end
        if opts.perEntryNormalize then opts.perEntryNormalize(entry) end
        normalizeSpellEntry(entry)
        opts.storeIn[i] = spellbands.applyBands(opts.bandsKey, entry, i)
        if opts.perEntryAfterBands then opts.perEntryAfterBands(entry, i) end
    end
    if opts.postLoad then opts.postLoad() end
end

-- ---------------------------------------------------------------------------
-- Buff
-- ---------------------------------------------------------------------------

local function defaultBuffEntry()
    return {
        gem = 0,
        spell = 0,
        minmana = 0,
        alias = false,
        announce = false,
        enabled = true,
        bands = { { targetphase = { 'self', 'tank', 'pc', 'mypet', 'pet' }, validtargets = { 'all' } } },
        spellicon = 0,
        precondition = true
    }
end

function botcast.LoadBuffConfig()
    botcast.LoadSpellSectionConfig('buff', {
        defaultEntry = defaultBuffEntry,
        bandsKey = 'buff',
        storeIn = BuffClass,
    })
end

local function IconCheck(index, EvalID)
    local entry = botconfig.getSpellEntry('buff', index)
    if not entry then return true end
    local spellicon = entry.spellicon
    if not spellicon or spellicon == 0 then return true end
    local botname = mq.TLO.Spawn(EvalID).Name()
    local info = charinfo.GetInfo(botname)
    local hasIcon = info and spellutils.PeerHasBuff(info, spellicon)
    return not hasIcon
end

local function BuffEvalBotNeedsBuff(botid, botname, spellid, range, index, targethit)
    local spawnid = mq.TLO.Spawn(botid).ID()
    local peer = charinfo.GetInfo(botname)
    if not peer then return nil, nil end
    local botbuff = spellutils.PeerHasBuff(peer, spellid)
    local botbuffstack = peer:Stacks(spellid)
    local botfreebuffslots = peer.FreeBuffSlots
    local botdist = spawnid and mq.TLO.Spawn(spawnid).Distance()
    if not (spawnid and botbuffstack and botfreebuffslots and botfreebuffslots > 0) then return nil, nil end
    if not IconCheck(index, spawnid) or botbuff then return nil, nil end
    if range and botdist and botdist <= range then return botid, targethit end
    return nil, nil
end

local function BuffEvalSelf(index, entry, spell, spellid, range, myid, myclass, tanktar)
    if not BuffClass[index] then return nil, nil end
    if myclass ~= 'BRD' then
        local mypetid = mq.TLO.Me.Pet.ID()
        if BuffClass[index].petspell and IconCheck(index, myid) and mypetid == 0 then
            return myid, 'petspell'
        end
        if BuffClass[index].self then
            local buffdur = mq.TLO.Me.Buff(spell).Duration()
            local mycasttime = mq.TLO.Spell(spell).MyCastTime()
            local buff = mq.TLO.Me.Buff(spell)() or mq.TLO.Me.Song(spell)()
            local stacks = mq.TLO.Spell(spell).Stacks()
            local tartype = mq.TLO.Spell(spell).TargetType()
            local freebuffslots = mq.TLO.Me.FreeBuffSlots()
            if (not buff) or (buffdur and buffdur < 24000 and mycasttime > 0 and freebuffslots > 0) then
                if IconCheck(index, myid) then
                    if tartype == 'Self' and stacks then return 1, 'self' end
                    if stacks then return myid, 'self' end
                end
            end
        end
        return nil, nil
    end
    if myclass == 'BRD' and BuffClass[index].self and IconCheck(index, myid) then
        local mysong = mq.TLO.Me.Song(spell)() or mq.TLO.Me.Buff(spell)()
        local mysongdur = mq.TLO.Me.Song(spell).Duration() or mq.TLO.Me.Buff(spell).Duration()
        local songtartype = mq.TLO.Spell(spell).TargetType()
        local songtype = mq.TLO.Spell(spell).SpellType()
        if (not mysong) or (mysongdur and mysongdur < 6100) then
            if songtartype and (songtartype == 'Group v1' or songtartype == 'Group v2' or songtartype == 'Self' or songtartype == 'AE PC v2') then
                return 1, 'self'
            elseif songtype and songtype == 'Detrimental' then
                local mysongdur2 = mq.TLO.Target.MyBuff(spell).Duration()
                local mysong2 = mq.TLO.Target.MyBuff(spell)()
                if tanktar and tanktar > 0 and ((not mysong2) or (mysongdur2 and mysongdur2 < 6100)) then
                    return tanktar, 'self'
                end
            else
                return myid, 'self'
            end
        end
    end
    return nil, nil
end

local function BuffEvalTank(index, entry, spell, spellid, range, tank, tankid)
    if not tank or not entry or not BuffClass[index].tank or not tankid or tankid <= 0 then return nil, nil end
    if not IconCheck(index, tankid) then return nil, nil end
    local peer = charinfo.GetInfo(tank)
    if peer then
        return BuffEvalBotNeedsBuff(tankid, tank, spellid, range, index, 'tank')
    end
    -- Non-bot tank (explicitly configured): buff state only from Spawn after targeting (BuffsPopulated)
    local tankdist = mq.TLO.Spawn(tankid).Distance()
    if not range or not tankdist or tankdist > range then return nil, nil end
    if not spellutils.EnsureSpawnBuffsPopulated(tankid, 'buff', index, 'tank', nil, 'after_tank', nil) then
        return nil, nil
    end
    if spellutils.SpawnNeedsBuff(tankid, spell, entry.spellicon) then return tankid, 'tank' end
    -- Out-of-group: best-effort cast in range when we don't have buff data (not targeted or BuffsPopulated false)
    if not mq.TLO.Group.Member(tank).Index() then return tankid, 'tank' end
    return nil, nil
end

-- Group AE count-and-threshold: count members where needMemberFn(grpmember, grpid, grpname, peer) is true;
-- if count >= entry.tarcnt return (Group v1 -> 1 else Me.ID()), targethit. opts.aeRange: when set, only count PC in range.
-- opts.includeMemberZero: when true, loop from 0 (Group.Member(0) is self); otherwise 1 to Members().
local function evalGroupAECount(entry, targethit, index, bandTable, phaseKey, needMemberFn, opts)
    if not bandTable[index] or not bandTable[index][phaseKey] then return nil, nil end
    local tartype = mq.TLO.Spell(entry.spell).TargetType()
    if tartype ~= 'Group v1' and tartype ~= 'Group v2' then return nil, nil end
    opts = opts or {}
    local aeRange = opts.aeRange
    local startIdx = (opts.includeMemberZero and 0) or 1
    local needCount = 0
    for i = startIdx, mq.TLO.Group.Members() do
        local grpmember = mq.TLO.Group.Member(i)
        if grpmember then
            local grpspawn = grpmember.Spawn
            local grpname = grpmember.Name()
            local grpid = grpmember.ID()
            if grpid and grpid > 0 then
                if aeRange then
                    local grpdist = grpspawn and grpspawn.Distance() or nil
                    if mq.TLO.Spawn(grpid).Type() ~= 'PC' or not grpdist or grpdist > aeRange then
                        -- skip
                    else
                        local peer = charinfo.GetInfo(grpname)
                        if needMemberFn(grpmember, grpid, grpname, peer) then needCount = needCount + 1 end
                    end
                else
                    local peer = charinfo.GetInfo(grpname)
                    if needMemberFn(grpmember, grpid, grpname, peer) then needCount = needCount + 1 end
                end
            end
        end
    end
    if needCount >= (entry.tarcnt or 1) then
        if tartype == 'Group v1' then return 1, targethit end
        return mq.TLO.Me.ID(), targethit
    end
    return nil, nil
end

local function BuffEvalGroupBuff(index, entry, spell, spellid, range)
    local aeRange = mq.TLO.Spell(spell).AERange()
    if entry.gem == 'item' and mq.TLO.FindItem(entry.spell)() then aeRange = mq.TLO.FindItem(entry.spell).Spell.AERange() end
    if not aeRange or aeRange <= 0 then return nil, nil end
    local function needBuff(grpmember, grpid, grpname, peer)
        if peer then
            local hasBuff = spellutils.PeerHasBuff(peer, spellid)
            local stacks = peer:Stacks(spellid)
            local free = peer.FreeBuffSlots
            return not hasBuff and stacks and free and free > 0
        end
        return spellutils.SpawnNeedsBuff(grpid, spell, entry.spellicon)
    end
    return evalGroupAECount(entry, 'groupbuff', index, BuffClass, 'groupbuff', needBuff, { aeRange = aeRange })
end

local function BuffEvalMyPet(index, entry, spell, spellid, range)
    if not BuffClass[index].mypet then return nil, nil end
    local mypetid = mq.TLO.Me.Pet.ID()
    local petbuff = mq.TLO.Me.Pet.Buff(spell)()
    local petrange = mq.TLO.Me.Pet.Distance()
    local myPeer = charinfo.GetInfo(mq.TLO.Me.Name())
    local petstacks = myPeer and myPeer:StacksPet(spellid)
    if mypetid > 0 and petstacks and not petbuff and petrange and range and range >= petrange then
        return mypetid, 'mypet'
    end
    return nil, nil
end

local function BuffEvalPets(index, entry, spellid, range, bots, botcount)
    if not BuffClass[index].pet then return nil, nil end
    for i = 1, botcount do
        if bots[i] then
            local peer = charinfo.GetInfo(bots[i])
            if peer then
                local botpet = mq.TLO.Spawn('pc =' .. bots[i]).Pet.ID()
                local petrange = mq.TLO.Spawn(botpet).Distance()
                local petbuff = spellutils.PeerHasPetBuff(peer, spellid)
                local botid = mq.TLO.Spawn('pc =' .. bots[i]).ID()
                local spawnid = mq.TLO.Spawn(botid).ID()
                local petstacks = peer:StacksPet(spellid)
                if spawnid and spawnid > 0 and botpet and botpet > 0 and petstacks and IconCheck(index, spawnid) and not petbuff and range and range >= petrange then
                    return botpet, 'pet'
                end
            end
        end
    end
    return nil, nil
end

-- Phase-first buff: phase order and helpers for RunPhaseFirstSpellCheck.
local BUFF_PHASE_ORDER = { 'self', 'byname', 'tank', 'groupbuff', 'groupmember', 'pc', 'mypet', 'pet' }

-- Shared get-targets helpers for buff/cure/heal GetTargetsForPhase.
-- opts for getTargetsGroupMember: botsFirst (add bots in group first), excludeBotsFromGroup (in group loop skip names that have charinfo).
local function getTargetsSelf()
    local out = {}
    local myid = mq.TLO.Me.ID()
    if myid and myid > 0 then out[#out + 1] = { id = myid, targethit = 'self' } end
    return out
end

local function getTargetsTank(context)
    local out = {}
    if context.tankid and context.tankid > 0 then
        out[#out + 1] = { id = context.tankid, targethit = 'tank' }
    end
    return out
end

local function getTargetsGroupCaster(targethit)
    local out = {}
    local meid = mq.TLO.Me.ID()
    if meid then out[#out + 1] = { id = meid, targethit = targethit } end
    return out
end

local function getTargetsGroupMember(context, opts)
    local out = {}
    opts = opts or {}
    if opts.botsFirst and context.bots then
        for i = 1, #context.bots do
            local name = context.bots[i]
            if name and mq.TLO.Group.Member(name).ID() then
                local botid = mq.TLO.Spawn('pc =' .. name).ID()
                local botclass = mq.TLO.Spawn('pc =' .. name).Class.ShortName()
                if botid and botid > 0 and botclass then out[#out + 1] = { id = botid, targethit = botclass:lower() } end
            end
        end
    end
    if mq.TLO.Group.Members() and mq.TLO.Group.Members() > 0 then
        for i = 1, mq.TLO.Group.Members() do
            local grpmember = mq.TLO.Group.Member(i)
            if grpmember and grpmember.Class then
                local grpname = grpmember.Name()
                local grpid = grpmember.ID()
                local grpclass = grpmember.Class.ShortName()
                if grpid and grpid > 0 and grpclass then
                    if opts.excludeBotsFromGroup and charinfo.GetInfo(grpname) then
                        -- skip (already added in botsFirst or is a bot)
                    else
                        out[#out + 1] = { id = grpid, targethit = grpclass:lower() }
                    end
                end
            end
        end
    end
    return out
end

local function getTargetsPc(context)
    local out = {}
    local bots = context.bots
    if not bots then return out end
    local n = context.botcount or #bots
    for i = 1, n do
        local name = bots[i]
        if name then
            local botid = mq.TLO.Spawn('pc =' .. name).ID()
            local botclass = mq.TLO.Spawn('pc =' .. name).Class.ShortName()
            if botid and botid > 0 and botclass then out[#out + 1] = { id = botid, targethit = botclass:lower() } end
        end
    end
    return out
end

local function getTargetsMypet()
    local out = {}
    local mypetid = mq.TLO.Me.Pet.ID()
    if mypetid and mypetid > 0 then out[#out + 1] = { id = mypetid, targethit = 'mypet' } end
    return out
end

local function getTargetsPet(context)
    local out = {}
    if not context.bots then return out end
    local n = context.botcount or #context.bots
    for i = 1, n do
        local petid = mq.TLO.Spawn('pc =' .. context.bots[i]).Pet.ID()
        if petid and petid > 0 then out[#out + 1] = { id = petid, targethit = 'pet' } end
    end
    return out
end

local function bandHasPhaseSimple(bandTable, spellIndex, phase)
    return bandTable[spellIndex] and bandTable[spellIndex][phase] and true or false
end

local function buffGetTargetsForPhase(phase, context)
    if phase == 'self' then return getTargetsSelf() end
    if phase == 'tank' then return getTargetsTank(context) end
    if phase == 'groupbuff' then return getTargetsGroupCaster('groupbuff') end
    if phase == 'groupmember' then return getTargetsGroupMember(context, {}) end
    if phase == 'pc' then return getTargetsPc(context) end
    if phase == 'mypet' then return getTargetsMypet() end
    if phase == 'pet' then return getTargetsPet(context) end
    if phase == 'byname' and context.buffCount then
        local out = {}
        local seen = {}
        for idx = 1, context.buffCount do
            if BuffClass[idx] and BuffClass[idx].name then
                for name, c in pairs(BuffClass[idx]) do
                    if name ~= 'name' and name ~= 'classes' and name ~= 'classesAll' and type(name) == 'string' and charinfo.GetInfo(name) and not seen[name] then
                        seen[name] = true
                        local botid = mq.TLO.Spawn('pc =' .. name).ID()
                        local botclass = mq.TLO.Spawn('pc =' .. name).Class.ShortName()
                        if botid and botid > 0 then out[#out + 1] = { id = botid, targethit = 'byname' } end
                    end
                end
            end
        end
        return out
    end
    return {}
end

local function buffBandHasPhase(spellIndex, phase)
    if phase == 'byname' then return BuffClass[spellIndex] and BuffClass[spellIndex].name and true or false end
    return bandHasPhaseSimple(BuffClass, spellIndex, phase)
end

local function buffTargetNeedsSpell(spellIndex, targetId, targethit, context)
    local entry = botconfig.getSpellEntry('buff', spellIndex)
    if not entry or not BuffClass[spellIndex] then return nil, nil end
    local spell, _, _, spellid = spellutils.GetSpellInfo(entry)
    if not spell or not spellid then return nil, nil end
    local sid = (spellid == 1536) and 1538 or spellid
    local gem = entry.gem
    local range = (mq.TLO.Spell(spell).MyRange() and mq.TLO.Spell(spell).MyRange() > 0) and mq.TLO.Spell(spell).MyRange()
        or mq.TLO.Spell(spell).AERange() or
        (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.MyRange())
    local tank, tankid, tanktar = spellutils.GetTankInfo(false)
    tanktar = tanktar or
    (tank and charinfo.GetInfo(tank) and charinfo.GetInfo(tank).Target and charinfo.GetInfo(tank).Target.ID or nil)
    local myid = mq.TLO.Me.ID()
    local myclass = mq.TLO.Me.Class.ShortName()

    if targethit == 'self' then
        return BuffEvalSelf(spellIndex, entry, spell, sid, range, myid, myclass, tanktar)
    end
    if targethit == 'tank' then
        local id, hit = BuffEvalTank(spellIndex, entry, spell, sid, range, context.tank, context.tankid)
        if id == targetId then return id, hit end
        return nil, nil
    end
    if targethit == 'groupbuff' then
        return BuffEvalGroupBuff(spellIndex, entry, spell, sid, range)
    end
    if targethit == 'mypet' then
        local id, hit = BuffEvalMyPet(spellIndex, entry, spell, sid, range)
        if id == targetId then return id, hit end
        return nil, nil
    end
    if targethit == 'pet' then
        local id, hit = BuffEvalPets(spellIndex, entry, sid, range, context.bots,
            context.botcount or #(context.bots or {}))
        if id == targetId then return id, hit end
        return nil, nil
    end
    if targethit == 'byname' then
        if not BuffClass[spellIndex].name then return nil, nil end
        local name = mq.TLO.Spawn(targetId).CleanName()
        if name then
            local id, hit = BuffEvalBotNeedsBuff(targetId, name, sid, range, spellIndex, 'byname')
            if id then return id, hit end
        end
        return nil, nil
    end
    -- groupmember or pc (class key)
    if BuffClass[spellIndex].groupmember or BuffClass[spellIndex].pc then
        local grpname = mq.TLO.Spawn(targetId).CleanName()
        local lc = targethit
        if (BuffClass[spellIndex].classes == 'all' or (BuffClass[spellIndex].classes and BuffClass[spellIndex].classes[lc])) and IconCheck(spellIndex, targetId) then
            local peer = charinfo.GetInfo(grpname)
            if peer then
                local id, hit = BuffEvalBotNeedsBuff(targetId, grpname, sid, range, spellIndex, lc)
                if id then return id, hit end
            else
                if spellutils.EnsureSpawnBuffsPopulated(targetId, 'buff', spellIndex, lc, nil, nil, nil) and spellutils.SpawnNeedsBuff(targetId, spell, entry.spellicon) then
                    return targetId, lc
                end
            end
        end
    end
    return nil, nil
end

function botcast.BuffCheck(runPriority)
    local mobList = state.getRunconfig().MobList
    local hasMob = mobList and mobList[1]
    local count = botconfig.getSpellCount('buff')
    if count <= 0 then return false end
    local tank, tankid = spellutils.GetTankInfo(false)
    local bots = spellutils.GetBotListShuffled()
    local ctx = { tank = tank, tankid = tankid, bots = bots, botcount = #bots, buffCount = count }
    local options = {
        skipInterruptForBRD = true,
        runPriority = runPriority,
        entryValid = function(i)
            local entry = botconfig.getSpellEntry('buff', i)
            if not entry then return false end
            local gem = entry.gem
            if entry.enabled == false then return false end
            if not ((type(gem) == 'number' and gem ~= 0) or type(gem) == 'string') then return false end
            local cbtspell = BuffClass[i] and BuffClass[i].cbt
            local idlespell = BuffClass[i] and BuffClass[i].idle
            return (not hasMob and (not cbtspell or idlespell)) or (hasMob and cbtspell)
        end,
    }
    local function getSpellIndices(phase)
        return spellutils.getSpellIndicesForPhase(count, phase, buffBandHasPhase)
    end
    return spellutils.RunPhaseFirstSpellCheck('buff', 'doBuff', BUFF_PHASE_ORDER, buffGetTargetsForPhase, getSpellIndices,
        buffTargetNeedsSpell, ctx, options)
end

-- ---------------------------------------------------------------------------
-- Cure
-- ---------------------------------------------------------------------------

local function defaultCureEntry()
    return {
        gem = 0,
        spell = 0,
        minmana = 0,
        alias = false,
        announce = false,
        curetype = "all",
        enabled = true,
        bands = { { targetphase = { 'self', 'tank', 'groupmember', 'pc' }, validtargets = { 'all' } } },
        priority = false,
        precondition = true
    }
end

function botcast.LoadCureConfig()
    botcast.LoadSpellSectionConfig('cure', {
        defaultEntry = defaultCureEntry,
        bandsKey = 'cure',
        storeIn = CureClass,
        perEntryAfterBands = function(entry, i)
            CureType[i] = {}
            for word in (entry.curetype or 'all'):gmatch("%S+") do
                CureType[i][word] = word
            end
        end,
    })
end

local function CureTypeList(index)
    local list = {}
    for k in pairs(CureType[index] or {}) do list[#list + 1] = k end
    return list
end

-- MQCharInfo peer fields for detrimentals (config curetype words are mapped here)
local CureTypeToPeerKey = {
    poison = "CountPoison",
    disease = "CountDisease",
    curse = "CountCurse",
    corruption = "CountCorruption",
}

local function CureEvalForTarget(index, botname, botid, botclass, targethit, spelltartype, resumePhase, resumeGroupIndex)
    local cureindex = CureClass[index]
    if not cureindex then return nil, nil end
    for _, v in pairs(CureType[index] or {}) do
        if not botname then
            local curetype = mq.TLO.Me[v] and mq.TLO.Me[v]()
            if string.lower(v) ~= 'all' and curetype then
                if spelltartype == 'Self' then return 1, 'self' end
                return mq.TLO.Me.ID(), 'self'
            end
        else
            local peer = charinfo.GetInfo(botname)
            if peer then
                local detrimentals = peer.Detrimentals or nil
                local key = (string.lower(v) ~= 'all') and CureTypeToPeerKey[string.lower(v)]
                local curetype = key and (peer[key] or nil) or nil
                if string.lower(v) == 'all' and detrimentals and detrimentals > 0 then
                    if targethit == 'tank' then return botid, 'tank' end
                    if targethit == 'groupmember' and spellutils.DistanceCheck('cure', index, botid) then
                        return botid,
                            'groupmember'
                    end
                    if targethit == botclass and cureindex[botclass] and spellutils.DistanceCheck('cure', index, botid) then
                        return
                            botid, botclass
                    end
                end
                if string.lower(v) ~= 'all' and curetype and curetype > 0 then
                    if targethit == 'tank' and mq.TLO.Spawn(botid).Type() == 'PC' and spellutils.DistanceCheck('cure', index, botid) then
                        return
                            botid, 'tank'
                    end
                    if targethit == 'groupmember' and spellutils.DistanceCheck('cure', index, botid) then
                        return botid,
                            'groupmember'
                    end
                    if targethit == botclass and cureindex[botclass] and spellutils.DistanceCheck('cure', index, botid) then
                        return
                            botid, botclass
                    end
                end
            end
        end
    end
    if botname and botid and not charinfo.GetInfo(botname) then
        if not spellutils.EnsureSpawnBuffsPopulated(botid, 'cure', index, targethit, CureTypeList(index), resumePhase, resumeGroupIndex) then
            return
                nil, nil
        end
        local typelist = CureTypeList(index)
        local needCure = spellutils.SpawnDetrimentalsForCure(botid, typelist)
        if needCure and spellutils.DistanceCheck('cure', index, botid) then
            if targethit == 'tank' then return botid, 'tank' end
            if targethit == 'groupmember' then return botid, 'groupmember' end
        end
    end
    return nil, nil
end

local function CureEvalGroupCure(index, entry)
    local typelist = CureTypeList(index)
    local function needCure(grpmember, grpid, grpname, peer)
        if peer then
            for _, v in pairs(CureType[index] or {}) do
                local detrimentals = peer.Detrimentals or nil
                local key = (string.lower(v) ~= 'all') and CureTypeToPeerKey[string.lower(v)]
                local curetype = key and (peer[key] or nil) or nil
                if (string.lower(v) == 'all' and detrimentals and detrimentals > 0) or (string.lower(v) ~= 'all' and curetype and curetype > 0) then
                    return true
                end
            end
            return false
        end
        return spellutils.SpawnDetrimentalsForCure(grpid, typelist)
    end
    return evalGroupAECount(entry, 'groupcure', index, CureClass, 'groupcure', needCure, {})
end

local function CureEval(index)
    local entry = botconfig.getSpellEntry('cure', index)
    local spell, _, spelltartype = spellutils.GetSpellInfo(entry)
    if not spell then return nil, nil end
    local bots = spellutils.GetBotListShuffled()
    local botcount = charinfo.GetPeerCnt()
    local tank, tankid = spellutils.GetTankInfo(false)
    local cureindex = CureClass[index]
    if not cureindex then return nil, nil end
    if cureindex.self then
        local id, hit = CureEvalForTarget(index, nil, nil, nil, 'self', spelltartype)
        if id then return id, hit end
    end
    if cureindex.tank and tankid then
        local id, hit = CureEvalForTarget(index, tank, tankid, nil, 'tank', spelltartype, 'after_tank', nil)
        if id then return id, hit end
    end
    if cureindex.groupcure then
        local id, hit = CureEvalGroupCure(index, entry)
        if id then return id, hit end
    end
    if cureindex.groupmember then
        for i = 1, botcount do
            local botname = bots[i]
            local botid = mq.TLO.Spawn('pc =' .. botname).ID()
            local botclass = mq.TLO.Spawn('pc =' .. botname).Class.ShortName()
            if botclass then botclass = string.lower(botclass) end
            if cureindex[botclass] and botid and mq.TLO.Group.Member(botname).ID() then
                local id, hit = CureEvalForTarget(index, botname, botid, botclass, 'groupmember', spelltartype)
                if id then return id, hit end
            end
        end
        for i = 1, mq.TLO.Group.Members() do
            local grpmember = mq.TLO.Group.Member(i)
            if grpmember and grpmember.Class then
                local grpname = grpmember.Name()
                local grpid = grpmember.ID()
                local grpclass = grpmember.Class.ShortName()
                if grpclass then grpclass = string.lower(grpclass) end
                if grpid and grpid > 0 and cureindex[grpclass] and not charinfo.GetInfo(grpname) then
                    local id, hit = CureEvalForTarget(index, grpname, grpid, grpclass, 'groupmember', spelltartype,
                        'groupmember', i)
                    if id then return id, hit end
                end
            end
        end
    end
    if cureindex.pc and botcount then
        for i = 1, botcount do
            local botname = bots[i]
            if botname then
                local botid = mq.TLO.Spawn('pc =' .. botname).ID()
                local botclass = mq.TLO.Spawn('pc =' .. botname).Class.ShortName()
                if botclass then botclass = string.lower(botclass) end
                if botclass and cureindex[botclass] then
                    local id, hit = CureEvalForTarget(index, botname, botid, botclass, botclass, spelltartype)
                    if id then return id, hit end
                end
            end
        end
    end
    return nil, nil
end

-- Phase-first cure: phase order and helpers for RunPhaseFirstSpellCheck.
local CURE_PHASE_ORDER = { 'self', 'tank', 'groupcure', 'groupmember', 'pc' }

local function cureGetTargetsForPhase(phase, context)
    if phase == 'self' then return getTargetsSelf() end
    if phase == 'tank' then return getTargetsTank(context) end
    if phase == 'groupcure' then return getTargetsGroupCaster('groupcure') end
    if phase == 'groupmember' then return getTargetsGroupMember(context,
            { botsFirst = true, excludeBotsFromGroup = true }) end
    if phase == 'pc' then return getTargetsPc(context) end
    return {}
end

local function cureBandHasPhase(spellIndex, phase)
    return bandHasPhaseSimple(CureClass, spellIndex, phase)
end

local function cureTargetNeedsSpell(spellIndex, targetId, targethit, context)
    local entry = botconfig.getSpellEntry('cure', spellIndex)
    if not entry or not CureClass[spellIndex] then return nil, nil end
    local spell, _, spelltartype = spellutils.GetSpellInfo(entry)
    if not spell then return nil, nil end
    local botname = (targethit ~= 'self') and mq.TLO.Spawn(targetId).CleanName() or nil
    local botclass = targethit
    if targethit == 'self' then
        return CureEvalForTarget(spellIndex, nil, nil, nil, 'self', spelltartype)
    end
    if targethit == 'tank' then
        local id, hit = CureEvalForTarget(spellIndex, context.tank, context.tankid, nil, 'tank', spelltartype, nil, nil)
        if id == targetId then return id, hit end
        return nil, nil
    end
    if targethit == 'groupcure' then
        return CureEvalGroupCure(spellIndex, entry)
    end
    local id, hit = CureEvalForTarget(spellIndex, botname, targetId, botclass, targethit, spelltartype, nil, nil)
    if id == targetId then return id, hit end
    return nil, nil
end

function botcast.CureCheck(runPriority)
    if state.getRunconfig().SpellTimer > mq.gettime() then return false end
    local count = botconfig.getSpellCount('cure')
    if count <= 0 then return false end
    local tank, tankid = spellutils.GetTankInfo(false)
    local bots = spellutils.GetBotListShuffled()
    local ctx = { tank = tank, tankid = tankid, bots = bots }
    local priority = myconfig.cure.prioritycure
    local options = {
        skipInterruptForBRD = true,
        runPriority = runPriority,
        priority = priority,
        afterCast = priority and function(i)
            local e, c = CureEval(i)
            return e and c
        end or nil,
        entryValid = function(i)
            local entry = botconfig.getSpellEntry('cure', i)
            if not entry then return false end
            local gem = entry.gem
            return (entry.enabled ~= false) and ((type(gem) == 'number' and gem ~= 0) or type(gem) == 'string')
        end,
    }
    local function getSpellIndices(phase)
        return spellutils.getSpellIndicesForPhase(count, phase, cureBandHasPhase)
    end
    return spellutils.RunPhaseFirstSpellCheck('cure', 'doCure', CURE_PHASE_ORDER, cureGetTargetsForPhase, getSpellIndices,
        cureTargetNeedsSpell, ctx, options)
end

-- ---------------------------------------------------------------------------
-- Heal
-- ---------------------------------------------------------------------------

local function defaultHealEntry()
    return {
        gem = 0,
        spell = 0,
        minmana = 0,
        minmanapct = 0,
        maxmanapct = 100,
        alias = false,
        announce = false,
        enabled = true,
        bands = { { targetphase = { 'self', 'tank', 'pc', 'groupmember', 'groupheal', 'mypet', 'pet', 'corpse' }, validtargets = { 'all' }, min = 0, max = 60 } },
        priority = false,
        precondition = true
    }
end

function botcast.LoadHealConfig()
    botcast.LoadSpellSectionConfig('heal', {
        defaultEntry = defaultHealEntry,
        bandsKey = 'heal',
        storeIn = AHThreshold,
        preLoad = function()
            if myconfig.heal.rezoffset == nil then myconfig.heal.rezoffset = 0 end
            if myconfig.heal.interruptlevel == nil then myconfig.heal.interruptlevel = 0.80 end
            if myconfig.heal.xttargets == nil then myconfig.heal.xttargets = 0 end
        end,
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

local function hpInBand(pct, th)
    return spellbands.hpInBand(pct, th)
end

-- Get spawn HP and check band. spawnIdOrSpawn: spawn ID (number) or spawn-like object with PctHPs(). band: { min, max }.
local function hpEvalSpawn(spawnIdOrSpawn, band)
    local pct
    if type(spawnIdOrSpawn) == 'number' then
        pct = mq.TLO.Spawn(spawnIdOrSpawn).PctHPs()
    else
        pct = spawnIdOrSpawn.PctHPs and spawnIdOrSpawn.PctHPs()
    end
    return pct and spellbands.hpInBand(pct, band)
end

-- Returns (id, targethit) if band allows phase, pct in band, and (distOk is nil or true); else (nil, nil).
local function hpEvalReturn(index, phaseKey, pct, id, targethit, distOk)
    if not AHThreshold[index] or not AHThreshold[index][phaseKey] then return nil, nil end
    if not pct or not hpInBand(pct, AHThreshold[index][phaseKey]) then return nil, nil end
    if distOk ~= nil and not distOk then return nil, nil end
    return id, targethit
end

local function HPEvalContext(index)
    local entry = botconfig.getSpellEntry('heal', index)
    if not entry then return nil end
    local gem = entry.gem
    local tank, tankid = spellutils.GetTankInfo(false)
    local botcount = charinfo.GetPeerCnt()
    local bots = spellutils.GetBotListShuffled()
    local botstr = table.concat(charinfo.GetPeers(), " ")
    local tanknbid = tank and string.find(botstr, tank)
    local spell, spellrange = spellutils.GetSpellInfo(entry)
    if not spell then return nil end
    if gem == 'item' and mq.TLO.FindItem(entry.spell)() then
        spellrange = mq.TLO.FindItem(entry.spell).Spell.MyRange()
    end
    return {
        entry = entry,
        gem = gem,
        spell = spell,
        spellrange = spellrange,
        tank = tank,
        tankid = tankid,
        tanknbid = tanknbid,
        botcount = botcount,
        bots = bots,
    }
end

local function CorpseRezIdForFilter(index, ctx, filter)
    local corpsecount = mq.TLO.SpawnCount('pccorpse radius ' .. myconfig.settings.acleash)()
    if not corpsecount or corpsecount == 0 then return nil end
    local corpsedist = myconfig.settings.acleash
    local thresh = AHThreshold[index]
    local matches = 0
    for i = 1, corpsecount do
        local nearcorpse = mq.TLO.NearestSpawn(i, 'pccorpse radius ' .. corpsedist).CleanName()
        if nearcorpse then nearcorpse = string.gsub(nearcorpse, "'s corpse", "") end
        local rezid = mq.TLO.NearestSpawn(i, 'pccorpse radius ' .. corpsedist).ID()
        local match = false
        if filter == 'all' then
            match = true
        elseif filter == 'bots' and ctx.botcount then
            for k = 1, ctx.botcount do
                local peer = charinfo.GetInfo(ctx.bots[k])
                if peer and peer.Name == nearcorpse then
                    match = true
                    break
                end
            end
        elseif filter == 'raid' and mq.TLO.Raid.Members() and mq.TLO.Raid.Members() > 0 then
            for k = 1, mq.TLO.Raid.Members() do
                local raidname = mq.TLO.Raid.Member(k).Name()
                if raidname == nearcorpse then
                    match = true
                    break
                end
            end
        end
        if match then
            if myconfig.heal.rezoffset > 0 and matches < myconfig.heal.rezoffset and corpsecount > myconfig.heal.rezoffset then
                matches = matches + 1
            else
                return rezid
            end
        end
    end
    return nil
end

local function HPEvalCorpse(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].corpse then return nil, nil end
    if not AHThreshold[index].cbt and state.getRunconfig().MobList and state.getRunconfig().MobList[1] then
        return nil,
            nil
    end
    if AHThreshold[index].all then
        local rezid = CorpseRezIdForFilter(index, ctx, 'all')
        if rezid then return rezid, 'corpse' end
    end
    if AHThreshold[index].bots then
        local rezid = CorpseRezIdForFilter(index, ctx, 'bots')
        if rezid then return rezid, 'corpse' end
    end
    if AHThreshold[index].raid then
        local rezid = CorpseRezIdForFilter(index, ctx, 'raid')
        if rezid then return rezid, 'corpse' end
    end
    return nil, nil
end

local function HPEvalSelf(index, ctx)
    local pct = mq.TLO.Me.PctHPs()
    local id = mq.TLO.Spell(ctx.entry.spell).TargetType() == 'Self' and 1 or mq.TLO.Me.ID()
    return hpEvalReturn(index, 'self', pct, id, 'self', nil)
end

local function HPEvalGrp(index, ctx)
    local aeRange = mq.TLO.Spell(ctx.entry.spell).AERange()
    if ctx.gem == 'item' and mq.TLO.FindItem(ctx.entry.spell)() then
        aeRange = mq.TLO.FindItem(ctx.entry.spell).Spell.AERange()
    end
    if not aeRange or aeRange <= 0 then return nil, nil end
    local function needHeal(grpmember, grpid, grpname, peer)
        local grpspawn = grpmember.Spawn
        if not grpspawn then return false end
        local grpmempcthp = grpspawn.PctHPs()
        local grpmemdist = grpspawn.Distance()
        return grpmember.Present() and grpmempcthp and hpInBand(grpmempcthp, AHThreshold[index].groupheal)
            and grpmemdist and grpmemdist <= aeRange and grpspawn.Type() ~= 'Corpse'
    end
    return evalGroupAECount(ctx.entry, 'groupheal', index, AHThreshold, 'groupheal', needHeal, { aeRange = aeRange, includeMemberZero = true })
end

local function HPEvalTank(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].tank or not ctx.tank then return nil, nil end
    local tankdist = mq.TLO.Spawn(ctx.tankid).Distance()
    local tankinfo = charinfo.GetInfo(ctx.tank)
    local tanknbhp = tankinfo and tankinfo.PctHPs or nil
    if not ctx.tanknbid and ctx.tankid and mq.TLO.Group.Member(ctx.tank).Index() then
        if mq.TLO.Spawn(ctx.tankid).Type() == 'PC' and hpEvalSpawn(ctx.tankid, AHThreshold[index].tank) and tankdist and ctx.spellrange and tankdist <= ctx.spellrange then
            return mq.TLO.Group.Member(ctx.tank).ID(), 'tank'
        end
    elseif ctx.tanknbid then
        if mq.TLO.Spawn(ctx.tankid).Type() == 'PC' and tanknbhp and hpInBand(tanknbhp, AHThreshold[index].tank) and tankdist and ctx.spellrange and tankdist <= ctx.spellrange then
            return mq.TLO.Spawn('pc =' .. ctx.tank).ID(), 'tank'
        end
    end
    return nil, nil
end

local function HPEvalPc(index, ctx)
    if not AHThreshold[index] then return nil, nil end
    local th = AHThreshold[index]
    local classOk = function(cls)
        if not cls then return false end
        local c = cls:lower()
        if th.classes == 'all' then return true end
        return th.classes and th.classes[c] == true
    end
    -- groupmember only: group members (Group slots)
    if th.groupmember and mq.TLO.Group.Members() > 0 then
        for i = 1, mq.TLO.Group.Members() do
            local grpmember = mq.TLO.Group.Member(i)
            if grpmember and grpmember.Class then
                local grpspawn = grpmember.Spawn
                local grpclass = grpmember.Class.ShortName()
                local grpid = grpmember.ID()
                local grpdist = grpspawn and grpspawn.Distance() or nil
                if classOk(grpclass) and mq.TLO.Spawn(grpid).Type() == 'PC' and th.groupmember and hpEvalSpawn(grpid, th.groupmember) then
                    if ctx.spellrange and grpdist and grpdist <= ctx.spellrange then return grpid, grpclass:lower() end
                end
            end
        end
    end
    -- pc: all peers (ctx.bots)
    if th.pc and ctx.botcount then
        for i = 1, ctx.botcount do
            local botid = mq.TLO.Spawn('pc =' .. ctx.bots[i]).ID()
            local botclass = mq.TLO.Spawn('pc =' .. ctx.bots[i]).Class.ShortName()
            local peer = charinfo.GetInfo(ctx.bots[i])
            local bothp = peer and peer.PctHPs or nil
            local botdist = mq.TLO.Spawn(ctx.bots[i]).Distance()
            if botid and botclass and classOk(botclass) and mq.TLO.Spawn(botid).Type() == 'PC' and bothp and th.pc and hpInBand(bothp, th.pc) then
                if botdist and ctx.spellrange and botdist <= ctx.spellrange then return botid, botclass:lower() end
            end
        end
    end
    return nil, nil
end

local function HPEvalMyPet(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].mypet then return nil, nil end
    local mypetid = mq.TLO.Me.Pet.ID()
    local mypetdist = mq.TLO.Me.Pet.Distance()
    if mypetid and mypetid > 0 then
        local distOk = mypetdist and ctx.spellrange and mypetdist <= ctx.spellrange
        if hpEvalSpawn(mypetid, AHThreshold[index].mypet) and distOk then return mypetid, 'mypet' end
    end
    return nil, nil
end

local function HPEvalPets(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].pet or not ctx.botcount then return nil, nil end
    for i = 1, ctx.botcount do
        local petid = mq.TLO.Spawn('pc =' .. ctx.bots[i]).Pet.ID()
        local petdist = petid and mq.TLO.Spawn(petid).Distance()
        if petid and petid > 0 then
            local distOk = ctx.spellrange and petdist and petdist <= ctx.spellrange
            if hpEvalSpawn(petid, AHThreshold[index].pet) and distOk then return petid, 'pet' end
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
                local xtrange = mq.TLO.Me.XTarget(i).Distance() or 500
                local xtid = mq.TLO.Me.XTarget(i).ID() or 0
                if xtid and xtid > 0 then
                    local distOk = xtrange <= ctx.spellrange
                    if hpEvalSpawn(xtid, AHThreshold[index].xtgt) and distOk then return xtid, 'xtgt' end
                end
            end
        end
    end
    return nil, nil
end

local function HPEval(index)
    if not index then return nil, nil end
    local ctx = HPEvalContext(index)
    if not ctx then return nil, nil end
    local id, hit = HPEvalCorpse(index, ctx)
    if id then return id, hit end
    id, hit = HPEvalSelf(index, ctx)
    if id then return id, hit end
    id, hit = HPEvalGrp(index, ctx)
    if id then return id, hit end
    id, hit = HPEvalTank(index, ctx)
    if id then return id, hit end
    id, hit = HPEvalPc(index, ctx)
    if id then return id, hit end
    id, hit = HPEvalMyPet(index, ctx)
    if id then return id, hit end
    id, hit = HPEvalPets(index, ctx)
    if id then return id, hit end
    id, hit = HPEvalXtgt(index, ctx)
    if id then return id, hit end
    return nil, nil
end

-- Phase-first heal: phase order and helpers for RunPhaseFirstSpellCheck.
local HEAL_PHASE_ORDER = { 'corpse', 'self', 'groupheal', 'tank', 'groupmember', 'pc', 'mypet', 'pet', 'xtgt' }

local function healGetTargetsForPhase(phase, context)
    if phase == 'self' then return getTargetsSelf() end
    if phase == 'tank' then return getTargetsTank(context) end
    if phase == 'groupheal' then return getTargetsGroupCaster('groupheal') end
    if phase == 'groupmember' then return getTargetsGroupMember(context, {}) end
    if phase == 'pc' then return getTargetsPc(context) end
    if phase == 'mypet' then return getTargetsMypet() end
    if phase == 'pet' then return getTargetsPet(context) end
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
        local count = botconfig.getSpellCount('heal')
        for idx = 1, count do
            if AHThreshold[idx] and AHThreshold[idx].corpse then
                local filter = AHThreshold[idx].all and 'all' or AHThreshold[idx].bots and 'bots' or
                AHThreshold[idx].raid and 'raid' or 'all'
                local rezid = CorpseRezIdForFilter(idx, context, filter)
                if rezid then return { { id = rezid, targethit = 'corpse' } } end
            end
        end
        return {}
    end
    return {}
end

local function healBandHasPhase(spellIndex, phase)
    if not AHThreshold[spellIndex] then return false end
    if phase == 'corpse' then return AHThreshold[spellIndex].corpse end
    if phase == 'groupmember' or phase == 'pc' then
        return (AHThreshold[spellIndex].groupmember or AHThreshold[spellIndex].pc) and true or false
    end
    return AHThreshold[spellIndex][phase] and true or false
end

local function healTargetNeedsSpell(spellIndex, targetId, targethit, context)
    local ctx = HPEvalContext(spellIndex)
    if not ctx then return nil, nil end
    if targethit == 'self' then return HPEvalSelf(spellIndex, ctx) end
    if targethit == 'tank' then
        local id, hit = HPEvalTank(spellIndex, ctx)
        if id == targetId then return id, hit end
        return nil, nil
    end
    if targethit == 'groupheal' then return HPEvalGrp(spellIndex, ctx) end
    if targethit == 'corpse' then
        local id, hit = HPEvalCorpse(spellIndex, ctx)
        if id == targetId then return id, hit end
        return nil, nil
    end
    if targethit == 'mypet' then
        local id, hit = HPEvalMyPet(spellIndex, ctx)
        if id == targetId then return id, hit end
        return nil, nil
    end
    if targethit == 'pet' then
        local id, hit = HPEvalPets(spellIndex, ctx)
        if id == targetId then return id, hit end
        return nil, nil
    end
    if targethit == 'xtgt' then
        local id, hit = HPEvalXtgt(spellIndex, ctx)
        if id == targetId then return id, hit end
        return nil, nil
    end
    -- groupmember or pc (class key)
    if AHThreshold[spellIndex] then
        local th = AHThreshold[spellIndex]
        local classOk = function(cls)
            if not cls then return false end
            local c = cls:lower()
            if th.classes == 'all' then return true end
            return th.classes and th.classes[c] == true
        end
        local sp = mq.TLO.Spawn(targetId)
        if sp and sp.ID() == targetId and mq.TLO.Spawn(targetId).Type() == 'PC' then
            local dist = sp.Distance()
            if th.groupmember and hpEvalSpawn(targetId, th.groupmember) and ctx.spellrange and dist and dist <= ctx.spellrange and classOk(targethit) then
                return targetId, targethit
            end
            if th.pc and context.botcount then
                local peer = charinfo.GetInfo(mq.TLO.Spawn(targetId).CleanName())
                local bothp = peer and peer.PctHPs or nil
                if bothp and hpInBand(bothp, th.pc) and dist and ctx.spellrange and dist <= ctx.spellrange and classOk(targethit) then
                    return targetId, targethit
                end
            end
        end
    end
    return nil, nil
end

function botcast.ValidateHeal()
    local target = state.getRunconfig().CurSpell.target
    local index = state.getRunconfig().CurSpell.spell
    local healtar, matchtype = HPEval(index)
    return healtar and healtar > 0
end

function botcast.HealCheck(runPriority)
    local count = botconfig.getSpellCount('heal')
    if count <= 0 then return false end
    local ctx = HPEvalContext(1)
    if not ctx then return false end
    local options = {
        runPriority = runPriority,
        priority = false,
        afterCast = function(_, _target, targethit)
            local entry = botconfig.getSpellEntry('heal',
                state.getRunconfig().CurSpell and state.getRunconfig().CurSpell.spell)
            if entry and entry.priority then return botcast.ValidateHeal() end
            return false
        end,
        entryValid = function(i)
            local entry = botconfig.getSpellEntry('heal', i)
            if not entry then return false end
            if entry.enabled == false or entry.gem == 0 then return false end
            local minmanapct = entry.minmanapct
            local maxmanapct = entry.maxmanapct
            if minmanapct == nil then minmanapct = 0 end
            if maxmanapct == nil then maxmanapct = 100 end
            local mymana = mq.TLO.Me.PctMana()
            if mymana and (mymana < minmanapct or mymana > maxmanapct) then return false end
            return true
        end,
    }
    local function getSpellIndices(phase)
        return spellutils.getSpellIndicesForPhase(count, phase, healBandHasPhase)
    end
    return spellutils.RunPhaseFirstSpellCheck('heal', 'doHeal', HEAL_PHASE_ORDER, healGetTargetsForPhase, getSpellIndices,
        healTargetNeedsSpell, ctx, options)
end

-- ---------------------------------------------------------------------------
-- Debuff
-- ---------------------------------------------------------------------------

local function defaultDebuffEntry()
    return {
        gem = 0,
        spell = 0,
        minmana = 0,
        alias = false,
        announce = false,
        enabled = true,
        bands = { { targetphase = { 'tanktar', 'notanktar', 'named' }, min = 20, max = 100 } },
        charmnames = '',
        recast = 0,
        delay = 0,
        precondition = true
    }
end

function botcast.LoadDebuffConfig()
    botcast.LoadSpellSectionConfig('debuff', {
        defaultEntry = defaultDebuffEntry,
        bandsKey = 'debuff',
        storeIn = DebuffBands,
        preLoad = spellstates.EnsureDebuffState,
        perEntryNormalize = function(entry)
            if not entry.delay then entry.delay = 0 end
        end,
    })
end

local sectionLoaders = {
    buff = botcast.LoadBuffConfig,
    cure = botcast.LoadCureConfig,
    heal = botcast.LoadHealConfig,
    debuff = botcast.LoadDebuffConfig,
}

function botcast.RegisterSectionLoader(section, settingsKey)
    botconfig.RegisterConfigLoader(function()
        if botconfig.config.settings[settingsKey] then sectionLoaders[section]() end
    end)
end

botcast.RegisterSectionLoader('buff', 'dobuff')
botcast.RegisterSectionLoader('cure', 'docure')
botcast.RegisterSectionLoader('heal', 'doheal')
botcast.RegisterSectionLoader('debuff', 'dodebuff')

local noncombatzones = { 'GuildHall', 'GuildLobby', 'PoKnowledge', 'Nexus', 'Bazaar', 'AbysmalSea', 'potranquility' }

local function ADSpawnCheck_ValidateAcmTarget(rc)
    if rc.engageTargetId then
        if not mq.TLO.Spawn(rc.engageTargetId).ID() or mq.TLO.Spawn(rc.engageTargetId).Type() == 'Corpse' then
            rc.engageTargetId = nil
        end
    end
    if utils.isInList(mq.TLO.Zone.ShortName(), noncombatzones) then return false end
    return true
end

local function ADSpawnCheck_BuildSpawnList()
    local function buildMobListPredicate(spawn)
        local distance2D = spawn.Distance() or 5000
        return distance2D <= myconfig.settings.acleash
    end
    return mq.getFilteredSpawns(buildMobListPredicate)
end

local function ADSpawnCheck_FilterSpawn(spawn, rc)
    local distance2D = spawn.Distance() or 5000
    local distanceZ = spawn.DistanceZ() or 5000
    local spawnname = spawn.CleanName() or 'none'
    if rc.campstatus then
        local spawnx, spawny, spawnz = spawn.X(), spawn.Y(), spawn.Z()
        distance2D = utils.calcDist2D(spawnx, spawny, rc.makecamp.x, rc.makecamp.y)
        if spawnz then distanceZ = math.abs(spawnz - rc.makecamp.z) end
    end
    if rc.FTECount and spawn.ID() and rc.FTEList and rc.FTEList[spawn.ID()] and rc.FTEList[spawn.ID()].timer > mq.gettime() then
        return false
    end
    if not (spawnname and distance2D and distanceZ and distance2D <= myconfig.settings.acleash and distanceZ <= myconfig.settings.zradius) then
        return false
    end
    if string.find(rc.ExcludeList or '', spawnname) then return false end
    if myconfig.settings.TargetFilter == 2 then
        return not string.find('pc,banner,campfire,mercenary,mount,aura,corpse', string.lower(spawn.Type()))
    end
    if myconfig.settings.TargetFilter == 1 then
        return (spawn.Type() == 'NPC' or (spawn.Type() == 'Pet' and spawn.Master.Type() ~= 'PC')) and spawn.LineOfSight()
    end
    if myconfig.settings.TargetFilter == 0 then
        return (spawn.Type() == 'NPC' or (spawn.Type() == 'Pet' and spawn.Master.Type() ~= 'PC')) and spawn.Aggressive() and
            spawn.LineOfSight()
    end
    return false
end

local function ADSpawnCheck_ApplyFilter(spawnlist, rc)
    rc.MobList = {}
    for _, spawn in ipairs(spawnlist) do
        if ADSpawnCheck_FilterSpawn(spawn, rc) then
            table.insert(rc.MobList, spawn)
        end
    end
end

function botcast.ADSpawnCheck()
    local rc = state.getRunconfig()
    if not ADSpawnCheck_ValidateAcmTarget(rc) then return end
    local spawnlist = ADSpawnCheck_BuildSpawnList()
    ADSpawnCheck_ApplyFilter(spawnlist, rc)
    table.sort(rc.MobList, function(a, b) return a.ID() < b.ID() end)
    local mobcount = 0
    local killtarpresent = false
    if KillTarget and (mq.TLO.Spawn(KillTarget).Type() == 'Corpse' or not mq.TLO.Spawn(KillTarget).ID()) then KillTarget = nil end
    for k, v in ipairs(rc.MobList) do
        mobcount = mobcount + 1
        if v.ID() == KillTarget then killtarpresent = true end
    end
    if not killtarpresent and KillTarget then table.insert(rc.MobList, mq.TLO.Spawn(KillTarget)) end
    rc.MobCount = mobcount
end

local function DebuffEvalBuildContext(index)
    local entry = botconfig.getSpellEntry('debuff', index)
    if not entry then return nil end
    local spell, spellrange, spelltartype, spellid = spellutils.GetSpellInfo(entry)
    if not spell then return nil end
    local gem = entry.gem
    if spellrange == 0 and spelltartype == 'PB AE' then
        spellrange = mq.TLO.Spell(spell).AERange() or
            (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.AERange())
    end
    local spelldur = mq.TLO.Spell(entry.spell).MyDuration() or
        (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.MyDuration())
    local tank, tankid, tanktar, tanktarhp = spellutils.GetTankInfo(true)
    if tanktar == 0 then tanktar = nil end
    local tanktarlvl = tanktar and mq.TLO.Spawn(tanktar).Level()
    if type(gem) == 'number' or gem == 'item' or gem == 'disc' or gem == 'alt' then
        spellid = mq.TLO.Spell(entry.spell).ID() or
            (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.ID())
    end
    local spellmaxlvl = mq.TLO.Spell(spellid).MaxLevel() or
        (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.MaxLevel())
    local myrange = (type(gem) == 'number' or gem == 'item' or gem == 'disc' or gem == 'alt') and
        (mq.TLO.Spell(spellid).MyRange() or (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.MyRange()))
        or (gem == 'ability' and 20) or nil
    if mq.TLO.Spell(spellid).Category() == 'Pet' then myrange = myconfig.settings.acleash end
    local db = DebuffBands[index]
    local mobMin = db and db.mobMin or 0
    local mobMax = db and db.mobMax or 100
    return {
        entry = entry,
        spell = spell,
        spellid = spellid,
        spellrange = spellrange,
        spelldur = spelldur,
        gem = gem,
        tank = tank,
        tankid = tankid,
        tanktar = tanktar,
        tanktarhp = tanktarhp,
        tanktarlvl = tanktarlvl,
        spellmaxlvl = spellmaxlvl,
        myrange = myrange,
        mobList = state.getRunconfig().MobList or {},
        mobMin = mobMin,
        mobMax = mobMax,
    }
end

local function DebuffEvalTankTar(index, ctx)
    local entry = ctx.entry
    local gem = entry.gem
    local db = DebuffBands[index]
    if not db or not db.tanktar or not ctx.tanktar then return nil, nil end
    if not hpEvalSpawn(ctx.tanktar, { min = db.mobMin, max = db.mobMax }) then return nil, nil end
    for _, v in ipairs(ctx.mobList) do
        if v.ID() == ctx.tanktar then
            local myrange = ctx.myrange
            if entry.gem == 'ability' then myrange = v.MaxRangeTo() end
            if not (myrange and v.Distance() and v.Distance() > myrange) then
                if not (ctx.spelldur and tonumber(ctx.spelldur) > 0 and spellstates.HasDebuffLongerThan(v.ID(), ctx.spellid, 6000)) then
                    local tanktarstack = mq.TLO.Spell(entry.spell).StacksSpawn(ctx.tanktar)() or
                        (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.StacksSpawn(ctx.tanktar))
                    if ctx.tanktarlvl and mq.TLO.Spell(ctx.spellid).Subcategory() == 'Enthrall' and ctx.spellmaxlvl and ctx.spellmaxlvl ~= 0 and ctx.spellmaxlvl < ctx.tanktarlvl then
                        return nil, nil
                    end
                    if (type(gem) == 'number' or gem == 'alt' or gem == 'disc' or gem == 'item') and not tanktarstack then
                        return nil, nil
                    end
                    return state.getRunconfig().engageTargetId or ctx.tanktar, 'tanktar'
                end
            end
        end
    end
    return nil, nil
end

local function DebuffEvalNotanktar(index, ctx)
    local entry = ctx.entry
    local gem = entry.gem
    local db = DebuffBands[index]
    if not db or not db.notanktar or not ctx.mobList[1] then return nil, nil end
    for _, v in ipairs(ctx.mobList) do
        if v.ID() ~= ctx.tanktar then
            if hpEvalSpawn(v, { min = db.mobMin, max = db.mobMax }) then
                local myrange = ctx.myrange
                if entry.gem == 'ability' then myrange = v.MaxRangeTo() end
                if not (myrange and v.Distance() and v.Distance() > myrange) then
                    local tarstacks = mq.TLO.Spell(entry.spell).StacksSpawn(v.ID())() or
                        (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.StacksSpawn(v.ID()))
                    if not (ctx.spellid and v.Level() and ctx.spellmaxlvl and ctx.spellmaxlvl ~= 0 and ctx.spellmaxlvl < v.Level()) then
                        if not ((type(gem) == 'number' or gem == 'alt' or gem == 'disc' or gem == 'item') and not tarstacks) then
                            if not (tonumber(ctx.spelldur) > 0 and v.ID() and spellstates.HasDebuffLongerThan(v.ID(), ctx.spellid, 6000)) then
                                return v.ID(), 'notanktar'
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, nil
end

local function DebuffEvalNamedTankTar(index, ctx)
    local entry = ctx.entry
    local gem = entry.gem
    local db = DebuffBands[index]
    if not db or not db.named or not ctx.tanktar then return nil, nil end
    if not hpEvalSpawn(ctx.tanktar, { min = db.mobMin, max = db.mobMax }) then return nil, nil end
    for _, v in ipairs(ctx.mobList) do
        if v.ID() == ctx.tanktar and v.Named() then
            local myrange = ctx.myrange
            if entry.gem == 'ability' then myrange = v.MaxRangeTo() end
            if myrange and v.Distance() and v.Distance() > myrange then return nil, nil end
            if not (ctx.spelldur and tonumber(ctx.spelldur) > 0 and spellstates.HasDebuffLongerThan(v.ID(), ctx.spellid, 6000)) then
                local tanktarstack = mq.TLO.Spell(entry.spell).StacksSpawn(ctx.tanktar)() or
                    (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.StacksSpawn(ctx.tanktar))
                if ctx.tanktarlvl and mq.TLO.Spell(ctx.spellid).Subcategory() == 'Enthrall' and ctx.spellmaxlvl and ctx.spellmaxlvl ~= 0 and ctx.spellmaxlvl < ctx.tanktarlvl then
                    return nil, nil
                end
                if (type(gem) == 'number' or gem == 'alt' or gem == 'disc' or gem == 'item') and not tanktarstack then
                    return nil, nil
                end
                return state.getRunconfig().engageTargetId or ctx.tanktar, 'tanktar'
            end
        end
    end
    return nil, nil
end

local function DebuffEval(index)
    local entry = botconfig.getSpellEntry('debuff', index)
    if not entry then return nil, nil end
    if entry.tarcnt and entry.tarcnt > state.getRunconfig().MobCount then return nil, nil end
    local id, hit = charm.GetRecastRequestForIndex(index)
    if id then
        charm.ClearRecastRequest()
        return id, hit
    end
    local ctx = DebuffEvalBuildContext(index)
    if not ctx then return nil, nil end
    id, hit = charm.EvalTarget(index, ctx)
    if id then return id, hit end
    id, hit = DebuffEvalTankTar(index, ctx)
    if id then return id, hit end
    id, hit = DebuffEvalNotanktar(index, ctx)
    if id then return id, hit end
    id, hit = DebuffEvalNamedTankTar(index, ctx)
    if id then return id, hit end
    return nil, nil
end

-- Phase-first debuff: phase order and helpers.
local DEBUFF_PHASE_ORDER = { 'charm', 'tanktar', 'notanktar', 'named' }

local function debuffGetTargetsForPhase(phase, context)
    local out = {}
    local mobList = context.mobList or state.getRunconfig().MobList or {}
    if phase == 'charm' then
        if context.charmRecasts then
            for _, v in pairs(context.charmRecasts) do
                if v and v.id then out[#out + 1] = { id = v.id, targethit = v.targethit or 'charmtar' } end
            end
        end
        local count = context.debuffCount or botconfig.getSpellCount('debuff')
        for i = 1, count do
            local dctx = DebuffEvalBuildContext(i)
            if dctx then
                local id, hit = charm.EvalTarget(i, dctx)
                if id then out[#out + 1] = { id = id, targethit = hit or 'charmtar' } end
            end
        end
        return out
    end
    if phase == 'tanktar' and context.tanktar and context.tanktar > 0 then
        out[#out + 1] = { id = context.tanktar, targethit = 'tanktar' }
        return out
    end
    if phase == 'notanktar' then
        for _, v in ipairs(mobList) do
            local vid = v.ID and v.ID() or v
            if vid and vid ~= context.tanktar then out[#out + 1] = { id = vid, targethit = 'notanktar' } end
        end
        return out
    end
    if phase == 'named' and context.tanktar and context.tanktar > 0 then
        local sp = mq.TLO.Spawn(context.tanktar)
        if sp and sp.ID() == context.tanktar and sp.Named() then
            out[#out + 1] = { id = context.tanktar, targethit = 'named' }
        end
        return out
    end
    return out
end

local function debuffBandHasPhase(spellIndex, phase)
    return bandHasPhaseSimple(DebuffBands, spellIndex, phase)
end

local function debuffTargetNeedsSpell(spellIndex, targetId, targethit, context)
    local entry = botconfig.getSpellEntry('debuff', spellIndex)
    if not entry then return nil, nil end
    if entry.tarcnt and entry.tarcnt > state.getRunconfig().MobCount then return nil, nil end
    if targethit == 'charmtar' or targethit == 'charm' then
        if context.charmRecasts and context.charmRecasts[spellIndex] and context.charmRecasts[spellIndex].id == targetId then
            return targetId, context.charmRecasts[spellIndex].targethit or 'charmtar'
        end
        local ctx = DebuffEvalBuildContext(spellIndex)
        if ctx then
            local id, hit = charm.EvalTarget(spellIndex, ctx)
            if id == targetId then return id, hit or 'charmtar' end
        end
        return nil, nil
    end
    local ctx = DebuffEvalBuildContext(spellIndex)
    if not ctx then return nil, nil end
    if targethit == 'tanktar' then
        local id, hit = DebuffEvalTankTar(spellIndex, ctx)
        if id == targetId then return id, hit end
        return nil, nil
    end
    if targethit == 'named' then
        local id, hit = DebuffEvalNamedTankTar(spellIndex, ctx)
        if id == targetId then return id, hit end
        return nil, nil
    end
    if targethit == 'notanktar' then
        local entry = ctx.entry
        local gem = entry.gem
        local db = DebuffBands[spellIndex]
        if not db or not db.notanktar then return nil, nil end
        for _, v in ipairs(ctx.mobList) do
            local vid = v.ID and v.ID() or v
            if vid == targetId then
                if hpEvalSpawn(v, { min = db.mobMin, max = db.mobMax }) then
                    local myrange = ctx.myrange
                    if entry.gem == 'ability' then myrange = v.MaxRangeTo and v.MaxRangeTo() or ctx.myrange end
                    if not (myrange and v.Distance and v.Distance() and v.Distance() > myrange) then
                        local tarstacks = mq.TLO.Spell(entry.spell).StacksSpawn(targetId)() or
                            (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.StacksSpawn(targetId))
                        local vlevel = v.Level and v.Level() or mq.TLO.Spawn(targetId).Level()
                        if not (ctx.spellid and vlevel and ctx.spellmaxlvl and ctx.spellmaxlvl ~= 0 and ctx.spellmaxlvl < vlevel) then
                            if not ((type(gem) == 'number' or gem == 'alt' or gem == 'disc' or gem == 'item') and not tarstacks) then
                                if not (tonumber(ctx.spelldur) > 0 and spellstates.HasDebuffLongerThan(targetId, ctx.spellid, 6000)) then
                                    return targetId, 'notanktar'
                                end
                            end
                        end
                    end
                end
                break
            end
        end
    end
    return nil, nil
end

local function DebuffOnBeforeCast(i, EvalID, targethit)
    local entry = botconfig.getSpellEntry('debuff', i)
    if entry ~= nil and entry.recast ~= nil and entry.recast > 0 and spellstates.GetRecastCounter(EvalID, i) >= entry.recast then
        return false
    end
    charm.BeforeCast(EvalID, targethit)
    if targethit == 'tanktar' and EvalID and EvalID > 0 then
        if not myconfig.melee.offtank then state.getRunconfig().engageTargetId = EvalID end
        if mq.TLO.Pet.Target.ID() ~= EvalID and not mq.TLO.Me.Pet.Combat() then
            mq.cmdf('/pet attack %s', EvalID)
        end
    end
    return true
end

function botcast.DebuffCheck(runPriority)
    if state.getRunconfig().SpellTimer > mq.gettime() then return false end
    local mobcountstart = state.getRunconfig().MobCount
    local botmelee = require('botmelee')
    if state.getRunconfig().MobList and state.getRunconfig().MobList[1] then
        local tank, _, tanktar = spellutils.GetTankInfo(true)
        if tanktar and tanktar > 0 and mq.TLO.Pet.Target.ID() ~= tanktar and not mq.TLO.Me.Pet.Combat() then botmelee
                .AdvCombat() end
    end
    local count = botconfig.getSpellCount('debuff')
    if count <= 0 then return false end
    local _, _, tanktar = spellutils.GetTankInfo(true)
    local charmRecasts = {}
    for i = 1, count do
        local id, hit = charm.GetRecastRequestForIndex(i)
        if id then charmRecasts[i] = { id = id, targethit = hit or 'charmtar' } end
    end
    local ctx = {
        tanktar = tanktar,
        charmRecasts = charmRecasts,
        debuffCount = count,
        mobList = state.getRunconfig().MobList or {},
    }
    local options = {
        skipInterruptForBRD = true,
        runPriority = runPriority,
        immuneCheck = true,
        beforeCast = DebuffOnBeforeCast,
        entryValid = function(i)
            local entry = botconfig.getSpellEntry('debuff', i)
            if not entry then return false end
            local gem = entry.gem
            return (entry.enabled ~= false) and ((type(gem) == 'number' and gem ~= 0) or type(gem) == 'string')
        end,
        afterCast = function(i, EvalID, targethit)
            if spellstates.GetDebuffDelay(i) and spellstates.GetDebuffDelay(i) > mq.gettime() then return false end
            if mobcountstart < state.getRunconfig().MobCount then return false end
            local prevID = EvalID
            local newEvalID, newTargethit = DebuffEval(i)
            local adEntry = botconfig.getSpellEntry('debuff', i)
            if newEvalID and prevID == newEvalID and adEntry and (adEntry.recast or 0) > 0 and state.getRunconfig().CurSpell and state.getRunconfig().CurSpell.spell == i and state.getRunconfig().CurSpell.resisted then
                local newCount = spellstates.IncrementRecastCounter(EvalID, i)
                state.getRunconfig().CurSpell = {}
                if newCount >= adEntry.recast then
                    printf(
                        '\ayCZBot:\ax\ar%s\ax has resisted spell \ar%s\ax debuff[%s] \am%s\ax times, disabling spell for this spawn',
                        mq.TLO.Spawn(EvalID).CleanName(), adEntry.spell, i, adEntry.recast)
                    local recastduration = 600000 + mq.gettime()
                    local spellid = mq.TLO.Spell(adEntry.spell).ID() or
                        (adEntry.gem == 'item' and mq.TLO.FindItem(adEntry.spell)() and mq.TLO.FindItem(adEntry.spell).Spell.ID())
                    local spelldur = tonumber(mq.TLO.Spell(spellid).MyDuration()) or 0
                    if spelldur > 0 then spellstates.DebuffListUpdate(EvalID, adEntry.spell, recastduration) end
                end
                return true
            end
            return false
        end,
    }
    local function getSpellIndices(phase)
        if phase == 'charm' then
            local out = {}
            for i = 1, count do
                if ctx.charmRecasts[i] then out[#out + 1] = i end
            end
            for i = 1, count do
                local dctx = DebuffEvalBuildContext(i)
                if dctx and charm.EvalTarget(i, dctx) then
                    local found = false
                    for _, si in ipairs(out) do if si == i then
                            found = true
                            break
                        end end
                    if not found then out[#out + 1] = i end
                end
            end
            return out
        end
        return spellutils.getSpellIndicesForPhase(count, phase, debuffBandHasPhase)
    end
    return spellutils.RunPhaseFirstSpellCheck('debuff', 'doDebuff', DEBUFF_PHASE_ORDER, debuffGetTargetsForPhase,
        getSpellIndices, debuffTargetNeedsSpell, ctx, options)
end

do
    local hookregistry = require('lib.hookregistry')
    hookregistry.registerHookFn('ADSpawnCheck', function(hookName)
        botcast.ADSpawnCheck()
    end)
    hookregistry.registerHookFn('priorityCure', function(hookName)
        if not myconfig.settings.docure or not (myconfig.cure.spells and #myconfig.cure.spells > 0) or not myconfig.cure.prioritycure then return end
        if state.getRunState() == 'idle' then state.getRunconfig().statusMessage = 'Cure Check' end
        botcast.CureCheck(bothooks.getPriority(hookName))
    end)
    hookregistry.registerHookFn('doHeal', function(hookName)
        if not myconfig.settings.doheal or not (myconfig.heal.spells and #myconfig.heal.spells > 0) then return end
        if state.getRunState() == 'idle' then state.getRunconfig().statusMessage = 'Heal Check' end
        botcast.HealCheck(bothooks.getPriority(hookName))
    end)
    hookregistry.registerHookFn('doDebuff', function(hookName)
        if not myconfig.settings.dodebuff or not (myconfig.debuff.spells and #myconfig.debuff.spells > 0) or not state.getRunconfig().MobList[1] then return end
        if state.getRunState() == 'idle' then state.getRunconfig().statusMessage = 'Debuff Check' end
        botcast.DebuffCheck(bothooks.getPriority(hookName))
    end)
    hookregistry.registerHookFn('doBuff', function(hookName)
        if not myconfig.settings.dobuff or not (myconfig.buff.spells and #myconfig.buff.spells > 0) then return end
        if state.getRunState() == 'idle' then state.getRunconfig().statusMessage = 'Buff Check' end
        botcast.BuffCheck(bothooks.getPriority(hookName))
    end)
    hookregistry.registerHookFn('doCure', function(hookName)
        if not myconfig.settings.docure or not (myconfig.cure.spells and #myconfig.cure.spells > 0) then return end
        if state.getRunState() == 'idle' then state.getRunconfig().statusMessage = 'Cure Check' end
        botcast.CureCheck(bothooks.getPriority(hookName))
    end)
end

return botcast
