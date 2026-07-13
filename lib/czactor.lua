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
local tickprof = require('lib.tickprof')

local czactor = {}

local PROTOCOL_VER = 1
local MAILBOX = 'czbot'
local OT_CLAIM_TTL_MS = 5000
local REZ_CLAIM_TTL_MS = 60000
local PING_INTERVAL_MS = 60000
local OT_HEARTBEAT_MS = 2000
local TICK_STALE_MS = 60000
local PEER_RECENT_MS = 90000
local CZACTOR_TICK_MS = 250
local TRAFFIC_WINDOW_MS = 60000
local INBOUND_QUEUE_WARN_DEPTH = 100
local INBOUND_QUEUE_MAX_DEPTH = 1000
local INBOUND_DRAIN_BUDGET = 150
local INBOUND_COMPACT_AT_HEAD = 512
local WHOS_BACKOFF_MIN_MS = 2000
local WHOS_BACKOFF_MAX_MS = 30000
local QUEUE_DEBUG_LOG_MS = 1000

local _actor = nil
local _inboundQueue = {}
local _inboundHead = 1
local _inboundTail = 1 -- next write index; depth = tail - head
local _lastTickAt = 0
local _tickStaleLoggedAt = 0
local _lastInitAttemptAt = 0
local _lastInitError = nil
local _nextCzactorTickAt = 0
local _trafficWindowStart = 0
local _trafficRecv = 0
local _trafficSendBroadcast = 0
local _trafficSendUnicast = 0
local _trafficDrained = 0
local _trafficDropped = 0
local _trafficEnqueued = 0
local _dropIdCounts = {}
local _enqueueIdCounts = {}
local _queueDepthWarnLoggedAt = 0
local _queueDropWarnLoggedAt = 0
local _queueDebug = false
local _queueDebugLoggedAt = 0
local processMessage

local INLINE_IMMEDIATE_IDS = {
    ping = true,
}
local FOLLOW_PRIORITY_IDS = {
    follow_me = true,
    follow_me_off = true,
}
local _nextPingAt = 0
local _nextOtHeartbeatAt = 0
local _nextClaimPruneAt = 0
local _nextRoleClaimsAt = 0
local _maPublishSeq = 0
local _mtPublishSeq = 0
local _lastMaEngagedSpawnId = nil
local _maEngagedHeartbeatNext = 0
local MA_ENGAGED_HEARTBEAT_MS = 2000
local _lastImMaPublishAt = 0
local _lastImMtPublishAt = 0

local MA_DISENGAGE_TRANSIENT_REASONS = {
    no_engage_target = true,
    engage_not_allowed = true,
    beyond_follow_distance = true,
    outside_camp_pin = true,
    moblist_empty = true,
}
local ROLE_CLAIMS_INTERVAL_MS = 2000
local applyImMa
local applyImMt
local clearMaActorEngaged
local _lastWhosMaAt = 0
local _lastWhosMtAt = 0
local _whosMaBackoffMs = WHOS_BACKOFF_MIN_MS
local _whosMtBackoffMs = WHOS_BACKOFF_MIN_MS

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

local function namesMatch(a, b)
    if not a or not b or a == '' or b == '' then return false end
    return string.lower(a) == string.lower(b)
end

local function shouldProcessInline(content)
    return content and content.id and INLINE_IMMEDIATE_IDS[content.id] == true
end

local function safeProcessInbound(message)
    if not processMessage then return end
    local ok, err = pcall(processMessage, message)
    if not ok then
        log.say('[czactor] processMessage error: %s', tostring(err))
    end
end

local function zonesMatch(a, b)
    if not a or a == '' or not b or b == '' then return true end
    return string.lower(a) == string.lower(b)
end

local function senderCharacter(inbound)
    if not inbound then return nil end
    if type(inbound.sender) == 'string' then return inbound.sender end
    if inbound.sender and inbound.sender.character then return inbound.sender.character end
    return nil
end

local function inboundEntryFromActorMessage(message)
    local senderTable = message.sender
    return {
        content = message.content,
        sender = senderTable and senderTable.character or nil,
    }
end

local function inboundDepth()
    return _inboundTail - _inboundHead
end

local function clearInboundQueue()
    _inboundQueue = {}
    _inboundHead = 1
    _inboundTail = 1
end

local function compactInboundQueue()
    local depth = inboundDepth()
    if depth <= 0 then
        clearInboundQueue()
        return
    end
    if _inboundHead < INBOUND_COMPACT_AT_HEAD then return end
    local newQ = {}
    local j = 1
    for i = _inboundHead, _inboundTail - 1 do
        newQ[j] = _inboundQueue[i]
        j = j + 1
    end
    _inboundQueue = newQ
    _inboundHead = 1
    _inboundTail = j
end

local function bumpIdCount(counts, id)
    id = id or '?'
    counts[id] = (counts[id] or 0) + 1
end

local function formatIdHistogram(counts, limit)
    limit = limit or 5
    local entries = {}
    for id, n in pairs(counts) do
        entries[#entries + 1] = { id = id, n = n }
    end
    table.sort(entries, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return tostring(a.id) < tostring(b.id)
    end)
    if #entries == 0 then return '(none)' end
    local parts = {}
    for i = 1, math.min(limit, #entries) do
        local e = entries[i]
        parts[#parts + 1] = string.format('%s=%d', tostring(e.id), e.n)
    end
    return table.concat(parts, ',')
end

local function entryMessageId(entry)
    return entry and entry.content and entry.content.id or nil
end

local function isFollowPriorityEntry(entry)
    local id = entryMessageId(entry)
    return id and FOLLOW_PRIORITY_IDS[id] == true
end

local function findNewestFollowIndex()
    for i = _inboundTail - 1, _inboundHead, -1 do
        if isFollowPriorityEntry(_inboundQueue[i]) then return i end
    end
    return nil
end

local function dequeueInbound()
    if _inboundHead >= _inboundTail then return nil end
    local msg = _inboundQueue[_inboundHead]
    _inboundQueue[_inboundHead] = nil
    _inboundHead = _inboundHead + 1
    if _inboundHead >= _inboundTail then
        clearInboundQueue()
    elseif _inboundHead >= INBOUND_COMPACT_AT_HEAD then
        compactInboundQueue()
    end
    return msg
end

local function enqueueInboundBack(entry)
    _inboundQueue[_inboundTail] = entry
    _inboundTail = _inboundTail + 1
end

local function enqueueInboundFront(entry)
    _inboundHead = _inboundHead - 1
    _inboundQueue[_inboundHead] = entry
end

local function recordDroppedEntry(entry)
    _trafficDropped = _trafficDropped + 1
    bumpIdCount(_dropIdCounts, entryMessageId(entry))
end

local function maybeWarnQueueDepth()
    local depth = inboundDepth()
    if depth < INBOUND_QUEUE_WARN_DEPTH then return end
    local now = mq.gettime()
    if (now - _queueDepthWarnLoggedAt) < TRAFFIC_WINDOW_MS then return end
    _queueDepthWarnLoggedAt = now
    log.say('[czactor] inbound queue depth %d (threshold %d) drained=%d dropped=%d enqueued=%d topIn=%s — drain may be lagging',
        depth, INBOUND_QUEUE_WARN_DEPTH, _trafficDrained, _trafficDropped, _trafficEnqueued,
        formatIdHistogram(_enqueueIdCounts))
end

local function maybeWarnQueueDrops(droppedNow)
    if droppedNow <= 0 then return end
    local now = mq.gettime()
    if (now - _queueDropWarnLoggedAt) < TRAFFIC_WINDOW_MS then return end
    _queueDropWarnLoggedAt = now
    log.say('[czactor] inbound queue capped at %d; dropped %d this tick (window dropped=%d topDrop=%s)',
        INBOUND_QUEUE_MAX_DEPTH, droppedNow, _trafficDropped, formatIdHistogram(_dropIdCounts))
end

local function maybeLogQueueDebug()
    if not _queueDebug then return end
    local now = mq.gettime()
    if (now - _queueDebugLoggedAt) < QUEUE_DEBUG_LOG_MS then return end
    _queueDebugLoggedAt = now
    local windowAge = _trafficWindowStart > 0 and (now - _trafficWindowStart) or 0
    log.say('[czactor] queue debug depth=%d head=%d tail=%d enq=%d drain=%d drop=%d windowAge=%dms topIn=%s topDrop=%s',
        inboundDepth(), _inboundHead, _inboundTail,
        _trafficEnqueued, _trafficDrained, _trafficDropped, windowAge,
        formatIdHistogram(_enqueueIdCounts), formatIdHistogram(_dropIdCounts))
end

local function enforceInboundCap()
    local droppedNow = 0
    while inboundDepth() > INBOUND_QUEUE_MAX_DEPTH do
        local keepIdx = findNewestFollowIndex()
        if keepIdx and keepIdx == _inboundHead then
            local follow = dequeueInbound()
            local victim = dequeueInbound()
            if victim then
                recordDroppedEntry(victim)
                droppedNow = droppedNow + 1
            end
            if follow then enqueueInboundFront(follow) end
            if not victim then break end
        else
            local victim = dequeueInbound()
            if not victim then break end
            recordDroppedEntry(victim)
            droppedNow = droppedNow + 1
        end
    end
    maybeWarnQueueDrops(droppedNow)
end

local function enqueueInbound(entry)
    local id = entryMessageId(entry)
    if id and FOLLOW_PRIORITY_IDS[id] then
        enqueueInboundFront(entry)
    else
        enqueueInboundBack(entry)
    end
    _trafficEnqueued = _trafficEnqueued + 1
    bumpIdCount(_enqueueIdCounts, id)
    enforceInboundCap()
    maybeWarnQueueDepth()
    maybeLogQueueDebug()
end

local function drainInboundQueue()
    local budget = INBOUND_DRAIN_BUDGET
    while budget > 0 do
        local msg = dequeueInbound()
        if not msg then break end
        budget = budget - 1
        _trafficDrained = _trafficDrained + 1
        safeProcessInbound(msg)
    end
    maybeLogQueueDebug()
end

local function destroyActorMailbox()
    if not _actor then return end
    pcall(function() actors.unregister(_actor) end)
    _actor = nil
    collectgarbage('collect')
end

local function mailboxStatusLabel()
    return _actor and 'ok' or 'MISSING'
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

local function nameJitterMs(name, intervalMs)
    name = name or myName() or ''
    intervalMs = intervalMs or 1
    if intervalMs < 1 then intervalMs = 1 end
    local h = 0
    for i = 1, #name do
        h = (h * 31 + string.byte(name, i)) % intervalMs
    end
    return h
end

local function resetTrafficWindowIfNeeded(now)
    if _trafficWindowStart == 0 or (now - _trafficWindowStart) >= TRAFFIC_WINDOW_MS then
        _trafficWindowStart = now
        _trafficRecv = 0
        _trafficSendBroadcast = 0
        _trafficSendUnicast = 0
        _trafficDrained = 0
        _trafficDropped = 0
        _trafficEnqueued = 0
        _dropIdCounts = {}
        _enqueueIdCounts = {}
    end
end

local function recordRecv()
    local now = mq.gettime()
    resetTrafficWindowIfNeeded(now)
    _trafficRecv = _trafficRecv + 1
end

local function recordSendBroadcast()
    local now = mq.gettime()
    resetTrafficWindowIfNeeded(now)
    _trafficSendBroadcast = _trafficSendBroadcast + 1
end

local function recordSendUnicast()
    local now = mq.gettime()
    resetTrafficWindowIfNeeded(now)
    _trafficSendUnicast = _trafficSendUnicast + 1
end

local function touchPeer(sender)
    if not sender or sender == '' then return end
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)
    rc.CzActorPeers[sender] = mq.gettime()
end

local function scheduleInitialTimers(now)
    local me = myName() or ''
    _nextPingAt = now + nameJitterMs(me, PING_INTERVAL_MS)
    _nextRoleClaimsAt = now + nameJitterMs(me, ROLE_CLAIMS_INTERVAL_MS)
    _nextClaimPruneAt = now + nameJitterMs(me, 1000)
    _nextOtHeartbeatAt = now + nameJitterMs(me, OT_HEARTBEAT_MS)
    _maEngagedHeartbeatNext = now + nameJitterMs(me, MA_ENGAGED_HEARTBEAT_MS)
end

function czactor.shutdown()
    destroyActorMailbox()
    clearInboundQueue()
end

--- Register the czbot mailbox once at macro startup. Safe to call again (no-op).
---@return boolean true when mailbox registered successfully
function czactor.init()
    if _actor then
        log.say('[czactor] init called but mailbox already registered')
        return true
    end
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)
    local now = mq.gettime()
    _lastInitAttemptAt = now
    _lastTickAt = now
    local registerErr
    local ok, result = pcall(function()
        return actors.register(MAILBOX, function(message)
            if not message then return end
            recordRecv()
            local content = message.content
            if type(content) ~= 'table' then return end
            local entry = inboundEntryFromActorMessage(message)
            if shouldProcessInline(content) then
                safeProcessInbound(entry)
                return
            end
            enqueueInbound(entry)
        end)
    end)
    if ok and result then
        _actor = result
    elseif ok then
        registerErr = 'actors.register returned nil'
    else
        registerErr = tostring(result)
    end
    if _actor then
        log.say('czactor: mailbox %s registered', MAILBOX)
        _lastInitError = nil
    else
        _lastInitError = registerErr
        local detail = registerErr and (' (' .. registerErr .. ')') or ''
        log.say('[czactor] mailbox %s registration FAILED%s — restart the macro', MAILBOX, detail)
    end
    scheduleInitialTimers(now)
    clearInboundQueue()
    _trafficWindowStart = now
    _trafficRecv = 0
    _trafficSendBroadcast = 0
    _trafficSendUnicast = 0
    _trafficDrained = 0
    _trafficDropped = 0
    _trafficEnqueued = 0
    _dropIdCounts = {}
    _enqueueIdCounts = {}
    _whosMaBackoffMs = WHOS_BACKOFF_MIN_MS
    _whosMtBackoffMs = WHOS_BACKOFF_MIN_MS
    return _actor ~= nil
end

function czactor.broadcast(msg)
    if not _actor then return end
    recordSendBroadcast()
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
    recordSendUnicast()
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
    _lastImMaPublishAt = mq.gettime()
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
    _lastImMtPublishAt = mq.gettime()
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

function czactor.publishWhosMa()
    local fields = { scope = roleBroadcastScope() }
    czactor_dispatch.logSend('whos_ma', fields)
    czactor.broadcast(envelope('whos_ma', fields))
end

function czactor.publishWhosMt()
    local fields = { scope = roleBroadcastScope() }
    czactor_dispatch.logSend('whos_mt', fields)
    czactor.broadcast(envelope('whos_mt', fields))
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
    local now = mq.gettime()
    if actions.askWhosMa and (now - _lastWhosMaAt) >= _whosMaBackoffMs then
        _lastWhosMaAt = now
        czactor.publishWhosMa()
        _whosMaBackoffMs = math.min(WHOS_BACKOFF_MAX_MS, math.max(WHOS_BACKOFF_MIN_MS, _whosMaBackoffMs * 2))
    end
    if actions.askWhosMt and (now - _lastWhosMtAt) >= _whosMtBackoffMs then
        _lastWhosMtAt = now
        czactor.publishWhosMt()
        _whosMtBackoffMs = math.min(WHOS_BACKOFF_MAX_MS, math.max(WHOS_BACKOFF_MIN_MS, _whosMtBackoffMs * 2))
    end
end

local function resetWhosMaBackoff()
    _whosMaBackoffMs = WHOS_BACKOFF_MIN_MS
end

local function resetWhosMtBackoff()
    _whosMtBackoffMs = WHOS_BACKOFF_MIN_MS
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
        return namesMatch(leaderName, me) or charinfo.GetInfo(leaderName) ~= nil
    end
    if scope == 'raid' then
        local raidMembers = mq.TLO.Raid.Members() or 0
        if raidMembers > 0 then
            for i = 1, raidMembers do
                if namesMatch(mq.TLO.Raid.Member(i).Name(), leaderName) then return true end
            end
        end
        if mq.TLO.Group.Member(leaderName).Index() then return true end
        return namesMatch(leaderName, me)
    end
    if namesMatch(leaderName, me) then return true end
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
    -- Post-zone Group.Member index can lag while EQ Main Tank / mt_list top is already known.
    local primary = auto_ma_mt.mtPrimaryTloName()
    if primary and namesMatch(primary, sender) then return true end
    local top = auto_ma_mt.topMtCandidateInZone()
    if top and namesMatch(top, sender) then return true end
    return auto_ma_mt.groupLacksActiveMt()
end

--- Accept whos_mt asks from group/raid peers; after zone, also accept when we have no
--- usable MT override so peers can re-discover the holder even if Group.Member lags.
local function acceptMtWhosAsk(sender)
    if not sender or sender == '' then return false end
    if inRaid() then
        return auto_ma_mt.isSenderInMyRaid(sender)
    end
    if auto_ma_mt.isSenderInMyGroup(sender) then return true end
    if not auto_ma_mt.getActorMtOverrideName() then return true end
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
    if cur and cur.name and not auto_ma_mt.isActorHolderAvailable(cur, false) then
        cur = nil
    end
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
    resetWhosMaBackoff()
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
    resetWhosMtBackoff()
end

local function expireMaClaimOverride()
    local rc = state.getRunconfig()
    local o = rc.ActorMaOverride
    if not o then return false end
    clearMaActorEngaged(rc, o.name)
    rc.ActorMaOverride = nil
    if o.inGroup then rc.MaReleased = true end
    tankrole.invalidateMa()
    return true
end

local function expireMtClaimOverride()
    local rc = state.getRunconfig()
    local o = rc.ActorMtOverride
    if not o then return false end
    rc.ActorMtOverride = nil
    if o.inGroup then rc.MtReleased = true end
    tankrole.invalidateMt()
    return true
end

--- Expire unavailable im_ma/im_mt overrides; re-run claim selection when any cleared.
---@param now number|nil mq.gettime() for tests; defaults to current time
---@return boolean anyExpired
function czactor.sweepExpiredRoleClaims(now)
    now = now or mq.gettime()
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)
    local anyExpired = false

    if rc.ActorMaOverride then
        if not auto_ma_mt.isActorHolderAvailable(rc.ActorMaOverride, false) then
            expireMaClaimOverride()
            anyExpired = true
        end
    end
    if rc.ActorMtOverride then
        if not auto_ma_mt.isActorHolderAvailable(rc.ActorMtOverride, false) then
            expireMtClaimOverride()
            anyExpired = true
        end
    end

    if anyExpired then
        czactor.onRoleReleaseReceived()
    end
    return anyExpired
end

function czactor.runRoleClaimsTick()
    local now = mq.gettime()
    if now < _nextRoleClaimsAt then return end
    _nextRoleClaimsAt = now + ROLE_CLAIMS_INTERVAL_MS
    czactor.sweepExpiredRoleClaims(now)
    local rc = state.getRunconfig()
    if not rc.maEligible and not rc.mtEligible and not rc.MaImHolding and not rc.MtImHolding then
        return
    end
    applyRoleClaimActions(auto_ma_mt.evaluateRoleClaims({ trigger = 'periodic' }))
end

--- After zone settle: rebroadcast im_mt/im_ma when this bot still holds or should claim,
--- so peers whose overrides expired during zone load can restore Actor*Override without
--- waiting on a whos_* round-trip that may also be gated by group-index lag.
function czactor.rebroadcastRoleClaimsAfterZone()
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)

    local claimMt, mtSource, mtIdx = auto_ma_mt.shouldClaimMt()
    if claimMt then
        czactor.publishImMt(mtSource, mtIdx or 0)
    elseif rc.MtImHolding then
        local top, topSource, topIdx = auto_ma_mt.topMtCandidateInZone()
        if top and namesMatch(top, myName()) then
            czactor.publishImMt(topSource or 'list', topIdx or 0)
        else
            local o = rc.ActorMtOverride
            czactor.publishImMt(o and o.source or 'list', o and o.listIndex or 0)
        end
    end

    local claimMa, maSource, maIdx = auto_ma_mt.shouldClaimMa()
    if claimMa then
        czactor.publishImMa(maSource, maIdx or 0)
    elseif rc.MaImHolding then
        local o = rc.ActorMaOverride
        czactor.publishImMa(o and o.source or 'list', o and o.listIndex or 0)
    end
end

local function respondToWhosMa()
    local rc = state.getRunconfig()
    local claim, source, listIndex = auto_ma_mt.shouldClaimMa()
    local now = mq.gettime()
    if claim then
        if rc.MaImHolding and (now - _lastImMaPublishAt) < ROLE_CLAIMS_INTERVAL_MS then
            return
        end
        czactor.publishImMa(source, listIndex)
        return
    end
    if rc.MaImHolding then
        if (now - _lastImMaPublishAt) < ROLE_CLAIMS_INTERVAL_MS then return end
        local o = rc.ActorMaOverride
        czactor.publishImMa(o and o.source or 'list', o and o.listIndex or 0)
    end
end

local function respondToWhosMt()
    local rc = state.getRunconfig()
    local claim, source, listIndex = auto_ma_mt.shouldClaimMt()
    local now = mq.gettime()
    if claim then
        if rc.MtImHolding and (now - _lastImMtPublishAt) < ROLE_CLAIMS_INTERVAL_MS then
            return
        end
        czactor.publishImMt(source, listIndex)
        return
    end
    if rc.MtImHolding then
        if (now - _lastImMtPublishAt) < ROLE_CLAIMS_INTERVAL_MS then return end
        local o = rc.ActorMtOverride
        czactor.publishImMt(o and o.source or 'list', o and o.listIndex or 0)
        return
    end
    -- Soft eligibility: automatic tanks whose EQ/list top is self still answer after a
    -- brief shouldClaimMt dip (e.g. post-zone proximity/charinfo lag).
    local tankSetting = rc.TankName
    if tankSetting == nil or tankSetting == '' then tankSetting = rc.AssistName end
    if tankSetting ~= 'automatic' then return end
    local top, topSource, topIdx = auto_ma_mt.topMtCandidateInZone()
    if top and namesMatch(top, myName()) then
        if (now - _lastImMtPublishAt) < ROLE_CLAIMS_INTERVAL_MS then return end
        czactor.publishImMt(topSource or 'list', topIdx or 0)
    end
end

local function applyWhosMa(content, sender)
    if sender and namesMatch(sender, myName()) then return end
    if content.zone and not zonesMatch(content.zone, myZone()) then return end
    if not acceptMaClaim(sender) then return end
    respondToWhosMa()
end

local function applyWhosMt(content, sender)
    if sender and namesMatch(sender, myName()) then return end
    if content.zone and not zonesMatch(content.zone, myZone()) then return end
    if not acceptMtWhosAsk(sender) then return end
    respondToWhosMt()
end

clearMaActorEngaged = function(rc, maName)
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
    local reason = content.reason
    if MA_DISENGAGE_TRANSIENT_REASONS[reason] then
        local rc = state.getRunconfig()
        local eng = rc.MaActorEngaged
        if eng and eng.spawnId and namesMatch(eng.maName, sender) and isAliveEngageSpawnId(eng.spawnId) then
            local assistName = tankrole.GetAssistTargetName()
            if assistName and namesMatch(sender, assistName) then
                return
            end
        end
    end
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

function czactor.publishMaEngaged(spawnId, mobName, force)
    if not spawnId or spawnId <= 0 then return end
    if not force and _lastMaEngagedSpawnId == spawnId then return end
    _lastMaEngagedSpawnId = spawnId
    czactor.publish('ma_engaged', {
        spawnId = spawnId,
        mobName = mobName,
        scope = roleBroadcastScope(),
    })
end

--- Re-broadcast ma_engaged while MA holds engageTargetId (followers recover missed messages).
function czactor.tickMaEngagedHeartbeat(spawnId, mobName)
    if not spawnId or spawnId <= 0 then return end
    local now = mq.gettime()
    if now < _maEngagedHeartbeatNext then return end
    _maEngagedHeartbeatNext = now + MA_ENGAGED_HEARTBEAT_MS + nameJitterMs(myName(), MA_ENGAGED_HEARTBEAT_MS)
    czactor.publishMaEngaged(spawnId, mobName, true)
end

function czactor.publishMaDisengage(reason)
    _lastMaEngagedSpawnId = nil
    _maEngagedHeartbeatNext = 0
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
            _nextOtHeartbeatAt = mq.gettime() + OT_HEARTBEAT_MS + nameJitterMs(myName(), OT_HEARTBEAT_MS)
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
    if namesMatch(content.leader, myName()) then
        log.say('[Follow] ignored follow_me (self leader)')
        return
    end
    if not czactor.matchesBroadcastScope(content.scope, content.leader) then
        log.say('[Follow] ignored follow_me from %s (scope=%s)', content.leader, content.scope or 'group')
        return
    end
    log.say('[Follow] follow_me from %s (scope=%s)', content.leader, content.scope or 'group')
    require('lib.follow').StartFollow(content.leader)
end

local function handleLeaderFollowMeOff(content)
    if not czactor.matchesBroadcastScope(content.scope, content.leader) then
        log.say('[Follow] ignored follow_me_off from %s (scope=%s)', content.leader, content.scope or 'group')
        return
    end
    log.say('[Follow] follow_me_off from %s (scope=%s)', content.leader, content.scope or 'group')
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

processMessage = function(inbound)
    if not inbound then return end
    local content = inbound.content
    if type(content) ~= 'table' then return end
    if content.ver and content.ver ~= PROTOCOL_VER then return end
    local sender = senderCharacter(inbound)
    touchPeer(sender)
    local id = content.id
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)

    if id == 'ping' or id == 'pong' then return end

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
    if id == 'whos_ma' then
        czactor_dispatch.logRecvIfRoleClaimDebug(id, sender, content)
        applyWhosMa(content, sender)
        return
    end
    if id == 'whos_mt' then
        czactor_dispatch.logRecvIfRoleClaimDebug(id, sender, content)
        applyWhosMt(content, sender)
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
    local now = mq.gettime()
    if now < _nextCzactorTickAt then return end
    _nextCzactorTickAt = now + CZACTOR_TICK_MS
    resetTrafficWindowIfNeeded(now)

    if _lastTickAt > 0 and (now - _lastTickAt) > TICK_STALE_MS then
        if (now - _tickStaleLoggedAt) > TICK_STALE_MS then
            _tickStaleLoggedAt = now
            log.say('[czactor] tick stale (%.1fs, queue=%d) — check mainloop/hooks',
                (now - _lastTickAt) / 1000, inboundDepth())
        end
    end
    _lastTickAt = now

    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)

    tickprof.span('drainInbound', function()
        drainInboundQueue()
    end)
    local common_sync = package.loaded['lib.common_sync']
    if common_sync and common_sync.tickPending then
        tickprof.span('common_sync', function()
            common_sync.tickPending()
        end)
    end

    local now = mq.gettime()
    if now >= _nextPingAt then
        _nextPingAt = now + PING_INTERVAL_MS
        czactor.broadcast(envelope('ping', {}))
    end

    if now >= _nextClaimPruneAt then
        tickprof.span('claimPrune', function()
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
        end)
    end

    tickprof.span('roleClaims', function()
        czactor.runRoleClaimsTick()
    end)
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

local function countRecentCzActorPeers(rc, withinMs)
    local now = mq.gettime()
    local total, recent = 0, 0
    for _, name in ipairs(charinfo.GetPeers()) do
        total = total + 1
        local last = rc.CzActorPeers[name]
        if last and (now - last) <= withinMs then
            recent = recent + 1
        end
    end
    return recent, total
end

function czactor.printStatus()
    local rc = state.getRunconfig()
    ensureRunconfigFields(rc)
    local now = mq.gettime()
    local depth = inboundDepth()
    local lastTickAge = _lastTickAt > 0 and string.format('%.1fs ago', (now - _lastTickAt) / 1000) or 'never'
    local recent, total = countRecentCzActorPeers(rc, PEER_RECENT_MS)
    local followLabel = (rc.followname and rc.followname ~= '') and rc.followname or '(none)'
    local mailboxLabel = mailboxStatusLabel()
    local windowAge = _trafficWindowStart > 0 and (now - _trafficWindowStart) or 0
    printf('  czactor: mailbox=%s lastTick=%s queue=%d (head=%d tail=%d) peersRecent=%d/%d follow=%s catchUp=%s',
        mailboxLabel, lastTickAge, depth, _inboundHead, _inboundTail, recent, total,
        followLabel, tostring(rc.followCatchUp == true))
    if depth >= INBOUND_QUEUE_WARN_DEPTH then
        printf('  WARNING: inbound queue depth %d (threshold %d, cap %d)',
            depth, INBOUND_QUEUE_WARN_DEPTH, INBOUND_QUEUE_MAX_DEPTH)
    end
    printf('  traffic (window %dms): recv=%d enqueued=%d drained=%d dropped=%d sendBroadcast=%d sendUnicast=%d',
        windowAge, _trafficRecv, _trafficEnqueued, _trafficDrained, _trafficDropped,
        _trafficSendBroadcast, _trafficSendUnicast)
    printf('  inbound ids: %s', formatIdHistogram(_enqueueIdCounts))
    if _trafficDropped > 0 then
        printf('  dropped ids: %s', formatIdHistogram(_dropIdCounts))
    end
    printf('  whos backoff: ma=%dms mt=%dms queueDebug=%s',
        _whosMaBackoffMs, _whosMtBackoffMs, tostring(_queueDebug))
    if mailboxLabel == 'MISSING' then
        printf('  WARNING: czbot mailbox not registered — Actor messages (followme, camphere, attack, MA/MT) are not sent or received. Restart the macro.')
        local initAge = _lastInitAttemptAt > 0 and string.format('%.1fs ago', (now - _lastInitAttemptAt) / 1000) or 'never'
        printf('  lastInitAttempt=%s', initAge)
        if _lastInitError then
            printf('  lastInitError=%s', _lastInitError)
        end
    elseif _lastTickAt > 0 and (now - _lastTickAt) > TICK_STALE_MS then
        printf('  WARNING: czactor tick stale (%.1fs) — mainloop or hooks may be blocked',
            (now - _lastTickAt) / 1000)
    end
    czactor.printPeerStatus()
    local maO = rc.ActorMaOverride
    local mtO = rc.ActorMtOverride
    printf('  MA override: %s', maO and maO.name or '(none)')
    if maO then
        local claimAge = maO.ts and string.format('%.1fs ago', (now - maO.ts) / 1000) or 'unknown'
        printf('    seq=%s source=%s listIndex=%s zone=%s publisher=%s inGroup=%s reason=%s claimed=%s',
            tostring(maO.seq), tostring(maO.source), tostring(maO.listIndex),
            tostring(maO.zone), tostring(maO.publisher), tostring(maO.inGroup),
            tostring(maO.reason), claimAge)
    end
    printf('  MT override: %s', mtO and mtO.name or '(none)')
    if mtO then
        local claimAge = mtO.ts and string.format('%.1fs ago', (now - mtO.ts) / 1000) or 'unknown'
        printf('    seq=%s source=%s listIndex=%s zone=%s publisher=%s inGroup=%s reason=%s claimed=%s',
            tostring(mtO.seq), tostring(mtO.source), tostring(mtO.listIndex),
            tostring(mtO.zone), tostring(mtO.publisher), tostring(mtO.inGroup),
            tostring(mtO.reason), claimAge)
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

function czactor.SetQueueDebug(on)
    _queueDebug = on and true or false
end

function czactor.IsQueueDebug()
    return _queueDebug
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
