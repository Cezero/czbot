---@class RunConfig
---@field ScriptList table
---@field SubOrder table
---@field zonename string
---@field engageTargetId number|nil
---@field AlertList number
---@field followid number
---@field followname string
---@field TankName string
---@field AssistName string
---@field ExcludeList string
---@field PriorityList string
---@field MobList table
---@field MobCount number
---@field engagetracker table
---@field campstatus boolean
---@field makecamp {x:number|nil, y:number|nil, z:number|nil}
---@field charmid number|nil
---@field domelee boolean|nil
---@field pulledmob number|nil
---@field pullreturntimer number|nil
---@field pullarc number|nil
---@field FTEList table
---@field FTECount number
---@field CurSpell table
---@field gemInUse table
---@field HoverTimer number
---@field DragHack boolean
---@field HoverEchoTimer number
---@field SpellTimer number
---@field interruptCounter table
---@field PreCH table
---@field gmtimer number
---@field MyPetID number|nil
---@field IgnoreMobBuff boolean
---@field YellTimer number
---@field MissedNote boolean
---@field terminate boolean
---@field runState string
---@field runStateDeadline number|nil
---@field runStatePhase string|nil
---@field runStatePayload table|nil
---@field pullState string|nil
---@field pullAPTargetID number|nil
---@field pullTagTimer number|nil
---@field pullReturnTimer number|nil
---@field pullPhase string|nil
---@field pullDeadline number|nil
---@field stucktimer number|nil
---@field mobprobtimer number
---@field spellNotInBook table|nil
---@field statusMessage string User-facing activity line for GUI

local M = {}

-- Run states that mean "busy". When busy, the main loop runs only hooks with
-- hook.priority <= payload.priority (see hookregistry.runNormalHooks).
-- Payload should include priority = mainloop hook priority of the "owner" of this activity.
local BUSY_STATES = {
    pulling = true,
    raid_mechanic = true,
    casting = true,
    dragging = true,
    camp_return = true,
    engage_return_follow = true,
    unstuck = true,
    chchain = true,
}
M._runconfig = nil

---Create or reset the runconfig table to default values.
function M.resetRunconfig()
    M._runconfig = {
        ScriptList = {},
        SubOrder = {},
        zonename = '',
        engageTargetId = nil,
        AlertList = 20,
        followid = 0,
        followname = '',
        TankName = '',
        AssistName = '',
        ExcludeList = '',
        PriorityList = '',
        MobList = {},
        MobCount = 0,
        engagetracker = {},
        campstatus = false,
        makecamp = { x = nil, y = nil, z = nil },
        charmid = nil,
        domelee = nil,
        pulledmob = nil,
        pullreturntimer = nil,
        pullarc = nil,
        FTEList = {},
        FTECount = 0,
        CurSpell = {},
        gemInUse = {},
        HoverTimer = 0,
        DragHack = false,
        HoverEchoTimer = 0,
        SpellTimer = 0,
        interruptCounter = {},
        PreCH = {},
        gmtimer = 0,
        MyPetID = nil,
        IgnoreMobBuff = false,
        YellTimer = 0,
        MissedNote = false,
        terminate = false,
        runState = 'idle',
        runStateDeadline = nil,
        runStatePhase = nil,
        runStatePayload = nil,
        pullState = nil,
        pullAPTargetID = nil,
        pullTagTimer = nil,
        pullReturnTimer = nil,
        pullPhase = nil,
        pullDeadline = nil,
        stucktimer = 0,
        mobprobtimer = 0,
        spellNotInBook = {},
        statusMessage = '',
    }
    return M._runconfig
end

---Set current run state and optional payload (deadline, phase, priority, or custom table).
---When setting a busy state (any in BUSY_STATES), payload should include priority (number) =
---mainloop hook priority of the owner so the main loop can filter which hooks run.
---@param name string One of: idle, pulling, raid_mechanic, casting, dragging, camp_return, engage_return_follow, melee, unstuck, chchain
---@param payload table|nil Optional: { deadline = number?, phase = string?, priority = number?, ... }
function M.setRunState(name, payload)
    local rc = M.getRunconfig()
    rc.runState = name or 'idle'
    rc.runStatePayload = payload
    if payload then
        rc.runStateDeadline = payload.deadline
        rc.runStatePhase = payload.phase
    else
        rc.runStateDeadline = nil
        rc.runStatePhase = nil
    end
end

---Clear run state back to idle.
function M.clearRunState()
    M.setRunState('idle', nil)
end

---@return string Current runState (e.g. 'idle', 'pulling').
function M.getRunState()
    return M.getRunconfig().runState or 'idle'
end

---True when runState is a "busy" state. Main loop uses isBusy() and payload.priority to run only hooks with hook.priority <= payload.priority.
---@return boolean
function M.isBusy()
    local s = M.getRunState()
    return s ~= 'idle' and BUSY_STATES[s] == true
end

---Get optional payload for current state (deadline, phase, or custom fields).
---@return table|nil
function M.getRunStatePayload()
    return M.getRunconfig().runStatePayload
end

---Check if runState has a deadline and it has passed.
---@return boolean
function M.runStateDeadlinePassed()
    local rc = M.getRunconfig()
    if not rc.runStateDeadline then return true end
    local mq = require('mq')
    return mq.gettime() >= rc.runStateDeadline
end

---@return RunConfig
function M.getRunconfig()
    if M._runconfig == nil then
        M.resetRunconfig()
    end
    return M._runconfig
end

return M
