-- cz_common synchronization via czactor: broadcast deltas after mutateCommon writes.

local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')
local log = require('lib.log')
local czactor = require('lib.czactor')
local czactor_dispatch = require('lib.czactor_dispatch')
local rolelists = require('lib.rolelists')

local common_sync = {}

local SYNC_LOCK_TRY_NOW = 3
local SYNC_PENDING_MAX = 8

---@type table[]|nil list of { delta = table }
local _pendingApplies = nil

local function deepCopy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do
        out[k] = deepCopy(v)
    end
    for i, v in ipairs(value) do
        out[i] = deepCopy(v)
    end
    return out
end

local function deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return false end
    for k, v in pairs(a) do
        if not deepEqual(v, b[k]) then return false end
    end
    for k, v in pairs(b) do
        if a[k] == nil then return false end
    end
    local lenA, lenB = #a, #b
    if lenA ~= lenB then return false end
    for i = 1, lenA do
        if not deepEqual(a[i], b[i]) then return false end
    end
    return true
end

local function deltaHasKeys(delta)
    if not delta then return false end
    if delta.top and next(delta.top) then return true end
    if delta.zones then
        for _, zb in pairs(delta.zones) do
            if type(zb) == 'table' and next(zb) then return true end
        end
    end
    return false
end

function common_sync.deepCopy(value)
    return deepCopy(value)
end

function common_sync.computeDelta(before, after)
    local delta = { top = {}, zones = {} }
    if not after then return delta end
    before = before or {}

    for k, v in pairs(after) do
        if k ~= 'zones' and not deepEqual(before[k], v) then
            delta.top[k] = deepCopy(v)
        end
    end

    local allZones = {}
    if type(before.zones) == 'table' then
        for zone in pairs(before.zones) do allZones[zone] = true end
    end
    if type(after.zones) == 'table' then
        for zone in pairs(after.zones) do allZones[zone] = true end
    end

    for zone in pairs(allZones) do
        local bz = before.zones and before.zones[zone] or nil
        local az = after.zones and after.zones[zone] or nil
        if not deepEqual(bz, az) then
            local zdelta = {}
            if type(az) == 'table' then
                for k, v in pairs(az) do
                    if not deepEqual(bz and bz[k], v) then
                        zdelta[k] = deepCopy(v)
                    end
                end
            end
            if type(bz) == 'table' then
                for k in pairs(bz) do
                    if az == nil or az[k] == nil then
                        zdelta[k] = az and az[k] or nil
                    end
                end
            end
            if next(zdelta) then
                delta.zones[zone] = zdelta
            end
        end
    end

    return delta
end

local function deltaCoversDisk(disk, delta)
    if not delta or not disk then return false end
    disk = disk or {}

    for k, v in pairs(delta.top or {}) do
        if not deepEqual(disk[k], v) then return false end
    end

    for zone, zdelta in pairs(delta.zones or {}) do
        local diskZb = disk.zones and disk.zones[zone] or nil
        for k, v in pairs(zdelta) do
            if not deepEqual(diskZb and diskZb[k], v) then return false end
        end
    end

    return true
end

local function applyDeltaToCommon(disk, delta)
    local out = deepCopy(disk or {})
    for k, v in pairs(delta.top or {}) do
        out[k] = deepCopy(v)
    end
    for zone, zdelta in pairs(delta.zones or {}) do
        if not out.zones then out.zones = {} end
        if not out.zones[zone] then out.zones[zone] = {} end
        for k, v in pairs(zdelta) do
            out.zones[zone][k] = deepCopy(v)
        end
    end
    return out
end

function common_sync.reloadAllFromCommon()
    botconfig.refreshZoneStateFromCommon()
    rolelists.loadFromCommon()
end

--- Try to apply without mq.delay. Returns true on success, false if lock busy / failed.
local function tryApplyWithLockOnce(delta)
    if not botconfig.tryAcquireCommonLock() then
        return false
    end
    if not botconfig.reloadCommonReadOnly() then
        botconfig.releaseCommonLock()
        log.say('common_sync: reload failed while applying delta')
        return true -- consumed; do not retry forever on read failure
    end
    local common = botconfig.getCommon()
    if deltaCoversDisk(common, delta) then
        botconfig.releaseCommonLock()
        return true
    end
    botconfig._suppressCommonSyncBroadcast = true
    botconfig._common = applyDeltaToCommon(common, delta)
    botconfig.saveCommonDirect()
    botconfig._suppressCommonSyncBroadcast = false
    botconfig.releaseCommonLock()
    return true
end

local function queuePendingApply(delta)
    if not _pendingApplies then _pendingApplies = {} end
    _pendingApplies[#_pendingApplies + 1] = { delta = delta }
    while #_pendingApplies > SYNC_PENDING_MAX do
        table.remove(_pendingApplies, 1)
    end
end

--- Non-blocking apply: a few immediate lock tries, else defer to czactor.tick.
local function applyWithLock(delta)
    for _ = 1, SYNC_LOCK_TRY_NOW do
        if tryApplyWithLockOnce(delta) then
            return true
        end
    end
    queuePendingApply(delta)
    return false
end

--- Retry deferred lock applies from czactor.tick (no mq.delay).
function common_sync.tickPending()
    if not _pendingApplies or #_pendingApplies == 0 then return end
    local remaining = {}
    local anyApplied = false
    for _, item in ipairs(_pendingApplies) do
        if tryApplyWithLockOnce(item.delta) then
            anyApplied = true
        else
            remaining[#remaining + 1] = item
        end
    end
    _pendingApplies = remaining
    if anyApplied then
        common_sync.reloadAllFromCommon()
    end
end

local function ensureSeqFields(rc)
    rc.commonSyncSeq = rc.commonSyncSeq or 0
    rc.commonSyncSeqByPublisher = rc.commonSyncSeqByPublisher or {}
end

function common_sync.publishAfterSave(delta, publisher)
    if not deltaHasKeys(delta) then return end
    local rc = state.getRunconfig()
    ensureSeqFields(rc)
    rc.commonSyncSeq = rc.commonSyncSeq + 1
    czactor.publish('common_sync', {
        seq = rc.commonSyncSeq,
        publisher = publisher,
        delta = delta,
    })
end

local function onCommonSync(content, sender)
    if type(content) ~= 'table' or type(content.delta) ~= 'table' then return end
    local seq = tonumber(content.seq) or 0
    local publisher = content.publisher or sender or ''
    if publisher == '' then return end

    local rc = state.getRunconfig()
    ensureSeqFields(rc)
    local lastSeq = rc.commonSyncSeqByPublisher[publisher] or 0
    if seq > 0 and seq <= lastSeq then return end
    if seq > 0 then rc.commonSyncSeqByPublisher[publisher] = seq end

    local delta = content.delta
    local disk = botconfig.readCommonFromDisk()
    if not deltaCoversDisk(disk, delta) then
        if not applyWithLock(delta) then
            -- Deferred; reload once pending clears in tickPending.
            return
        end
    end

    common_sync.reloadAllFromCommon()
end

function common_sync.registerActorHandlers()
    czactor_dispatch.RegisterHandler('common_sync', onCommonSync)
end

return common_sync
