-- Protect casters: MA mid-fight peel + shared pure-caster helpers for MA re-pick.
-- Scheduler runs only when settings.protectCasters is on; at most one mob inspect per tick.

local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')
local tankrole = require('lib.tankrole')
local spellutils = require('lib.spellutils')
local spawnutils = require('lib.spawnutils')
local charm = require('lib.charm')

local M = {}

local PURE_CASTER = {
    CLR = true, DRU = true, SHM = true,
    ENC = true, WIZ = true, MAG = true, NEC = true,
}

local RECHECK_MS = 5000
local MEZ_FALLBACK_MS = 3000
local MEMBER_CACHE_MS = 2000

---@type table<number, { nextCheckAt: number, threatVictimId: number|nil, threatSince: number|nil, lastTargetId: number|nil }>
local watch = {}
local readyThreatId = nil
local nextDue = 0
local listFingerprint = nil
local memberIds = {}
local memberIdsUntil = 0

local function settings()
    return botconfig.config and botconfig.config.settings
end

local function protectSecMs()
    local sec = tonumber(settings() and settings().protectCastersSec) or 30
    if sec < 1 then sec = 1 end
    return sec * 1000
end

local function clearAll()
    watch = {}
    readyThreatId = nil
    nextDue = 0
    listFingerprint = nil
end

local function recomputeNextDue()
    local soonest = nil
    for _, w in pairs(watch) do
        local t = w.nextCheckAt or 0
        if not soonest or t < soonest then soonest = t end
    end
    nextDue = soonest or 0
end

local function dropWatch(mobId)
    if watch[mobId] then
        watch[mobId] = nil
        if readyThreatId == mobId then readyThreatId = nil end
        recomputeNextDue()
    end
end

local function refreshMemberIds(now)
    if now < memberIdsUntil then return end
    memberIdsUntil = now + MEMBER_CACHE_MS
    memberIds = {}
    local meId = mq.TLO.Me.ID()
    if meId and meId > 0 then memberIds[meId] = true end
    local gn = tonumber(mq.TLO.Group.Members()) or 0
    for i = 0, gn do
        local m = mq.TLO.Group.Member(i)
        local id = m and m.ID and m.ID()
        if id and id > 0 then memberIds[id] = true end
    end
    local rn = tonumber(mq.TLO.Raid.Members()) or 0
    if rn > 0 then
        for i = 1, rn do
            local id = mq.TLO.Raid.Member(i).ID()
            if id and id > 0 then memberIds[id] = true end
        end
    end
end

--- True when spawnId is a pure-caster PC in group or raid (or self).
function M.isPureCasterVictim(spawnId)
    if not spawnId or spawnId <= 0 then return false end
    local sp = mq.TLO.Spawn(spawnId)
    if not sp or not sp.ID() or sp.ID() ~= spawnId then return false end
    if sp.Type() ~= 'PC' then return false end
    local cls = sp.Class and sp.Class.ShortName and sp.Class.ShortName()
    if not cls or not PURE_CASTER[string.upper(tostring(cls))] then return false end
    refreshMemberIds(mq.gettime())
    return memberIds[spawnId] == true
end

--- Victim spawn id if mob currently targets a pure caster group/raid member; else nil.
function M.mobPureCasterVictimId(spawn)
    if not spawn or not spawn.ID or not spawn.ID() then return nil end
    local tid = spawn.Target and spawn.Target.ID and spawn.Target.ID()
    if not tid or tid <= 0 then return nil end
    if M.isPureCasterVictim(tid) then return tid end
    return nil
end

function M.mobHasPureCasterTarget(spawn)
    return M.mobPureCasterVictimId(spawn) ~= nil
end

--- Accrued continuous threat ms for mobId (0 if none).
function M.threatDurationMs(mobId)
    local w = mobId and watch[mobId]
    if not w or not w.threatSince then return 0 end
    return math.max(0, mq.gettime() - w.threatSince)
end

local function mobListFingerprint(mobList)
    local n = 0
    local sum = 0
    for _, v in ipairs(mobList or {}) do
        local id = v.ID and v.ID()
        if id and id > 0 then
            n = n + 1
            sum = sum + id
        end
    end
    return n, sum
end

local function reconcileWatch(rc, engageId, now)
    local mobList = rc.MobList or {}
    local n, sum = mobListFingerprint(mobList)
    local fp = n * 1000000003 + sum
    if fp == listFingerprint then return n end
    listFingerprint = fp

    local present = {}
    for _, v in ipairs(mobList) do
        local id = v.ID and v.ID()
        if id and id > 0 and id ~= engageId then
            present[id] = true
            if not watch[id] then
                watch[id] = { nextCheckAt = now, threatVictimId = nil, threatSince = nil, lastTargetId = nil }
            end
        end
    end
    for id in pairs(watch) do
        if not present[id] then
            watch[id] = nil
            if readyThreatId == id then readyThreatId = nil end
        end
    end
    if engageId and watch[engageId] then
        dropWatch(engageId)
    end
    recomputeNextDue()
    return n
end

local function pickDueMobId(now)
    local bestId, bestAt = nil, nil
    for id, w in pairs(watch) do
        local t = w.nextCheckAt or 0
        if t <= now and (not bestAt or t < bestAt or (t == bestAt and id < bestId)) then
            bestId, bestAt = id, t
        end
    end
    return bestId
end

local function schedule(w, at)
    w.nextCheckAt = at
    if nextDue == 0 or at < nextDue then nextDue = at end
end

local function clearThreat(w)
    w.threatVictimId = nil
    w.threatSince = nil
    w.lastTargetId = nil
end

local function inspectMob(rc, mobId, engageId, now)
    if mobId == engageId then
        dropWatch(mobId)
        return
    end
    local spawn = mq.TLO.Spawn(mobId)
    if not spawnutils.isAliveEngageSpawn(spawn) then
        dropWatch(mobId)
        return
    end
    local inList = false
    for _, v in ipairs(rc.MobList or {}) do
        if v.ID and v.ID() == mobId then inList = true; break end
    end
    if not inList or charm.isCharmSkipped(mobId, rc) then
        dropWatch(mobId)
        return
    end

    local w = watch[mobId]
    if not w then return end

    local mezRem = spellutils.SpawnEnthrallRemainingMs(mobId)
    if mezRem and mezRem > 0 then
        clearThreat(w)
        if readyThreatId == mobId then readyThreatId = nil end
        local delay = mezRem > 0 and mezRem or MEZ_FALLBACK_MS
        if delay < MEZ_FALLBACK_MS then delay = MEZ_FALLBACK_MS end
        schedule(w, now + delay)
        recomputeNextDue()
        return
    end

    local victimId = M.mobPureCasterVictimId(spawn)
    if not victimId then
        clearThreat(w)
        if readyThreatId == mobId then readyThreatId = nil end
        schedule(w, now + RECHECK_MS)
        recomputeNextDue()
        return
    end

    if w.threatVictimId and w.threatVictimId ~= victimId then
        w.threatSince = now
    elseif not w.threatSince then
        w.threatSince = now
    end
    w.threatVictimId = victimId
    w.lastTargetId = victimId

    local need = protectSecMs()
    if (now - w.threatSince) >= need then
        readyThreatId = mobId
    elseif readyThreatId == mobId then
        -- Accrual lost threshold somehow; keep ready only if still over threshold.
        readyThreatId = nil
    end
    schedule(w, now + RECHECK_MS)
    recomputeNextDue()
end

--- Mid-fight scheduler: early-outs; at most one mob inspect per call.
function M.tick(rc)
    local s = settings()
    if not s or s.protectCasters ~= true then
        if next(watch) or readyThreatId then clearAll() end
        return
    end
    if not tankrole.AmIMainAssist() then return end
    rc = rc or state.getRunconfig()
    if rc.attackCommandEngage then return end
    if state.getMobCount(rc) <= 1 then
        if next(watch) or readyThreatId then clearAll() end
        return
    end

    local engageId = rc.engageTargetId
    if engageId and engageId > 0 then
        local esp = mq.TLO.Spawn(engageId)
        if esp and esp.Named and esp.Named() then
            -- Do not peel off a named; still allow watch maintenance for re-pick later.
            -- Skip producing readyThreatId for trash while sticky named.
            if readyThreatId and readyThreatId ~= engageId then
                local rsp = mq.TLO.Spawn(readyThreatId)
                if not (rsp and rsp.Named and rsp.Named()) then
                    readyThreatId = nil
                end
            end
        end
    end

    local now = mq.gettime()
    reconcileWatch(rc, engageId, now)

    if not next(watch) then
        readyThreatId = nil
        nextDue = 0
        return
    end

    if readyThreatId and (not watch[readyThreatId] or readyThreatId == engageId) then
        readyThreatId = nil
    end

    if now < nextDue then return end

    local dueId = pickDueMobId(now)
    if not dueId then
        recomputeNextDue()
        return
    end
    inspectMob(rc, dueId, engageId, now)
end

--- O(1) ready peel id for sticky MA branch; nil when inactive or sticky named.
function M.getReadyThreatId(rc, engageId)
    local s = settings()
    if not s or s.protectCasters ~= true then return nil end
    if not readyThreatId then return nil end
    if engageId and readyThreatId == engageId then return nil end
    if engageId and engageId > 0 then
        local esp = mq.TLO.Spawn(engageId)
        if esp and esp.Named and esp.Named() then return nil end
    end
    local sp = mq.TLO.Spawn(readyThreatId)
    if not spawnutils.isAliveEngageSpawn(sp) then
        dropWatch(readyThreatId)
        return nil
    end
    if spellutils.SpawnMezActive(readyThreatId) then
        dropWatch(readyThreatId)
        return nil
    end
    return readyThreatId
end

--- Sort key helpers for MA re-pick (higher = better for caster threat).
--- Returns threatDurationMs when Protect on and accrued; else 1 if live pure-caster target; else 0.
function M.repickThreatScore(spawn, protectOn)
    if not spawn or not spawn.ID then return 0 end
    local id = spawn.ID()
    if not id or id <= 0 then return 0 end
    if protectOn then
        local dur = M.threatDurationMs(id)
        if dur > 0 then return dur end
    end
    if M.mobHasPureCasterTarget(spawn) then
        return 1
    end
    return 0
end

function M.clear()
    clearAll()
end

return M
