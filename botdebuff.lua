local mq = require('mq')
local botconfig = require('lib.config')
local spellutils = require('lib.spellutils')
local spellstates = require('lib.spellstates')
local state = require('lib.state')
local utils = require('lib.utils')
local bothooks = require('lib.bothooks')
local charm = require('lib.charm')
local castutils = require('lib.castutils')
local tankrole = require('lib.tankrole')
local aggro = require('lib.aggro')
local botmove = require('botmove')
local combat = require('lib.combat')
local log = require('lib.log')

local botdebuff = {}
local DebuffBands = {}
local _hasCharmSpell = false
local _hasNotmatarBand = false
--- Module-level spell meta (id/range/dur/maxlvl/ae) cleared on debuff config reload.
local _debuffSpellMeta = {}
local bardtwist = require('lib.bardtwist')
local botmelee = require('botmelee')
local targeting = require('lib.targeting')
local castinterrupt = require('lib.castinterrupt')
local spawnutils = require('lib.spawnutils')
local tickprof = require('lib.tickprof')

local function defaultDebuffEntry()
    return botconfig.getDefaultSpellEntry('debuff')
end

local function normalizeDebuffEntry(entry)
    if not entry then return end
    if type(entry.dontStack) == 'table' then
        local allowed = spellutils.GetDebuffDontStackAllowlist()
        local filtered = {}
        for _, tag in ipairs(entry.dontStack) do
            if allowed[tag] then filtered[#filtered + 1] = tag end
        end
        entry.dontStack = #filtered > 0 and filtered or nil
    end
    if type(entry.stopWhen) == 'table' then
        local allowed = spellutils.GetDebuffStopWhenAllowlist()
        local filtered = {}
        for _, tag in ipairs(entry.stopWhen) do
            if allowed[tag] then filtered[#filtered + 1] = tag end
        end
        entry.stopWhen = #filtered > 0 and filtered or nil
    end
end

function botdebuff.LoadDebuffConfig()
    _debuffSpellMeta = {}
    spellutils.ClearMezNukeSpellCache()
    castutils.LoadSpellSectionConfig('debuff', {
        defaultEntry = defaultDebuffEntry,
        bandsKey = 'debuff',
        storeIn = DebuffBands,
        perEntryNormalize = normalizeDebuffEntry,
    })
    _hasCharmSpell = false
    _hasNotmatarBand = false
    local count = botconfig.getSpellCount('debuff')
    local myconfig = botconfig.config
    for i = 1, count do
        local entry = botconfig.getSpellEntry('debuff', i)
        if entry and entry.enabled ~= false then
            if spellutils.IsCharmSpell(entry) then _hasCharmSpell = true end
            local db = DebuffBands[i]
            if db and db.notmatar then _hasNotmatarBand = true end
            local spell, spellrange, spelltartype = spellutils.GetSpellInfo(entry)
            if spell then
                local gem = entry.gem
                local meta = {
                    spell = spell,
                    spellrange = spellrange,
                    spelltartype = spelltartype,
                }
                if gem == 'ability' then
                    meta.myrange = 20
                    meta.myrangeSq = 400
                    _debuffSpellMeta[i] = meta
                elseif gem ~= 'script' then
                    local spellEntity = spellutils.GetSpellEntity(entry)
                    if spellEntity then
                        meta.spellid = spellEntity.ID()
                        meta.spellmaxlvl = spellEntity.MaxLevel()
                        meta.myrange = spellEntity.MyRange()
                        if spellrange == 0 and spelltartype == 'PB AE' then
                            meta.spellrange = spellEntity.AERange()
                        end
                        meta.spelldur = tonumber(spellEntity.MyDuration.TotalSeconds()) or 0
                        if spellEntity.Category() == 'Pet' then
                            meta.myrange = myconfig.settings.acleash
                        end
                        if spellutils.IsTargetedAESpell(entry) then
                            local ar = spellEntity.AERange()
                            if ar and ar > 0 then
                                meta.aeRange = ar
                                meta.minCastDist = ar + 2
                                meta.minCastDistSq = meta.minCastDist * meta.minCastDist
                            end
                        end
                        meta.myrangeSq = meta.myrange and (meta.myrange * meta.myrange) or nil
                        _debuffSpellMeta[i] = meta
                    end
                end
            end
        end
    end
end

castutils.RegisterSectionLoader('debuff', 'dodebuff', botdebuff.LoadDebuffConfig)

local function campCountOk(mobCount, mintar, maxtar)
    -- Treat 0 as "no limit"; only enforce when > 0
    if mintar and mintar > 0 and mobCount < mintar then return false end
    if maxtar and maxtar > 0 and mobCount > maxtar then return false end
    return true
end

local myconfig = botconfig.config

local function onlyMTDebuffAllowed(entry)
    if not entry.onlyMT then return true end
    if tankrole.AmIMainTank() and not myconfig.melee.offtank then return true end
    return botmelee.isActivelyOfftanking()
end

local function getMatarChosenTargetId(entry, ctx)
    if not entry.onlyMT then return ctx.maTargetId end
    if botmelee.isActivelyOfftanking() then
        return state.getRunconfig().engageTargetId
    end
    return ctx.mtTargetId
end

--- MobList spawn for matar eval; OT engage target allowed when briefly outside MobList.
--- Prefer direct Spawn when chosen id is already MA/MT (avoids MobList scan on the hot path).
local function debuffMatarSpawnForTarget(chosenTargetId, ctx)
    if not chosenTargetId then return nil end
    if chosenTargetId == ctx.maTargetId or chosenTargetId == ctx.mtTargetId then
        local sp = mq.TLO.Spawn(chosenTargetId)
        if spawnutils.isAliveEngageSpawn(sp) then return sp end
    end
    for _, v in ipairs(ctx.mobList) do
        if v.ID() == chosenTargetId then return v end
    end
    local rc = state.getRunconfig()
    if botmelee.isActivelyOfftanking() and chosenTargetId == rc.engageTargetId then
        local sp = mq.TLO.Spawn(chosenTargetId)
        if spawnutils.isAliveEngageSpawn(sp) then return sp end
    end
    return nil
end

local function DebuffEvalBuildContext(index, shared)
    local entry = botconfig.getSpellEntry('debuff', index)
    if not entry then return nil end
    local meta = _debuffSpellMeta[index]
    local spell, spellrange, spellId, spellMaxLvl, myrange, spelldur, minCastDistSq, aeRange, minCastDist
    if meta and meta.spell then
        spell = meta.spell
        spellrange = meta.spellrange
        spellId = meta.spellid
        spellMaxLvl = meta.spellmaxlvl
        myrange = meta.myrange
        spelldur = meta.spelldur
        aeRange = meta.aeRange
        minCastDist = meta.minCastDist
        minCastDistSq = meta.minCastDistSq
    else
        local spelltartype
        spell, spellrange, spelltartype = spellutils.GetSpellInfo(entry)
        if not spell then return nil end
        local gem = entry.gem
        if gem ~= 'ability' and gem ~= 'script' then
            local spellEntity = spellutils.GetSpellEntity(entry)
            if not spellEntity then return nil end
            spellId = spellEntity.ID()
            spellMaxLvl = spellEntity.MaxLevel()
            myrange = spellEntity.MyRange()
            if spellrange == 0 and spelltartype == 'PB AE' then
                spellrange = spellEntity.AERange()
            end
            spelldur = tonumber(spellEntity.MyDuration.TotalSeconds()) or 0
            if spellEntity.Category() == 'Pet' then myrange = botconfig.config.settings.acleash end
            if spellutils.IsTargetedAESpell(entry) then
                local ar = spellEntity.AERange()
                if ar and ar > 0 then
                    aeRange = ar
                    minCastDist = aeRange + 2
                    minCastDistSq = minCastDist * minCastDist
                end
            end
        end
        if gem == 'ability' then myrange = 20 end
    end
    if not spell then return nil end
    local gem = entry.gem
    -- Prefer pass-local MA/MT from DebuffCheck; fall back to Assist/Tank TLOs.
    local assistid, maTargetId, maTargetHp, maTargetLvl
    local tankid, mtTargetId, mtTargetHp, mtTargetLvl
    if shared then
        assistid = shared.assistid
        maTargetId = shared.maTargetId
        maTargetHp = shared.maTargethp
        maTargetLvl = shared.maTargetLvl
        tankid = shared.tankid
        mtTargetId = shared.mtTargetId
        mtTargetHp = shared.mtTargethp
        mtTargetLvl = shared.mtTargetLvl
    else
        local _tank
        _tank, tankid, mtTargetId, mtTargetHp = spellutils.GetTankInfo(true)
        if mtTargetId == 0 then mtTargetId = nil end
        mtTargetLvl = mtTargetId and mq.TLO.Spawn(mtTargetId).Level()
        local _assist
        _assist, assistid, maTargetId, maTargetHp = spellutils.GetAssistInfo(true)
        if maTargetId == 0 then maTargetId = nil end
        maTargetLvl = maTargetId and mq.TLO.Spawn(maTargetId).Level()
    end
    local myrangeSq = (meta and meta.myrangeSq) or (myrange and (myrange * myrange) or nil)
    local db = DebuffBands[index]
    local mobMin = db and db.mobMin or 0
    local mobMax = db and db.mobMax or 100
    local aggroMin = db and db.aggroMin or 0
    local aggroMax = db and db.aggroMax or 100
    return {
        entry = entry,
        spell = spell,
        spellid = spellId,
        spellrange = spellrange,
        spelldur = spelldur,
        gem = gem,
        assistid = assistid,
        maTargetId = maTargetId,
        maTargethp = maTargetHp,
        maTargetLvl = maTargetLvl,
        mtTargetId = mtTargetId,
        mtTargethp = mtTargetHp,
        mtTargetLvl = mtTargetLvl,
        spellmaxlvl = spellMaxLvl,
        myrange = myrange,
        myrangeSq = myrangeSq,
        aeRange = aeRange,
        minCastDist = minCastDist,
        minCastDistSq = minCastDistSq,
        mobList = (shared and shared.mobList) or (state.getRunconfig().MobList or {}),
        mobMin = mobMin,
        mobMax = mobMax,
        aggroMin = aggroMin,
        aggroMax = aggroMax,
        mintar = db and db.mintar,
        maxtar = db and db.maxtar,
    }
end

--- Pass-local spell context cache (set on DebuffCheck context as getSpellCtx).
local function spellCtxFor(context, index)
    if context and context.getSpellCtx then
        return context.getSpellCtx(index)
    end
    return DebuffEvalBuildContext(index, context)
end

-- Returns true if spawn is a valid target for this debuff (range, level, stacks, duration, AE mintar).
-- Performs mez skip messages (level, already mezzed) when applicable.
-- phase: 'matar' | 'notmatar' (named uses same rules as matar).
local function DebuffSpawnNeedsSpell(entry, ctx, spawn, phase)
    return spellutils.SpawnNeedsDebuff(entry, ctx, spawn, phase)
end

local function bardMatarDebuffEntry(spellIndex)
    if mq.TLO.Me.Class.ShortName() ~= 'BRD' then return nil, nil end
    local entry = botconfig.getSpellEntry('debuff', spellIndex)
    if not entry or entry.enabled == false then return nil, nil end
    local gem = entry.gem
    if type(gem) ~= 'number' or gem < 1 or gem > 12 then return nil, nil end
    if spellutils.IsMezSpell(entry) then return nil, nil end
    local db = DebuffBands[spellIndex]
    if not db or not db.matar then return nil, nil end
    return entry, db
end

--- True when a bard matar debuff has stopWhen (sing-until; combat twist, not twist-once).
function botdebuff.BardMatarDebuffHasStopWhen(spellIndex)
    local entry = bardMatarDebuffEntry(spellIndex)
    return entry and entry.stopWhen and #entry.stopWhen > 0 or false
end

--- True when a bard matar debuff uses twist-once (dontStack, precondition, restrictive HP).
--- stopWhen alone uses sustained combat twist instead.
function botdebuff.BardMatarDebuffUsesTwistOnce(spellIndex)
    local entry, db = bardMatarDebuffEntry(spellIndex)
    if not entry then return false end
    if type(entry.precondition) == 'string' then
        local pre = entry.precondition:match('^%s*(.-)%s*$') or entry.precondition
        if pre ~= '' and pre ~= 'true' then return true end
    end
    if entry.dontStack and #entry.dontStack > 0 then return true end
    local assistpct = (botconfig.config.melee and botconfig.config.melee.assistpct) or 99
    local mobMax = db.mobMax or 100
    if mobMax < 100 and mobMax ~= assistpct then return true end
    return false
end

--- True when a bard matar debuff is conditional (twist-once or stopWhen combat twist).
function botdebuff.BardMatarDebuffIsConditional(spellIndex)
    return botdebuff.BardMatarDebuffUsesTwistOnce(spellIndex)
        or botdebuff.BardMatarDebuffHasStopWhen(spellIndex)
end

--- True when a bard matar debuff gem belongs in the combat twist for maTargetId (or nil MA).
function botdebuff.BardMatarDebuffInCombatTwist(spellIndex, maTargetId)
    if botdebuff.BardMatarDebuffUsesTwistOnce(spellIndex) then return false end
    local entry = bardMatarDebuffEntry(spellIndex)
    if not entry then return false end
    if entry.stopWhen and #entry.stopWhen > 0 and maTargetId then
        if spellutils.SpawnHasStopWhenCategory(maTargetId, entry.stopWhen) then
            return false
        end
    end
    return true
end

--- True when a conditional matar debuff should be sung via twist-once (or cast via doDebuff).
function botdebuff.MatarDebuffNeededForTwist(index)
    if not botdebuff.BardMatarDebuffUsesTwistOnce(index) then return false end
    local entry = botconfig.getSpellEntry('debuff', index)
    if not entry or entry.enabled == false then return false end
    if spellutils.IsMezSpell(entry) then return false end
    local db = DebuffBands[index]
    if not db or not db.matar then
        if not (db and db.burn and not db.notmatar and not db.named) then return false end
    end
    if db.burn then return false end
    if not onlyMTDebuffAllowed(entry) then return false end
    local ctx = DebuffEvalBuildContext(index)
    if not ctx then return false end
    local chosenTargetId = getMatarChosenTargetId(entry, ctx)
    if not chosenTargetId then return false end
    if not spawnutils.isAliveEngageSpawn(mq.TLO.Spawn(chosenTargetId)) then return false end
    if not castutils.hpEvalSpawn(chosenTargetId, { min = db.mobMin, max = db.mobMax }) then return false end
    local spawn = debuffMatarSpawnForTarget(chosenTargetId, ctx)
    if not spawn then return false end
    if not DebuffSpawnNeedsSpell(entry, ctx, spawn, 'matar') then return false end
    return spellutils.PreCondCheck('debuff', index, chosenTargetId)
end

local function DebuffEvalMatar(index, ctx)
    local entry = ctx.entry
    local db = DebuffBands[index]
    if not db or not db.matar then
        if not (db.burn and not db.notmatar and not db.named) then return nil, nil end
    end
    if spellutils.IsMezSpell(entry) then return nil, nil end

    -- `matar` phase provides both MA and MT candidate targets.
    -- For `onlyMT` debuffs we cast on MT's target (or OT engage target when actively off-tanking).
    if not onlyMTDebuffAllowed(entry) then return nil, nil end
    local chosenTargetId = getMatarChosenTargetId(entry, ctx)
    if not chosenTargetId then return nil, nil end
    if not spawnutils.isAliveEngageSpawn(mq.TLO.Spawn(chosenTargetId)) then return nil, nil end

    if not castutils.hpEvalSpawn(chosenTargetId, { min = db.mobMin, max = db.mobMax }) then return nil, nil end
    local spawn = debuffMatarSpawnForTarget(chosenTargetId, ctx)
    if spawn and DebuffSpawnNeedsSpell(entry, ctx, spawn, 'matar') then
        return chosenTargetId, 'matar'
    end
    return nil, nil
end

local function DebuffEvalNotmatar(index, ctx)
    local entry = ctx.entry
    local db = DebuffBands[index]
    if not db or not db.notmatar or not ctx.mobList[1] then return nil, nil end
    local maTargetId = ctx.maTargetId
    for _, v in ipairs(ctx.mobList) do
        local vid = v.ID and v.ID() or nil
        if vid and vid ~= maTargetId then
            if charm.isCharmSkipped(vid, state.getRunconfig()) then
                -- skip: charmed pet or post-charm hold
            elseif castutils.hpEvalSpawn(v, { min = db.mobMin, max = db.mobMax }) then
                if DebuffSpawnNeedsSpell(entry, ctx, v, 'notmatar') then
                    return v.ID(), 'notmatar'
                end
            elseif spellutils.IsMezSpell(entry) then
                local name = (v.CleanName and v.CleanName()) or ('id ' .. tostring(vid))
                spellutils.DbgMezTrace('skip %s (id %s) - hp band', name, vid)
            end
        end
    end
    return nil, nil
end

local function DebuffEvalNamedMatar(index, ctx)
    local entry = ctx.entry
    local db = DebuffBands[index]
    if not db or not db.named then return nil, nil end
    if spellutils.IsMezSpell(entry) then return nil, nil end

    if not onlyMTDebuffAllowed(entry) then return nil, nil end
    local chosenTargetId = getMatarChosenTargetId(entry, ctx)
    if not chosenTargetId then return nil, nil end

    if not castutils.hpEvalSpawn(chosenTargetId, { min = db.mobMin, max = db.mobMax }) then return nil, nil end
    local spawn = debuffMatarSpawnForTarget(chosenTargetId, ctx)
    if spawn and spawn.Named() and DebuffSpawnNeedsSpell(entry, ctx, spawn, 'matar') then
        return chosenTargetId, 'matar'
    end
    return nil, nil
end

local function DebuffEval(index)
    local entry = botconfig.getSpellEntry('debuff', index)
    if not entry then return nil, nil end
    local db = DebuffBands[index]
    if not campCountOk(state.getMobCount(), db and db.mintar, db and db.maxtar) then return nil, nil end
    if not aggro.inBand(db and db.aggroMin, db and db.aggroMax) then return nil, nil end
    local id, hit = charm.GetRecastRequestForIndex(index)
    if id then
        charm.ClearRecastRequest()
        return id, hit
    end
    local ctx = DebuffEvalBuildContext(index)
    if not ctx then return nil, nil end
    id, hit = charm.EvalTarget(index, ctx)
    if id then return id, hit end
    id, hit = DebuffEvalMatar(index, ctx)
    if id then return id, hit end
    id, hit = DebuffEvalNotmatar(index, ctx)
    if id then return id, hit end
    id, hit = DebuffEvalNamedMatar(index, ctx)
    if id then return id, hit end
    return nil, nil
end

local DEBUFF_PHASE_ORDER = { 'charm', 'burn', 'notmatar', 'matar', 'named' }

--- Cache notmatar SpawnNeedsDebuff results for this DebuffCheck pass (spellIndex -> spawnId -> bool).
local function notmatarNeedCached(context, spellIndex, sctx, spawn)
    local vid = spawn and spawn.ID and spawn.ID() or nil
    if not vid or not sctx then return false end
    context.notmatarNeedCache = context.notmatarNeedCache or {}
    local bySpell = context.notmatarNeedCache[spellIndex]
    if not bySpell then
        bySpell = {}
        context.notmatarNeedCache[spellIndex] = bySpell
    end
    local cached = bySpell[vid]
    if cached ~= nil then return cached end
    local db = DebuffBands[spellIndex]
    local need = false
    if not charm.isCharmSkipped(vid, state.getRunconfig())
        and castutils.hpEvalSpawn(spawn, { min = db.mobMin, max = db.mobMax })
        and DebuffSpawnNeedsSpell(sctx.entry, sctx, spawn, 'notmatar') then
        need = true
    end
    bySpell[vid] = need
    return need
end

--- Pass-local CheckGemReadiness (once per spell index per DebuffCheck).
local function debuffGemReady(context, spellIndex, entry)
    if not context then
        return spellutils.CheckGemReadiness('debuff', spellIndex, entry)
    end
    context.gemReadyCache = context.gemReadyCache or {}
    local cached = context.gemReadyCache[spellIndex]
    if cached ~= nil then return cached end
    cached = spellutils.CheckGemReadiness('debuff', spellIndex, entry) and true or false
    context.gemReadyCache[spellIndex] = cached
    return cached
end

--- Pass-local matar/named need cache (spellIndex -> spawnId -> bool).
local function matarNeedCached(context, spellIndex, spawnId, computeFn)
    if not context or not spawnId then return computeFn() end
    context.matarNeedCache = context.matarNeedCache or {}
    local bySpell = context.matarNeedCache[spellIndex]
    if not bySpell then
        bySpell = {}
        context.matarNeedCache[spellIndex] = bySpell
    end
    local cached = bySpell[spawnId]
    if cached ~= nil then return cached end
    cached = computeFn() and true or false
    bySpell[spawnId] = cached
    return cached
end

local function debuffGetTargetsForPhase(phase, context)
    local out = {}
    local mobList = context.mobList or state.getRunconfig().MobList or {}
    if phase == 'charm' then
        if context.charmRecasts then
            for _, v in pairs(context.charmRecasts) do
                if v and v.id then out[#out + 1] = { id = v.id, targethit = v.targethit or 'charmtar' } end
            end
        end
        if not _hasCharmSpell then return out end
        local count = context.debuffCount or botconfig.getSpellCount('debuff')
        for i = 1, count do
            local entry = botconfig.getSpellEntry('debuff', i)
            if entry and spellutils.IsCharmSpell(entry) then
                local dctx = spellCtxFor(context, i)
                if dctx then
                    local id, hit = charm.EvalTarget(i, dctx)
                    if id then out[#out + 1] = { id = id, targethit = hit or 'charmtar' } end
                end
            end
        end
        return out
    end
    if phase == 'burn' then
        if not state.IsBurnActive() then return out end
        local spellCount = context.debuffCount or botconfig.getSpellCount('debuff')
        local maTargetId = context.maTargetId
        local mtTargetId = context.mtTargetId
        local wantMatar, wantNotmatar, wantNamed = false, false, false
        for si = 1, spellCount do
            local db = DebuffBands[si]
            if db and db.burn then
                if db.matar or db.named or (not db.notmatar and not db.named) then wantMatar = true end
                if db.notmatar then wantNotmatar = true end
                if db.named then wantNamed = true end
            end
        end
        if wantMatar or wantNamed then
            if maTargetId and maTargetId > 0 then
                if wantNamed then
                    local sp = mq.TLO.Spawn(maTargetId)
                    if sp and sp.Named() then out[#out + 1] = { id = maTargetId, targethit = 'named' } end
                else
                    out[#out + 1] = { id = maTargetId, targethit = 'matar' }
                end
                if mtTargetId and mtTargetId > 0 and mtTargetId ~= maTargetId then
                    if wantNamed then
                        local sp = mq.TLO.Spawn(mtTargetId)
                        if sp and sp.Named() then out[#out + 1] = { id = mtTargetId, targethit = 'named' } end
                    else
                        out[#out + 1] = { id = mtTargetId, targethit = 'matar' }
                    end
                end
            end
        end
        if wantNotmatar then
            local seen = {}
            for si = 1, spellCount do
                local db = DebuffBands[si]
                if db and db.burn and db.notmatar then
                    local sctx = spellCtxFor(context, si)
                    if sctx then
                        for _, v in ipairs(mobList) do
                            local vid = v.ID and v.ID() or nil
                            if vid and vid ~= maTargetId and notmatarNeedCached(context, si, sctx, v) then
                                if not seen[vid] then
                                    seen[vid] = true
                                    out[#out + 1] = { id = vid, targethit = 'notmatar' }
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
        return out
    end
    local maTargetId = context.maTargetId
    local mtTargetId = context.mtTargetId
    if phase == 'matar' then
        -- Suspend matar/named entirely when MA has no live target.
        if not maTargetId or maTargetId <= 0 then return out end
        if spawnutils.isAliveEngageSpawn(mq.TLO.Spawn(maTargetId)) then
            out[#out + 1] = { id = maTargetId, targethit = 'matar' }
        end
        if mtTargetId and mtTargetId > 0 and mtTargetId ~= maTargetId
            and spawnutils.isAliveEngageSpawn(mq.TLO.Spawn(mtTargetId)) then
            out[#out + 1] = { id = mtTargetId, targethit = 'matar' }
        end
        return out
    end
    if phase == 'notmatar' then
        if not _hasNotmatarBand then return out end
        -- Discover + cache need per spell×spawn for scanned pairs; needsSpell prefers cache.
        local seen = {}
        local spellCount = context.debuffCount or botconfig.getSpellCount('debuff')
        for si = 1, spellCount do
            local db = DebuffBands[si]
            if db and db.notmatar then
                local sctx = spellCtxFor(context, si)
                if sctx then
                    for _, v in ipairs(mobList) do
                        local vid = v.ID and v.ID() or nil
                        if vid and vid ~= maTargetId and notmatarNeedCached(context, si, sctx, v) then
                            if not seen[vid] then
                                seen[vid] = true
                                out[#out + 1] = { id = vid, targethit = 'notmatar' }
                            end
                            break
                        end
                    end
                end
            end
        end
        if #out > 0 and spellutils.IsMezDebug() then
            local parts = {}
            for i, t in ipairs(out) do
                local sp = mq.TLO.Spawn(t.id)
                local name = (sp and sp.CleanName and sp.CleanName()) or tostring(t.id)
                parts[i] = string.format('%s(%s)', name, t.id)
            end
            spellutils.MezLog('notmatar targets this tick: %s', table.concat(parts, ', '))
        end
        return out
    end
    if phase == 'named' then
        -- Suspend named entirely when MA has no target.
        if not maTargetId or maTargetId <= 0 then return out end
        local ids = { maTargetId }
        if mtTargetId and mtTargetId > 0 and mtTargetId ~= maTargetId then ids[#ids + 1] = mtTargetId end
        for _, id in ipairs(ids) do
            local sp = mq.TLO.Spawn(id)
            if sp and sp.ID() == id and sp.Named() then out[#out + 1] = { id = id, targethit = 'named' } end
        end
        return out
    end
    return out
end

local function nukeFlavorAllowed(rc, flavor)
    if not flavor then return true end
    if rc.nukeFlavorsAutoDisabled and rc.nukeFlavorsAutoDisabled[flavor] then return false end
    if not rc.nukeFlavorsAllowed then return true end
    return rc.nukeFlavorsAllowed[flavor] == true
end

local function debuffTargetNeedsSpell(spellIndex, targetId, targethit, context)
    local entry = botconfig.getSpellEntry('debuff', spellIndex)
    if not entry then return nil, nil end
    local db = DebuffBands[spellIndex]
    if not campCountOk(state.getMobCount(), db and db.mintar, db and db.maxtar) then
        return nil, nil
    end
    if not aggro.inBand(db and db.aggroMin, db and db.aggroMax) then
        return nil, nil
    end
    local rc = state.getRunconfig()
    if spellutils.IsNukeSpell(entry) and not spellutils.IsConcussionSpell(entry) then
        local flavor = spellutils.GetNukeFlavor(entry)
        if not nukeFlavorAllowed(rc, flavor) then return nil, nil end
    end
    if targethit == 'charmtar' or targethit == 'charm' then
        if context.charmRecasts and context.charmRecasts[spellIndex] and context.charmRecasts[spellIndex].id == targetId then
            return targetId, context.charmRecasts[spellIndex].targethit or 'charmtar'
        end
        local ctx = spellCtxFor(context, spellIndex)
        if ctx then
            local id, hit = charm.EvalTarget(spellIndex, ctx)
            if id == targetId then return id, hit or 'charmtar' end
        end
        return nil, nil
    end
    local ctx = spellCtxFor(context, spellIndex)
    if not ctx then return nil, nil end
    if targethit == 'matar' then
        if not debuffGemReady(context, spellIndex, entry) then return nil, nil end
        if not onlyMTDebuffAllowed(entry) then return nil, nil end
        -- DebuffList-first: skip full EvalMatar when we already track a long-enough duration.
        if not entry.recastActive and ctx.spellid
            and spellstates.HasDebuffLongerThan(targetId, ctx.spellid, spellutils.GetDebuffRefreshThresholdMs()) then
            return nil, nil
        end
        local need = matarNeedCached(context, spellIndex, targetId, function()
            local id = DebuffEvalMatar(spellIndex, ctx)
            if id == targetId then return true end
            -- Burn-only on MA target (no matar flag on band).
            if db and db.burn and not db.matar and not db.notmatar and not db.named and state.IsBurnActive() then
                local chosenTargetId = getMatarChosenTargetId(entry, ctx)
                if chosenTargetId == targetId and castutils.hpEvalSpawn(targetId, { min = db.mobMin, max = db.mobMax }) then
                    local spawn = debuffMatarSpawnForTarget(targetId, ctx)
                    if spawn and DebuffSpawnNeedsSpell(entry, ctx, spawn, 'matar') then
                        return true
                    end
                end
            end
            return false
        end)
        if need then return targetId, 'matar' end
        return nil, nil
    end
    if targethit == 'named' then
        if not debuffGemReady(context, spellIndex, entry) then return nil, nil end
        if not onlyMTDebuffAllowed(entry) then return nil, nil end
        if not entry.recastActive and ctx.spellid
            and spellstates.HasDebuffLongerThan(targetId, ctx.spellid, spellutils.GetDebuffRefreshThresholdMs()) then
            return nil, nil
        end
        local need = matarNeedCached(context, spellIndex, targetId, function()
            local id = DebuffEvalNamedMatar(spellIndex, ctx)
            return id == targetId
        end)
        if need then return targetId, 'matar' end
        return nil, nil
    end
    if targethit == 'notmatar' then
        if not db or not db.notmatar then return nil, nil end
        local cache = context.notmatarNeedCache and context.notmatarNeedCache[spellIndex]
        if cache and cache[targetId] ~= nil then
            if cache[targetId] then return targetId, 'notmatar' end
            return nil, nil
        end
        for _, v in ipairs(ctx.mobList) do
            local vid = v.ID and v.ID() or v
            if vid == targetId then
                if castutils.hpEvalSpawn(v, { min = db.mobMin, max = db.mobMax })
                    and DebuffSpawnNeedsSpell(ctx.entry, ctx, v, 'notmatar') then
                    return targetId, 'notmatar'
                end
                break
            end
        end
    end
    return nil, nil
end

--- Same assistpct / MobList gate as resolveMeleeAssistTarget for setting engageTargetId.
local function matarTargetPassesAssistEngageGate(evalId, rc)
    return botmelee.matarTargetPassesAssistEngageGate(evalId, rc)
end

local function DebuffOnBeforeCast(i, EvalID, targethit)
    local myconfig = botconfig.config
    local entry = botconfig.getSpellEntry('debuff', i)
    if not entry then return false end
    if EvalID and utils.isProtectedSpawn(mq.TLO.Spawn(EvalID)) then return false end
    if EvalID and not spawnutils.isAliveEngageSpawn(mq.TLO.Spawn(EvalID)) then return false end
    -- Reactive mode (settings.engageXTargetOnly, opt-in): only debuff/mez/nuke mobs on our XTarget
    -- Auto-Hater list (aggro'd on the group). Stops the bot casting on -- and thereby aggroing -- unwanted
    -- MobList NPCs (e.g. an enchanter slowing/mezzing a mob nobody is fighting). /cz attack bypasses it.
    if myconfig.settings.engageXTargetOnly == true and not state.getRunconfig().attackCommandEngage
        and EvalID and EvalID > 0 and not require('lib.spawnutils').isOnXTargetAutoHater(EvalID) then
        return false
    end
    if not spellutils.CheckGemReadiness('debuff', i, entry) then return false end
    if not spellutils.IsConcussionSpell(entry) and entry.recast ~= nil and entry.recast > 0 and spellstates.GetRecastCounter(EvalID, i) >= entry.recast then
        return false
    end
    charm.BeforeCast(EvalID, targethit)
    if targethit == 'matar' and EvalID and EvalID > 0 then
        local rc = state.getRunconfig()
        local desiredPetTargetId = EvalID
        if tankrole.AmIMainTank() and myconfig.melee['mtSticky'] == true and not myconfig.melee.offtank
            and not tankrole.AmIMainAssist() then
            -- Sticky MT: keep melee/pets on MT target even if the matar debuff is aimed at MA target.
            local _, _, mtTargetId = spellutils.GetTankInfo(true)
            if mtTargetId and mtTargetId ~= 0 then
                desiredPetTargetId = mtTargetId
                if matarTargetPassesAssistEngageGate(mtTargetId, rc) then
                    rc.engageTargetId = mtTargetId
                    botmelee.armMobprobEngageGrace(mtTargetId)
                end
            elseif matarTargetPassesAssistEngageGate(EvalID, rc) then
                rc.engageTargetId = EvalID
                botmelee.armMobprobEngageGrace(EvalID)
            end
        elseif not myconfig.melee.offtank and matarTargetPassesAssistEngageGate(EvalID, rc) then
            rc.engageTargetId = EvalID
            botmelee.armMobprobEngageGrace(EvalID)
        end

        if desiredPetTargetId and mq.TLO.Pet.Target.ID() ~= desiredPetTargetId and not mq.TLO.Me.Pet.Combat() then
            mq.cmdf('/pet attack %s', desiredPetTargetId)
        end
    end
    return true
end

--- Re-target MA/camp after bard notmatar mez and restore stick/attack (botmelee owns the path).
local function retargetMaTargetAfterBardMez(excludeId)
    return botmelee.retargetAndEngageAfterBardMez(excludeId)
end

local function updateBardTwistOnceDebuffState(entry, evalId)
    if not entry or not evalId then return end
    local durationSec = spellutils.GetSpellDurationSec(entry)
    if durationSec > 0 then
        local myduration = durationSec * 1000 + mq.gettime()
        if spellutils.IsMezSpell(entry) then
            local remMs = spellutils.SpawnEnthrallRemainingMs(evalId)
            if remMs > 0 then
                myduration = mq.gettime() + remMs
            end
        end
        spellstates.DebuffListUpdate(evalId, entry.spell, myduration)
    elseif durationSec == 0 then
        spellstates.DebuffListUpdate(evalId, entry.spell, mq.gettime() + 12 * 1000)
    end
end

local MEZ_TWIST_ONCE_MAX_FAILS = 2
local MEZ_TWIST_FAIL_SKIP_MS = 30000
local BARD_TWIST_ONCE_ABSOLUTE_MAX_MS = 8000

local function getMezTwistFailCounts(rc)
    if not rc.mezTwistFailCounts then rc.mezTwistFailCounts = {} end
    return rc.mezTwistFailCounts
end

local function clearMezTwistFailCount(rc, spawnId)
    if not spawnId or not rc.mezTwistFailCounts then return end
    rc.mezTwistFailCounts[spawnId] = nil
end

local function clearMezTwistFailSkip(rc, spawnId)
    if not spawnId or not rc.mezTwistFailSkipUntil then return end
    rc.mezTwistFailSkipUntil[spawnId] = nil
end

local function clearMezTwistFailState(rc, spawnId)
    clearMezTwistFailCount(rc, spawnId)
    clearMezTwistFailSkip(rc, spawnId)
end

local function incrementMezTwistFailCount(rc, spawnId)
    if not spawnId or spawnId <= 0 then return 0 end
    local counts = getMezTwistFailCounts(rc)
    local current = counts[spawnId] or 0
    if current >= MEZ_TWIST_ONCE_MAX_FAILS then return current end
    counts[spawnId] = current + 1
    return counts[spawnId]
end

local function applyMezTwistFailSkip(rc, spawnId)
    if not spawnId or spawnId <= 0 then return end
    if not rc.mezTwistFailSkipUntil then rc.mezTwistFailSkipUntil = {} end
    rc.mezTwistFailSkipUntil[spawnId] = mq.gettime() + MEZ_TWIST_FAIL_SKIP_MS
end

--- True when twist-once mez actually landed (not a missed note / aborted song).
local function mezTwistOnceLanded(rc, evalId, entry)
    if rc.MissedNote then return false end
    if not evalId or evalId <= 0 then return false end
    if not spawnutils.isAliveEngageSpawn(mq.TLO.Spawn(evalId)) then return false end
    if entry and entry.spell and spellutils.SpawnHasDebuffSpell(entry.spell, evalId) then
        return true
    end
    local remMs = spellutils.SpawnEnthrallRemainingMs(evalId)
    if remMs > spellutils.GetDebuffRefreshThresholdMs() then return true end
    if remMs > 0 then return true end
    local sp = mq.TLO.Spawn(evalId)
    if sp and sp.ID() == evalId then
        local ok, mezzed = pcall(function() return sp.Mezzed and sp.Mezzed() end)
        if ok and mezzed == true then return true end
    end
    if mq.TLO.Target.ID() == evalId and mq.TLO.Target.Mezzed() then return true end
    return false
end

local function handleNotmatarMezTwistOnceOutcome(rc, w, attemptedCast)
    if w.targethit ~= 'notmatar' or not w.entry or not spellutils.IsMezSpell(w.entry) then return end
    local evalId = w.EvalID
    if mezTwistOnceLanded(rc, evalId, w.entry) then
        updateBardTwistOnceDebuffState(w.entry, evalId)
        clearMezTwistFailState(rc, evalId)
        spellutils.MezLog('twist-once mez landed on id %s', tostring(evalId))
    elseif attemptedCast then
        local fails = incrementMezTwistFailCount(rc, evalId)
        spellutils.MezLog('twist-once mez missed on id %s (fail %d/%d)', tostring(evalId), fails, MEZ_TWIST_ONCE_MAX_FAILS)
        if fails >= MEZ_TWIST_ONCE_MAX_FAILS and not spellutils.IsMezTwistFailSkipped(evalId, rc) then
            applyMezTwistFailSkip(rc, evalId)
            log.say('[Mez] giving up on \at%s\ax (id %s) after %d failed twist-once attempts',
                (mq.TLO.Spawn(evalId) and mq.TLO.Spawn(evalId).CleanName()) or '?', evalId, fails)
        end
    end
    rc.MissedNote = false
end

--- True when a BRD twist-once wait should abort (target died, left camp, or fight ended).
local function bardTwistOnceShouldAbort(w, rc)
    if state.getRunState() == state.STATES.camp_return then return true end
    local evalId = w.EvalID
    if not evalId or evalId <= 0 then return true end
    if not spawnutils.isAliveEngageSpawn(mq.TLO.Spawn(evalId)) then return true end
    if w.targethit == 'matar' then
        if state.getMobCount() <= 0 then return true end
        local found = false
        for _, v in ipairs(rc.MobList or {}) do
            if v.ID() == evalId then
                found = true
                break
            end
        end
        if not found then return true end
    end
    if w.targethit == 'notmatar' then
        local found = false
        for _, v in ipairs(rc.MobList or {}) do
            if v.ID() == evalId then
                found = true
                break
            end
        end
        if not found then return true end
    end
    return false
end

local function finishBardTwistOnceWait(rc, w, opts)
    opts = opts or {}
    local attemptedCast = opts.attemptedCast == true
    if opts.stopTwist then
        bardtwist.StopTwist()
    end
    rc.bardTwistOnceWait = nil
    state.clearRunState()
    if w.targethit == 'notmatar' and w.entry and spellutils.IsMezSpell(w.entry) then
        handleNotmatarMezTwistOnceOutcome(rc, w, attemptedCast)
    elseif opts.recordDebuff and w.singingStarted and spawnutils.isAliveEngageSpawn(mq.TLO.Spawn(w.EvalID)) then
        updateBardTwistOnceDebuffState(w.entry, w.EvalID)
    end
    if w.targethit == 'notmatar' then
        if w.EvalID and (rc.engageTargetId == w.EvalID or not spawnutils.isAliveEngageSpawn(mq.TLO.Spawn(w.EvalID))) then
            rc.engageTargetId = nil
            if rc.lastAssistTargetId == w.EvalID then
                rc.lastAssistTargetId = nil
            end
            if w.EvalID and not spawnutils.isAliveEngageSpawn(mq.TLO.Spawn(w.EvalID)) then
                clearMezTwistFailState(rc, w.EvalID)
            end
        end
    elseif w.targethit == 'matar' and w.EvalID and not spawnutils.isAliveEngageSpawn(mq.TLO.Spawn(w.EvalID)) then
        rc.engageTargetId = nil
        if rc.lastAssistTargetId == w.EvalID then
            rc.lastAssistTargetId = nil
        end
    end
    if state.getMobCount() <= 0 then
        rc.engageTargetId = nil
        rc.attackCommandEngage = nil
        rc.lastAssistTargetId = nil
    end
    if w.targethit == 'notmatar' then
        retargetMaTargetAfterBardMez(w.EvalID)
    end
    -- Only camp-empty ends the fight; mez-target death must not ResetCombatState mid-pull.
    local fightEnded = state.getMobCount() <= 0
    if fightEnded then
        combat.ResetCombatState()
    end
    botmelee.syncEngageStatusMessage(rc)
    local mode = bardtwist.GetCurrentTwistMode()
    local currentListRaw = mq.TLO.Twist() and mq.TLO.Twist.List()
    local currentGems = currentListRaw and tostring(currentListRaw) or '(none)'
    local desiredGems = mode and bardtwist.GetTwistListForMode(mode) or {}
    local desiredStr = (#desiredGems > 0) and table.concat(desiredGems, ' ') or '(none)'
    bardtwist.BardDbgNow(
        'twist-once done: evalId=%s fightEnded=%s mobs=%d engageId=%s runState=%s mode=%s current=[%s] desired=[%s]',
        tostring(w.EvalID), tostring(fightEnded), state.getMobCount(), tostring(rc.engageTargetId),
        state.getRunStateName(), tostring(mode), currentGems, desiredStr)
    bardtwist.RestoreCombatTwistAfterTwistOnce()
end

local BARD_TWIST_ONCE_HARD_CAP_MS = 2000

local function finishTwistOnceWaitWithReason(rc, w, reason, opts)
    opts = opts or {}
    spellutils.MezLog('twist-once wait finish: reason=%s evalId=%s gem=%s',
        tostring(reason), tostring(w.EvalID), tostring(w.entry and w.entry.gem))
    finishBardTwistOnceWait(rc, w, opts)
end

--- BRD twist-once wait: wait for song, update debuff state, re-target if needed, resume twist for current mode.
local function DebuffCheckHandleBardTwistOnceWait(rc)
    if mq.TLO.Me.Class.ShortName() ~= 'BRD' or not rc.bardTwistOnceWait then
        return false
    end
    local w = rc.bardTwistOnceWait
    if not w or not w.entry or not w.EvalID then
        bardtwist.StopTwist()
        rc.bardTwistOnceWait = nil
        state.clearRunState()
        botmelee.syncEngageStatusMessage(rc)
        return false
    end

    local mode = bardtwist.GetCurrentTwistMode()
    if mode then bardtwist.ReconcileTwistOnceActive(mode) end

    if bardTwistOnceShouldAbort(w, rc) then
        local stillSinging = mq.TLO.Me.Casting() or (mq.TLO.Me.CastTimeLeft() or 0) > 0
        if stillSinging then w.singingStarted = true end
        finishTwistOnceWaitWithReason(rc, w, 'abort', {
            stopTwist = bardtwist.IsTwistOnceActive() or stillSinging,
            attemptedCast = w.singingStarted == true,
        })
        return true
    end

    local now = mq.gettime()
    if w.startedAt and now > w.startedAt + BARD_TWIST_ONCE_ABSOLUTE_MAX_MS then
        finishTwistOnceWaitWithReason(rc, w, 'absolute_max', {
            stopTwist = bardtwist.IsTwistOnceActive(),
            attemptedCast = w.singingStarted == true,
        })
        return true
    end

    local onceGem = w.entry.gem
    local onceListActive = type(onceGem) == 'number' and bardtwist.IsTwistListSolelyGem(onceGem)
    local stillSinging = mq.TLO.Me.Casting() or (mq.TLO.Me.CastTimeLeft() or 0) > 0

    if onceListActive then
        w.onceListSeen = true
    end

    -- MQ2Twist cleared altTwist: List is no longer solely the once gem (only after we saw it).
    if type(onceGem) == 'number' and not onceListActive and w.onceListSeen then
        finishTwistOnceWaitWithReason(rc, w, 'once_list_cleared', {
            attemptedCast = w.singingStarted == true or stillSinging,
            recordDebuff = (w.singingStarted or stillSinging)
                and spawnutils.isAliveEngageSpawn(mq.TLO.Spawn(w.EvalID)),
        })
        return true
    end

    -- Only prolong while MQ2Twist still has the once list; combat-twist casting must not block finish.
    if onceListActive and stillSinging then
        w.singingStarted = true
        return true
    end

    if bardtwist.IsTwistOnceActive() then
        w.singingStarted = true
        local pastDeadline = w.deadline and now >= w.deadline
        local pastHardCap = w.deadline and now > w.deadline + BARD_TWIST_ONCE_HARD_CAP_MS
        local twistOnceAt = bardtwist.GetLastTwistOnceAt()
        local castMs = w.castTimeMs or 3000
        local pastTwistOnceWindow = twistOnceAt > 0 and now > twistOnceAt + castMs + 200
        if not pastDeadline and not pastHardCap and not pastTwistOnceWindow then
            return true
        end
        finishTwistOnceWaitWithReason(rc, w, 'twist_once_window', {
            attemptedCast = true,
            recordDebuff = spawnutils.isAliveEngageSpawn(mq.TLO.Spawn(w.EvalID)),
        })
        return true
    elseif not w.singingStarted and w.deadline and now < w.deadline then
        return true
    end

    local attemptedCast = w.singingStarted == true
    finishTwistOnceWaitWithReason(rc, w, 'complete', {
        attemptedCast = attemptedCast,
        recordDebuff = attemptedCast and spawnutils.isAliveEngageSpawn(mq.TLO.Spawn(w.EvalID)),
    })
    return true
end

--- Tick BRD twist-once wait (finish/abort). Safe to call every tick regardless of MobList.
function botdebuff.TickBardTwistOnceWait(rc)
    return DebuffCheckHandleBardTwistOnceWait(rc or state.getRunconfig())
end

--- Twist-once bard debuff on a single target (conditional matar, notmatar mez, CH/Gate interrupt).
---@param targethit string 'matar' | 'notmatar'
---@param reason string|nil When set, logs as interrupt (e.g. 'Complete Heal/Gate') instead of add mez.
function botdebuff.CastBardDebuffTwistOnce(spellIndex, EvalID, targethit, runPriority, reason)
    if mq.TLO.Me.Class.ShortName() ~= 'BRD' then return false end
    if not EvalID or EvalID <= 0 or not spawnutils.isAliveEngageSpawn(mq.TLO.Spawn(EvalID)) then
        return true
    end
    if state.getRunState() == state.STATES.camp_return then
        return true
    end
    local rc = state.getRunconfig()
    local entry = botconfig.getSpellEntry('debuff', spellIndex)
    if not entry or type(entry.gem) ~= 'number' then return false end
    local spellName = entry.spell or ('gem' .. tostring(entry.gem))
    local targetName = (mq.TLO.Spawn(EvalID) and mq.TLO.Spawn(EvalID).CleanName()) or tostring(EvalID)
    if targethit == 'notmatar' then
        if spellutils.IsMezTwistFailSkipped(EvalID, rc) then
            return true
        end
        local function skipAlreadyMezzed()
            log.say('[Mez] skipping \at%s\ax (id %s) - already mezzed by another player (detected before cast)', targetName, EvalID)
            spellutils.RecordDontStackDebuffFromSpawn(EvalID, entry.spell, 'Mezzed')
            retargetMaTargetAfterBardMez(EvalID)
            bardtwist.RestoreCombatTwistAfterTwistOnce()
            return true
        end
        -- Spawn-side already blocks remes: skip without retargeting (avoids steal/idle loop).
        if spellutils.SpawnMezBlocksDontStack(EvalID) then
            return skipAlreadyMezzed()
        end
        targeting.TargetAndWaitBuffsPopulated(EvalID, 1000)
        if mq.TLO.Target.ID() == EvalID and mq.TLO.Target.Mezzed() then
            local remMs = spellutils.SpawnEnthrallRemainingMs(EvalID)
            local threshold = spellutils.GetDebuffRefreshThresholdMs()
            local inRemesWindow = remMs > 0 and remMs <= threshold
            if not inRemesWindow then
                return skipAlreadyMezzed()
            end
        end
        mq.cmd('/squelch /attack off')
        if reason and reason ~= '' then
            log.say('interrupting \ag%s\ax on \at%s\ax (%s)', spellName, targetName, reason)
        else
            log.say('[Mez] casting \am%s\ax on add \at%s\ax (id %s)', spellName, targetName, EvalID)
        end
    elseif targethit == 'matar' then
        if mq.TLO.Target.ID() ~= EvalID then
            targeting.TargetAndWait(EvalID, 500)
        end
        log.say('[Debuff] twist-once \am%s\ax on \at%s\ax (id %s)', spellName, targetName, EvalID)
    else
        return false
    end
    bardtwist.EnsureTwistForMode('combat')
    bardtwist.SetTwistOnceGem(entry.gem)
    local castTime = entry.spell and mq.TLO.Spell(entry.spell).MyCastTime()
    local castTimeMs = (castTime and castTime > 0) and castTime or 3000
    rc.bardTwistOnceWait = {
        spellIndex = spellIndex,
        EvalID = EvalID,
        entry = entry,
        targethit = targethit,
        singingStarted = false,
        castTimeMs = castTimeMs,
        deadline = mq.gettime() + castTimeMs + 100,
        startedAt = mq.gettime(),
    }
    if not state.canStartBusyState(state.STATES.casting) then
        rc.bardTwistOnceWait = nil
        return false
    end
    state.setRunState(state.STATES.casting, {
        deadline = mq.gettime() + 20000,
        priority = runPriority or bothooks.getPriority('doDebuff'),
    })
    return true
end

--- Twist-once bard mez (notmatar); used by CH/Gate interrupt.
function botdebuff.CastBardMezOnce(spellIndex, EvalID, runPriority, reason)
    return botdebuff.CastBardDebuffTwistOnce(spellIndex, EvalID, 'notmatar', runPriority, reason)
end

local function DebuffCheckBardTwistOnceCast(spellIndex, EvalID, targethit, sub, runPriority, _spellcheckResume)
    if sub ~= 'debuff' or mq.TLO.Me.Class.ShortName() ~= 'BRD' then return false end
    if targethit == 'notmatar' then
        return botdebuff.CastBardDebuffTwistOnce(spellIndex, EvalID, targethit, runPriority, nil)
    end
    if targethit == 'matar' then
        if botdebuff.BardMatarDebuffUsesTwistOnce(spellIndex) then
            return botdebuff.CastBardDebuffTwistOnce(spellIndex, EvalID, targethit, runPriority, nil)
        end
        -- Unconditional matar: sustained by combat twist, not a separate cast.
        return true
    end
    return false
end

local function DebuffEntryValid(i)
    local entry = botconfig.getSpellEntry('debuff', i)
    if not entry then return false end
    local gem = entry.gem
    return (entry.enabled ~= false) and ((type(gem) == 'number' and gem ~= 0) or type(gem) == 'string')
end

local function DebuffCheckAfterCast(spellIndex, EvalID, targethit, mobcountstart)
    if spellstates.GetDebuffDelay(spellIndex) and spellstates.GetDebuffDelay(spellIndex) > mq.gettime() then return false end
    if mobcountstart < state.getMobCount() then return false end
    local prevID = EvalID
    local newEvalID, newTargethit = DebuffEval(spellIndex)
    local adEntry = botconfig.getSpellEntry('debuff', spellIndex)
    if newEvalID and prevID == newEvalID and adEntry and (adEntry.recast or 0) > 0 and state.getRunconfig().CurSpell and state.getRunconfig().CurSpell.spell == spellIndex and state.getRunconfig().CurSpell.resisted then
        local newCount = spellstates.IncrementRecastCounter(EvalID, spellIndex)
        state.getRunconfig().CurSpell = {}
        if newCount >= adEntry.recast then
            local rc = state.getRunconfig()
            log.say('\ar%s\ax has resisted spell \ar%s\ax debuff[%s] \am%s\ax times, disabling spell for this spawn',
                mq.TLO.Spawn(EvalID).CleanName(), adEntry.spell, spellIndex, adEntry.recast)
            local recastduration = 600000 + mq.gettime()
            local duration_sec = spellutils.GetSpellDurationSec(adEntry)
            if duration_sec > 0 then spellstates.DebuffListUpdate(EvalID, adEntry.spell, recastduration) end
            if spellutils.IsNukeSpell(adEntry) then
                local flavor = spellutils.GetNukeFlavor(adEntry)
                if flavor then
                    if not rc.nukeResistDisabledRecent then rc.nukeResistDisabledRecent = {} end
                    rc.nukeResistDisabledRecent[#rc.nukeResistDisabledRecent + 1] = { flavor = flavor }
                    if #rc.nukeResistDisabledRecent > 5 then
                        table.remove(rc.nukeResistDisabledRecent, 1)
                    end
                    local n = #rc.nukeResistDisabledRecent
                    if n >= 3 then
                        local f = rc.nukeResistDisabledRecent[n].flavor
                        if rc.nukeResistDisabledRecent[n - 1].flavor == f and rc.nukeResistDisabledRecent[n - 2].flavor == f then
                            if not rc.nukeFlavorsAutoDisabled then rc.nukeFlavorsAutoDisabled = {} end
                            if not rc.nukeFlavorsAutoDisabled[f] then
                                rc.nukeFlavorsAutoDisabled[f] = true
                                log.say('\ar%s\ax nukes auto-disabled after resists on 3 mobs in a row.', f:gsub('^%l', string.upper))
                                botconfig.saveNukeFlavorsToCommon()
                            end
                        end
                    end
                end
            end
        end
        return true
    end
    return false
end

local function debuffGetSpellIndices(phase, count, ctx, target)
    if phase == 'charm' then
        local out = {}
        for i = 1, count do
            if ctx.charmRecasts[i] then out[#out + 1] = i end
        end
        if not _hasCharmSpell then return out end
        for i = 1, count do
            local entry = botconfig.getSpellEntry('debuff', i)
            if entry and spellutils.IsCharmSpell(entry) then
                local dctx = spellCtxFor(ctx, i)
                if dctx and charm.EvalTarget(i, dctx) then
                    local found = false
                    for _, si in ipairs(out) do
                        if si == i then
                            found = true
                            break
                        end
                    end
                    if not found then out[#out + 1] = i end
                end
            end
        end
        return out
    end
    local base = spellutils.getSpellIndicesForPhase(count, phase, DebuffBands)
    if base and #base > 0 and phase ~= 'burn' then
        local filtered = {}
        for _, i in ipairs(base) do
            if not (DebuffBands[i] and DebuffBands[i].burn) then
                filtered[#filtered + 1] = i
            end
        end
        base = filtered
    end
    if not base or #base == 0 then return base end
    local rc = state.getRunconfig()
    local nonNuke, nukeIndices = {}, {}
    for _, i in ipairs(base) do
        local entry = botconfig.getSpellEntry('debuff', i)
        if entry and spellutils.IsNukeSpell(entry) then
            local flavor = spellutils.GetNukeFlavor(entry)
            if nukeFlavorAllowed(rc, flavor) then nukeIndices[#nukeIndices + 1] = i end
        else
            nonNuke[#nonNuke + 1] = i end
    end
    if #nukeIndices == 0 then return nonNuke end
    local n = #nukeIndices
    local startPos = 1
    if rc.lastNukeIndex then
        for pos, spellIdx in ipairs(nukeIndices) do
            if spellIdx == rc.lastNukeIndex then
                startPos = (pos % n) + 1
                break
            end
        end
    end
    local rotated = {}
    for j = 0, n - 1 do
        rotated[#rotated + 1] = nukeIndices[((startPos - 1 + j) % n) + 1]
    end
    for _, i in ipairs(rotated) do nonNuke[#nonNuke + 1] = i end
    local fullBase = nonNuke
    if (phase == 'matar' or phase == 'named' or phase == 'burn') and target and target.id then
        local concussionIndex, concussionRecast = nil, nil
        for _, i in ipairs(fullBase) do
            local entry = botconfig.getSpellEntry('debuff', i)
            if entry and spellutils.IsConcussionSpell(entry) and (entry.recast or 0) > 0 then
                concussionIndex = i
                concussionRecast = entry.recast
                break
            end
        end
        if concussionIndex and concussionRecast then
            local c = spellstates.GetConcussionCounter(target.id)
            if c >= concussionRecast then
                return { concussionIndex }
            end
            local out = {}
            for _, i in ipairs(fullBase) do
                local entry = botconfig.getSpellEntry('debuff', i)
                if not entry or not spellutils.IsConcussionSpell(entry) or (entry.recast or 0) <= 0 then
                    out[#out + 1] = i
                end
            end
            return out
        end
    end
    return fullBase
end

--- Single place for debuff hook context:
--- MA/MT targets are computed here so `matar`/`notmatar`/`named` phase targeting can be decoupled.
local function debuffBuildContext(rc, maTargetId, mtTargetId)
    rc = rc or state.getRunconfig()
    local count = botconfig.getSpellCount('debuff')
    if maTargetId == nil then
        local _
        _, _, maTargetId = spellutils.GetAssistInfo(true)
    end
    if maTargetId == 0 then maTargetId = nil end
    if mtTargetId == nil then
        local _
        _, _, mtTargetId = spellutils.GetTankInfo(true)
    end
    if mtTargetId == 0 then mtTargetId = nil end
    local maTargetHp = maTargetId and mq.TLO.Spawn(maTargetId).PctHPs() or nil
    local mtTargetHp = mtTargetId and mq.TLO.Spawn(mtTargetId).PctHPs() or nil
    local maTargetLvl = maTargetId and mq.TLO.Spawn(maTargetId).Level() or nil
    local mtTargetLvl = mtTargetId and mq.TLO.Spawn(mtTargetId).Level() or nil
    local charmRecasts = {}
    for i = 1, count do
        local id, hit = charm.GetRecastRequestForIndex(i)
        if id then charmRecasts[i] = { id = id, targethit = hit or 'charmtar' } end
    end
    return {
        maTargetId = maTargetId,
        mtTargetId = mtTargetId,
        maTargethp = maTargetHp,
        mtTargethp = mtTargetHp,
        maTargetLvl = maTargetLvl,
        mtTargetLvl = mtTargetLvl,
        charmRecasts = charmRecasts,
        debuffCount = count,
        mobList = rc.MobList or {},
        mobcountstart = state.getMobCount(),
    }
end

local function refreshBardCombatTwistIfNeeded()
    local rc = state.getRunconfig()
    if rc.bardTwistOnceWait then return end
    if mq.TLO.Me.Class.ShortName() == 'BRD' then
        bardtwist.EnsureDefaultTwistRunning()
    end
end

function botdebuff.DebuffCheck(runPriority)
    castinterrupt.tickPending()
    if state.getRunconfig().SpellTimer > mq.gettime() then return false end
    ---@type RunConfig
    local rc = state.getRunconfig()
    if DebuffCheckHandleBardTwistOnceWait(rc) then return false end
    if spellutils.handleSpellCheckReentry('debuff', { runPriority = runPriority, skipInterruptForBRD = true }) then
        return false
    end
    if state.getMobCount() <= 0 then return false end
    local maTargetId, mtTargetId
    if rc.MobList and rc.MobList[1] and not rc.bardTwistOnceWait then
        local desiredPetTargetId = rc.engageTargetId
        local _
        _, _, maTargetId = spellutils.GetAssistInfo(true)
        if maTargetId == 0 then maTargetId = nil end
        _, _, mtTargetId = spellutils.GetTankInfo(true)
        if mtTargetId == 0 then mtTargetId = nil end

        -- Sticky MT mode: pets stay on MT's target even when a tanktar debuff is aimed at MA.
        if not (desiredPetTargetId and desiredPetTargetId > 0) then
            if tankrole.AmIMainTank() and botconfig.config.melee and botconfig.config.melee['mtSticky'] == true
                and not botconfig.config.melee.offtank and not tankrole.AmIMainAssist() then
                desiredPetTargetId = mtTargetId
            else
                desiredPetTargetId = maTargetId
            end
        end

        if mq.TLO.Me.Pet.ID() and desiredPetTargetId and desiredPetTargetId > 0
            and mq.TLO.Pet.Target.ID() ~= desiredPetTargetId and not mq.TLO.Me.Pet.Combat() then
            botmelee.AdvCombat()
        end
    end
    local ctx = tickprof.span('context', function()
        return debuffBuildContext(rc, maTargetId, mtTargetId)
    end)
    local count = ctx.debuffCount
    if count <= 0 then return false end
    local spellCtxCache = {}
    ctx.getSpellCtx = function(index)
        local cached = spellCtxCache[index]
        if cached ~= nil then
            return cached or nil
        end
        local built = DebuffEvalBuildContext(index, ctx)
        spellCtxCache[index] = built or false
        return built
    end
    local indicesByPhase = {}
    local options = {
        skipInterruptForBRD = true,
        runPriority = runPriority,
        noResume = true,
        mezDebug = mq.TLO.Me.Class.ShortName() == 'BRD',
        immuneCheck = true,
        beforeCast = DebuffOnBeforeCast,
        customCastFn = DebuffCheckBardTwistOnceCast,
        entryValid = DebuffEntryValid,
        afterCast = function(i, EvalID, targethit)
            return DebuffCheckAfterCast(i, EvalID, targethit, ctx.mobcountstart)
        end,
    }
    local function getSpellIndices(phase, target)
        local cached = indicesByPhase[phase]
        if cached then return cached end
        cached = debuffGetSpellIndices(phase, count, ctx, target)
        indicesByPhase[phase] = cached
        return cached
    end
    local function getTargets(phase, context)
        return tickprof.span('targets', function()
            return debuffGetTargetsForPhase(phase, context)
        end)
    end
    local function needsSpell(spellIndex, targetId, targethit, context, phase)
        return tickprof.span('needs', function()
            return debuffTargetNeedsSpell(spellIndex, targetId, targethit, context)
        end)
    end
    local result = tickprof.span('spellcheck', function()
        return spellutils.RunPhaseFirstSpellCheck('debuff', 'doDebuff', DEBUFF_PHASE_ORDER, getTargets,
            getSpellIndices, needsSpell, ctx, options)
    end)
    refreshBardCombatTwistIfNeeded()
    return result
end

function botdebuff.getHookFn(name)
    if name == 'doDebuff' then
        return function(hookName)
            if utils.isNearPrimaryBindPoint() then
                local rc = state.getRunconfig()
                if state.getRunState() == state.STATES.resume_doDebuff then
                    state.clearRunState()
                    rc.CurSpell = {}
                    rc.statusMessage = ''
                end
                if state.getRunState() == state.STATES.casting and rc.CurSpell and rc.CurSpell.sub == 'debuff' then
                    spellutils.clearCastingStateOrResume()
                end
                utils.enforceBindStealth()
                return
            end
            if state.isTravelMode() and not state.isTravelAttackOverriding() then return end
            if botmove.isBeyondFollowDistance() then return end
            if utils.isNonCombatZone(mq.TLO.Zone.ShortName()) then return end
            local rc = state.getRunconfig()
            if botdebuff.TickBardTwistOnceWait(rc) then return end
            local myconfig = botconfig.config
            if not (myconfig.settings.dodebuff or state.isTravelAttackOverriding()) or not (myconfig.debuff.spells and #myconfig.debuff.spells > 0) then return end
            if not rc.MobList[1] then
                if state.getRunState() == state.STATES.resume_doDebuff then
                    state.clearRunState()
                    rc.CurSpell = {}
                    rc.statusMessage = ''
                    return
                end
                if state.getRunState() == state.STATES.casting and rc.CurSpell and rc.CurSpell.sub == 'debuff' then
                    spellutils.clearCastingStateOrResume()
                    return
                end
                if rc.bardTwistOnceWait and botdebuff.TickBardTwistOnceWait(rc) then
                    return
                end
                return
            end
            if state.getRunState() == state.STATES.idle then rc.statusMessage = 'Debuff Check' end
            botdebuff.DebuffCheck(bothooks.getPriority(hookName))
        end
    end
    return nil
end

return botdebuff
