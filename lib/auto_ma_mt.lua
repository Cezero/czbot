-- Shared automatic MA/MT list utilities: zone-local claims, list walks, promotion.
-- Used by lib/tankrole.lua, lib/czactor.lua, lib/chchain.lua, and lib/rolelists.lua.
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

local function myZone()
    return mq.TLO.Zone.ShortName() or ''
end

local function inRaid()
    return mq.TLO.Raid.Members() and mq.TLO.Raid.Members() > 0
end

local function isAutomaticAssist()
    local rc = state.getRunconfig()
    local name = rc.AssistName
    if name == nil or name == '' then name = rc.TankName end
    return name == 'automatic'
end

local function isAutomaticTank()
    local rc = state.getRunconfig()
    local name = rc.TankName
    if name == nil or name == '' then name = rc.AssistName end
    return name == 'automatic'
end

local function meAlive()
    return not mq.TLO.Me.Dead() and not mq.TLO.Me.Hovering() and (mq.TLO.Me.PctHPs() or 0) > 0
end

function auto_ma_mt.isCandidateAvailable(name, requireLeash)
    if not name or name == '' then return false end
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

local function rosterMemberNames()
    local names = {}
    local me = myName()
    if inRaid() then
        local raidMembers = mq.TLO.Raid.Members() or 0
        for i = 1, raidMembers do
            local n = mq.TLO.Raid.Member(i).Name()
            if n and n ~= '' then names[#names + 1] = n end
        end
        return names
    end
    if me and me ~= '' then names[#names + 1] = me end
    local groupMembers = mq.TLO.Group.Members() or 0
    for i = 1, groupMembers do
        local n = mq.TLO.Group.Member(i).Name()
        if n and n ~= '' and not namesEqual(n, me) then names[#names + 1] = n end
    end
    return names
end

local function memberAliveInMyZone(name)
    if namesEqual(name, myName()) then return meAlive() end
    local ctx = charinfoutils.getLeaderContext(name)
    return ctx and ctx.alive and ctx.sameZone
end

--- At least one other roster member in this zone, or solo in zone (advance party).
--- When requireMaLeash, nearest in-zone peer must be within maAnchorLeash.
function auto_ma_mt.hasRosterProximityInZone(requireMaLeash)
    local me = myName()
    local inZoneOthers = 0
    local closestDist = nil
    for _, name in ipairs(rosterMemberNames()) do
        if not namesEqual(name, me) and memberAliveInMyZone(name) then
            inZoneOthers = inZoneOthers + 1
            local ctx = charinfoutils.getLeaderContext(name)
            if ctx and ctx.distance then
                if not closestDist or ctx.distance < closestDist then
                    closestDist = ctx.distance
                end
            end
        end
    end
    if inZoneOthers == 0 then return true end
    if requireMaLeash then
        local leash = getAnchorLeash()
        return closestDist ~= nil and closestDist <= leash
    end
    return true
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

function auto_ma_mt.canClaimMa()
    return true
end

function auto_ma_mt.canClaimMt()
    return true
end

--- @return boolean claim
--- @return string|nil source 'primary'|'list'
--- @return number|nil listIndex
function auto_ma_mt.shouldClaimMa()
    if not isAutomaticAssist() or not meAlive() then return false end
    if not auto_ma_mt.canClaimMa() then return false end
    if not auto_ma_mt.hasRosterProximityInZone(true) then return false end
    local top, source, listIndex = auto_ma_mt.topMaCandidateInZone()
    if not top or not namesEqual(top, myName()) then return false end
    return true, source, listIndex
end

--- @return boolean claim
--- @return string|nil source 'primary'|'list'
--- @return number|nil listIndex
function auto_ma_mt.shouldClaimMt()
    if not isAutomaticTank() or not meAlive() then return false end
    if not auto_ma_mt.canClaimMt() then return false end
    if not auto_ma_mt.hasRosterProximityInZone(false) then return false end
    local top, source, listIndex = auto_ma_mt.topMtCandidateInZone()
    if not top or not namesEqual(top, myName()) then return false end
    return true, source, listIndex
end

function auto_ma_mt.groupLacksActiveMa()
    if inRaid() then return false end
    local rc = state.getRunconfig()
    local primary = auto_ma_mt.maPrimaryTloName()
    if (not primary or primary == '') and not rc.ActorMaOverride then
        return true
    end
    if rc.MaReleased then return true end
    local o = rc.ActorMaOverride
    if o and o.name and auto_ma_mt.isSenderInMyGroup(o.name) then return false end
    if primary and primary ~= '' and not rc.MaReleased then return false end
    return true
end

function auto_ma_mt.groupLacksActiveMt()
    if inRaid() then return false end
    local rc = state.getRunconfig()
    local primary = auto_ma_mt.mtPrimaryTloName()
    if (not primary or primary == '') and not rc.ActorMtOverride then
        return true
    end
    if rc.MtReleased then return true end
    local o = rc.ActorMtOverride
    if o and o.name and auto_ma_mt.isSenderInMyGroup(o.name) then return false end
    if primary and primary ~= '' and not rc.MtReleased then return false end
    return true
end

--- True when an actor override entry refers to a live, in-zone holder.
---@param override table|nil
---@param requireMaLeash boolean|nil when true, ma_list leash applies to the holder name
function auto_ma_mt.isActorHolderAvailable(override, requireMaLeash)
    if not override or not override.name or override.name == '' then return false end
    if override.expiresAt and mq.gettime() > override.expiresAt then return false end
    return auto_ma_mt.isCandidateAvailable(override.name, requireMaLeash == true)
end

--- Return stored actor override name when the holder is still available.
function auto_ma_mt.getActorMaOverrideName()
    local o = state.getRunconfig().ActorMaOverride
    if not auto_ma_mt.isActorHolderAvailable(o, false) then return nil end
    return o.name
end

function auto_ma_mt.getActorMtOverrideName()
    local o = state.getRunconfig().ActorMtOverride
    if not auto_ma_mt.isActorHolderAvailable(o, false) then return nil end
    return o.name
end

function auto_ma_mt.getActorMaOverrideNameIfAvailable()
    return auto_ma_mt.getActorMaOverrideName()
end

function auto_ma_mt.getActorMtOverrideNameIfAvailable()
    return auto_ma_mt.getActorMtOverrideName()
end

--- Clear actor overrides whose holder is no longer available (missed release_ma/release_mt).
---@return boolean clearedMa
---@return boolean clearedMt
function auto_ma_mt.sweepStaleActorOverrides()
    local rc = state.getRunconfig()
    local clearedMa, clearedMt = false, false
    if rc.ActorMaOverride and not auto_ma_mt.isActorHolderAvailable(rc.ActorMaOverride, false) then
        rc.ActorMaOverride = nil
        clearedMa = true
    end
    if rc.ActorMtOverride and not auto_ma_mt.isActorHolderAvailable(rc.ActorMtOverride, false) then
        rc.ActorMtOverride = nil
        clearedMt = true
    end
    return clearedMa, clearedMt
end

--- Evaluate whether this bot should publish im_*, release_*, or ask whos_*.
--- Holders publish im_* only when first claiming (not every tick). Sticky MT hold
--- skips release on brief post-zone eligibility dips. Peers without a usable actor
--- override ask whos_* (with czactor backoff) so the holder can answer; EQ/list are
--- claim eligibility only, not a reason to skip discovery.
---@param opts table|nil { trigger = 'release'|'periodic' }
---@return table actions { releaseMa?, publishMa?, askWhosMa?, releaseMt?, publishMt?, askWhosMt? }
function auto_ma_mt.evaluateRoleClaims(opts)
    opts = opts or {}
    local rc = state.getRunconfig()
    local me = myName()
    if not me or me == '' then return {} end

    local actions = {}
    local claimMa, maSource, maIdx = auto_ma_mt.shouldClaimMa()
    local claimMt, mtSource, mtIdx = auto_ma_mt.shouldClaimMt()

    if rc.MaImHolding and (not isAutomaticAssist() or not claimMa) then
        actions.releaseMa = true
    elseif claimMa and not rc.MaImHolding then
        actions.publishMa = { source = maSource, listIndex = maIdx or 0 }
    elseif opts.trigger ~= 'release'
        and isAutomaticAssist() and not claimMa and not auto_ma_mt.getActorMaOverrideName() then
        actions.askWhosMa = true
    end

    if rc.MtImHolding and not isAutomaticTank() then
        actions.releaseMt = true
    elseif rc.MtImHolding and not claimMt then
        -- Sticky hold: only release when a different in-zone candidate clearly owns MT,
        -- or when this bot is dead/hovering. Brief post-zone eligibility dips must not drop the claim.
        if not meAlive() then
            actions.releaseMt = true
        else
            local top = auto_ma_mt.topMtCandidateInZone()
            if top and not namesEqual(top, me) then
                actions.releaseMt = true
            end
        end
    elseif claimMt and not rc.MtImHolding then
        actions.publishMt = { source = mtSource, listIndex = mtIdx or 0 }
    elseif opts.trigger ~= 'release'
        and isAutomaticTank() and not claimMt and not auto_ma_mt.getActorMtOverrideName() then
        actions.askWhosMt = true
    end

    return actions
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
        return { index = 1, tank = name }
    end

    local idx = auto_ma_mt.indexInList(rc.MtList, name)
    if idx then
        return { index = idx, tank = name }
    end
    return { index = 1, tank = name }
end

return auto_ma_mt
