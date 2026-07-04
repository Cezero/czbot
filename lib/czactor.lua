-- CZBot Actor channel: peer coordination (OT claims, role broadcasts, leader commands).
-- Requires MacroQuest lua `actors` module (same transport as MQCharinfo).

local mq = require('mq')
local actors = require('actors')
local charinfo = require('plugin.charinfo')
local charinfoutils = require('lib.charinfoutils')
local state = require('lib.state')
local log = require('lib.log')
local czactor_dispatch = require('lib.czactor_dispatch')

local czactor = {}

local PROTOCOL_VER = 1
local MAILBOX = 'czbot'
local OT_CLAIM_TTL_MS = 5000
local PING_INTERVAL_MS = 30000
local OT_HEARTBEAT_MS = 2000
local ROLE_HANDOFF_INTERVAL_MS = 2000

local _actor = nil
local _inboundQueue = {}
local _nextPingAt = 0
local _nextOtHeartbeatAt = 0
local _nextRoleHandoffAt = 0
local _nextClaimPruneAt = 0

local function myName()
    return mq.TLO.Me.Name()
end

local function myZone()
    return mq.TLO.Zone.ShortName() or ''
end

local function zonesMatch(a, b)
    if not a or a == '' or not b or b == '' then return true end
    return string.lower(a) == string.lower(b)
end

local function senderCharacter(message)
    if not message or not message.sender then return nil end
    return message.sender.character
end

local function envelope(id, fields)
    fields = fields or {}
    fields.id = id
    fields.ver = PROTOCOL_VER
    fields.ts = mq.gettime()
    fields.zone = myZone()
    return fields
end

local function ensureRunconfigFields(rc)
    rc.OtClaims = rc.OtClaims or {}
    rc.CzActorPeers = rc.CzActorPeers or {}
end

function czactor.init()
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)
    if _actor then return end
    _actor = actors.register(MAILBOX, function(message)
        if type(message) ~= 'table' or type(message.content) ~= 'table' then return end
        _inboundQueue[#_inboundQueue + 1] = message
    end)
    _nextPingAt = mq.gettime()
end

function czactor.broadcast(msg)
    if not _actor then return end
    _actor:send(msg)
end

function czactor.publish(messageId, fields)
    if not messageId then return end
    fields = fields or {}
    czactor_dispatch.logSend(messageId, fields)
    czactor.broadcast(envelope(messageId, fields))
end

function czactor.sendToCharacter(character, msg)
    if not _actor or not character or character == '' then return end
    _actor:send({ character = character }, msg)
end

local function firstAvailableFromMaList()
    local rc = state.getRunconfig()
    local list = rc.MaList
    if type(list) ~= 'table' then return nil end
    local leash = require('lib.tankrole').getAnchorLeash()
    for _, name in ipairs(list) do
        local ctx = charinfoutils.getLeaderContext(name)
        if ctx and ctx.alive and ctx.sameZone then
            if ctx.distance == nil or ctx.distance <= leash then
                return name
            end
        end
    end
    return nil
end

local function firstAvailableFromMtList()
    local rc = state.getRunconfig()
    local list = rc.MtList
    if type(list) ~= 'table' then return nil end
    for _, name in ipairs(list) do
        local ctx = charinfoutils.getLeaderContext(name)
        if ctx and ctx.alive and ctx.sameZone then return name end
    end
    return nil
end

local function maPrimaryTloName()
    local raidMembers = mq.TLO.Raid.Members() or 0
    if raidMembers > 0 then
        local n = mq.TLO.Raid.MainAssist and mq.TLO.Raid.MainAssist.Name and mq.TLO.Raid.MainAssist.Name()
        if n and n ~= '' then return n end
        return nil
    end
    local n = mq.TLO.Group.MainAssist and mq.TLO.Group.MainAssist.Name and mq.TLO.Group.MainAssist.Name()
    if n and n ~= '' then return n end
    return nil
end

local function isAutomaticAssist()
    local rc = state.getRunconfig()
    local name = rc.AssistName
    if name == nil or name == '' then name = rc.TankName end
    return name == 'automatic'
end

local function isAutomaticTank()
    return state.getRunconfig().TankName == 'automatic'
end

local function nextMaSeq()
    local rc = state.getRunconfig()
    local cur = rc.ActorMaOverride and rc.ActorMaOverride.seq or 0
    return cur + 1
end

local function nextMtSeq()
    local rc = state.getRunconfig()
    local cur = rc.ActorMtOverride and rc.ActorMtOverride.seq or 0
    return cur + 1
end

function czactor.publishMaUpdate(name, reason)
    if not name or name == '' then return end
    local seq = nextMaSeq()
    czactor.broadcast(envelope('ma_update', { name = name, seq = seq, reason = reason or 'manual' }))
end

function czactor.publishMtUpdate(name, reason)
    if not name or name == '' then return end
    local seq = nextMtSeq()
    czactor.broadcast(envelope('mt_update', { name = name, seq = seq, reason = reason or 'manual' }))
end

function czactor.getMaOverrideNameIfAvailable()
    local rc = state.getRunconfig()
    local o = rc.ActorMaOverride
    if not o or not o.name or o.name == '' then return nil end
    if o.expiresAt and mq.gettime() > o.expiresAt then return nil end
    if o.zone and not zonesMatch(o.zone, myZone()) then return nil end
    local ctx = charinfoutils.getLeaderContext(o.name)
    if not ctx or not ctx.alive or not ctx.sameZone then return nil end
    return o.name
end

function czactor.getMtOverrideNameIfAvailable()
    local rc = state.getRunconfig()
    local o = rc.ActorMtOverride
    if not o or not o.name or o.name == '' then return nil end
    if o.expiresAt and mq.gettime() > o.expiresAt then return nil end
    if o.zone and not zonesMatch(o.zone, myZone()) then return nil end
    local ctx = charinfoutils.getLeaderContext(o.name)
    if not ctx or not ctx.alive or not ctx.sameZone then return nil end
    return o.name
end

function czactor.matchesBroadcastScope(scope, leaderName)
    if not leaderName or leaderName == '' then return false end
    scope = scope or 'group'
    local me = myName()
    if scope == 'peers' then
        return leaderName == me or charinfo.GetInfo(leaderName) ~= nil
    end
    if scope == 'raid' then
        local raidMembers = mq.TLO.Raid.Members() or 0
        if raidMembers <= 0 then return false end
        for i = 1, raidMembers do
            if mq.TLO.Raid.Member(i).Name() == leaderName then return true end
        end
        return leaderName == me
    end
    if leaderName == me then return true end
    if mq.TLO.Group.Member(leaderName).Index() then return true end
    return false
end

function czactor.broadcastFollowMe(scope, leaderName)
    czactor.broadcast(envelope('follow_me', { leader = leaderName, scope = scope or 'group' }))
end

function czactor.broadcastFollowMeOff(scope)
    czactor.broadcast(envelope('follow_me_off', { scope = scope or 'group', leader = myName() }))
end

function czactor.broadcastCampHere(scope, leaderName)
    czactor.broadcast(envelope('camp_here', { leader = leaderName, scope = scope or 'group' }))
end

function czactor.broadcastCampHereOff(scope)
    czactor.broadcast(envelope('camp_here_off', { scope = scope or 'group', leader = myName() }))
end

local function applyMaUpdate(content, sender)
    local rc = state.getRunconfig()
    local name = content.name
    if not name or name == '' then return end
    if content.zone and not zonesMatch(content.zone, myZone()) then return end
    local cur = rc.ActorMaOverride
    local seq = content.seq or 0
    if cur and cur.seq and seq < cur.seq then return end
    if cur and cur.seq and seq == cur.seq and sender and cur.publisher and sender ~= cur.publisher then return end
    rc.ActorMaOverride = {
        name = name,
        seq = seq,
        ts = content.ts,
        expiresAt = content.expiresAt or content['until'],
        zone = content.zone,
        publisher = sender,
        reason = content.reason,
    }
    require('lib.tankrole').invalidateMa()
end

local function applyMtUpdate(content, sender)
    local rc = state.getRunconfig()
    local name = content.name
    if not name or name == '' then return end
    if content.zone and not zonesMatch(content.zone, myZone()) then return end
    local cur = rc.ActorMtOverride
    local seq = content.seq or 0
    if cur and cur.seq and seq < cur.seq then return end
    if cur and cur.seq and seq == cur.seq and sender and cur.publisher and sender ~= cur.publisher then return end
    rc.ActorMtOverride = {
        name = name,
        seq = seq,
        ts = content.ts,
        expiresAt = content.expiresAt or content['until'],
        zone = content.zone,
        publisher = sender,
        reason = content.reason,
    }
    require('lib.tankrole').invalidateMt()
end

local function pruneOtClaims(rc)
    local now = mq.gettime()
    for spawnId, claim in pairs(rc.OtClaims) do
        if not claim or (now - (claim.ts or 0)) > OT_CLAIM_TTL_MS then
            rc.OtClaims[spawnId] = nil
        end
    end
end

local function setOtClaim(spawnId, character, ts, zone)
    if not spawnId or spawnId <= 0 or not character then return end
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)
    rc.OtClaims[spawnId] = { character = character, ts = ts or mq.gettime(), zone = zone or myZone() }
end

function czactor.publishOtClaim(spawnId, mobName, primaryId)
    if not spawnId or spawnId <= 0 then return end
    local rc = state.getRunconfig()
    local ts = mq.gettime()
    rc.OtMyClaim = { spawnId = spawnId, ts = ts }
    czactor.broadcast(envelope('ot_claim', {
        spawnId = spawnId,
        mobName = mobName,
        primaryId = primaryId,
    }))
    setOtClaim(spawnId, myName(), ts, myZone())
end

function czactor.publishOtRelease(spawnId, reason)
    if not spawnId or spawnId <= 0 then return end
    local rc = state.getRunconfig()
    if rc.OtMyClaim and rc.OtMyClaim.spawnId == spawnId then
        rc.OtMyClaim = nil
    end
    rc.OtClaims[spawnId] = nil
    czactor.broadcast(envelope('ot_release', { spawnId = spawnId, reason = reason or 'disengage' }))
end

function czactor.releaseMyOtClaim(reason)
    local rc = state.getRunconfig()
    if rc.OtMyClaim and rc.OtMyClaim.spawnId then
        czactor.publishOtRelease(rc.OtMyClaim.spawnId, reason)
    end
end

function czactor.isSpawnClaimedByOther(spawnId)
    local rc = state.getRunconfig()
    local claim = rc.OtClaims and rc.OtClaims[spawnId]
    if not claim then return false end
    return claim.character ~= myName()
end

function czactor.canClaimSpawn(spawnId, myTs)
    local rc = state.getRunconfig()
    local claim = rc.OtClaims and rc.OtClaims[spawnId]
    if not claim then return true end
    if claim.character == myName() then return true end
    myTs = myTs or mq.gettime()
    return myTs > (claim.ts or 0)
end

local function handleOtClaimYield(spawnId, otherChar, otherTs)
    local rc = state.getRunconfig()
    if not rc.OtMyClaim or rc.OtMyClaim.spawnId ~= spawnId then return end
    if rc.OtMyClaim.ts and otherTs and otherTs <= rc.OtMyClaim.ts then return end
    if otherChar == myName() then return end
    rc.OtMyClaim = nil
    czactor.publishOtRelease(spawnId, 'yield')
    if rc.engageTargetId == spawnId then
        rc.engageTargetId = nil
        rc.attackCommandEngage = nil
    end
end

function czactor.getActiveOfftanks()
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)
    pruneOtClaims(rc)
    local out = {}
    local now = mq.gettime()
    for spawnId, claim in pairs(rc.OtClaims) do
        if claim and claim.character and claim.character ~= myName() then
            if (now - (claim.ts or 0)) <= OT_CLAIM_TTL_MS then
                if charinfo.GetInfo(claim.character) then
                    out[#out + 1] = {
                        name = claim.character,
                        spawnId = spawnId,
                        claimTs = claim.ts,
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b) return (a.name or '') < (b.name or '') end)
    return out
end

function czactor.pickOfftankAdd(mobList, maTarId, mtTarId)
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)
    pruneOtClaims(rc)
    local charm = require('lib.charm')
    local candidates = {}
    for _, v in ipairs(mobList or {}) do
        local id = v.ID and v.ID() or v
        if id and id > 0 then
            if id ~= maTarId and id ~= mtTarId and not charm.isCharmSkipped(id, rc) then
                candidates[#candidates + 1] = id
            end
        end
    end
    table.sort(candidates)
    local now = mq.gettime()
    for _, id in ipairs(candidates) do
        if czactor.canClaimSpawn(id, now) then
            return id
        end
    end
    return nil
end

function czactor.syncOtClaimForEngage(spawnId, mobName, maTarId)
    if not spawnId or spawnId <= 0 then return end
    local rc = state.getRunconfig()
    if rc.OtMyClaim and rc.OtMyClaim.spawnId == spawnId then
        if mq.gettime() >= _nextOtHeartbeatAt then
            _nextOtHeartbeatAt = mq.gettime() + OT_HEARTBEAT_MS
            czactor.broadcast(envelope('ot_heartbeat', {
                spawnId = spawnId,
                mobName = mobName,
                primaryId = maTarId,
            }))
            setOtClaim(spawnId, myName(), mq.gettime(), myZone())
        end
        return
    end
    czactor.publishOtClaim(spawnId, mobName, maTarId)
end

local function handleLeaderFollowMe(content)
    if not czactor.matchesBroadcastScope(content.scope, content.leader) then return end
    require('lib.follow').StartFollow(content.leader)
end

local function handleLeaderFollowMeOff(content)
    if not czactor.matchesBroadcastScope(content.scope, content.leader) then return end
    require('lib.follow').StopFollow('command')
end

local function handleLeaderCampHere(content)
    if not czactor.matchesBroadcastScope(content.scope, content.leader) then return end
    local follow = require('lib.follow')
    local botmove = require('botmove')
    local botpull = require('botpull')
    local rc = state.getRunconfig()
    follow.StopFollow('command')
    local pullCfg = require('lib.config').config.pull
    local pullActive = rc.dopull == true
    local roamOnly = pullCfg and pullCfg.roam == true and pullActive
    local hunterMode = pullCfg and pullCfg.hunter == true and not roamOnly and pullActive
    if not (roamOnly or hunterMode) then
        botmove.MakeCamp('on')
    end
    botpull.DisablePull('camphere')
end

local function handleLeaderCampHereOff(content)
    if not czactor.matchesBroadcastScope(content.scope, content.leader) then return end
    require('lib.follow').StopFollow('command')
    local rc = state.getRunconfig()
    if rc.campstatus then require('botmove').MakeCamp('off') end
end

local function processMessage(message)
    if type(message) ~= 'table' then return end
    local content = message.content
    if type(content) ~= 'table' then return end
    if content.ver and content.ver ~= PROTOCOL_VER then return end
    local sender = senderCharacter(message)
    local id = content.id
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)

    if id == 'ping' then
        if sender then rc.CzActorPeers[sender] = mq.gettime() end
        if sender and sender ~= myName() then
            czactor.sendToCharacter(sender, envelope('pong', {}))
        end
        return
    end
    if id == 'pong' then
        if sender then rc.CzActorPeers[sender] = mq.gettime() end
        return
    end

    if id == 'ma_update' then applyMaUpdate(content, sender) return end
    if id == 'mt_update' then applyMtUpdate(content, sender) return end

    if id == 'ot_claim' or id == 'ot_heartbeat' then
        local spawnId = content.spawnId
        if spawnId and spawnId > 0 and sender then
            setOtClaim(spawnId, sender, content.ts, content.zone)
            handleOtClaimYield(spawnId, sender, content.ts)
        end
        return
    end
    if id == 'ot_release' then
        local spawnId = content.spawnId
        if spawnId and spawnId > 0 then
            local claim = rc.OtClaims[spawnId]
            if not claim or claim.character == sender or sender == nil then
                rc.OtClaims[spawnId] = nil
            end
        end
        return
    end

    if id == 'follow_me' then handleLeaderFollowMe(content) return end
    if id == 'follow_me_off' then handleLeaderFollowMeOff(content) return end
    if id == 'camp_here' then handleLeaderCampHere(content) return end
    if id == 'camp_here_off' then handleLeaderCampHereOff(content) return end

    if czactor_dispatch.Dispatch(content, sender) then return end
end

local function tickRoleHandoff()
    local now = mq.gettime()
    if now < _nextRoleHandoffAt then return end
    _nextRoleHandoffAt = now + ROLE_HANDOFF_INTERVAL_MS

    local rc = state.getRunconfig()
    local me = myName()
    if isAutomaticAssist() then
        local primary = maPrimaryTloName()
        local primaryOk = false
        if primary then
            local ctx = charinfoutils.getLeaderContext(primary)
            primaryOk = ctx and ctx.alive and ctx.sameZone
        end
        if not primaryOk then
            local candidate = firstAvailableFromMaList()
            if candidate == me then
                local cur = rc.ActorMaOverride
                if not cur or cur.name ~= me then
                    czactor.publishMaUpdate(me, 'death')
                end
            end
        end
    end

    if isAutomaticTank() then
        local raidMembers = mq.TLO.Raid.Members() or 0
        local primaryOk = false
        if raidMembers == 0 then
            local primary = mq.TLO.Group.MainTank and mq.TLO.Group.MainTank.Name and mq.TLO.Group.MainTank.Name()
            if primary and primary ~= '' then
                local ctx = charinfoutils.getLeaderContext(primary)
                primaryOk = ctx and ctx.alive and ctx.sameZone
            end
        end
        if not primaryOk then
            local candidate = firstAvailableFromMtList()
            if candidate == me then
                local cur = rc.ActorMtOverride
                if not cur or cur.name ~= me then
                    czactor.publishMtUpdate(me, 'death')
                end
            end
        end
    end
end

function czactor.tick()
    if not _actor then return end
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)

    while _inboundQueue[1] ~= nil do
        local msg = table.remove(_inboundQueue, 1)
        if msg then processMessage(msg) end
    end

    local now = mq.gettime()
    if now >= _nextPingAt then
        _nextPingAt = now + PING_INTERVAL_MS
        czactor.broadcast(envelope('ping', {}))
    end

    if now >= _nextClaimPruneAt then
        _nextClaimPruneAt = now + 1000
        pruneOtClaims(rc)
        if rc.OtMyClaim and rc.OtMyClaim.spawnId then
            local sid = rc.OtMyClaim.spawnId
            local sp = mq.TLO.Spawn(sid)
            if not sp or not sp.ID() or sp.ID() == 0 or sp.Type() == 'Corpse'
                or not require('lib.spawnutils').isAliveEngageSpawn(sp) then
                czactor.publishOtRelease(sid, 'dead')
            end
        end
    end

    tickRoleHandoff()
end

function czactor.sendPing()
    czactor.broadcast(envelope('ping', {}))
end

function czactor.onMaResumed()
    if require('lib.tankrole').AmIMainAssist() then
        czactor.publishMaUpdate(myName(), 'resume')
    end
end

function czactor.printPeerStatus()
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)
    local peers = charinfo.GetPeers()
    log.say('czbot Actor peers (%d charinfo, czbot replies below):', #peers)
    for _, name in ipairs(peers) do
        local last = rc.CzActorPeers[name]
        local age = last and string.format('%.1fs ago', (mq.gettime() - last) / 1000) or 'never'
        printf('  %s  czbot=%s', name, age)
    end
end

function czactor.printStatus()
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)
    czactor.printPeerStatus()
    local maO = rc.ActorMaOverride
    local mtO = rc.ActorMtOverride
    printf('  MA override: %s', maO and maO.name or '(none)')
    if maO then printf('    seq=%s reason=%s publisher=%s', tostring(maO.seq), tostring(maO.reason), tostring(maO.publisher)) end
    printf('  MT override: %s', mtO and mtO.name or '(none)')
    if mtO then printf('    seq=%s reason=%s publisher=%s', tostring(mtO.seq), tostring(mtO.reason), tostring(mtO.publisher)) end
    local claimCount = 0
    for spawnId, claim in pairs(rc.OtClaims or {}) do
        claimCount = claimCount + 1
        printf('  OT claim spawn %s -> %s (%.1fs ago)', tostring(spawnId), tostring(claim.character),
            (mq.gettime() - (claim.ts or 0)) / 1000)
    end
    if claimCount == 0 then printf('  OT claims: (none)') end
    if rc.OtMyClaim then
        printf('  My OT claim: spawn %s', tostring(rc.OtMyClaim.spawnId))
    end
end

function czactor.getHookFn(name)
    if name == 'czactorTick' then
        return function(_hookName)
            czactor.tick()
        end
    end
    return nil
end

return czactor
