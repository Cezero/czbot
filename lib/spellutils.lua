local mq = require('mq')
local botconfig = require('lib.config')
local spellsdb = require('lib.spellsdb')
local immune = require('lib.immune')
local state = require('lib.state')
local spellstates = require('lib.spellstates')
local tankrole = require('lib.tankrole')
local charinfo = require('plugin.charinfo')
local spellutils = {}
local _deps = {}

function spellutils.Init(deps)
    if deps then
        _deps.AdvCombat = deps.AdvCombat
    end
end

function spellutils.MountCheck()
    local mountcast = botconfig.config.settings.mountcast or 'none'
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

-- Ensure we have buff data for this spawn (for non-peer buff/cure checks). Buffs only populate after
-- targeting the spawn for a few ms. Returns true if we can read buffs (targeted and BuffsPopulated);
-- if not, targets the spawn, sets state 'buffs_populate_wait', and returns false so caller should
-- return without casting. Next tick RunSpellCheckLoop will re-enter and either wait or clear state.
-- Optional spellIndex and targethit are stored in payload so the wait block can cast on clear.
-- Optional cureTypeList (for sub=='cure') is stored so the wait block can re-check need.
-- Optional resumePhase and resumeGroupIndex (for sub=='buff') let the wait block set buffs_resume on clear.
function spellutils.EnsureSpawnBuffsPopulated(spawnId, sub, spellIndex, targethit, cureTypeList, resumePhase,
                                              resumeGroupIndex)
    if not spawnId or not sub then return false end
    local runState = state.getRunState()
    local payload = state.getRunStatePayload()
    if runState == 'buffs_populate_wait' and payload and payload.spawnId == spawnId and payload.sub == sub then
        if mq.TLO.Target.ID() ~= spawnId then
            mq.cmdf('/tar id %s', spawnId)
            return false
        end
        local sp = mq.TLO.Spawn(spawnId)
        if sp and sp.BuffsPopulated and sp.BuffsPopulated() then
            state.clearRunState()
            return true
        end
        return false
    end
    if mq.TLO.Target.ID() == spawnId then
        local sp = mq.TLO.Spawn(spawnId)
        if sp and sp.BuffsPopulated and sp.BuffsPopulated() then return true end
    end
    state.setRunState('buffs_populate_wait',
        { spawnId = spawnId, sub = sub, spellIndex = spellIndex, targethit = targethit, cureTypeList = cureTypeList, resumePhase =
        resumePhase, resumeGroupIndex = resumeGroupIndex })
    mq.cmdf('/tar id %s', spawnId)
    return false
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

-- Post-cast logic when CastTimeLeft() has reached 0 (called from RunSpellCheckLoop).
function spellutils.OnCastComplete(index, EvalID, targethit, sub)
    local rc = state.getRunconfig()
    local entry = botconfig.getSpellEntry(sub, index)
    if not entry then return end
    local spell = string.lower(entry.spell or '')
    local spellid = mq.TLO.Spell(spell).ID()
    mq.doevents()
    if SpellResisted then
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

-- Common spell-check loop: re-entrant; one step per tick. No mq.delay.
-- If CurSpell.phase is casting/precast, handle that first. If loading_gem, check deadline/gem.
-- Otherwise iterate indices and optionally start a cast (CastSpell sets phase and returns).
function spellutils.RunSpellCheckLoop(sub, count, evalFn, options)
    options = options or {}
    local skipInterruptForBRD = options.skipInterruptForBRD ~= false
    local rc = state.getRunconfig()

    mq.doevents()
    if mq.TLO.Me.State() == 'DEAD' or mq.TLO.Me.State() == 'HOVER' then return false end

    -- Re-entry: currently casting
    if rc.CurSpell and rc.CurSpell.sub and rc.CurSpell.phase == 'casting' then
        if mq.TLO.Me.CastTimeLeft() > 0 and (not skipInterruptForBRD or mq.TLO.Me.Class.ShortName() ~= 'BRD') then
            spellutils.InterruptCheck()
        end
        if mq.TLO.Me.CastTimeLeft() > 0 then return false end
        spellutils.OnCastComplete(rc.CurSpell.spell, rc.CurSpell.target, rc.CurSpell.targethit, rc.CurSpell.sub)
        local cont = true
        if options.afterCast then
            cont = options.afterCast(rc.CurSpell.spell, rc.CurSpell.target, rc.CurSpell.targethit)
        end
        rc.CurSpell = {}
        rc.statusMessage = ''
        state.clearRunState()
        if not cont then return true end
        if not options.priority then return true end
        -- fall through to try next spell index
    end

    -- Re-entry: waiting for move to stop (do not clear phase so CastSpell sees resuming = true)
    if rc.CurSpell and rc.CurSpell.phase == 'precast_wait_move' then
        if mq.TLO.Me.Moving() then
            if mq.gettime() < (rc.CurSpell.deadline or 0) then return false end
            rc.CurSpell = {}
            rc.statusMessage = ''
            state.clearRunState()
            return false
        end
        spellutils.CastSpell(rc.CurSpell.spell, rc.CurSpell.target, rc.CurSpell.targethit, rc.CurSpell.sub)
        return false
    end

    -- Re-entry: waiting for target (do not clear phase so CastSpell sees resuming = true)
    if rc.CurSpell and rc.CurSpell.phase == 'precast' then
        if mq.TLO.Target.ID() ~= rc.CurSpell.target then
            if mq.gettime() < (rc.CurSpell.deadline or 0) then return false end
            rc.CurSpell = {}
            rc.statusMessage = ''
            state.clearRunState()
            return false
        end
        spellutils.CastSpell(rc.CurSpell.spell, rc.CurSpell.target, rc.CurSpell.targethit, rc.CurSpell.sub)
        return false
    end

    -- loading_gem: check each tick
    if state.getRunState() == 'loading_gem' then
        local p = state.getRunStatePayload()
        if p and p.deadline and mq.gettime() >= p.deadline then state.clearRunState() end
        if state.getRunState() == 'loading_gem' and p and p.gem and p.spell then
            local cur = mq.TLO.Me.Gem(p.gem)()
            if cur and string.lower(cur) == string.lower(p.spell) then state.clearRunState() end
        end
        if state.getRunState() == 'loading_gem' then return false end
    end

    -- Re-entry: waiting for spawn buffs to populate (non-peer buff/cure). Target spawn, then wait until BuffsPopulated.
    if state.getRunState() == 'buffs_populate_wait' then
        local p = state.getRunStatePayload()
        if p and p.spawnId then
            if mq.TLO.Target.ID() ~= p.spawnId then
                mq.cmdf('/tar id %s', p.spawnId)
                return false
            end
            local sp = mq.TLO.Spawn(p.spawnId)
            if not sp or not sp.BuffsPopulated or not sp.BuffsPopulated() then
                return false
            end
            state.clearRunState()
            if p.spellIndex and p.targethit then
                local shouldCast = false
                if p.sub == 'buff' then
                    local entry = botconfig.getSpellEntry(p.sub, p.spellIndex)
                    if entry then
                        local spell = spellutils.GetSpellInfo(entry)
                        shouldCast = (spell and spellutils.SpawnNeedsBuff(p.spawnId, spell, entry.spellicon)) == true
                    end
                elseif p.sub == 'cure' then
                    shouldCast = spellutils.SpawnDetrimentalsForCure(p.spawnId, p.cureTypeList or {}) == true
                else
                    shouldCast = true
                end
                if shouldCast then
                    spellutils.CastSpell(p.spellIndex, p.spawnId, p.targethit, p.sub)
                end
                if p.sub == 'buff' and (p.resumePhase or p.resumeGroupIndex) then
                    local phase = p.resumePhase or 'after_tank'
                    local nextGroupMemberIndex = (p.resumePhase == 'groupmember' and p.resumeGroupIndex) and
                    (p.resumeGroupIndex + 1) or nil
                    state.setRunState('buffs_resume',
                        { buffIndex = p.spellIndex, phase = phase, nextGroupMemberIndex = nextGroupMemberIndex })
                elseif p.sub == 'cure' and (p.resumePhase or p.resumeGroupIndex) then
                    local phase = p.resumePhase or 'after_tank'
                    local nextGroupMemberIndex = (p.resumePhase == 'groupmember' and p.resumeGroupIndex) and
                    (p.resumeGroupIndex + 1) or nil
                    state.setRunState('cures_resume',
                        { cureIndex = p.spellIndex, phase = phase, nextGroupMemberIndex = nextGroupMemberIndex })
                end
                return false
            end
        end
    end

    for i = 1, count do
        if MasterPause then return false end
        local runState = state.getRunState()
        local p = state.getRunStatePayload()
        -- If resume index is no longer valid (e.g. disabled after spell not in book), clear so full loop runs
        if runState == 'buffs_resume' and sub == 'buff' and p and p.buffIndex and options.entryValid and not options.entryValid(p.buffIndex) then
            state.clearRunState()
            runState = state.getRunState()
            p = state.getRunStatePayload()
        elseif runState == 'cures_resume' and sub == 'cure' and p and p.cureIndex and options.entryValid and not options.entryValid(p.cureIndex) then
            state.clearRunState()
            runState = state.getRunState()
            p = state.getRunStatePayload()
        end
        if (runState == 'buffs_resume' and sub == 'buff' and p and p.buffIndex and i ~= p.buffIndex)
            or (runState == 'cures_resume' and sub == 'cure' and p and p.cureIndex and i ~= p.cureIndex) then
            -- skip this index; only run eval for the index we are resuming
        else
            local spellNotInBook = rc.spellNotInBook and rc.spellNotInBook[sub] and rc.spellNotInBook[sub][i]
            if (not options.entryValid or options.entryValid(i)) and not spellNotInBook then
                local EvalID, targethit = evalFn(i)
                if state.getRunState() == 'buffs_populate_wait' then
                    return false
                end
                if EvalID and targethit
                    and (not options.beforeCast or options.beforeCast(i, EvalID, targethit))
                    and (not options.immuneCheck or spellutils.ImmuneCheck(sub, i, EvalID))
                    and spellutils.PreCondCheck(sub, i, EvalID) then
                    -- Only exit when we actually started a cast (or precast); otherwise try next index
                    if spellutils.CastSpell(i, EvalID, targethit, sub) then
                        return false
                    end
                end
            end
        end
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

function spellutils.LoadSpell(Sub, ID)
    local entry = botconfig.getSpellEntry(Sub, ID)
    if not entry then return false end
    if mq.TLO.Me.Class.ShortName() ~= 'BRD' and mq.TLO.Me.CastTimeLeft() > 0 then
        return false
    end
    local spell = entry.spell
    local gem = entry.gem
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
    local rc = state.getRunconfig()
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
                mq.cmdf('/memspell %s "%s"', gem, spell)
                rc.gemInUse[gem] = (mq.gettime() + mq.TLO.Spell(spell).RecastTime())
                state.setRunState('loading_gem', { deadline = mq.gettime() + 10000, gem = gem, spell = spell })
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
    local rc = state.getRunconfig()
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
                mq.cmd('/stopcast')
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
                rc.CurSpell = {}
                rc.statusMessage = ''
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
                rc.CurSpell = {}
                rc.statusMessage = ''
            elseif sub == 'debuff' and mq.TLO.Spell(spellid).CategoryID() ~= 20 then
                mq.cmdf('/multiline ; /echo Interrupt %s on MobID %s, debuff already present ; /interrupt', spellname,
                    target)
                local spelldur = mq.TLO.Target.Buff(spellname).Duration() + mq.gettime()
                spellstates.DebuffListUpdate(target, spellid, spelldur)
                mq.cmd('/interrupt')
                rc.CurSpell = {}
                rc.statusMessage = ''
            end
        end
        if mq.TLO.Target.ID() == target and mq.TLO.Target.BuffsPopulated() and mq.TLO.Spell(spellid).StacksTarget() == 'FALSE' then
            if sub == 'buff' then
                printf('\ayCZBot:\axInterrupt %s, buff does not stack on target: %s', spellname, spellname, targetname)
                mq.cmd('/interrupt')
                if not rc.interruptCounter[spellid] then rc.interruptCounter[spellid] = { 0, 0 } end
                rc.interruptCounter[spellid] = { rc.interruptCounter[spellid][1] + 1, mq.gettime() + 10000 }
                rc.CurSpell = {}
                rc.statusMessage = ''
            elseif sub == 'debuff' then
                printf('\ayCZBot:\axInterrupt %s on MobID %s Name %s, debuff does not stack', spellname, target,
                    targetname)
                spellstates.DebuffListUpdate(target, spellname,
                    mq.TLO.Target.Buff(spellname).Duration() + mq.gettime())
                mq.cmd('/interrupt')
                rc.CurSpell = {}
                rc.statusMessage = ''
            end
        end
    end
    if mq.TLO.Me.CastTimeLeft() > 0 and sub == 'cure' and false then
        if criteria == 'all' then criteria = 'Detrimentals' end
        local tarname = mq.TLO.Target.CleanName()
        local curtar = mq.TLO.Target.ID()
        local buffspop = mq.TLO.Target.BuffsPopulated()
        if tarname then
            local peer = charinfo.GetInfo(tarname)
            local nbid = peer and peer.ID or nil
            local nbdebuff = peer and peer[criteria] or nil
            if curtar and nbid and curtar == target and buffspop and not nbdebuff then
                printf('\ayCZBot:\axInterrupt %s, is no longer %s', spellname, criteria)
                mq.cmd('/interrupt')
                rc.CurSpell = {}
                rc.statusMessage = ''
            end
        end
    end
end

function spellutils.CastSpell(index, EvalID, targethit, sub)
    local rc = state.getRunconfig()
    local entry = botconfig.getSpellEntry(sub, index)
    if not entry then return false end
    local resuming = (rc.CurSpell and rc.CurSpell.phase and rc.CurSpell.spell == index and rc.CurSpell.sub == sub)
    if not resuming then
        if not spellutils.SpellCheck(sub, index) then return false end
        if not spellutils.LoadSpell(sub, index) then return false end
        rc.CurSpell = {
            sub = sub,
            spell = index,
            target = EvalID,
            targethit = targethit,
            resisted = false,
        }
        if targethit == 'charmtar' then rc.charmid = EvalID end
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
        mq.cmd('/multiline ; /nav stop log=off ; /stick off)')
        rc.CurSpell.phase = 'precast_wait_move'
        rc.CurSpell.deadline = mq.gettime() + 3000
        state.setRunState('casting')
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
    if EvalID ~= 1 or (targethit ~= 'self' and targethit ~= 'groupheal' and targethit ~= 'groupbuff' and targethit ~= 'groupcure') then
        if mq.TLO.Target.ID() ~= EvalID then
            mq.cmdf('/tar id %s', EvalID)
            rc.CurSpell.phase = 'precast'
            rc.CurSpell.deadline = mq.gettime() + 1000
            state.setRunState('casting')
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
    state.setRunState('casting')
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
