-- Shared automatic MA/MT list utilities: zone-local resolution, list walks, promotion.
-- Used by lib/tankrole.lua, lib/chchain.lua, and lib/rolelists.lua.
-- ma_list/mt_list generation counters invalidate tankrole automatic-resolution caches.

local mq = require('mq')
local botconfig = require('lib.config')
local charinfoutils = require('lib.charinfoutils')
local state = require('lib.state')

local auto_ma_mt = {}

local _maListGen = 0
local _mtListGen = 0

function auto_ma_mt.getMaListGen()
    return _maListGen
end

function auto_ma_mt.getMtListGen()
    return _mtListGen
end

function auto_ma_mt.bumpMaListGen()
    _maListGen = _maListGen + 1
end

function auto_ma_mt.bumpMtListGen()
    _mtListGen = _mtListGen + 1
end

local function getAnchorLeash()
    local settings = botconfig.config.settings
    return tonumber(settings.maAnchorLeash) or tonumber(settings.acleash) or 75
end

local function namesEqual(a, b)
    if not a or not b then return false end
    return string.lower(a) == string.lower(b)
end

local function myName()
    return mq.TLO.Me.Name()
end

local function inRaid()
    return mq.TLO.Raid.Members() and mq.TLO.Raid.Members() > 0
end

local function meAlive()
    return not mq.TLO.Me.Dead() and not mq.TLO.Me.Hovering() and (mq.TLO.Me.PctHPs() or 0) > 0
end

function auto_ma_mt.isCandidateAvailable(name, requireLeash)
    if not name or name == '' then return false end
    -- Self: trust live Me TLOs, never MQCharinfo peer snapshots (those flap under load
    -- and made the MA bot's own Assist Name oscillate between '-' and self).
    if namesEqual(name, myName()) then
        if not meAlive() then return false end
        return true
    end
    local ctx = charinfoutils.getLeaderContext(name)
    if not ctx or not ctx.alive or not ctx.sameZone then return false end
    if requireLeash then
        local leash = getAnchorLeash()
        local dist = charinfoutils.leaderDistance2D(ctx)
        if not dist or dist > leash then return false end
    end
    return true
end

function auto_ma_mt.firstAvailableFromList(list, requireLeash)
    if type(list) ~= 'table' then return nil end
    for _, name in ipairs(list) do
        if auto_ma_mt.isCandidateAvailable(name, requireLeash) then return name end
    end
    return nil
end

function auto_ma_mt.firstAvailableFromMtList(list)
    return auto_ma_mt.firstAvailableFromList(list, false)
end

function auto_ma_mt.firstAvailableFromMaList(list)
    return auto_ma_mt.firstAvailableFromList(list, true)
end

function auto_ma_mt.indexInList(list, name)
    if type(list) ~= 'table' or not name or name == '' then return nil end
    for i, entry in ipairs(list) do
        if namesEqual(entry, name) then return i end
    end
    return nil
end

function auto_ma_mt.refreshRoleClaimEligibility()
    local rc = state.getRunconfig()
    local me = myName()
    rc.maEligible = me ~= nil and me ~= '' and auto_ma_mt.indexInList(rc.MaList, me) ~= nil
    rc.mtEligible = me ~= nil and me ~= '' and auto_ma_mt.indexInList(rc.MtList, me) ~= nil
end

function auto_ma_mt.promoteNameInList(list, name)
    if type(list) ~= 'table' or not name or name == '' then return list end
    local out = {}
    out[#out + 1] = name
    for _, entry in ipairs(list) do
        if not namesEqual(entry, name) then
            out[#out + 1] = entry
        end
    end
    return out
end

function auto_ma_mt.firstAliveFromIndex(list, startIdx, rangeCheckFn)
    if type(list) ~= 'table' or #list == 0 then return nil end
    startIdx = tonumber(startIdx) or 1
    if startIdx < 1 then startIdx = 1 end
    for idx = startIdx, #list do
        local name = list[idx]
        if name and name ~= '' then
            local sp = mq.TLO.Spawn('=' .. name)
            if sp and sp.Type() == 'PC' and sp.ID() and sp.ID() > 0 and not sp.Dead() and (sp.PctHPs() or 0) > 0 then
                local tid = sp.ID()
                if not rangeCheckFn or rangeCheckFn(tid) then
                    return tid, idx, name
                end
            end
        end
    end
    return nil
end

function auto_ma_mt.firstAliveMtFromIndex(list, startIdx, rangeCheckFn)
    return auto_ma_mt.firstAliveFromIndex(list, startIdx, rangeCheckFn)
end

function auto_ma_mt.maPrimaryTloName()
    if inRaid() then
        local n = mq.TLO.Raid.MainAssist and mq.TLO.Raid.MainAssist.Name and mq.TLO.Raid.MainAssist.Name()
        if n and n ~= '' then return n end
        return nil
    end
    local n = mq.TLO.Group.MainAssist and mq.TLO.Group.MainAssist.Name and mq.TLO.Group.MainAssist.Name()
    if n and n ~= '' then return n end
    return nil
end

function auto_ma_mt.mtPrimaryTloName()
    if inRaid() then return nil end
    local n = mq.TLO.Group.MainTank and mq.TLO.Group.MainTank.Name and mq.TLO.Group.MainTank.Name()
    if n and n ~= '' then return n end
    return nil
end

function auto_ma_mt.isSenderInMyGroup(sender)
    if not sender or sender == '' then return false end
    local me = myName()
    if namesEqual(sender, me) then return true end
    if inRaid() then return false end
    local idx = mq.TLO.Group.Member(sender).Index()
    return idx ~= nil and idx > 0
end

function auto_ma_mt.isSenderInMyRaid(sender)
    if not sender or sender == '' then return false end
    if namesEqual(sender, myName()) then return true end
    local raidMembers = mq.TLO.Raid.Members() or 0
    if raidMembers <= 0 then return false end
    for i = 1, raidMembers do
        if namesEqual(mq.TLO.Raid.Member(i).Name(), sender) then return true end
    end
    return false
end

--- Zone-local MA winner: primary then ma_list. Returns name, source ('primary'|'list'), listIndex.
function auto_ma_mt.topMaCandidateInZone()
    local primary = auto_ma_mt.maPrimaryTloName()
    if primary and auto_ma_mt.isCandidateAvailable(primary, false) then
        return primary, 'primary', 0
    end
    local list = state.getRunconfig().MaList
    if type(list) ~= 'table' then return nil end
    local requireLeash = not inRaid()
    for i, name in ipairs(list) do
        if auto_ma_mt.isCandidateAvailable(name, requireLeash) then
            return name, 'list', i
        end
    end
    return nil
end

--- Zone-local MT winner: group MainTank (non-raid) then mt_list.
function auto_ma_mt.topMtCandidateInZone()
    if not inRaid() then
        local primary = auto_ma_mt.mtPrimaryTloName()
        if primary and auto_ma_mt.isCandidateAvailable(primary, false) then
            return primary, 'primary', 0
        end
    end
    local list = state.getRunconfig().MtList
    if type(list) ~= 'table' then return nil end
    for i, name in ipairs(list) do
        if auto_ma_mt.isCandidateAvailable(name, false) then
            return name, 'list', i
        end
    end
    return nil
end

--- True when a manual override entry refers to a live, in-zone holder.
---@param override table|nil
---@param requireMaLeash boolean|nil when true, ma_list leash applies to the holder name
function auto_ma_mt.isActorHolderAvailable(override, requireMaLeash)
    if not override or not override.name or override.name == '' then return false end
    if override.expiresAt and mq.gettime() > override.expiresAt then return false end
    return auto_ma_mt.isCandidateAvailable(override.name, requireMaLeash == true)
end

function auto_ma_mt.getManualMaOverrideName()
    local o = state.getRunconfig().ActorMaOverride
    if not o or o.reason ~= 'manual' then return nil end
    if not auto_ma_mt.isActorHolderAvailable(o, false) then return nil end
    return o.name
end

function auto_ma_mt.getManualMtOverrideName()
    local o = state.getRunconfig().ActorMtOverride
    if not o or o.reason ~= 'manual' then return nil end
    if not auto_ma_mt.isActorHolderAvailable(o, false) then return nil end
    return o.name
end

--- Clear manual ma_update/mt_update overrides when the holder is unavailable or expired.
function auto_ma_mt.sweepStaleManualRoleOverrides()
    local rc = state.getRunconfig()
    if rc.ActorMaOverride and rc.ActorMaOverride.reason ~= 'manual' then
        rc.ActorMaOverride = nil
    elseif rc.ActorMaOverride and rc.ActorMaOverride.reason == 'manual'
        and not auto_ma_mt.isActorHolderAvailable(rc.ActorMaOverride, false) then
        rc.ActorMaOverride = nil
    end
    if rc.ActorMtOverride and rc.ActorMtOverride.reason ~= 'manual' then
        rc.ActorMtOverride = nil
    elseif rc.ActorMtOverride and rc.ActorMtOverride.reason == 'manual'
        and not auto_ma_mt.isActorHolderAvailable(rc.ActorMtOverride, false) then
        rc.ActorMtOverride = nil
    end
end

function auto_ma_mt.handleMtOverride(name, reason)
    if not name or name == '' then return nil end
    local rc = state.getRunconfig()
    local list = rc.MtList
    if type(list) ~= 'table' then list = {} end

    if reason == 'manual' or reason == 'tank_swap' then
        rc.MtList = auto_ma_mt.promoteNameInList(list, name)
        botconfig.mutateCommon(function(common)
            common.mt_list = botconfig.copyStringList(rc.MtList)
        end)
        auto_ma_mt.bumpMtListGen()
        auto_ma_mt.refreshRoleClaimEligibility()
        return { index = 1, tank = name }
    end

    local idx = auto_ma_mt.indexInList(rc.MtList, name)
    if idx then
        return { index = idx, tank = name }
    end
    return { index = 1, tank = name }
end

return auto_ma_mt
