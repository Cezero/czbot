local mq = require('mq')
local botconfig = require('lib.config')
local spellsdb = require('lib.spellsdb')
local immune = require('lib.immune')
local state = require('lib.state')
local spellstates = require('lib.spellstates')
local tankrole = require('lib.tankrole')
local charinfo = require("mqcharinfo")
local spellutils = {}
local _deps = {}

function spellutils.Init(deps)
    if deps then
        _deps.AdvCombat = deps.AdvCombat
    end
end

function spellutils.MountCheck()
    local mountcast = botconfig.config.settings.mountcast
    if not mountcast or mountcast == 'none' then return end
    local mount, spelltype = mountcast:match("^%s*(.-)%s*|%s*(.-)%s*$")
    botconfig.config['mount1'] = { gem = spelltype, spell = mount }
    if not mq.TLO.Me.Mount() and not MountCastFailed then
        spellutils.CastSpell('1', 1, 'mountcast', 'mount')
    end
end

-- Returns true if the spell has no reagents or the character has >= required count of each reagent in inventory.
function spellutils.HasReagents(Sub, ID)
    local entry = botconfig.getSpellEntry(Sub, ID)
    if not entry or not entry.spell then return true end
    local spellForReagents = entry.spell
    if entry.gem == 'item' and mq.TLO.FindItem(entry.spell)() then
        spellForReagents = mq.TLO.FindItem(entry.spell).Spell.Name()
        if not spellForReagents or spellForReagents == '' then return true end
    end
    local sp = mq.TLO.Spell(spellForReagents)
    if not sp() then return true end
    for slot = 1, 4 do
        local rid = sp.ReagentID(slot)()
        if rid and rid > 0 then
            local need = sp.ReagentCount(slot)() or 1
            local have = mq.TLO.FindItemCount(tostring(rid))() or 0
            if have < need then return false end
        end
    end
    return true
end

-- checks spell is loaded, minmana is met, and gem is ready, precondition is good
function spellutils.SpellCheck(Sub, ID)
    local spell = nil
    local minmana = nil
    local gem = nil
    local entry = botconfig.getSpellEntry(Sub, ID)
    if gem ~= "item" and entry and type(entry.alias) == 'string' and spellsdb and spellsdb.resolve_entry then
        local level = tonumber(mq.TLO.Me.Level()) or 1
        if (not entry.spell or entry.spell == 0 or entry.spell == '0' or entry._resolved_level ~= level) then
            spellsdb.resolve_entry(Sub, ID, false)
        end
    end
    if entry and entry.spell then spell = entry.spell end
    minmana = (entry and entry.minmana ~= nil) and entry.minmana or 0
    if entry and entry.gem then gem = entry.gem end
    --check gemInUse (prevents spells fighting over the same gem)
    --spell
    if mq.TLO.Window('SpellBookWnd').Open() then mq.cmd('/book') end
    if spellstates.GetReagentDelay(Sub, ID) and spellstates.GetReagentDelay(Sub, ID) > mq.gettime() then return false end
    if not spellutils.HasReagents(Sub, ID) then
        if entry then entry.enabled = false end
        spellstates.SetReagentDelay(Sub, ID, mq.gettime() + (5 * 60 * 1000)) -- 5 min before retrying this spell
        printf('\ayCZBot:\axMissing reagent for %s, disabling spell for 5 minutes', spell)
        return false
    end
    local spellmana = mq.TLO.Spell(spell).Mana()
    local spellend = mq.TLO.Spell(spell).EnduranceCost()
    if not ((tonumber(gem) and gem <= 13 and gem > 0) or gem == 'alt' or gem == 'item' or gem == 'script' or gem == 'disc' or gem == 'ability') then return false end
    if (tonumber(gem) or gem == 'alt') and spellmana then
        if (mq.TLO.Spell(spell).Mana() and mq.TLO.Spell(spell).Mana() > 0 and ((mq.TLO.Me.CurrentMana() - (mq.TLO.Me.ManaRegen() * 2)) < mq.TLO.Spell(spell).Mana()) or (mq.TLO.Me.PctMana() < minmana)) then return false end
    end
    if gem == 'alt' then
        if not mq.TLO.Me.AltAbilityReady(spell) then return false end
    end
    if gem == 'disc' and spellend then
        if not mq.TLO.Me.CombatAbilityReady(spell) then return false end
        if (mq.TLO.Spell(spell).EnduranceCost() and ((mq.TLO.Me.CurrentEndurance() - (mq.TLO.Me.EnduranceRegen() * 2)) < mq.TLO.Spell(spell).EnduranceCost()) or (mq.TLO.Me.PctMana() < minmana)) then return false end
    end
    return true
end

--Immune check
function spellutils.ImmuneCheck(Sub, ID, EvalID)
    local entry = botconfig.getSpellEntry(Sub, ID)
    if not entry then return true end
    local spell = mq.TLO.Spell(entry.spell)()
    local zone = mq.TLO.Zone.ShortName()
    local targetname = mq.TLO.Spawn(EvalID).CleanName()
    local t = immune.get()
    if t[spell] and t[spell][zone] and t[spell][zone][targetname] then return false else return true end
end

--Check Distance
function spellutils.DistanceCheck(Sub, ID, EvalID)
    local entry = botconfig.getSpellEntry(Sub, ID)
    if not entry then return false end
    local spell = entry.spell
    if not spell then return false end
    local spellid = nil
    local myrange = mq.TLO.Spell(spell).MyRange()
    local tardist = mq.TLO.Spawn(EvalID).Distance()
    if mq.TLO.Spell(spell).AERange() and mq.TLO.Spell(spell).AERange() > 0 and mq.TLO.Spawn(EvalID).Distance() <= mq.TLO.Spell(spell).AERange() then
        return true
    elseif tardist and myrange and tardist <= myrange then
        return true
    else
        return false
    end
end

-- Returns true if peer has spellid in Buff or ShortBuff (rich array scan).
function spellutils.PeerHasBuff(peerInfo, spellid)
    if not peerInfo then return false end
    local function has(list)
        if not list then return false end
        for _, b in ipairs(list) do
            if b and b.Spell and (b.Spell.ID == spellid or tostring(b.Spell.ID) == tostring(spellid)) then return true end
        end
        return false
    end
    return has(peerInfo.Buff) or has(peerInfo.ShortBuff)
end

-- Returns true if peer's pet has spellid in PetBuff.
function spellutils.PeerHasPetBuff(peerInfo, spellid)
    if not peerInfo or not peerInfo.PetBuff then return false end
    for _, b in ipairs(peerInfo.PetBuff) do
        if b and b.Spell and (b.Spell.ID == spellid or tostring(b.Spell.ID) == tostring(spellid)) then return true end
    end
    return false
end

-- Returns true if the spawn already has this heal spell (buff or shortbuff). Used when entry.isHoT is true
-- to avoid recasting HoTs. Covers self and peer PCs; non-peers are treated as not having the spell (no targeting).
function spellutils.TargetHasHealSpell(entry, spawnId)
    if not entry or not entry.spell or not spawnId or spawnId <= 0 then return false end
    local myid = mq.TLO.Me.ID()
    if spawnId == myid or spawnId == 1 then
        return mq.TLO.Me.Buff(entry.spell)() or mq.TLO.Me.ShortBuff(entry.spell)()
    end
    local name = mq.TLO.Spawn(spawnId).Name()
    local peer = charinfo.GetInfo(name)
    if peer then
        local spellid = mq.TLO.Spell(entry.spell).ID()
        return spellutils.PeerHasBuff(peer, spellid)
    end
    return false
end

-- Ensure we have buff data for this spawn (for non-peer buff/cure checks). Buffs only populate after
-- targeting the spawn for a few ms. If not already targeted with BuffsPopulated, /tar and block up to 1s.
-- Returns true when we can read buffs (targeted and BuffsPopulated). Optional args (spellIndex, etc.) kept for API compatibility.
function spellutils.EnsureSpawnBuffsPopulated(spawnId, sub, spellIndex, targethit, cureTypeList, resumePhase,
                                              resumeGroupIndex)
    if not spawnId or not sub then return false end
    if mq.TLO.Target.ID() == spawnId then
        local sp = mq.TLO.Spawn(spawnId)
        if sp and sp.BuffsPopulated and sp.BuffsPopulated() then return true end
    end
    mq.cmdf('/tar id %s', spawnId)
    state.getRunconfig().statusMessage = string.format('Waiting for target buffs (id %s)', spawnId)
    mq.delay(1000, function() return mq.TLO.Target.BuffsPopulated() == true end)
    local sp = mq.TLO.Spawn(spawnId)
    local ok = sp and sp.BuffsPopulated and sp.BuffsPopulated() and mq.TLO.Target.ID() == spawnId
    if not ok then state.getRunconfig().statusMessage = '' end
    return ok
end

-- Spawn: does this spawn need the buff? Buffs are only available on Spawn (like mobs); you must have
-- targeted the spawn for a few ms until BuffsPopulated is true, then Spawn.Buff() is valid.
-- Call EnsureSpawnBuffsPopulated(spawnId, 'buff') first; if it returns false, do not cast.
-- Returns true only when BuffsPopulated and they do not have the buff. Returns false when not
-- populated or when they already have the buff.
function spellutils.SpawnNeedsBuff(spawnId, spellName, spellicon)
    if not spawnId or not spellName or spellName == '' then return false end
    local sp = mq.TLO.Spawn(spawnId)
    if not sp or not sp.ID() or sp.ID() == 0 then return false end
    if not sp.BuffsPopulated or not sp.BuffsPopulated() then return false end
    local hasBuff = sp.Buff(spellName)()
    return not hasBuff
end

-- Spawn: does this spawn have a matching detrimental? Same as buffs: only valid after targeting
-- the spawn until BuffsPopulated is true. Spawn has no Detrimentals/CountXXX; we walk sp.Buff(i)
-- and use TotalCounters to find curable debuffs, then CountersPoison/CountersDisease/etc. on each buff.
function spellutils.SpawnDetrimentalsForCure(spawnId, cureTypeList)
    if not spawnId or not cureTypeList or type(cureTypeList) ~= 'table' then return false end
    local sp = mq.TLO.Spawn(spawnId)
    if not sp or not sp.ID() or sp.ID() == 0 then return false end
    if not sp.BuffsPopulated or not sp.BuffsPopulated() then return false end
    local maxSlots = (sp.MaxBuffSlots and sp.MaxBuffSlots()) or 40
    local countPoison, countDisease, countCurse, countCorruption = 0, 0, 0, 0
    local hasCurable = false
    for i = 1, maxSlots do
        local b = sp.Buff(i)
        if b then
            local total = b.TotalCounters and b.TotalCounters() or 0
            if total > 0 then
                hasCurable = true
                countPoison = countPoison + (b.CountersPoison and b.CountersPoison() or 0)
                countDisease = countDisease + (b.CountersDisease and b.CountersDisease() or 0)
                countCurse = countCurse + (b.CountersCurse and b.CountersCurse() or 0)
                countCorruption = countCorruption + (b.CountersCorruption and b.CountersCorruption() or 0)
            end
        end
    end
    if not hasCurable then return false end
    for _, v in ipairs(cureTypeList) do
        local vlower = string.lower(tostring(v))
        if vlower == 'all' then return true end
        if vlower == 'poison' and countPoison > 0 then return true end
        if vlower == 'disease' and countDisease > 0 then return true end
        if vlower == 'curse' and countCurse > 0 then return true end
        if vlower == 'corruption' and countCorruption > 0 then return true end
    end
    return false
end

-- Returns table of bot names from charinfo.GetPeers(), Fisher-Yates shuffled.
function spellutils.GetBotListShuffled()
    local bots = charinfo.GetPeers()
    for i = #bots, 2, -1 do
        local j = math.random(1, i)
        bots[i], bots[j] = bots[j], bots[i]
    end
    return bots
end

-- Resolve spell name, range, target type from config entry; if gem == 'item' use FindItem spell.
-- entry must have .spell and .gem. Returns spell (name), range, tartype, and optionally spellid.
function spellutils.GetSpellInfo(entry)
    if not entry or not entry.spell then return nil, nil, nil, nil end
    local gem = entry.gem
    local spell = entry.spell
    local range = mq.TLO.Spell(spell).MyRange()
    local tartype = mq.TLO.Spell(spell).TargetType()
    if gem == 'item' then
        spell = mq.TLO.FindItem(spell).Spell.Name()
        if mq.TLO.FindItem(entry.spell)() then
            range = mq.TLO.FindItem(entry.spell).Spell.MyRange()
            tartype = mq.TLO.FindItem(entry.spell).Spell.TargetType()
        end
    end
    local spellid = mq.TLO.Spell(spell).ID() or
        (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.ID())
    return spell, range, tartype, spellid
end

-- Tank = Main Tank only (heals). Uses GetPCTarget for MT's target when needed. Assist/MA is not used here.
function spellutils.GetTankInfo(includeTarget)
    local mainTankName = state.getRunconfig().TankName
    if mainTankName == 'automatic' then mainTankName = tankrole.GetMainTankName() end
    if not mainTankName or mainTankName == '' then return nil, nil, nil, nil end
    local tankid = mq.TLO.Spawn('pc =' .. mainTankName).ID()
    if not includeTarget then return mainTankName, tankid, nil, nil end
    local tanktar, tanktarhp
    local info = charinfo.GetInfo(mainTankName)
    if info and info.ID then
        tanktar = info.Target and info.Target.ID or nil
        tanktarhp = info.TargetHP
    elseif tankid then
        local botmelee = require('botmelee')
        tanktar = botmelee.GetPCTarget(mainTankName)
        tanktarhp = tanktar and mq.TLO.Spawn(tanktar).PctHPs() or nil
    end
    if tanktar == 0 then tanktar = nil end
    return mainTankName, tankid, tanktar, tanktarhp
end

-- Post-cast logic when CastTimeLeft() has reached 0 (called from handleSpellCheckReentry / phase-first re-entry).
function spellutils.OnCastComplete(index, EvalID, targethit, sub)
    local rc = state.getRunconfig()
    local entry = botconfig.getSpellEntry(sub, index)
    if not entry then return end
    local spell = string.lower(entry.spell or '')
    local spellid = mq.TLO.Spell(spell).ID()
    if not rc.CurSpell.viaMQ2Cast and SpellResisted then
        rc.CurSpell.resisted = true
        SpellResisted = false
    end
    if sub == 'debuff' then
        if entry.delay and entry.delay > 0 then
            spellstates.SetDebuffDelay(index, mq.gettime() + (entry.delay * 1000))
        end
        if (mq.TLO.Spell(spell).MyDuration() and tonumber(mq.TLO.Spell(spell).MyDuration()) > 0) then
            if mq.TLO.Target.Buff(spell).ID() or mq.TLO.Me.Class.ShortName() == 'BRD' and not rc.MissedNote then
                local myduration = mq.TLO.Spell(spell).MyDuration.TotalSeconds() * 1000 + mq.gettime()
                if not rc.CurSpell.resisted then
                    spellstates.DebuffListUpdate(EvalID, spellid, myduration)
                    spellstates.ResetRecastCounter(EvalID, index)
                end
            end
        end
    end
    if rc.MissedNote then rc.MissedNote = false end
end

-- ---------------------------------------------------------------------------
-- Phase-first spell-check utilities (small, reusable)
-- ---------------------------------------------------------------------------

--- Returns resume cursor if run state is hookName .. '_resume', else nil.
function spellutils.getResumeCursor(hookName)
    local runState = state.getRunState()
    local expected = (hookName or '') .. '_resume'
    if runState ~= expected then return nil end
    return state.getRunStatePayload()
end

--- On leaving a cast: if payload has spellcheckResume, set that hook's _resume state; else clearRunState().
function spellutils.clearCastingStateOrResume()
    local rc = state.getRunconfig()
    rc.CurSpell = {}
    rc.statusMessage = ''
    local p = state.getRunStatePayload()
    if p and p.spellcheckResume and p.spellcheckResume.hook then
        state.setRunState(p.spellcheckResume.hook .. '_resume', p.spellcheckResume)
    else
        state.clearRunState()
    end
end

--- Handles CurSpell re-entry (casting, precast, precast_wait_move). Returns true if handled (caller should return), false to run the phase-first loop.
function spellutils.handleSpellCheckReentry(sub, options)
    options = options or {}
    if state.getRunState() == 'loading_gem' then
        return false
    end
    local skipInterruptForBRD = options.skipInterruptForBRD ~= false
    local rc = state.getRunconfig()

    if rc.CurSpell and rc.CurSpell.phase == 'cast_complete_pending_resist' then
        spellutils.OnCastComplete(rc.CurSpell.spell, rc.CurSpell.target, rc.CurSpell.targethit, rc.CurSpell.sub)
        if options.afterCast then
            options.afterCast(rc.CurSpell.spell, rc.CurSpell.target, rc.CurSpell.targethit)
        end
        spellutils.clearCastingStateOrResume()
        return true
    end

    -- MQ2Cast completion: poll Cast.Status and Cast.Result; do not use CastTimeLeft.
    if rc.CurSpell and rc.CurSpell.phase == 'casting' and rc.CurSpell.viaMQ2Cast then
        if (not skipInterruptForBRD or mq.TLO.Me.Class.ShortName() ~= 'BRD') then
            spellutils.InterruptCheck()
        end
        local status = mq.TLO.Cast.Status() or ''
        local storedId = mq.TLO.Cast.Stored.ID() or 0
        if not string.find(status, 'C') and storedId == (rc.CurSpell.spellid or 0) then
            rc.CurSpell.resisted = (mq.TLO.Cast.Result() == 'CAST_RESIST')
            if mq.TLO.Cast.Result() == 'CAST_IMMUNE' and rc.CurSpell.target then
                immune.processList(rc.CurSpell.target)
            end
            spellutils.OnCastComplete(rc.CurSpell.spell, rc.CurSpell.target, rc.CurSpell.targethit, rc.CurSpell.sub)
            if options.afterCast then
                options.afterCast(rc.CurSpell.spell, rc.CurSpell.target, rc.CurSpell.targethit)
            end
            spellutils.clearCastingStateOrResume()
            return true
        end
        if sub == rc.CurSpell.sub then
            return true
        end
    end

    if rc.CurSpell and rc.CurSpell.sub and rc.CurSpell.phase == 'casting' then
        if mq.TLO.Me.CastTimeLeft() > 0 and (not skipInterruptForBRD or mq.TLO.Me.Class.ShortName() ~= 'BRD') then
            spellutils.InterruptCheck()
        end
        if mq.TLO.Me.CastTimeLeft() > 0 then
            if sub == rc.CurSpell.sub then
                return true
            end
        else
            if rc.CurSpell.sub ~= 'debuff' then
                spellutils.OnCastComplete(rc.CurSpell.spell, rc.CurSpell.target, rc.CurSpell.targethit, rc.CurSpell.sub)
                if options.afterCast then
                    options.afterCast(rc.CurSpell.spell, rc.CurSpell.target, rc.CurSpell.targethit)
                end
                spellutils.clearCastingStateOrResume()
                return true
            end
            rc.CurSpell.phase = 'cast_complete_pending_resist'
            return true
        end
    end

    if rc.CurSpell and rc.CurSpell.phase == 'precast_wait_move' then
        if mq.TLO.Me.Moving() then
            if mq.gettime() < (rc.CurSpell.deadline or 0) then return true end
            spellutils.clearCastingStateOrResume()
            return true
        end
        spellutils.CastSpell(rc.CurSpell.spell, rc.CurSpell.target, rc.CurSpell.targethit, rc.CurSpell.sub,
            options.runPriority, rc.CurSpell.spellcheckResume)
        return true
    end

    if rc.CurSpell and rc.CurSpell.phase == 'precast' then
        if mq.TLO.Target.ID() ~= rc.CurSpell.target then
            if mq.gettime() < (rc.CurSpell.deadline or 0) then return true end
            spellutils.clearCastingStateOrResume()
            return true
        end
        spellutils.CastSpell(rc.CurSpell.spell, rc.CurSpell.target, rc.CurSpell.targethit, rc.CurSpell.sub,
            options.runPriority, rc.CurSpell.spellcheckResume)
        return true
    end

    return false
end

--- Returns list of spell indices (1..count) for which bandHasPhaseFn(i, phase) is true.
function spellutils.getSpellIndicesForPhase(count, phase, bandHasPhaseFn)
    if not bandHasPhaseFn or type(bandHasPhaseFn) ~= 'function' then return {} end
    local out = {}
    for i = 1, count do
        if bandHasPhaseFn(i, phase) then
            out[#out + 1] = i
        end
    end
    return out
end

--- For one target, finds first spell in spellIndices that needs to be cast. Returns spellIndex, EvalID, targethit or nil.
function spellutils.checkIfTargetNeedsSpells(sub, spellIndices, targetId, targethit, context, options, targetNeedsSpellFn)
    if not targetNeedsSpellFn or not spellIndices then return nil end
    options = options or {}
    local rc = state.getRunconfig()
    for _, spellIndex in ipairs(spellIndices) do
        if MasterPause then return nil end
        local spellNotInBook = rc.spellNotInBook and rc.spellNotInBook[sub] and rc.spellNotInBook[sub][spellIndex]
        if not spellNotInBook and (not options.entryValid or options.entryValid(spellIndex)) then
            local EvalID, hit = targetNeedsSpellFn(spellIndex, targetId, targethit, context)
            if EvalID and hit then
                if (not options.beforeCast or options.beforeCast(spellIndex, EvalID, hit))
                    and (not options.immuneCheck or spellutils.ImmuneCheck(sub, spellIndex, EvalID))
                    and spellutils.PreCondCheck(sub, spellIndex, EvalID) then
                    return spellIndex, EvalID, hit
                end
            end
        end
    end
    return nil
end

--- Thin phase-first orchestrator. phaseOrder = ordered list of phase names; getTargetsFn(phase, context) returns list of { id, targethit }; getSpellIndicesFn(phase) returns list of indices; targetNeedsSpellFn(spellIndex, targetId, targethit, context) returns EvalID, targethit or nil.
function spellutils.RunPhaseFirstSpellCheck(sub, hookName, phaseOrder, getTargetsFn, getSpellIndicesFn,
                                            targetNeedsSpellFn, context, options)
    options = options or {}
    local runPriority = options.runPriority
    local rc = state.getRunconfig()

    if spellutils.handleSpellCheckReentry(sub, options) then
        return false
    end

    local cursor = spellutils.getResumeCursor(hookName)
    local startPhaseIdx = 1
    local startTargetIdx = 1
    local startSpellIdx = 1
    if cursor and cursor.phase and cursor.targetIndex and cursor.spellIndex then
        for pi, p in ipairs(phaseOrder) do
            if p == cursor.phase then
                startPhaseIdx = pi
                startTargetIdx = cursor.targetIndex or 1
                startSpellIdx = cursor.spellIndex or 1
                break
            end
        end
    end
    if cursor and options.entryValid and cursor.spellIndex and not options.entryValid(cursor.spellIndex) then
        state.clearRunState()
    end

    for phaseIdx = startPhaseIdx, #phaseOrder do
        local phase = phaseOrder[phaseIdx]
        local targets = getTargetsFn(phase, context)
        if targets and #targets > 0 then
            local spellIndices = getSpellIndicesFn(phase)
            if spellIndices and #spellIndices > 0 then
                local targetStart = (phaseIdx == startPhaseIdx) and startTargetIdx or 1
                for targetIdx = targetStart, #targets do
                    local target = targets[targetIdx]
                    if target and target.id then
                        local spellStart = (phaseIdx == startPhaseIdx and targetIdx == targetStart) and startSpellIdx or
                        1
                        local fromSpellIndices = {}
                        for _, si in ipairs(spellIndices) do
                            if si >= spellStart then fromSpellIndices[#fromSpellIndices + 1] = si end
                        end
                        if #fromSpellIndices > 0 then
                            local spellIndex, EvalID, targethit = spellutils.checkIfTargetNeedsSpells(sub,
                                fromSpellIndices, target.id, target.targethit, context, options, targetNeedsSpellFn)
                            if spellIndex and EvalID and targethit then
                                if rc.CurSpell and rc.CurSpell.phase == 'casting' and rc.CurSpell.sub ~= sub and mq.TLO.Me.CastTimeLeft() > 0 then
                                    mq.cmd('/stopcast')
                                    spellutils.clearCastingStateOrResume()
                                end
                                local spellcheckResume = { hook = hookName, phase = phase, targetIndex = targetIdx, spellIndex =
                                spellIndex }
                                if spellutils.CastSpell(spellIndex, EvalID, targethit, sub, runPriority, spellcheckResume) then
                                    return false
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    -- Clear _resume state when loop completes without starting a new cast (so we don't stay stuck in doHeal_resume etc.)
    if state.getRunState() == hookName .. '_resume' then
        state.clearRunState()
    end
    return false
end

-- precondition check
function spellutils.PreCondCheck(Sub, ID, spawnID)
    local entry = botconfig.getSpellEntry(Sub, ID)
    if not entry then return false end
    if entry.precondition == nil then return true end
    local precond = entry.precondition
    EvalID = spawnID
    if type(entry.precondition) == 'string' then
        local loadprecond, loadError = load('local mq = require("mq") ' .. precond)
        if loadprecond then
            local env = { EvalID = EvalID }
            setmetatable(env, { __index = _G })
            local output = loadprecond()
            EvalID = nil
            return output
        else
            print('problem loading precond') -- TODO add more context to make this a meaningful error message
        end
    elseif type(entry.precondition) == 'boolean' then
        if entry.precondition then
            EvalID = nil; return true
        end
    end
    EvalID = nil
    return true
end

--checks if a precondition is valid
function spellutils.ProcessScript(script, Sub, ID)
    if botconfig.config.script and type(botconfig.config.script[script]) == 'string' then
        local loadprecond, loadError = load('local mq = require("mq") ' .. botconfig.config.script[script])
        if loadprecond then
            return true
        else
            print('problem loading precond') -- TODO add more context to make this a meaningful error message
            local entry = botconfig.getSpellEntry(Sub, ID)
            if entry then entry.enabled = false end
            return false
        end
    elseif type(botconfig.config[script]) == 'boolean' then
        if botconfig.config[script] then return true end
    end
end

--runs script
function spellutils.RunScript(script, Sub, ID)
    if botconfig.config.script and type(botconfig.config.script[script]) == 'string' then
        local loadprecond, loadError = load('local mq = require("mq") ' .. botconfig.config.script[script])
        if loadprecond then
            local output = loadprecond()
            return output
        else
            print('problem loading precond') -- TODO add more context to make this a meaningful error message
            local entry = botconfig.getSpellEntry(Sub, ID)
            if entry then entry.enabled = false end
            return false
        end
    elseif type(botconfig.config[script]) == 'boolean' then
        if botconfig.config[script] then return true end
    end
end

--- Check loading_gem completion. Returns 'still_waiting', 'done_ok', or 'done_fail'.
--- Payload must have spell, gem, deadline. Uses Cast.Status() "M" and Me.Gem(gem)() to decide.
--- When Status() does not yet show "M", we treat as still_waiting until deadline (avoids aborting before MQ2Cast sets "M").
function spellutils.LoadingGemComplete(payload)
    if not payload or not payload.spell or not payload.gem then return 'done_fail' end
    if mq.gettime() >= (payload.deadline or 0) then
        local g = mq.TLO.Me.Gem(payload.gem)()
        return (g and string.lower(g) == string.lower(payload.spell)) and 'done_ok' or 'done_fail'
    end
    if string.find(mq.TLO.Cast.Status() or '', 'M') then return 'still_waiting' end
    local g = mq.TLO.Me.Gem(payload.gem)()
    if g and string.lower(g) == string.lower(payload.spell) then return 'done_ok' end
    -- No "M" and spell not in gem yet: may be before MQ2Cast set "M" or mem in progress. Wait until deadline.
    return 'still_waiting'
end

function spellutils.LoadSpell(Sub, ID, runPriority)
    local entry = botconfig.getSpellEntry(Sub, ID)
    if not entry then return false end
    if mq.TLO.Me.Class.ShortName() ~= 'BRD' and mq.TLO.Me.CastTimeLeft() > 0 then
        return false
    end
    local spell = entry.spell
    local gem = entry.gem
    local rc = state.getRunconfig()
    -- Re-entry: we're in loading_gem; drive completion (even when this call is for a different spell, so we don't get stuck).
    if state.getRunState() == 'loading_gem' then
        local p = state.getRunStatePayload()
        if not p or not p.spell or not p.gem then
            state.clearRunState()
            rc.CurSpell = {}
            return false
        end
        if p.source == 'chchain_setup' then return false end
        local result = spellutils.LoadingGemComplete(p)
        if result == 'still_waiting' then return false end
        rc.statusMessage = ''
        state.clearRunState()
        if result == 'done_ok' then
            if p.sub == Sub and p.id == ID then return true end
            rc.CurSpell = {}
            return false
        end
        -- done_fail
        local failEntry = botconfig.getSpellEntry(p.sub, p.id)
        if failEntry then
            printf('\ayCZBot:\ax %s[%s]: Spell %s could not be memorized in gem %s', p.sub, p.id, p.spell, p.gem)
            failEntry.enabled = false
            if not rc.spellNotInBook then rc.spellNotInBook = {} end
            if not rc.spellNotInBook[p.sub] then rc.spellNotInBook[p.sub] = {} end
            rc.spellNotInBook[p.sub][p.id] = true
        end
        rc.CurSpell = {}
        return false
    end
    -- if gem ready and spell loaded, return true, else run load logic
    if type(gem) == 'number' and mq.TLO.Me.Gem(spell)() == gem and mq.TLO.Me.SpellReady(spell)() then return true end
    if gem == 'item' then
        if mq.TLO.Me.ItemReady(spell)() then
            return true
        else
            return false
        end
    end
    if gem == 'disc' then
        if mq.TLO.Me.CombatAbilityReady(spell)() then return true else return false end
    end
    if gem == 'ability' then
        if mq.TLO.Me.AbilityReady(spell)() then return true else return false end
    end
    if gem == 'alt' then
        if mq.TLO.Me.AltAbilityReady(spell)() then return true else return false end
    end
    if gem == 'script' then
        if spellutils.ProcessScript(spell, Sub, ID) then return true else return false end
    end
    --check gemInUse (prevents spells fighting over the same gem)
    if type(gem) == 'number' then
        if rc.gemInUse[gem] then
            if mq.TLO.Me.Gem(gem)() and string.lower(mq.TLO.Me.Gem(gem)()) ~= string.lower(spell) and rc.gemInUse[gem] > mq.gettime() then
                return false
            elseif rc.gemInUse[gem] < mq.gettime() then
                rc.gemInUse[gem] = nil
            end
        end
        -- is gem ready if not and spell loaded, set gemInUse
        -- is spell loaded?
        if mq.TLO.Me.Gem(spell)() ~= gem then
            if mq.TLO.Me.Book(spell)() then
                mq.cmdf('/memorize "%s" %s', spell, gem)
                rc.gemInUse[gem] = (mq.gettime() + mq.TLO.Spell(spell).RecastTime())
                rc.statusMessage = string.format('Memorizing %s (gem %s)', spell, gem)
                rc.CurSpell = { phase = 'memorizing', sub = Sub, spell = ID, gem = gem }
                state.setRunState('loading_gem', {
                    sub = Sub,
                    id = ID,
                    spell = spell,
                    gem = gem,
                    deadline = mq.gettime() + 10000,
                    priority = runPriority,
                })
                return false
            else
                printf('\ayCZBot:\ax %s[%s]: Spell %s not found in your book', Sub, ID, spell)
                entry.enabled = false
                if not rc.spellNotInBook then rc.spellNotInBook = {} end
                if not rc.spellNotInBook[Sub] then rc.spellNotInBook[Sub] = {} end
                rc.spellNotInBook[Sub][ID] = true
                state.clearRunState()
                return false
            end
        end
        if not mq.TLO.Me.SpellReady(spell)() then
            if mq.TLO.Me.Gem(spell)() == gem then rc.gemInUse[gem] = (mq.gettime() + mq.TLO.Spell(spell).RecastTime() + 5500) end
            return false
        end
    end
    return true
end

function spellutils.InterruptCheck()
    if state.getRunState() == 'loading_gem' then return false end
    local rc = state.getRunconfig()
    if rc.CurSpell.phase == 'memorizing' then return false end
    if not rc.CurSpell.sub then return false end
    local sub = rc.CurSpell.sub
    local spell = rc.CurSpell.spell
    local entry = botconfig.getSpellEntry(sub, spell)
    if not entry then return false end
    local spellname = entry.spell or (entry.gem == 'item' and mq.TLO.FindItem(entry.spell).Spell())
    if not spellname then return false end
    local criteria = rc.CurSpell.targethit
    local target = rc.CurSpell.target
    local spelltartype = mq.TLO.Spell(spellname).TargetType()
    local targetname = mq.TLO.Spawn(target).CleanName()
    local spellid = mq.TLO.Spell(entry.spell).ID() or
        (entry.gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.ID())
    local spelldur = mq.TLO.Spell(spellname).MyDuration.TotalSeconds() or
        (entry.gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.MyDuration())
    if not criteria then return false end
    if spelldur then spelldur = spelldur * 1000 end
    if not target or not spell or not criteria or not sub then return false end
    if mq.TLO.Me.Class.ShortName() ~= 'BRD' then
        if mq.TLO.Target.ID() and string.lower(spelltartype) ~= "self" and (mq.TLO.Target.ID() == 0 or string.find(mq.TLO.Target.Name(), 'corpse') and criteria ~= 'corpse') then
            mq.cmd('/squelch /multiline; /stick off ; /target clear')
            if mq.TLO.Me.CastTimeLeft() > 0 and target ~= 1 and criteria ~= 'groupheal' and criteria ~= 'groupbuff' and criteria ~= 'groupcure' then
                mq.cmd('/echo I lost my target, interrupting')
                if rc.CurSpell.viaMQ2Cast then mq.cmd('/interrupt') else mq.cmd('/stopcast') end
                if mq.TLO.Me.CastTimeLeft() > 0 and mq.TLO.Me.Combat() then mq.cmd('/attack off') end
            end
            if state.getRunconfig().domelee and _deps.AdvCombat then _deps.AdvCombat() end
        end
    end
    if criteria ~= 'corpse' then
        if mq.TLO.Target.Type() == 'Corpse' and criteria ~= 'corpse' then
            mq.cmd(
                '/multiline ; /interrupt ; /squelch /target clear ; /echo My target is dead, interrupting')
        end
    end
    if sub == 'heal' and criteria ~= 'corpse' then
        local th = AHThreshold and spell and AHThreshold[spell] and AHThreshold[spell][criteria]
        if th and mq.TLO.Target.PctHPs() and mq.TLO.Target.ID() == target then
            local maxVal = type(th) == 'table' and th.max or th
            if (maxVal + (math.abs(maxVal - 100) * botconfig.config.heal.interruptlevel)) <= mq.TLO.Target.PctHPs() then
                mq.cmdf('/multiline ; /interrupt ; /echo Interrupting Spell %s, target is above the threshold',
                    entry.spell)
                mq.cmd('/interrupt')
                spellutils.clearCastingStateOrResume()
            end
        end
    end
    if mq.TLO.Me.CastTimeLeft() > 0 and (sub == 'debuff' or sub == 'buff') and spelldur and spelldur > 0 and mq.TLO.Me.Class.ShortName() ~= 'BRD' then
        local buffid = mq.TLO.Target.Buff(spellname).ID() or false
        local buffstaleness = mq.TLO.Target.Buff(spellname).Staleness() or 0
        local buffdur = mq.TLO.Target.Buff(spellname).Duration() or 0
        if mq.TLO.Target.ID() == target and mq.TLO.Target.BuffsPopulated() and buffid and buffstaleness < 2000 and buffdur > (spelldur * .10) then
            if sub == 'buff' then
                if mq.TLO.Spell(spellid).StacksTarget() then
                    mq.cmdf('/multiline ; /echo Interrupt %s, buff does not stack on target: %s ; /interrupt', spellname,
                        spellname, targetname)
                end
                mq.cmdf('/multiline ; /echo Interrupt %s, buff already present ; /interrupt', spellname, spellname)
                mq.cmd('/interrupt')
                if not rc.interruptCounter[spellid] then rc.interruptCounter[spellid] = { 0, 0 } end
                rc.interruptCounter[spellid] = { rc.interruptCounter[spellid][1] + 1, mq.gettime() + 10000 }
                spellutils.clearCastingStateOrResume()
            elseif sub == 'debuff' and mq.TLO.Spell(spellid).CategoryID() ~= 20 then
                mq.cmdf('/multiline ; /echo Interrupt %s on MobID %s, debuff already present ; /interrupt', spellname,
                    target)
                local spelldur = mq.TLO.Target.Buff(spellname).Duration() + mq.gettime()
                spellstates.DebuffListUpdate(target, spellid, spelldur)
                mq.cmd('/interrupt')
                spellutils.clearCastingStateOrResume()
            end
        end
        if mq.TLO.Target.ID() == target and mq.TLO.Target.BuffsPopulated() and mq.TLO.Spell(spellid).StacksTarget() == 'FALSE' then
            if sub == 'buff' then
                printf('\ayCZBot:\axInterrupt %s, buff does not stack on target: %s', spellname, spellname, targetname)
                mq.cmd('/interrupt')
                if not rc.interruptCounter[spellid] then rc.interruptCounter[spellid] = { 0, 0 } end
                rc.interruptCounter[spellid] = { rc.interruptCounter[spellid][1] + 1, mq.gettime() + 10000 }
                spellutils.clearCastingStateOrResume()
            elseif sub == 'debuff' then
                printf('\ayCZBot:\axInterrupt %s on MobID %s Name %s, debuff does not stack', spellname, target,
                    targetname)
                spellstates.DebuffListUpdate(target, spellname,
                    mq.TLO.Target.Buff(spellname).Duration() + mq.gettime())
                mq.cmd('/interrupt')
                spellutils.clearCastingStateOrResume()
            end
        end
    end
end

function spellutils.CastSpell(index, EvalID, targethit, sub, runPriority, spellcheckResume)
    local rc = state.getRunconfig()
    local entry = botconfig.getSpellEntry(sub, index)
    if not entry then return false end
    local resuming = (rc.CurSpell and rc.CurSpell.phase and rc.CurSpell.spell == index and rc.CurSpell.sub == sub)
    if not resuming then
        if not spellutils.SpellCheck(sub, index) then return false end
        if not spellutils.LoadSpell(sub, index, runPriority) then return false end
        rc.CurSpell = {
            sub = sub,
            spell = index,
            target = EvalID,
            targethit = targethit,
            resisted = false,
            spellcheckResume = spellcheckResume,
        }
        if targethit == 'charmtar' then rc.charmid = EvalID end
    else
        if spellcheckResume then rc.CurSpell.spellcheckResume = spellcheckResume end
    end
    local spell = string.lower(entry.spell or '')
    local gem = entry.gem
    local targetname = mq.TLO.Spawn(EvalID).CleanName()
    local spellname = entry.spell or spell
    if not resuming then
        if sub == 'heal' then
            rc.statusMessage = string.format('Healing %s with %s', targetname, spellname)
        elseif sub == 'buff' then
            rc.statusMessage = string.format('Buffing %s with %s', targetname, spellname)
        elseif sub == 'debuff' or sub == 'ad' then
            rc.statusMessage = string.format('Nuking %s with %s', targetname, spellname)
        elseif sub == 'cure' then
            rc.statusMessage = string.format('Curing %s with %s', targetname, spellname)
        else
            rc.statusMessage = string.format('Casting %s on %s', spellname, targetname)
        end
    end

    if not resuming and (mq.TLO.Spell(spell).MyCastTime() and mq.TLO.Spell(spell).MyCastTime() > 0 and (mq.TLO.Me.Moving() or mq.TLO.Navigation.Active() or mq.TLO.Stick.Active()) and mq.TLO.Me.Class.ShortName() ~= 'BRD') then
        mq.cmd('/multiline ; /nav stop log=off ; /stick off')
        rc.CurSpell.phase = 'precast_wait_move'
        rc.CurSpell.deadline = mq.gettime() + 3000
        state.setRunState('casting',
            { deadline = mq.gettime() + 3000, priority = runPriority, spellcheckResume = rc.CurSpell.spellcheckResume })
        return true
    end
    -- TODO: Revisit bard mez + melee cycle. Current behavior: attack off when mezzing notanktar, and bard never
    -- re-engages melee while mez is "active", so bard just stands there singing mez. Desired: attack off, target add,
    -- pulse mez, wait for land, re-assist MA, attack on (optionally twist DPS song), stay on MA target ~12-15s,
    -- then attack off, target add, re-pulse mez, repeat. Implement in a later plan (state/timers per mez target).
    if (sub == 'debuff' and targethit == 'notanktar' and mq.TLO.Me.Combat()) then mq.cmd('/squelch /attack off') end
    if (mq.TLO.Plugin('MQ2Twist').IsLoaded()) then
        if mq.TLO.Twist() and mq.TLO.Twist.Twisting() then mq.cmd('/squelch /twist stop') end
    end
    if mq.TLO.Me.Class.ShortName() == 'BRD' then
        if (botconfig.config.settings.domelee and state.getRunconfig().MobCount > 0 and targethit ~= 'notanktar' and not mq.TLO.Me.Combat()) then
            if _deps.AdvCombat then _deps.AdvCombat() end
        end
        if type(gem) == 'number' and mq.TLO.Me.SpellReady(spell)() then mq.cmd('/squelch /stopcast') end
    end
    local useMQ2Cast = (type(gem) == 'number' or gem == 'item' or gem == 'alt')
    if not useMQ2Cast and (EvalID ~= 1 or (targethit ~= 'self' and targethit ~= 'groupheal' and targethit ~= 'groupbuff' and targethit ~= 'groupcure')) then
        if mq.TLO.Target.ID() ~= EvalID then
            mq.cmdf('/tar id %s', EvalID)
            rc.CurSpell.phase = 'precast'
            rc.CurSpell.deadline = mq.gettime() + 1000
            state.setRunState('casting', { priority = runPriority, spellcheckResume = rc.CurSpell.spellcheckResume })
            return true
        end
    end
    if entry.announce and type(entry.announce) == 'string' then
        printf("\ayCZBot:\axCasting \ag%s\ax on >\ay%s\ax<", spell, targetname)
    end
    -- Stand before cast when sitting (not on mount); MQ2Cast does not do this.
    if mq.TLO.Me.Sitting() and not mq.TLO.Me.Mount() then
        mq.cmd('/stand')
    end
    if useMQ2Cast then
        local castSpellId = mq.TLO.Spell(entry.spell).ID()
        if entry.gem == 'item' and mq.TLO.FindItem(entry.spell)() then
            castSpellId = mq.TLO.FindItem(entry.spell).Spell.ID()
        end
        local castArg = (type(gem) == 'number') and tostring(gem) or gem
        local cmd = string.format('/casting "%s" %s', spellname, castArg)
        if EvalID ~= 1 or (targethit ~= 'self' and targethit ~= 'groupheal' and targethit ~= 'groupbuff' and targethit ~= 'groupcure') then
            cmd = cmd .. string.format(' -targetid|%s', EvalID)
        end
        if sub == 'debuff' then
            cmd = cmd .. ' -maxtries|2'
        end
        rc.CurSpell.viaMQ2Cast = true
        rc.CurSpell.spellid = castSpellId
        mq.cmd(cmd)
        rc.CurSpell.phase = 'casting'
        state.setRunState('casting', { priority = runPriority, spellcheckResume = rc.CurSpell.spellcheckResume })
        return true
    end
    if type(gem) == 'number' or gem == 'item' or gem == 'alt' or gem == 'script' then
        if EvalID == 1 and (targethit == 'self' or targethit == 'groupheal' or targethit == 'groupbuff' or targethit == 'groupcure') then
            if type(gem) == 'number' then
                mq.cmdf('/cast "%s"', spell)
            elseif gem == 'item' then
                mq.cmdf('/cast item "%s"', spell)
            elseif gem == 'alt' then
                mq.cmdf('/alt act %s', mq.TLO.Me.AltAbility(spell)())
            elseif gem == 'script' then
                spellutils.RunScript(spell, sub, index)
            end
        else
            if type(gem) == 'number' then
                mq.cmdf('/cast "%s"', spell)
            elseif gem == 'item' then
                mq.cmdf('/cast item "%s"', spell)
            elseif gem == 'alt' then
                mq.cmdf('/alt act %s', mq.TLO.Me.AltAbility(spell)())
            elseif gem == 'script' then
                spellutils.RunScript(spell, sub, index)
            end
        end
    elseif gem == 'disc' and mq.TLO.Me.CombatAbilityReady(spell)() then
        mq.cmdf('/squelch /disc %s', spell)
    elseif gem == 'ability' then
        mq.cmdf('/squelch /face fast')
        mq.cmdf('/doability %s', spell)
    end
    rc.CurSpell.phase = 'casting'
    state.setRunState('casting', { priority = runPriority, spellcheckResume = rc.CurSpell.spellcheckResume })
    return true
end

function spellutils.RefreshSpells()
    local enabled, disabled = 0, 0
    local function refresh_section(section)
        local cnt = botconfig.getSpellCount(section)
        if not cnt or cnt <= 0 then return end
        for i = 1, cnt do
            local entry = botconfig.getSpellEntry(section, i)
            if entry and type(entry.alias) == 'string' and entry.alias ~= '' then
                if spellsdb and spellsdb.resolve_entry then spellsdb.resolve_entry(section, i, true) end
                local known = false
                if entry.gem == 'disc' then
                    known = entry.spell and entry.spell ~= 0 and entry.spell ~= '' and
                        mq.TLO.Me.CombatAbility(entry.spell)() ~= nil
                else
                    known = entry.spell and mq.TLO.Me.Book(entry.spell)()
                end
                if known then
                    if entry.enabled == false then
                        entry.enabled = (entry._saved_enabled ~= false) and (entry._saved_enabled or true)
                        entry._saved_enabled = nil
                        enabled = enabled + 1
                    end
                else
                    if entry._saved_enabled == nil then entry._saved_enabled = entry.enabled end
                    if entry.enabled then disabled = disabled + 1 end
                    entry.enabled = false
                end
            end
        end
    end
    refresh_section('heal')
    refresh_section('buff')
    refresh_section('debuff')
    refresh_section('cure')
    printf('Refreshed alias spells. Enabled:%s Disabled:%s', enabled, disabled)
end

return spellutils
