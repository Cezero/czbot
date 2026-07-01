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

-- Each leg of a nudge lasts one main-loop tick (~100ms): hold out, then hold return.
local NUDGE_PAIRS = {
    { 'forward', 'back' },
    { 'back', 'forward' },
    { 'strafe_left', 'strafe_right' },
    { 'strafe_right', 'strafe_left' },
}

local _idleUntil = 0
local _wiggle = nil -- { outDir, returnDir, step=1|2 }
local _prev = {
    x = nil,
    y = nil,
    z = nil,
    runState = nil,
    curSpellKey = nil,
    sitting = nil,
    combat = nil,
    engageTargetId = nil,
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
        combat = me.Combat() == true,
        engageTargetId = rc.engageTargetId,
    }
end

local function isActive(snap)
    if _wiggle then return true end
    if state.isDeadOrHover() then return true end

    local me = mq.TLO.Me
    if me.Moving() then return true end
    if mq.TLO.Navigation.Active() then return true end
    if mq.TLO.Stick.Active() then return true end
    if me.Casting() then return true end
    if (me.CastTimeLeft() or 0) > 0 then return true end
    if spellutils.IsMemorizing() then return true end
    if me.Combat() then return true end
    if me.AutoFire() then return true end

    local rc = state.getRunconfig()
    if rc.engageTargetId then return true end

    if _prev.x ~= nil then
        if posDelta(_prev.x, _prev.y, _prev.z, snap.x, snap.y, snap.z) > POSITION_EPS then return true end
        if snap.runState ~= _prev.runState then return true end
        if snap.curSpellKey ~= _prev.curSpellKey then return true end
        if snap.sitting ~= _prev.sitting then return true end
        if snap.combat ~= _prev.combat then return true end
        if snap.engageTargetId ~= _prev.engageTargetId then return true end
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
    _prev.combat = snap.combat
    _prev.engageTargetId = snap.engageTargetId
end

local function tickWiggle()
    if not _wiggle then return end

    if _wiggle.step == 1 then
        mq.cmdf('/squelch /keypress %s', _wiggle.outDir)
        mq.cmdf('/squelch /keypress %s hold', _wiggle.returnDir)
        log.say('anti-AFK: nudge return hold %s', _wiggle.returnDir)
        _wiggle.step = 2
        return
    end

    if _wiggle.step == 2 then
        mq.cmdf('/squelch /keypress %s', _wiggle.returnDir)
        log.say('anti-AFK: nudge complete (%s then %s)', _wiggle.outDir, _wiggle.returnDir)
        _wiggle = nil
    end
end

local function startNudge()
    local pair = NUDGE_PAIRS[math.random(1, #NUDGE_PAIRS)]
    local outDir, returnDir = pair[1], pair[2]
    if mq.TLO.Navigation.Active() then mq.cmd('/squelch /nav stop log=off') end
    if mq.TLO.Me.Sitting() then mq.cmd('/stand') end
    mq.cmdf('/squelch /keypress %s hold', outDir)
    _wiggle = { outDir = outDir, returnDir = returnDir, step = 1 }
    log.say('anti-AFK: nudge out hold %s (return %s)', outDir, returnDir)
end

local function sitStandToggle()
    if mq.TLO.Me.Sitting() then
        mq.cmd('/stand')
        log.say('anti-AFK: stand')
    else
        mq.cmd('/squelch /sit on')
        log.say('anti-AFK: sit')
    end
end

local function fireAction()
    if math.random(1, 2) == 1 then
        sitStandToggle()
    else
        startNudge()
    end
end

function M.tick()
    local now = mq.gettime()

    tickWiggle()

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
