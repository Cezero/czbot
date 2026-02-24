local mq = require('mq')
local botconfig = require('lib.config')
local botgui = require('gui.components.botgui')
local commands = require('lib.commands')
local mobfilter = require('lib.mobfilter')
local state = require('lib.state')
local botmove = require('botmove')
local hookregistry = require('lib.hookregistry')
local spellutils = require('lib.spellutils')
local bardtwist = require('lib.bardtwist')
local botevents = require('botevents')
local utils = require('lib.utils')

local ok, VERSION = pcall(require, 'version')
if not ok then VERSION = "dev" end

local bothooks = require('lib.bothooks')
local botlogic = {}
local myconfig = botconfig.config

local SIT_HYSTERESIS_PCT = 3

-- CharState: per-tick character state. Split into sub-handlers for clarity and testability.

local function charState_StartupIfRequested(args)
    if args[1] ~= 'startup' then return end
    if mq.TLO.Me.Hovering() then
        printf('\ayCZBot:\axCan\'t start CZBot cause I\'m hovering over my corpse!')
        state.getRunconfig().terminate = true
        return
    end
    if mq.TLO.Me.Moving() then
        mq.cmd('/multiline ; /nav stop log=off; /stick off)')
    end
    if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
end

local function charState_Always()
    if mq.TLO.Window('LootWnd').Open() then mq.cmd('/clean') end
    if mq.TLO.Me.Ducking() then mq.cmd('/keypress duck') end
    -- Camp return: clear when not moving or deadline passed
    if state.getRunState() == state.STATES.camp_return then
        local p = state.getRunStatePayload()
        if not mq.TLO.Me.Moving() or (p and p.deadline and mq.gettime() >= p.deadline) then
            state.clearRunState()
        end
    end
    -- Clear stuck casting: effectively idle or deadline passed with no active cast. Do not clear while memorizing.
    -- When viaMQ2Cast and no cast bar yet (castTimeLeft==0), do not clear as effectivelyIdle so MQ2Cast has time to sit/memorize.
    if state.getRunState() == state.STATES.casting then
        if not spellutils.IsMemorizing() then
            local castTimeLeft = mq.TLO.Me.CastTimeLeft() or 0
            local effectivelyIdle = state.getMobCount() == 0 and not mq.TLO.Me.Casting() and castTimeLeft == 0
            local deadlineStuck = state.runStateDeadlinePassed() and castTimeLeft == 0
            local rc = state.getRunconfig()
            if deadlineStuck or (effectivelyIdle and not (rc.CurSpell and rc.CurSpell.viaMQ2Cast and castTimeLeft == 0)) then
                spellutils.clearCastingStateOrResume()
            end
        end
    end

    local rc = state.getRunconfig()
    local mustStand = false
    local wantToSit = false
    -- Stand if follow on and target beyond follow distance
    if rc.followid and rc.followid > 0 then
        local followSpawn = mq.TLO.Spawn(rc.followid)
        local dSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), followSpawn.X(), followSpawn.Y())
        if dSq and botconfig.config.settings.followdistanceSq and dSq >= botconfig.config.settings.followdistanceSq then
            mustStand = true
        end
    end
    -- Stand if < 40% HP and mobs in camp
    if mq.TLO.Me.PctHPs() < 40 and state.getMobCount() > 0 then mustStand = true end
    local aboveSitHysteresis = true -- when dosit off, allow stand
    -- Sit when enabled and not casting, not moving, not combat, and mana/endurance below thresholds (strict <); stand only when above threshold + hysteresis. No sit in travel mode.
    if botconfig.config.settings.dosit and not state.isTravelMode() and state.getRunState() ~= state.STATES.casting and not mq.TLO.Me.Moving() and mq.TLO.Me.CastTimeLeft() == 0 and not mq.TLO.Me.Combat() and not mq.TLO.Me.AutoFire() then
        if state.getMobCount() == 0 then rc.sitTimer = nil end
        local sitBlockedByHit = rc.sitTimer and mq.gettime() < rc.sitTimer and state.getMobCount() > 0
        local sitmana = tonumber(botconfig.config.settings.sitmana)
        local sitendur = tonumber(botconfig.config.settings.sitendur)
        if not mustStand and not sitBlockedByHit then
            if (mq.TLO.Me.PctMana() < sitmana and mq.TLO.Me.MaxMana() > 0) or mq.TLO.Me.PctEndurance() < sitendur then
                wantToSit = true
            end
        end
        aboveSitHysteresis = (mq.TLO.Me.MaxMana() == 0 or mq.TLO.Me.PctMana() > sitmana + SIT_HYSTERESIS_PCT) and (mq.TLO.Me.PctEndurance() > sitendur + SIT_HYSTERESIS_PCT)
    end
    -- if sitting and must stand or (above hysteresis and not casting), stand. Do not stand for mana while casting/memorizing.
    if mq.TLO.Me.Sitting() and (mustStand or (aboveSitHysteresis and state.getRunState() ~= state.STATES.casting)) then
        mq.cmd('/stand')
    end
    -- if not sitting and want to sit, sit
    if not mq.TLO.Me.Sitting() and wantToSit then
        mq.cmd('/squelch /sit on')
    end

    -- Cursor / inventory: auto-inv or set OutOfSpace
    if mq.TLO.Cursor.ID() and not rc.OutOfSpace then
        if mq.TLO.Me.FreeInventory() == 0 then
            printf('\ayCZBot:\axI\'m out of inventory space!')
            rc.OutOfSpace = true
        else
            mq.cmd('/autoinv')
            rc.OutOfSpace = false
        end
    elseif not mq.TLO.Cursor.ID() and mq.TLO.Me.FreeInventory() and mq.TLO.Me.FreeInventory() > 0 then
        rc.OutOfSpace = false
    end
    if botconfig.config.settings.domount and not state.isTravelMode() and botconfig.config.settings.mountcast then spellutils.MountCheck() end
end

--- Returns true if dead/hover; caller should return. Sets dead state and HoverTimer/HoverEchoTimer, may call Event_Slain.
local function charState_DeadOrHover()
    if mq.TLO.Me.State() ~= 'DEAD' and (mq.TLO.Me.State() ~= 'HOVER' or not mq.TLO.Me.Hovering()) then return false end
    state.clearRunState()
    state.getRunconfig().CurSpell = {}
    state.getRunconfig().statusMessage = ''
    state.setRunState(state.STATES.dead, nil)
    if not state.getRunconfig().HoverEchoTimer or state.getRunconfig().HoverEchoTimer == 0 then
        state.getRunconfig().HoverEchoTimer = mq.gettime() + 300000
    end
    if state.getRunconfig().HoverTimer < mq.gettime() then
        botevents.Event_Slain()
    end
    return true
end

local function charState_PostDead()
    if state.getRunState() == state.STATES.dead then
        state.clearRunState()
    end
    local tarname = mq.TLO.Target.Name()
    if tarname and string.find(tarname, 'corpse') then
        mq.cmd('/squelch /multiline ; /attack off ; /target clear ; /stick off')
    end
    if mq.TLO.Me.State() == 'FEIGN' then mq.cmd('/stand') end
    local rc = state.getRunconfig()
    if not rc.engageTargetId or mq.TLO.Target.ID() ~= rc.engageTargetId then
        if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
        if (not rc.engageTargetId or (rc.engageTargetId and mq.TLO.Me.Pet.Target.ID() ~= rc.engageTargetId)) and mq.TLO.Me.Pet.Aggressive() then
            mq.cmd('/squelch /pet back off')
            mq.cmd('/squelch /pet follow')
        end
    end
    if not (rc.MobList and rc.MobList[1] and rc.engageTargetId) then
        rc.engageTargetId = nil
    end
    if mq.TLO.Plugin('MQ2GMCheck').IsLoaded() and mq.TLO.GMCheck() == 'TRUE' then
        botevents.Event_GMDetected()
    end
    if mq.TLO.Me.Pet.ID() then
        if not rc.MyPetID or rc.MyPetID ~= mq.TLO.Me.Pet.ID() then
            rc.MyPetID = mq.TLO.Me.Pet.ID()
            mq.cmd('/pet leader')
        end
    end
end

local function CharState(...)
    local args = { ... }
    charState_StartupIfRequested(args)
    charState_Always()
    if charState_DeadOrHover() then return end
    charState_PostDead()
end

-- State for doMiscTimer (runs every 1s): throttle and inactive-click timer.
local _miscLastRun = 0
local _miscInactivetimer = 0
-- State for doMovementCheck (runs when busy, every 1s): camp return and follow.
local _movementLastRun = 0

-- doMiscTimer sub-routines (run every 1s from _runDoMiscTimer).
local function _miscInactiveClick()
    if state.getRunconfig().engageTargetId then return end
    if _miscInactivetimer >= mq.gettime() then return end
    _miscInactivetimer = mq.gettime() + math.random(60000, 90000)
    mq.cmd('/click right center')
end

local function _miscDrag()
    if not myconfig.settings.dodrag then return end
    botmove.DragCheck()
end

-- Movement only: camp return and follow. Runs in runWhenBusy pass so pure casters get camp/follow even when stuck in casting. Throttled 1s.
local function _runDoMovementCheck()
    if _movementLastRun > mq.gettime() then return end
    botmove.FollowAndStuckCheck()
    botmove.MakeCampLeashCheck()
    _movementLastRun = mq.gettime() + 1000
end

-- Misc only: inactive click (anti-afk, random 60–90s interval) and drag. Runs only when priority allows (not when casting). Throttled 1s.
local function _runDoMiscTimer()
    if _miscLastRun > mq.gettime() then return end
    _miscInactiveClick() -- anti-afk, randomized interval
    _miscDrag()
    _miscLastRun = mq.gettime() + 1000
end

-- Register built-in hook implementations. registerAllFromConfig() (called from StartUp) wires them from bothooks.
local function _registerBuiltinHooks()
    hookregistry.registerHookFn('zoneCheck', function(hookName)
        if state.getRunconfig().zonename ~= mq.TLO.Zone.ShortName() then
            botevents.OnZoneChange()
        end
    end)

    -- Drains MQ event queue so chat/events are processed every tick.
    hookregistry.registerHookFn('doEvents', function(hookName)
        mq.doevents()
    end)

    hookregistry.registerHookFn('charState', function(hookName)
        CharState()
    end)

    hookregistry.registerHookFn('doMovementCheck', function(hookName)
        _runDoMovementCheck()
    end)

    hookregistry.registerHookFn('doMiscTimer', function(hookName)
        _runDoMiscTimer()
    end)
end

function botlogic.StartUp(...)
    print('CZBot is starting! (' .. VERSION .. ')')
    math.randomseed(os.time() * 1000 + os.clock() * 1000)
    if mq.TLO.Me.Hovering() or string.find(mq.TLO.Me.Name() or '', 'corpse') then
        printf('\ayCZBot:\axCan\'t start CZBot cause I\'m hovering over my corpse!')
        state.getRunconfig().terminate = true
        return
    end
    -- Optional plugins (load if not loaded; no terminate)
    if (mq.TLO.Plugin('MQRemote').IsLoaded() == nil) then
        mq.cmd('/squelch /plugin MQRemote load')
    end
    if (mq.TLO.Plugin('MQ2Exchange').IsLoaded() == nil) then
        mq.cmd('/squelch /plugin MQ2Exchange load')
    end
    -- MQ2Cast, MQ2MoveUtils, MQ2Twist, MQCharinfo are required and verified in init.lua before this runs.
    --load config file
    state.resetRunconfig()
    ---@type RunConfig
    local runconfig = state.getRunconfig()
    local args = { ... }
    botconfig.LoadConfig()
    runconfig.zonename = mq.TLO.Zone.ShortName() or ''
    if args[1] then
        runconfig.TankName = (args[1] == 'automatic') and 'automatic' or (args[1]:sub(1, 1):upper() .. args[1]:sub(2))
    else
        runconfig.TankName = botconfig.config.settings.TankName
    end
    runconfig.AssistName = botconfig.config.settings.AssistName or runconfig.TankName
    if args[2] == 'makecamp' then commands.MakeCamp('on') end
    if args[2] == 'follow' and args[1] then commands.Follow(args[1]) end
    if args[2] == 'travel' and args[1] then commands.Travel(args[1]) end
    mobfilter.process('exclude', 'zone')
    mobfilter.process('priority', 'zone')
    mobfilter.process('charm', 'zone')
    local comkeytable = botconfig.getCommon()
    if not comkeytable.raidlist then comkeytable.raidlist = {} end
    --make sure char isnt doing anything already (stop nav, clear cursor, ect)
    CharState('startup')
    mq.imgui.init('debuggui', botgui.getUpdateFn())
    _registerBuiltinHooks()
    hookregistry.registerAllFromConfig()
    --check startup scripts NTA
    --check each section
    --build variables for enabled sections
    --load tbcommon stuff
end

function botlogic.mainloop()
    while not state.getRunconfig().terminate do
        hookregistry.runRunWhenPausedHooks()
        if not MasterPause then
            hookregistry.runNormalHooks()
        end
        mq.delay(100)
    end
end

-- Register all MQ events (zone reset lives in botevents.OnZoneChange).
botevents.BindEvents()

return botlogic
