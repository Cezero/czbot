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
---@field ExcludeList table
---@field PriorityList table
---@field CharmList table
---@field MobList table
---@field engagetracker table
---@field campstatus boolean
---@field makecamp {x:number|nil, y:number|nil, z:number|nil}
---@field charmid number|nil
---@field domelee boolean|nil
---@field dopull boolean|nil
---@field pulledmob number|nil
---@field pullreturntimer number|nil
---@field pulledmobLastDistSq number|nil cached distance-squared from puller to pulled mob when last saw it closer
---@field pulledmobLastCloserTime number|nil mq.gettime() when we last observed pulled mob get closer (10s timeout)
---@field pullNavStartHP number|nil PctHPs when we started navigating (for add-abort on damage)
---@field pullarc number|nil
---@field FTEList table
---@field FTECount number
---@field CurSpell table When casting: phase (e.g. casting, precast, precast_wait_move), sub, spell (index), target, targethit, spellcheckResume; when via MQ2Cast: viaMQ2Cast, spellid.
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
---@field unstuckWiggleIndex number|nil current step (1–9) in unstuck wiggle sequence; nil when not wiggling or after sequence
---@field mobprobtimer number
---@field sitTimer number|nil mq.gettime() until which we should not auto-sit (set when hit; cleared when expired or no mobs in camp)
---@field spellNotInBook table|nil
---@field statusMessage string User-facing activity line for GUI
---@field pullHealerManaWait { name: string, pct: number }|nil when set, puller is waiting on this healer's mana before next pull; status tab shows it
---@field bardNotanktarWait table|nil BRD notanktar twist-once: { spellIndex, EvalID, entry } while waiting for cast to finish
---@field notanktarDebuffTimers table|nil BRD: spawn ID -> mq.gettime() when to re-apply notanktar debuff (e.g. mez)
---@field OutOfSpace boolean|nil true when inventory was full (cursor item); cleared when space available again
--- CHChain state (set by commands.cmd_chchain / chchainSetupContinuation; read by lib.chchain).
---@field doChchain boolean
---@field chchainCurtank number
---@field chchainPause number
---@field chchainTank string
---@field chchainTanklist table
---@field chnextClr string|boolean|nil
---@field chchainList string|nil
--- Abort flags: true when abort turned off domelee/dodebuff so "abort off" can restore them.
---@field meleeAbort boolean
---@field debuffAbort boolean
--- Nuke rotation and flavor: last cast nuke index; recent resist-disables for global auto-disable; allowed/auto-disabled flavors (loaded from common per zone).
---@field lastNukeIndex number|nil
---@field nukeResistDisabledRecent table|nil last N entries { flavor = string }; used to detect 3-in-a-row same flavor -> global auto-disable
---@field nukeFlavorsAllowed table|nil flavor -> true (allowed); nil = all allowed
---@field nukeFlavorsAutoDisabled table|nil flavor -> true (auto-disabled due to resist streak)

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
        ExcludeList = {},
        PriorityList = {},
        CharmList = {},
        MobList = {},
        engagetracker = {},
        campstatus = false,
        makecamp = { x = nil, y = nil, z = nil },
        charmid = nil,
        domelee = nil,
        dopull = false,
        pulledmob = nil,
        pullreturntimer = nil,
        pulledmobLastDistSq = nil,
        pulledmobLastCloserTime = nil,
        pullNavStartHP = nil,
        pullarc = nil,
        FTEList = {},
        FTECount = 0,
        CurSpell = {},
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
        unstuckWiggleIndex = nil,
        mobprobtimer = 0,
        sitTimer = nil,
        spellNotInBook = {},
        statusMessage = '',
        pullHealerManaWait = nil,
        bardNotanktarWait = nil,
        notanktarDebuffTimers = nil,
        OutOfSpace = false,
        doChchain = false,
        chchainCurtank = 1,
        chchainPause = 0,
        chchainTank = '',
        chchainTanklist = {},
        chnextClr = nil,
        chchainList = nil,
        meleeAbort = false,
        debuffAbort = false,
        lastNukeIndex = nil,
        nukeResistDisabledRecent = nil,
        nukeFlavorsAllowed = nil,
        nukeFlavorsAutoDisabled = nil,
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

---Return number of mobs in camp (length of MobList). Single source of truth; use instead of a separate MobCount.
---@param rc RunConfig|nil Optional; defaults to getRunconfig().
---@return number
function M.getMobCount(rc)
    rc = rc or M.getRunconfig()
    return #(rc.MobList or {})
end

return M
