-- Resolves Main Tank (MT) vs Main Assist (MA) for the bot.
-- MT = who gets heals, mtSticky follow rules, and onlyMT abilities (taunt; also OT engage when off-tanking). MT never picks camp mobs.
-- MA = who selects targets from MobList (named-first, puller priority); DPS/offtank/non-sticky MT follow MA.
-- "automatic" uses Group/Raid window roles: Group.MainTank, Group.MainAssist, Group.Puller.
-- Raid has MainAssist only; MainTank and Puller always come from Group.
-- When primary is unavailable, falls back to cz_common ma_list / mt_list (proximity-gated).
-- Automatic resolution is cached until invalidation or the cached candidate becomes unavailable.

local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')
local charinfo = require("plugin.charinfo")
local charinfoutils = require('lib.charinfoutils')
local rolelists = require('lib.rolelists')

local tankrole = {}

local _maCache = {}
local _mtCache = {}
local _leashGen = 0
local _tickMemo = {
    assistName = nil,
    tankName = nil,
    assistResolved = false,
    tankResolved = false,
}

function tankrole.getAnchorLeash()
    local settings = botconfig.config.settings
    return tonumber(settings.maAnchorLeash) or tonumber(settings.acleash) or 75
end

local getAnchorLeash = tankrole.getAnchorLeash

function tankrole.beginTick()
    _tickMemo.assistResolved = false
    _tickMemo.tankResolved = false
    _tickMemo.assistName = nil
    _tickMemo.tankName = nil
end

function tankrole.bumpLeashGen()
    _leashGen = _leashGen + 1
    tankrole.invalidateAll()
end

function tankrole.invalidateMa()
    _maCache = {}
    _tickMemo.assistResolved = false
    _tickMemo.assistName = nil
end

function tankrole.invalidateMt()
    _mtCache = {}
    _tickMemo.tankResolved = false
    _tickMemo.tankName = nil
end

function tankrole.invalidateAll()
    tankrole.invalidateMa()
    tankrole.invalidateMt()
end

local function isCandidateAvailable(name, requireLeash)
    if not name or name == '' then return false end
    local ctx = charinfoutils.getLeaderContext(name)
    if not ctx or not ctx.alive or not ctx.sameZone then return false end
    if requireLeash then
        local leash = getAnchorLeash()
        if not ctx.distance or ctx.distance > leash then return false end
    end
    return true
end

local function firstAvailableFromList(list, requireLeash)
    if type(list) ~= 'table' then return nil end
    for _, name in ipairs(list) do
        if isCandidateAvailable(name, requireLeash) then return name end
    end
    return nil
end

local function inRaid()
    return mq.TLO.Raid.Members() and mq.TLO.Raid.Members() > 0
end

local function tloName(tlo)
    if not tlo or not tlo.Name then return nil end
    local name = tlo.Name()
    if not name or name == '' then return nil end
    return name
end

local function getMaPrimaryTlo()
    if inRaid() then return tloName(mq.TLO.Raid.MainAssist) end
    return tloName(mq.TLO.Group.MainAssist)
end

local function getMtPrimaryTlo()
    if inRaid() then return nil end
    return tloName(mq.TLO.Group.MainTank)
end

local function auditCandidate(name, requireLeash)
    if not name or name == '' then
        return { name = name, ok = false, reason = 'empty name' }
    end
    local ctx = charinfoutils.getLeaderContext(name)
    if not ctx then
        return {
            name = name,
            ok = false,
            reason = 'no leader context (charinfo/spawn)',
            source = nil,
            alive = false,
            sameZone = false,
            distance = nil,
            requireLeash = requireLeash,
            leash = getAnchorLeash(),
            leashOk = false,
        }
    end
    local leash = getAnchorLeash()
    local leashOk = not requireLeash or (ctx.distance ~= nil and ctx.distance <= leash)
    local ok = ctx.alive and ctx.sameZone and leashOk
    return {
        name = name,
        ok = ok,
        source = ctx.source,
        alive = ctx.alive,
        sameZone = ctx.sameZone,
        distance = ctx.distance,
        requireLeash = requireLeash,
        leash = leash,
        leashOk = leashOk,
    }
end

local function summarizeMaPath()
    local raid = inRaid()
    local primary = getMaPrimaryTlo()
    if primary then
        if isCandidateAvailable(primary, false) then
            return string.format('primary available (%s MA): %s', raid and 'raid' or 'group', primary)
        end
        local fallback = firstAvailableFromList(state.getRunconfig().MaList, true)
        if fallback then return 'ma_list fallback: ' .. fallback end
        return 'primary retention (unavailable): ' .. primary
    end
    local fallback = firstAvailableFromList(state.getRunconfig().MaList, true)
    if fallback then return 'ma_list only: ' .. fallback end
    return 'no MA resolved'
end

local function summarizeMtPath()
    if not inRaid() then
        local primary = getMtPrimaryTlo()
        if primary and isCandidateAvailable(primary, false) then
            return 'group MainTank: ' .. primary
        end
        if primary then
            local fallback = firstAvailableFromList(state.getRunconfig().MtList, true)
            if fallback then return 'group MT unavailable, mt_list fallback: ' .. fallback end
            return 'group MT unavailable, no mt_list match'
        end
    else
        local fallback = firstAvailableFromList(state.getRunconfig().MtList, true)
        if fallback then return 'raid mt_list: ' .. fallback end
        return 'raid mt_list walk: no match'
    end
    local fallback = firstAvailableFromList(state.getRunconfig().MtList, true)
    if fallback then return 'mt_list only: ' .. fallback end
    return 'no MT resolved'
end

local function printListAudit(label, list)
    local count = type(list) == 'table' and #list or 0
    printf('  %s (%d entries):', label, count)
    if count == 0 then
        printf('    (empty)')
        return
    end
    for i, name in ipairs(list) do
        local primary = auditCandidate(name, false)
        local listRule = auditCandidate(name, true)
        local distStr = primary.distance and string.format('%.1f', primary.distance) or 'nil'
        printf('    [%d] %s  source=%s  alive=%s  sameZone=%s  dist=%s',
            i, tostring(name),
            tostring(primary.source or 'nil'),
            primary.alive and 'yes' or 'no',
            primary.sameZone and 'yes' or 'no',
            distStr)
        printf('        primary (no leash): %s',
            primary.ok and 'PASS' or 'FAIL')
        printf('        list (leash<=%s): %s',
            tostring(listRule.leash),
            listRule.ok and 'PASS' or 'FAIL')
    end
end

---@return table { name: string|nil, source: string, primaryTlo: string|nil, inRaid: boolean }
local function resolveAutomaticAssistFull()
    local raid = inRaid()
    local primaryTlo = getMaPrimaryTlo()
    local meta = { primaryTlo = primaryTlo, inRaid = raid }

    if primaryTlo then
        if isCandidateAvailable(primaryTlo, false) then
            meta.name = primaryTlo
            meta.source = 'primary'
            return meta
        end
        local fallback = firstAvailableFromList(state.getRunconfig().MaList, true)
        if fallback then
            meta.name = fallback
            meta.source = 'list'
            return meta
        end
        meta.name = primaryTlo
        meta.source = 'primary_retained'
        return meta
    end

    local fallback = firstAvailableFromList(state.getRunconfig().MaList, true)
    meta.name = fallback
    meta.source = fallback and 'list' or nil
    return meta
end

---@return table { name: string|nil, source: string|nil, primaryTlo: string|nil, inRaid: boolean }
local function resolveAutomaticTankFull()
    local raid = inRaid()
    local primaryTlo = getMtPrimaryTlo()
    local meta = { primaryTlo = primaryTlo, inRaid = raid }

    if not raid and primaryTlo and isCandidateAvailable(primaryTlo, false) then
        meta.name = primaryTlo
        meta.source = 'primary'
        return meta
    end

    local fallback = firstAvailableFromList(state.getRunconfig().MtList, true)
    meta.name = fallback
    meta.source = fallback and 'list' or nil
    return meta
end

local function isCachedMaValid(cache)
    if not cache.name or not cache.source then return false end
    if inRaid() ~= cache.inRaid then return false end
    if getMaPrimaryTlo() ~= cache.primaryTlo then return false end
    if rolelists.getMaListGen() ~= cache.listGen then return false end
    if _leashGen ~= cache.leashGen then return false end

    if cache.source == 'primary' then
        return isCandidateAvailable(cache.name, false)
    end
    if cache.source == 'list' then
        return isCandidateAvailable(cache.name, true)
    end
    if cache.source == 'primary_retained' then
        if cache.name ~= cache.primaryTlo then return false end
        if cache.primaryTlo and isCandidateAvailable(cache.primaryTlo, false) then return false end
        if firstAvailableFromList(state.getRunconfig().MaList, true) then return false end
        return true
    end
    return false
end

local function isCachedMtValid(cache)
    if not cache.name or not cache.source then return false end
    if inRaid() ~= cache.inRaid then return false end
    if getMtPrimaryTlo() ~= cache.primaryTlo then return false end
    if rolelists.getMtListGen() ~= cache.listGen then return false end
    if _leashGen ~= cache.leashGen then return false end

    if cache.source == 'primary' then
        return isCandidateAvailable(cache.name, false)
    end
    if cache.source == 'list' then
        return isCandidateAvailable(cache.name, true)
    end
    return false
end

local function storeMaCache(result)
    _maCache = {
        name = result.name,
        source = result.source,
        primaryTlo = result.primaryTlo,
        inRaid = result.inRaid,
        listGen = rolelists.getMaListGen(),
        leashGen = _leashGen,
    }
end

local function storeMtCache(result)
    _mtCache = {
        name = result.name,
        source = result.source,
        primaryTlo = result.primaryTlo,
        inRaid = result.inRaid,
        listGen = rolelists.getMtListGen(),
        leashGen = _leashGen,
    }
end

local function resolveAutomaticAssistName()
    if _tickMemo.assistResolved then
        return _tickMemo.assistName
    end

    if _maCache.name and isCachedMaValid(_maCache) then
        _tickMemo.assistName = _maCache.name
        _tickMemo.assistResolved = true
        return _maCache.name
    end

    local result = resolveAutomaticAssistFull()
    storeMaCache(result)
    _tickMemo.assistName = result.name
    _tickMemo.assistResolved = true
    return result.name
end

local function resolveAutomaticTankName()
    if _tickMemo.tankResolved then
        return _tickMemo.tankName
    end

    if _mtCache.name and isCachedMtValid(_mtCache) then
        _tickMemo.tankName = _mtCache.name
        _tickMemo.tankResolved = true
        return _mtCache.name
    end

    local result = resolveAutomaticTankFull()
    storeMtCache(result)
    _tickMemo.tankName = result.name
    _tickMemo.tankResolved = true
    return result.name
end

--- Return the Main Assist's character name (who DPS/offtank follow). Reads AssistName from runconfig; if nil/empty, uses TankName for backward compat.
---@return string|nil
function tankrole.GetAssistTargetName()
    local rc = state.getRunconfig()
    local name = rc.AssistName
    if name == nil or name == '' then
        name = rc.TankName
    end
    if name == nil or name == '' then return nil end
    if name == 'automatic' then
        return resolveAutomaticAssistName()
    end
    if _tickMemo.assistResolved then
        return _tickMemo.assistName
    end
    _tickMemo.assistName = name
    _tickMemo.assistResolved = true
    return name
end

--- Return the Main Tank's character name (who gets heals). Reads TankName from runconfig.
---@return string|nil
function tankrole.GetMainTankName()
    local name = state.getRunconfig().TankName
    if name == nil or name == '' then return nil end
    if name == 'automatic' then
        return resolveAutomaticTankName()
    end
    if _tickMemo.tankResolved then
        return _tickMemo.tankName
    end
    _tickMemo.tankName = name
    _tickMemo.tankResolved = true
    return name
end

--- Return the Puller's current target ID when this toon is the MA (puller priority in selectMATarget). Group only; Raid has no Puller.
---@return number|nil
function tankrole.GetPullerTargetID()
    if not tankrole.AmIMainAssist() then return nil end
    local puller = mq.TLO.Group.Puller
    if not puller or not puller.Name then return nil end
    local pullerName = puller.Name()
    if not pullerName or pullerName == '' then return nil end
    local info = charinfo.GetInfo(pullerName)
    if info and info.Target and info.Target.ID then return info.Target.ID end
    return nil
end

--- True when this character is the Main Tank (resolved from TankName / Group.MainTank).
---@return boolean
function tankrole.AmIMainTank()
    return tankrole.GetMainTankName() == mq.TLO.Me.Name()
end

--- True when this character is the Main Assist (resolved from AssistName / Group or Raid MainAssist). Used so the MA bot runs selectMATarget.
---@return boolean
function tankrole.AmIMainAssist()
    return tankrole.GetAssistTargetName() == mq.TLO.Me.Name()
end

--- Print automatic MA/MT resolution diagnostics (/cz tankrole).
function tankrole.debugPrint()
    tankrole.invalidateAll()

    local rc = state.getRunconfig()
    local settings = botconfig.config.settings or {}
    local raid = inRaid()
    local raidMembers = mq.TLO.Raid.Members() or 0
    local effectiveLeash = getAnchorLeash()

    printf('\ayCZBot:\ax tankrole diagnostic')
    printf('  inRaid: %s (Raid.Members=%s)', raid and 'yes' or 'no', tostring(raidMembers))
    printf('  rc.TankName=%s  rc.AssistName=%s',
        tostring(rc.TankName), tostring(rc.AssistName))
    printf('  settings.TankName=%s  settings.AssistName=%s',
        tostring(settings.TankName), tostring(settings.AssistName))
    printf('  maAnchorLeash=%s  acleash=%s  effective leash=%s',
        tostring(settings.maAnchorLeash), tostring(settings.acleash), tostring(effectiveLeash))
    printf('  TLO Raid.MainAssist=%s  Group.MainAssist=%s  Group.MainTank=%s',
        tostring(tloName(mq.TLO.Raid.MainAssist)),
        tostring(tloName(mq.TLO.Group.MainAssist)),
        tostring(tloName(mq.TLO.Group.MainTank)))

    local assistName = tankrole.GetAssistTargetName()
    local tankName = tankrole.GetMainTankName()
    printf('  resolved Assist=%s  resolved Tank=%s',
        assistName and assistName or '(nil)',
        tankName and tankName or '(nil)')
    printf('  AmIMainAssist=%s  AmIMainTank=%s',
        tankrole.AmIMainAssist() and 'yes' or 'no',
        tankrole.AmIMainTank() and 'yes' or 'no')

    printListAudit('MaList', rc.MaList)
    printListAudit('MtList', rc.MtList)

    printf('  MA path: %s', summarizeMaPath())
    printf('  MT path: %s', summarizeMtPath())
end

return tankrole
