-- Anti-AFK: random sit/stand or micro-nudge after 60–90s of continuous true idle.
-- Runs every main-loop tick (including when MasterPause); activity pushes the idle deadline forward.
local mq = require('mq')
local state = require('lib.state')
local spellutils = require('lib.spellutils')
local log = require('lib.log')

local M = {}

local DEBUG = false
local POSITION_EPS = 0.5
local IDLE_MIN_MS = 60000
local IDLE_MAX_MS = 90000
local NUDGE_HOLD_MS = 200

local DIRECTIONS = { 'forward', 'back', 'left', 'right' }

local _idleUntil = 0
local _wiggle = nil -- { dir, phase='hold', deadline }
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

local function dbg(fmt, ...)
    if DEBUG then log.say('[antiafk] ' .. fmt, ...) end
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

local function tickWiggle(now)
    if not _wiggle or _wiggle.phase ~= 'hold' then return end
    if now < (_wiggle.deadline or 0) then return end
    mq.cmdf('/squelch /keypress %s', _wiggle.dir)
    dbg('nudge release %s', _wiggle.dir)
    _wiggle = nil
end

local function startNudge()
    local dir = DIRECTIONS[math.random(1, #DIRECTIONS)]
    if mq.TLO.Navigation.Active() then mq.cmd('/squelch /nav stop log=off') end
    if mq.TLO.Me.Sitting() then mq.cmd('/stand') end
    mq.cmdf('/squelch /keypress %s hold', dir)
    _wiggle = { dir = dir, phase = 'hold', deadline = mq.gettime() + NUDGE_HOLD_MS }
    dbg('nudge hold %s', dir)
end

local function sitStandToggle()
    if mq.TLO.Me.Sitting() then
        mq.cmd('/stand')
    else
        mq.cmd('/squelch /sit on')
    end
    dbg('sit/stand toggle')
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

    tickWiggle(now)

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
