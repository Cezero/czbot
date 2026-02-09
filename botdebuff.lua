local mq = require('mq')
local botconfig = require('lib.config')
local spellbands = require('lib.spellbands')
local spellutils = require('lib.spellutils')
local spellstates = require('lib.spellstates')
local state = require('lib.state')
local utils = require('lib.utils')
local charinfo = require('mqcharinfo')
local bothooks = require('lib.bothooks')
local charm = require('lib.charm')
local castutils = require('lib.castutils')

local botdebuff = {}
local DebuffBands = {}

local function defaultDebuffEntry()
    return botconfig.getDefaultSpellEntry('debuff')
end

function botdebuff.LoadDebuffConfig()
    castutils.LoadSpellSectionConfig('debuff', {
        defaultEntry = defaultDebuffEntry,
        bandsKey = 'debuff',
        storeIn = DebuffBands,
    })
end

castutils.RegisterSectionLoader('debuff', 'dodebuff', botdebuff.LoadDebuffConfig)

local function DebuffEvalBuildContext(index)
    local myconfig = botconfig.config
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
    if not castutils.hpEvalSpawn(ctx.tanktar, { min = db.mobMin, max = db.mobMax }) then return nil, nil end
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
            if castutils.hpEvalSpawn(v, { min = db.mobMin, max = db.mobMax }) then
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
    if not castutils.hpEvalSpawn(ctx.tanktar, { min = db.mobMin, max = db.mobMax }) then return nil, nil end
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
    return castutils.bandHasPhaseSimple(DebuffBands, spellIndex, phase)
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
                if castutils.hpEvalSpawn(v, { min = db.mobMin, max = db.mobMax }) then
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
    local myconfig = botconfig.config
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

function botdebuff.DebuffCheck(runPriority)
    if state.getRunconfig().SpellTimer > mq.gettime() then return false end
    local mobcountstart = state.getRunconfig().MobCount
    local botmelee = require('botmelee')
    if state.getRunconfig().MobList and state.getRunconfig().MobList[1] then
        local tank, _, tanktar = spellutils.GetTankInfo(true)
        if tanktar and tanktar > 0 and mq.TLO.Pet.Target.ID() ~= tanktar and not mq.TLO.Me.Pet.Combat() then botmelee.AdvCombat() end
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

function botdebuff.getHookFn(name)
    if name == 'doDebuff' then
        return function(hookName)
            local myconfig = botconfig.config
            if not myconfig.settings.dodebuff or not (myconfig.debuff.spells and #myconfig.debuff.spells > 0) or not state.getRunconfig().MobList[1] then return end
            if utils.isNonCombatZone(mq.TLO.Zone.ShortName()) then return end
            if state.getRunState() == 'idle' then state.getRunconfig().statusMessage = 'Debuff Check' end
            botdebuff.DebuffCheck(bothooks.getPriority(hookName))
        end
    end
    return nil
end

return botdebuff
