local mq = require('mq')
local botconfig = require('lib.config')
local botgui = require('botgui')
local commands = require('lib.commands')
local mobfilter = require('lib.mobfilter')
local state = require('lib.state')
local botmove = require('botmove')
local hookregistry = require('lib.hookregistry')
local spellutils = require('lib.spellutils')
local bardtwist = require('lib.bardtwist')
local botevents = require('botevents')
local utils = require('lib.utils')

local bothooks = require('lib.bothooks')
local botlogic = {}
local myconfig = botconfig.config

-- TODO: CharState is a large per-tick handler; consider breaking into smaller functions (e.g. sit, mount, dead/hover, pet, etc.).
local function CharState(...)
    local args = { ... }
    local tarname = mq.TLO.Target.Name()
    if args[1] == 'startup' then
        if mq.TLO.Me.Hovering() then
            printf('\ayCZBot:\axCan\'t start CZBot cause I\'m hovering over my corpse!')
            state.getRunconfig().terminate = true
            return
        end
        if (mq.TLO.Me.Moving()) then
            mq.cmd('/multiline ; /nav stop log=off; /stick off)')
        end
        if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
    end
    if mq.TLO.Window('LootWnd').Open() then
        mq.cmd('/clean')
    end
    if mq.TLO.Me.Ducking() then
        mq.cmd('/keypress duck')
    end
    if state.getRunState() == 'camp_return' then
        if not mq.TLO.Me.Moving() or (state.getRunStatePayload() and state.getRunStatePayload().deadline and mq.gettime() >= state.getRunStatePayload().deadline) then
            state.clearRunState()
        end
    elseif state.getRunconfig().campstatus and state.getRunconfig().makecamp.x and state.getRunconfig().makecamp.y then
        local campSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), state.getRunconfig().makecamp.x, state.getRunconfig().makecamp.y)
        if campSq and botconfig.config.settings.acleashSq and campSq > botconfig.config.settings.acleashSq then botmove.MakeCamp('return') end
    end
    -- Stand when follow is on and target is beyond follow distance (so follow logic can run)
    do
        local rc = state.getRunconfig()
        if rc.followid and rc.followid > 0 and mq.TLO.Me.Sitting() then
            local followSpawn = mq.TLO.Spawn(rc.followid)
            local dSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), followSpawn.X(), followSpawn.Y())
            if dSq and botconfig.config.settings.followdistanceSq and dSq >= botconfig.config.settings.followdistanceSq then mq.cmd('/stand') end
        end
    end
    if botconfig.config.settings.dosit and state.getRunState() ~= 'casting' and not mq.TLO.Me.Sitting() and not mq.TLO.Me.Moving() and mq.TLO.Me.CastTimeLeft() == 0 and not mq.TLO.Me.Combat() and not mq.TLO.Me.AutoFire() then
        local rc = state.getRunconfig()
        local skipSitForFollow = false
        if rc.followid and rc.followid > 0 then
            local followSpawn = mq.TLO.Spawn(rc.followid)
            local dSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), followSpawn.X(), followSpawn.Y())
            if dSq and botconfig.config.settings.followdistanceSq and dSq >= botconfig.config.settings.followdistanceSq then skipSitForFollow = true end
        end
        if not skipSitForFollow then
            local sitcheck = true
            if (tonumber(botconfig.config.settings.sitmana) >= mq.TLO.Me.PctMana() and mq.TLO.Me.MaxMana() > 0) or tonumber(botconfig.config.settings.sitendur) >= mq.TLO.Me.PctEndurance() then
                if mq.TLO.Me.PctHPs() < 40 and state.getRunconfig().MobCount > 0 then sitcheck = false end
                if sitcheck then mq.cmd('/squelch /sit on') end
            end
        end
    end
    do
        local rc = state.getRunconfig()
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
    end
    if botconfig.config.settings.domount and botconfig.config.settings.mountcast then spellutils.MountCheck() end
    if mq.TLO.Me.State() == 'DEAD' or (mq.TLO.Me.State() == 'HOVER' and mq.TLO.Me.Hovering()) then
        state.setRunState('dead', nil)
        if not state.getRunconfig().HoverEchoTimer or state.getRunconfig().HoverEchoTimer == 0 then
            state.getRunconfig().HoverEchoTimer =
                mq.gettime() + 300000
        end
        if state.getRunconfig().HoverTimer < mq.gettime() then
            botevents.Event_Slain()
        end
        return
    end
    if state.getRunState() == 'dead' then
        state.clearRunState()
    end
    if tarname and string.find(tarname, 'corpse') then
        mq.cmd('/squelch /multiline ; /attack off ; /target clear ; /stick off')
    end
    if mq.TLO.Me.State() == 'FEIGN' then
        mq.cmd('/stand')
    end
    if not state.getRunconfig().engageTargetId or mq.TLO.Target.ID() ~= state.getRunconfig().engageTargetId then
        if mq.TLO.Me.Combat() then
            mq.cmd('/attack off')
        end
        if ((not state.getRunconfig().engageTargetId or (state.getRunconfig().engageTargetId and mq.TLO.Me.Pet.Target.ID() ~= state.getRunconfig().engageTargetId)) and mq.TLO.Me.Pet.Aggressive()) then
            mq.cmd('/squelch /pet back off')
            mq.cmd('/squelch /pet follow')
        end
    end
    if not (state.getRunconfig().MobList[1] and state.getRunconfig().engageTargetId) then
        state.getRunconfig().engageTargetId = nil
    end
    if mq.TLO.Plugin('MQ2GMCheck').IsLoaded() then
        if mq.TLO.GMCheck() == 'TRUE' then
            botevents.Event_GMDetected()
        end
    end
    if mq.TLO.Me.Pet.ID() and not state.getRunconfig().MyPetID then
        state.getRunconfig().MyPetID = mq.TLO.Me.Pet.ID()
        mq.cmd('/pet leader')
    elseif mq.TLO.Me.Pet.ID() and state.getRunconfig().MyPetID ~= mq.TLO.Me.Pet.ID() then
        state.getRunconfig().MyPetID = mq.TLO.Me.Pet.ID()
        mq.cmd('/pet leader')
    end
end

-- State for doMiscTimer (runs every 1s): throttle and inactive-click timer.
local _miscLastRun = 0
local _miscInactivetimer = 0

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

local function _runDoMiscTimer()
    if _miscLastRun > mq.gettime() then return end
    _miscInactiveClick()
    _miscDrag()
    botmove.FollowAndStuckCheck()
    botmove.MakeCampLeashCheck()
    _miscLastRun = mq.gettime() + 1000
end

-- Register built-in hook implementations. registerAllFromConfig() (called from StartUp) wires them from bothooks.
local function _registerBuiltinHooks()
    hookregistry.registerHookFn('zoneCheck', function(hookName)
        if state.getRunconfig().zonename ~= mq.TLO.Zone.ShortName() then
            botevents.OnZoneChange()
        end
    end)

    hookregistry.registerHookFn('doEvents', function(hookName)
        mq.doevents()
    end)

    hookregistry.registerHookFn('charState', function(hookName)
        CharState()
    end)

    hookregistry.registerHookFn('doMiscTimer', function(hookName)
        _runDoMiscTimer()
    end)
end

function botlogic.StartUp(...)
    print('CZBot is starting! (v1.00)') -- not debug, keep but change version to pull from a variable
    math.randomseed(os.time() * 1000 + os.clock() * 1000)
    if mq.TLO.Me.Hovering() or string.find(mq.TLO.Me.Name(), 'corpse') then
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
    runconfig.zonename = mq.TLO.Zone.ShortName()
    if args[1] then
        runconfig.TankName = (args[1] == 'automatic') and 'automatic' or (args[1]:sub(1, 1):upper() .. args[1]:sub(2))
    else
        runconfig.TankName = botconfig.config.settings.TankName
    end
    runconfig.AssistName = botconfig.config.settings.AssistName or runconfig.TankName
    if args[2] == 'makecamp' then commands.MakeCamp('on') end
    if args[2] == 'follow' and args[1] then commands.Follow(args[1]) end
    mobfilter.process('exclude', 'zone')
    mobfilter.process('priority', 'zone')
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
