-- Non-peer raid member buffing: segregated from CharInfo peer/watch paths.
-- Roster and spawn-buff duration caches refresh only when idle, at most once a minute.
-- When settings.buffNonPeerRaid is off, callers must not invoke maybeRefreshRoster / needsBuff.

local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')
local utils = require('lib.utils')
local spellutils = require('lib.spellutils')
local charinfo = require('plugin.charinfo')

local M = {}

local REFRESH_MS = 60000
--- Match spellutils buff refresh window: still-up when remaining above this.
local STILL_UP_MS = 20000
--- Optimistic remaining after we cast onto a non-peer (until next idle refresh).
local POST_CAST_MS = 60000

local _rosterAt = 0
local _rosterFlag = false
local _rosterMembers = {} -- { { id, name, class }, ... }

local _buffBySpawn = {} -- [spawnId] = { at = ms, bySpellId = { [id] = remainingMs|false } }
local _spawnRefreshBudget = 0

local function settingOn()
    return botconfig.config.settings and botconfig.config.settings.buffNonPeerRaid == true
end

local function inCombat()
    return state.isCombatContextForBuff()
end

--- Reset per-BuffCheck spawn-populate budget (at most one EnsureSpawnBuffsPopulated per pass).
function M.beginBuffPass()
    _spawnRefreshBudget = 1
end

function M.clearCaches()
    _rosterAt = 0
    _rosterFlag = false
    _rosterMembers = {}
    _buffBySpawn = {}
    _spawnRefreshBudget = 0
end

--- Idle-only roster refresh when toggle is on; no-op when off or in combat or within TTL.
function M.maybeRefreshRoster()
    if not settingOn() then return end
    if inCombat() then return end
    local now = mq.gettime()
    if _rosterAt > 0 and (now - _rosterAt) < REFRESH_MS then return end
    _rosterAt = now
    _rosterFlag = false
    _rosterMembers = {}
    local n = mq.TLO.Raid.Members() or 0
    if n <= 0 then return end
    local meId = mq.TLO.Me.ID()
    for i = 1, n do
        local rm = mq.TLO.Raid.Member(i)
        local name = rm and rm.Name and rm.Name()
        if name and name ~= '' and not charinfo.GetInfo(name) then
            local classRaw = rm.Class and rm.Class.ShortName and rm.Class.ShortName()
            local class = type(classRaw) == 'string' and classRaw:lower() or nil
            local id = rm.ID and rm.ID()
            if not id or id <= 0 then
                id = mq.TLO.Spawn('pc =' .. name).ID() or 0
            end
            if id and id > 0 and id ~= meId and class and class ~= '' then
                local sp = mq.TLO.Spawn(id)
                if sp and sp.Type and sp.Type() == 'PC' then
                    _rosterFlag = true
                    _rosterMembers[#_rosterMembers + 1] = { id = id, name = name, class = class }
                end
            end
        end
    end
end

--- Cached flag only (does not force refresh).
function M.hasMembers()
    return _rosterFlag
end

--- Cached member list only (does not force refresh).
--- @return table[] { id, name, class }
function M.getMembers()
    if not _rosterFlag then return {} end
    return _rosterMembers
end

local function cacheEntry(spawnId)
    return _buffBySpawn[spawnId]
end

local function remainingFor(entry, spellId, now)
    if not entry or not spellId then return nil end
    local v = entry.bySpellId and entry.bySpellId[spellId]
    if v == nil then return nil end
    if v == false then return false end
    local left = v - (now - entry.at)
    if left <= 0 then return false end
    return left
end

local function anyStillUp(entry, spellIds, now)
    for i = 1, #spellIds do
        local left = remainingFor(entry, spellIds[i], now)
        if type(left) == 'number' and left > STILL_UP_MS then
            return true
        end
    end
    return false
end

local function anyKnownAbsent(entry, spellIds, now)
    local saw = false
    for i = 1, #spellIds do
        local left = remainingFor(entry, spellIds[i], now)
        if left ~= nil then
            saw = true
            if type(left) == 'number' and left > STILL_UP_MS then
                return false
            end
        end
    end
    return saw
end

local function readSpawnBuffDuration(sp, checkId, checkName)
    if checkName and checkName ~= '' then
        local buff = sp.Buff(checkName)
        if buff and buff() then
            local matchedId = buff.ID and buff.ID()
            if not checkId or matchedId == checkId then
                local dur = buff.Duration and buff.Duration()
                return dur ~= nil and dur or 0
            end
        end
    end
    if checkId and checkId > 0 then
        local maxSlots = (sp.MaxBuffSlots and sp.MaxBuffSlots()) or 40
        for i = 1, maxSlots do
            local b = sp.Buff(i)
            if b and b() and b.ID and b.ID() == checkId then
                local dur = b.Duration and b.Duration()
                return dur ~= nil and dur or 0
            end
        end
    end
    return false
end

--- Populate cache for one spawn (requires BuffsPopulated). Returns true if cache written.
local function refreshSpawnCache(spawnId, spellId, spellName, spellicon)
    if not spellutils.EnsureSpawnBuffsPopulated(spawnId, 'buff', nil, 'nonpeerraid', nil, nil, nil) then
        return false
    end
    local sp = mq.TLO.Spawn(spawnId)
    if not sp or not sp.BuffsPopulated or not sp.BuffsPopulated() then return false end
    local now = mq.gettime()
    local bySpellId = {}
    local ids = {}
    if spellId and spellId > 0 then
        ids[#ids + 1] = { id = spellId, name = spellName }
    end
    local icons = type(spellicon) == 'table' and spellicon
        or ((spellicon and spellicon ~= 0) and { spellicon } or {})
    for _, iconId in ipairs(icons) do
        local n = tonumber(iconId)
        if n and n > 0 then
            ids[#ids + 1] = { id = n, name = mq.TLO.Spell(n).Name() }
        end
    end
    for _, item in ipairs(ids) do
        bySpellId[item.id] = readSpawnBuffDuration(sp, item.id, item.name)
    end
    _buffBySpawn[spawnId] = { at = now, bySpellId = bySpellId }
    return true
end

local function heightAllows(entry, spawnId)
    local threshold = entry and tonumber(entry.height)
    if (not threshold or threshold <= 0) and spellutils.IsShrinkSpell(entry) then
        threshold = 2.4
    end
    if not threshold or threshold <= 0 then return true end
    if not spawnId or spawnId <= 0 then return false end
    local ht = mq.TLO.Spawn(spawnId).Height()
    return ht ~= nil and ht > threshold
end

local function classMatches(buffClass, classLc)
    if not buffClass or not classLc then return false end
    if buffClass.classes == 'all' then return true end
    return buffClass[classLc] == true
end

local function relatedSpellIds(spellId, spellicon)
    local out = {}
    if spellId and spellId > 0 then out[#out + 1] = spellId end
    local icons = type(spellicon) == 'table' and spellicon
        or ((spellicon and spellicon ~= 0) and { spellicon } or {})
    for _, iconId in ipairs(icons) do
        local n = tonumber(iconId)
        if n and n > 0 then out[#out + 1] = n end
    end
    return out
end

--- After a successful cast onto a non-peer raid member, avoid immediate re-cast from stale "missing".
function M.noteCast(spawnId, spellId)
    if not spawnId or not spellId then return end
    local now = mq.gettime()
    local e = _buffBySpawn[spawnId]
    if not e then
        e = { at = now, bySpellId = {} }
        _buffBySpawn[spawnId] = e
    else
        e.at = now
        e.bySpellId = e.bySpellId or {}
    end
    e.bySpellId[spellId] = POST_CAST_MS
end

--- Need-check for non-peer raid targets. Class filter first; spawn cache before targeting.
--- @return number|nil targetId, string|nil targethit ('pc')
function M.needsBuff(spellIndex, targetId, member, entry, spellName, spellId, rangeSq, buffClass)
    if not settingOn() or not _rosterFlag then return nil, nil end
    if not buffClass or not buffClass.pc then return nil, nil end
    if not member or not classMatches(buffClass, member.class) then return nil, nil end
    if not targetId or targetId <= 0 or not entry or not spellName or spellName == '' then return nil, nil end

    local sp = mq.TLO.Spawn(targetId)
    if not sp or not sp.ID() or sp.ID() == 0 or sp.Type() == 'Corpse' then return nil, nil end
    if not heightAllows(entry, targetId) then return nil, nil end

    local dSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), sp.X(), sp.Y())
    if rangeSq and (not dSq or dSq > rangeSq) then return nil, nil end

    local related = relatedSpellIds(spellId, entry.spellicon)
    local now = mq.gettime()
    local cached = cacheEntry(targetId)
    local cacheFresh = cached and cached.at and (now - cached.at) < REFRESH_MS

    if cacheFresh and anyStillUp(cached, related, now) then
        return nil, nil
    end

    if cacheFresh and anyKnownAbsent(cached, related, now) then
        -- Cache says missing / near expiry: confirm with SpawnNeedsBuff only if already populated.
        if sp.BuffsPopulated and sp.BuffsPopulated() then
            if spellutils.SpawnNeedsBuff(targetId, spellName, entry.spellicon) then
                return targetId, 'pc'
            end
            return nil, nil
        end
        -- Not populated: idle refresh if budget allows; combat skip.
        if inCombat() then return nil, nil end
        if _spawnRefreshBudget <= 0 then return nil, nil end
        _spawnRefreshBudget = _spawnRefreshBudget - 1
        if not refreshSpawnCache(targetId, spellId, spellName, entry.spellicon) then return nil, nil end
        cached = cacheEntry(targetId)
        if anyStillUp(cached, related, mq.gettime()) then return nil, nil end
        if spellutils.SpawnNeedsBuff(targetId, spellName, entry.spellicon) then
            return targetId, 'pc'
        end
        return nil, nil
    end

    -- Missing or stale cache.
    if inCombat() then return nil, nil end
    if not cacheFresh then
        if _spawnRefreshBudget <= 0 then return nil, nil end
        _spawnRefreshBudget = _spawnRefreshBudget - 1
        if not refreshSpawnCache(targetId, spellId, spellName, entry.spellicon) then return nil, nil end
        cached = cacheEntry(targetId)
        now = mq.gettime()
        if anyStillUp(cached, related, now) then return nil, nil end
        if spellutils.SpawnNeedsBuff(targetId, spellName, entry.spellicon) then
            return targetId, 'pc'
        end
        return nil, nil
    end

    return nil, nil
end

return M
