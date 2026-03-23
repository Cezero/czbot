local mq = require('mq')
local botconfig = require('lib.config')
local combat = require('lib.combat')
local state = require('lib.state')
local bothooks = require('lib.bothooks')
local targeting = require('lib.targeting')
local utils = require('lib.utils')
local charinfo = require("mqcharinfo")
local myconfig = botconfig.config

local botmove = {}
local CorpseID = nil
local carryCorpseID = nil
local lastFollowResolveFailTime = 0

-- ---------------------------------------------------------------------------
-- Follow / stuck helpers
-- ---------------------------------------------------------------------------

local function refreshFollowId()
    local rc = state.getRunconfig()
    if not rc.followid or rc.followid == 0 then
        if rc.followname and rc.followname ~= '' then
            local id = mq.TLO.Spawn('=' .. rc.followname).ID()
            if id then rc.followid = id end
        end
        if not rc.followid or rc.followid == 0 then return end
    end
    local followid = rc.followid
    if not followid or followid == 0 then return end
    -- After zone, spawn by old id is invalid; re-resolve from followname. Clear stale id if leader not in zone yet.
    if not mq.TLO.Spawn('id ' .. followid).ID() or mq.TLO.Spawn('id ' .. followid).Type() == 'Corpse' then
        local id = rc.followname and rc.followname ~= '' and mq.TLO.Spawn('=' .. rc.followname).ID()
        if id then
            rc.followid = id
        else
            local now = mq.gettime()
            local oldName = rc.followname
            rc.followid = 0
            rc.followname = ''
            if now >= lastFollowResolveFailTime + 15000 then
                lastFollowResolveFailTime = now
                if oldName and oldName ~= '' then
                    printf('\ayCZBot:\axFollow: unable to resolve leader "%s" in zone; clearing follow.', oldName)
                else
                    printf('\ayCZBot:\axFollow: unable to resolve current follow target; clearing follow.')
                end
            end
        end
    end
end

local function doFollowNav()
    local rc = state.getRunconfig()
    if mq.TLO.Me.Sneaking() then mq.cmd('/doability sneak') end
    mq.cmdf('/nav id %s log=off', rc.followid)
end

local function shouldCallFollow(rc)
    local followid = mq.TLO.Spawn(rc.followid).ID() or 0
    local followdistance = mq.TLO.Spawn(rc.followid).Distance() or 0
    local engageId = rc.engageTargetId or 0
    local followtype = mq.TLO.Spawn(rc.followid).Type() or "none"
    return followid > 0 and followdistance > 0 and engageId == 0 and followtype ~= 'CORPSE' and
        followdistance >= myconfig.settings.followdistance
end

local function updateStuckTimerWithinLeash(rc)
    local d3 = mq.TLO.Spawn(rc.followid).Distance3D()
    if d3 and d3 <= myconfig.settings.acleash and (not rc.stucktimer or rc.stucktimer < mq.gettime() + 60000) then
        rc.stucktimer = mq.gettime() + 60000
    end
end

-- ---------------------------------------------------------------------------
-- UnStuck phase handlers
-- ---------------------------------------------------------------------------

local UNSTUCK_EXIT_COOLDOWN_MS = 60000

local function tickUnstuckPhase(p, followid, stuckdistance)
    local rc = state.getRunconfig()
    if not p or p.followid ~= followid then
        rc.stucktimer = mq.gettime() + UNSTUCK_EXIT_COOLDOWN_MS
        state.clearRunState()
        return true
    end
    if mq.gettime() < (p.deadline or 0) then return true end
    local nowdist = mq.TLO.Spawn(followid).Distance3D()
    if p.phase == 'nav_wait5' then
        if nowdist and stuckdistance >= nowdist + 10 then
            rc.stucktimer = mq.gettime() + UNSTUCK_EXIT_COOLDOWN_MS
            state.clearRunState()
            return true
        end
        rc.stucktimer = mq.gettime() + UNSTUCK_EXIT_COOLDOWN_MS
        state.clearRunState()
    elseif p.phase == 'wiggle_wait' then
        mq.cmd('/squelch /keypress forward')
        mq.cmdf('/squelch /nav id %s log=off', followid)
        if nowdist and stuckdistance >= nowdist + 10 then
            rc.stucktimer = mq.gettime() + UNSTUCK_EXIT_COOLDOWN_MS
            state.clearRunState()
            return true
        end
        mq.cmd('/squelch /keypress back hold')
        if state.canStartBusyState(state.STATES.unstuck) then
            state.setRunState(state.STATES.unstuck,
                {
                    phase = 'back_wait',
                    deadline = mq.gettime() + 2000,
                    followid = followid,
                    stuckdistance = stuckdistance,
                    priority =
                        bothooks.getPriority('doMiscTimer')
                })
        end
    elseif p.phase == 'back_wait' then
        mq.cmd('/squelch /keypress back')
        mq.cmdf('/squelch /nav id %s log=off', followid)
        rc.stucktimer = mq.gettime() + UNSTUCK_EXIT_COOLDOWN_MS
        state.clearRunState()
    end
    return true
end

local function tryPathExistsUnstuck(followid)
    if not followid or followid == 0 then return false end
    if not mq.TLO.Navigation.PathExists('id ' .. followid)() then return false end
    mq.cmdf('/nav id %s los=on dist=15 log=off', followid)
    if state.canStartBusyState(state.STATES.unstuck) then
        state.setRunState(state.STATES.unstuck,
            {
                phase = 'nav_wait5',
                deadline = mq.gettime() + 5000,
                followid = followid,
                priority = bothooks.getPriority(
                    'doMiscTimer')
            })
    end
    return true
end

local function tryAutoSizeUnstuck(followid, stuckdistance)
    if not mq.TLO.Navigation.Active() then return false end
    if mq.TLO.Plugin("MQ2AutoSize").IsLoaded() then mq.cmd('/autosize sizeself 1') end
    local d = mq.TLO.Spawn(followid).Distance3D()
    local rc = state.getRunconfig()
    if d and stuckdistance >= d + 10 then
        rc.stucktimer = mq.gettime() + 60000
        return true
    end
    if mq.TLO.Plugin("MQ2AutoSize").IsLoaded() then mq.cmd('/autosize sizeself 12') end
    d = mq.TLO.Spawn(followid).Distance3D()
    if d and stuckdistance >= d + 10 then
        rc.stucktimer = mq.gettime() + 60000
        return true
    end
    if mq.TLO.Plugin("MQ2AutoSize").IsLoaded() then mq.cmd('/autosize sizeself 8') end
    d = mq.TLO.Spawn(followid).Distance3D()
    if d and stuckdistance >= d + 10 then
        rc.stucktimer = mq.gettime() + 60000
        return true
    end
    return false
end

-- Unstuck wiggle: last step uses random heading/size (obstacle avoidance; movement needed is unknown).
local function doWiggleUnstuck(followid, stuckdistance)
    local rc = state.getRunconfig()
    local stuckdir = math.random(0, 360)
    local ransize = math.random(1, 12)
    local wiggleHeadings = { 0, 90, 180, 270, 0, 90, 180, 270, stuckdir }
    local wiggleSizes = { 1, 1, 1, 1, 12, 12, 12, 12, ransize }
    mq.cmd('/nav stop')
    local idx = (rc.unstuckWiggleIndex or 0) + 1
    rc.unstuckWiggleIndex = idx
    local heading = wiggleHeadings[idx] or stuckdir
    local size = wiggleSizes[idx] or ransize
    print('facing heading:', heading, ' sizing to:', size) -- not debug, but needs reformatting / context to be meaningful
    if mq.TLO.Plugin("MQ2AutoSize").IsLoaded() then
        mq.cmdf('/squelch /multiline ; /face fast heading %s ; /stand ; /autosize sizeself %s ; /keypress forward hold',
            heading, size)
    end
    if state.canStartBusyState(state.STATES.unstuck) then
        state.setRunState(state.STATES.unstuck,
            {
                phase = 'wiggle_wait',
                deadline = mq.gettime() + 2000,
                followid = followid,
                stuckdistance = stuckdistance,
                priority =
                    bothooks.getPriority('doMiscTimer')
            })
    end
    if idx >= 9 then rc.unstuckWiggleIndex = nil end
end

-- ---------------------------------------------------------------------------
-- Engage return-to-follow phase handlers
-- ---------------------------------------------------------------------------

local function tickEngageReturnDelay400(p)
    local now = mq.gettime()
    if now < (p.deadline or 0) then return end
    if state.canStartBusyState(state.STATES.engage_return_follow) then
        state.setRunState(state.STATES.engage_return_follow,
            { phase = 'nav_wait', deadline = now + 10000, priority = bothooks.getPriority('doMiscTimer') })
    end
end

local function tickEngageReturnNavWait(p)
    local now = mq.gettime()
    if not mq.TLO.Navigation.Active() or now >= (p.deadline or 0) then
        state.clearRunState()
    end
end

-- ---------------------------------------------------------------------------
-- MakeCamp leash helpers
-- ---------------------------------------------------------------------------

local function campDistanceOk(rc)
    local campCloseSq = myconfig.settings.campRestDistanceSq
    local distSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), rc.makecamp.x, rc.makecamp.y)
    return distSq and campCloseSq and distSq <= campCloseSq
end

local function campLOSOk(rc)
    if not rc.makecamp or not rc.makecamp.x or not rc.makecamp.y or not rc.makecamp.z then
        return false
    end
    local meX, meY, meZ = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
    if not meX or not meY or not meZ then
        return false
    end
    return mq.TLO.LineOfSight(meX ..
        ',' .. meY .. ',' .. meZ .. ':' .. rc.makecamp.x .. ',' .. rc.makecamp.y .. ',' .. rc.makecamp.z)()
end

local function hasCampSet(rc)
    return rc and rc.campstatus and rc.makecamp and rc.makecamp.x and rc.makecamp.y and rc.makecamp.z
end

local function isCampDragWorkflowActive()
    if state.getRunState() ~= state.STATES.dragging then return false end
    local p = state.getRunStatePayload()
    return p and p.mode == 'camp_fetch'
end

local function isCorpseAtCamp(corpseID, rc)
    if not corpseID or not hasCampSet(rc) then return false end
    local corpseX = mq.TLO.Spawn(corpseID).X()
    local corpseY = mq.TLO.Spawn(corpseID).Y()
    if not corpseX or not corpseY then return false end
    local campCloseSq = myconfig.settings.campRestDistanceSq
    local distSq = utils.getDistanceSquared2D(corpseX, corpseY, rc.makecamp.x, rc.makecamp.y)
    return distSq and campCloseSq and distSq <= campCloseSq
end

local function doLeashResetCombat()
    combat.ResetCombatState()
end

-- Navigate to camp location (makecamp.x/y/z). opts: dist (number|nil), echoMsg (string|nil).
local function doNavToCamp(opts)
    opts = opts or {}
    local rc = state.getRunconfig()
    if not rc.makecamp.x or not rc.makecamp.y or not rc.makecamp.z then return end
    if opts.echoMsg then mq.cmd('/echo ' .. opts.echoMsg) end
    if opts.dist ~= nil then
        mq.cmdf('/nav locxyz %s %s %s log=off dist=%s', rc.makecamp.x, rc.makecamp.y, rc.makecamp.z, opts.dist)
    else
        mq.cmdf('/nav locxyz %s %s %s log=off', rc.makecamp.x, rc.makecamp.y, rc.makecamp.z)
    end
end

-- ---------------------------------------------------------------------------
-- MakeCamp (on / off / return) helpers
-- ---------------------------------------------------------------------------

local function setCampHere()
    local rc = state.getRunconfig()
    rc.makecamp.x = mq.TLO.Me.X()
    rc.makecamp.y = mq.TLO.Me.Y()
    rc.makecamp.z = mq.TLO.Me.Z()
end

local function makeCampOn()
    if mq.TLO.Stick.Active() then mq.cmd('/stick off') end
    if mq.TLO.Navigation.Active() then mq.cmd('/nav stop log=off') end
    if not mq.TLO.Navigation.MeshLoaded() then
        printf('\ayCZBot:\axCannot use makecamp (no mesh loaded)')
        return false
    end
    setCampHere()
    state.getRunconfig().campstatus = true
    local rc = state.getRunconfig()
    rc.followid = 0
    rc.followname = ''
    printf('\ayCZBot:\axhanging out using mq2nav')
    return true
end

local function makeCampOff()
    if not myconfig.pull.hunter then state.getRunconfig().makecamp = { x = nil, y = nil, z = nil } end
    state.getRunconfig().campstatus = false
    printf('\ayCZBot:\axmakecamp \aroff\ax')
end

local function makeCampReturn()
    doLeashResetCombat()
    doNavToCamp()
    if state.canStartBusyState(state.STATES.camp_return) then
        state.setRunState(state.STATES.camp_return,
            { deadline = mq.gettime() + 5000, priority = bothooks.getPriority('doMiscTimer') })
    end
end

-- ---------------------------------------------------------------------------
-- DragCheck helpers
-- ---------------------------------------------------------------------------

local DragDist = 1500

local function tickSumcorpsePending()
    if state.getRunState() ~= state.STATES.sumcorpse_pending then return false end
    local p = state.getRunStatePayload()
    if p and p.corpseID then
        targeting.TargetAndWait(p.corpseID, 500)
        mq.cmd('/sumcorpse')
    end
    state.clearRunState()
    return true
end

local function tickDragging(payload)
    if not payload or not payload.corpseID then
        state.clearRunState()
        return true
    end
    local rc = state.getRunconfig()
    local cid = payload.corpseID
    if payload.phase == 'init' then
        if mq.gettime() < (payload.deadline or 0) then return true end
        mq.cmd('/hidec none')
        mq.cmd('/hidec alwaysnpc')
        mq.cmd('/multiline ; /attack off ; /stick off')
        targeting.TargetAndWait(cid, 500)
        if state.canStartBusyState(state.STATES.dragging) then
            state.setRunState(state.STATES.dragging,
                {
                    phase = 'sneak',
                    mode = payload.mode,
                    corpseID = cid,
                    priority = bothooks.getPriority('doMiscTimer')
                })
        end
        return true
    end
    if payload.phase == 'sneak' then
        if mq.TLO.Me.Class.ShortName() == 'ROG' and (not mq.TLO.Me.Invis() or not mq.TLO.Me.Sneaking()) then
            if not mq.TLO.Me.Sneaking() then mq.cmd('/squelch /doability sneak') end
            if mq.TLO.Me.AbilityReady("Hide")() then mq.cmd('/squelch /doability hide') end
            return true
        end
        mq.cmdf('/nav id %s', cid)
        if state.canStartBusyState(state.STATES.dragging) then
            state.setRunState(state.STATES.dragging,
                {
                    phase = 'navigating',
                    mode = payload.mode,
                    corpseID = cid,
                    priority = bothooks.getPriority('doMiscTimer')
                })
        end
        return true
    end
    if payload.phase == 'navigating' then
        if not mq.TLO.Navigation.Active() then
            state.clearRunState()
            return true
        end
        local corpsedist = mq.TLO.Spawn(cid).Distance3D()
        if mq.TLO.Spawn(cid).ID() and corpsedist and corpsedist < 90 then
            if not targeting.TargetAndWait(cid, 1000) then
                return true
            end
            mq.cmd('/multiline ; /corpsedrag ; /nav stop')
            if payload.mode == 'carry' then
                carryCorpseID = cid
                state.clearRunState()
                CorpseID = nil
                return true
            end
            if payload.mode == 'camp_fetch' and hasCampSet(rc) then
                doNavToCamp({ dist = myconfig.settings.campRestDistance or 15 })
                if state.canStartBusyState(state.STATES.dragging) then
                    state.setRunState(state.STATES.dragging,
                        {
                            phase = 'returning_camp',
                            mode = 'camp_fetch',
                            corpseID = cid,
                            deadline = mq.gettime() + 20000,
                            priority = bothooks.getPriority('doMiscTimer')
                        })
                end
                return true
            end
            state.clearRunState()
            CorpseID = nil
            return true
        end
    end
    if payload.phase == 'returning_camp' then
        if hasCampSet(rc) and campDistanceOk(rc) and campLOSOk(rc) then
            if mq.TLO.Navigation.Active() then mq.cmd('/nav stop') end
            if not targeting.TargetAndWait(cid, 1000) then
                return true
            end
            mq.cmd('/corpsedrop')
            state.clearRunState()
            CorpseID = nil
            return true
        end
        if not mq.TLO.Navigation.Active() or mq.gettime() >= (payload.deadline or 0) then
            state.clearRunState()
            CorpseID = nil
            return true
        end
    end
    return true
end

local function findCorpseCandidates(maxDist, mode)
    local rc = state.getRunconfig()
    local bots = charinfo.GetPeers()
    local searchDist = maxDist or DragDist
    local candidates = {}
    for cor = 1, charinfo.GetPeerCnt() do
        local bot = bots[cor]
        if bot then
            local corpseSpawn = mq.TLO.Spawn(bot .. "'s corpse")
            local corpseType = corpseSpawn.Type()
            local corpsedist = corpseSpawn.Distance()
            local corpseID = corpseSpawn.ID()
            local inRange = corpseType == 'Corpse' and corpsedist and corpsedist > 10 and corpsedist < searchDist
            if inRange and corpseID then
                local atCamp = mode == 'camp_fetch' and isCorpseAtCamp(corpseID, rc)
                if not atCamp then
                    candidates[#candidates + 1] = { id = corpseID, dist = corpsedist }
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        return a.dist > b.dist
    end)
    return candidates
end

local function startDrag(corpseId, justDidSumcorpse, mode)
    local rc = state.getRunconfig()
    if rc.DragHack and corpseId and not justDidSumcorpse then
        targeting.TargetAndWait(corpseId, 500)
        mq.cmd('/sumcorpse')
        return true
    end
    if corpseId and mq.TLO.Navigation.PathExists('id ' .. corpseId)() then
        mq.cmd('/multiline ; /mqtarget clear ; /hidec all')
        if state.canStartBusyState(state.STATES.dragging) then
            state.setRunState(state.STATES.dragging,
                {
                    phase = 'init',
                    mode = mode,
                    corpseID = corpseId,
                    deadline = mq.gettime() + 2000,
                    priority = bothooks.getPriority(
                        'doMiscTimer')
                })
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function botmove.FollowCall()
    if MasterPause then return false end
    local rc = state.getRunconfig()
    if not rc.stucktimer then rc.stucktimer = 0 end
    if rc.stucktimer <= mq.gettime() then botmove.UnStuck() end
    refreshFollowId()
    if not rc.followid or rc.followid == 0 then return end
    if mq.TLO.Me.Sitting() then mq.cmd('/stand') end
    doFollowNav()
end

function botmove.UnStuck()
    local rc = state.getRunconfig()
    local followid = rc.followid
    if not followid or followid == 0 then return false end
    local stuckdistance = mq.TLO.Spawn(followid).Distance3D() or 100
    local acleash = myconfig.settings.acleash
    if stuckdistance < acleash then return false end

    if state.getRunState() == state.STATES.unstuck then
        local p = state.getRunStatePayload()
        if tickUnstuckPhase(p, followid, stuckdistance) then return false end
    end

    if tryPathExistsUnstuck(followid) then return false end

    mq.cmd('/echo I appear to be stuck, attempting to get unstuck')
    if tryAutoSizeUnstuck(followid, stuckdistance) then return false end

    doWiggleUnstuck(followid, stuckdistance)
    return false
end

function botmove.StartReturnToFollowAfterEngage()
    local rc = state.getRunconfig()
    if not rc.followid or rc.followid == 0 then return end
    local followid = mq.TLO.Spawn(rc.followid).ID() or 0
    local followtype = mq.TLO.Spawn(rc.followid).Type() or "none"
    local followdistance = mq.TLO.Spawn(rc.followid).Distance() or 0
    if followdistance < myconfig.settings.followdistance or not followid or followtype == 'CORPSE' then return end
    mq.cmd('/multiline ; /stick off ; /squelch /attack off ; /mqtarget self')
    botmove.FollowCall()
    if state.canStartBusyState(state.STATES.engage_return_follow) then
        state.setRunState(state.STATES.engage_return_follow,
            { phase = 'delay_400', deadline = mq.gettime() + 400, priority = bothooks.getPriority('doMiscTimer') })
    end
end

function botmove.TickReturnToFollowAfterEngage()
    if state.getRunState() ~= state.STATES.engage_return_follow then return end
    local p = state.getRunStatePayload()
    if not p then
        state.clearRunState()
        return
    end
    if p.phase == 'delay_400' then
        tickEngageReturnDelay400(p)
        return
    end
    if p.phase == 'nav_wait' then
        tickEngageReturnNavWait(p)
    end
end

-- Follow nav + stuck detection and unstuck state machine. Called from doMovementCheck (runWhenBusy).
function botmove.FollowAndStuckCheck()
    botmove.TickReturnToFollowAfterEngage()
    local rc = state.getRunconfig()
    if (rc.followid and rc.followid > 0) or (rc.followname and rc.followname ~= '') then
        refreshFollowId()
    end
    if not (rc.followid and rc.followid > 0) then return end
    local followid = mq.TLO.Spawn(rc.followid).ID() or 0
    if followid > 0 and followid ~= rc.followid then
        rc.followid = followid
    end
    if shouldCallFollow(rc) then
        botmove.FollowCall()
    end
    updateStuckTimerWithinLeash(rc)
end

-- Camp return and leash. Called from doMovementCheck (runWhenBusy).
function botmove.MakeCampLeashCheck()
    if not state.getRunconfig().campstatus then return end
    if state.getRunconfig().engageTargetId then return end
    if isCampDragWorkflowActive() then return end
    if mq.TLO.Me.Class.ShortName() ~= 'BRD' and mq.TLO.Me.Casting.ID() then return end
    if state.getRunState() == state.STATES.pulling then return end
    local rc = state.getRunconfig()
    if not rc.makecamp or not rc.makecamp.x or not rc.makecamp.y or not rc.makecamp.z then return end
    if campDistanceOk(rc) and campLOSOk(rc) then return end
    print("\ar Exceeded ACLeash\ax, resetting combat") -- not debug, real status message
    doLeashResetCombat()
    botmove.MakeCamp('return')
end

function botmove.NavToCamp(opts)
    doNavToCamp(opts)
end

--- Returns true when the current position is at camp (within camp-close distance and LOS).
function botmove.AtCamp()
    local rc = state.getRunconfig()
    if not rc.makecamp.x or not rc.makecamp.y or not rc.makecamp.z then return false end
    return campDistanceOk(rc) and campLOSOk(rc)
end

function botmove.SetCampHere()
    setCampHere()
end

--- Set or clear camp. mode: 'on' | 'off' | 'return' or nil (toggle).
function botmove.MakeCamp(...)
    local args = { ... }
    local mode = args[1]
    if not mode then
        mode = state.getRunconfig().campstatus and 'off' or 'on'
    end
    if mode == 'on' then
        return makeCampOn()
    elseif mode == 'off' then
        makeCampOff()
    elseif mode == 'return' then
        print('return called') -- not debug, but needs reformatting / context to be meaningful
        makeCampReturn()
    end
end

function botmove.DragCheck()
    local just_did_sumcorpse = tickSumcorpsePending()
    local rc = state.getRunconfig()
    local mode = hasCampSet(rc) and 'camp_fetch' or 'carry'

    if state.getRunState() == state.STATES.dragging then
        local payload = state.getRunStatePayload()
        if tickDragging(payload) then return end
    end

    if mode == 'carry' and carryCorpseID then
        if mq.TLO.Spawn(carryCorpseID).ID() then return false end
        carryCorpseID = nil
    end

    CorpseID = nil
    local searchDist = (mode == 'carry') and (myconfig.settings.acleash or 75) or DragDist
    local candidates = findCorpseCandidates(searchDist, mode)
    if #candidates == 0 then return false end
    for _, corpse in ipairs(candidates) do
        if startDrag(corpse.id, just_did_sumcorpse, mode) then
            CorpseID = corpse.id
            return true
        end
    end
    return false
end

return botmove
