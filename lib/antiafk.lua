-- Anti-AFK: open then close a random top-level pack (or inventory) after 3–4 min of continuous true idle.
-- Runs every main-loop tick (including when MasterPause); activity pushes the idle deadline forward.
-- Close is scheduled on a future tick (1–5 s) — no mq.delay/pause.
local mq = require('mq')
local state = require('lib.state')
local spellutils = require('lib.spellutils')
local log = require('lib.log')
local botconfig = require('lib.config')

local M = {}

local POSITION_EPS = 0.5
local IDLE_MIN_MS = 180000
local IDLE_MAX_MS = 240000
local CLOSE_MIN_MS = 1000
local CLOSE_MAX_MS = 5000
local NUM_PACKS = 10

local _idleUntil = 0
local _closeUntil = 0
local _closeTarget = nil -- { kind = 'pack', index = N } | { kind = 'inventory' }
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

local function randomCloseMs()
    return math.random(CLOSE_MIN_MS, CLOSE_MAX_MS)
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

local function listTopLevelPacks()
    local packs = {}
    for i = 1, NUM_PACKS do
        local pack = 'pack' .. i
        local container = tonumber(mq.TLO.InvSlot(pack).Item.Container())
        if container and container > 0 then
            packs[#packs + 1] = i
        end
    end
    return packs
end

local function scheduleClose(target)
    _closeTarget = target
    _closeUntil = mq.gettime() + randomCloseMs()
end

local function applyPendingClose(now)
    if not _closeTarget or _closeUntil == 0 then return end
    if now < _closeUntil then return end

    local target = _closeTarget
    _closeTarget = nil
    _closeUntil = 0

    if target.kind == 'pack' then
        local idx = target.index
        if mq.TLO.Window('Pack' .. idx).Open() then
            mq.cmdf('/itemnotify pack%d rightmouseup', idx)
            log.say('anti-AFK: close pack%d', idx)
        end
    elseif target.kind == 'inventory' then
        if mq.TLO.Window('InventoryWindow').Open() then
            mq.cmd('/windowstate InventoryWindow close')
            log.say('anti-AFK: close inventory')
        end
    end
end

local function fireAction()
    if state.isAntiAfkBlocked() then
        log.say('anti-AFK: skipped (combat/busy)')
        return false
    end

    local packs = listTopLevelPacks()
    if #packs > 0 then
        local idx = packs[math.random(1, #packs)]
        if not mq.TLO.Window('Pack' .. idx).Open() then
            mq.cmdf('/itemnotify pack%d rightmouseup', idx)
        end
        log.say('anti-AFK: open pack%d', idx)
        scheduleClose({ kind = 'pack', index = idx })
    else
        if not mq.TLO.Window('InventoryWindow').Open() then
            mq.cmd('/windowstate InventoryWindow open')
        end
        log.say('anti-AFK: open inventory')
        scheduleClose({ kind = 'inventory' })
    end
    return true
end

function M.tick()
    local now = mq.gettime()

    -- Finish a scheduled close even if anti-AFK was toggled off mid-wait.
    applyPendingClose(now)

    if botconfig.config.settings.antiAfk == false then return end

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
