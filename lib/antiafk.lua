-- Anti-AFK: random sit/stand or micro-nudge after 60–90s of continuous true idle.
-- Runs every main-loop tick (including when MasterPause); activity pushes the idle deadline forward.
local mq = require('mq')
local state = require('lib.state')
local spellutils = require('lib.spellutils')
local log = require('lib.log')

local M = {}

local POSITION_EPS = 0.5
local IDLE_MIN_MS = 60000
local IDLE_MAX_MS = 90000
local NUDGE_HOLD_MS = 25

-- Brief out-and-back pairs using strafe keys (not turn).
local NUDGE_PAIRS = {
    { 'forward', 'back' },
    { 'back', 'forward' },
    { 'strafe_left', 'strafe_right' },
    { 'strafe_right', 'strafe_left' },
}

local _idleUntil = 0
local _prev = {
    x = nil,
    y = nil,
    z = nil,
    runState = nil,
    curSpellKey = nil,
    sitting = nil,
    mobCount = nil,
}

local function randomIdleMs()
    return math.random(IDLE_MIN_MS, IDLE_MAX_MS)
end

local function posDelta(x1, y1, z1, x2, y2, z2)
    if x1 == nil or x2 == nil then return 0 end
    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function curSpellKey(rc)
    local cs = rc.CurSpell
    if not cs then return nil end
    return string.format('%s/%s/%s', tostring(cs.sub), tostring(cs.phase), tostring(cs.spell))
end

local function takeSnapshot()
    local rc = state.getRunconfig()
    local me = mq.TLO.Me
    return {
        x = me.X() or 0,
        y = me.Y() or 0,
        z = me.Z() or 0,
        runState = state.getRunState(),
        curSpellKey = curSpellKey(rc),
        sitting = me.Sitting() == true,
        mobCount = state.getMobCount(rc),
    }
end

local function isActive(snap)
    local rc = state.getRunconfig()
    if state.isAntiAfkBlocked(rc) then return true end
    if spellutils.IsMemorizing() then return true end
    if mq.TLO.Me.AutoFire() then return true end

    if _prev.x ~= nil then
        if posDelta(_prev.x, _prev.y, _prev.z, snap.x, snap.y, snap.z) > POSITION_EPS then return true end
        if snap.runState ~= _prev.runState then return true end
        if snap.curSpellKey ~= _prev.curSpellKey then return true end
        if snap.sitting ~= _prev.sitting then return true end
        if snap.mobCount ~= _prev.mobCount then return true end
    end

    return false
end

local function updatePrev(snap)
    _prev.x = snap.x
    _prev.y = snap.y
    _prev.z = snap.z
    _prev.runState = snap.runState
    _prev.curSpellKey = snap.curSpellKey
    _prev.sitting = snap.sitting
    _prev.mobCount = snap.mobCount
end

local function runNudgeSequence(outDir, returnDir)
    mq.cmdf('/squelch /keypress %s hold', outDir)
    log.say('anti-AFK: nudge out hold %s (return %s)', outDir, returnDir)

    mq.delay(NUDGE_HOLD_MS)
    mq.cmdf('/squelch /keypress %s', outDir)
    mq.cmdf('/squelch /keypress %s hold', returnDir)
    log.say('anti-AFK: nudge return hold %s', returnDir)

    mq.delay(NUDGE_HOLD_MS)
    mq.cmdf('/squelch /keypress %s', returnDir)
    log.say('anti-AFK: nudge complete (%s then %s)', outDir, returnDir)
end

local function startNudge()
    local pair = NUDGE_PAIRS[math.random(1, #NUDGE_PAIRS)]
    local outDir, returnDir = pair[1], pair[2]
    if mq.TLO.Navigation.Active() then mq.cmd('/squelch /nav stop log=off') end
    if mq.TLO.Me.Sitting() then mq.cmd('/stand') end
    runNudgeSequence(outDir, returnDir)
end

local function fireAction()
    if state.isAntiAfkBlocked() then
        log.say('anti-AFK: skipped (combat/busy)')
        return false
    end
    if mq.TLO.Me.Sitting() then
        mq.cmd('/stand')
        log.say('anti-AFK: stand')
        return true
    end
    if math.random(1, 2) == 1 then
        mq.cmd('/squelch /sit on')
        log.say('anti-AFK: sit')
    else
        startNudge()
    end
    return true
end

function M.tick()
    local now = mq.gettime()

    local snap = takeSnapshot()
    local active = isActive(snap)
    updatePrev(snap)

    if active then
        _idleUntil = now + randomIdleMs()
        return
    end

    if _idleUntil == 0 then
        _idleUntil = now + randomIdleMs()
        return
    end

    if now >= _idleUntil then
        fireAction()
        _idleUntil = now + randomIdleMs()
    end
end

return M
