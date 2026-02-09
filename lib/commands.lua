-- Command parser for /cz: dispatches to per-command handlers.
-- Uses globals and modules from the CZBot environment (state.getRunconfig(), botconfig, etc.).

local M = {}
local mq = require('mq')
local botconfig = require('lib.config')
local botgui = require('botgui')
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
local groupmanager = require('lib.groupmanager')
local charinfo = require("mqcharinfo")
local utils = require('lib.utils')
local command_dispatcher = require('lib.command_dispatcher')
local follow = require('lib.follow')
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
}

-- --- Toggle handler (domelee, dopull, etc.) ---
local function cmd_toggle(args)
    if args[2] == 'on' then
        botconfig.config.settings[args[1]] = true
    elseif args[2] == 'off' then
        botconfig.config.settings[args[1]] = false
        if args[1] == 'dopull' then
            if APTarget and APTarget.ID() then APTarget = nil end
            if botconfig.config.pull.hunter then
                state.getRunconfig().makecamp = { x = nil, y = nil, z = nil }
            end
            mq.cmd('/squelch /target clear ; /nav stop ; /stick off ; /attack off')
        end
    else
        if botconfig.config.settings[args[1]] == true then
            botconfig.config.settings[args[1]] = false
            if args[1] == 'dopull' or args[1] == 'domelee' then
                if APTarget and APTarget.ID() then APTarget = nil end
                mq.cmd('/squelch /target clear ; /nav stop ; /stick off ; /attack off')
            end
            if args[1] == 'dopull' and botconfig.config.pull.hunter then
                state.getRunconfig().makecamp = { x = nil, y = nil, z = nil }
            end
        else
            botconfig.config.settings[args[1]] = false
            botconfig.config.settings[args[1]] = true
        end
    end
    botconfig.RunConfigLoaders()
    if botconfig.config.settings.doraid then botraid.LoadRaidConfig() end
    printf('\ayCZBot:\axTurning %s to %s', args[1], botconfig.config.settings[args[1]])
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
            printf('\ayCZBot:\axLoaded lua file %s', args[3])
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
    if args[2] then
        botmove.MakeCamp(args[2])
    elseif not args[2] then
        if state.getRunconfig().campstatus then
            botmove.MakeCamp('off')
        else
            botmove.MakeCamp('on')
        end
    end
    if state.getRunconfig().followid or state.getRunconfig().followname then
        state.getRunconfig().followid = nil
        state.getRunconfig().followname = nil
    end
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
    if state.getRunconfig().followid or state.getRunconfig().followname then
        state.getRunconfig().followid = nil
        state.getRunconfig().followname = nil
    end
    if state.getRunconfig().campstatus then botmove.MakeCamp('off') end
    printf('\ayCZBot:\ax\arDisabling makecamp and follow')
end

local function cmd_exclude(args)
    local excludemob = args[2]
    if not args[2] then excludemob = mq.TLO.Target.CleanName() end
    if excludemob and not string.find(state.getRunconfig().ExcludeList, excludemob) and args[2] ~= 'save' then
        printf('\ayCZBot:\axExcluding %s from CZBot', excludemob)
        state.getRunconfig().ExcludeList = state.getRunconfig().ExcludeList .. excludemob .. '|'
        if APTarget and APTarget.ID() then APTarget = nil end
        mq.cmd('/squelch /target clear ; /nav stop ; /stick off ; /attack off')
    end
    if args[3] == 'save' or args[2] == 'save' then
        printf('\ayCZBot:\axSaving exclude list')
        mobfilter.process('exclude', 'save')
    else
        mobfilter.process('exclude')
    end
end

local function cmd_xarc(args)
    botpull.SetPullArc(args[2])
end

local function cmd_priority(args)
    local prioritymob = args[2]
    if not args[2] then prioritymob = mq.TLO.Target.CleanName() end
    if prioritymob and not string.find(state.getRunconfig().PriorityList, prioritymob) and args[2] ~= 'save' then
        printf('\ayCZBot:\axPrioritizing %s in CZBot', prioritymob)
        state.getRunconfig().PriorityList = state.getRunconfig().PriorityList .. prioritymob .. '|'
    end
    if args[3] == 'save' or args[2] == 'save' then
        printf('\ayCZBot:\axSaving priority list')
        mobfilter.process('priority', 'save')
    else
        mobfilter.process('priority')
    end
end

local function cmd_abort(args)
    if not args[2] then
        if mq.TLO.Me.CastTimeLeft() > 0 and state.getRunconfig().CurSpell.sub and state.getRunconfig().CurSpell.sub == 'ad' then
            mq.cmd('/stopcast')
        end
        if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
        if mq.TLO.Target.ID() then mq.cmd('/squelch /target clear') end
        if state.getRunconfig().engageTargetId then state.getRunconfig().engageTargetId = nil end
        if botconfig.config.settings.domelee then
            botconfig.config.settings.domelee = false
            meleeabort = true
        end
        if botconfig.config.settings.dodebuff then
            botconfig.config.settings.dodebuff = false
            debuffabort = true
        end
        printf('\ayCZBot:\ax\arAbort+ called!\ax - DoDebuffs & DoMelee FALSE and leashing to camp')
    elseif args[2] == 'off' then
        if not botconfig.config.settings.domelee and meleeabort then botconfig.config.settings.domelee = true end
        if not botconfig.config.settings.dodebuff and debuffabort then botconfig.config.settings.dodebuff = true end
        mq.cmd('\arAbort\ax OFF, enabling dps sections again')
    end
end

local function cmd_leash(args)
    if state.getRunconfig().campstatus then
        printf('\ayCZBot:\ax\arLeash\ax called, returning to camp location')
        botmove.MakeCamp('return')
    else
        printf('\ayCZBot:\axNo camp set, cannot leash')
    end
end

-- Engage MA's target.
local function cmd_attack(args)
    local tankrole = require('lib.tankrole')
    local assistName = tankrole.GetAssistTargetName()
    if not assistName then
        printf('\ayCZBot:\ax\ar No Main Assist set, cannot engage')
        return
    end
    local maInfo = charinfo.GetInfo(assistName)
    local KillTarget = maInfo and maInfo.Target and maInfo.Target.ID or nil
    state.getRunconfig().engageTargetId = KillTarget
    if KillTarget then
        printf('\ayCZBot:\ax\arEngaging\ax \ay%s\ax now', mq.TLO.Spawn(KillTarget).CleanName())
    else
        printf('\ayCZBot:\ax\ar Main Assist has no target, cannot engage')
    end
end

-- Set MT (Main Tank).
local function cmd_tank(args)
    if not args[2] then return end
    local name = (args[2] == 'automatic') and 'automatic' or (args[2]:sub(1, 1):upper() .. args[2]:sub(2))
    state.getRunconfig().TankName = name
    printf('\ayCZBot:\axSetting tank to %s', name)
    mq.TLO.Target.TargetOfTarget()
end

-- Set MA (Main Assist).
local function cmd_assist(args)
    if not args[2] then return end
    local name = (args[2] == 'automatic') and 'automatic' or (args[2]:sub(1, 1):upper() .. args[2]:sub(2))
    state.getRunconfig().AssistName = name
    printf('\ayCZBot:\axSetting assist to %s', name)
end

local function cmd_stickcmd(args, str)
    botconfig.config.melee.stickcmd = str:match('stickcmd' .. "%s+(.+)")
    printf('\ayCZBot:\axSetting stickcmd to %s', botconfig.config.melee.stickcmd)
end

local function cmd_acleash(args)
    botconfig.config.settings.acleash = tonumber(args[2])
    printf('\ayCZBot:\axSetting acleash to %s', botconfig.config.settings.acleash)
end

local function cmd_targetfilter(args)
    botconfig.config.settings.TargetFilter = tonumber(args[2])
    printf('\ayCZBot:\axSetting TargetFilter to %s', botconfig.config.settings.TargetFilter)
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
        printf(
            '\ayCZBot:\ax%s is an invalid value for offtank, please use true, on, false, off, or leave it blank to toggle',
            args[2])
        return false
    end
    printf('\ayCZBot:\axSetting offtank to %s', botconfig.config.melee.offtank)
end

-- Cast by alias (section: heal, buff, debuff, cure)
local function cmd_cast(args)
    if not args[2] then return end
    local target = args[3] and mq.TLO.Spawn(args[3]).ID() or mq.TLO.Target.ID()
    local function do_spell_section(cfgkey, loadfn, settingkey)
        local cnt = botconfig.getSpellCount(cfgkey)
        if not cnt or cnt <= 0 then return end
        for i = 1, cnt do
            local entry = botconfig.getSpellEntry(cfgkey, i)
            if not entry then return end
            for value in tostring(entry.alias or ''):gmatch("[^|]+") do
                if value == args[2] and (args[3] ~= 'on' and args[3] ~= 'off') then
                    printf('\ayCZBot:\ax\agCasting\ax %s on %s', entry.spell, mq.TLO.Spawn(target).CleanName())
                    if cfgkey == 'debuff' and mq.TLO.Me.CastTimeLeft() > 0 then
                        spellutils.InterruptCheck()
                        return
                    end
                    if not spellutils.CastSpell(i, target, 'castcommand', cfgkey) then
                        printf('\ayCZBot:\ax\arCast command spell %s not ready!', entry.spell)
                    end
                elseif args[3] and value == args[2] then
                    if args[3] == 'on' then
                        entry.enabled = true
                        printf('\ayCZBot:\axEnabling \ag%s\ax', entry.spell)
                        if not botconfig.config.settings[settingkey] then
                            loadfn()
                            botconfig.config.settings[settingkey] = true
                        end
                    end
                    if args[3] == 'off' then
                        entry.enabled = false
                        printf('\ayCZBot:\axDisabling \ag%s\ax', entry.spell)
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
                        printf('\ayCZBot:\axSetting \ag%s to \ay%s\ax', args[2], value)
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
                        botconfig.WriteToFile(tempconfig, botconfig.getPath())
                        botconfig.RunConfigLoaders()
                    end
                end
            end
        else
            if type(v) == "table" then
                for k2, v2 in pairs(tempconfig[k]) do
                    if args[2] == k2 then
                        printf('\ayCZBot:\axSetting \ag%s to \ay%s\ax', args[2], value)
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
                        botconfig.WriteToFile(tempconfig, botconfig.getPath())
                        botconfig.RunConfigLoaders()
                    end
                end
            end
        end
    end
    if dochchain then
        botconfig.config.settings.dodebuff = false
        botconfig.config.settings.dobuff = false
        botconfig.config.settings.domelee = false
        botconfig.config.settings.doheal = false
        botconfig.config.settings.docure = false
        botconfig.config.settings.dopull = false
        botconfig.config.settings.dopet = false
    end
    if not valfound then printf('\ayCZBot:\ax\ar%s not found', args[2]) end
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
        printf('\ayCZBot:\ax%s is not a valid CZBot sub please use heal, buff, debuff, or cure', sub)
        return false
    end
    local currentCount = botconfig.getSpellCount(sub)
    if not key or key < 1 or key > currentCount + 1 then
        printf('\ayCZBot:\ax%s is not a valid position for %s (use 1 to %s)', args[3], sub, currentCount + 1)
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
    printf('\ayCZBot:\axadded new %s entry at position %s', sub, key)
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
        printf('\ayCZBot:\ax\ag%s\ax is set as \ay%s\ay', args[2], botconfig.config[sub][key])
    else
        printf('\ayCZBot:\ax\ar%s\ar is not a valid CZBot value', args[2])
    end
end

-- CHChain: stop, setup, start, tank, pause
local function cmd_chchain(args)
    if args[2] == 'stop' and dochchain then
        dochchain = false
        printf('\ayCZBot:\ax\arDisabling\ax CHChain')
        mq.cmd('/rs CHCHain OFF')
        if state.getRunconfig().PreCH['dodebuff'] then
            botconfig.config.settings.dodebuff = state.getRunconfig().PreCH
                ['dodebuff']
        end
        if state.getRunconfig().PreCH['dobuff'] then
            botconfig.config.settings.dobuff = state.getRunconfig().PreCH
                ['dobuff']
        end
        if state.getRunconfig().PreCH['domelee'] then
            botconfig.config.settings.domelee = state.getRunconfig().PreCH
                ['domelee']
        end
        if state.getRunconfig().PreCH['doheal'] then
            botconfig.config.settings.doheal = state.getRunconfig().PreCH
                ['doheal']
        end
        if state.getRunconfig().PreCH['dopull'] then
            botconfig.config.settings.dopull = state.getRunconfig().PreCH
                ['dopull']
        end
        if state.getRunconfig().PreCH['dopet'] then
            botconfig.config.settings.dopet = state.getRunconfig().PreCH
                ['dopet']
        end
        if state.getRunconfig().PreCH['docure'] then
            botconfig.config.settings.docure = state.getRunconfig().PreCH
                ['docure']
        end
    end
    if args[2] == 'setup' then
        local gem = 5
        local spell = 'complete heal'
        if not dochchain then state.getRunconfig().PreCH = utils.DeepCopy(botconfig.config.settings) end
        local tmpchchainlist = args[3]
        local aminlist = false
        for v in string.gmatch(tmpchchainlist, "([^,]+)") do
            if string.lower(v) == string.lower(mq.TLO.Me.CleanName()) then aminlist = true end
        end
        if not aminlist then return false end
        if mq.TLO.Me.Gem(spell)() ~= gem then
            if mq.TLO.Me.Book(spell)() then
                mq.cmdf('/memorize "%s" %s', spell, gem)
                state.getRunconfig().gemInUse[gem] = (mq.gettime() + mq.TLO.Spell(spell).RecastTime())
                state.getRunconfig().statusMessage = 'CHChain: memorizing Complete Heal'
                mq.delay(10000, function()
                    local g = mq.TLO.Me.Gem(gem)()
                    return g and string.lower(g) == string.lower(spell)
                end)
                state.getRunconfig().statusMessage = ''
            else
                printf('\ayCZBot:\axCZBot CHChain: Spell %s not found in your book, failed to start CHChain', spell)
                return false
            end
        end
        chchainlist = args[3]
        chnextclr = nil
        clericlisttbl = {}
        for v in string.gmatch(chchainlist, "([^,]+)") do
            table.insert(clericlisttbl, v)
            if chnextclr then
                chnextclr = v
                break
            end
            if string.lower(v) == string.lower(mq.TLO.Me.CleanName()) then
                dochchain = true
                chnextclr = true
            end
        end
        if chnextclr == true then chnextclr = clericlisttbl[1] end
        if dochchain then
            chchainpause = args[4]
            chtanklist = {}
            if args[5] then
                for v in string.gmatch(args[5], "([^,]+)") do
                    local vtrim = v:sub(-1) == "'" and v:sub(1, -2) or v
                    if mq.TLO.Spawn('=' .. vtrim).Type() == 'PC' then
                        table.insert(chtanklist, vtrim)
                        print('adding ' .. vtrim .. ' to tank list') -- doesn't look like debug but probably should be formatted better
                    end
                end
            end
            chchaintank = chtanklist[1]
            local chtankstr = table.concat(chtanklist, ",")
            botconfig.config.settings.dodebuff = false
            botconfig.config.settings.dobuff = false
            botconfig.config.settings.domelee = false
            botconfig.config.settings.doheal = false
            botconfig.config.settings.docure = false
            botconfig.config.settings.dopull = false
            botconfig.config.settings.dopet = false
            mq.cmdf('/rs CHChain ON (NextClr: %s, Pause: %s, Tank: %s)', chnextclr, chchainpause, chtankstr)
        end
    end
    if args[2] == 'start' then
        if args[3] == mq.TLO.Me.Name() then chchain.OnGo('start', mq.TLO.Me.Name()) end
    end
    if args[2] == 'tank' then
        if mq.TLO.Spawn('=' .. args[3]) then
            chchaintank = args[3]
            chtanklist = {}
        end
        mq.cmdf('/rs CHChain tank: %s', chchaintank)
    end
    if args[2] == 'pause' then
        if args[3] then chchainpause = args[3] end
        mq.cmdf('/rs CHChain pause: %s', chchainpause)
    end
end

local function cmd_draghack(args)
    if args[2] then
        if args[2] == 'on' then state.getRunconfig().DragHack = true end
        if args[2] == 'off' then state.getRunconfig().DragHack = false end
    elseif not args[2] then
        if state.getRunconfig().DragHack then state.getRunconfig().DragHack = false else state.getRunconfig().DragHack = true end
    end
    printf('\ayCZBot:\axSet DragHack to %s', state.getRunconfig().DragHack)
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
            printf('\ayCZBot:\ax\ag%s\ax in slot \ay%s\ax augs: %s', itemlink, args[2], augstring)
        else
            printf('\ayCZBot:\ax\arI have no augment in %s', itemlink)
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

local function cmd_raid(args)
    local sub = args[2] and string.lower(args[2])
    if sub == 'save' then
        if not args[3] or args[3] == '' then
            printf('\ayCZBot:\ax Noname given, cant save raid (/cz raid save raidname)')
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
    follow = cmd_follow,
    stop = cmd_stop,
    exclude = cmd_exclude,
    xarc = cmd_xarc,
    priority = cmd_priority,
    abort = cmd_abort,
    leash = cmd_leash,
    attack = cmd_attack,
    tank = cmd_tank,
    assist = cmd_assist,
    stickcmd = cmd_stickcmd,
    acleash = cmd_acleash,
    targetfilter = cmd_targetfilter,
    offtank = cmd_offtank,
    cast = cmd_cast,
    setvar = cmd_setvar,
    addspell = cmd_addspell,
    refresh = cmd_refresh,
    refreshspells = cmd_refresh,
    echo = cmd_echo,
    chchain = cmd_chchain,
    draghack = cmd_draghack,
    linkitem = cmd_linkitem,
    linkaugs = cmd_linkaugs,
    spread = cmd_spread,
    raid = cmd_raid,
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
    cmd_makecamp({ 'makecamp', mode }, '')
end

function M.Follow(tankName)
    if tankName then cmd_follow({ 'follow', tankName }, '') end
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

function M.czpause(...)
    local args = { ... }
    if args[1] and args[1] == 'off' then
        MasterPause = false
        mq.cmd('/echo Unpausing CZBot')
    elseif args[1] and args[1] == 'on' then
        MasterPause = true
        mq.cmd('/echo Pausing CZBot')
    else
        if MasterPause == false then
            MasterPause = true
            mq.cmd('/echo Pausing CZBot')
        else
            MasterPause = false
            mq.cmd('/echo Unpausing CZBot')
        end
    end
end

mq.bind('/cz', M.Parse)
mq.bind('/czshow', botgui.UIEnable)
mq.bind('/czp', M.czpause)
mq.bind('/czquit', function() state.getRunconfig().terminate = true end)

return M
