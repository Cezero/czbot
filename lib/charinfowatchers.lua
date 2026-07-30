-- CharInfo HEAL/BUFF/CURE watcher registration and query helpers for czbot.

local mq = require('mq')
local botconfig = require('lib.config')
local rolelists = require('lib.rolelists')
local tankrole = require('lib.tankrole')
local charinfo = require('plugin.charinfo')
local spellutils = require('lib.spellutils')

local M = {}

local PHASE_TO_SCOPE = {
    tank = 'LIST',
    offtank = 'LIST',
    groupmember = 'INGROUP',
    groupheal = 'GRPAGG',
    groupbuff = 'GRPAGG',
    groupcure = 'GRPAGG',
    pc = 'ALL',
}

local KIND_BY_SECTION = {
    heal = 'HEAL',
    buff = 'BUFF',
    cure = 'CURE',
}

local CURE_TYPES = { 'POISON', 'DISEASE', 'CURSE', 'CORRUPTION' }

--- Normalize spellicon to a list of positive spell IDs. Accepts number, string, or array.
function M.normalizeSpelliconList(spellicon)
    local out = {}
    local seen = {}
    local function add(v)
        local n = tonumber(v)
        if n and n > 0 and not seen[n] then
            seen[n] = true
            out[#out + 1] = n
        end
    end
    if type(spellicon) == 'table' then
        for _, v in ipairs(spellicon) do add(v) end
    else
        add(spellicon)
    end
    return out
end

function M.phaseToScope(phase)
    return PHASE_TO_SCOPE[phase]
end

function M.sectionToKind(section)
    return KIND_BY_SECTION[section]
end

--- MtList ∪ OtList names for LIST tank/offtank watchers.
function M.tankOtWatchNames()
    local seen = {}
    local out = {}
    local function addList(list)
        if type(list) ~= 'table' then return end
        for _, name in ipairs(list) do
            if type(name) == 'string' and name ~= '' then
                local key = name:lower()
                if not seen[key] then
                    seen[key] = true
                    out[#out + 1] = name
                end
            end
        end
    end
    addList(rolelists.getMtList())
    addList(rolelists.getOtList())
    return out
end

local function classesFromValidTargets(validTgts)
    if type(validTgts) ~= 'table' or #validTgts == 0 then
        return {}
    end
    local out = {}
    for _, c in ipairs(validTgts) do
        if type(c) == 'string' and c ~= '' and c:lower() ~= 'all' then
            out[#out + 1] = c:upper()
        end
    end
    return out
end

local function spellIdForEntry(entry)
    if not entry or not entry.spell then return nil end
    local id = spellutils.GetSpellId(entry)
    if id and id > 0 then return id end
    local ok, sid = pcall(function() return mq.TLO.Spell(entry.spell).ID() end)
    if ok and sid and sid > 0 then return sid end
    return nil
end

local function forEachWatcherPhase(band, listNames, onPhase)
    local tp = band and band.targetphase
    if type(tp) ~= 'table' then return end
    local classes = classesFromValidTargets(band.validtargets)
    local did = {}
    for _, phase in ipairs(tp) do
        local scope = PHASE_TO_SCOPE[phase]
        if scope and not did[scope] then
            if scope == 'LIST' then
                if #listNames > 0 then
                    onPhase(scope, phase, classes)
                    did[scope] = true
                end
            else
                onPhase(scope, phase, classes)
                did[scope] = true
            end
        end
    end
end

function M.registerHealWatchers()
    if not charinfo.ClearWatchers then return end
    charinfo.ClearWatchers('HEAL')
    local count = botconfig.getSpellCount('heal')
    local listNames = M.tankOtWatchNames()
    for i = 1, count do
        local entry = botconfig.getSpellEntry('heal', i)
        if entry and entry.enabled ~= false then
            local spellId = spellIdForEntry(entry)
            local bands = entry.bands
            if spellId and type(bands) == 'table' then
                for _, band in ipairs(bands) do
                    local minHp = band.min ~= nil and band.min or 0
                    local maxHp = band.max ~= nil and band.max or 100
                    forEachWatcherPhase(band, listNames, function(scope, _phase, classes)
                        charinfo.RegisterHealWatcher({
                            spellId = spellId,
                            scope = scope,
                            minHp = minHp,
                            maxHp = maxHp,
                            classes = (scope == 'LIST') and {} or classes,
                            names = (scope == 'LIST') and listNames or nil,
                        })
                    end)
                end
            end
        end
    end
end

function M.registerBuffWatchers()
    if not charinfo.ClearWatchers then return end
    charinfo.ClearWatchers('BUFF')
    local count = botconfig.getSpellCount('buff')
    local listNames = M.tankOtWatchNames()
    for i = 1, count do
        local entry = botconfig.getSpellEntry('buff', i)
        if entry and entry.enabled ~= false then
            local spellId = spellIdForEntry(entry)
            local equivIds = M.normalizeSpelliconList(entry.spellicon)
            entry.spellicon = equivIds
            local bands = entry.bands
            if spellId and type(bands) == 'table' then
                local height = tonumber(entry.height) or 0
                if height <= 0 and spellutils.IsShrinkSpell(entry) then
                    height = 2.4
                end
                for _, band in ipairs(bands) do
                    forEachWatcherPhase(band, listNames, function(scope, _phase, classes)
                        charinfo.RegisterBuffWatcher({
                            spellId = spellId,
                            scope = scope,
                            classes = (scope == 'LIST') and {} or classes,
                            names = (scope == 'LIST') and listNames or nil,
                            equivIds = equivIds,
                            height = height,
                        })
                    end)
                end
            end
        end
    end
end

local function cureTypesFromEntry(entry)
    local ct = entry and entry.curetype
    if type(ct) ~= 'table' or #ct == 0 then return { 'POISON' } end
    local out = {}
    for _, t in ipairs(ct) do
        if type(t) == 'string' then
            local u = t:upper()
            if u == 'ALL' then
                return { 'POISON', 'DISEASE', 'CURSE', 'CORRUPTION' }
            end
            out[#out + 1] = u
        end
    end
    return out
end

function M.registerCureWatchers()
    if not charinfo.ClearWatchers then return end
    charinfo.ClearWatchers('CURE')
    local count = botconfig.getSpellCount('cure')
    local listNames = M.tankOtWatchNames()
    for i = 1, count do
        local entry = botconfig.getSpellEntry('cure', i)
        if entry and entry.enabled ~= false then
            local spellId = spellIdForEntry(entry)
            local cureTypes = cureTypesFromEntry(entry)
            local bands = entry.bands
            if spellId and type(bands) == 'table' then
                for _, band in ipairs(bands) do
                    forEachWatcherPhase(band, listNames, function(scope, _phase, classes)
                        for _, cureType in ipairs(cureTypes) do
                            charinfo.RegisterCureWatcher({
                                spellId = spellId,
                                cureType = cureType,
                                scope = scope,
                                classes = (scope == 'LIST') and {} or classes,
                                names = (scope == 'LIST') and listNames or nil,
                            })
                        end
                    end)
                end
            end
        end
    end
end

--- True if spawnId is in GetWatchList(kind, scope, spellId).
--- Uses a short-lived cache so repeated membership probes in one tick avoid re-fetch/linear scan.
local _watchListCache = {} -- key -> { set = {[id]=true}, at = ms }
local WATCH_LIST_CACHE_MS = 50

local function watchListKey(kind, scope, spellId)
    return tostring(kind) .. '\0' .. tostring(scope) .. '\0' .. tostring(spellId)
end

local function watchListIdSet(kind, scope, spellId)
    if not spellId or not charinfo.GetWatchList then return nil end
    local key = watchListKey(kind, scope, spellId)
    local now = mq.gettime()
    local hit = _watchListCache[key]
    if hit and (now - hit.at) < WATCH_LIST_CACHE_MS then
        return hit.set
    end
    local ids = charinfo.GetWatchList(kind, scope, spellId)
    local set = {}
    if type(ids) == 'table' then
        for _, id in ipairs(ids) do
            if id then set[id] = true end
        end
    end
    _watchListCache[key] = { set = set, at = now }
    return set
end

function M.watchListHas(kind, scope, spellId, spawnId)
    if not spawnId or spawnId <= 0 or not spellId then return false end
    local set = watchListIdSet(kind, scope, spellId)
    return set ~= nil and set[spawnId] == true
end

--- Minute-cached: any group member who is not a CharInfo peer.
local NONPEER_REFRESH_MS = 60000
local _nonPeerAt = 0
local _nonPeerFlag = false
local _nonPeerMembers = {} -- { { id, name }, ... }

local function refreshNonPeerGroupMembers()
    local now = mq.gettime()
    if now - _nonPeerAt < NONPEER_REFRESH_MS and _nonPeerAt > 0 then
        return
    end
    _nonPeerAt = now
    _nonPeerFlag = false
    _nonPeerMembers = {}
    local n = mq.TLO.Group.Members()
    if not n or n <= 0 then return end
    for i = 1, n do
        local member = mq.TLO.Group.Member(i)
        local name = member and member.Name()
        if name and name ~= '' and not charinfo.GetInfo(name) then
            local id = member.ID and member.ID()
            if id and id > 0 then
                _nonPeerFlag = true
                _nonPeerMembers[#_nonPeerMembers + 1] = { id = id, name = name }
            end
        end
    end
end

--- True when the last refresh found at least one non-peer group member.
function M.hasNonPeerGroupMembers()
    refreshNonPeerGroupMembers()
    return _nonPeerFlag
end

--- Cached non-peer group members from the last refresh (empty when flag is false).
--- @return table[] list of { id, name }
function M.getNonPeerGroupMembers()
    refreshNonPeerGroupMembers()
    if not _nonPeerFlag then return {} end
    return _nonPeerMembers
end

--- Build target entries from watchlist for a phase.
function M.targetsFromWatchList(kind, phase, spellId)
    local scope = PHASE_TO_SCOPE[phase]
    if not scope or scope == 'GRPAGG' or not charinfo.GetWatchList then return {} end
    local ids = charinfo.GetWatchList(kind, scope, spellId)
    if type(ids) ~= 'table' then return {} end
    local idSet = {}
    for _, id in ipairs(ids) do idSet[id] = true end

    local out = {}
    if phase == 'tank' then
        local mtName = tankrole.GetMainTankName()
        if mtName and mtName ~= '' then
            local peer = charinfo.GetInfo(mtName)
            local id = peer and peer.ID
            if (not id or id <= 0) then
                id = mq.TLO.Spawn('pc =' .. mtName).ID()
            end
            if id and id > 0 and idSet[id] then
                out[#out + 1] = { id = id, targethit = 'tank', name = mtName }
            end
        end
        return out
    end
    if phase == 'offtank' then
        local czactor = require('lib.czactor')
        for _, ot in ipairs(czactor.getActiveOfftanks()) do
            local peer = charinfo.GetInfo(ot.name)
            local id = peer and peer.ID
            if (not id or id <= 0) then
                id = mq.TLO.Spawn('pc =' .. ot.name).ID()
            end
            if id and id > 0 and idSet[id] then
                out[#out + 1] = { id = id, targethit = 'offtank', name = ot.name }
            end
        end
        return out
    end

    for _, id in ipairs(ids) do
        if id and id > 0 then
            out[#out + 1] = { id = id, targethit = phase }
        end
    end
    return out
end

--- Union of watchlist targets across all spells in section that have this phase.
function M.unionTargetsForPhase(section, phase, spellCount, bandHasPhaseFn)
    local kind = KIND_BY_SECTION[section]
    local scope = PHASE_TO_SCOPE[phase]
    if not kind or not scope or scope == 'GRPAGG' then return {} end
    local seen = {}
    local out = {}
    for i = 1, spellCount do
        if bandHasPhaseFn(i, phase) then
            local entry = botconfig.getSpellEntry(section, i)
            local spellId = spellIdForEntry(entry)
            if spellId then
                for _, t in ipairs(M.targetsFromWatchList(kind, phase, spellId)) do
                    if t.id and not seen[t.id] then
                        seen[t.id] = true
                        out[#out + 1] = t
                    end
                end
            end
        end
    end
    return out
end

--- GRPAGG readiness: peerCount (+ optional non-peer needs) vs tarcnt with self-as-tiebreaker.
---@param nonPeerNeeds number|nil extra needy non-peer group members (default 0)
function M.grpAggShouldCast(kind, spellId, tarcnt, selfPassesFn, nonPeerNeeds)
    local need = tonumber(tarcnt) or 1
    local peerCount = 0
    if charinfo.GetWatchCount then
        peerCount = charinfo.GetWatchCount(kind, 'GRPAGG', spellId) or 0
    end
    local total = peerCount + (tonumber(nonPeerNeeds) or 0)
    if total >= need then return true end
    if total == need - 1 then
        return selfPassesFn and selfPassesFn() == true
    end
    return false
end

function M.interruptScopeForTargethit(targethit)
    return PHASE_TO_SCOPE[targethit]
end

function M.spellIdForEntry(entry)
    return spellIdForEntry(entry)
end

return M
