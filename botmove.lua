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

-- ---------------------------------------------------------------------------
-- Follow / stuck helpers
-- ---------------------------------------------------------------------------

local function refreshFollowId()
    local rc = state.getRunconfig()
    if not mq.TLO.Spawn('id ' .. rc.followid).ID() or mq.TLO.Spawn('id ' .. rc.followid).Type() == 'Corpse' then
        local id = mq.TLO.Spawn('=' .. rc.followname).ID()
        if id then rc.followid = id end
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
    return followid > 0 and followdistance > 0 and engageId == 0 and followtype ~= 'CORPSE' and followdistance >= myconfig.settings.followdistance
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
            state.setRunState(state.STATES.unstuck, { phase = 'back_wait', deadline = mq.gettime() + 2000, followid = followid, stuckdistance = stuckdistance, priority = bothooks.getPriority('doMiscTimer') })
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
    if not mq.TLO.Navigation.PathExists('id ' .. followid)() then return false end
    mq.cmdf('/nav id %s los=on dist=15 log=off', followid)
    if state.canStartBusyState(state.STATES.unstuck) then
        state.setRunState(state.STATES.unstuck, { phase = 'nav_wait5', deadline = mq.gettime() + 5000, followid = followid, priority = bothooks.getPriority('doMiscTimer') })
    end
    return true
end

local function tryAutoSizeUnstuck(followid, stuckdistance)
    if not mq.TLO.Navigation.Active() then return false end
    if mq.TLO.Plugin("MQ2AutoSize").IsLoaded() then mq.cmd('/autosize sizeself 1') end
    local d = mq.TLO.Spawn(followid).Distance3D()
    local rc = state.getRunconfig()
    if d and stuckdistance >= d + 10 then rc.stucktimer = mq.gettime() + 60000 return true end
    if mq.TLO.Plugin("MQ2AutoSize").IsLoaded() then mq.cmd('/autosize sizeself 12') end
    d = mq.TLO.Spawn(followid).Distance3D()
    if d and stuckdistance >= d + 10 then rc.stucktimer = mq.gettime() + 60000 return true end
    if mq.TLO.Plugin("MQ2AutoSize").IsLoaded() then mq.cmd('/autosize sizeself 8') end
    d = mq.TLO.Spawn(followid).Distance3D()
    if d and stuckdistance >= d + 10 then rc.stucktimer = mq.gettime() + 60000 return true end
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
        mq.cmdf('/squelch /multiline ; /face fast heading %s ; /stand ; /autosize sizeself %s ; /keypress forward hold', heading, size)
    end
    if state.canStartBusyState(state.STATES.unstuck) then
        state.setRunState(state.STATES.unstuck, { phase = 'wiggle_wait', deadline = mq.gettime() + 2000, followid = followid, stuckdistance = stuckdistance, priority = bothooks.getPriority('doMiscTimer') })
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
        state.setRunState(state.STATES.engage_return_follow, { phase = 'nav_wait', deadline = now + 10000, priority = bothooks.getPriority('doMiscTimer') })
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
    return mq.TLO.LineOfSight(mq.TLO.Me.X() .. ',' .. mq.TLO.Me.Y() .. ',' .. mq.TLO.Me.Z() .. ':' .. rc.makecamp.x .. ',' .. rc.makecamp.y .. ',' .. rc.makecamp.z)()
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
        state.setRunState(state.STATES.camp_return, { deadline = mq.gettime() + 5000, priority = bothooks.getPriority('doMiscTimer') })
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
    if not payload or not payload.corpseID then state.clearRunState() return true end
    local cid = payload.corpseID
    if payload.phase == 'init' then
        if mq.gettime() < (payload.deadline or 0) then return true end
        mq.cmd('/hidec none')
        mq.cmd('/hidec alwaysnpc')
        mq.cmd('/multiline ; /attack off ; /stick off')
        targeting.TargetAndWait(cid, 500)
        if state.canStartBusyState(state.STATES.dragging) then
            state.setRunState(state.STATES.dragging, { phase = 'sneak', corpseID = cid, priority = bothooks.getPriority('doMiscTimer') })
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
            state.setRunState(state.STATES.dragging, { phase = 'navigating', corpseID = cid, priority = bothooks.getPriority('doMiscTimer') })
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
            mq.cmd('/multiline ; /corpsedrag ; /nav stop')
            state.clearRunState()
            CorpseID = nil
        end
    end
    return true
end

local function findCorpseToDrag()
    local bots = charinfo.GetPeers()
    for cor = 1, charinfo.GetPeerCnt() do
        local bot = bots[cor]
        local corpse = nil
        local corpsedist = nil
        if bot then
            corpse = mq.TLO.Spawn(bot .. "'s corpse").Type()
            corpsedist = mq.TLO.Spawn(bot .. "'s corpse").Distance()
        end
        if corpse == 'Corpse' and corpsedist and corpsedist > 10 and corpsedist < DragDist then
            return mq.TLO.Spawn(bot .. "'s corpse").ID()
        end
    end
    return nil
end

local function startDrag(corpseId, justDidSumcorpse)
    local rc = state.getRunconfig()
    if rc.DragHack and corpseId and not justDidSumcorpse then
        targeting.TargetAndWait(corpseId, 500)
        mq.cmd('/sumcorpse')
        return
    end
    if corpseId and mq.TLO.Navigation.PathExists('id ' .. corpseId)() then
        mq.cmd('/multiline ; /target clear ; /hidec all')
        if state.canStartBusyState(state.STATES.dragging) then
            state.setRunState(state.STATES.dragging, { phase = 'init', corpseID = corpseId, deadline = mq.gettime() + 2000, priority = bothooks.getPriority('doMiscTimer') })
        end
    end
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
    local followid = mq.TLO.Spawn(rc.followid).ID() or 0
    local followtype = mq.TLO.Spawn(rc.followid).Type() or "none"
    local followdistance = mq.TLO.Spawn(rc.followid).Distance() or 0
    if followdistance < myconfig.settings.followdistance or not followid or followtype == 'CORPSE' then return end
    mq.cmd('/multiline ; /stick off ; /squelch /attack off ; /target self')
    botmove.FollowCall()
    if state.canStartBusyState(state.STATES.engage_return_follow) then
        state.setRunState(state.STATES.engage_return_follow, { phase = 'delay_400', deadline = mq.gettime() + 400, priority = bothooks.getPriority('doMiscTimer') })
    end
end

function botmove.TickReturnToFollowAfterEngage()
    if state.getRunState() ~= state.STATES.engage_return_follow then return end
    local p = state.getRunStatePayload()
    if not p then state.clearRunState() return end
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
    if not (state.getRunconfig().followid and state.getRunconfig().followid > 0) then return end
    local rc = state.getRunconfig()
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
    if mq.TLO.Me.Class.ShortName() ~= 'BRD' and mq.TLO.Me.Casting.ID() then return end
    if state.getRunState() == state.STATES.pulling then return end
    local rc = state.getRunconfig()
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

    if state.getRunState() == state.STATES.dragging then
        local payload = state.getRunStatePayload()
        if tickDragging(payload) then return end
    end

    CorpseID = nil
    CorpseID = findCorpseToDrag()
    if not CorpseID then return false end
    startDrag(CorpseID, just_did_sumcorpse)
end

return botmove
