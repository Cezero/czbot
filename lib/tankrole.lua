-- Resolves Main Tank (MT) vs Main Assist (MA) for the bot.
-- MT = who gets heals, mtSticky follow rules, and onlyMT abilities (taunt; also OT engage when off-tanking). MT never picks camp mobs.
-- MA = who selects targets from MobList (named-first, puller priority); DPS/offtank/non-sticky MT follow MA.
-- "automatic" uses Group/Raid window roles: Group.MainTank, Group.MainAssist, Group.Puller.
-- Raid has MainAssist only; MainTank and Puller always come from Group.
-- When primary is unavailable, falls back to cz_common ma_list / mt_list (proximity-gated).

local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')
local charinfo = require("plugin.charinfo")
local charinfoutils = require('lib.charinfoutils')

local tankrole = {}

function tankrole.getAnchorLeash()
    local settings = botconfig.config.settings
    return tonumber(settings.maAnchorLeash) or tonumber(settings.acleash) or 75
end

local getAnchorLeash = tankrole.getAnchorLeash

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
    local primary
    if raid then
        primary = tloName(mq.TLO.Raid.MainAssist)
    else
        primary = tloName(mq.TLO.Group.MainAssist)
    end
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
        local primary = tloName(mq.TLO.Group.MainTank)
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

local function resolveAutomaticAssistName()
    local primary
    if inRaid() then
        local ma = mq.TLO.Raid.MainAssist
        if ma and ma.Name then primary = ma.Name() end
    else
        local gma = mq.TLO.Group.MainAssist
        if gma and gma.Name then primary = gma.Name() end
    end
    if primary and primary ~= '' then
        if isCandidateAvailable(primary, false) then
            return primary
        end
        local fallback = firstAvailableFromList(state.getRunconfig().MaList, true)
        if fallback then return fallback end
        return primary -- dead/unavailable: keep identity for lastAssistTargetId / engage cache
    end
    return firstAvailableFromList(state.getRunconfig().MaList, true)
end

local function resolveAutomaticTankName()
    if not inRaid() then
        local gmt = mq.TLO.Group.MainTank
        local primary = gmt and gmt.Name and gmt.Name() or nil
        if primary and primary ~= '' and isCandidateAvailable(primary, false) then
            return primary
        end
    end
    return firstAvailableFromList(state.getRunconfig().MtList, true)
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
