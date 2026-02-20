local mq = require('mq')
local botconfig = require('lib.config')
local spellsdb = require('lib.spellsdb')
local immune = require('lib.immune')
local state = require('lib.state')
local spellstates = require('lib.spellstates')
local tankrole = require('lib.tankrole')
local charinfo = require("mqcharinfo")
local bardtwist = require('lib.bardtwist')
local castutils = require('lib.castutils')
local utils = require('lib.utils')
local spellutils = {}
local _deps = {}

local CASTING_STUCK_MS = 20000
--- When buff remaining time on target is below this (ms), do not interrupt with "buff already present" (allow refresh cast to complete). Should match botbuff's refresh window (e.g. 24s for self).
local BUFF_REFRESH_THRESHOLD_MS = 24000

function spellutils.GetDebuffDontStackAllowlist()
    return botconfig.DEBUFF_DONTSTACK_ALLOWED
end

--- Returns the first category from the list that is present on the current target (Target[tag].ID() > 0), or nil. Only considers tags in the allowlist.
function spellutils.TargetHasDebuffCategory(categories)
    if not categories or #categories == 0 then return nil end
    for _, tag in ipairs(categories) do
        if botconfig.DEBUFF_DONTSTACK_ALLOWED[tag] and mq.TLO.Target[tag] and mq.TLO.Target[tag].ID and mq.TLO.Target[tag].ID() and mq.TLO.Target[tag].ID() > 0 then
            return tag
        end
    end
    return nil
end

--- Record that our spell should be considered "on spawn" until the other spell's duration, so we don't re-attempt every tick. Call when target is current target. categoryTag = e.g. 'Snared'.
function spellutils.RecordDontStackDebuffFromTarget(targetSpawnId, ourSpell, categoryTag)
    if not targetSpawnId or not ourSpell or not categoryTag then return end
    local spellRef = mq.TLO.Target[categoryTag]
    if not spellRef then return end
    local durationSec = 0
    if spellRef.MyDuration then
        durationSec = tonumber(spellRef.MyDuration.TotalSeconds()) or 0 -- MyDuration() ALWAYS has TotalSeconds() we don't need to check for nil
    end
    if durationSec <= 0 then return end
    local expire = mq.gettime() + durationSec * 1000
    spellstates.DebuffListUpdate(targetSpawnId, ourSpell, expire)
end

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
-- Do not store mq.TLO.Spell() proxy; use direct chains to avoid TLO quirk (stored proxy can break/hang).
function spellutils.HasReagents(Sub, ID)
    local entry = botconfig.getSpellEntry(Sub, ID)
    if not entry or not entry.spell then return true end
    local spellForReagents = entry.spell
    if entry.gem == 'item' and mq.TLO.FindItem(entry.spell)() then
        spellForReagents = mq.TLO.FindItem(entry.spell).Spell.Name()
        if not spellForReagents or spellForReagents == '' then return true end
    end
    if not mq.TLO.Spell(spellForReagents)() then return true end
    for slot = 1, 4 do
        local rid = mq.TLO.Spell(spellForReagents).ReagentID(slot)()
        if rid and rid > 0 then
            local need = mq.TLO.Spell(spellForReagents).ReagentCount(slot)() or 1
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
        if (not entry.spell or entry.spell == '' or entry._resolved_level ~= level) then
            spellsdb.resolve_entry(Sub, ID, false)
        end
    end
    if entry and entry.spell then spell = entry.spell end
    if not spell then return false end
    minmana = (entry and entry.minmana ~= nil) and entry.minmana or 0
    if entry and entry.gem then gem = entry.gem end
    if mq.TLO.Window('SpellBookWnd').Open() then mq.cmd('/book') end
    if spellstates.GetReagentDelay(Sub, ID) and spellstates.GetReagentDelay(Sub, ID) > mq.gettime() then return false end
    if not spellutils.HasReagents(Sub, ID) then
        if entry then entry.enabled = false end
        spellstates.SetReagentDelay(Sub, ID, mq.gettime() + (5 * 60 * 1000)) -- 5 min before retrying this spell
        printf('\ayCZBot:\axMissing reagent for %s, disabling spell for 5 minutes', spell)
        return false
    end
    local spellmana, spellend
    if gem ~= 'ability' then
        if not mq.TLO.Spell(spell)() then return false end
        spellmana = mq.TLO.Spell(spell).Mana()
        spellend = mq.TLO.Spell(spell).EnduranceCost()
    end
    if not ((tonumber(gem) and gem <= 13 and gem > 0) or gem == 'alt' or gem == 'item' or gem == 'script' or gem == 'disc' or gem == 'ability') then return false end
    if (tonumber(gem) or gem == 'alt') and spellmana then
        if (spellmana > 0 and ((mq.TLO.Me.CurrentMana() - (mq.TLO.Me.ManaRegen() * 2)) < spellmana) or (mq.TLO.Me.PctMana() < minmana)) then return false end
    end
    if gem == 'alt' then
        if not mq.TLO.Me.AltAbilityReady(spell) then return false end
    end
    if gem == 'disc' and spellend then
        if not mq.TLO.Me.CombatAbilityReady(spell) then return false end
        if (spellend and ((mq.TLO.Me.CurrentEndurance() - (mq.TLO.Me.EnduranceRegen() * 2)) < spellend) or (mq.TLO.Me.PctMana() < minmana)) then return false end
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

--Check Distance (uses distance squared for comparisons)
function spellutils.DistanceCheck(Sub, ID, EvalID)
    local entry = botconfig.getSpellEntry(Sub, ID)
    if not entry then return false end
    local spell = entry.spell
    if not spell then return false end
    local spellid = nil
    local myrange = mq.TLO.Spell(spell).MyRange()
    local aeRange = mq.TLO.Spell(spell).AERange()
    local targ = mq.TLO.Spawn(EvalID)
    local distSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), targ.X(), targ.Y())
    if aeRange and aeRange > 0 and distSq and distSq <= (aeRange * aeRange) then
        return true
    elseif distSq and myrange and distSq <= (myrange * myrange) then
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

-- Returns true if the spawn already has this heal spell (buff or shortbuff). Used for HoT spells (autodetected via IsHoTSpell)
-- to avoid recasting HoTs. Covers self and peer PCs; non-peers are treated as not having the spell (no targeting).
function spellutils.TargetHasHealSpell(entry, spawnId)
    if not entry or not entry.spell or not spawnId or spawnId <= 0 then return false end
    local myid = mq.TLO.Me.ID()
    if spawnId == myid or spawnId == 1 then
        return mq.TLO.Me.FindBuff(entry.spell)()
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
    if sub == 'buff' then
        local sp = mq.TLO.Spawn(spawnId)
        if sp and sp.Type and sp.Type() == 'Corpse' then return false end
    end
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

-- Default class order for bot list: healers, tanks, casters, DPS. Used when config does not override.
-- Config: botconfig.getCommon().botListClassOrder = { 'clr', 'shm', 'dru', ... } (lowercase class short names).
spellutils.DEFAULT_BOTLIST_CLASS_ORDER = { 'clr', 'shm', 'dru', 'war', 'shd', 'pal', 'enc', 'wiz', 'mag', 'nec', 'brd', 'mnk', 'rog', 'bst', 'rng', 'bzk' }

local function _getBotListClassPriority()
    local order = spellutils.DEFAULT_BOTLIST_CLASS_ORDER
    local common = botconfig.getCommon()
    if common and common.botListClassOrder and type(common.botListClassOrder) == 'table' and #common.botListClassOrder > 0 then
        order = common.botListClassOrder
    end
    local priority = {}
    for i, cls in ipairs(order) do
        priority[string.lower(tostring(cls))] = i
    end
    return priority
end

--- Returns priority number for a class short name (lower = earlier in rez/target order). Unknown class returns 9999.
function spellutils.GetClassOrderPriority(classShortName)
    local priority = _getBotListClassPriority()
    return priority[string.lower(tostring(classShortName or ''))] or 9999
end

--- Returns table of bot names from charinfo.GetPeers(), sorted by class order (healers first, then tanks, casters, DPS).
--- Order is configurable via botconfig.getCommon().botListClassOrder (array of lowercase class short names).
function spellutils.GetBotListOrdered()
    local bots = charinfo.GetPeers()
    if not bots or #bots == 0 then return bots end
    local priority = _getBotListClassPriority()
    table.sort(bots, function(a, b)
        local acls = mq.TLO.Spawn('pc =' .. a).Class.ShortName()
        local bcls = mq.TLO.Spawn('pc =' .. b).Class.ShortName()
        acls = acls and string.lower(acls) or ''
        bcls = bcls and string.lower(bcls) or ''
        local ap = priority[acls] or 9999
        local bp = priority[bcls] or 9999
        if ap ~= bp then return ap < bp end
        return (a or '') < (b or '')
    end)
    return bots
end

-- Returns table of bot names from charinfo.GetPeers(), Fisher-Yates shuffled. Prefer GetBotListOrdered for deterministic targeting.
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

-- Return spell ID for entry, handling gem == 'item' via FindItem.Spell.ID().
function spellutils.GetSpellId(entry)
    if not entry or not entry.spell then return nil end
    local id = mq.TLO.Spell(entry.spell).ID()
    if id then return id end
    if entry.gem == 'item' and mq.TLO.FindItem(entry.spell)() then
        return mq.TLO.FindItem(entry.spell).Spell.ID()
    end
    return nil
end

-- Return the spell TLO for the entry (Spell or FindItem.Spell for items). Nil if neither applies.
function spellutils.GetSpellEntity(entry)
    if not entry or not entry.spell then return nil end
    if entry.gem == 'item' then
        if not mq.TLO.FindItem(entry.spell)() then return nil end
        return mq.TLO.FindItem(entry.spell).Spell
    end
    return mq.TLO.Spell(entry.spell)
end

-- Return duration in seconds for the entry's spell (handles item). Returns 0 if none or invalid.
-- MyDuration() returns ticks (1 tick = 6 sec); use MyDuration.TotalSeconds() for seconds.
function spellutils.GetSpellDurationSec(entry)
    local e = spellutils.GetSpellEntity(entry)
    if not e or not e.MyDuration then return 0 end
    return tonumber(e.MyDuration.TotalSeconds()) or 0 -- MyDuration() ALWAYS has TotalSeconds() we don't need to check for nil
end

-- Returns true if the debuff entry is a nuke (no duration / direct damage). Used for rotation and flavor filtering.
function spellutils.IsNukeSpell(entry)
    if not entry or not entry.spell then return false end
    if entry.gem == 'disc' or entry.gem == 'ability' then return false end
    return spellutils.GetSpellDurationSec(entry) == 0
end

-- MQ Spell.ResistType() -> normalized flavor string. Returns nil if unknown or no entity.
local RESIST_TYPE_TO_FLAVOR = {
    ['Cold'] = 'ice',
    ['Fire'] = 'fire',
    ['Magic'] = 'magic',
    ['Poison'] = 'poison',
    ['Disease'] = 'disease',
    ['Chromatic'] = 'chromatic',
    ['Prismatic'] = 'prismatic',
    ['Unresistable'] = 'unresistable',
    ['Corruption'] = 'corruption',
}

function spellutils.GetNukeFlavor(entry)
    local e = spellutils.GetSpellEntity(entry)
    if not e then return nil end
    local rt = e.ResistType and e.ResistType() or e.ResistType
    if type(rt) == 'function' then rt = rt(e) end
    if not rt or type(rt) ~= 'string' then return nil end
    return RESIST_TYPE_TO_FLAVOR[rt] or rt:lower()
end

-- Return whether the spell stacks on the given spawn (handles item). Nil/false if no stack or no entity.
function spellutils.SpellStacksSpawn(entry, spawnId)
    local e = spellutils.GetSpellEntity(entry)
    return e and e.StacksSpawn(spawnId)()
end

-- SPA 22 = Charm (MacroQuest spelleffects.h). Returns true if the spell for entry has the Charm effect.
-- Do not store mq.TLO.Spell() proxy; use direct chains (see HasReagents comment).
function spellutils.IsCharmSpell(entry)
    if not entry or not entry.spell then return false end
    if entry.gem == 'item' then
        if not mq.TLO.FindItem(entry.spell)() then return false end
        local ok, hasCharm = pcall(function() return mq.TLO.FindItem(entry.spell).Spell.HasSPA(22)() end)
        if ok and hasCharm then return true end
        local ok2, cat = pcall(function() return mq.TLO.FindItem(entry.spell).Spell.Category() end)
        local ok3, sub = pcall(function() return mq.TLO.FindItem(entry.spell).Spell.Subcategory() end)
        if cat and type(cat) == 'string' and cat:lower():find('charm') then return true end
        if sub and type(sub) == 'string' and sub:lower():find('charm') then return true end
        return false
    end
    if not mq.TLO.Spell(entry.spell)() then return false end
    local ok, hasCharm = pcall(function() return mq.TLO.Spell(entry.spell).HasSPA(22)() end)
    if ok and hasCharm then return true end
    local ok2, cat = pcall(function() return mq.TLO.Spell(entry.spell).Category() end)
    local ok3, sub = pcall(function() return mq.TLO.Spell(entry.spell).Subcategory() end)
    if cat and type(cat) == 'string' and cat:lower():find('charm') then return true end
    if sub and type(sub) == 'string' and sub:lower():find('charm') then return true end
    return false
end

-- Returns true if the spell is a mez (Enthrall subcategory). Used for GUI label and level checks.
function spellutils.IsMezSpell(entry)
    if not entry or not entry.spell then return false end
    local e = spellutils.GetSpellEntity(entry)
    if not e then return false end
    local sub = e.Subcategory and e.Subcategory() or e.Subcategory
    if type(sub) == 'function' then sub = sub(e) end
    return sub and type(sub) == 'string' and sub == 'Enthrall'
end

-- Returns true if the spell is targeted AE (radius around target) with AERange > 0.
function spellutils.IsTargetedAESpell(entry)
    if not entry or not entry.spell then return false end
    local spell, _, tartype = spellutils.GetSpellInfo(entry)
    if not spell or tartype ~= 'Targeted AE' then return false end
    local aerange = 0
    if entry.gem == 'item' then
        if mq.TLO.FindItem(entry.spell)() then aerange = mq.TLO.FindItem(entry.spell).Spell.AERange() or 0 end
    else
        aerange = mq.TLO.Spell(spell).AERange() or 0
    end
    return aerange > 0
end

-- SPA 100 = HoT Heals (MacroQuest spelleffects.h). Returns true if the spell for entry has the HoT effect.
-- Do not store mq.TLO.Spell() proxy; use direct chains (see HasReagents comment).
function spellutils.IsHoTSpell(entry)
    if not entry or not entry.spell then return false end
    if entry.gem == 'item' then
        if not mq.TLO.FindItem(entry.spell)() then return false end
        local ok, hasHoT = pcall(function() return mq.TLO.FindItem(entry.spell).Spell.HasSPA(100)() end)
        return ok and hasHoT
    end
    if not mq.TLO.Spell(entry.spell)() then return false end
    local ok, hasHoT = pcall(function() return mq.TLO.Spell(entry.spell).HasSPA(100)() end)
    return ok and hasHoT
end

-- Returns true if the spell is a pet summon (Category Pet, or SPA 33 SUMMON_PET / SPA 103 CALL_PET).
-- Do not store mq.TLO.Spell() proxy; use direct chains (see HasReagents comment).
function spellutils.IsPetSummonSpell(entry)
    if not entry or not entry.spell then return false end
    if entry.gem == 'item' then
        if not mq.TLO.FindItem(entry.spell)() then return false end
        local okCat, cat = pcall(function() return mq.TLO.FindItem(entry.spell).Spell.Category() end)
        if okCat and cat and type(cat) == 'string' and cat == 'Pet' then return true end
        local ok33, has33 = pcall(function() return mq.TLO.FindItem(entry.spell).Spell.HasSPA(33)() end)
        if ok33 and has33 then return true end
        local ok103, has103 = pcall(function() return mq.TLO.FindItem(entry.spell).Spell.HasSPA(103)() end)
        return ok103 and has103
    end
    if not mq.TLO.Spell(entry.spell)() then return false end
    local okCat, cat = pcall(function() return mq.TLO.Spell(entry.spell).Category() end)
    if okCat and cat and type(cat) == 'string' and cat == 'Pet' then return true end
    local ok33, has33 = pcall(function() return mq.TLO.Spell(entry.spell).HasSPA(33)() end)
    if ok33 and has33 then return true end
    local ok103, has103 = pcall(function() return mq.TLO.Spell(entry.spell).HasSPA(103)() end)
    return ok103 and has103
end

-- Tank = Main Tank only (heals). Uses GetPCTarget for MT's target when needed. Assist/MA is not used here.
function spellutils.GetTankInfo(includeTarget)
    local mainTankName = state.getRunconfig().TankName
    if mainTankName == 'automatic' then
        local mtn = tankrole.GetMainTankName()
        if mtn then mainTankName = mtn end
    end
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
        if spellutils.IsNukeSpell(entry) then
            rc.lastNukeIndex = index
        end
        local durationSec = spellutils.GetSpellDurationSec(entry)
        if durationSec > 0 then
            if mq.TLO.Target.Buff(spell).ID() or mq.TLO.Me.Class.ShortName() == 'BRD' and not rc.MissedNote then
                local myduration = durationSec * 1000 + mq.gettime()
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

--- Returns resume cursor if run state is this hook's resume state (numeric), else nil.
function spellutils.getResumeCursor(hookName)
    if state.getRunState() ~= state.RESUME_BY_HOOK[hookName] then return nil end
    return state.getRunStatePayload()
end

--- Single exit from casting: clears CurSpell/statusMessage, then sets hookName_resume (if spellcheckResume) or clearRunState().
--- All code that leaves the "casting" busy state must call this so CurSpell and runState stay in sync.
function spellutils.clearCastingStateOrResume()
    local rc = state.getRunconfig()
    local hadSub = rc.CurSpell and rc.CurSpell.sub
    if mq.TLO.Me.Class.ShortName() == 'BRD' and hadSub and (hadSub == 'buff' or hadSub == 'debuff' or hadSub == 'cure') then
        bardtwist.ResumeTwist()
    end
    rc.CurSpell = {}
    rc.statusMessage = ''
    local p = state.getRunStatePayload()
    if p and p.spellcheckResume and p.spellcheckResume.hook then
        local resumeNum = state.RESUME_BY_HOOK[p.spellcheckResume.hook]
        if resumeNum then
            state.setRunState(resumeNum, p.spellcheckResume)
        else
            state.clearRunState()
        end
    else
        state.clearRunState()
    end
end

--- True when MQ2Cast is memorizing (spell into gem). Cast.Status() contains 'M'; no cast bar yet (CastTimeLeft 0) to distinguish from HoT channeling.
function spellutils.IsMemorizing()
    local rc = state.getRunconfig()
    if not rc.CurSpell or not rc.CurSpell.viaMQ2Cast then return false end
    local status = mq.TLO.Cast.Status() or ''
    if not string.find(status, 'M') then return false end
    return (mq.TLO.Me.CastTimeLeft() or 0) == 0
end

--- Handles CurSpell re-entry (casting, precast, precast_wait_move). Returns true if handled (caller should return), false to run the phase-first loop.
function spellutils.handleSpellCheckReentry(sub, options)
    options = options or {}
    local skipInterruptForBRD = options.skipInterruptForBRD ~= false
    local rc = state.getRunconfig()

    -- Stuck casting recovery: clear if we've been in casting state past deadline. Do not clear while memorizing.
    if state.getRunState() == state.STATES.casting and state.runStateDeadlinePassed() then
        if not spellutils.IsMemorizing() then
            spellutils.clearCastingStateOrResume()
            return false
        end
    end

    -- Heal: clear casting state when target is above interrupt threshold (e.g. 100%), even if Cast.Status() has 'M' (HoT) or completion wasn't detected. Skip when memorizing.
    if not spellutils.IsMemorizing() and rc.CurSpell and rc.CurSpell.phase == 'casting' and rc.CurSpell.sub == 'heal' and rc.CurSpell.target and mq.TLO.Target.ID() == rc.CurSpell.target then
        local entry = botconfig.getSpellEntry('heal', rc.CurSpell.spell)
        if entry then
            spellutils.InterruptCheckHealThreshold(rc, 'heal', rc.CurSpell.targethit, rc.CurSpell.spell, mq.TLO.Target, rc.CurSpell.target, entry)
            if not rc.CurSpell.phase then
                return false
            end
        end
    end

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
        if rc.CurSpell.target and mq.TLO.Target.ID() ~= rc.CurSpell.target then
            spellutils.clearCastingStateOrResume()
            return false
        end
        if (not skipInterruptForBRD or mq.TLO.Me.Class.ShortName() ~= 'BRD') and not spellutils.IsMemorizing() then
            spellutils.InterruptCheck()
        end
        local status = mq.TLO.Cast.Status() or ''
        local storedId = mq.TLO.Cast.Stored.ID() or 0
        local castResult = mq.TLO.Cast.Result() or ''
        local complete = (not string.find(status, 'C') and not string.find(status, 'M') and storedId == (rc.CurSpell.spellid or 0))
        if complete then
            rc.CurSpell.resisted = (castResult == 'CAST_RESIST')
            if castResult == 'CAST_IMMUNE' and rc.CurSpell.target then
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

    if rc.CurSpell and rc.CurSpell.sub and rc.CurSpell.phase == 'casting' and not rc.CurSpell.viaMQ2Cast then
        if rc.CurSpell.target and mq.TLO.Target.ID() ~= rc.CurSpell.target then
            spellutils.clearCastingStateOrResume()
            return false
        end
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

    -- Another sub is casting; do not run our phase loop or we overwrite CurSpell and get stuck (e.g. heal fizzles, we set CurSpell=buff, storedId stays heal).
    if rc.CurSpell and rc.CurSpell.phase == 'casting' and rc.CurSpell.sub and rc.CurSpell.sub ~= sub then
        return true
    end

    return false
end

--- Returns list of spell indices (1..count) for which the band has the phase.
--- bandHasPhaseFnOrTable: function(spellIndex, phase) or band table (uses castutils.bandHasPhaseSimple).
function spellutils.getSpellIndicesForPhase(count, phase, bandHasPhaseFnOrTable)
    if not bandHasPhaseFnOrTable then return {} end
    local out = {}
    local check = type(bandHasPhaseFnOrTable) == 'function'
        and bandHasPhaseFnOrTable
        or function(i, p) return castutils.bandHasPhaseSimple(bandHasPhaseFnOrTable, i, p) end
    for i = 1, count do
        if check(i, phase) then
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
                                if rc.CurSpell and rc.CurSpell.phase == 'casting' and rc.CurSpell.sub ~= sub and mq.TLO.Me.CastTimeLeft() > 0 and not spellutils.IsMemorizing() then
                                    mq.cmd('/stopcast')
                                    spellutils.clearCastingStateOrResume()
                                end
                                local spellcheckResume = {
                                    hook = hookName,
                                    phase = phase,
                                    targetIndex = targetIdx,
                                    spellIndex =
                                        spellIndex
                                }
                                if options.customCastFn and options.customCastFn(spellIndex, EvalID, targethit, sub, runPriority, spellcheckResume) then
                                    return false
                                end
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
    if state.getRunState() == state.RESUME_BY_HOOK[hookName] then
        state.clearRunState()
    end
    return false
end

-- precondition check: precondition is string or nil. Literal 'true'/'false' skip Lua eval.
function spellutils.PreCondCheck(Sub, ID, spawnID)
    local entry = botconfig.getSpellEntry(Sub, ID)
    if not entry then return false end
    if entry.precondition == nil then return true end
    if type(entry.precondition) ~= 'string' then
        EvalID = nil; return true
    end
    local precond = entry.precondition:match('^%s*(.-)%s*$') or entry.precondition
    if precond == 'true' then
        EvalID = nil; return true
    end
    if precond == 'false' then
        EvalID = nil; return false
    end
    EvalID = spawnID
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
    EvalID = nil
    return true
end

-- Internal: load script from config.script[script]; if run then execute. Returns (success, output or nil).
local function loadAndOptionalRun(script, run)
    if not botconfig.config.script or type(botconfig.config.script[script]) ~= 'string' then
        return false, nil
    end
    local chunk, loadError = load('local mq = require("mq") ' .. botconfig.config.script[script])
    if not chunk then
        print('problem loading precond') -- TODO add more context to make this a meaningful error message
        return false, nil
    end
    if not run then
        return true, nil
    end
    local output = chunk()
    return true, output
end

--checks if a precondition is valid
function spellutils.ProcessScript(script, Sub, ID)
    if type(botconfig.config[script]) == 'boolean' then
        if botconfig.config[script] then return true end
    end
    if botconfig.config.script and type(botconfig.config.script[script]) == 'string' then
        local ok = loadAndOptionalRun(script, false)
        if not ok then
            local entry = botconfig.getSpellEntry(Sub, ID)
            if entry then entry.enabled = false end
            return false
        end
        return true
    end
end

--runs script
function spellutils.RunScript(script, Sub, ID)
    if type(botconfig.config[script]) == 'boolean' then
        if botconfig.config[script] then return true end
    end
    if botconfig.config.script and type(botconfig.config.script[script]) == 'string' then
        local ok, output = loadAndOptionalRun(script, true)
        if not ok then
            local entry = botconfig.getSpellEntry(Sub, ID)
            if entry then entry.enabled = false end
            return false
        end
        return output
    end
end

function spellutils.InterruptCheckTargetLost(rc, targetSpawn, criteria, spelltartype)
    if mq.TLO.Me.Class.ShortName() == 'BRD' then return end
    if not targetSpawn.ID() or string.lower(spelltartype) == 'self' then return end
    local lostOrCorpse = (targetSpawn.ID() == 0) or
        (string.find(targetSpawn.Name() or '', 'corpse') and criteria ~= 'corpse')
    if not lostOrCorpse then return end
    mq.cmd('/squelch /multiline; /stick off ; /target clear')
    if mq.TLO.Me.CastTimeLeft() > 0 and rc.CurSpell.target ~= mq.TLO.Me.ID() and criteria ~= 'groupheal' and criteria ~= 'groupbuff' and criteria ~= 'groupcure' then
        mq.cmd('/echo I lost my target, interrupting')
        if rc.CurSpell.viaMQ2Cast then mq.cmd('/interrupt') else mq.cmd('/stopcast') end
        if mq.TLO.Me.CastTimeLeft() > 0 and mq.TLO.Me.Combat() then mq.cmd('/attack off') end
    end
    if state.getRunconfig().domelee and _deps.AdvCombat then _deps.AdvCombat() end
end

function spellutils.InterruptCheckHealThreshold(rc, sub, criteria, spell, targetSpawn, target, entry)
    if sub ~= 'heal' or criteria == 'corpse' then return end
    local th = AHThreshold and spell and AHThreshold[spell] and AHThreshold[spell][criteria]
    if not th or not targetSpawn.PctHPs() or targetSpawn.ID() ~= target then return end
    local maxVal = type(th) == 'table' and th.max or th
    if (maxVal + (math.abs(maxVal - 100) * botconfig.config.heal.interruptlevel)) <= targetSpawn.PctHPs() then
        mq.cmdf('/multiline ; /interrupt ; /echo Interrupting Spell %s, target is above the threshold', entry.spell)
        mq.cmd('/interrupt')
        spellutils.clearCastingStateOrResume()
    end
end

function spellutils.InterruptCheckDontStack(entry, target, spellname)
    if not (entry.dontStack and #entry.dontStack > 0) then return end
    if mq.TLO.Me.CastTimeLeft() <= 0 or mq.TLO.Target.ID() ~= target or not mq.TLO.Target.BuffsPopulated() then return end
    local tag = spellutils.TargetHasDebuffCategory(entry.dontStack)
    if not tag then return end
    printf('\ayCZBot:\axInterrupt %s, target already %s', spellname, tag)
    spellutils.RecordDontStackDebuffFromTarget(target, entry.spell, tag)
    mq.cmd('/interrupt')
    spellutils.clearCastingStateOrResume()
end

function spellutils.InterruptCheckBuffDebuffAlreadyPresent(rc, sub, entry, spellname, spellid, spelldurMs, target,
                                                           targetname)
    local durMs = tonumber(spelldurMs) or 0
    if mq.TLO.Me.CastTimeLeft() <= 0 or (sub ~= 'debuff' and sub ~= 'buff') or not spelldurMs or durMs <= 0 or mq.TLO.Me.Class.ShortName() == 'BRD' then return end
    if mq.TLO.Target.ID() ~= target or not mq.TLO.Target.BuffsPopulated() then return end
    local buffid = mq.TLO.Target.Buff(spellname).ID() or false
    local buffstaleness = mq.TLO.Target.Buff(spellname).Staleness() or 0
    local buffdur = mq.TLO.Target.Buff(spellname).Duration() or 0
    local buffPresent = buffid and buffstaleness < 2000 and buffdur > (durMs * 0.10)
    local stacks = mq.TLO.Spell(spellid).StacksTarget()

    if sub == 'buff' then
        if not stacks then
            printf('\ayCZBot:\axInterrupt %s, buff does not stack on target: %s', spellname, targetname)
            mq.cmd('/interrupt')
            if not rc.interruptCounter[spellid] then rc.interruptCounter[spellid] = { 0, 0 } end
            rc.interruptCounter[spellid] = { rc.interruptCounter[spellid][1] + 1, mq.gettime() + 10000 }
            spellutils.clearCastingStateOrResume()
        elseif buffPresent and buffdur >= BUFF_REFRESH_THRESHOLD_MS then
            -- Buff present with enough time left: interrupt. Below threshold we allow refresh cast to complete.
            printf('\ayCZBot:\axInterrupt %s, buff already present', spellname)
            mq.cmd('/interrupt')
            if not rc.interruptCounter[spellid] then rc.interruptCounter[spellid] = { 0, 0 } end
            rc.interruptCounter[spellid] = { rc.interruptCounter[spellid][1] + 1, mq.gettime() + 10000 }
            spellutils.clearCastingStateOrResume()
        end
    elseif sub == 'debuff' then
        local shouldInterrupt = (buffPresent and mq.TLO.Spell(spellid).CategoryID() ~= 20) or not stacks
        if shouldInterrupt then
            if not stacks then
                printf('\ayCZBot:\axInterrupt %s on MobID %s Name %s, debuff does not stack', spellname, target, targetname)
            else
                printf('\ayCZBot:\axInterrupt %s on MobID %s, debuff already present', spellname, target)
            end
            local expire = (mq.TLO.Target.Buff(spellname).Duration() or 0) + mq.gettime()
            spellstates.DebuffListUpdate(target, spellid, expire)
            mq.cmd('/interrupt')
            spellutils.clearCastingStateOrResume()
        end
    end
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
    local spelltartype = mq.TLO.Spell(spellname).TargetType() or ''
    local targetname = mq.TLO.Spawn(target).CleanName()
    local spellid = spellutils.GetSpellId(entry)
    if not spellid then return false end
    local spelldur = spellutils.GetSpellDurationSec(entry) * 1000
    if not criteria then return false end
    if not target or not spell or not criteria or not sub then return false end
    if not mq.TLO.Target.ID() or mq.TLO.Target.ID() == 0 then return false end
    local targetSpawn = mq.TLO.Target

    -- Heal threshold must run even when Cast.Status() contains 'M' (e.g. HoT channeling), so we clear when target is above band.
    if sub == 'heal' then
        spellutils.InterruptCheckHealThreshold(rc, sub, criteria, spell, targetSpawn, target, entry)
    end
    if string.find(mq.TLO.Cast.Status() or '', 'M') then return false end

    spellutils.InterruptCheckTargetLost(rc, targetSpawn, criteria, spelltartype)
    if criteria ~= 'corpse' and targetSpawn.Type() == 'Corpse' then
        mq.cmd('/multiline ; /interrupt ; /squelch /target clear ; /echo My target is dead, interrupting')
    end
    spellutils.InterruptCheckHealThreshold(rc, sub, criteria, spell, targetSpawn, target, entry)
    if sub == 'debuff' then
        spellutils.InterruptCheckDontStack(entry, target, spellname)
    end
    spellutils.InterruptCheckBuffDebuffAlreadyPresent(rc, sub, entry, spellname, spellid, spelldur, target, targetname)
end

-- CastSpell helpers (used by CastSpell only or by re-entry flow).

function spellutils.CheckGemReadiness(sub, index, entry)
    local rc = state.getRunconfig()
    local spell = entry.spell
    local gem = entry.gem
    if type(gem) == 'number' then
        if not mq.TLO.Me.Book(spell)() then
            printf('\ayCZBot:\ax %s[%s]: Spell %s not found in your book', sub, index, spell)
            entry.enabled = false
            if not rc.spellNotInBook then rc.spellNotInBook = {} end
            if not rc.spellNotInBook[sub] then rc.spellNotInBook[sub] = {} end
            rc.spellNotInBook[sub][index] = true
            return false
        end
    elseif gem == 'item' then
        if not mq.TLO.Me.ItemReady(spell)() then return false end
    elseif gem == 'disc' then
        if not mq.TLO.Me.CombatAbilityReady(spell)() then return false end
    elseif gem == 'ability' then
        if not mq.TLO.Me.AbilityReady(spell)() then return false end
    elseif gem == 'alt' then
        if not mq.TLO.Me.AltAbilityReady(spell)() then return false end
    elseif gem == 'script' then
        if not spellutils.ProcessScript(spell, sub, index) then return false end
    end
    return true
end

function spellutils.SetCastStatusMessage(sub, targetname, spellname, entry)
    local rc = state.getRunconfig()
    if sub == 'heal' then
        rc.statusMessage = string.format('Healing %s with %s', targetname, spellname)
    elseif sub == 'buff' then
        rc.statusMessage = string.format('Buffing %s with %s', targetname, spellname)
    elseif sub == 'debuff' or sub == 'ad' then
        if entry and (entry.gem == 'ability' or entry.gem == 'disc') then
            rc.statusMessage = string.format('Using %s on %s', spellname, targetname)
        elseif entry and spellutils.IsMezSpell(entry) then
            rc.statusMessage = string.format('Mezzing %s with %s', targetname, spellname)
        elseif entry and spellutils.IsNukeSpell(entry) then
            rc.statusMessage = string.format('Nuking %s with %s', targetname, spellname)
        else
            rc.statusMessage = string.format('Casting %s on %s', spellname, targetname)
        end
    elseif sub == 'cure' then
        rc.statusMessage = string.format('Curing %s with %s', targetname, spellname)
    else
        rc.statusMessage = string.format('Casting %s on %s', spellname, targetname)
    end
end

function spellutils.ShouldWaitForMovement(entry)
    if not entry or not entry.spell then return false end
    local spell = string.lower(entry.spell or '')
    local castTime = mq.TLO.Spell(spell).MyCastTime()
    if not castTime or castTime <= 0 then return false end
    if mq.TLO.Me.Class.ShortName() == 'BRD' then return false end
    return mq.TLO.Me.Moving() or mq.TLO.Navigation.Active() or mq.TLO.Stick.Active()
end

function spellutils.RequireTargetThenDontStackDebuff(entry, EvalID)
    if not (entry and entry.dontStack and #entry.dontStack > 0) then return false end
    if mq.TLO.Target.ID() ~= EvalID then
        mq.cmdf('/tar id %s', EvalID)
        mq.delay(500, function() return mq.TLO.Target.BuffsPopulated() == true end)
    end
    if mq.TLO.Target.ID() == EvalID and mq.TLO.Target.BuffsPopulated() then
        local tag = spellutils.TargetHasDebuffCategory(entry.dontStack)
        if tag then
            spellutils.RecordDontStackDebuffFromTarget(EvalID, entry.spell, tag)
            return true
        end
    end
    return false
end

function spellutils.BuildMQ2CastCommand(entry, EvalID, sub)
    local gem = entry.gem
    local spellname = entry.spell
    local castArg = (type(gem) == 'number') and tostring(gem) or gem
    local cmd = string.format('/casting "%s" %s', spellname, castArg)
    cmd = cmd .. string.format(' -targetid|%s', EvalID)
    if sub == 'debuff' then
        cmd = cmd .. ' -maxtries|2'
    end
    return cmd
end

--- Only for cast types MQ2Cast does not support. Called from CastSpell when gem is script/disc/ability.
function spellutils.ExecuteNativeCast(gem, spell, sub, index)
    if gem == 'script' then
        spellutils.RunScript(spell, sub, index)
    elseif gem == 'disc' and mq.TLO.Me.CombatAbilityReady(spell)() then
        mq.cmdf('/squelch /disc %s', spell)
    elseif gem == 'ability' then
        mq.cmdf('/squelch /face fast')
        mq.cmdf('/doability %s', spell)
    end
end

--- EvalID is the spawn ID of the cast target; for self/group it is Me.ID().
function spellutils.CastSpell(index, EvalID, targethit, sub, runPriority, spellcheckResume)
    local rc = state.getRunconfig()
    local meId = mq.TLO.Me.ID()
    local entry = botconfig.getSpellEntry(sub, index)
    if not entry then return false end
    local resuming = (rc.CurSpell and rc.CurSpell.phase and rc.CurSpell.spell == index and rc.CurSpell.sub == sub)
    if not resuming then
        if not state.canStartBusyState(state.STATES.casting) then return false end
        if not spellutils.SpellCheck(sub, index) then return false end
        if mq.TLO.Me.Class.ShortName() ~= 'BRD' and mq.TLO.Me.CastTimeLeft() > 0 then return false end
        if not spellutils.CheckGemReadiness(sub, index, entry) then return false end
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
    local spawn = mq.TLO.Spawn(EvalID)
    local targetname = (spawn and spawn.CleanName()) or 'Unknown'
    local spellname = entry.spell or spell
    if not resuming then
        spellutils.SetCastStatusMessage(sub, targetname, spellname, (sub == 'debuff' or sub == 'ad') and entry or nil)
    end

    if not resuming and spellutils.ShouldWaitForMovement(entry) then
        mq.cmd('/multiline ; /nav stop log=off ; /stick off')
        rc.CurSpell.phase = 'precast_wait_move'
        rc.CurSpell.deadline = mq.gettime() + 3000
        state.setRunState(state.STATES.casting,
            { deadline = mq.gettime() + 3000, priority = runPriority, spellcheckResume = rc.CurSpell.spellcheckResume })
        return true
    end
    if (sub == 'debuff' and targethit == 'notanktar' and mq.TLO.Me.Combat()) then mq.cmd('/squelch /attack off') end
    if bardtwist and bardtwist.StopTwist then bardtwist.StopTwist() end
    if mq.TLO.Me.Class.ShortName() == 'BRD' then
        if (botconfig.config.settings.domelee and state.getMobCount() > 0 and targethit ~= 'notanktar' and not mq.TLO.Me.Combat()) then
            if _deps.AdvCombat then _deps.AdvCombat() end
        end
        if type(gem) == 'number' and mq.TLO.Me.SpellReady(spell)() then mq.cmd('/squelch /stopcast') end
    end
    local useMQ2Cast = (type(gem) == 'number' or gem == 'item' or gem == 'alt')
    if not useMQ2Cast and mq.TLO.Target.ID() ~= EvalID then
        mq.cmdf('/tar id %s', EvalID)
        rc.CurSpell.phase = 'precast'
        rc.CurSpell.deadline = mq.gettime() + 1000
        state.setRunState(state.STATES.casting, { deadline = mq.gettime() + CASTING_STUCK_MS, priority = runPriority, spellcheckResume = rc.CurSpell.spellcheckResume })
        return true
    end
    if sub == 'debuff' and spellutils.RequireTargetThenDontStackDebuff(entry, EvalID) then
        return false
    end
    if entry.announce then
        printf("\ayCZBot:\axCasting \ag%s\ax on >\ay%s\ax<", spell, targetname)
    end
    if mq.TLO.Me.Sitting() and not mq.TLO.Me.Mount() and (not rc.CurSpell or rc.CurSpell.phase ~= 'casting') then
        mq.cmd('/stand')
    end
    if useMQ2Cast then
        local castSpellId = spellutils.GetSpellId(entry)
        local cmd = spellutils.BuildMQ2CastCommand(entry, EvalID, sub)
        rc.CurSpell.viaMQ2Cast = true
        rc.CurSpell.spellid = castSpellId
        mq.cmd(cmd)
        rc.CurSpell.phase = 'casting'
        state.setRunState(state.STATES.casting, { deadline = mq.gettime() + CASTING_STUCK_MS, priority = runPriority, spellcheckResume = rc.CurSpell.spellcheckResume })
        return true
    end
    spellutils.ExecuteNativeCast(gem, spell, sub, index)
    rc.CurSpell.phase = 'casting'
    state.setRunState(state.STATES.casting, { deadline = mq.gettime() + CASTING_STUCK_MS, priority = runPriority, spellcheckResume = rc.CurSpell.spellcheckResume })
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
                    known = entry.spell and entry.spell ~= '' and
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

spellutils.BUFF_REFRESH_THRESHOLD_MS = BUFF_REFRESH_THRESHOLD_MS

return spellutils
