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
local bardtwist = require('lib.bardtwist')

local function defaultDebuffEntry()
    return botconfig.getDefaultSpellEntry('debuff')
end

local function normalizeDebuffEntry(entry)
    if not entry or type(entry.dontStack) ~= 'table' then return end
    local allowed = spellutils.GetDebuffDontStackAllowlist()
    local filtered = {}
    for _, tag in ipairs(entry.dontStack) do
        if allowed[tag] then filtered[#filtered + 1] = tag end
    end
    entry.dontStack = #filtered > 0 and filtered or nil
end

function botdebuff.LoadDebuffConfig()
    castutils.LoadSpellSectionConfig('debuff', {
        defaultEntry = defaultDebuffEntry,
        bandsKey = 'debuff',
        storeIn = DebuffBands,
        perEntryNormalize = normalizeDebuffEntry,
    })
end

castutils.RegisterSectionLoader('debuff', 'dodebuff', botdebuff.LoadDebuffConfig)

local function campCountOk(mobCount, mintar, maxtar)
    local effectiveMintar = mintar or (maxtar and 1) or nil
    if effectiveMintar and mobCount < effectiveMintar then return false end
    if maxtar and mobCount > maxtar then return false end
    return true
end

local function DebuffEvalBuildContext(index)
    local myconfig = botconfig.config
    local entry = botconfig.getSpellEntry('debuff', index)
    if not entry then return nil end
    local spell, spellrange, spelltartype, spellid = spellutils.GetSpellInfo(entry)
    if not spell then return nil end
    local gem = entry.gem
    local spellId, spellMaxLvl, myrange, spelldur, minCastDistSq, aeRange, minCastDist = nil, nil, nil, nil, nil, nil,
        nil
    local tank, tankid, tanktar, tanktarhp = spellutils.GetTankInfo(true)
    if tanktar == 0 then tanktar = nil end
    local tanktarlvl = tanktar and mq.TLO.Spawn(tanktar).Level()
    if gem ~= 'ability' and gem ~= 'script' then
        local spellEntity = spellutils.GetSpellEntity(entry)
        if not spellEntity then return nil end
        spellId = spellEntity.ID()
        spellMaxLvl = spellEntity.MaxLevel()
        myrange = spellEntity.MyRange()
        if spellrange == 0 and spelltartype == 'PB AE' then
            spellrange = spellEntity.AERange()
        end
        spelldur = spellEntity.MyDuration()
        if spellEntity.Category() == 'Pet' then myrange = myconfig.settings.acleash end
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
    local myrangeSq = myrange and (myrange * myrange) or nil
    local db = DebuffBands[index]
    local mobMin = db and db.mobMin or 0
    local mobMax = db and db.mobMax or 100
    return {
        entry = entry,
        spell = spell,
        spellid = spellId,
        spellrange = spellrange,
        spelldur = spelldur,
        gem = gem,
        tank = tank,
        tankid = tankid,
        tanktar = tanktar,
        tanktarhp = tanktarhp,
        tanktarlvl = tanktarlvl,
        spellmaxlvl = spellMaxLvl,
        myrange = myrange,
        myrangeSq = myrangeSq,
        aeRange = aeRange,
        minCastDist = minCastDist,
        minCastDistSq = minCastDistSq,
        mobList = state.getRunconfig().MobList or {},
        mobMin = mobMin,
        mobMax = mobMax,
        mintar = db and db.mintar,
        maxtar = db and db.maxtar,
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
            local myrangeSq = ctx.myrangeSq
            if entry.gem == 'ability' then
                local mr = v.MaxRangeTo(); local e = mr and math.max(0, mr - 2); myrangeSq = e and (e * e)
            end
            local distSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), v.X(), v.Y())
            if ctx.minCastDistSq and distSq and distSq < ctx.minCastDistSq then
                return nil, nil
            end
            if not (myrangeSq and distSq and distSq > myrangeSq) then
                if not (ctx.spelldur and tonumber(ctx.spelldur) > 0 and spellstates.HasDebuffLongerThan(v.ID(), ctx.spellid, 6000)) then
                    local tanktarstack = spellutils.SpellStacksSpawn(entry, ctx.tanktar)
                    if ctx.tanktarlvl and spellutils.IsMezSpell(entry) and ctx.spellmaxlvl and ctx.spellmaxlvl ~= 0 and ctx.spellmaxlvl < ctx.tanktarlvl then
                        return nil, nil
                    end
                    if (type(gem) == 'number' or gem == 'alt' or gem == 'disc' or gem == 'item') and not tanktarstack then
                        return nil, nil
                    end
                    if ctx.aeRange and ctx.mintar and castutils.CountMobsWithinAERangeOfSpawn(ctx.mobList, ctx.tanktar, ctx.aeRange) < ctx.mintar then
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
                local myrangeSq = ctx.myrangeSq
                if entry.gem == 'ability' then
                    local mr = v.MaxRangeTo(); local e = mr and math.max(0, mr - 2); myrangeSq = e and (e * e)
                end
                local distSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), v.X(), v.Y())
                if ctx.minCastDistSq and distSq and distSq < ctx.minCastDistSq then
                    -- skip this add (target too close for targetted AE)
                else
                    if not (myrangeSq and distSq and distSq > myrangeSq) then
                        local tarstacks = spellutils.SpellStacksSpawn(entry, v.ID())
                        if not (ctx.spellid and v.Level() and ctx.spellmaxlvl and ctx.spellmaxlvl ~= 0 and ctx.spellmaxlvl < v.Level()) then
                            if not ((type(gem) == 'number' or gem == 'alt' or gem == 'disc' or gem == 'item') and not tarstacks) then
                                if not (tonumber(ctx.spelldur) > 0 and v.ID() and spellstates.HasDebuffLongerThan(v.ID(), ctx.spellid, 6000)) then
                                    if not (ctx.aeRange and ctx.mintar and castutils.CountMobsWithinAERangeOfSpawn(ctx.mobList, v.ID(), ctx.aeRange) < ctx.mintar) then
                                        return v.ID(), 'notanktar'
                                    end
                                end
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
            local myrangeSq = ctx.myrangeSq
            if entry.gem == 'ability' then
                local mr = v.MaxRangeTo(); local e = mr and math.max(0, mr - 2); myrangeSq = e and (e * e)
            end
            local distSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), v.X(), v.Y())
            if ctx.minCastDistSq and distSq and distSq < ctx.minCastDistSq then return nil, nil end
            if myrangeSq and distSq and distSq > myrangeSq then return nil, nil end
            if not (ctx.spelldur and tonumber(ctx.spelldur) > 0 and spellstates.HasDebuffLongerThan(v.ID(), ctx.spellid, 6000)) then
                local tanktarstack = spellutils.SpellStacksSpawn(entry, ctx.tanktar)
                if ctx.tanktarlvl and spellutils.IsMezSpell(entry) and ctx.spellmaxlvl and ctx.spellmaxlvl ~= 0 and ctx.spellmaxlvl < ctx.tanktarlvl then
                    return nil, nil
                end
                if (type(gem) == 'number' or gem == 'alt' or gem == 'disc' or gem == 'item') and not tanktarstack then
                    return nil, nil
                end
                if ctx.aeRange and ctx.mintar and castutils.CountMobsWithinAERangeOfSpawn(ctx.mobList, ctx.tanktar, ctx.aeRange) < ctx.mintar then
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
    local db = DebuffBands[index]
    if not campCountOk(state.getRunconfig().MobCount, db and db.mintar, db and db.maxtar) then return nil, nil end
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
            local entry = botconfig.getSpellEntry('debuff', i)
            if entry and spellutils.IsCharmSpell(entry) then
                local dctx = DebuffEvalBuildContext(i)
                if dctx then
                    local id, hit = charm.EvalTarget(i, dctx)
                    if id then out[#out + 1] = { id = id, targethit = hit or 'charmtar' } end
                end
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
    if not campCountOk(state.getRunconfig().MobCount, db and db.mintar, db and db.maxtar) then return nil, nil end
    local rc = state.getRunconfig()
    if spellutils.IsNukeSpell(entry) then
        local flavor = spellutils.GetNukeFlavor(entry)
        if not nukeFlavorAllowed(rc, flavor) then return nil, nil end
    end
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
        -- Re-apply when bard notanktar timer expired (e.g. mez before duration ends).
        local timers = context.notanktarDebuffTimers
        if timers and timers[targetId] and mq.gettime() >= timers[targetId] then
            for _, v in ipairs(ctx.mobList) do
                local vid = v.ID and v.ID() or v
                if vid == targetId then
                    if castutils.hpEvalSpawn(v, { min = db.mobMin, max = db.mobMax }) then
                        local myrangeSq = ctx.myrangeSq
                        if entry.gem == 'ability' then
                            local mr = v.MaxRangeTo and v.MaxRangeTo() or ctx.myrange; local e = mr and math.max(0, mr - 2); myrangeSq = e and (e * e)
                        end
                        local distSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), v.X(), v.Y())
                        if not (myrangeSq and distSq and distSq > myrangeSq) then
                            return targetId, 'notanktar'
                        end
                    end
                    break
                end
            end
        end
        for _, v in ipairs(ctx.mobList) do
            local vid = v.ID and v.ID() or v
            if vid == targetId then
                if castutils.hpEvalSpawn(v, { min = db.mobMin, max = db.mobMax }) then
                    local distSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), v.X(), v.Y())
                    if ctx.minCastDistSq and distSq and distSq < ctx.minCastDistSq then
                        break
                    end
                    local myrangeSq = ctx.myrangeSq
                    if entry.gem == 'ability' then
                        local mr = v.MaxRangeTo and v.MaxRangeTo() or ctx.myrange; local e = mr and math.max(0, mr - 2); myrangeSq = e and (e * e)
                    end
                    if not (myrangeSq and distSq and distSq > myrangeSq) then
                        local tarstacks = spellutils.SpellStacksSpawn(entry, targetId)
                        local vlevel = v.Level and v.Level() or mq.TLO.Spawn(targetId).Level()
                        if not (ctx.spellid and vlevel and ctx.spellmaxlvl and ctx.spellmaxlvl ~= 0 and ctx.spellmaxlvl < vlevel) then
                            if not ((type(gem) == 'number' or gem == 'alt' or gem == 'disc' or gem == 'item') and not tarstacks) then
                                if not (tonumber(ctx.spelldur) > 0 and spellstates.HasDebuffLongerThan(targetId, ctx.spellid, 6000)) then
                                    if not (ctx.aeRange and ctx.mintar and castutils.CountMobsWithinAERangeOfSpawn(ctx.mobList, targetId, ctx.aeRange) < ctx.mintar) then
                                        return targetId, 'notanktar'
                                    end
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
    if not entry then return false end
    if not spellutils.CheckGemReadiness('debuff', i, entry) then return false end
    if entry.recast ~= nil and entry.recast > 0 and spellstates.GetRecastCounter(EvalID, i) >= entry.recast then
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

-- BRD notanktar twist-once: wait for cast to finish then post-cast (resist, DebuffListUpdate, timer, re-target MA). Returns true if handled.
local function DebuffCheckHandleBardNotanktarWait(rc)
    if mq.TLO.Me.Class.ShortName() ~= 'BRD' or state.getRunState() ~= 'doDebuff_bard_notanktar_wait' or not rc.bardNotanktarWait then
        return false
    end
    local w = rc.bardNotanktarWait
    if not w or not w.entry or not w.EvalID then
        rc.bardNotanktarWait = nil
        state.clearRunState()
        return false
    end
    if mq.TLO.Me.Casting() or (mq.TLO.Me.CastTimeLeft() and mq.TLO.Me.CastTimeLeft() > 0) then
        return false
    end
    rc.bardNotanktarWait = nil
    state.clearRunState()
    local duration_sec = spellutils.GetSpellDurationSec(w.entry)
    local duration_end = duration_sec > 0 and (mq.gettime() + duration_sec * 1000) or nil
    if duration_end then
        spellstates.DebuffListUpdate(w.EvalID, w.entry.spell, duration_end)
        local bardCfg = botconfig.config.bard
        local mezSec = (bardCfg and type(bardCfg.mez_remez_sec) == 'number' and bardCfg.mez_remez_sec) or 6
        if not rc.notanktarDebuffTimers then rc.notanktarDebuffTimers = {} end
        rc.notanktarDebuffTimers[w.EvalID] = mq.gettime() + (duration_sec - mezSec) * 1000
    end
    local _, _, tanktar = spellutils.GetTankInfo(true)
    if tanktar and tanktar > 0 then mq.cmdf('/tar id %s', tanktar) end
    return true
end

local function DebuffCheckBardNotanktarCast(spellIndex, EvalID, targethit, sub, _runPriority, _spellcheckResume)
    if sub ~= 'debuff' or targethit ~= 'notanktar' or mq.TLO.Me.Class.ShortName() ~= 'BRD' then return false end
    local rc = state.getRunconfig()
    local entry = botconfig.getSpellEntry('debuff', spellIndex)
    if not entry or type(entry.gem) ~= 'number' then return false end
    mq.cmd('/squelch /attack off')
    if mq.TLO.Target.ID() ~= EvalID then mq.cmdf('/tar id %s', EvalID) end
    bardtwist.EnsureTwistForMode('combat')
    bardtwist.SetTwistOnceGem(entry.gem)
    rc.bardNotanktarWait = { spellIndex = spellIndex, EvalID = EvalID, entry = entry }
    state.setRunState('doDebuff_bard_notanktar_wait', {})
    return true
end

local function DebuffEntryValid(i)
    local entry = botconfig.getSpellEntry('debuff', i)
    if not entry then return false end
    local gem = entry.gem
    return (entry.enabled ~= false) and ((type(gem) == 'number' and gem ~= 0) or type(gem) == 'string')
end

local function DebuffCheckAfterCast(spellIndex, EvalID, targethit, mobcountstart)
    if spellstates.GetDebuffDelay(spellIndex) and spellstates.GetDebuffDelay(spellIndex) > mq.gettime() then return false end
    if mobcountstart < state.getRunconfig().MobCount then return false end
    local prevID = EvalID
    local newEvalID, newTargethit = DebuffEval(spellIndex)
    local adEntry = botconfig.getSpellEntry('debuff', spellIndex)
    if newEvalID and prevID == newEvalID and adEntry and (adEntry.recast or 0) > 0 and state.getRunconfig().CurSpell and state.getRunconfig().CurSpell.spell == spellIndex and state.getRunconfig().CurSpell.resisted then
        local newCount = spellstates.IncrementRecastCounter(EvalID, spellIndex)
        state.getRunconfig().CurSpell = {}
        if newCount >= adEntry.recast then
            local rc = state.getRunconfig()
            printf(
                '\ayCZBot:\ax\ar%s\ax has resisted spell \ar%s\ax debuff[%s] \am%s\ax times, disabling spell for this spawn',
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
                                printf('\ayCZBot:\ax \ar%s\ax nukes auto-disabled after resists on 3 mobs in a row.', f:gsub('^%l', string.upper))
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

local function debuffGetSpellIndices(phase, count, ctx)
    if phase == 'charm' then
        local out = {}
        for i = 1, count do
            if ctx.charmRecasts[i] then out[#out + 1] = i end
        end
        for i = 1, count do
            local entry = botconfig.getSpellEntry('debuff', i)
            if entry and spellutils.IsCharmSpell(entry) then
                local dctx = DebuffEvalBuildContext(i)
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
    if not base or #base == 0 then return base end
    local rc = state.getRunconfig()
    local nonNuke, nukeIndices = {}, {}
    for _, i in ipairs(base) do
        local entry = botconfig.getSpellEntry('debuff', i)
        if entry and spellutils.IsNukeSpell(entry) then
            local flavor = spellutils.GetNukeFlavor(entry)
            if nukeFlavorAllowed(rc, flavor) then nukeIndices[#nukeIndices + 1] = i end
        else
            nonNuke[#nonNuke + 1] = i
        end
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
    return nonNuke
end

function botdebuff.DebuffCheck(runPriority)
    if state.getRunconfig().SpellTimer > mq.gettime() then return false end
    ---@type RunConfig
    local rc = state.getRunconfig()
    if DebuffCheckHandleBardNotanktarWait(rc) then return false end
    if not rc.MobCount or rc.MobCount <= 0 then return false end
    local mobcountstart = rc.MobCount
    local botmelee = require('botmelee')
    if rc.MobList and rc.MobList[1] then
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
        notanktarDebuffTimers = rc.notanktarDebuffTimers,
    }
    local options = {
        skipInterruptForBRD = true,
        runPriority = runPriority,
        immuneCheck = true,
        beforeCast = DebuffOnBeforeCast,
        customCastFn = DebuffCheckBardNotanktarCast,
        entryValid = DebuffEntryValid,
        afterCast = function(i, EvalID, targethit)
            return DebuffCheckAfterCast(i, EvalID, targethit, mobcountstart)
        end,
    }
    local function getSpellIndices(phase)
        return debuffGetSpellIndices(phase, count, ctx)
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
