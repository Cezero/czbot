-- Helpers for MQCharInfo peer data (CharinfoPeer usertype from plugin.charinfo).
-- State[] is a 1-based string array (e.g. {'ATTACK', 'STAND', 'GROUP'}).

local mq = require('mq')
local utils = require('lib.utils')

local charinfoutils = {}

local UNAVAILABLE_STATE_FLAGS = { 'DEAD', 'FEIGN', 'HOVER' }

--- True when peer.State contains flag (e.g. 'ATTACK').
function charinfoutils.peerHasState(peer, flag)
    if not peer or not peer.State or not flag then return false end
    for _, v in ipairs(peer.State) do
        if v == flag then return true end
    end
    return false
end

function charinfoutils.peerHasAnyState(peer, flags)
    if not peer or not flags then return false end
    for _, flag in ipairs(flags) do
        if charinfoutils.peerHasState(peer, flag) then return true end
    end
    return false
end

local function peerZoneShortName(zone)
    if not zone then return nil end
    local sn = zone.ShortName
    if sn and sn ~= '' then return sn end
    local name = zone.Name
    if name and name ~= '' then return name end
    return nil
end

---@return boolean|nil true/false when both names known; nil when either is missing
local function zoneShortNamesMatch(a, b)
    if not a or a == '' or not b or b == '' then return nil end
    return string.lower(a) == string.lower(b)
end

local function aliveFromCharinfoPeer(peer)
    if charinfoutils.peerHasAnyState(peer, UNAVAILABLE_STATE_FLAGS) then
        return false
    end
    local pct = peer.PctHPs
    return pct == nil or pct > 0
end

local function baseContextFromCharinfo(name, peer)
    local zone = peer.Zone
    local targetId = peer.Target and peer.Target.ID or nil
    if targetId and targetId <= 0 then targetId = nil end
    return {
        source = 'charinfo',
        name = name,
        x = zone and zone.X or nil,
        y = zone and zone.Y or nil,
        z = zone and zone.Z or nil,
        distance = zone and zone.Distance or nil,
        targetId = targetId,
        inAttack = charinfoutils.peerHasState(peer, 'ATTACK'),
        alive = aliveFromCharinfoPeer(peer),
        sameZone = false,
        peerZone = peerZoneShortName(zone),
        peer = peer,
    }
end

local PLAYERSTATE_AGGRESSIVE = 4
local PLAYERSTATE_FORCED_AGGRESSIVE = 8

local function spawnInAttack(spawn)
    if not spawn then return false end
    local psFn = spawn.PlayerState
    if psFn then
        local ps = psFn()
        if ps then return bit32.band(ps, bit32.bor(PLAYERSTATE_AGGRESSIVE, PLAYERSTATE_FORCED_AGGRESSIVE)) ~= 0 end
    end
    local aggFn = spawn.Aggressive
    if aggFn then return aggFn() == true end
    return false
end

local function leaderContextFromSpawn(name)
    local spawn = mq.TLO.Spawn('pc =' .. name)
    local spawnId = spawn and spawn.ID()
    if not spawnId or spawnId == 0 then return nil end
    local meX, meY, meZ = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
    local sx, sy, sz = spawn.X(), spawn.Y(), spawn.Z()
    local distSq = utils.getDistanceSquared3D(meX, meY, meZ, sx, sy, sz)
    local distance = distSq and math.sqrt(distSq) or nil
    local targetId = spawn.Target and spawn.Target.ID() or nil
    if targetId and targetId <= 0 then targetId = nil end
    local alive = not spawn.Dead() and not spawn.Hovering()
    return {
        source = 'spawn',
        name = name,
        x = sx,
        y = sy,
        z = sz,
        distance = distance,
        targetId = targetId,
        inAttack = spawnInAttack(spawn),
        alive = alive,
        sameZone = true,
        peerZone = nil,
        peer = nil,
    }
end

local function mergeCharinfoWithSpawn(charinfoCtx, spawnCtx)
    if charinfoCtx.distance == nil then
        charinfoCtx.distance = spawnCtx.distance
    end
    if not charinfoCtx.x then charinfoCtx.x = spawnCtx.x end
    if not charinfoCtx.y then charinfoCtx.y = spawnCtx.y end
    if not charinfoCtx.z then charinfoCtx.z = spawnCtx.z end
    charinfoCtx.sameZone = true
    return charinfoCtx
end

local function leaderContextFromCharinfoPeer(name, peer)
    local myZone = mq.TLO.Zone.ShortName()
    local peerZone = peerZoneShortName(peer.Zone)
    local zoneMatch = zoneShortNamesMatch(peerZone, myZone)

    if zoneMatch == false then
        local ctx = baseContextFromCharinfo(name, peer)
        ctx.sameZone = false
        return ctx
    end

    local ctx = baseContextFromCharinfo(name, peer)
    if zoneMatch == true and ctx.x and ctx.y and ctx.z then
        ctx.sameZone = true
        return ctx
    end
    if ctx.distance ~= nil then
        ctx.sameZone = true
        return ctx
    end

    local spawnCtx = leaderContextFromSpawn(name)
    if spawnCtx then
        return mergeCharinfoWithSpawn(ctx, spawnCtx)
    end

    ctx.sameZone = false
    return ctx
end

local function leaderContextForSelf(name)
    local ok, charinfo = pcall(require, 'plugin.charinfo')
    if ok and charinfo then
        local peer = charinfo.GetInfo(name)
        if peer then
            local ctx = baseContextFromCharinfo(name, peer)
            ctx.sameZone = true
            ctx.distance = 0
            ctx.peerZone = mq.TLO.Zone.ShortName()
            return ctx
        end
    end
    local spawnCtx = leaderContextFromSpawn(name)
    if spawnCtx then
        spawnCtx.distance = 0
        spawnCtx.peerZone = mq.TLO.Zone.ShortName()
        return spawnCtx
    end
    return nil
end

--- 2D distance to leader context (follow leash semantics); prefers ctx coords over ctx.distance.
---@param ctx table|nil
---@return number|nil
function charinfoutils.leaderDistance2D(ctx)
    if not ctx then return nil end
    if ctx.x and ctx.y then
        local meX, meY = mq.TLO.Me.X(), mq.TLO.Me.Y()
        if meX and meY then
            local dSq = utils.getDistanceSquared2D(meX, meY, ctx.x, ctx.y)
            if dSq then return math.sqrt(dSq) end
        end
    end
    return ctx.distance
end

--- 3D distance to leader context; prefers ctx coords over ctx.distance.
---@param ctx table|nil
---@return number|nil
function charinfoutils.leaderDistance3D(ctx)
    if not ctx then return nil end
    if ctx.x and ctx.y and ctx.z then
        local meX, meY, meZ = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
        if meX and meY and meZ then
            local dSq = utils.getDistanceSquared3D(meX, meY, meZ, ctx.x, ctx.y, ctx.z)
            if dSq then return math.sqrt(dSq) end
        end
    end
    return ctx.distance
end

--- Normalized leader context from charinfo (bot peer) or Spawn TLO (non-bot PC).
---@param name string|nil
---@return table|nil
function charinfoutils.getLeaderContext(name)
    if not name or name == '' then return nil end

    local meName = mq.TLO.Me.Name()
    if meName and name == meName then
        return leaderContextForSelf(name)
    end

    local ok, charinfo = pcall(require, 'plugin.charinfo')
    if ok and charinfo then
        local peer = charinfo.GetInfo(name)
        if peer then return leaderContextFromCharinfoPeer(name, peer) end
    end
    return leaderContextFromSpawn(name)
end

return charinfoutils
