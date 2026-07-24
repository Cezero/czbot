-- Resolves Main Tank (MT) vs Main Assist (MA) for the bot.
-- MT = who gets heals, mtSticky follow rules, and onlyMT abilities (taunt; also OT engage when off-tanking). MT never picks camp mobs.
-- MA = who selects targets from MobList (named-first, puller priority); DPS/offtank/non-sticky MT follow MA.
-- "automatic" resolves locally: EQ Group/Raid primary roles, then ma_list/mt_list fallback.
-- ma_update/mt_update (manual) overrides take precedence until the named PC is unavailable.
-- Automatic resolution is cached until invalidation or the cached candidate becomes unavailable.
-- A throttled refresh re-resolves every 2s so higher-priority MA/MT can reclaim the role after rez.

local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')
local charinfo = require("plugin.charinfo")
local charinfoutils = require('lib.charinfoutils')
local auto_ma_mt = require('lib.auto_ma_mt')
local log = require('lib.log')

local tankrole = {}

local _maCache = {}
local _mtCache = {}
local _leashGen = 0
local REFRESH_INTERVAL_MS = 2000
local _nextRefreshAt = 0
local _tickMemo = {
    assistName = nil,
    tankName = nil,
    assistResolved = false,
    tankResolved = false,
    maListGen = nil,
    mtListGen = nil,
    leashGen = nil,
}
local maybeRefreshAutomaticCache

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
    _tickMemo.maListGen = nil
    _tickMemo.mtListGen = nil
    _tickMemo.leashGen = nil
    maybeRefreshAutomaticCache()
end

function tankrole.bumpLeashGen()
    _leashGen = _leashGen + 1
    tankrole.invalidateAll()
end

function tankrole.invalidateMa()
    _maCache = {}
    _tickMemo.assistResolved = false
    _tickMemo.assistName = nil
    _tickMemo.maListGen = nil
    _tickMemo.leashGen = nil
end

function tankrole.invalidateMt()
    _mtCache = {}
    _tickMemo.tankResolved = false
    _tickMemo.tankName = nil
    _tickMemo.mtListGen = nil
    _tickMemo.leashGen = nil
end

function tankrole.invalidateAll()
    tankrole.invalidateMa()
    tankrole.invalidateMt()
end

local function isCandidateAvailable(name, requireLeash)
    return auto_ma_mt.isCandidateAvailable(name, requireLeash)
end

local function firstAvailableFromList(list, requireLeash)
    return auto_ma_mt.firstAvailableFromList(list, requireLeash)
end

local function firstAvailableFromMtList(list)
    return auto_ma_mt.firstAvailableFromMtList(list)
end

local function inRaid()
    return mq.TLO.Raid.Members() and mq.TLO.Raid.Members() > 0
end

--- True when not in a raid and not in a group (no other group members).
local function isUngrouped()
    if inRaid() then return false end
    return (mq.TLO.Group.Members() or 0) == 0
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
        peerZone = ctx.peerZone,
        requireLeash = requireLeash,
        leash = leash,
        leashOk = leashOk,
    }
end

local function summarizeMaPath()
    local manual = auto_ma_mt.getManualMaOverrideName()
    if manual then return 'manual override: ' .. manual end
    local raid = inRaid()
    local primary = getMaPrimaryTlo()
    if primary and isCandidateAvailable(primary, false) then
        return string.format('primary available (%s MA): %s', raid and 'raid' or 'group', primary)
    end
    local fallback = firstAvailableFromList(state.getRunconfig().MaList, not raid)
    if fallback then return 'ma_list fallback: ' .. fallback end
    if primary then return 'primary unavailable, no ma_list match: ' .. primary end
    return 'no MA resolved'
end

local function summarizeMtPath()
    local manual = auto_ma_mt.getManualMtOverrideName()
    if manual then return 'manual override: ' .. manual end
    if not inRaid() then
        local primary = getMtPrimaryTlo()
        if primary and isCandidateAvailable(primary, false) then
            return 'group MainTank: ' .. primary
        end
        if primary then
            local fallback = firstAvailableFromMtList(state.getRunconfig().MtList)
            if fallback then return 'group MT unavailable, mt_list fallback: ' .. fallback end
            return 'group MT unavailable, no mt_list match'
        end
    else
        local fallback = firstAvailableFromMtList(state.getRunconfig().MtList)
        if fallback then return 'raid mt_list: ' .. fallback end
        return 'raid mt_list walk: no match'
    end
    local fallback = firstAvailableFromMtList(state.getRunconfig().MtList)
    if fallback then return 'mt_list only: ' .. fallback end
    return 'no MT resolved'
end

local function printListAudit(label, list, listRequireLeash)
    local count = type(list) == 'table' and #list or 0
    printf('  %s (%d entries):', label, count)
    if count == 0 then
        printf('    (empty)')
        return
    end
    local useLeash = listRequireLeash ~= false
    for i, name in ipairs(list) do
        local primary = auditCandidate(name, false)
        local listRule = auditCandidate(name, useLeash)
        local distStr = primary.distance and string.format('%.1f', primary.distance) or 'nil'
        local peerZoneStr = primary.peerZone and tostring(primary.peerZone) or 'nil'
        printf('    [%d] %s  source=%s  alive=%s  sameZone=%s  dist=%s  peerZone=%s',
            i, tostring(name),
            tostring(primary.source or 'nil'),
            primary.alive and 'yes' or 'no',
            primary.sameZone and 'yes' or 'no',
            distStr,
            peerZoneStr)
        printf('        primary (no leash): %s',
            primary.ok and 'PASS' or 'FAIL')
        if useLeash then
            printf('        list (leash<=%s): %s',
                tostring(listRule.leash),
                listRule.ok and 'PASS' or 'FAIL')
        else
            printf('        list (in-zone only): %s',
                listRule.ok and 'PASS' or 'FAIL')
        end
    end
end

local function resolveAutomaticAssistFull()
    local raid = inRaid()
    local primaryTlo = getMaPrimaryTlo()
    local meta = { primaryTlo = primaryTlo, inRaid = raid }

    local manual = auto_ma_mt.getManualMaOverrideName()
    if manual then
        meta.name = manual
        meta.source = 'manual'
        return meta
    end

    local name, source = auto_ma_mt.topMaCandidateInZone()
    meta.name = name
    meta.source = source
    return meta
end

---@return table { name: string|nil, source: string|nil, primaryTlo: string|nil, inRaid: boolean }
local function resolveAutomaticTankFull()
    local raid = inRaid()
    local primaryTlo = getMtPrimaryTlo()
    local meta = { primaryTlo = primaryTlo, inRaid = raid }

    local manual = auto_ma_mt.getManualMtOverrideName()
    if manual then
        meta.name = manual
        meta.source = 'manual'
        return meta
    end

    local name, source = auto_ma_mt.topMtCandidateInZone()
    meta.name = name
    meta.source = source
    return meta
end

local function isCachedMaValid(cache)
    if not cache.name or not cache.source then return false end
    if inRaid() ~= cache.inRaid then return false end
    if getMaPrimaryTlo() ~= cache.primaryTlo then return false end
    if auto_ma_mt.getMaListGen() ~= cache.listGen then return false end
    if _leashGen ~= cache.leashGen then return false end

    if cache.source == 'manual' then
        local o = state.getRunconfig().ActorMaOverride
        return o and o.reason == 'manual' and auto_ma_mt.isActorHolderAvailable(o, false)
    end
    if cache.source == 'primary' then
        return isCandidateAvailable(cache.name, false)
    end
    if cache.source == 'list' then
        return isCandidateAvailable(cache.name, not inRaid())
    end
    return false
end

local function isCachedMtValid(cache)
    if not cache.name or not cache.source then return false end
    if inRaid() ~= cache.inRaid then return false end
    if getMtPrimaryTlo() ~= cache.primaryTlo then return false end
    if auto_ma_mt.getMtListGen() ~= cache.listGen then return false end
    if _leashGen ~= cache.leashGen then return false end

    if cache.source == 'manual' then
        local o = state.getRunconfig().ActorMtOverride
        return o and o.reason == 'manual' and auto_ma_mt.isActorHolderAvailable(o, false)
    end
    if cache.source == 'primary' then
        return isCandidateAvailable(cache.name, false)
    end
    if cache.source == 'list' then
        return isCandidateAvailable(cache.name, false)
    end
    return false
end

local function storeMaCache(result)
    _maCache = {
        name = result.name,
        source = result.source,
        primaryTlo = result.primaryTlo,
        inRaid = result.inRaid,
        listGen = auto_ma_mt.getMaListGen(),
        leashGen = _leashGen,
    }
end

local function storeMtCache(result)
    _mtCache = {
        name = result.name,
        source = result.source,
        primaryTlo = result.primaryTlo,
        inRaid = result.inRaid,
        listGen = auto_ma_mt.getMtListGen(),
        leashGen = _leashGen,
    }
end

local function getEffectiveAssistSetting(rc)
    local name = rc.AssistName
    if name == nil or name == '' then
        name = rc.TankName
    end
    return name
end

local function getEffectiveTankSetting(rc)
    local name = rc.TankName
    if name == nil or name == '' then
        name = rc.AssistName
    end
    return name
end

maybeRefreshAutomaticCache = function()
    local now = mq.gettime()
    if now < _nextRefreshAt then return end
    _nextRefreshAt = now + REFRESH_INTERVAL_MS

    auto_ma_mt.sweepStaleManualRoleOverrides()

    local rc = state.getRunconfig()
    local assistSetting = getEffectiveAssistSetting(rc)
    if assistSetting == 'automatic' then
        local oldMa = _maCache.name
        local oldSource = _maCache.source
        local fresh = resolveAutomaticAssistFull()
        if fresh.name ~= oldMa or fresh.source ~= oldSource then
            log.say('MA switched to %s (was %s)', tostring(fresh.name or '(nil)'), tostring(oldMa or '(nil)'))
            storeMaCache(fresh)
        end
    end
    if getEffectiveTankSetting(rc) == 'automatic' then
        local oldMt = _mtCache.name
        local oldSource = _mtCache.source
        local fresh = resolveAutomaticTankFull()
        if fresh.name ~= oldMt or fresh.source ~= oldSource then
            log.say('MT switched to %s (was %s)', tostring(fresh.name or '(nil)'), tostring(oldMt or '(nil)'))
            storeMtCache(fresh)
            if fresh.name and fresh.name ~= oldMt then
                local chchain = require('lib.chchain')
                if chchain.syncCurtankFromMtName then
                    chchain.syncCurtankFromMtName(fresh.name, 'automatic')
                end
            end
        end
    end
end

local function resolveAutomaticAssistName()
    if _tickMemo.assistResolved
        and _tickMemo.maListGen == auto_ma_mt.getMaListGen()
        and _tickMemo.leashGen == _leashGen then
        return _tickMemo.assistName
    end

    if _maCache.name and isCachedMaValid(_maCache) then
        _tickMemo.assistName = _maCache.name
        _tickMemo.assistResolved = true
        _tickMemo.maListGen = auto_ma_mt.getMaListGen()
        _tickMemo.leashGen = _leashGen
        return _maCache.name
    end

    local result = resolveAutomaticAssistFull()
    storeMaCache(result)
    _tickMemo.assistName = result.name
    _tickMemo.assistResolved = true
    _tickMemo.maListGen = auto_ma_mt.getMaListGen()
    _tickMemo.leashGen = _leashGen
    return result.name
end

local function resolveAutomaticTankName()
    if _tickMemo.tankResolved
        and _tickMemo.mtListGen == auto_ma_mt.getMtListGen()
        and _tickMemo.leashGen == _leashGen then
        return _tickMemo.tankName
    end

    if _mtCache.name and isCachedMtValid(_mtCache) then
        _tickMemo.tankName = _mtCache.name
        _tickMemo.tankResolved = true
        _tickMemo.mtListGen = auto_ma_mt.getMtListGen()
        _tickMemo.leashGen = _leashGen
        return _mtCache.name
    end

    local result = resolveAutomaticTankFull()
    local prev = _mtCache.name
    storeMtCache(result)
    if result.name and result.name ~= prev then
        local chchain = require('lib.chchain')
        if chchain.syncCurtankFromMtName then
            chchain.syncCurtankFromMtName(result.name, 'automatic')
        end
    end
    _tickMemo.tankName = result.name
    _tickMemo.tankResolved = true
    _tickMemo.mtListGen = auto_ma_mt.getMtListGen()
    _tickMemo.leashGen = _leashGen
    return result.name
end

--- Return the Main Assist's character name (who DPS/offtank follow). Reads AssistName from runconfig; if nil/empty, uses TankName for backward compat.
--- When ungrouped (no group/raid) and Assist/Tank are unset (or automatic resolves to nil), defaults to self.
---@return string|nil
function tankrole.GetAssistTargetName()
    local rc = state.getRunconfig()
    local name = rc.AssistName
    if name == nil or name == '' then
        name = rc.TankName
    end
    if name == nil or name == '' then
        if isUngrouped() then return mq.TLO.Me.Name() end
        return nil
    end
    if name == 'automatic' then
        local resolved = resolveAutomaticAssistName()
        if (not resolved or resolved == '') and isUngrouped() then return mq.TLO.Me.Name() end
        return resolved
    end
    if _tickMemo.assistResolved then
        return _tickMemo.assistName
    end
    _tickMemo.assistName = name
    _tickMemo.assistResolved = true
    return name
end

--- Return the Main Tank's character name (who gets heals). Reads TankName from runconfig.
--- When ungrouped (no group/raid) and Tank/Assist are unset (or automatic resolves to nil), defaults to self.
---@return string|nil
function tankrole.GetMainTankName()
    local rc = state.getRunconfig()
    local name = getEffectiveTankSetting(rc)
    if name == nil or name == '' then
        if isUngrouped() then return mq.TLO.Me.Name() end
        return nil
    end
    if name == 'automatic' then
        local resolved = resolveAutomaticTankName()
        if (not resolved or resolved == '') and isUngrouped() then return mq.TLO.Me.Name() end
        return resolved
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

--- Print automatic MA/MT resolution diagnostics (/cz tank status, /cz tankrole).
function tankrole.debugPrint()
    tankrole.invalidateAll()

    local rc = state.getRunconfig()
    local settings = botconfig.config.settings or {}
    local raid = inRaid()
    local raidMembers = mq.TLO.Raid.Members() or 0
    local effectiveLeash = getAnchorLeash()

    log.say('tankrole diagnostic')
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

    printListAudit('MaList (zone-local resolution walk)', rc.MaList, not raid)
    printListAudit('MtList (zone-local resolution walk)', rc.MtList, false)

    local topMa, topMaSrc, topMaIdx = auto_ma_mt.topMaCandidateInZone()
    local topMt, topMtSrc, topMtIdx = auto_ma_mt.topMtCandidateInZone()
    printf('  topMaCandidateInZone=%s source=%s idx=%s',
        tostring(topMa), tostring(topMaSrc), tostring(topMaIdx))
    printf('  topMtCandidateInZone=%s source=%s idx=%s',
        tostring(topMt), tostring(topMtSrc), tostring(topMtIdx))

    printf('  MA path: %s', summarizeMaPath())
    printf('  MT path: %s', summarizeMtPath())
    if rc.ActorMaOverride then
        printf('  Manual MA override: %s seq=%s publisher=%s reason=%s',
            tostring(rc.ActorMaOverride.name), tostring(rc.ActorMaOverride.seq),
            tostring(rc.ActorMaOverride.publisher), tostring(rc.ActorMaOverride.reason))
    else
        printf('  Manual MA override: (none)')
    end
    if rc.ActorMtOverride then
        printf('  Manual MT override: %s seq=%s publisher=%s reason=%s',
            tostring(rc.ActorMtOverride.name), tostring(rc.ActorMtOverride.seq),
            tostring(rc.ActorMtOverride.publisher), tostring(rc.ActorMtOverride.reason))
    else
        printf('  Manual MT override: (none)')
    end
end

return tankrole
