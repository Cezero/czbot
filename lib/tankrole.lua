-- Resolves Main Tank (MT) vs Main Assist (MA) for the bot.
-- MT = who gets heals, mtSticky follow rules, and onlyMT abilities (taunt; also OT engage when off-tanking). MT never picks camp mobs.
-- MA = who selects targets from MobList (named-first, puller priority); DPS/offtank/non-sticky MT follow MA.
-- "automatic" resolves locally: EQ Group/Raid primary roles, then ma_list/mt_list fallback.
-- ma_update/mt_update (manual) overrides take precedence until the named PC is unavailable.
-- Automatic resolution is cached until invalidation or the cached candidate becomes unavailable.
-- A throttled refresh re-resolves every 2s. MA may reclaim after rez. MT moves only forward during a fight.

local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')
local charinfo = require("plugin.charinfo")
local charinfoutils = require('lib.charinfoutils')
local auto_ma_mt = require('lib.auto_ma_mt')
local utils = require('lib.utils')
local log = require('lib.log')

local tankrole = {}

local _maCache = {}
local _mtCache = {}
local _leashGen = 0
local REFRESH_INTERVAL_MS = 2000
local MT_OOC_RESET_MS = 5000
local _nextRefreshAt = 0
-- Forward-only automatic MT cursor. Index 0 allows group MainTank; list names start at 1.
local _mtFloor = 0
local _mtListSig = nil
local _mtLockZone = nil
local _mtHeldName = nil
local _mtHeldSource = nil
local _mtOocSince = nil
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

local function namesEqual(a, b)
    if not a or not b then return false end
    return string.lower(a) == string.lower(b)
end

local function currentZone()
    local zone = mq.TLO.Zone.ShortName()
    if not zone or zone == '' then return nil end
    return zone
end

local function clearMtCursor()
    _mtFloor = 0
    _mtLockZone = nil
    _mtOocSince = nil
    _mtHeldName = nil
    _mtHeldSource = nil
end

local function mtListSignature()
    local list = state.getRunconfig().MtList
    if type(list) ~= 'table' then return '' end
    local parts = {}
    for i, name in ipairs(list) do
        parts[i] = string.lower(tostring(name or ''))
    end
    return table.concat(parts, '\0')
end

--- Clear the cursor when mt_list order changes. A generation bump with the same names (zone reload) keeps it.
local function syncMtFloorToListGen()
    local sig = mtListSignature()
    if _mtListSig == nil then
        _mtListSig = sig
        return
    end
    if sig ~= _mtListSig then
        _mtListSig = sig
        clearMtCursor()
    end
end

local function absentFromMtLockZone()
    if not _mtLockZone or _mtLockZone == '' then return false end
    local zone = currentZone()
    if not zone then return false end
    return not namesEqual(zone, _mtLockZone)
end

local function inPrimaryBindZone()
    if utils.isNearPrimaryBindPoint() then return true end
    local bindTlo = mq.TLO.Me.ZoneBound
    local bindZone = bindTlo and bindTlo.ShortName and bindTlo.ShortName()
    local zone = currentZone()
    if not bindZone or bindZone == '' or not zone then return false end
    return namesEqual(bindZone, zone)
end

local function anyMemberInAttack()
    local raid = inRaid()
    local count = raid and (mq.TLO.Raid.Members() or 0) or (mq.TLO.Group.Members() or 0)
    if count <= 0 then return false end
    local me = mq.TLO.Me.Name()
    for i = 1, count do
        local member = raid and mq.TLO.Raid.Member(i) or mq.TLO.Group.Member(i)
        local name = member and member.Name and member.Name()
        if name and name ~= '' and not namesEqual(name, me) then
            local ctx = charinfoutils.getLeaderContext(name)
            if ctx and ctx.sameZone and ctx.alive and ctx.inAttack then return true end
        end
    end
    return false
end

--- True while this fight should keep the forward MT cursor.
local function mtFightActive()
    if state.isCombatContextForBuff() then return true end
    if mq.TLO.Me.CombatState() == 'COMBAT' then return true end
    return anyMemberInAttack()
end

local function mtOocResetReady()
    if absentFromMtLockZone() then return false end
    if mtFightActive() then
        _mtOocSince = nil
        return false
    end
    local now = mq.gettime()
    if not _mtOocSince then
        _mtOocSince = now
        return false
    end
    return (now - _mtOocSince) >= MT_OOC_RESET_MS
end

local function rememberMtHold(name, source, index)
    if not name then return end
    _mtHeldName = name
    _mtHeldSource = source
    if index ~= nil then _mtFloor = index end
end

local function finishMt(meta)
    if not meta.name and not meta.source then
        meta.source = 'none'
    end
    return meta
end

---@return table { name: string|nil, source: string|nil, primaryTlo: string|nil, inRaid: boolean, syncReason: string|nil, wrapped: boolean|nil }
local function resolveAutomaticTankFull()
    local raid = inRaid()
    local primaryTlo = getMtPrimaryTlo()
    local meta = { primaryTlo = primaryTlo, inRaid = raid, wrapped = false, syncReason = 'automatic' }

    local manual = auto_ma_mt.getManualMtOverrideName()
    if manual then
        meta.name = manual
        meta.source = 'manual'
        return meta
    end

    syncMtFloorToListGen()

    if absentFromMtLockZone() then
        meta.name = _mtHeldName
        meta.source = _mtHeldSource or (_mtHeldName and 'list' or nil)
        return finishMt(meta)
    end

    if mtOocResetReady() then
        local hadCursor = _mtFloor > 0 or _mtLockZone ~= nil
        _mtLockZone = nil
        _mtOocSince = nil
        local name, source, index = auto_ma_mt.mtCandidateFromIndex(0)
        meta.name = name
        meta.source = source
        meta.syncReason = hadCursor and 'mt_reset' or 'automatic'
        if name then
            rememberMtHold(name, source, index or 0)
        else
            _mtFloor = 0
        end
        return finishMt(meta)
    end

    local name, source, index, wrapped = auto_ma_mt.mtCandidateFromIndex(_mtFloor)
    meta.name = name
    meta.source = source
    meta.wrapped = wrapped == true
    if meta.wrapped then meta.syncReason = 'mt_wrap' end
    if name then
        rememberMtHold(name, source, index)
    end
    return finishMt(meta)
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
    if not cache.source then return false end
    -- No living candidate. Reuse until the throttled refresh; do not scan the raid every tick.
    if cache.source == 'none' then
        if absentFromMtLockZone() then return false end
        if inRaid() ~= cache.inRaid then return false end
        if getMtPrimaryTlo() ~= cache.primaryTlo then return false end
        if auto_ma_mt.getMtListGen() ~= cache.listGen then return false end
        return true
    end
    if not cache.name then return false end
    if absentFromMtLockZone() and _mtHeldName and namesEqual(cache.name, _mtHeldName) then
        return true
    end
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
            local verb = fresh.wrapped and 'MT wrapped to %s (was %s)' or 'MT switched to %s (was %s)'
            log.say(verb, tostring(fresh.name or '(nil)'), tostring(oldMt or '(nil)'))
            storeMtCache(fresh)
            if fresh.name and fresh.name ~= oldMt then
                local chchain = require('lib.chchain')
                if chchain.syncCurtankFromMtName then
                    chchain.syncCurtankFromMtName(fresh.name, fresh.syncReason or 'automatic')
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

    if _mtCache.source and isCachedMtValid(_mtCache) then
        _tickMemo.tankName = _mtCache.name
        _tickMemo.tankResolved = true
        _tickMemo.mtListGen = auto_ma_mt.getMtListGen()
        _tickMemo.leashGen = _leashGen
        return _mtCache.name
    end

    local result = resolveAutomaticTankFull()
    if not result.source then result.source = 'none' end
    local prev = _mtCache.name
    storeMtCache(result)
    if result.name and result.name ~= prev then
        local chchain = require('lib.chchain')
        if chchain.syncCurtankFromMtName then
            chchain.syncCurtankFromMtName(result.name, result.syncReason or 'automatic')
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
        -- Bind (or any zone other than the fight) must not fall back to self when the held MT is elsewhere.
        if absentFromMtLockZone() then return resolved end
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

--- Advance the MT floor past this character when they die as the automatic MT.
--- Runs before the death reset clears the name cache, so a later resolve cannot keep them.
function tankrole.noteLocalMtDeath()
    local rc = state.getRunconfig()
    if getEffectiveTankSetting(rc) ~= 'automatic' then return end
    local me = mq.TLO.Me.Name()
    if not me or me == '' then return end
    local current = _mtCache.name or _mtHeldName
    if not current or not namesEqual(current, me) then return end
    local listIdx = auto_ma_mt.indexInList(rc.MtList, me)
    if listIdx then
        _mtFloor = listIdx + 1
    else
        _mtFloor = 1
    end
    local zone = currentZone()
    if zone then _mtLockZone = zone end
    _mtOocSince = nil
    if _mtHeldName and namesEqual(_mtHeldName, me) then
        _mtHeldName = nil
        _mtHeldSource = nil
    end
end

--- Alive zone changes with no death lock clear the cursor. A release to bind keeps it.
function tankrole.onZoneChanged()
    if not _mtLockZone then
        clearMtCursor()
        return
    end
    local zone = currentZone()
    if zone and namesEqual(zone, _mtLockZone) then
        _mtOocSince = nil
        return
    end
    local rc = state.getRunconfig()
    if rc.wasDeadOrHover or inPrimaryBindZone() then
        _mtOocSince = nil
        return
    end
    if mtFightActive() then
        if zone then _mtLockZone = zone end
        _mtOocSince = nil
        return
    end
    clearMtCursor()
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
    printf('  MT floor=%s lockZone=%s held=%s absent=%s fight=%s',
        tostring(_mtFloor),
        _mtLockZone or '(none)',
        tostring(_mtHeldName or '(none)'),
        absentFromMtLockZone() and 'yes' or 'no',
        mtFightActive() and 'yes' or 'no')

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
