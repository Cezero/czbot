-- Shared /cz attack engage helpers and MobProb engage grace.
-- Extracted from botmelee so czactor can apply attack engages without a botmelee cycle.

local mq = require('mq')
local state = require('lib.state')
local utils = require('lib.utils')
local spawnutils = require('lib.spawnutils')
local charm = require('lib.charm')
local botconfig = require('lib.config')

local engage = {}

local _mobprobGraceEngageId = nil
local DEFAULT_MOBPROB_ENGAGE_GRACE_MS = 1000

local function getMobprobEngageGraceMs()
    local myconfig = botconfig.config
    local ms = tonumber(myconfig.melee and myconfig.melee.mobprobEngageGraceMs)
    if ms == nil then return DEFAULT_MOBPROB_ENGAGE_GRACE_MS end
    if ms < 0 then return 0 end
    return ms
end

--- Suppress MobProb /nav briefly after acquiring a new engage target (avoids early swing LoS/range spam).
---@param engageId number|nil
function engage.armMobprobEngageGrace(engageId)
    if state.getRunconfig().domobprob ~= true then return end
    if not engageId or engageId <= 0 then return end
    local graceMs = getMobprobEngageGraceMs()
    if graceMs <= 0 then return end
    if engageId == _mobprobGraceEngageId then return end
    _mobprobGraceEngageId = engageId
    state.getRunconfig().mobprobEngageGraceUntil = mq.gettime() + graceMs
end

function engage.clearMobprobEngageGrace()
    _mobprobGraceEngageId = nil
    state.getRunconfig().mobprobEngageGraceUntil = 0
end

--- Apply /cz attack engagement state (command issuer or peer receive).
--- Does not call botmove; callers should invoke onFollowEngagementStarted when isNewEngage.
---@param spawnId number
---@return boolean success
---@return string|nil mobName
---@return boolean|nil isNewEngage
function engage.applyAttackCommandEngage(spawnId)
    if not spawnId or spawnId <= 0 then return false, nil, nil end
    local sp = mq.TLO.Spawn(spawnId)
    if not sp or not sp.ID() or sp.ID() == 0 then return false, nil, nil end
    if utils.isProtectedSpawn(sp) then return false, nil, nil end
    if not spawnutils.isAliveEngageSpawn(sp) then return false, nil, nil end
    local rc = state.getRunconfig()
    if charm.isCharmSkipped(spawnId, rc) then return false, nil, nil end
    charm.releaseCharmTarget(spawnId, rc)
    local prevEngageId = rc.engageTargetId
    local isNewEngage = not prevEngageId or prevEngageId ~= spawnId
    rc.engageTargetId = spawnId
    rc.attackCommandEngage = true
    engage.armMobprobEngageGrace(spawnId)
    return true, sp.CleanName() or tostring(spawnId), isNewEngage
end

return engage
