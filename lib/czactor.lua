-- CZBot Actor channel: peer coordination (OT claims, role broadcasts, leader commands).
-- Requires MacroQuest lua `actors` module (same transport as MQCharinfo).

local mq = require('mq')
local actors = require('actors')
local charinfo = require('plugin.charinfo')
local state = require('lib.state')
local log = require('lib.log')
local czactor_dispatch = require('lib.czactor_dispatch')
local auto_ma_mt = require('lib.auto_ma_mt')
local tankrole = require('lib.tankrole')

local czactor = {}

local PROTOCOL_VER = 1
local MAILBOX = 'czbot'
local OT_CLAIM_TTL_MS = 5000
local REZ_CLAIM_TTL_MS = 60000
local PING_INTERVAL_MS = 30000
local OT_HEARTBEAT_MS = 2000

local _actor = nil
local _inboundQueue = {}
local _nextPingAt = 0
local _nextOtHeartbeatAt = 0
local _nextClaimPruneAt = 0
local _nextRoleClaimsAt = 0
local _maPublishSeq = 0
local _mtPublishSeq = 0
local _lastMaEngagedSpawnId = nil
local ROLE_CLAIMS_INTERVAL_MS = 2000
local applyImMa
local applyImMt

local function inRaid()
    return mq.TLO.Raid.Members() and mq.TLO.Raid.Members() > 0
end

local function roleBroadcastScope()
    return inRaid() and 'raid' or 'group'
end

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
    rc.RezClaims = rc.RezClaims or {}
    rc.CzActorPeers = rc.CzActorPeers or {}
    if rc.MaReleased == nil then rc.MaReleased = false end
    if rc.MtReleased == nil then rc.MtReleased = false end
    if rc.MaImHolding == nil then rc.MaImHolding = false end
    if rc.MtImHolding == nil then rc.MtImHolding = false end
end

function czactor.init()
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)
    if _actor then
        pcall(function() actors.unregister(_actor) end)
        _actor = nil
    end
    _actor = actors.register(MAILBOX, function(message)
        if not message then return end
        local content = message.content
        if type(content) ~= 'table' then return end
        _inboundQueue[#_inboundQueue + 1] = message
    end)
    if not _actor then
        printf('czactor: mailbox %s registration failed', MAILBOX)
    end
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
    _actor:send({ character = character, mailbox = MAILBOX }, msg)
end

local function nextManualMaSeq()
    local rc = state.getRunconfig()
    local cur = rc.ActorMaOverride and rc.ActorMaOverride.seq or 0
    return cur + 1
end

local function nextManualMtSeq()
    local rc = state.getRunconfig()
    local cur = rc.ActorMtOverride and rc.ActorMtOverride.seq or 0
    return cur + 1
end

function czactor.publishMaUpdate(name, reason)
    if not name or name == '' then return end
    local seq = nextManualMaSeq()
    czactor.broadcast(envelope('ma_update', {
        name = name,
        seq = seq,
        reason = reason or 'manual',
        scope = roleBroadcastScope(),
    }))
end

function czactor.publishMtUpdate(name, reason)
    if not name or name == '' then return end
    local seq = nextManualMtSeq()
    czactor.broadcast(envelope('mt_update', {
        name = name,
        seq = seq,
        reason = reason or 'manual',
        scope = roleBroadcastScope(),
    }))
end

function czactor.publishImMa(source, listIndex)
    _maPublishSeq = _maPublishSeq + 1
    local rc = state.getRunconfig()
    rc.MaImHolding = true
    local fields = {
        name = myName(),
        seq = _maPublishSeq,
        scope = roleBroadcastScope(),
        source = source or 'list',
        listIndex = listIndex or 0,
    }
    local content = envelope('im_ma', fields)
    applyImMa(content, myName())
    czactor_dispatch.logSend('im_ma', fields)
    czactor.broadcast(content)
end

function czactor.publishImMt(source, listIndex)
    _mtPublishSeq = _mtPublishSeq + 1
    local rc = state.getRunconfig()
    rc.MtImHolding = true
    local fields = {
        name = myName(),
        seq = _mtPublishSeq,
        scope = roleBroadcastScope(),
        source = source or 'list',
        listIndex = listIndex or 0,
    }
    local content = envelope('im_mt', fields)
    applyImMt(content, myName())
    czactor_dispatch.logSend('im_mt', fields)
    czactor.broadcast(content)
end

function czactor.publishReleaseMa()
    local rc = state.getRunconfig()
    rc.MaImHolding = false
    local cur = rc.ActorMaOverride
    local me = myName()
    if cur and cur.name and me and string.lower(cur.name) == string.lower(me) then
        rc.ActorMaOverride = nil
    end
    if auto_ma_mt.isSenderInMyGroup(me) then
        rc.MaReleased = true
    end
    tankrole.invalidateMa()
    czactor.publish('release_ma', {
        name = me,
        scope = roleBroadcastScope(),
    })
end

function czactor.publishReleaseMt()
    local rc = state.getRunconfig()
    rc.MtImHolding = false
    local cur = rc.ActorMtOverride
    local me = myName()
    if cur and cur.name and me and string.lower(cur.name) == string.lower(me) then
        rc.ActorMtOverride = nil
    end
    if auto_ma_mt.isSenderInMyGroup(me) then
        rc.MtReleased = true
    end
    tankrole.invalidateMt()
    czactor.publish('release_mt', {
        name = me,
        scope = roleBroadcastScope(),
    })
end

local function applyRoleClaimActions(actions)
    if not actions then return end
    if actions.releaseMa then czactor.publishReleaseMa() end
    if actions.releaseMt then czactor.publishReleaseMt() end
    if actions.publishMa then
        czactor.publishImMa(actions.publishMa.source, actions.publishMa.listIndex)
    end
    if actions.publishMt then
        czactor.publishImMt(actions.publishMt.source, actions.publishMt.listIndex)
    end
end

function czactor.runRoleClaimsTick()
    local now = mq.gettime()
    if now < _nextRoleClaimsAt then return end
    _nextRoleClaimsAt = now + ROLE_CLAIMS_INTERVAL_MS
    applyRoleClaimActions(auto_ma_mt.evaluateRoleClaims({ trigger = 'periodic' }))
end

function czactor.onRoleReleaseReceived()
    applyRoleClaimActions(auto_ma_mt.evaluateRoleClaims({ trigger = 'release' }))
end

function czactor.getMaOverrideNameIfAvailable()
    return auto_ma_mt.getActorMaOverrideNameIfAvailable()
end

function czactor.getMtOverrideNameIfAvailable()
    return auto_ma_mt.getActorMtOverrideNameIfAvailable()
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

local function acceptMaClaim(sender)
    if not sender or sender == '' then return false end
    if inRaid() then
        return auto_ma_mt.isSenderInMyRaid(sender)
    end
    if auto_ma_mt.isSenderInMyGroup(sender) then return true end
    return auto_ma_mt.groupLacksActiveMa()
end

local function acceptMtClaim(sender)
    if not sender or sender == '' then return false end
    if inRaid() then
        return auto_ma_mt.isSenderInMyRaid(sender)
    end
    if auto_ma_mt.isSenderInMyGroup(sender) then return true end
    return auto_ma_mt.groupLacksActiveMt()
end

local function acceptMaRelease(sender, rc)
    if not sender or sender == '' then return false end
    if inRaid() then
        return auto_ma_mt.isSenderInMyRaid(sender)
    end
    if auto_ma_mt.isSenderInMyGroup(sender) then return true end
    local o = rc.ActorMaOverride
    return o and o.name and string.lower(o.name) == string.lower(sender)
end

local function acceptMtRelease(sender, rc)
    if not sender or sender == '' then return false end
    if inRaid() then
        return auto_ma_mt.isSenderInMyRaid(sender)
    end
    if auto_ma_mt.isSenderInMyGroup(sender) then return true end
    local o = rc.ActorMtOverride
    return o and o.name and string.lower(o.name) == string.lower(sender)
end

local function shouldAcceptImClaim(content, sender, cur)
    if not cur or not cur.name then return true end
    local newInGroup = auto_ma_mt.isSenderInMyGroup(sender)
    local curInGroup = cur.inGroup
    if curInGroup == nil and cur.publisher then
        curInGroup = auto_ma_mt.isSenderInMyGroup(cur.publisher)
    end
    if newInGroup and not curInGroup then return true end
    if not newInGroup and curInGroup then return false end

    local newIdx = tonumber(content.listIndex) or 999
    local curIdx = tonumber(cur.listIndex) or (cur.source == 'primary' and 0 or 999)
    local newSource = content.source or 'list'
    local curSource = cur.source or 'list'

    if newSource == 'primary' and curSource ~= 'primary' then return true end
    if newSource ~= 'primary' and curSource == 'primary' then return false end

    if newIdx < curIdx then return true end
    if newIdx > curIdx then return false end

    local newSeq = tonumber(content.seq) or 0
    local curSeq = tonumber(cur.seq) or 0
    if sender == cur.publisher then return newSeq >= curSeq end
    return newSeq > curSeq
end

applyImMa = function(content, sender)
    local rc = state.getRunconfig()
    local name = content.name or sender
    if not name or name == '' then
        czactor_dispatch.logRoleClaimReject('im_ma', 'empty name', sender)
        return
    end
    if content.zone and not zonesMatch(content.zone, myZone()) then
        czactor_dispatch.logRoleClaimReject('im_ma', 'zone mismatch', sender,
            string.format('msgZone=%s myZone=%s', tostring(content.zone), tostring(myZone())))
        return
    end
    if not acceptMaClaim(sender) then
        czactor_dispatch.logRoleClaimReject('im_ma', 'acceptMaClaim', sender)
        return
    end
    local cur = rc.ActorMaOverride
    if cur and cur.reason == 'manual' then
        czactor_dispatch.logRoleClaimReject('im_ma', 'manual override active', sender,
            string.format('cur=%s', tostring(cur.name)))
        return
    end
    if not shouldAcceptImClaim(content, sender, cur) then
        czactor_dispatch.logRoleClaimReject('im_ma', 'shouldAcceptImClaim', sender,
            string.format('cur=%s seq=%s', tostring(cur and cur.name), tostring(cur and cur.seq)))
        return
    end

    local inGroup = auto_ma_mt.isSenderInMyGroup(sender)
    rc.ActorMaOverride = {
        name = name,
        seq = content.seq or 0,
        ts = content.ts,
        zone = content.zone,
        publisher = sender,
        reason = 'claim',
        scope = content.scope,
        source = content.source,
        listIndex = content.listIndex,
        inGroup = inGroup,
    }
    if inGroup then rc.MaReleased = false end
    tankrole.invalidateMa()
end

applyImMt = function(content, sender)
    local rc = state.getRunconfig()
    local name = content.name or sender
    if not name or name == '' then
        czactor_dispatch.logRoleClaimReject('im_mt', 'empty name', sender)
        return
    end
    if content.zone and not zonesMatch(content.zone, myZone()) then
        czactor_dispatch.logRoleClaimReject('im_mt', 'zone mismatch', sender,
            string.format('msgZone=%s myZone=%s', tostring(content.zone), tostring(myZone())))
        return
    end
    if not acceptMtClaim(sender) then
        czactor_dispatch.logRoleClaimReject('im_mt', 'acceptMtClaim', sender)
        return
    end
    local cur = rc.ActorMtOverride
    if cur and cur.reason == 'manual' then
        czactor_dispatch.logRoleClaimReject('im_mt', 'manual override active', sender,
            string.format('cur=%s', tostring(cur.name)))
        return
    end
    if not shouldAcceptImClaim(content, sender, cur) then
        czactor_dispatch.logRoleClaimReject('im_mt', 'shouldAcceptImClaim', sender,
            string.format('cur=%s seq=%s', tostring(cur and cur.name), tostring(cur and cur.seq)))
        return
    end

    local inGroup = auto_ma_mt.isSenderInMyGroup(sender)
    rc.ActorMtOverride = {
        name = name,
        seq = content.seq or 0,
        ts = content.ts,
        zone = content.zone,
        publisher = sender,
        reason = 'claim',
        scope = content.scope,
        source = content.source,
        listIndex = content.listIndex,
        inGroup = inGroup,
    }
    if inGroup then rc.MtReleased = false end
    local prevName = cur and cur.name
    local nameChanged = not prevName or not name
        or string.lower(prevName) ~= string.lower(name)
    if nameChanged then
        require('lib.chchain').syncCurtankFromMtName(name, 'claim')
    end
    tankrole.invalidateMt()
end

local function clearMaActorEngaged(rc, maName)
    local eng = rc.MaActorEngaged
    if not eng then return end
    if maName and eng.maName and string.lower(eng.maName) ~= string.lower(maName) then return end
    rc.MaActorEngaged = nil
    rc.followCatchUp = false
end

local function isAliveEngageSpawnId(spawnId)
    if not spawnId or spawnId <= 0 then return false end
    local sp = mq.TLO.Spawn(spawnId)
    if not sp or not sp.ID() or sp.ID() == 0 or sp.Type() == 'Corpse' then return false end
    return require('lib.spawnutils').isAliveEngageSpawn(sp)
end

local function namesMatch(a, b)
    if not a or not b or a == '' or b == '' then return false end
    return string.lower(a) == string.lower(b)
end

local function applyMaEngaged(content, sender)
    if not sender or sender == myName() then return end
    if content.zone and not zonesMatch(content.zone, myZone()) then return end
    if not acceptMaClaim(sender) then return end
    local spawnId = content.spawnId
    if not spawnId or spawnId <= 0 then return end
    local rc = state.getRunconfig()
    local prev = rc.MaActorEngaged
    local isNew = not prev or prev.spawnId ~= spawnId
    rc.MaActorEngaged = {
        maName = sender,
        spawnId = spawnId,
        ts = content.ts or mq.gettime(),
        zone = content.zone,
        scope = content.scope,
    }
    if isNew then
        require('botmove').onFollowEngagementStarted(rc)
    end
end

local function applyMaDisengage(content, sender)
    if not sender or sender == myName() then return end
    if content.zone and not zonesMatch(content.zone, myZone()) then return end
    if not acceptMaClaim(sender) then return end
    clearMaActorEngaged(state.getRunconfig(), sender)
end

local function applyAttackEngage(content, sender)
    if not sender or sender == myName() then return end
    if content.zone and not zonesMatch(content.zone, myZone()) then return end
    local issuer = content.issuer or sender
    if not czactor.matchesBroadcastScope(content.scope, issuer) then return end
    local spawnId = content.spawnId
    if not spawnId or spawnId <= 0 then return end
    local botmelee = require('botmelee')
    local ok, mobName = botmelee.applyAttackCommandEngage(spawnId)
    if ok then
        log.say('[Attack] engaging %s (%s) from %s', mobName or '?', tostring(spawnId), sender)
    end
end

function czactor.publishMaEngaged(spawnId, mobName)
    if not spawnId or spawnId <= 0 then return end
    if _lastMaEngagedSpawnId == spawnId then return end
    _lastMaEngagedSpawnId = spawnId
    czactor.publish('ma_engaged', {
        spawnId = spawnId,
        mobName = mobName,
        scope = roleBroadcastScope(),
    })
end

function czactor.publishMaDisengage(reason)
    _lastMaEngagedSpawnId = nil
    czactor.publish('ma_disengage', {
        reason = reason or 'disengage',
        scope = roleBroadcastScope(),
    })
end

function czactor.publishAttackEngage(spawnId, mobName, assistName)
    if not spawnId or spawnId <= 0 then return end
    local issuer = myName()
    if not issuer or issuer == '' then return end
    czactor.publish('attack', {
        spawnId = spawnId,
        mobName = mobName,
        assistName = assistName,
        issuer = issuer,
        scope = roleBroadcastScope(),
    })
end

function czactor.getMaEngagedSpawnId(maName)
    maName = maName or tankrole.GetAssistTargetName()
    if not maName or maName == '' then return nil end
    if namesMatch(maName, myName()) and tankrole.AmIMainAssist() then
        local rc = state.getRunconfig()
        local id = rc.engageTargetId
        if id and id > 0 and isAliveEngageSpawnId(id) then return id end
        return nil
    end
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)
    local eng = rc.MaActorEngaged
    if not eng or not eng.spawnId or not namesMatch(eng.maName, maName) then return nil end
    if eng.zone and not zonesMatch(eng.zone, myZone()) then return nil end
    if not isAliveEngageSpawnId(eng.spawnId) then
        rc.MaActorEngaged = nil
        return nil
    end
    return eng.spawnId
end

function czactor.isMaEngagementActive()
    if tankrole.AmIMainAssist() then
        local rc = state.getRunconfig()
        local id = rc.engageTargetId
        return id and id > 0 and isAliveEngageSpawnId(id)
    end
    local maName = tankrole.GetAssistTargetName()
    if not maName or maName == '' then return false end
    return czactor.getMaEngagedSpawnId(maName) ~= nil
end

local function applyReleaseMa(content, sender)
    local rc = state.getRunconfig()
    if content.zone and not zonesMatch(content.zone, myZone()) then return end
    if not acceptMaRelease(sender, rc) then return end
    local name = content.name or sender
    local cur = rc.ActorMaOverride
    if cur and cur.name and name and string.lower(cur.name) ~= string.lower(name) then return end
    clearMaActorEngaged(rc, name)
    rc.ActorMaOverride = nil
    if auto_ma_mt.isSenderInMyGroup(sender) then
        rc.MaReleased = true
    end
    tankrole.invalidateMa()
    czactor.onRoleReleaseReceived()
end

local function applyReleaseMt(content, sender)
    local rc = state.getRunconfig()
    if content.zone and not zonesMatch(content.zone, myZone()) then return end
    if not acceptMtRelease(sender, rc) then return end
    local name = content.name or sender
    local cur = rc.ActorMtOverride
    if cur and cur.name and name and string.lower(cur.name) ~= string.lower(name) then return end
    rc.ActorMtOverride = nil
    if auto_ma_mt.isSenderInMyGroup(sender) then
        rc.MtReleased = true
    end
    tankrole.invalidateMt()
    czactor.onRoleReleaseReceived()
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
        inGroup = sender and auto_ma_mt.isSenderInMyGroup(sender),
    }
    tankrole.invalidateMa()
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
        inGroup = sender and auto_ma_mt.isSenderInMyGroup(sender),
    }
    require('lib.chchain').syncCurtankFromMtName(name, content.reason or 'manual')
    tankrole.invalidateMt()
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

local function pruneRezClaims(rc)
    local now = mq.gettime()
    for corpseId, claim in pairs(rc.RezClaims) do
        if not claim or (now - (claim.ts or 0)) > REZ_CLAIM_TTL_MS then
            rc.RezClaims[corpseId] = nil
        end
    end
end

local function setRezClaim(corpseId, character, ts, zone)
    if not corpseId or corpseId <= 0 or not character then return end
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)
    rc.RezClaims[corpseId] = { character = character, ts = ts or mq.gettime(), zone = zone or myZone() }
end

function czactor.isCorpseRezClaimedByOther(corpseId)
    if not corpseId or corpseId <= 0 then return false end
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)
    pruneRezClaims(rc)
    local claim = rc.RezClaims[corpseId]
    if not claim then return false end
    if claim.character == myName() then return false end
    if claim.zone and not zonesMatch(claim.zone, myZone()) then return false end
    return true
end

function czactor.syncRezClaim(corpseId)
    if not corpseId or corpseId <= 0 then return end
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)
    if rc.RezMyClaim and rc.RezMyClaim.corpseId == corpseId then return end
    local ts = mq.gettime()
    rc.RezMyClaim = { corpseId = corpseId, ts = ts }
    czactor.publish('rez_claim', { corpseId = corpseId })
    setRezClaim(corpseId, myName(), ts, myZone())
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
    if content.leader == myName() then return end
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
    if not message then return end
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
    if id == 'im_ma' then
        czactor_dispatch.logRecvIfRoleClaimDebug(id, sender, content)
        applyImMa(content, sender)
        return
    end
    if id == 'im_mt' then
        czactor_dispatch.logRecvIfRoleClaimDebug(id, sender, content)
        applyImMt(content, sender)
        return
    end
    if id == 'release_ma' then
        czactor_dispatch.logRecvIfRoleClaimDebug(id, sender, content)
        applyReleaseMa(content, sender)
        return
    end
    if id == 'release_mt' then
        czactor_dispatch.logRecvIfRoleClaimDebug(id, sender, content)
        applyReleaseMt(content, sender)
        return
    end

    if id == 'ma_engaged' then applyMaEngaged(content, sender) return end
    if id == 'ma_disengage' then applyMaDisengage(content, sender) return end

    if id == 'attack' then applyAttackEngage(content, sender) return end

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

    if id == 'rez_claim' then
        local corpseId = content.corpseId
        if corpseId and corpseId > 0 and sender then
            setRezClaim(corpseId, sender, content.ts, content.zone)
        end
        return
    end

    if id == 'follow_me' then handleLeaderFollowMe(content) return end
    if id == 'follow_me_off' then handleLeaderFollowMeOff(content) return end
    if id == 'camp_here' then handleLeaderCampHere(content) return end
    if id == 'camp_here_off' then handleLeaderCampHereOff(content) return end

    if czactor_dispatch.Dispatch(content, sender) then return end
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
        pruneRezClaims(rc)
        if rc.OtMyClaim and rc.OtMyClaim.spawnId then
            local sid = rc.OtMyClaim.spawnId
            local sp = mq.TLO.Spawn(sid)
            if not sp or not sp.ID() or sp.ID() == 0 or sp.Type() == 'Corpse'
                or not require('lib.spawnutils').isAliveEngageSpawn(sp) then
                czactor.publishOtRelease(sid, 'dead')
            end
        end
        if rc.RezMyClaim and rc.RezMyClaim.corpseId then
            local cid = rc.RezMyClaim.corpseId
            local sp = mq.TLO.Spawn(cid)
            if not sp or not sp.ID() or sp.ID() == 0 or sp.Type() ~= 'Corpse' then
                rc.RezMyClaim = nil
            end
        end
        if rc.MaActorEngaged and rc.MaActorEngaged.spawnId then
            if not isAliveEngageSpawnId(rc.MaActorEngaged.spawnId) then
                rc.MaActorEngaged = nil
                rc.followCatchUp = false
            end
        end
    end

    czactor.runRoleClaimsTick()
end

function czactor.sendPing()
    czactor.broadcast(envelope('ping', {}))
end

function czactor.onMaResumed()
    czactor.onRoleReleaseReceived()
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
    if maO then
        printf('    seq=%s source=%s listIndex=%s zone=%s publisher=%s inGroup=%s reason=%s',
            tostring(maO.seq), tostring(maO.source), tostring(maO.listIndex),
            tostring(maO.zone), tostring(maO.publisher), tostring(maO.inGroup),
            tostring(maO.reason))
    end
    printf('  MT override: %s', mtO and mtO.name or '(none)')
    if mtO then
        printf('    seq=%s source=%s listIndex=%s zone=%s publisher=%s inGroup=%s reason=%s',
            tostring(mtO.seq), tostring(mtO.source), tostring(mtO.listIndex),
            tostring(mtO.zone), tostring(mtO.publisher), tostring(mtO.inGroup),
            tostring(mtO.reason))
    end
    printf('  MaReleased=%s MtReleased=%s MaImHolding=%s MtImHolding=%s',
        tostring(rc.MaReleased), tostring(rc.MtReleased),
        tostring(rc.MaImHolding), tostring(rc.MtImHolding))
    local maEng = rc.MaActorEngaged
    if maEng and maEng.spawnId then
        printf('  MA engaged: %s -> spawn %s (%.1fs ago)', tostring(maEng.maName),
            tostring(maEng.spawnId), (mq.gettime() - (maEng.ts or 0)) / 1000)
    else
        printf('  MA engaged: (none)')
    end
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
    pruneRezClaims(rc)
    local rezClaimCount = 0
    for corpseId, claim in pairs(rc.RezClaims or {}) do
        rezClaimCount = rezClaimCount + 1
        printf('  Rez claim corpse %s -> %s (%.1fs ago)', tostring(corpseId), tostring(claim.character),
            (mq.gettime() - (claim.ts or 0)) / 1000)
    end
    if rezClaimCount == 0 then printf('  Rez claims: (none)') end
    if rc.RezMyClaim then
        printf('  My rez claim: corpse %s', tostring(rc.RezMyClaim.corpseId))
    end
end

function czactor.SetRoleClaimLogDebug(on)
    czactor_dispatch.SetRoleClaimLogDebug(on)
end

function czactor.IsRoleClaimLogDebug()
    return czactor_dispatch.IsRoleClaimLogDebug()
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
