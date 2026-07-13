-- Command parser for /cz: dispatches to per-command handlers.
-- Uses globals and modules from the CZBot environment (state.getRunconfig(), botconfig, etc.).

local M = {}

--- Normalize a tank/assist command name argument ('automatic' or capitalized PC name).
function M.normalizeRoleNameArg(raw)
    if raw == 'automatic' then return 'automatic' end
    return raw:sub(1, 1):upper() .. raw:sub(2)
end

local mq = require('mq')
local botconfig = require('lib.config')
local botgui = require('gui.components.botgui')
local spellutils = require('lib.spellutils')
local botmove = require('botmove')
local botpull = require('botpull')
local botbuff = require('botbuff')
local botcure = require('botcure')
local botheal = require('botheal')
local botdebuff = require('botdebuff')
local botraid = require('botraid')
local botevents = require('botevents')
local chchain = require('lib.chchain')
local mobfilter = require('lib.mobfilter')
local state = require('lib.state')
local bothooks = require('lib.bothooks')
local bardtwist = require('lib.bardtwist')
local groupmanager = require('lib.groupmanager')
local charinfo = require("plugin.charinfo")
local utils = require('lib.utils')
local command_dispatcher = require('lib.command_dispatcher')
local follow = require('lib.follow')
local spawnutils = require('lib.spawnutils')
local czactor = require('lib.czactor')
local tankrole = require('lib.tankrole')
local rolelists = require('lib.rolelists')
local common_sync = require('lib.common_sync')
local targeting = require('lib.targeting')
local log = require('lib.log')
local unpack = unpack

local TOGGLELIST = {
    domelee = true,
    dopull = true,
    dodebuff = true,
    dobuff = true,
    doheal = true,
    doraid = true,
    docure = true,
    dosit = true,
    domount = true,
    dodrag = true,
    doforage = true,
}

local function refreshBardTwistMode()
    if bardtwist and bardtwist.EnsureDefaultTwistRunning then
        bardtwist.EnsureDefaultTwistRunning()
    end
end

-- --- Toggle handler (domelee, dopull, etc.) ---
local function cmd_toggle(args)
    local rc = state.getRunconfig()
    local isDopull = (args[1] == 'dopull')
    local function getVal()
        if isDopull then return rc.dopull == true end
        return botconfig.config.settings[args[1]] == true
    end
    local function setVal(v)
        if isDopull then rc.dopull = v else botconfig.config.settings[args[1]] = v end
    end
    if args[2] == 'on' then
        setVal(true)
    elseif args[2] == 'off' then
        if isDopull then
            botpull.DisablePull('command')
        else
            setVal(false)
        end
    else
        if getVal() then
            if isDopull then
                botpull.DisablePull('command')
            else
                setVal(false)
                if args[1] == 'domelee' then
                    if APTarget and APTarget.ID() then APTarget = nil end
                    mq.cmd('/squelch /mqtarget clear ; /nav stop ; /stick off ; /attack off')
                end
            end
        else
            setVal(false)
            setVal(true)
        end
    end
    botconfig.RunConfigLoaders()
    if botconfig.config.settings.doraid then botraid.LoadRaidConfig() end
    if isDopull and rc.dopull == true then
        botpull.syncPullMapFilter(true)
        botpull.ensurePullCampState(rc)
    end
    log.say('Turning %s to %s', args[1],
        isDopull and tostring(rc.dopull) or tostring(botconfig.config.settings[args[1]]))
end

local function cmd_togglesongs(args)
    if not bardtwist.IsBard() then
        log.say('togglesongs is bard-only.')
        return
    end
    local rc = state.getRunconfig()
    local function songsOn()
        return rc.dosongs ~= false
    end
    if args[2] == 'on' then
        rc.dosongs = true
    elseif args[2] == 'off' then
        rc.dosongs = false
    else
        rc.dosongs = not songsOn()
    end
    if rc.dosongs == false then
        bardtwist.StopTwist()
    elseif botconfig.config.settings.dobuff then
        bardtwist.EnsureDefaultTwistRunning()
    end
    log.say('Songs %s', rc.dosongs ~= false and 'on' or 'off')
end

local function cmd_mobprob(args)
    local rc = state.getRunconfig()
    local function mobprobOn() return rc.domobprob == true end
    if args[2] == 'on' then
        rc.domobprob = true
    elseif args[2] == 'off' then
        rc.domobprob = false
    else
        rc.domobprob = not mobprobOn()
    end
    log.say('MobProb %s', rc.domobprob == true and 'on' or 'off')
end

local function cmd_togglecampacleash(args)
    local rc = state.getRunconfig()
    if rc.campstatus ~= true or not rc.makecamp or not rc.makecamp.x or not rc.makecamp.y then
        log.say('togglecampacleash requires makecamp on.')
        return
    end
    local function acleashOn()
        return rc.doCampAcleash ~= false
    end
    if args[2] == 'on' then
        rc.doCampAcleash = true
    elseif args[2] == 'off' then
        rc.doCampAcleash = false
    else
        rc.doCampAcleash = not acleashOn()
    end
    -- Persist so the choice survives reloads (seeded back into rc at startup from settings.campAcleash).
    botconfig.config.settings.campAcleash = rc.doCampAcleash
    botconfig.ApplyAndPersist()
    log.say('Camp acleash %s', rc.doCampAcleash ~= false and 'on' or 'off')
end

local function cmd_addjunk(args, str)
    local zone = mq.TLO.Zone.ShortName()
    if not zone or zone == '' then
        log.say('No zone; cannot add junk.')
        return
    end
    local itemName
    if args[2] then
        itemName = table.concat(args, ' ', 2)
    elseif mq.TLO.Cursor.ID() and mq.TLO.Cursor.Name() then
        itemName = mq.TLO.Cursor.Name()
    end
    if not itemName or itemName == '' then
        log.say('No item name given and nothing on cursor. Use: /cz addjunk <itemname> or put item on cursor.')
        return
    end
    botconfig.addZoneJunk(zone, itemName)
    log.say('Added "%s" to zone %s junk list.', itemName, zone)
end

local function cmd_foragezone(args, str)
    local zone = mq.TLO.Zone.ShortName()
    if not zone or zone == '' then
        log.say('No zone; cannot set foragezone.')
        return
    end
    local sub = args[2] and args[2]:lower()
    if sub == 'on' then
        botconfig.setForageDisabledInZone(zone, false)
        log.say('Auto-forage enabled in this zone.')
    elseif sub == 'off' then
        botconfig.setForageDisabledInZone(zone, true)
        log.say('Auto-forage disabled in this zone.')
    else
        log.say('Usage: /cz foragezone on|off')
    end
end

local function cmd_import(args)
    if args[2] == 'lua' then
        local importpath = mq.configDir .. "\\" .. args[3]
        local configData, err = loadfile(importpath)
        if err then
            printf('failed to import lua file at %s', importpath)
        elseif configData then
            local newconfig = configData()
            if newconfig then
                for k in pairs(botconfig.config) do botconfig.config[k] = nil end
                for k, v in pairs(newconfig) do botconfig.config[k] = v end
            end
            botconfig.RunConfigLoaders()
            log.say('Loaded lua file %s', args[3])
            if args[4] == 'save' then botconfig.Save(botconfig.getPath()) end
        end
    else
        printf('Usage: /cz import lua <filename> [save]')
    end
end

local function cmd_export(args)
    local exportpath = mq.configDir .. "\\" .. args[2]
    botconfig.WriteToFile(botconfig.config, exportpath)
    print("Exporting my config to " .. exportpath)
end

local function cmd_debug(args)
    if args[2] == 'on' then
        print('Enabling debug messages')
        debug = true
    elseif args[2] == 'off' then
        print('Disabling debug messages')
        debug = false
    else
        if debug == true then
            print('Disabling debug messages')
            debug = false
        elseif debug == false then
            print('Enabling debug messages')
            debug = true
        end
    end
end

local function cmd_ui(args)
    botgui.UIEnable()
end

local function cmd_quit(args, str)
    state.getRunconfig().terminate = true
end

local function cmd_makecamp(args, str)
    botmove.MakeCamp(args[2])
    local rc = state.getRunconfig()
    if rc.followid or rc.followname then
        rc.followid = 0
        rc.followname = ''
        rc.travelMode = false
        refreshBardTwistMode()
    end
end

local function autoBroadcastScope()
    return ((mq.TLO.Raid.Members() or 0) > 0) and 'raid' or 'group'
end

---@return string|nil scope 'group'|'raid' for explicit scope; nil when action is off and scope should come from remembered mode
---@return 'on'|'off'|nil action
---@return string|nil err usage message when args are invalid
local function parseLeaderBroadcastArgs(args, startIdx, usage)
    startIdx = startIdx or 2
    local sub = args[startIdx] and string.lower(args[startIdx])
    local third = args[startIdx + 1] and string.lower(args[startIdx + 1])

    if sub == 'off' or sub == 'stop' then
        if third then return nil, nil, usage end
        return nil, 'off', nil
    end

    if sub == 'group' or sub == 'raid' then
        if third == 'stop' or third == 'off' then
            if args[startIdx + 2] then return nil, nil, usage end
            return sub, 'off', nil
        end
        if third then return nil, nil, usage end
        return sub, 'on', nil
    end

    if not sub then
        return autoBroadcastScope(), 'on', nil
    end

    return nil, nil, usage
end

local function isMobilePullMode(rc)
    local pullCfg = botconfig.config.pull
    local pullActive = rc.dopull == true
    local roamOnly = pullCfg and pullCfg.roam == true and pullActive
    local hunterMode = pullCfg and pullCfg.hunter == true and not roamOnly and pullActive
    return roamOnly or hunterMode
end

-- Leader camp broadcast via czbot Actor channel. Mirrors Status-tab group-camp button.
local function cmd_camphere(args)
    local rc = state.getRunconfig()
    local usage = 'Usage: /cz camphere [group|raid|off|stop]'
    local scope, action, err = parseLeaderBroadcastArgs(args, 2, usage)
    if err then
        log.say(err)
        return
    end

    if action == 'off' then
        if not scope then
            scope = rc.camphereMode
            if not scope then
                log.say('Camphere not active')
                return
            end
        end
        czactor.broadcastCampHereOff(scope)
        follow.StopFollow('command')
        if rc.campstatus then botmove.MakeCamp('off') end
        log.say('Camphere OFF (%s)', scope)
        if rc.camphereMode == scope then rc.camphereMode = nil end
        return
    end

    if rc.followmeMode then
        czactor.broadcastFollowMeOff(rc.followmeMode)
        rc.followmeMode = nil
    end

    if rc.camphereMode and rc.camphereMode ~= scope then
        czactor.broadcastCampHereOff(rc.camphereMode)
    end

    follow.StopFollow('command')
    if not isMobilePullMode(rc) then
        botmove.MakeCamp('on')
    end
    local myname = mq.TLO.Me.Name()
    if not myname or myname == '' then return end
    czactor.broadcastCampHere(scope, myname)
    rc.camphereMode = scope
    log.say('Camphere ON (%s)', scope)
end

local function cmd_follow(args, str)
    local rc = state.getRunconfig()
    local targetName
    if args[2] == nil then
        targetName = rc.TankName
    else
        targetName = args[2]
    end
    if targetName then follow.StartFollow(targetName) end
end

local function cmd_stop(args)
    follow.StopFollow('command')
    if state.getRunconfig().campstatus then botmove.MakeCamp('off') end
    log.say('\arDisabling makecamp and follow')
end

local function cmd_travel(args, str)
    local rc = state.getRunconfig()
    local targetName
    if args[2] == nil then
        targetName = rc.TankName
    else
        targetName = args[2]
    end
    if targetName then
        follow.StartFollow(targetName)
        rc.travelMode = true
        log.say('\auTravel mode ON, following %s', targetName)
    end
end

local function cmd_followme(args)
    local rc = state.getRunconfig()
    local usage = 'Usage: /cz followme [group|raid|off|stop]'
    local scope, action, err = parseLeaderBroadcastArgs(args, 2, usage)
    if err then
        log.say(err)
        return
    end

    if action == 'off' then
        if not scope then
            scope = rc.followmeMode
            if not scope then
                log.say('Followme not active')
                return
            end
        end
        czactor.broadcastFollowMeOff(scope)
        log.say('Followme OFF (%s)', scope)
        if rc.followmeMode == scope then rc.followmeMode = nil end
        return
    end

    if rc.camphereMode then
        czactor.broadcastCampHereOff(rc.camphereMode)
        rc.camphereMode = nil
    end

    follow.StopFollow('command')
    local campSet = rc.campstatus or (rc.makecamp and (rc.makecamp.x or rc.makecamp.y or rc.makecamp.z))
    if campSet then botmove.ClearCamp() end

    if rc.followmeMode and rc.followmeMode ~= scope then
        czactor.broadcastFollowMeOff(rc.followmeMode)
    end

    local myname = mq.TLO.Me.Name()
    if not myname or myname == '' then return end

    czactor.broadcastFollowMe(scope, myname)
    rc.followmeMode = scope
    log.say('Followme ON (%s -> %s)', scope, myname)
end

local function tableContains(list, name)
    if type(list) ~= 'table' then return false end
    for _, n in ipairs(list) do
        if n == name then return true end
    end
    return false
end

local function removeFromList(list, name)
    for i = #list, 1, -1 do
        if list[i] == name then
            table.remove(list, i)
            return true
        end
    end
    return false
end

local function cmd_exclude(args)
    local rc = state.getRunconfig()
    if not rc.ExcludeList then rc.ExcludeList = {} end
    if args[2] == 'remove' then
        local name = args[3] or mq.TLO.Target.CleanName()
        if name and removeFromList(rc.ExcludeList, name) then
            log.say('Removed %s from exclude list', name)
            if APTarget and APTarget.ID() then APTarget = nil end
            mq.cmd('/squelch /mqtarget clear ; /nav stop ; /stick off ; /attack off')
            mobfilter.process('exclude', 'save_replace')
        end
        return
    end
    local excludemob = args[2] or mq.TLO.Target.CleanName()
    if excludemob and not tableContains(rc.ExcludeList, excludemob) then
        log.say('Excluding %s from CZBot', excludemob)
        table.insert(rc.ExcludeList, excludemob)
        if APTarget and APTarget.ID() then APTarget = nil end
        mq.cmd('/squelch /mqtarget clear ; /nav stop ; /stick off ; /attack off')
        mobfilter.process('exclude', 'save')
    end
end

local function cmd_fte(args)
    local rc = state.getRunconfig()
    local sub = args[2] and string.lower(args[2]) or ''
    if sub == 'clear' then
        if args[3] and string.lower(args[3]) == 'all' then
            spawnutils.clearFTE(rc, nil)
            log.say('Cleared all FTE entries')
            return
        end
        local tid = mq.TLO.Target.ID()
        if tid and tid > 0 and mq.TLO.Target.Type() == 'NPC' then
            spawnutils.clearFTE(rc, tid)
            log.say('Cleared FTE entry for %s (%s)', mq.TLO.Target.CleanName() or mq.TLO.Target.Name(), tid)
        else
            log.say('Usage: /cz fte clear [all] — or target an NPC')
        end
        return
    end
    log.say('Usage: /cz fte clear [all]')
end

local function cmd_xarc(args)
    botpull.SetPullArc(args[2])
end

local function cmd_priority(args)
    local rc = state.getRunconfig()
    if not rc.PriorityList then rc.PriorityList = {} end
    if args[2] == 'remove' then
        local name = args[3] or mq.TLO.Target.CleanName()
        if name and removeFromList(rc.PriorityList, name) then
            log.say('Removed %s from priority list', name)
            mobfilter.process('priority', 'save_replace')
        end
        return
    end
    local prioritymob = args[2] or mq.TLO.Target.CleanName()
    if prioritymob and not tableContains(rc.PriorityList, prioritymob) then
        log.say('Prioritizing %s in CZBot', prioritymob)
        table.insert(rc.PriorityList, prioritymob)
        mobfilter.process('priority', 'save')
    end
end

local function cmd_charm(args)
    local rc = state.getRunconfig()
    if not rc.CharmList then rc.CharmList = {} end
    if args[2] == 'remove' then
        local name = args[3] or mq.TLO.Target.CleanName()
        if name and removeFromList(rc.CharmList, name) then
            log.say('Removed %s from charm list', name)
            mobfilter.process('charm', 'save_replace')
        end
        return
    end
    local charmmob = args[2] or mq.TLO.Target.CleanName()
    if charmmob and not tableContains(rc.CharmList, charmmob) then
        log.say('Adding %s to charm list', charmmob)
        table.insert(rc.CharmList, charmmob)
        mobfilter.process('charm', 'save')
    end
end

-- Reload shared common config from disk, then refresh current-zone runtime derived lists/state.
-- This is useful when multiple bots share `cz_common.lua` and one bot edits via UI.
local function cmd_reloadcommon(args)
    common_sync.reloadAllFromCommon()
    local zone = mq.TLO.Zone.ShortName()
    zone = zone and zone ~= '' and zone or '<unknown>'
    log.say('Reloaded \agcz_common.lua\ax and refreshed zone state (zone=%s).', zone)
end

local function cmd_abort(args)
    local rc = state.getRunconfig()
    if not args[2] then
        if mq.TLO.Me.CastTimeLeft() > 0 and rc.CurSpell.sub and rc.CurSpell.sub == 'ad' then
            mq.cmd('/stopcast')
        end
        if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
        if mq.TLO.Target.ID() then mq.cmd('/squelch /mqtarget clear') end
        if rc.engageTargetId then rc.engageTargetId = nil end
        rc.attackCommandEngage = nil
        if botconfig.config.settings.domelee then
            botconfig.config.settings.domelee = false
            rc.meleeAbort = true
        end
        if botconfig.config.settings.dodebuff then
            botconfig.config.settings.dodebuff = false
            rc.debuffAbort = true
        end
        log.say('\arAbort+ called!\ax - DoDebuffs & DoMelee FALSE and leashing to camp')
    elseif args[2] == 'off' then
        if not botconfig.config.settings.domelee and rc.meleeAbort then
            botconfig.config.settings.domelee = true
            rc.meleeAbort = false
        end
        if not botconfig.config.settings.dodebuff and rc.debuffAbort then
            botconfig.config.settings.dodebuff = true
            rc.debuffAbort = false
        end
        mq.cmd('\arAbort\ax OFF, enabling dps sections again')
    end
end

local function cmd_leash(args)
    if state.getRunconfig().campstatus then
        log.say('\arLeash\ax called, returning to camp location')
        botmove.MakeCamp('return')
    else
        log.say('No camp set, cannot leash')
    end
end

local function cmd_disengage(args)
    local botmelee = require('botmelee')
    local tankrole = require('lib.tankrole')
    if not state.isMeleeEngaged(state.getRunconfig()) then
        log.say('Not engaged')
        return
    end
    botmelee.disengageCombat('command')
    if tankrole.AmIMainAssist() then
        log.say('\arDisengage\ax: MA released target and broadcast to group')
    else
        log.say('\arDisengage\ax: released current target')
    end
end

-- Engage MA's target, or (if name given) that player's target for this engagement only.
local function cmd_attack(args)
    local assistName
    local overrideName -- used for messages when args[2] was a specific player name
    if args[2] and args[2]:match('%S') then
        local normalized = M.normalizeRoleNameArg(args[2])
        if normalized == 'automatic' then
            assistName = tankrole.GetAssistTargetName()
        else
            assistName = normalized
            overrideName = normalized
        end
    else
        assistName = tankrole.GetAssistTargetName()
    end
    if not assistName then
        log.say('\ar No Main Assist set, cannot engage')
        return
    end
    local _, assistid, KillTarget = spellutils.GetAssistInfo(true)
    if not assistid or assistid == 0 then
        log.say('\ar Could not find %s\ax', assistName)
        return
    end
    if KillTarget == 0 then KillTarget = nil end
    if KillTarget and utils.isProtectedSpawn(mq.TLO.Spawn(KillTarget)) then
        log.say('\ar Cannot engage protected NPC\ax')
        return
    end
    if not KillTarget then
        if overrideName then
            log.say('\ar %s has no target, cannot engage\ax', overrideName)
        else
            log.say('\ar Main Assist has no target, cannot engage')
        end
        return
    end
    local botmelee = require('botmelee')
    local ok, mobName = botmelee.applyAttackCommandEngage(KillTarget)
    if not ok then
        log.say('\ar Cannot engage target\ax')
        return
    end
    czactor.publishAttackEngage(KillTarget, mobName, assistName)
    local msg = log.fmt('\arEngaging\ax \ay%s\ax now', mobName or mq.TLO.Spawn(KillTarget).CleanName())
    if overrideName then
        msg = msg .. string.format(' \at(assist: %s)\ax', overrideName)
    end
    printf('%s', msg)
end

local TANK_USAGE = 'Usage: /cz tank set <name>|automatic|status  (/cz tankrole = status)'

local function setTankName(name)
    if not name or name == '' then
        log.say(TANK_USAGE)
        return
    end
    name = M.normalizeRoleNameArg(name)
    state.getRunconfig().TankName = name
    botconfig.config.settings.TankName = name
    tankrole.invalidateAll()
    botconfig.ApplyAndPersist()
    log.say('Setting tank to %s (saved)', name)
    if name ~= 'automatic' then
        czactor.publishMtUpdate(name, 'manual')
    end
    mq.TLO.Target.TargetOfTarget()
end

local function cmd_tank(args)
    local sub = args[2] and string.lower(args[2])
    if not sub then
        log.say(TANK_USAGE)
        return
    end
    if sub == 'status' then
        tankrole.debugPrint()
        return
    end
    if sub == 'automatic' then
        setTankName('automatic')
        return
    end
    if sub == 'set' then
        setTankName(args[3])
        return
    end
    log.say('Unknown subcommand "%s". %s', tostring(args[2]), TANK_USAGE)
end

local ASSIST_USAGE = 'Usage: /cz assist set <name>|automatic|status'

local function setAssistName(name)
    if not name or name == '' then
        log.say(ASSIST_USAGE)
        return
    end
    name = M.normalizeRoleNameArg(name)
    local rc = state.getRunconfig()
    rc.AssistName = name
    rc.lastAssistTargetId = nil
    botconfig.config.settings.AssistName = name
    tankrole.invalidateAll()
    botconfig.ApplyAndPersist()
    log.say('Setting assist to %s (saved)', name)
    if name ~= 'automatic' then
        czactor.publishMaUpdate(name, 'manual')
    end
end

local function cmd_assist(args)
    local sub = args[2] and string.lower(args[2])
    if not sub then
        log.say(ASSIST_USAGE)
        return
    end
    if sub == 'status' then
        tankrole.debugPrint()
        return
    end
    if sub == 'automatic' then
        setAssistName('automatic')
        return
    end
    if sub == 'set' then
        setAssistName(args[3])
        return
    end
    log.say('Unknown subcommand "%s". %s', tostring(args[2]), ASSIST_USAGE)
end

local function cmd_tankrole(_args)
    tankrole.debugPrint()
end

local function cmd_actor(args)
    local sub = args[2] and string.lower(args[2])
    if sub == 'ping' then
        czactor.sendPing()
        czactor.printPeerStatus()
    elseif sub == 'status' then
        czactor.printStatus()
    else
        log.say('Usage: /cz actor ping|status')
    end
end

local function cmd_stickcmd(args, str)
    botconfig.config.melee.stickcmd = str:match('stickcmd' .. "%s+(.+)")
    log.say('Setting stickcmd to %s', botconfig.config.melee.stickcmd)
end

local function cmd_acleash(args)
    botconfig.config.settings.acleash = tonumber(args[2])
    botconfig.recomputeDerivedSettings()
    log.say('Setting acleash to %s', botconfig.config.settings.acleash)
end

local function cmd_evadepct(args)
    local val = tonumber(args[2])
    if val == nil or val < 0 or val > 100 then
        log.say('Usage: /cz evadepct <0-100>')
        return
    end
    if not botconfig.config.melee then botconfig.config.melee = {} end
    botconfig.config.melee.evadePct = val
    botconfig.ApplyAndPersist()
    log.say('Setting evadePct to %d', val)
end

local function cmd_camprestdistance(args)
    botconfig.config.settings.campRestDistance = tonumber(args[2])
    botconfig.recomputeDerivedSettings()
    log.say('Setting campRestDistance to %s', botconfig.config.settings.campRestDistance)
end

local function cmd_targetfilter(args)
    botconfig.config.settings.TargetFilter = tonumber(args[2])
    log.say('Setting TargetFilter to %d', botconfig.config.settings.TargetFilter)
end

local function cmd_mobfilter(args)
    local spawnutils = require('lib.spawnutils')
    local id = args[2] and tonumber(args[2]) or nil
    spawnutils.explainMobFilter(id)
end

local function cmd_macampanchor(args)
    local mode = args[2] and string.lower(args[2]) or ''
    if mode == 'on' or mode == 'true' or mode == '1' then
        botconfig.config.settings.maCampAnchor = true
    elseif mode == 'off' or mode == 'false' or mode == '0' then
        botconfig.config.settings.maCampAnchor = false
    else
        botconfig.config.settings.maCampAnchor = not (botconfig.config.settings.maCampAnchor ~= false)
    end
    log.say('MA camp anchor %s', botconfig.config.settings.maCampAnchor ~= false and 'on' or 'off')
end

local function cmd_engagextargetonly(args)
    local mode = args[2] and string.lower(args[2]) or ''
    if mode == 'on' or mode == 'true' or mode == '1' then
        botconfig.config.settings.engageXTargetOnly = true
    elseif mode == 'off' or mode == 'false' or mode == '0' then
        botconfig.config.settings.engageXTargetOnly = false
    else
        botconfig.config.settings.engageXTargetOnly = not (botconfig.config.settings.engageXTargetOnly == true)
    end
    botconfig.ApplyAndPersist()
    log.say('Engage XTarget-only %s', botconfig.config.settings.engageXTargetOnly == true and 'on' or 'off')
end

local function cmd_role(args)
    local ok, key, invalidateRoles = botconfig.ApplyRole(args[2])
    if invalidateRoles then
        tankrole.invalidateAll()
    end
    if ok then
        log.say('Applied role preset: \ag%s\ax', key)
    else
        log.say('Unknown role "%s" (use: tank, ma, dps, healer)', tostring(args[2]))
    end
end

local function cmd_mezdebug(args)
    local spellutils = require('lib.spellutils')
    local mode = args[2] and string.lower(args[2]) or ''
    if mode == 'on' or mode == 'true' or mode == '1' then
        spellutils.SetMezDebug(true)
    elseif mode == 'off' or mode == 'false' or mode == '0' then
        spellutils.SetMezDebug(false)
    else
        spellutils.SetMezDebug(not spellutils.IsMezDebug())
    end
    log.say('Mez debug logging %s', spellutils.IsMezDebug() and 'on' or 'off')
end

local function cmd_buffdebug(args)
    local spellutils = require('lib.spellutils')
    local mode = args[2] and string.lower(args[2]) or ''
    if mode == 'on' or mode == 'true' or mode == '1' then
        spellutils.SetBuffDebug(true)
    elseif mode == 'off' or mode == 'false' or mode == '0' then
        spellutils.SetBuffDebug(false)
    else
        spellutils.SetBuffDebug(not spellutils.IsBuffDebug())
    end
    log.say('Buff debug logging %s', spellutils.IsBuffDebug() and 'on' or 'off')
end

local function cmd_barddebug(args)
    local bardtwist = require('lib.bardtwist')
    local mode = args[2] and string.lower(args[2]) or ''
    if mode == 'on' or mode == 'true' or mode == '1' then
        bardtwist.SetBardDebug(true)
    elseif mode == 'off' or mode == 'false' or mode == '0' then
        bardtwist.SetBardDebug(false)
    else
        bardtwist.SetBardDebug(not bardtwist.IsBardDebug())
    end
    log.say('Bard debug logging %s', bardtwist.IsBardDebug() and 'on' or 'off')
end

local function cmd_tickdebug(args)
    local tickprof = require('lib.tickprof')
    local mode = args[2] and string.lower(args[2]) or ''
    if mode == 'on' or mode == 'true' or mode == '1' then
        tickprof.SetDebug(true)
    elseif mode == 'off' or mode == 'false' or mode == '0' then
        tickprof.SetDebug(false)
    else
        tickprof.SetDebug(not tickprof.IsDebug())
    end
    log.say('Tick debug logging %s', tickprof.IsDebug() and 'on' or 'off')
end

local function cmd_actordebug(args)
    local czactor = require('lib.czactor')
    local mode = args[2] and string.lower(args[2]) or ''
    if mode == 'queue' then
        local sub = args[3] and string.lower(args[3]) or ''
        if sub == 'on' or sub == 'true' or sub == '1' then
            czactor.SetQueueDebug(true)
        elseif sub == 'off' or sub == 'false' or sub == '0' then
            czactor.SetQueueDebug(false)
        else
            czactor.SetQueueDebug(not czactor.IsQueueDebug())
        end
        log.say('Actor queue debug logging %s', czactor.IsQueueDebug() and 'on' or 'off')
        return
    end
    if mode == 'on' or mode == 'true' or mode == '1' then
        czactor.SetRoleClaimLogDebug(true)
    elseif mode == 'off' or mode == 'false' or mode == '0' then
        czactor.SetRoleClaimLogDebug(false)
    else
        czactor.SetRoleClaimLogDebug(not czactor.IsRoleClaimLogDebug())
    end
    log.say('Actor role-claim debug logging %s (queue: /cz actordebug queue [on|off])',
        czactor.IsRoleClaimLogDebug() and 'on' or 'off')
end

local function cmd_burn(args)
    local arg = args[2] and string.lower(args[2]) or ''
    if arg == 'off' or arg == 'stop' or arg == '0' then
        state.ClearBurn()
        log.say('Burn window stopped.')
        return
    end
    local sec = state.SetBurn(tonumber(args[2])) -- nil arg -> default window
    log.say('Burn window started (%ds). Debuffs with a Burn band phase will cast.', sec)
end

local function cmd_aetank(args)
    local mode = args[2] and string.lower(args[2]) or ''
    if mode == 'on' or mode == 'true' or mode == '1' then
        botconfig.config.settings.tankAllMobs = true
    elseif mode == 'off' or mode == 'false' or mode == '0' then
        botconfig.config.settings.tankAllMobs = false
    else
        botconfig.config.settings.tankAllMobs = not (botconfig.config.settings.tankAllMobs == true)
    end
    botconfig.ApplyAndPersist()
    log.say('AE-tank %s', (botconfig.config.settings.tankAllMobs == true) and 'on' or 'off')
end

local function cmd_premem(args)
    local mode = args[2] and string.lower(args[2]) or ''
    if mode == 'on' or mode == 'true' or mode == '1' then
        botconfig.config.settings.premem = true
    elseif mode == 'off' or mode == 'false' or mode == '0' then
        botconfig.config.settings.premem = false
    else
        botconfig.config.settings.premem = not (botconfig.config.settings.premem ~= false)
    end
    botconfig.ApplyAndPersist()
    log.say('Pre-memorize gembar %s', (botconfig.config.settings.premem ~= false) and 'on' or 'off')
end

local function cmd_antiafk(args)
    local mode = args[2] and string.lower(args[2]) or ''
    if mode == 'on' or mode == 'true' or mode == '1' then
        botconfig.config.settings.antiAfk = true
    elseif mode == 'off' or mode == 'false' or mode == '0' then
        botconfig.config.settings.antiAfk = false
    else
        botconfig.config.settings.antiAfk = not (botconfig.config.settings.antiAfk ~= false)
    end
    botconfig.ApplyAndPersist()
    log.say('Anti-AFK %s', (botconfig.config.settings.antiAfk ~= false) and 'on' or 'off')
end

local function cmd_prememdebug(args)
    local premem = require('lib.premem')
    local mode = args[2] and string.lower(args[2]) or ''
    if mode == 'on' or mode == 'true' or mode == '1' then
        premem.SetDebug(true)
    elseif mode == 'off' or mode == 'false' or mode == '0' then
        premem.SetDebug(false)
    else
        premem.SetDebug(not premem.IsDebug())
    end
    log.say('Pre-mem debug logging %s', premem.IsDebug() and 'on' or 'off')
end

local function cmd_scribe(args)
    require('lib.scribe').Run()
end

local function cmd_autoscribe(args)
    local mode = args[2] and string.lower(args[2]) or ''
    if mode == 'on' or mode == 'true' or mode == '1' then
        botconfig.config.settings.autoScribe = true
    elseif mode == 'off' or mode == 'false' or mode == '0' then
        botconfig.config.settings.autoScribe = false
    else
        botconfig.config.settings.autoScribe = not (botconfig.config.settings.autoScribe ~= false)
    end
    botconfig.ApplyAndPersist()
    log.say('Auto-scribe on level-up %s', (botconfig.config.settings.autoScribe ~= false) and 'on' or 'off')
end

local function cmd_upgrades(args)
    local su = require('lib.spellupgrade')
    su.scan()
    local pending = su.getPending()
    if #pending == 0 then
        log.say('No spell upgrades available.')
        return
    end
    log.say('%d spell upgrade(s) available:', #pending)
    for i, u in ipairs(pending) do
        printf('  [%d] %s: %s (L%d) -> %s (L%d)', i, u.section, u.old, u.oldLevel, u.new, u.newLevel)
    end
    printf('  Apply with /cz applyupgrade <n|all>')
end

local function cmd_applyupgrade(args)
    local su = require('lib.spellupgrade')
    local which = args[2] and string.lower(args[2]) or ''
    if which == '' then
        log.say('Usage: /cz applyupgrade <n|all>  (see /cz upgrades)')
        return
    end
    if which == 'all' then
        log.say('Applied %d upgrade(s).', su.applyAll())
    else
        local n = tonumber(which)
        if not n or not su.apply(n) then
            log.say('No upgrade #%s (see /cz upgrades).', tostring(args[2]))
        end
    end
end

local function cmd_upgradedebug(args)
    local su = require('lib.spellupgrade')
    local mode = args[2] and string.lower(args[2]) or ''
    if mode == 'on' or mode == 'true' or mode == '1' then su.SetDebug(true)
    elseif mode == 'off' or mode == 'false' or mode == '0' then su.SetDebug(false)
    else su.SetDebug(not su.IsDebug()) end
    log.say('Upgrade debug logging %s', su.IsDebug() and 'on' or 'off')
end

local function cmd_aetankmezzer(args)
    local mode = args[2] and string.lower(args[2]) or ''
    if mode == 'on' or mode == 'true' or mode == '1' then
        botconfig.config.settings.aeTankIgnoreMezzer = true
    elseif mode == 'off' or mode == 'false' or mode == '0' then
        botconfig.config.settings.aeTankIgnoreMezzer = false
    else
        botconfig.config.settings.aeTankIgnoreMezzer = not (botconfig.config.settings.aeTankIgnoreMezzer == true)
    end
    botconfig.ApplyAndPersist()
    log.say('AE-tank ignore-mezzer %s', (botconfig.config.settings.aeTankIgnoreMezzer == true) and 'on (AE-tank runs with ENC/BRD in group)' or 'off (auto-suppress on ENC/BRD)')
end

local function cmd_aetankdebug(args)
    local botmelee = require('botmelee')
    local mode = args[2] and string.lower(args[2]) or ''
    if mode == 'on' or mode == 'true' or mode == '1' then botmelee.SetAeTankDebug(true)
    elseif mode == 'off' or mode == 'false' or mode == '0' then botmelee.SetAeTankDebug(false)
    else botmelee.SetAeTankDebug(not botmelee.IsAeTankDebug()) end
    log.say('AE-tank debug logging %s', botmelee.IsAeTankDebug() and 'on' or 'off')
end

local function cmd_charmpetsetup(args)
    local mode = args[2] and string.lower(args[2]) or ''
    if mode == 'on' or mode == 'true' or mode == '1' then
        botconfig.config.settings.charmPetAutoSetup = true
    elseif mode == 'off' or mode == 'false' or mode == '0' then
        botconfig.config.settings.charmPetAutoSetup = false
    else
        botconfig.config.settings.charmPetAutoSetup = not (botconfig.config.settings.charmPetAutoSetup ~= false)
    end
    botconfig.ApplyAndPersist()
    log.say('Charm pet auto-setup %s', (botconfig.config.settings.charmPetAutoSetup ~= false) and 'on' or 'off')
end

local function cmd_maanchorleash(args)
    local val = tonumber(args[2])
    if not val or val < 1 then
        log.say('Usage: /cz maanchorleash <number>')
        return
    end
    botconfig.config.settings.maAnchorLeash = val
    tankrole.bumpLeashGen()
    log.say('Setting maAnchorLeash to %s', val)
end

local function cmd_offtank(args)
    if not args[2] then
        if botconfig.config.melee.offtank == true then
            botconfig.config.melee.offtank = false
        else
            botconfig.config.melee.offtank = true
        end
    elseif string.lower(args[2]) == 'true' or string.lower(args[2]) == 'on' then
        botconfig.config.melee.offtank = true
    elseif string.lower(args[2]) == 'false' or string.lower(args[2]) == 'off' then
        botconfig.config.melee.offtank = false
    else
        log.say('%s is an invalid value for offtank, please use true, on, false, off, or leave it blank to toggle',
            args[2])
        return false
    end
    log.say('Setting offtank to %s', botconfig.config.melee.offtank)
end

-- Cast by alias (section: heal, buff, debuff, cure)
local function cmd_cast(args)
    if not args[2] then return end
    local function resolveCastTarget()
        if args[3] and args[3] ~= 'on' and args[3] ~= 'off' then
            local sp = mq.TLO.Spawn(args[3])
            local id = sp and sp.ID()
            if id and id > 0 then
                return id, sp.CleanName()
            end
        end
        local tid = mq.TLO.Target.ID()
        if tid and tid > 0 then
            return tid, mq.TLO.Target.CleanName()
        end
        return mq.TLO.Me.ID(), mq.TLO.Me.CleanName()
    end
    local function do_spell_section(cfgkey, loadfn, settingkey)
        local cnt = botconfig.getSpellCount(cfgkey)
        if not cnt or cnt <= 0 then return end
        for i = 1, cnt do
            local entry = botconfig.getSpellEntry(cfgkey, i)
            if not entry then return end
            for value in tostring(entry.alias or ''):gmatch("[^|]+") do
                if value == args[2] and (args[3] ~= 'on' and args[3] ~= 'off') then
                    local tgtID, tgtName = resolveCastTarget()
                    log.say('\agCasting\ax %s on %s', entry.spell, tgtName)
                    if cfgkey == 'debuff' and mq.TLO.Me.CastTimeLeft() > 0 then
                        spellutils.InterruptCheck()
                        return
                    end
                    if not spellutils.CastSpell(i, tgtID, 'castcommand', cfgkey) then
                        log.say('\arCast command spell %s not ready!', entry.spell)
                    end
                elseif args[3] and value == args[2] then
                    if args[3] == 'on' then
                        entry.enabled = true
                        log.say('Enabling \ag%s\ax', entry.spell)
                        if not botconfig.config.settings[settingkey] then
                            loadfn()
                            botconfig.config.settings[settingkey] = true
                        end
                    end
                    if args[3] == 'off' then
                        entry.enabled = false
                        log.say('Disabling \ag%s\ax', entry.spell)
                    end
                end
            end
        end
    end
    do_spell_section('debuff', botdebuff.LoadDebuffConfig, 'dodebuff')
    do_spell_section('buff', botbuff.LoadBuffConfig, 'dobuff')
    do_spell_section('heal', botheal.LoadHealConfig, 'doheal')
    do_spell_section('cure', botcure.LoadCureConfig, 'docure')
end

local function cmd_setvar(args)
    local valfound = false
    local sub, key
    local value = args[3]
    local tempconfig = {}
    local temploadconfig = loadfile(botconfig.getPath())
    if args[2]:find("%.") ~= nil then
        local beforeDot, afterDot = args[2]:match("([^%.]+)%.(.+)")
        sub = beforeDot
        key = afterDot
    end
    if temploadconfig then tempconfig = temploadconfig() end
    for k, v in pairs(tempconfig) do
        if sub then
            if type(v) == "table" and k == sub then
                for k2, v2 in pairs(tempconfig[k]) do
                    if key == k2 then
                        log.say('Setting \ag%s to \ay%s\ax', args[2], value)
                        valfound = true
                        if tonumber(value) then
                            tempconfig[k][k2] = tonumber(value)
                            botconfig.config[k][k2] = tonumber(value)
                        elseif value == "true" then
                            tempconfig[k][k2] = true
                            botconfig.config[k][k2] = true
                        elseif value == "false" then
                            tempconfig[k][k2] = false
                            botconfig.config[k][k2] = false
                        else
                            tempconfig[k][k2] = value
                            botconfig.config[k][k2] = value
                        end
                        botconfig.recomputeDerivedSettings()
                        botconfig.WriteToFile(tempconfig, botconfig.getPath())
                        botconfig.RunConfigLoaders()
                    end
                end
            end
        else
            if type(v) == "table" then
                for k2, v2 in pairs(tempconfig[k]) do
                    if args[2] == k2 then
                        log.say('Setting \ag%s to \ay%s\ax', args[2], value)
                        valfound = true
                        if tonumber(value) then
                            tempconfig[k][k2] = tonumber(value)
                            botconfig.config[k][k2] = tonumber(value)
                        elseif value == "true" then
                            tempconfig[k][k2] = true
                            botconfig.config[k][k2] = true
                        elseif value == "false" then
                            tempconfig[k][k2] = false
                            botconfig.config[k][k2] = false
                        else
                            tempconfig[k][k2] = value
                            botconfig.config[k][k2] = value
                        end
                        botconfig.recomputeDerivedSettings()
                        botconfig.WriteToFile(tempconfig, botconfig.getPath())
                        botconfig.RunConfigLoaders()
                    end
                end
            end
        end
    end
    if state.getRunconfig().doChchain then
        botconfig.config.settings.dodebuff = false
        botconfig.config.settings.dobuff = false
        botconfig.config.settings.domelee = false
        botconfig.config.settings.doheal = false
        botconfig.config.settings.docure = false
        state.getRunconfig().dopull = false
    end
    if not valfound then log.say('\ar%s not found', args[2]) end
end

local function copyEntry(src)
    if not src then return nil end
    local t = {}
    for k, v in pairs(src) do t[k] = v end
    return t
end

local function cmd_addspell(args)
    local sub = args[2]
    local key = tonumber(args[3])
    local sublist = { "heal", "cure", "buff", "debuff" }
    local subfound = false
    for _, word in ipairs(sublist) do
        if word == sub then
            subfound = true; break
        end
    end
    if not subfound then
        log.say('%s is not a valid CZBot sub please use heal, buff, debuff, or cure', sub)
        return false
    end
    local currentCount = botconfig.getSpellCount(sub)
    if not key or key < 1 or key > currentCount + 1 then
        log.say('%s is not a valid position for %s (use 1 to %s)', args[3], sub, currentCount + 1)
        return false
    end
    local temploadconfig = loadfile(botconfig.getPath())
    local tempconfig = (temploadconfig and temploadconfig()) or {}
    if not tempconfig[sub] then tempconfig[sub] = {} end
    if not tempconfig[sub].spells then tempconfig[sub].spells = {} end
    local newEntry = botconfig.getDefaultSpellEntry(sub)
    table.insert(tempconfig[sub].spells, key, newEntry)
    botconfig.WriteToFile(tempconfig, botconfig.getPath())
    botconfig.Load(botconfig.getPath())
    botconfig.RunConfigLoaders()
    if sub == 'heal' then botheal.LoadHealConfig() end
    if sub == 'buff' then botbuff.LoadBuffConfig() end
    if sub == 'debuff' then botdebuff.LoadDebuffConfig() end
    if sub == 'cure' then botcure.LoadCureConfig() end
    log.say('added new %s entry at position %s', sub, key)
end


local function cmd_refresh(args)
    spellutils.RefreshSpells()
end

local function cmd_echo(args)
    if not args[2] then return end
    local sub, key
    if args[2]:find("%.") ~= nil then
        local beforeDot, afterDot = args[2]:match("([^%.]+)%.(.+)")
        sub = beforeDot
        key = afterDot
    end
    if sub and key and botconfig.config[sub] and botconfig.config[sub][key] ~= nil then
        log.say('\ag%s\ax is set as \ay%s\ay', args[2], botconfig.config[sub][key])
    else
        log.say('\ar%s\ar is not a valid CZBot value', args[2])
    end
end

local function cmd_clickdoor()
    mq.cmd('/doortarget')
    mq.delay(500)
    mq.cmd('/click left door')
end

local function resolveSaytargetScope(args)
    local sub = args[2] and string.lower(args[2])
    if sub == 'group' or sub == 'raid' then
        return sub, 3
    end
    return autoBroadcastScope(), 2
end

local function cmd_syt(args, str)
    local id = args[2] and tonumber(args[2])
    local message
    if args[3] then
        message = table.concat(args, ' ', 3)
    elseif str then
        message = str:match('syt%s+%S+%s+(.+)') or str:match('saytarget%s+%S+%s+(.+)')
    end
    if not id or id == 0 or not message or message == '' then
        log.say('usage: /cz syt <spawnId> <message>')
        return
    end
    if not targeting.TargetAndWait(id, 500) then
        log.say('failed to target spawn id %s', id)
        return
    end
    mq.delay(math.random(10, 50) * 500)
    mq.cmdf('/say %s', message)
end

local function cmd_saytarget(args, str)
    local legacyId = args[2] and tonumber(args[2])
    if legacyId and legacyId ~= 0 then
        return cmd_syt(args, str)
    end

    local scope, msgStart = resolveSaytargetScope(args)
    local message = (msgStart <= #args) and table.concat(args, ' ', msgStart) or nil
    if (not message or message == '') and str then
        local sub = args[2] and string.lower(args[2])
        if sub == 'group' or sub == 'raid' then
            message = str:match('saytarget%s+' .. sub .. '%s+(.+)')
        else
            message = str:match('saytarget%s+(.+)')
        end
    end
    if message then
        local inner = message:match('^"(.*)"$')
        if inner then message = inner end
    end
    if not message or message == '' then
        log.say('usage: /cz saytarget [group|raid] <message>')
        return
    end
    local targetId = mq.TLO.Target.ID()
    if not targetId or targetId == 0 then
        log.say('saytarget requires a target')
        return
    end
    mq.cmdf('/rc %s /cz syt %s %s', scope, targetId, message)
    log.say('saytarget broadcast (%s)', scope)
    cmd_syt({ 'syt', tostring(targetId), message }, '')
end

-- CHChain: on, off, start, test, delay
local function cmd_chchain(args)
    local sub = args[2] and string.lower(args[2])
    if not sub then
        log.say('Usage: /cz chchain on|off|start|test|delay <ms>')
        return
    end
    if sub == 'on' then
        if chchain.enable() then
            chchain.publishControl('start')
        end
        return
    end
    if sub == 'off' or sub == 'stop' then
        chchain.publishControl('stop')
        chchain.disable()
        return
    end
    if sub == 'start' then
        chchain.publishControl('kickoff', meName())
        chchain.startCast(false)
        return
    end
    if sub == 'test' then
        if not state.getRunconfig().doChchain then chchain.enable() end
        chchain.startCast(true)
        return
    end
    if sub == 'delay' then
        local v = tonumber(args[3])
        if not v then
            log.say('CH delay: %d ms', chchain.getSettings().broadcastDelayMs)
            return
        end
        if v < 100 then v = v * 1000 end
        chchain.saveSettings({ broadcastDelayMs = math.max(0, math.min(30000, v)) })
        log.say('CH delay set to %d ms', v)
        return
    end
    log.say('Usage: /cz chchain on|off|start|test|delay <ms>')
end

local function meName()
    return mq.TLO.Me.CleanName() or mq.TLO.Me.Name()
end

local function cmd_draghack(args)
    if args[2] then
        if args[2] == 'on' then state.getRunconfig().DragHack = true end
        if args[2] == 'off' then state.getRunconfig().DragHack = false end
    elseif not args[2] then
        if state.getRunconfig().DragHack then state.getRunconfig().DragHack = false else state.getRunconfig().DragHack = true end
    end
    log.say('Set DragHack to %s', state.getRunconfig().DragHack)
end

local function cmd_linkitem(args)
    botevents.Event_LinkItem(args[1], args[2], args[3])
end

local function cmd_linkaugs(args)
    local itemslot = tonumber(mq.TLO.InvSlot(args[2])())
    local itemlink = mq.TLO.InvSlot(args[2]).Item.ItemLink('CLICKABLE')()
    if itemslot then
        local augstring = nil
        local augslots = tonumber(mq.TLO.InvSlot(itemslot).Item.Augs())
        for i = 1, augslots do
            local aug = mq.TLO.InvSlot(itemslot).Item.AugSlot(i)()
            local auglink = mq.TLO.FindItem(aug).ItemLink('CLICKABLE')()
            if aug and augstring then
                augstring = augstring .. " , " .. auglink
            elseif aug then
                augstring = auglink
            end
        end
        if augstring then
            log.say('\ag%s\ax in slot \ay%s\ax augs: %s', itemlink, args[2], augstring)
        else
            log.say('\arI have no augment in %s', itemlink)
        end
    end
end

local function cmd_spread(args)
    local peers = charinfo.GetPeers()
    local myname = mq.TLO.Me.Name()
    local startX = mq.TLO.Me.X()
    local startY = mq.TLO.Me.Y()
    local heading = mq.TLO.Me.Heading.Degrees()
    local slot = 0
    for _, bot in ipairs(peers) do
        if bot == myname then
            -- skip self; we stay in place and only run the face command
        else
            slot = slot + 1
            local xiter = startX + ((slot - 1) % 6 + 1) * 5
            local yiter = startY + math.floor((slot - 1) / 6) * 5
            mq.cmdf('/rc %s /nav locxy %s %s', bot, xiter, yiter)
        end
    end
    mq.cmd('/face fast heading ' .. heading)
    mq.cmdf('/rc zone /face fast heading %s', heading)
end

local function getApplicableNukeFlavors()
    local count = botconfig.getSpellCount('debuff')
    local out = {}
    for i = 1, count do
        local entry = botconfig.getSpellEntry('debuff', i)
        if entry and spellutils.IsNukeSpell(entry) then
            local f = spellutils.GetNukeFlavor(entry)
            if f then out[f] = true end
        end
    end
    return out
end

local function cmd_togglenuke(args)
    local raw = args[2] and tostring(args[2]) or ''
    local flavorArg = string.lower(raw:match('^%s*(.-)%s*$') or '')
    if flavorArg == '' then
        log.say('Usage: /cz togglenuke <flavor> [on|off]. Flavors: fire, ice, magic, poison, disease (and cold=ice).')
        return
    end
    local flavor = (flavorArg == 'cold') and 'ice' or flavorArg
    local applicable = getApplicableNukeFlavors()
    if not applicable[flavor] then
        log.say('No nuke with flavor \ar%s\ax in debuff list. Use a flavor from your configured nukes.',
            flavor)
        return
    end
    local force = args[3] and string.lower(args[3])
    local rc = state.getRunconfig()
    local function setOff()
        if not rc.nukeFlavorsAllowed then
            rc.nukeFlavorsAllowed = {}
            for f in pairs(applicable) do rc.nukeFlavorsAllowed[f] = true end
        end
        rc.nukeFlavorsAllowed[flavor] = nil
    end
    local function setOn()
        if rc.nukeFlavorsAutoDisabled then rc.nukeFlavorsAutoDisabled[flavor] = nil end
        if rc.nukeFlavorsAllowed then rc.nukeFlavorsAllowed[flavor] = true end
    end
    if force == 'off' then
        setOff()
        log.say('Nuke flavor \ar%s\ax turned off.', flavor)
    elseif force == 'on' then
        setOn()
        log.say('Nuke flavor \ag%s\ax turned on.', flavor)
    else
        local allowed = (not rc.nukeFlavorsAutoDisabled or not rc.nukeFlavorsAutoDisabled[flavor])
            and (not rc.nukeFlavorsAllowed or rc.nukeFlavorsAllowed[flavor])
        if allowed then
            setOff(); log.say('Nuke flavor \ar%s\ax turned off.', flavor)
        else
            setOn(); log.say('Nuke flavor \ag%s\ax turned on.', flavor)
        end
    end
    rc.nukeResistDisabledRecent = nil
    botconfig.saveNukeFlavorsToCommon()
end

local function cmd_raid(args)
    local sub = args[2] and string.lower(args[2])
    if sub == 'save' then
        if not args[3] or args[3] == '' then
            log.say('Noname given, cant save raid (/cz raid save raidname)')
            return
        end
        groupmanager.SaveRaid(args[3])
    elseif sub == 'load' then
        if not args[3] or args[3] == '' then
            print('no raid name giving /cz raid load raidname') -- this is a real error message but needs to be reformatted
            return
        end
        groupmanager.LoadRaid(args[3])
    end
end

-- Handler table: command name -> function(args, str).
-- Handlers receive (args, str); str only used by stickcmd.
local handlers = {
    import = cmd_import,
    export = cmd_export,
    debug = cmd_debug,
    ui = cmd_ui,
    show = cmd_ui,
    makecamp = cmd_makecamp,
    camphere = cmd_camphere,
    follow = cmd_follow,
    followme = cmd_followme,
    travel = cmd_travel,
    stop = cmd_stop,
    exclude = cmd_exclude,
    fte = cmd_fte,
    xarc = cmd_xarc,
    priority = cmd_priority,
    charm = cmd_charm,
    reloadcommon = cmd_reloadcommon,
    reloadczcommon = cmd_reloadcommon,
    abort = cmd_abort,
    disengage = cmd_disengage,
    leash = cmd_leash,
    attack = cmd_attack,
    tank = cmd_tank,
    assist = cmd_assist,
    tankrole = cmd_tankrole,
    stickcmd = cmd_stickcmd,
    acleash = cmd_acleash,
    evadepct = cmd_evadepct,
    camprestdistance = cmd_camprestdistance,
    targetfilter = cmd_targetfilter,
    mobfilter = cmd_mobfilter,
    macampanchor = cmd_macampanchor,
    engagextargetonly = cmd_engagextargetonly,
    xtargetonly = cmd_engagextargetonly,
    role = cmd_role,
    mezdebug = cmd_mezdebug,
    buffdebug = cmd_buffdebug,
    barddebug = cmd_barddebug,
    tickdebug = cmd_tickdebug,
    actordebug = cmd_actordebug,
    charmpetsetup = cmd_charmpetsetup,
    aetank = cmd_aetank,
    aetankmezzer = cmd_aetankmezzer,
    aetankdebug = cmd_aetankdebug,
    premem = cmd_premem,
    antiafk = cmd_antiafk,
    prememdebug = cmd_prememdebug,
    scribe = cmd_scribe,
    autoscribe = cmd_autoscribe,
    upgrades = cmd_upgrades,
    applyupgrade = cmd_applyupgrade,
    upgradedebug = cmd_upgradedebug,
    burn = cmd_burn,
    maanchorleash = cmd_maanchorleash,
    offtank = cmd_offtank,
    actor = cmd_actor,
    cast = cmd_cast,
    setvar = cmd_setvar,
    addspell = cmd_addspell,
    refresh = cmd_refresh,
    refreshspells = cmd_refresh,
    echo = cmd_echo,
    clickdoor = cmd_clickdoor,
    saytarget = cmd_saytarget,
    syt = cmd_syt,
    chchain = cmd_chchain,
    draghack = cmd_draghack,
    linkitem = cmd_linkitem,
    linkaugs = cmd_linkaugs,
    spread = cmd_spread,
    raid = cmd_raid,
    togglenuke = cmd_togglenuke,
    togglesongs = cmd_togglesongs,
    mobprob = cmd_mobprob,
    togglecampacleash = cmd_togglecampacleash,
    addjunk = cmd_addjunk,
    foragezone = cmd_foragezone,
    quit = cmd_quit,
}

-- Register toggle commands (same handler for all togglelist keys)
for k in pairs(TOGGLELIST) do
    handlers[k] = cmd_toggle
end

for cmd, fn in pairs(handlers) do
    command_dispatcher.RegisterCommand(cmd, fn)
end

-- Entry points for makecamp/follow (callable without going through the parser)
function M.MakeCamp(mode)
    botmove.MakeCamp(mode)
end

function M.Follow(tankName)
    if tankName then cmd_follow({ 'follow', tankName }, '') end
end

function M.Travel(tankName)
    if tankName then cmd_travel({ 'travel', tankName }, '') end
end

function M.Parse(...)
    local args = { ... }
    local str = ''
    for i = 1, #args, 1 do
        if i > 1 then str = str .. ' ' end
        str = str .. args[i]
    end
    if TOGGLELIST[args[1]] then
        cmd_toggle(args)
        return
    end

    command_dispatcher.Dispatch(args[1], unpack(args, 2))
end

M.czpause = state.czpause

mq.bind('/cz', M.Parse)
mq.bind('/czshow', botgui.UIEnable)
mq.bind('/czp', M.czpause)
mq.bind('/czquit', function() state.getRunconfig().terminate = true end)

return M
