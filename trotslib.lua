local mq = require('mq')
local imgui = require('ImGui')
local trotsdb = require('trotsdb')
local trotslib = {}

-- directory of this script, used for local imports
local tbdir = ''
local _src = debug and debug.getinfo and debug.getinfo(1, 'S') and debug.getinfo(1, 'S').source or ''
if _src then
    local m = _src:match('@(.+)[/\\]')
    if m then tbdir = m .. '\\' end
end

--build variables for trotslib
--create full copy of a table instead of a reference
function DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[DeepCopy(orig_key)] = DeepCopy(orig_value)
        end
        setmetatable(copy, DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

local function writeConfigToFile(config, filename, order)
    local file = io.open(filename, "w") -- Open a file in write mode
    if not file then
        return false, "Could not open file for writing."
    end

    local function writesubTable(t, order2, indent)
        indent = indent or ""
        if type(order2) == "table" then
            local value = ''
            local valueStr = nil
            for _, key in ipairs(order2) do
                value = t[key]
                if type(value) == "table" then
                    print("detected a corrupted value for:", key, " = ", value)
                    printf("setting %s to nil, please check your config", key)
                    valueStr = nil
                    file:write(indent .. "['" .. key .. "'] =  nil ,\n")
                    file:flush()
                else
                    --print(key)
                    if tonumber(value) then
                        valueStr = tonumber(value)
                        if debug then print(key, valueStr) end
                        file:write(indent .. "['" .. key .. "'] = ", valueStr, ",\n")
                        file:flush()
                    elseif value == true then
                        valueStr = true
                        file:write(indent .. "['" .. key .. "'] = true,\n")
                        file:flush()
                    elseif value == false then
                        valueStr = false
                        file:write(indent .. "['" .. key .. "'] = false ,\n")
                    else
                        valueStr = type(value) == "string" and '"' .. value .. '"' or tostring(value)
                        --print("string2:",key, " = ",valueStr)
                        file:write(indent .. "['" .. key .. "'] = " .. valueStr .. ",\n")
                        file:flush()
                    end
                end
            end
        end
    end

    local function writeTable(t, order1)
        local entcounter = 1
        local indent = ""
        --print(order)
        if type(order1) == "table" then
            local value = ''
            local section = ''
            for _, key in ipairs(order1) do
                if string.sub(key, 1, 2) == 'ah' or string.sub(key, 1, 2) == 'ab' or string.sub(key, 1, 2) == 'ad' or string.sub(key, 1, 2) == 'ac' or string.sub(key, 1, 2) == 'ae' then
                    if string.sub(key, 1, 2) == 'ah' then section = 'heal' end
                    if string.sub(key, 1, 2) == 'ab' then section = 'buff' end
                    if string.sub(key, 1, 2) == 'ad' then section = 'debuff' end
                    if string.sub(key, 1, 2) == 'ac' then section = 'cure' end
                    if string.sub(key, 1, 2) == 'ae' then section = 'event' end
                    --need for loop to build all possible spell entries
                    if myconfig[section] and myconfig[section].count ~= nil then
                        for i = 1, myconfig[section]['count'] do
                            value = t[key .. i]
                            if type(value) == "table" then
                                file:write(indent .. "['" .. key .. i .. "'] = {\n")
                                file:flush()
                                writesubTable(value, subOrder[key], indent .. "  ")
                                file:write(indent .. "},\n")
                                file:flush()
                                entcounter = entcounter + 1
                            end
                        end
                    else
                    end
                else
                    value = t[key]
                    if type(value) == "table" then
                        file:write(indent .. "['" .. key .. "'] = {\n")
                        file:flush()
                        -- If the value is a table, and there's a sub-order for it, pass it along
                        writesubTable(value, subOrder[key], indent .. "  ")
                        file:write(indent .. "},\n")
                        file:flush()
                    else
                        local valueStr = type(value) == "string" and '"' .. value .. '"' or tostring(value)
                        file:write(indent .. "['" .. key .. "'] = " .. valueStr .. ",\n")
                        file:flush()
                    end
                end
            end
        end
    end

    file:write("StoredConfig =  {\n")
    file:flush()
    writeTable(config, order)
    file:write("}\n")
    file:flush()
    file:write("return StoredConfig")
    file:flush()

    file:close() -- Don't forget to close the file when done
    return true
end

-- Function to sanitize the file content
-- Function to sanitize the file content more accurately
local function sanitizeConfigFile(path)
    -- Read the raw file content
    local file, err = io.open(path, "r")
    if not file then
        print("Error opening file:", err)
        return nil
    end

    local content = file:read("*all")
    file:close()

    -- Pattern to match specific entries with "table: 0xXXXXXX" and replace with nil
    -- This only targets the format key = table: 0xXXXXXX and leaves other parts untouched
    content = content:gsub("%['%w+'%]%s*=%s*table: 0x[%w]+%s*,?", function(entry)
        print("Sanitizing invalid entry:", entry)
        return entry:gsub("table: 0x[%w]+", "nil")
    end)

    -- Load the sanitized Lua code from the string
    local configData, loadErr = load(content)
    if not configData then
        print("Error loading sanitized config:", loadErr)
        return nil
    end
    print("Config repaired and reloaded successfully")
    -- Execute the loaded function to get the config table
    local config = configData()
    return config
end


debug = false
local tbgui = false
local isOpen, shouldDraw = true, true
local YELLOW = ImVec4(1, 1, 0, 1)
local RED = ImVec4(1, 0, 0, 1)
local TABLE_FLAGS = bit32.bor(ImGuiTableFlags.ScrollY, ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersOuter,
    ImGuiTableFlags.BordersV, ImGuiTableFlags.SizingStretchSame, ImGuiTableFlags.Sortable,
    ImGuiTableFlags.Hideable, ImGuiTableFlags.Resizable, ImGuiTableFlags.Reorderable)
local function drawNestedTableTree(table)
    for k, v in pairs(table) do
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        if type(v) == 'table' then
            local open = ImGui.TreeNodeEx(tostring(k), ImGuiTreeNodeFlags.SpanFullWidth)
            if open then
                drawNestedTableTree(v)
                ImGui.TreePop()
            end
        else
            ImGui.TextColored(YELLOW, '%s', k)
            ImGui.TableNextColumn()
            ImGui.TextColored(RED, '%s', v)
            ImGui.TableNextColumn()
            -- Create an input text field with a unique ID using the key
            if type(v) == 'number' or type(v) == 'string' or type(v) == 'boolean' then
                local buf = tostring(v) -- Convert the initial value to string
                local flags = ImGuiInputTextFlags.EnterReturnsTrue
                local valueChanged, newValue = ImGui.InputText('##' .. k, buf, flags)
                if newValue then
                    -- Check if the edited value is a number
                    local num = tonumber(valueChanged)
                    local string = valueChanged
                    if num then
                        table[k] = num
                    elseif string == 'true' then
                        table[k] = true
                    elseif string == 'false' then
                        table[k] = false
                    else
                        -- If it's not a number or 'true'/'false', keep it as a string
                        table[k] = string
                    end
                end
                ImGui.TableNextColumn()
            end
        end
    end
end

local function drawOrderedNestedTableTree(table, order)
    for k, v in ipairs(order) do
        --ImGui.SetNextItemOpen(true, ImGuiCond.FirstUseEver)
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        if v == 'ah' or v == 'ab' or v == 'ad' or v == 'ac' or v == 'ae' then
            if v == 'ah' then section = 'heal' end
            if v == 'ab' then section = 'buff' end
            if v == 'ad' then section = 'debuff' end
            if v == 'ac' then section = 'cure' end
            if v == 'ae' then section = 'event' end
            if myconfig[section] and myconfig[section].count ~= nil then
                for i = 1, myconfig[section]['count'] do
                    value = table[v .. i]
                    if type(value) == "table" then
                        local open = ImGui.TreeNodeEx(tostring(v .. i), ImGuiTreeNodeFlags.SpanFullWidth)
                        if open then
                            drawOrderedNestedTableTree(value, subOrder[v])
                            ImGui.TreePop()
                        end
                    end
                end
            end
        elseif type(table[v]) == 'table' then
            local open = ImGui.TreeNodeEx(tostring(v), ImGuiTreeNodeFlags.SpanFullWidth)
            if open then
                drawOrderedNestedTableTree(table[v], subOrder[v])
                ImGui.TreePop()
            end
        else
            ImGui.TextColored(YELLOW, '%s', v)
            ImGui.TableNextColumn()
            ImGui.TextColored(RED, '%s', table[v])
            ImGui.TableNextColumn()
            -- Create an input text field with a unique ID using the key
            if type(table[v]) == 'number' or type(table[v]) == 'string' or type(table[v]) == 'boolean' then
                local buf = tostring(table[v]) -- Convert the initial value to string
                local flags = ImGuiInputTextFlags.EnterReturnsTrue
                local valueChanged, newValue = ImGui.InputText('##' .. v, buf, flags)
                if newValue then
                    -- Check if the edited value is a number
                    local num = tonumber(valueChanged)
                    local string = valueChanged
                    if num then
                        table[v] = num
                    elseif string == 'true' then
                        table[v] = true
                    elseif string == 'false' then
                        table[v] = false
                    else
                        -- If it's not a number or 'true'/'false', keep it as a string
                        table[v] = string
                    end
                    if myconfig.settings['domelee'] then trotsmelee.LoadMeleeConfig() end
                    if myconfig.settings['dopull'] then trotspull.LoadPullConfig() end
                    if myconfig.settings['doheal'] then trotsheal.LoadHealConfig() end
                    if myconfig.settings['dobuff'] then trotsbuff.LoadBuffConfig() end
                    if myconfig.settings['dodebuff'] then trotsdebuff.LoadDebuffConfig() end
                    if myconfig.settings['docure'] then trotscure.LoadCureConfig() end
                    if myconfig.settings['doevent'] then trotsevent.LoadEventConfig() end
                end
                ImGui.TableNextColumn()
            end
        end
    end
end

local function drawTableTree(t, a, order)
    ImGui.SetNextItemOpen(true, ImGuiCond.FirstUseEver)
    if ImGui.TreeNode(a) then
        if ImGui.BeginTable('state table', 3, TABLE_FLAGS, -1, -1) then
            ImGui.TableSetupScrollFreeze(0, 1)
            ImGui.TableSetupColumn('Key', ImGuiTableColumnFlags.DefaultSort, 2, 1)
            ImGui.TableSetupColumn('Value', ImGuiTableColumnFlags.DefaultSort, 2, 2)
            ImGui.TableSetupColumn('Edit', ImGuiTableColumnFlags.DefaultSort, 2, 3)
            ImGui.TableHeadersRow()
            if not order then drawNestedTableTree(t) else drawOrderedNestedTableTree(t, order) end
            -- Retrieve the sort specs
            local sortSpecs = ImGui.TableGetSortSpecs()

            -- Sort the keys alphabetically if needed
            if sortSpecs then
                table.sort(t, function(a, b)
                    return a < b
                end)
            end
            ImGui.EndTable()
        end
        ImGui.TreePop()
    end
end

local function updateImGui()
    -- Don't draw the UI if the UI was closed by pressing the X button
    if not isOpen then return end
    if not tbgui then return end
    local window_settings = {
        x = 200, -- Default X position
        y = 200, -- Default Y position
        w = 600, -- Default width
        h = 800, -- Default height
        collapsed = false
    }

    -- Set defaults before Begin
    ImGui.SetNextWindowPos(ImVec2(window_settings.x, window_settings.y), ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowSize(ImVec2(window_settings.w, window_settings.h), ImGuiCond.FirstUseEver)
    -- isOpen will be set false if the X button is pressed on the window
    -- shouldDraw will generally always be true unless the window is collapsed
    isOpen, shouldDraw = ImGui.Begin(path, isOpen)
    -- Only draw the window contents if shouldDraw is true
    if shouldDraw then
        if ImGui.BeginTabBar('TrotsBot GUI') then
            if ImGui.BeginTabItem('Config') then
                if ImGui.Button('End Trotsbot') then
                    terminate = true
                end
                ImGui.SameLine()
                if ImGui.Button('Save Ini') then
                    writeConfigToFile(myconfig, path, keyOrder)
                    if myconfig.settings['domelee'] then trotsmelee.LoadMeleeConfig() end
                    if myconfig.settings['dopull'] then trotspull.LoadPullConfig() end
                    if myconfig.settings['doheal'] then trotsheal.LoadHealConfig() end
                    if myconfig.settings['dobuff'] then trotsbuff.LoadBuffConfig() end
                    if myconfig.settings['dodebuff'] then trotsdebuff.LoadDebuffConfig() end
                    if myconfig.settings['docure'] then trotscure.LoadCureConfig() end
                    if myconfig.settings['doevent'] then trotsevent.LoadEventConfig() end
                end
                ImGui.SameLine()
                if ImGui.Button('Save Common') then
                    ProcessExcludeList('save')
                end
                ImGui.SameLine()
                if ImGui.Button('Open Ini') then
                    os.execute('start "" "' .. path .. '"')
                end
                drawTableTree(myconfig, 'ini', keyOrder)
                ImGui.EndTabItem()
            end
            if ImGui.BeginTabItem('Debug') then
                ImGui.Text('Debug area, these are running variables in trotbot, editting these may cause crashes!')
                drawTableTree(runconfig, 'running')
                ImGui.EndTabItem()
            end
            ImGui.EndTabBar()
        end
    end
    -- Always call ImGui.End if begin was called
    ImGui.End()
end

local function UIEnable()
    isOpen = true
    tbgui = true
end

function trotslib.isInList(value, list)
    for _, v in ipairs(list) do
        if value == v then
            return true
        end
    end
    return false
end

function trotslib.StartUp(...)
    print('Trotsbot LUA is starting! (v6.28)')
    math.randomseed(os.time() * 1000 + os.clock() * 1000)
    if mq.TLO.Me.Hovering() or string.find(mq.TLO.Me.Name(), 'corpse') then
        mq.cmd('/dgt \ayTrotsbot:\axCan\'t start TrotsBot cause I\'m hovering over my corpse!')
        terminate = true
        return
    end
    -- verify mq2 and plugin requirements are met
    if mq.TLO.Alias('/tb')() then
        print('Trotsbot Startup: Old /tb mq alias detected, deleting this as it is no longer required for TrotsBot LUA')
        mq.cmd('/squelch /alias /tb delete')
    end
    if (mq.TLO.Plugin('MQ2DanNet').IsLoaded() == nil) then
        mq.cmd('/squelch /plugin MQ2DanNet load')
    end
    if (mq.TLO.Plugin('MQ2Cast').IsLoaded() == nil) then
        mq.cmd('/squelch /plugin MQ2Cast load')
    end
    if (mq.TLO.Plugin('MQ2Exchange').IsLoaded() == nil) then
        mq.cmd('/squelch /plugin MQ2Exchange load')
    end
    if (mq.TLO.Plugin('MQ2MoveUtils').IsLoaded() == nil) then
        mq.cmd('/squelch /plugin MQ2MoveUtils load')
    end
    if (not mq.TLO.Plugin('MQ2NetBots').IsLoaded()) then
        mq.cmd('/squelch /plugin MQ2NetBots load')
    end
    if (not mq.TLO.Plugin('MQ2Cast').IsLoaded()) then
        mq.cmd('/squelch /plugin MQ2Cast load')
    end
    if not (mq.TLO.NetBots.Enable() and mq.TLO.NetBots.Listen() and mq.TLO.NetBots.Output() and mq.TLO.NetBots(mq.TLO.Me.Name()).MaxEndurance()) then
        mq.cmd(
        '/multiline ; /dgt Trotsbot Startup: \agNetbots\ag is not fully enabled, enabling it ; /netbots on grab=on send=on ext=on')
    end
    --load config file
    runconfig = {}
    runconfig['ScriptList'] = {}
    IniFile = 'TB_' .. mq.TLO.Me.Name()
    keyOrder = { 'settings', 'pull', 'melee', 'heal', 'buff', 'debuff', 'cure', 'event', 'ah', 'ab', 'ad', 'ac', 'ae',
        'script' }                                                                                                                -- Add the keys in the order you want them to be saved
    -- The sub-order for nested tables, if needed
    subOrder = {
        settings = { 'dodebuff', 'doheal', 'dobuff', 'docure', 'doevent', 'domelee', 'dopull', 'doraid', 'dodrag', 'domount', 'mountcast', 'dosit', 'sitmana', 'sitendur', 'TankName', 'TargetFilter', 'masterlist', 'petassist', 'acleash', 'zradius' },
        pull = { 'pullability', 'abilityrange', 'radius', 'zrange', 'maxlevel', 'minlevel', 'chainpullhp', 'chainpullcnt', 'mana', 'manaclass', 'leash', 'usepriority', 'hunter' },
        melee = { 'assistpct', 'stickcmd', 'offtank', 'minmana', 'otoffset' },
        heal = { 'count', 'rezoffset', 'interruptlevel', 'xttargets' },
        buff = { 'count' },
        debuff = { 'count' },
        cure = { 'count', 'prioritycure' },
        event = { 'count' },
        ah = { 'gem', 'spell', 'alias', 'announce', 'minmana', 'tarcnt', 'class', 'priority', 'precondition' },
        ab = { 'gem', 'spell', 'alias', 'announce', 'minmana', 'tarcnt', 'class', 'spellicon', 'precondition' },
        ad = { 'gem', 'spell', 'alias', 'announce', 'minmana', 'tarcnt', 'tartype', 'beghp', 'endhp', 'recast', 'delay', 'precondition' },
        ac = { 'gem', 'spell', 'alias', 'announce', 'minmana', 'curetype', 'tarcnt', 'class', 'priority', 'precondition' },
        ae = { 'gem', 'spell', 'alias', 'announce', 'minmana', 'minhp', 'minendur', 'maxmana', 'maxhp', 'maxendur', 'tarcnt', 'class', 'precondition' },
        script = {}
    }
    runconfig['SubOrder'] = {}
    for k, v in ipairs(runconfig['ScriptList']) do
        runconfig['SubOrder'][v] = myconfig['script'][v]
    end
    runconfig['zonename'] = mq.TLO.Zone.ShortName()
    runconfig['acmatarget'] = nil
    runconfig['AlertList'] = 20
    runconfig['followid'] = 0
    runconfig['followname'] = ''
    trotslib.LoadConfig(...)
    if not comkeytable then comkeytable = {} end
    if comkeytable['excludelist'] and comkeytable.excludelist[mq.TLO.Zone.ShortName()] then
        runconfig['ExcludeList'] = comkeytable.excludelist[mq.TLO.Zone.ShortName()]
    else
        runconfig['ExcludeList'] = ''
    end
    if comkeytable['prioritylist'] and comkeytable.prioritylist[mq.TLO.Zone.ShortName()] then
        runconfig['PriorityList'] = comkeytable.prioritylist[mq.TLO.Zone.ShortName()]
    else
        runconfig['PriorityList'] = ''
    end
    if not comkeytable.raidlist then comkeytable.raidlist = {} end
    runconfig['MobList'] = {}
    runconfig['MobCount'] = 0
    DoYell = false
    DoYellTimer = 0
    runconfig['engagetracker'] = {}
    FTEList = {}
    FTECount = 0
    CurSpell = {}
    gemInUse = {}
    HoverTimer = 0
    DragHack = false
    HoverEchoTimer = 0
    SpellTimer = 0
    interruptCounter = {}
    PreCH = {}
    gmtimer = 0
    MyPetID = nil
    EquipGear = false
    IgnoreMobBuff = false
    YellTimer = 0
    MissedNote = false
    if mq.TLO.EverQuest.Server() == 'Rindiss' then IgnoreMobBuff = true end
    --make sure char isnt doing anything already (stop nav, clear cursor, ect)
    trotslib.CharState('startup')
    mq.imgui.init('debuggui', updateImGui)
    --check startup scripts NTA
    --check each section
    --build variables for enabled sections
    --load tbcommon stuff
end

function BotCheck()
    runconfig['BotList'] = {}
    ---@diagnostic disable-next-line: missing-parameter
    for v in string.gmatch(mq.TLO.NetBots.Client(), "%S+") do
        table.insert(runconfig['BotList'], v)
    end
end

function trotslib.EquipGear(geartoequip)
    local myitem = mq.TLO.FindItem(geartoequip)()
    if not myitem then return false end
    local canuse          = mq.TLO.FindItem(geartoequip).CanUse()
    local toequipitemlink = mq.TLO.FindItem(geartoequip).ItemLink('CLICKABLE')()
    local wornslot        = mq.TLO.FindItem(geartoequip).WornSlot(1)()
    local slotname        = mq.TLO.InvSlot(wornslot).Name()
    local curitemlink     = mq.TLO.Me.Inventory(wornslot).ItemLink('CLICKABLE')() or 'EMPTY'
    if canuse and wornslot then
        mq.cmdf('/dgt \ayTrotsbot:\ax\ayattempting to replace \ar%s\ax with \ag%s\ax in slot %s', curitemlink,
            toequipitemlink, slotname)
    else
        mq.cmdf('/dgt \ayTrotsbot:\ax\ar%s is not equipable by my class/race\ax', toequipitemlink)
        return false
    end

    local function findaugslot(slot)
        local augslots = tonumber(mq.TLO.InvSlot(slot).Item.Augs())
        if tonumber(augslots) then
            for i = 1, augslots do
                local a
                if mq.TLO.InvSlot(slot).Item["AugSlot" .. i]() == augtype then
                    return i
                end
            end
        else
            mq.cmdf('%s has no augslots')
        end
    end

    local augslot = findaugslot(wornslot)

    local function invsearch(itemname)
        if not itemname then return false end
        for packcntr = 1, 10 do
            local packname = mq.TLO.InvSlot("pack" .. packcntr).Item.Name()
            if packname and string.lower(packname) == string.lower(itemname) then return packcntr end
            if mq.TLO.InvSlot("pack" .. packcntr).Item.Container() then
                local packslots = mq.TLO.InvSlot("pack" .. packcntr).Item.Container()
                for slotcntr = 1, packslots do
                    local slotname = mq.TLO.InvSlot("pack" .. packcntr).Item.Item(slotcntr)()
                    if slotname and string.lower(slotname) == string.lower(itemname) then return packcntr, slotcntr end
                end
            end
        end
        return false
    end

    local function equipaugs(slot)
        if mq.TLO.InvSlot(slot).Item.ID() then
            mq.TLO.InvSlot(slot).Item.Inspect()
            local augslots = mq.TLO.InvSlot(slot).Item.Augs()
            mq.delay(100)
            for i = 1, augslots do
                local itemslot, packslot = invsearch(RemovedAugs[i])
                if itemslot then
                    if packslot then
                        mq.cmdf('/itemnotify in pack%s %s leftmouseup', itemslot, packslot)
                    else
                        mq.cmdf('/itemnotify pack%s  leftmouseup', itemslot, packslot)
                    end
                    mq.delay(3000, function() if mq.TLO.Cursor.ID() then return true end end)
                    mq.cmdf('/notify ItemDisplayWindow IDW_Socket_Slot_%s_Item leftmouseup', i)
                    mq.delay(3000, function() if mq.TLO.Window("ConfirmationDialogBox") then return true end end)
                    mq.cmd('/yes')
                    mq.delay(2000, function() if mq.TLO.InvSlot(slot).Item.AugSlot(i)() then return true end end)
                    if mq.TLO.InvSlot(slot).Item.AugSlot(i)() then
                        mq.cmdf("/dgt \ayTrotsbot:\axI've equiped %s in my %s succesfully", RemovedAugs[i], geartoequip)
                    else
                        mq.cmdf("/dgt \ayTrotsbot:\axSomething went wrong equiping %s", RemovedAugs[i])
                    end
                end
            end
        else
            mq.cmdf('/dgt \ayTrotsbot:\axInvalid slot or missing item')
        end
    end

    local function removeaugs(slot)
        local augslots = mq.TLO.InvSlot(slot).Item.Augs()
        local curitem = mq.TLO.InvSlot(slot).Item()
        RemovedAugs = {}
        if augslots and curitem then
            for i = 1, augslots do
                if mq.TLO.InvSlot(slot).Item.AugSlot(i)() then
                    local aug = mq.TLO.InvSlot(slot).Item.AugSlot(i)()
                    if aug then
                        table.insert(RemovedAugs, aug)
                        mq.cmdf("/dgt \ayTrotsbot:\axI have an augment in %s, removing it", curitem)
                        mq.cmdf('/removeaug "%s" "%s"', aug, mq.TLO.InvSlot(slot).Item())
                        mq.delay(3000, function() if mq.TLO.Window("ConfirmationDialogBox") then return true end end)
                        if mq.TLO.Window("ConfirmationDialogBox") then
                            mq.cmd('/yes')
                            mq.delay(3000,
                                function() if (not mq.TLO.InvSlot(slot).Item.AugSlot(augslot)()) and mq.TLO.Cursor.ID() then return true end end)
                            mq.delay(100)
                            mq.cmd('/autoinv')
                        end
                        mq.delay(2000, function() if mq.TLO.InvSlot(slot).Item.AugSlot(i)() then return true end end)
                        if not mq.TLO.InvSlot(slot).Item.AugSlot(i)() then
                            mq.cmdf("/dgt \ayTrotsbot:\axI've removed \ag%s\ax in \ag%s\ax succesfully", RemovedAugs[i],
                                curitem)
                        else
                            mq.cmdf(
                            "/dgt \ayTrotsbot:\ax\arSomething went wrong removing %s from %s most likely need distillers",
                                RemovedAugs[i], curitem)
                        end
                    end
                end
            end
        end
        return augslots
    end

    -- remove augments from existing item

    if wornslot then removeaugs(wornslot) end


    --equip the item

    mq.cmdf('/itemnotify "%s" leftmouseup', geartoequip)
    mq.cmdf('/itemnotify "%s" leftmouseup', wornslot)
    mq.delay(300)
    if mq.TLO.Window("ConfirmationDialogBox")() then mq.cmdf('/yes') end
    mq.cmd('/autoinv')

    --equip the augs back

    equipaugs(wornslot)

    if mq.TLO.Me.Inventory(wornslot)() == geartoequip then
        mq.cmdf('/dgt \ayTrotsbot:\ax\agSuccesfully equiped\ax %s in slot %s', geartoequip, slotname)
    else
        mq.cmdf('/dgt \ayTrotsbot:\ax\arSomething went wrong\ax equiping %s in slot %s', geartoequip, slotname)
    end
end

function trotslib.MountCheck()
    local mountcast = myconfig.settings['mountcast'] or 'none'
    local mount, spelltype = mountcast:match("^%s*(.-)%s*|%s*(.-)%s*$")
    myconfig['mount1'] = { gem = spelltype, spell = mount }
    if not mq.TLO.Me.Mount() and not MountCastFailed then
        trotslib.CastSpell('1', 1, 'mountcast', 'mount')
    end
end

function trotslib.CharState(...)
    local args = { ... }
    local tarname = mq.TLO.Target.Name()
    if args[1] == 'startup' then
        if mq.TLO.Me.Hovering() then
            mq.cmd('/dgt \ayTrotsbot:\axCan\'t start TrotsBot cause I\'m hovering over my corpse!')
            terminate = true
            return
        end
        if (mq.TLO.Me.Moving()) then
            mq.cmd('/multiline ; /nav stop log=off; /stick off)')
        end
        if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
    end
    ---@diagnostic disable-next-line: missing-parameter
    if (mq.TLO.Window('TradeWnd').Open() and not mq.TLO.Window('TradeWnd').MyTradeReady() and not mq.TLO.Cursor.ID()) then
        local tradepartner = 'none'
        local itemintrade = 'none'
        if mq.TLO.Window('TradeWnd').Child('TRDW_OtherName')() and mq.TLO.Window('TradeWnd').Child('TRDW_OtherName')() ~= 0 then
            tradepartner = mq.TLO.Window('TradeWnd').Child('TRDW_OtherName').Text()
        elseif mq.TLO.Window('TradeWnd').Child('TRDW_HisName')() then
            tradepartner = mq.TLO.Window('TradeWnd').Child('TRDW_HisName').Text()
        end
        if (string.find(myconfig.settings['masterlist'], tradepartner) or string.find(mq.TLO.NetBots.Client(), tradepartner)) then
            mq.delay(1000)
            itemintrade = mq.TLO.Window('TradeWnd').Child('TRDW_TradeSlot8').Tooltip()
            while mq.TLO.Window('TradeWnd').Open() do
                mq.cmd('/notify TradeWnd TRDW_Trade_Button leftmouseup')
                mq.delay(500)
            end
        end
        if EquipGear == true and itemintrade then
            mq.delay(1000, function() if mq.TLO.FindItem(itemintrade)() then return true end end)
            trotslib.EquipGear(itemintrade)
        end
    end
    if mq.TLO.Window('LootWnd').Open() then
        mq.cmd('/clean')
    end
    if mq.TLO.Me.Ducking() then
        mq.cmd('/keypress duck')
    end
    if runconfig['campstatus'] and trotslib.calcDist2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), runconfig['makecampx'], runconfig['makecampy']) and trotslib.calcDist2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), runconfig['makecampx'], runconfig['makecampy']) > myconfig.settings['acleash'] then
        trotsmove.MakeCamp('return') end
    if myconfig.settings['dosit'] and not mq.TLO.Me.Sitting() and not mq.TLO.Me.Moving() and mq.TLO.Me.CastTimeLeft() == 0 and not mq.TLO.Me.Combat() and not mq.TLO.Me.AutoFire() then
        local sitcheck = true
        if (tonumber(myconfig.settings['sitmana']) >= mq.TLO.Me.PctMana() and mq.TLO.Me.MaxMana() > 0) or tonumber(myconfig.settings['sitendur']) >= mq.TLO.Me.PctEndurance() then
            if mq.TLO.Me.PctHPs() < 40 and runconfig['MobCount'] > 0 then sitcheck = false end
            if sitcheck then mq.cmd('/squelch /sit on') end
        end
    end
    if (mq.TLO.Cursor.ID() and not OutOfSpace) then
        if mq.TLO.Me.FreeInventory() == 0 then
            mq.cmd('/dgt \ayTrotsbot:\axI\'m out of inventory space!')
            OutOfSpace = true
        else
            mq.cmd('/autoinv')
        end
    end
    if myconfig.settings['domount'] and myconfig.settings['mountcast'] then trotslib.MountCheck() end
    if mq.TLO.Me.State() == 'DEAD' or mq.TLO.Me.State() == 'HOVER' and mq.TLO.Me.Hovering() then
        if not HoverEchoTimer then HoverEchoTimer = mq.gettime() + 300000 end
        if HoverTimer < mq.gettime() then
            Event_Slain()
        end
    end
    if tarname and string.find(tarname, 'corpse') then
        mq.cmd('/squelch /multiline ; /attack off ; /target clear ; /stick off')
    end
    if mq.TLO.Me.State() == 'FEIGN' then
        mq.cmd('/stand')
    end
    if (mq.TLO.Plugin('MQ2Twist').IsLoaded()) then
        if mq.TLO.Twist() and mq.TLO.Twist.Twisting() then mq.cmd('/squelch /twist stop') end
    end
    if not runconfig['acmatarget'] or mq.TLO.Target.ID() ~= runconfig['acmatarget'] then
        if mq.TLO.Me.Combat() then
            mq.cmd('/attack off')
        end
        if ((not runconfig['acmatarget'] or (runconfig['acmatarget'] and mq.TLO.Me.Pet.Target.ID() ~= runconfig['acmatarget'])) and mq.TLO.Me.Pet.Aggressive()) then
            mq.cmd('/squelch /pet back off')
            mq.cmd('/squelch /pet follow')
        end
    end
    if not (runconfig['MobList'][1] and runconfig['acmatarget']) then
        runconfig['acmatarget'] = nil
    end
    if mq.TLO.Plugin('MQ2GMCheck').IsLoaded() then
        if mq.TLO.GMCheck() == 'TRUE' then
            Event_GMDetected()
        end
    end
    if mq.TLO.Me.Pet.ID() and not MyPetID then
        MyPetID = mq.TLO.Me.Pet.ID()
        mq.cmd('/pet leader')
    elseif mq.TLO.Me.Pet.ID() and MyPetID ~= mq.TLO.Me.Pet.ID() then
        MyPetID = mq.TLO.Me.Pet.ID()
        mq.cmd('/pet leader')
    end
end

function trotslib.LoadConfig(...)
    -- attempt to read the config file
    local args = { ... }
    myconfig = {}
    local configData, err = loadfile(path)
    if err then
        -- failed to read the config file, create it using pickle
        print('load failed')
        myconfig = sanitizeConfigFile(path)
        --writeConfigToFile(myconfig, path, keyOrder)
    elseif configData then
        -- file loaded, put content into your config table
        myconfig = configData()
    end
    if not myconfig then
        print('making new config')
        myconfig = {}
    end
    if not myconfig.settings then
        myconfig.settings = {}
    end
    if not myconfig.melee then
        myconfig.melee = {}
    end
    if not myconfig.pull then
        myconfig.pull = {}
    end
    if not myconfig.heal then
        myconfig.heal = {}
    end
    if not myconfig.buff then
        myconfig.buff = {}
    end
    if not myconfig.debuff then
        myconfig.debuff = {}
    end
    if not myconfig.script then
        myconfig.script = {}
    end
    if not myconfig.cure then
        myconfig.cure = {}
    end
    if not myconfig.event then
        myconfig.event = {}
    end
    if args[1] then myconfig.settings['TankName'] = args[1]:sub(1, 1):upper() .. args[1]:sub(2) end
    --validate config tables are all built correctly
    if (myconfig.settings['domelee'] == nil) then myconfig.settings['domelee'] = false end
    if (myconfig.settings['doheal'] == nil) then myconfig.settings['doheal'] = false end
    if (myconfig.settings['dobuff'] == nil) then myconfig.settings['dobuff'] = false end
    if (myconfig.settings['dodebuff'] == nil) then myconfig.settings['dodebuff'] = false end
    if (myconfig.settings['docure'] == nil) then myconfig.settings['docure'] = false end
    if (myconfig.settings['doevent'] == nil) then myconfig.settings['doevent'] = false end
    if (myconfig.settings['dopull'] == nil) then myconfig.settings['dopull'] = false end
    if (myconfig.settings['doraid'] == nil) then myconfig.settings['doraid'] = false end
    if (myconfig.settings['dodrag'] == nil) then myconfig.settings['dodrag'] = false end
    if (myconfig.settings['domount'] == nil) then myconfig.settings['domount'] = false end
    if (myconfig.settings['mountcast'] == nil) then myconfig.settings['mountcast'] = false end
    if (myconfig.settings['dosit'] == nil) then myconfig.settings['dosit'] = true end
    if (myconfig.settings['sitmana'] == nil) then myconfig.settings['sitmana'] = 90 end
    if (myconfig.settings['sitendur'] == nil) then myconfig.settings['sitendur'] = 90 end
    if (myconfig.settings['masterlist'] == nil) then myconfig.settings['masterlist'] = 'netbots' end
    if (myconfig.settings['acleash'] == nil) then myconfig.settings['acleash'] = 75 end
    if (myconfig.settings['zradius'] == nil) then myconfig.settings['zradius'] = 75 end
    if (myconfig.settings['TankName'] == nil) then myconfig.settings['TankName'] = "manual" end
    if (myconfig.settings['TargetFilter'] == nil) then myconfig.settings['TargetFilter'] = '0' end
    if (myconfig.settings['petassist'] == nil) then myconfig.settings['petassist'] = false end
    if (myconfig.settings['spelldb'] == nil) then myconfig.settings['spelldb'] = (tbdir ~= '' and (tbdir .. 'spells.db') or 'spells.db') end
    if myconfig.settings['domelee'] then trotsmelee.LoadMeleeConfig() end
    if myconfig.settings['dopull'] then trotspull.LoadPullConfig() end
    if myconfig.settings['doheal'] then trotsheal.LoadHealConfig() end
    if myconfig.settings['dobuff'] then trotsbuff.LoadBuffConfig() end
    if myconfig.settings['dodebuff'] then trotsdebuff.LoadDebuffConfig() end
    if myconfig.settings['docure'] then trotscure.LoadCureConfig() end
    if myconfig.settings['doevent'] then trotsevent.LoadEventConfig() end
    for k, v in ipairs(runconfig['ScriptList']) do
        runconfig['SubOrder'][v] = v
    end
    for k, v in ipairs(runconfig['ScriptList']) do
        table.insert(subOrder.script, v)
    end
    -- print the contents
    --for k,v in pairs (myconfig.settings) do print(k,v) end
    -- save the config
    writeConfigToFile(myconfig, path, keyOrder)
    -- attempt to load the TBcommon file
    local commonData, errr = loadfile(mq.configDir .. '/' .. 'TBCommon.lua')
    if errr then
        -- failed to read the config file, create it using pickle
        mq.pickle('TBCommon.lua', comkeytable)
    elseif commonData then
        -- file loaded, put content into your config table
        comkeytable = commonData()
        if not comkeytable then comkeytable = {} end
    end
    local immuneData, errr = loadfile(mq.configDir .. '/' .. 'tbimmune.lua')
    if errr then
        -- failed to read the config file, create it using pickle
        mq.pickle('tbimmune.lua', ImmuneList)
        ImmuneList = {}
    elseif immuneData then
        -- file loaded, put content into your config table
        ImmuneList = immuneData()
        if not ImmuneList then ImmuneList = {} end
    end
    if (args[2] == 'makecamp') then
        cmdparse('makecamp', 'on')
    end
    if (args[2] == 'follow') then
        cmdparse('follow', args[1])
    end
end

function trotslib.calcDist3D(x1, y1, z1, x2, y2, z2)
    if x1 and y1 and x2 and y2 and z1 and z2 then return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2 + (z2 - z1) ^ 2) end
end

function trotslib.calcDist2D(x1, y1, x2, y2)
    if x1 and y1 and x2 and y2 then return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) end
end

function trotslib.ImportIni()
    if string.find(mq.TLO.Ini(IniFile)(), 'Settings') then
        print('importing settings from your Ini file to TrotsBot LUA')
        trotslib.LoadINIVar('Settings', 'DoMelee', 'FALSE', 'domelee', IniFile)
        trotslib.LoadINIVar('Settings', 'DoBuffs', 'FALSE', 'dobuff', IniFile)
        trotslib.LoadINIVar('Settings', 'DoDebuffs', 'FALSE', 'dodebuff', IniFile)
        trotslib.LoadINIVar('Settings', 'DoHeals', 'FALSE', 'doheal', IniFile)
        trotslib.LoadINIVar('Settings', 'DoPull', 'FALSE', 'dopull', IniFile)
        trotslib.LoadINIVar('Settings', 'DoSit', 'FALSE', 'dosit', IniFile)
        trotslib.LoadINIVar('Settings', 'MasterList', 'netbots', 'masterlist', IniFile)
        trotslib.LoadINIVar('Settings', 'SitManaPct', 90, 'sitmana', IniFile)
        trotslib.LoadINIVar('Settings', 'SitEndurPct', 90, 'sitendur', IniFile)
        trotslib.LoadINIVar('Melee', 'StickCmd', 'hold uw 7', 'stickcmd', IniFile)
        trotslib.LoadINIVar('Melee', 'ACLeash', 75, 'acleash', IniFile)
        trotslib.LoadINIVar('Melee', 'ACAssistPct', 95, 'assistpct', IniFile)
        trotslib.LoadINIVar('Melee', 'OffTank', 0, 'offtank', IniFile)
        trotslib.LoadINIVar('Melee', 'OTOffSet', 95, 'otoffset', IniFile)
        trotslib.LoadINIVar('AdvHeal', 'AHCount', 2, 'count', IniFile)
        trotslib.LoadINIVar('AdvHeal', 'RezOffSet', 0, 'rezoffset', IniFile)
        trotslib.LoadINIVar('AdvBuff', 'ABCount', 2, 'count', IniFile)
        trotslib.LoadINIVar('AdvDebuff', 'ADCount', 2, 'count', IniFile)
        trotslib.LoadINIVar('AdvPull', 'APPullAbility', 400, 'pullability', IniFile)
        trotslib.LoadINIVar('AdvPull', 'PullAbilityRange', 400, 'abilityrange', IniFile)
        trotslib.LoadINIVar('AdvPull', 'APRadius', 400, 'radius', IniFile)
        trotslib.LoadINIVar('AdvPull', 'APMaxZRange', 400, 'zrange', IniFile)
        trotslib.LoadINIVar('AdvPull', 'APPullMaxLevel', 400, 'maxlevel', IniFile)
        trotslib.LoadINIVar('AdvPull', 'APPullMinLevel', 400, 'minlevel', IniFile)
        trotslib.LoadINIVar('AdvPull', 'HealMana', 400, 'mana', IniFile)
        trotslib.LoadINIVar('AdvPull', 'HealManaClass', 400, 'manaclass', IniFile)
        trotslib.LoadINIVar('AdvPull', 'APMobLeash', 400, 'leash', IniFile)
        trotslib.LoadINIVar('AdvPull', 'PriorityPull', 400, 'usepriority', IniFile)
        trotslib.LoadINIVar('AdvPull', 'HunterMode', 400, 'hunter', IniFile)
        if myconfig.debuff.count and myconfig.debuff.count > 0 then
            for i = 1, myconfig.debuff.count do
                trotslib.LoadINIVar('AD' .. i, 'Gem', 0, 'gem', IniFile)
                trotslib.LoadINIVar('AD' .. i, 'Spell', 0, 'spell', IniFile)
                trotslib.LoadINIVar('AD' .. i, 'SpellAlias', "", 'alias', IniFile)
                trotslib.LoadINIVar('AD' .. i, 'Announce', "", 'announce', IniFile)
                trotslib.LoadINIVar('AD' .. i, 'SpellMinMana', 0, 'minmana', IniFile)
                trotslib.LoadINIVar('AD' .. i, 'TarCnt', 0, 'tarcnt', IniFile)
                trotslib.LoadINIVar('AD' .. i, 'TarType', 0, 'tartype', IniFile)
                trotslib.LoadINIVar('AD' .. i, 'TarBegHP', 0, 'beghp', IniFile)
                trotslib.LoadINIVar('AD' .. i, 'TarEndHP', 0, 'endhp', IniFile)
                trotslib.LoadINIVar('AD' .. i, 'SpellRecast', 0, 'recast', IniFile)
                trotslib.LoadINIVar('AD' .. i, 'PreCondReset', true, 'precondition', IniFile)
            end
        end
        if myconfig.buff.count and myconfig.buff.count > 0 then
            for i = 1, myconfig.buff.count do
                trotslib.LoadINIVar('AB' .. i, 'Gem', 0, 'gem', IniFile)
                trotslib.LoadINIVar('AB' .. i, 'Spell', 0, 'spell', IniFile)
                trotslib.LoadINIVar('AB' .. i, 'SpellAlias', "", 'alias', IniFile)
                trotslib.LoadINIVar('AB' .. i, 'Announce', "", 'announce', IniFile)
                trotslib.LoadINIVar('AB' .. i, 'SpellMinMana', 0, 'minmana', IniFile)
                trotslib.LoadINIVar('AB' .. i, 'TarCnt', 0, 'tarcnt', IniFile)
                trotslib.LoadINIVar('AB' .. i, 'TarType',
                    'war brd clr pal shd shm rng rog ber mnk dru bst mag nec enc wiz', 'class', IniFile)
                trotslib.LoadINIVar('AB' .. i, 'SpellIcon', 0, 'spellicon', IniFile)
                trotslib.LoadINIVar('AB' .. i, 'SpellRecast', 0, 'recast', IniFile)
                trotslib.LoadINIVar('AB' .. i, 'PreCondReset', true, 'precondition', IniFile)
            end
        end
        if myconfig.heal.count and myconfig.heal.count > 0 then
            for i = 1, myconfig.heal.count do
                trotslib.LoadINIVar('AH' .. i, 'Gem', 0, 'gem', IniFile)
                trotslib.LoadINIVar('AH' .. i, 'Spell', 0, 'spell', IniFile)
                trotslib.LoadINIVar('AH' .. i, 'SpellAlias', "", 'alias', IniFile)
                trotslib.LoadINIVar('AH' .. i, 'Announce', "", 'announce', IniFile)
                trotslib.LoadINIVar('AH' .. i, 'SpellMinMana', 0, 'minmana', IniFile)
                trotslib.LoadINIVar('AH' .. i, 'TarCnt', 0, 'tarcnt', IniFile)
                trotslib.LoadINIVar('AH' .. i, 'Class', 'war brd clr pal shd shm rng rog ber mnk dru bst mag nec enc wiz',
                    'class', IniFile)
                trotslib.LoadINIVar('AH' .. i, 'PreCondReset', true, 'precondition', IniFile)
            end
        end
        writeConfigToFile(myconfig, path, keyOrder)
        trotslib.LoadConfig()
    end
end

function trotslib.ImportCom()
    if string.find(mq.TLO.Ini('TBCommon')(), 'Settings') then
        print('importing settings from your CommonFile file to TrotsBot LUA')
        excludelistimp = string.lower(mq.TLO.Ini('TBCommon', 'ExcludeList')())
        comkeytable = {}
        comkeytable.excludelist = {}
        comkeytable.prioritylist = {}
        for exvalue in string.gmatch(tostring(excludelistimp), "([^|]+)") do
            if (exvalue) then
                comkeytable.excludelist[tostring(exvalue)] = mq.TLO.Ini('TBCommon', 'ExcludeList', string.lower(exvalue))()
                --print('inserting '..exvalue)
            end
        end
        table.sort(comkeytable.excludelist)
        prioritylistimp = string.lower(mq.TLO.Ini('TBCommon', 'PriorityList')())
        for prvalue in string.gmatch(tostring(prioritylistimp), "([^|]+)") do
            if (prvalue) then
                comkeytable.prioritylist[tostring(prvalue)] = mq.TLO.Ini('TBCommon', 'PriorityList',
                    string.lower(prvalue))()
                --print('inserting '..prvalue)
            end
        end
        table.sort(comkeytable)
        mq.pickle('tbcommon.lua', comkeytable)
        if comkeytable['excludelist'] and comkeytable.excludelist[mq.TLO.Zone.ShortName()] then
            runconfig['ExcludeList'] = comkeytable.excludelist[mq.TLO.Zone.ShortName()]
        else
            runconfig['ExcludeList'] = ''
        end
    end
end

function trotslib.LoadINIVar(IniSection, IniVar, IniValue, MacroVar, MyIni)
    local IniString = mq.TLO.Ini(MyIni, IniSection, IniVar, 'NOTFOUND')()
    if IniString == 'TRUE' then
        IniString = true
    end
    if IniString == 'FALSE' then
        IniString = false
    end
    IniValue = tostring(IniValue)
    IniValue = string.lower(IniValue)
    local MacroVar = string.lower(MacroVar)
    if IniSection == 'AdvDebuff' then IniSection = 'debuff' end
    if IniSection == 'AdvBuff' then IniSection = 'buff' end
    if IniSection == 'AdvHeal' then IniSection = 'heal' end
    if IniSection == 'AdvPull' then IniSection = 'pull' end
    print(MacroVar .. ' is ' .. tostring(IniString) .. ' in section ' .. string.lower(IniSection))
    if (IniString == "NOTFOUND") then
        if IniValue == 'dodebuffs' then IniValue = 'dodebuff' end
        if IniValue == 'doheals' then IniValue = 'doheal' end
        if IniValue == 'dobuffs' then IniValue = 'dobuff' end
        if IniValue == 'doevents' then Inivalue = 'doevent' end
        if IniValue == 'docures' then IniValue = 'docure' end
        if not myconfig[string.lower(IniSection)] then myconfig[string.lower(IniSection)] = {} end
        myconfig[string.lower(IniSection)][MacroVar] = IniValue
        print(MacroVar .. ' not found in ini, saving as default value ' .. myconfig[string.lower(IniSection)][MacroVar])
    else
        if not myconfig[string.lower(IniSection)] then myconfig[string.lower(IniSection)] = {} end
        if tonumber(IniString) then
            myconfig[string.lower(IniSection)][MacroVar] = tonumber(IniString)
        elseif type(IniString) == 'string' and string.lower(IniString) == "null" then
            IniString = 0
        else
            if not myconfig[string.lower(IniSection)] then myconfig[string.lower(IniSection)] = {} end
            myconfig[string.lower(IniSection)][MacroVar] = IniString
        end
        print('saved variable' .. MacroVar .. ' as ', myconfig[string.lower(IniSection)][MacroVar])
    end
end

--cleans ADMobList
function CleanMobList()
    DebuffList = {}
end

function trotslib.MakeObs(obsname, bot, query)
    if obsname and query and bot then
        if not mq.TLO.DanNet(bot).ObserveSet(query)() then
            mq.cmdf('/dobserve %s -q %s', bot, query)
            mq.delay(2000, function() return mq.TLO.DanNet(bot).Observe(query).Received() end)
        end
        _G[obsname] = mq.TLO.DanNet(bot).O(query)()
    end
end

function trotslib.DropObs()
    local peercnt = mq.TLO.DanNet.PeerCount()
    for peeriter = 1, peercnt do
        local obscnt = mq.TLO.DanNet(mq.TLO.DanNet.Peers(peeriter)).ObserveCount() or 0
        if obscnt and obscnt > 0 then
            mq.cmdf('/dobs %s -drop', mq.TLO.DanNet.Peers(peeriter)())
            --printf('dropping obs for %s', peer)
        end
    end
end

function trotslib.DragCheck()
    if debug then print('drag call') end
    CorpseID = nil
    local DragOn = false
    DragDist = 1500
    if not mq.TLO.Spawn(CorpseID).ID() then CorpseID = nil end
    local botstr = mq.TLO.NetBots.Client()
    local bots = {}
    for bot in botstr:gmatch("%S+") do
        table.insert(bots, bot)
    end
    for cor = 1, mq.TLO.NetBots.Counts() do
        local bot = mq.TLO.NetBots(bots[cor]).Name()
        local corpse = nil
        local corpsedist = nil
        -- group and raid condition removed and (mq.TLO.Group.Member(bot).ID() or mq.TLO.Raid.Member((bot)).ID())
        if bot then
            corpse = mq.TLO.Spawn(bot .. "'s corpse").Type()
            corpsedist = mq.TLO.Spawn(bot .. "'s corpse").Distance()
        end
        if debug then print(bot, corpse) end
        if (corpse == 'Corpse' and corpsedist > 10 and corpsedist < DragDist) then
            CorpseID = mq.TLO.Spawn(bot .. "'s corpse").ID()
            break
        end
    end
    if not CorpseID then return false end
    if debug then print('CorpseID is ' .. CorpseID) end
    if (DragHack and CorpseID) then
        mq.cmdf('/tar id %s', CorpseID)
        mq.delay(1000, function() if mq.TLO.Target.ID() == CorpseID then return true end end)
        mq.cmd('/sumcorpse')
    end
    if (CorpseID and mq.TLO.Navigation.PathExists('id ' .. CorpseID)()) then
        DragOn = true
        mq.cmd('/multiline ; /target clear ; /hidec all')
        mq.delay(2000)
        mq.cmd('/hidec none')
        mq.delay(1000)
        mq.cmd('/hidec alwaysnpc')
        mq.cmdf('/multiline ; /attack off ; /stick off ; /tar id %s', CorpseID)
        while ((mq.TLO.Me.Class.ShortName() == 'ROG') and not mq.TLO.Me.Invis() or (mq.TLO.Me.Class.ShortName() == 'ROG' and not mq.TLO.Me.Sneaking())) do
            mq.delay(100)
            if not mq.TLO.Me.Sneaking() then mq.cmd('/squelch /doability sneak') end
            if mq.TLO.Me.AbilityReady("Hide")() then mq.cmd('/squelch /doability hide') end
        end
        mq.delay(2000)
        mq.cmdf('/nav id %s', CorpseID)
        while (mq.TLO.Target.Type() == 'Corpse' and mq.TLO.Navigation.Active()) do
            mq.delay(100)
            mq.doevents()
            local corpsedist = mq.TLO.Spawn(CorpseID).Distance3D()
            if (CorpseID and mq.TLO.Spawn(CorpseID).ID() and corpsedist and corpsedist < 90) then
                mq.cmd('/multiline ; /corpsedrag ; /nav stop')
                DragOn = false
                CorpseID = nil
            end
        end
    end
end

--rebuilds exclude list
function ProcessExcludeList(command)
    if command then
        if command == 'save' then
            if not comkeytable.excludelist then comkeytable.excludelist = {} end
            comkeytable.excludelist[mq.TLO.Zone.ShortName()] = runconfig['ExcludeList']
            local function sort_alphabetical(a, b)
                return a:lower() < b:lower()
            end
            table.sort(comkeytable.excludelist, sort_alphabetical)
            for key in pairs(comkeytable.excludelist) do
            end
            mq.pickle('tbcommon.lua', comkeytable)
        elseif command == 'zone' then
            mq.cmdf('/squelch /alert clear %s', runconfig['AlertList'])
            if comkeytable.excludelist and comkeytable.excludelist[mq.TLO.Zone.ShortName()] then
                runconfig['ExcludeList'] = comkeytable.excludelist[mq.TLO.Zone.ShortName()]
            else
                runconfig['ExcludeList'] = ''
            end
        end
    end
end

function ProcessPriorityList(command)
    if command then
        if command == 'save' then
            comkeytable.prioritylist[mq.TLO.Zone.ShortName()] = runconfig['PriorityList']
            local function sort_alphabetical(a, b)
                return a:lower() < b:lower()
            end
            table.sort(comkeytable.prioritylist, sort_alphabetical)
            for key in pairs(comkeytable.prioritylist) do
            end
            mq.pickle('tbcommon.lua', comkeytable)
        elseif command == 'zone' then
            if not comkeytable.prioritylist then comkeytable.prioritylist = {} end
            runconfig['PriorityList'] = comkeytable.prioritylist[mq.TLO.Zone.ShortName()]
        end
    end
end

function ProcessImmuneList(immuneID)
    local spell = mq.TLO.Spell(myconfig[CurSpell.sub .. CurSpell.spell].spell)()
    local zone = mq.TLO.Zone.ShortName()
    if immuneID and spell and mq.TLO.Spawn(immuneID).ID() and mq.TLO.Spawn(immuneID).Type() ~= 'Corpse' then
        if not ImmuneList[spell] then ImmuneList[spell] = {} end
        if not ImmuneList[spell][zone] then ImmuneList[spell][zone] = {} end
        if not ImmuneList[spell][zone][mq.TLO.Spawn(immuneID).CleanName()] then
            ImmuneList[spell][zone][mq.TLO.Spawn(immuneID).CleanName()] = true
            mq.cmdf('/dgt \ayTrotsbot:\ax%s is \\arIMMUNE\\ax to spell \\ag%s\\ax, adding to the ImmuneList',
                mq.TLO.Spawn(immuneID).CleanName(), spell)
            mq.pickle('tbimmune.lua', ImmuneList)
        end
    end
end

--function to reset zone specific variables
function DelayOnZone()
    runconfig['zonename'] = mq.TLO.Zone.ShortName()
    if runconfig['campstatus'] == true then
        runconfig['makecampx'] = nil
        runconfig['makecampy'] = nil
        runconfig['makecampz'] = nil
    end
    runconfig['campstatus'] = false
    if myconfig.settings['dopull'] == true then myconfig.settings['dopull'] = false end
    if runconfig['acmatarget'] then runconfig['acmatarget'] = nil end
    if APTarget then APTarget = nil end
    ProcessExcludeList('zone')
    ProcessPriorityList('zone')
    CleanMobList()
    trotslib.DropObs()
    MountCastFailed = false
end

function trotslib.IgnoreCheck()
    --print('build check for doyell array')
    return true
end

-- checks spell is loaded, minmana is met, and gem is ready, precondition is good
function trotslib.SpellCheck(Sub, ID)
    local spell = nil
    local minmana = nil
    local gem = nil
    local spellreg = mq.TLO.Spell(spell).ReagentID(1)()
    local entry = myconfig[Sub .. ID]
    if gem ~= "item" and entry and type(entry.alias) == 'string' and trotsdb and trotsdb.resolve_entry then
        local level = tonumber(mq.TLO.Me.Level()) or 1
        if (not entry.spell or entry.spell == 0 or entry.spell == '0' or entry._resolved_level ~= level) then
            trotsdb.resolve_entry(Sub, ID, false)
        end
    end
    if myconfig[Sub .. ID] and myconfig[Sub .. ID].spell then spell = myconfig[Sub .. ID].spell end
    if myconfig[Sub .. ID] and myconfig[Sub .. ID].minmana then minmana = myconfig[Sub .. ID].minmana end
    if myconfig[Sub .. ID] and myconfig[Sub .. ID].gem then gem = myconfig[Sub .. ID].gem end
    --check gemInUse (prevents spells fighting over the same gem)
    --spell
    if mq.TLO.Window('SpellBookWnd').Open() then mq.cmd('/book') end
    if spellreg and spellreg > 0 and not mq.TLO.FindItem(spellreg)() then
        myconfig[Sub .. ID].tarcnt = 0
        mq.cmdf('/dgt \ayTrotsbot:\axMissing reagent for %s, disabling spell', spell)
        return false
    end
    local spellmana = mq.TLO.Spell(spell).Mana()
    local spellend = mq.TLO.Spell(spell).EnduranceCost()
    if not ((tonumber(gem) and gem <= 13 and gem > 0) or gem == 'alt' or gem == 'item' or gem == 'script' or gem == 'disc' or gem == 'ability') then return false end
    if (tonumber(gem) or gem == 'alt') and spellmana then
        if (mq.TLO.Spell(spell).Mana() and mq.TLO.Spell(spell).Mana() > 0 and ((mq.TLO.Me.CurrentMana() - (mq.TLO.Me.ManaRegen() * 2)) < mq.TLO.Spell(spell).Mana()) or (mq.TLO.Me.PctMana() < minmana)) then return false end
    end
    if gem == 'alt' then
        if not mq.TLO.Me.AltAbilityReady(spell) then return false end
    end
    if gem == 'disc' and spellend then
        if not mq.TLO.Me.CombatAbilityReady(spell) then return false end
        if (mq.TLO.Spell(spell).EnduranceCost() and ((mq.TLO.Me.CurrentEndurance() - (mq.TLO.Me.EnduranceRegen() * 2)) < mq.TLO.Spell(spell).EnduranceCost()) or (mq.TLO.Me.PctMana() < minmana)) then return false end
    end
    return true
end

--Immune check
function trotslib.ImmuneCheck(Sub, ID, EvalID)
    --print('immunecheck')
    local spell = mq.TLO.Spell(myconfig[Sub .. ID].spell)()
    local zone = mq.TLO.Zone.ShortName()
    local targetname = mq.TLO.Spawn(EvalID).CleanName()
    if ImmuneList[spell] and ImmuneList[spell][zone] and ImmuneList[spell][zone][targetname] then return false else return true end
end

--Check Distance
function trotslib.DistanceCheck(Sub, ID, EvalID)
    local spell = nil
    local spellid = nil
    local myrange = nil
    if myconfig[Sub .. ID] then
        local entry = myconfig[Sub .. ID]
        --if type(entry.alias) == 'string' and trotsdb and trotsdb.resolve_entry then
        --local level = tonumber(mq.TLO.Me.Level()) or 1
        --if (not entry.spell or entry.spell == 0 or entry.spell == '0' or entry._resolved_level ~= level) then
        --trotsdb.resolve_entry(Sub, ID, false)
        --end
        --end
        if entry.spell then spell = entry.spell end
    end
    local tardist = mq.TLO.Spawn(EvalID).Distance()
    if spell then myrange = mq.TLO.Spell(spell).MyRange() end
    if not spell then return false end
    if myconfig[Sub .. ID] then
        spell = myconfig[Sub .. ID].spell
    else
        spell = Sub
    end
    if mq.TLO.Spell(spell).AERange() and mq.TLO.Spell(spell).AERange() > 0 and mq.TLO.Spawn(EvalID).Distance() <= mq.TLO.Spell(spell).AERange() then
        return true
    elseif tardist and myrange and tardist <= myrange then
        return true
    else
        return false
    end
end

--Check HP
--Check Mana
--Check Endur

-- precondition check
function trotslib.PreCondCheck(Sub, ID, spawnID)
    --print('precond')
    local precond = myconfig[Sub .. ID].precondition
    EvalID = spawnID
    if type(myconfig[Sub .. ID].precondition) == 'string' then
        local loadprecond, loadError = load('local mq = require("mq") ' .. precond)
        if loadprecond then
            local env = { EvalID = EvalID }
            setmetatable(env, { __index = _G })
            local output = loadprecond()
            return output
        else
            print('problem loading precond')
        end
    elseif type(myconfig[Sub .. ID].precondition) == 'boolean' then
        if myconfig[Sub .. ID].precondition then return true end
    end
    EvalID = nil
end

--checks if a precondition is valid
function trotslib.ProcessScript(script, Sub, ID)
    --print('precond')
    if myconfig['script'] and type(myconfig.script[script]) == 'string' then
        local loadprecond, loadError = load('local mq = require("mq") ' .. myconfig['script'][script])
        if loadprecond then
            return true
        else
            print('problem loading precond')
            myconfig[Sub .. ID].tarcnt = 0
            return false
        end
    elseif type(myconfig[script]) == 'boolean' then
        if myconfig[script] then return true end
    end
end

--runs script
function trotslib.RunScript(script, Sub, ID)
    --print('precond')
    if myconfig['script'] and type(myconfig['script'][script]) == 'string' then
        local loadprecond, loadError = load('local mq = require("mq") ' .. myconfig['script'][script])
        if loadprecond then
            local output = loadprecond()
            return output
        else
            print('problem loading precond')
            myconfig[Sub .. ID].tarcnt = 0
            return false
        end
    elseif type(myconfig[script]) == 'boolean' then
        if myconfig[script] then return true end
    end
end

function trotslib.LoadSpell(Sub, ID)
    if debug then print('loadspell') end
    if mq.TLO.Me.Class.ShortName() ~= 'BRD' and mq.TLO.Me.CastTimeLeft() > 0 then
        if debug then printf("waiting for cast to complete before loading %s", myconfig[Sub .. ID].spell) end
        while (mq.TLO.Me.CastTimeLeft() > 0) do
            mq.delay(100)
            trotslib.InterruptCheck()
        end
    end
    local spell = myconfig[Sub .. ID].spell
    local gem = myconfig[Sub .. ID].gem
    -- if gem ready and spell loaded, return true, else run load logic
    if type(gem) == 'number' and mq.TLO.Me.Gem(spell)() == gem and mq.TLO.Me.SpellReady(spell)() then return true end
    if gem == 'item' then
        if mq.TLO.Me.ItemReady(spell)() then
            return true
        else
            return false
        end
    end
    if gem == 'disc' then
        if mq.TLO.Me.CombatAbilityReady(spell)() then return true else return false end
    end
    if gem == 'ability' then
        if debug then print("ability ready?:", mq.TLO.Me.AbilityReady(spell)()) end
        if mq.TLO.Me.AbilityReady(spell)() then return true else return false end
    end
    if gem == 'alt' then
        if mq.TLO.Me.AltAbilityReady(spell)() then return true else return false end
    end
    if gem == 'script' then
        if trotslib.ProcessScript(spell, Sub, ID) then return true else return false end
    end
    --check gemInUse (prevents spells fighting over the same gem)
    if type(gem) == 'number' then
        if gemInUse[gem] then
            if mq.TLO.Me.Gem(gem)() and string.lower(mq.TLO.Me.Gem(gem)()) ~= string.lower(spell) and gemInUse[gem] > mq.gettime() then
                return false
            elseif gemInUse[gem] < mq.gettime() then
                gemInUse[gem] = nil
            end
        end
        -- is gem ready if not and spell loaded, set gemInUse
        -- is spell loaded?
        if mq.TLO.Me.Gem(spell)() ~= gem then
            if mq.TLO.Me.Book(spell)() then
                mq.cmdf('/memspell %s "%s"', gem, spell)

                function gemtest()
                    local curgem = mq.TLO.Me.Gem(gem)()
                    if curgem then curgem = string.lower(curgem) end
                    return curgem == string.lower(spell)
                end

                mq.delay(10000, gemtest)
                gemInUse[gem] = (mq.gettime() + mq.TLO.Spell(spell).RecastTime())
                local timer = mq.gettime() + 10000
                local function timertest()
                    if timer <= mq.gettime() then return false else return true end
                end
                while (mq.TLO.Me.Gem(gem)() and string.lower(mq.TLO.Me.Gem(gem)()) ~= string.lower(spell)) and timertest() do
                    mq.delay(50)
                end
                return false
            else
                mq.cmdf('/dgt \ayTrotsbot:\ax ' .. Sub .. ID .. ': Spell %s not found in your book', spell)
                myconfig[Sub .. ID].tarcnt = 0
                return false
            end
        end
        if not mq.TLO.Me.SpellReady(spell)() then
            if mq.TLO.Me.Gem(spell)() == gem then gemInUse[gem] = (mq.gettime() + mq.TLO.Spell(spell).RecastTime() + 5500) end
            return false
        end
    end
    return true
end

function trotslib.InterruptCheck()
    -- disabling debug messages as this gets called too much, remove comments to debug interrupts
    if not CurSpell.sub then return false end
    local sub = CurSpell.sub
    local spell = CurSpell.spell
    local spellname = nil
    if sub and spell then spellname = myconfig[sub .. spell].spell or
        (myconfig[sub .. spell].gem == 'item' and mq.TLO.FindItem(myconfig[sub .. spell].spell).Spell()) end
    local criteria = CurSpell.logic
    local target = CurSpell.target
    local spelltartype = mq.TLO.Spell(spellname).TargetType()
    local targetname = mq.TLO.Spawn(target).CleanName()
    local spellid = mq.TLO.Spell(myconfig[sub .. spell].spell).ID() or
    (myconfig[sub .. spell].gem == 'item' and mq.TLO.FindItem(myconfig[sub .. spell].spell).Spell.ID())
    local spelldur = mq.TLO.Spell(spellname).MyDuration.TotalSeconds() or
    (myconfig[sub .. spell].gem == 'item' and mq.TLO.FindItem(myconfig[sub .. spell].spell).Spell.MyDuration())
    if not criteria then return false end
    if spelldur then spelldur = spelldur * 1000 end
    if not target or not spell or not criteria or not sub then return false end
    if mq.TLO.Me.Class.ShortName() ~= 'BRD' then
        if mq.TLO.Target.ID() and string.lower(spelltartype) ~= "self" and (mq.TLO.Target.ID() == 0 or string.find(mq.TLO.Target.Name(), 'corpse') and criteria ~= 'corpse') then
            mq.cmd('/squelch /multiline; /stick off ; /target clear')
            if mq.TLO.Me.CastTimeLeft() > 0 and EvalID ~= 1 and classhit ~= 'grp' then
                mq.cmd('/echo I lost my target, interrupting')
                mq.cmd('/stopcast')
                if mq.TLO.Me.CastTimeLeft() > 0 and mq.TLO.Me.Combat() then mq.cmd('/attack off') end
            end
            if runconfig.domelee then trotsmelee.AdvCombat() end
        end
    end
    if criteria ~= 'corpse' then
        if mq.TLO.Target.Type() == 'Corpse' and criteria ~= 'corpse' then mq.cmd(
            '/multiline ; /interrupt ; /squelch /target clear ; /echo My target is dead, interrupting') end
    end
    --if debug then print('interrupt call ', 'sub:',sub, ' spellname:',spellname, ' spellid:',spellid, ' criteria:',criteria, ' target:',target, ' spelldur:', spelldur, ' casttiming:',mq.TLO.Me.CastTimeLeft() ) end
    if sub == 'ah' and criteria ~= 'corpse' then
        if mq.TLO.Target.PctHPs() and AHThreshold and AHThreshold[spell] and AHThreshold[spell][criteria] and (AHThreshold[spell][criteria] + (math.abs(AHThreshold[spell][criteria] - 100) * myconfig.heal['interruptlevel'])) <= mq.TLO.Target.PctHPs() and mq.TLO.Target.ID() == target then
            mq.cmdf('/multiline ; /interrupt ; /echo Interrupting Spell %s, target is above the threshold',
                myconfig['ah' .. spell]['spell'])
            while (mq.TLO.Me.CastTimeLeft() > 0) do
                mq.cmd('/interrupt')
                mq.delay(100)
            end
            mq.delay(3000, function() return mq.TLO.Me.CastTimeLeft() == 0 end)
            CurSpell = {}
        end
    end
    if mq.TLO.Me.CastTimeLeft() > 0 and (sub == 'ad' or sub == 'ab') and spelldur and spelldur > 0 and mq.TLO.Me.Class.ShortName() ~= 'BRD' then
        local buffid = mq.TLO.Target.Buff(spellname).ID() or false
        local buffstaleness = mq.TLO.Target.Buff(spellname).Staleness() or 0
        local buffdur = mq.TLO.Target.Buff(spellname).Duration() or 0
        --if debug then print("ab or ad interrupt target check target:", mq.TLO.Target.ID(),target ,' buff dur remain: ', mq.TLO.Target.Buff(spellname).Duration(), ' spelldur:', spelldur, ' buffspopulated:', mq.TLO.Target.BuffsPopulated() , ' cachedbuff:',mq.TLO.Target.CachedBuff(spellid) () , ' staleness:',mq.TLO.Target.CachedBuff(spellid).Staleness(), 'targetname:', targetname) end
        if mq.TLO.Target.ID() == target and mq.TLO.Target.BuffsPopulated() and buffid and buffstaleness < 2000 and buffdur > (spelldur * .10) then
            if sub == 'ab' then
                if mq.TLO.Spell(spellid).StacksTarget() then
                    mq.cmdf('/multiline ; /echo Interrupt %s, buff does not stack on target: %s ; /interrupt', spellname,
                        spellname, targetname)
                end
                mq.cmdf('/multiline ; /echo Interrupt %s, buff already present ; /interrupt', spellname, spellname)
                while (mq.TLO.Me.CastTimeLeft() > 0) do
                    mq.cmd('/interrupt')
                    mq.delay(100)
                end
                if not interruptCounter[spellid] then interruptCounter[spellid] = { 0, 0 } end
                interruptCounter[spellid] = { interruptCounter[spellid][1] + 1, mq.gettime() + 10000 }
                CurSpell = {}
            elseif sub == 'ad' and mq.TLO.Spell(spellid).CategoryID() ~= 20 then
                mq.cmdf('/multiline ; /echo Interrupt %s on MobID %s, debuff already present ; /interrupt', spellname,
                    target)
                local spelldur = mq.TLO.Target.Buff(spellname).Duration() + mq.gettime()
                trotsdebuff.DebuffListUpdate(target, spellid, spelldur)
                while (mq.TLO.Me.CastTimeLeft() > 0) do
                    mq.cmd('/interrupt')
                    mq.delay(100)
                end
                CurSpell = {}
            end
        end
        --if debug then print(mq.TLO.Spell(spellid).StacksTarget(), spellid, spellname, targetname, mq.TLO.Target.Name()) end
        if mq.TLO.Target.ID() == target and mq.TLO.Target.BuffsPopulated() and mq.TLO.Spell(spellid).StacksTarget() == 'FALSE' then
            if sub == 'ab' then
                mq.cmdf('/multiline ; /dgt \ayTrotsbot:\axInterrupt %s, buff does not stack on target: %s ; /interrupt',
                    spellname, spellname, targetname)
                while (mq.TLO.Me.CastTimeLeft() > 0) do
                    mq.cmd('/interrupt')
                    mq.delay(100)
                end
                if not interruptCounter[spellid] then interruptCounter[spellid] = { 0, 0 } end
                interruptCounter[spellid] = { interruptCounter[spellid][1] + 1, mq.gettime() + 10000 }
                CurSpell = {}
            elseif sub == 'ad' then
                mq.cmdf(
                '/multiline ; /dgt \ayTrotsbot:\axInterrupt %s on MobID %s Name %s, debuff does not stack ; /interrupt',
                    spellname, target, targetname)
                trotsdebuff.DebuffListUpdate(target, spellname, mq.TLO.Target.Buff(spellname).Duration())
                while (mq.TLO.Me.CastTimeLeft() > 0) do
                    mq.cmd('/interrupt')
                    mq.delay(100)
                end
                CurSpell = {}
            end
        end
    end
    -- cure interrupt logic, currently broken (no way to pass in the curetype currently)
    if mq.TLO.Me.CastTimeLeft() > 0 and sub == 'ac' and false then
        if criteria == 'all' then criteria = 'Detrimentals' end
        local tarname = mq.TLO.Target.CleanName()
        local curtar = mq.TLO.Target.ID()
        local buffspop = mq.TLO.Target.BuffsPopulated()
        local tarname = mq.TLO.Target.CleanName()
        if tarname then
            local nbid = mq.TLO.NetBots(tarname).ID()
            local nbdebuff = mq.TLO.NetBots(tarname)[criteria]()
            if curtar and nbid and curtar == target and buffspop and not nbdebuff then
                mq.cmdf('/multiline ; /dgt \ayTrotsbot:\axInterrupt %s, is no longer %s ; /interrupt', spellname,
                    criteria)
                while (mq.TLO.Me.CastTimeLeft() > 0) do
                    mq.cmd('/interrupt')
                    mq.delay(100)
                end
                CurSpell = {}
            end
        end
    end
end

function trotslib.CastSpell(index, EvalID, classhit, sub)
    if debug then print('castspell') end
    local entry = myconfig[sub .. index]
    --if entry and type(entry.alias) == 'string' and trotsdb and trotsdb.resolve_entry then
    --local level = tonumber(mq.TLO.Me.Level()) or 1
    --if (not entry.spell or entry.spell == 0 or entry.spell == '0' or entry._resolved_level ~= level) then
    -- trotsdb.resolve_entry(sub, index, false)
    --end
    --end
    local spell = string.lower(myconfig[sub .. index]['spell'])
    local spellid = mq.TLO.Spell(spell).ID()
    local gem = myconfig[sub .. index]['gem']
    local targetname = mq.TLO.Spawn(EvalID).CleanName()
    if (mq.TLO.Spell(spell).MyCastTime() and mq.TLO.Spell(spell).MyCastTime() > 0 and (mq.TLO.Me.Moving() or mq.TLO.Navigation.Active() or mq.TLO.Stick.Active()) and mq.TLO.Me.Class.ShortName() ~= 'BRD') then
        mq.cmd('/multiline ; /nav stop log=off ; /stick off)')
    end
    if (sub == 'ad' and classhit == 'notanktar' and mq.TLO.Me.Combat()) then mq.cmd('/squelch /attack off') end
    if mq.TLO.Me.Class.ShortName() ~= 'BRD' then mq.delay(3000, function() return not mq.TLO.Me.Moving() end) end
    if debug then print(myconfig[sub .. index]['spell'], myconfig[sub .. index]['gem'], EvalID) end
    if (mq.TLO.Plugin('MQ2Twist').IsLoaded()) then
        if mq.TLO.Twist() and mq.TLO.Twist.Twisting() then mq.cmd('/squelch /twist stop') end
    end
    if mq.TLO.Me.Class.ShortName() == 'BRD' then
        if (myconfig.settings['domelee'] and runconfig['MobCount'] > 0 and classhit ~= 'notanktar' and not mq.TLO.Me.Combat()) then
            trotsmelee.AdvCombat() end
        if type(gem) == 'number' then
            while not mq.TLO.Me.SpellReady(spell)() do mq.delay(10) end
            if mq.TLO.Me.SpellReady(spell)() then mq.cmd('/squelch /stopcast') end
        end
    end
    if entry.announce and type(entry.announce) == 'string' and mq.TLO.Me.CastTimeLeft() == 0 then
        mq.cmdf("/dgt \ayTrotsbot:\axCasting \ag%s\ax on >\ay%s\ax<", spell, targetname)
    end
    local casttimer = mq.gettime() + 300
    if type(gem) == 'number' or gem == 'item' or gem == 'alt' or 'script' then
        if EvalID == 1 and (classhit == 'self' or classhit == 'grp') then
            if type(gem) == 'number' then
                mq.cmdf('/cast "%s"', spell)
            elseif gem == 'item' then
                mq.cmdf('/cast item "%s"', spell)
            elseif gem == 'alt' then
                mq.cmdf('/alt act %s', mq.TLO.Me.AltAbility(spell)())
            elseif gem == 'script' then
                trotslib.RunScript(spell, sub, index)
            end
        else
            if debug then print(myconfig[sub .. index]['spell'], "targeting") end
            if mq.TLO.Target.ID() ~= EvalID then mq.cmdf('/tar id %s', EvalID) end
            mq.delay(1000, function() if mq.TLO.Target.ID() == EvalID then return true end end)
            if type(gem) == 'number' then
                mq.cmdf('/cast "%s"', spell)
            elseif gem == 'item' then
                mq.cmdf('/cast item "%s"', spell)
            elseif gem == 'alt' then
                mq.cmdf('/alt act %s', mq.TLO.Me.AltAbility(spell)())
            elseif gem == 'script' then
                trotslib.RunScript(spell, sub, index)
            end
        end
        -- tested on live servers and all spells take .4 sec to register a fizzle/miss notes
        -- since for AD we need to know if the spell casted before we check for resist or add it to the debuff list, we must wait
        -- also this is post cast so it doesnt really slow anything down if the spell worked, if it failed it ensures we retry for awhile
        if sub == 'ad' then mq.delay(400) end
        while mq.TLO.Me.CastTimeLeft() == 0 and casttimer > mq.gettime() do
            mq.doevents()
            if MissedNote then
                mq.cmdf('/cast "%s"', spell)
                mq.delay(400)
            end
            if mq.TLO.Cast.Result() == 'CAST_FIZZLE' then mq.cmdf('/cast "%s"', spell) end
        end
    end
    if gem == 'disc' and mq.TLO.Me.CombatAbilityReady(spell)() then
        local casttimer = mq.gettime() + 3000
        while mq.TLO.Me.CombatAbilityReady(spell)() and casttimer > mq.gettime() do
            if mq.TLO.Target.ID() ~= EvalID then mq.cmdf('/tar id %s', EvalID) end
            mq.delay(1000, function() if mq.TLO.Target.ID() == EvalID then return true end end)
            mq.cmdf('/squelch /disc %s', spell)
            if debug then print('casting ' .. spell) end
            mq.delay(100)
        end
    end
    if gem == 'ability' then
        mq.cmdf('/squelch /face fast')
        mq.cmdf('/doability %s', spell)
    end
    CurSpell = {
        sub = sub,
        spell = index,
        target = EvalID,
        logic = classhit,
        resisted = false,
    }
    if classhit == 'charmtar' then runconfig['charmid'] = EvalID end
    if mq.TLO.Me.Class.ShortName() ~= 'BRD' then
        while mq.TLO.Me.CastTimeLeft() > 0 do
            mq.delay(10)
            trotslib.InterruptCheck()
        end
    elseif mq.TLO.Me.Class.ShortName() == 'BRD' then
        while mq.TLO.Me.CastTimeLeft() > 0 and mq.TLO.Me.CastTimeLeft() < 10000 do
            mq.delay(1)
            if MissedNote then MissedNote = false end
            if mq.TLO.Target.ID() and (mq.TLO.Target.ID() == 0 or string.find(mq.TLO.Target.Name(), 'corpse')) then
                local tarname = mq.TLO.Target.Name()
                if mq.TLO.NetBots(myconfig.settings['TankName']).TargetID() and mq.TLO.NetBots(myconfig.settings['TankName']).TargetID() ~= 0 and myconfig.settings['domelee'] then
                    if tarname and string.find(mq.TLO.Target.Name(), 'corpse') then mq.cmd(
                        '/squelch /multiline ; /attack off ; /stick off ; /target clear') end
                    --if runconfig.domelee then trotsmelee.AdvCombat() end
                end
            end
        end
        mq.delay(500,
            function() if mq.TLO.Me.Song(spell).Duration() and mq.TLO.Me.Song(spell).Duration() > 10000 then return true end end)
    end
    --print('castwait5')
    mq.doevents()
    if SpellResisted then
        CurSpell.resisted = true
        SpellResisted = false
    end
    if sub == 'ad' then
        if myconfig[sub .. index]['delay'] > 0 then
            DebuffDlyLst[index] = mq.gettime() + (myconfig[sub .. index]['delay'] * 1000)
        end
        if debug then print(spell, mq.TLO.Spell(spell).MyDuration(), tonumber(mq.TLO.Spell(spell).MyDuration())) end
        if (mq.TLO.Spell(spell).MyDuration() and tonumber(mq.TLO.Spell(spell).MyDuration()) > 0) then
            mq.delay(50)
            if debug then print('debufflistupdate check1', mq.TLO.Target.MyBuff(spell).ID(), spell, mq.TLO.Target()) end
            if mq.TLO.Target.Buff(spell).ID() or mq.TLO.Me.Class.ShortName() == 'BRD' and not MissedNote then
                local myduration = mq.TLO.Spell(spell).MyDuration.TotalSeconds() * 1000 + mq.gettime()
                if debug then print('debufflistupdate check2 resisted?:', CurSpell.resisted) end
                if not CurSpell.resisted then
                    if debug then print('saving ', EvalID, ' and spell ', spell, ' with duration ', myduration,
                            ' time is ', mq.gettime()) end
                    trotsdebuff.DebuffListUpdate(EvalID, spellid, myduration)
                    if recastcntr[EvalID] and recastcntr[EvalID][index] and recastcntr[EvalID][index].counter then
                        recastcntr[EvalID][index].counter = 0
                    end
                    return true
                end
            end
        end
    end
    if MissedNote then MissedNote = false end
end

function trotslib.RefreshSpells()
    local enabled, disabled = 0, 0
    local function refresh_section(sub, section_key)
        local cnt = myconfig[section_key] and myconfig[section_key].count or 0
        if not cnt or cnt <= 0 then return end
        for i = 1, cnt do
            local key = sub .. i
            local entry = myconfig[key]
            if entry and type(entry.alias) == 'string' and entry.alias ~= '' then
                if trotsdb and trotsdb.resolve_entry then trotsdb.resolve_entry(sub, i, true) end
                local known = false
                if entry.gem == 'disc' then
                    -- For disciplines, check CombatAbility (but only if spell is valid, not 0)
                    known = entry.spell and entry.spell ~= 0 and entry.spell ~= '' and
                    mq.TLO.Me.CombatAbility(entry.spell)() ~= nil
                else
                    -- For spells, check Book
                    known = entry.spell and mq.TLO.Me.Book(entry.spell)()
                end
                if known then
                    if entry.tarcnt == 0 then
                        entry.tarcnt = entry._saved_tarcnt or 1
                        entry._saved_tarcnt = nil
                        enabled = enabled + 1
                    end
                else
                    if entry._saved_tarcnt == nil then entry._saved_tarcnt = entry.tarcnt or 0 end
                    if entry.tarcnt ~= 0 then disabled = disabled + 1 end
                    entry.tarcnt = 0
                end
            end
        end
    end
    refresh_section('ah', 'heal')
    refresh_section('ab', 'buff')
    refresh_section('ad', 'debuff')
    refresh_section('ac', 'cure')
    refresh_section('ae', 'event')
    mq.cmdf('/dgt Refreshed alias spells. Enabled:%s Disabled:%s', enabled, disabled)
end

function trotslib.GroupInvite(groupldr, groupmembers, grptype)
    if debug then rintf('groupldr: %s', groupldr) end
    local myid = mq.TLO.Me.ID() or 0
    local groupldrspawnid = mq.TLO.Spawn('pc =' .. groupldr).ID() or 0
    for raidmember, _ in pairs(groupmembers) do
        local spawnid = mq.TLO.Spawn('pc =' .. raidmember).ID() or 0
        if debug then printf('%s inviting: %s', groupldr, raidmember) end
        if (grptype == 'group' or spawnid > 0) and groupldrspawnid ~= myid then
            mq.cmdf('/dex %s /inv %s', groupldr, raidmember)
            mq.delay(50)
        elseif spawnid > 0 and groupldrspawnid == myid then
            mq.cmdf('/inv %s', raidmember)
            mq.delay(50)
        elseif grptype == 'raid' then
            mq.cmdf("/dgt \ayTrotsbot:\ax\ar%s's\ax group member \ar%s\ax is not in the zone, skipping", groupldr,
                raidmember)
        end
    end
end

function Event_Invite()
end

function Event_Slain()
    local respawntimeleft = (HoverEchoTimer - mq.gettime()) / 1000
    mq.cmdf('/dgt \ayTrotsbot:\axI died and am hovering, %s seconds until I release', respawntimeleft)
    mq.cmd('/multiline ; /consent group ; /consent raid ; /consent guild')
    if false and mq.TLO.NetBots.Counts() then
        --disabling this as it doesnt seem needed and spams badly
        for i = 1, mq.TLO.NetBots.Counts() do
            mq.cmdf('/consent %s', mq.TLO.NetBots[i].Name())
            mq.delay(200)
        end
    end
    HoverTimer = mq.gettime() + 30000
end

function Event_CastRst()
    SpellResisted = true
end

function Event_CastImm(line)
    local curtarget = mq.TLO.Target.ID()
    local sub = CurSpell.sub
    local spell = CurSpell.spell
    local spellid = mq.TLO.Spell(myconfig[sub .. spell].spell).ID()
    if string.find(line, "(with this spell)") then return false end
    if mq.TLO.Cast.Stored.ID() == spellid then
        if mq.TLO.Spell(spellid).TargetType() ~= "Targeted AE" and mq.TLO.Spell(spellid).TargetType() ~= "PB AE" then
            if CurSpell.target or CurSpell.target == 1 then
                if CurSpell.target == curtarget then
                    local immuneID = CurSpell.target
                    ProcessImmuneList(immuneID)
                end
            end
        end
    end
end

function Event_MissedNote()
    --print('MissedNote')
    MissedNote = true
end

function Event_CastStn()
end

function Event_CharmBroke(line, charmspell)
    local charmspellname = mq.TLO.Spell(charmspellid).Name()
    local charmid = runconfig['charmid']
    if runconfig['charmid'] and charmspell == charmspellname then
        if DebuffList[charmid] and DebuffList[charmid][charmspellid] then DebuffList[charmid][charmspellid] = nil end
        mq.cmdf('/dgt \ayTrotsbot:\ax\arCHARM %s wore off!', charmspell)
        trotslib.CastSpell(charmindex, charmid, 'charmtar', 'ad')
    end
end

function Event_ResetMelee()
end

function Event_WornOff()
end

function Event_Camping()
end

function Event_GoM()
end

function Event_LockedDoor()
end

function Event_EQBC()
end

function Event_DanChat()
end

function Event_CHChain(line, arg1)
    if string.lower(arg1) ~= string.lower(mq.TLO.Me.Name()) then return false end
    if not dochchain then return false end
    local chcall = true
    chchaincurtank = 1
    local chtimer = (chchainpause * 100) + mq.gettime()
    if debug then print(chtimer, ' ', mq.gettime()) end
    local tankid = mq.TLO.Spawn('=' .. chchaintank).ID()
    if debug then print(tankid, chchaintank) end
    if not tankid or tankid == 0 or mq.TLO.Spawn(tankid).Type() == 'Corpse' then
        chchaincurtank = chchaincurtank + 1
        if chtanklist[chchaincurtank] and mq.TLO.Spawn('=' .. chtanklist[chchaincurtank]).Type() == 'PC' and mq.TLO.Spawn('=' .. chtanklist[chchaincurtank]).ID() then
            mq.cmdf('/rs Tank DIED or ZONED, moving to tank %s, %s', chchaincurtank, chtanklist[chchaincurtank])
            chchaintank = chtanklist[chchaincurtank]
            tankid = mq.TLO.Spawn('=' .. chchaintank).ID()
        else
            mq.cmdf('/rs Tank %s is not in zone or dead, skipping', chchaintank)
            mq.delay((chchainpause * 100))
            mq.cmdf('/rs <<Go %s>>', chnextclr)
            return
        end
    end
    if chchaintank and mq.TLO.Target.ID() ~= tankid then
        mq.cmdf('/tar id %s', tankid)
    end
    if (mq.TLO.Me.CurrentMana() - (mq.TLO.Me.ManaRegen() * 2)) < 400 then
        mq.cmdf('/rs SKIP ME (out of mana)')
        mq.delay((chchainpause * 100))
        mq.cmdf('/rs <<Go %s>>', chnextclr)
        return
    end
    if not trotslib.DistanceCheck('complete heal', 0, tankid) then mq.cmdf(
        '/rs Tank %s is out of range of complete heal!', chchaintank) end
    mq.cmdf('/multiline ; /cast "Complete Heal" ; /rs CH >> %s << (pause:%s mana:%s)', chchaintank, chchainpause,
        mq.TLO.Me.PctMana())
    while (chcall) do
        if mq.TLO.Cast.Result() == 'CAST_FIZZLE' then
            printf('Fizzled, trying again cast status: %s', mq.TLO.Cast.Result())
            mq.cmdf('/cast "Complete Heal"')
        end
        if not mq.TLO.Me.Sitting() and not mq.TLO.Me.CastTimeLeft() then
            mq.delay(10)
            mq.cmd('/sit on')
        end
        mq.delay(10)
        if chtimer < mq.gettime() and chcall then
            mq.cmdf('/rs <<Go %s>>', chnextclr)
            chcall = false
        end
        if mq.TLO.Me.CastTimeLeft() and mq.TLO.Target.Type() == 'Corpse' then
            mq.cmdf('/multiline ; /rs CHChain: Target died, interrupting cast ; /interrupt')
            while (chtimer < mq.gettime() and chcall) do
                mq.delay(10)
            end
            mq.cmdf('/rs <<Go %s>>', chnextclr)
            chcall = false
        end
    end
    if not mq.TLO.Me.Sitting() and not mq.TLO.Me.CastTimeLeft() then
        mq.delay(10)
        mq.cmd('/sit on')
    end
end

function Event_CHChainSetup(line, arg1, arg2, arg3, arg4)
    if arg1 == 'setup' then cmdparse('chchain', 'setup', arg2, arg3, arg4) end
end

function Event_CHChainStop(line)
    if string.find(line, 'stop') then cmdparse('chchain', 'stop') end
end

function Event_CHChainStart(line, arg1, argN)
    local cleanname = arg1:match("%S+")
    if arg1 then cmdparse('chchain', 'start', cleanname) end
end

function Event_CHChainTank(line, arg1, argN)
    local cleanname = arg1:match("%S+")
    if arg1 and dochchain then cmdparse('chchain', 'tank', cleanname) end
end

function Event_CHChainPause(line, arg1, argN)
    if arg1 and dochchain then cmdparse('chchain', 'pause', arg1) end
end

function Event_LinkItem(line, Slot, HPFilter)
    if debug then mq.cmdf('/echo %s | %s', Slot, HPFilter) end
    HPValue = HPFilter
    if string.find(line, 'TB-') then return false end
    if string.find(Slot, "'") then Slot = string.sub(Slot, 2) end
    if HPValue and string.find(HPValue, "'") then HPValue = string.sub(HPValue, 2) end
    if HPValue then
        if HPFilter < mq.TLO.InvSlot(Slot).Item.HP() then return false end
    end
    if not mq.TLO.Me.Inventory(Slot).ID() then
        mq.cmdf('/dgt \ayTrotsbot:\ax\arMy \at%s slot \aris empty!', Slot)
        mq.cmdf('/rs My %s slot is empty!', Slot)
        return
    end
    local itemlink = mq.TLO.Me.Inventory(Slot).ItemLink('CLICKABLE')()
    local itemac = mq.TLO.InvSlot(Slot).Item.AC()
    local itemhp = mq.TLO.InvSlot(Slot).Item.HP()
    local itemmana = mq.TLO.InvSlot(Slot).Item.Mana()
    mq.cmdf('/dgt \ayTrotsbot:\ax%s AC:%s HP:%s Mana:%s', itemlink, itemac, itemhp, itemmana)
    mq.cmdf('/rs \ayTrotsbot:\ax%s AC:%s HP:%s Mana:%s', itemlink, itemac, itemhp, itemmana)
end

function Event_TooSteep()
end

function trotslib.DoYell()
    if YellTimer < mq.gettime() then
        mq.cmd('/yell')
        YellTimer = mq.gettime() + 3000
    end
end

function Event_FTELocked()
    local spawn = mq.TLO.Target
    if spawn.ID() and spawn.ID() > 0 then mq.cmdf(
        '/dgt \ayTrotsbot:\ax\arUh Oh, \ag%s\ax is \arFTE locked\ax to someone else!', spawn.Name()) end
    --if DoYell and DoYellTimer < mq.gettime() then
    --mq.cmd('/yell')
    DoYellTimer = mq.gettime() + 5000
    --end
    if FTECount == 0 then FTECount = FTECount + 1 end
    if spawn.ID() and spawn.ID() > 0 and not FTEList[spawn.ID()] then
        FTEList[spawn.ID()] = { id = spawn.ID(), hitcount = 1, timer = mq.gettime() + 10000 }
    elseif FTEList[spawn.ID()] and FTEList[spawn.ID()].hitcount == 1 then
        FTEList[spawn.ID()] = { id = spawn.ID(), hitcount = 2, timer = mq.gettime() + 30000 }
    elseif FTEList[spawn.ID()] and FTEList[spawn.ID()].hitcount >= 2 then
        FTEList[spawn.ID()] = { id = spawn.ID(), hitcount = 3, timer = mq.gettime() + 90500 }
    end
    mq.cmd('/multiline ; /squelch /target myself ; /attack off ; /stopcast ; /nav stop log=off; /stick off')
    if myconfig.settings['dopull'] then
        print('clearing pull target ')
        APTarget = false
    end
    trotsdebuff.ADSpawnCheck()
end

function Event_GMDetected()
    if gmtimer < mq.gettime() then
        mq.cmd('/dgt \ayTrotsbot:\axGM Detected! Disabling DoMelee, MakeCamp, and Stick!')
        myconfig.settings['domelee'] = false
        mq.cmd('/stick off')
        MakeCampX = nil
        MakeCampY = nil
        MakeCampZ = nil
        CampStatus = nil
        gmtimer = mq.gettime() + 60000
    end
end

function Event_MountFailed()
    if myconfig.domount then MountCastFailed = true end
end

function cmdparse(...)
    local args = { ... }
    local str = ''
    for i = 1, #args, 1 do
        if i > 1 then
            str = str .. ' '
        end
        str = str .. args[i]
    end
    local togglelist = { domelee = true, dopull = true, dodebuff = true, dobuff = true, doheal = true, doevent = true, doraid = true, docure = true, dosit = true, domount = true, dodrag = true }
    if debug then for i in pairs(args) do print(args[i]) end end
    -- command to toggle major subsections on or off
    if togglelist[args[1]] then
        if args[2] == 'on' then
            myconfig.settings[args[1]] = true
        elseif args[2] == 'off' then
            myconfig.settings[args[1]] = false
            if args[1] == 'dopull' then
                if APTarget and APTarget.ID() then APTarget = nil end
                if myconfig['pull'].hunter then
                    runconfig['makecampx'] = false
                    runconfig['makecampy'] = false
                    runconfig['makecampz'] = false
                end
                mq.cmd('/squelch /target clear ; /nav stop ; /stick off ; /attack off')
            end
        else
            if myconfig.settings[args[1]] == true then
                myconfig.settings[args[1]] = false
                if args[1] == 'dopull' or args[1] == 'domelee' then
                    if APTarget and APTarget.ID() then APTarget = nil end
                    mq.cmd('/squelch /target clear ; /nav stop ; /stick off ; /attack off')
                end
                if args[1] == 'dopull' and myconfig['pull'].hunter then
                    runconfig['makecampx'] = false
                    runconfig['makecampy'] = false
                    runconfig['makecampz'] = false
                end
            else
                myconfig.settings[args[1]] = false
                myconfig.settings[args[1]] = true
            end
        end
        if myconfig.settings['domelee'] then trotsmelee.LoadMeleeConfig() end
        if myconfig.settings['dopull'] then trotspull.LoadPullConfig() end
        if myconfig.settings['doheal'] then trotsheal.LoadHealConfig() end
        if myconfig.settings['dobuff'] then trotsbuff.LoadBuffConfig() end
        if myconfig.settings['dodebuff'] then trotsdebuff.LoadDebuffConfig() end
        if myconfig.settings['docure'] then trotscure.LoadCureConfig() end
        if myconfig.settings['doevent'] then trotsevent.LoadEventConfig() end
        if myconfig.settings['doraid'] then trotsraid.LoadRaidConfig() end
        mq.cmdf('/dgt \ayTrotsbot:\axTurning %s to %s', args[1], myconfig.settings[args[1]])
    end
    if args[1] == 'doyell' then
        if args[2] == 'on' then
            print('Enabling yelling for FTE')
            DoYell = true
        elseif args[2] == 'off' then
            print('Disabling yelling for FTE')
            DoYell = false
        else
            if DoYell == true then
                print('Disabling yelling for FTE')
                DoYell = false
            elseif DoYell == false then
                print('Enabling yelling for FTE')
                DoYell = true
            end
        end
    end
    -- command to import ini from legacy trotsbot
    if args[1] == 'import' then
        if args[2] == 'ini' then
            trotslib.ImportIni()
        end
        if args[2] == 'common' then
            trotslib.ImportCom()
        end
        if args[2] == 'lua' then
            local importpath = mq.configDir .. "\\" .. args[3]
            local configData, err = loadfile(importpath)
            if err then
                -- failed to read the config file, create it using pickle
                printf('failed to import lua file at %s', importpath)
            elseif configData then
                -- file loaded, put content into your config table
                myconfig = configData()
                if myconfig.settings['domelee'] then trotsmelee.LoadMeleeConfig() end
                if myconfig.settings['dopull'] then trotspull.LoadPullConfig() end
                if myconfig.settings['doheal'] then trotsheal.LoadHealConfig() end
                if myconfig.settings['dobuff'] then trotsbuff.LoadBuffConfig() end
                if myconfig.settings['dodebuff'] then trotsdebuff.LoadDebuffConfig() end
                if myconfig.settings['docure'] then trotscure.LoadCureConfig() end
                if myconfig.settings['doevent'] then trotsevent.LoadEventConfig() end
                mq.cmdf('/dgt \ayTrotsbot:\axLoaded lua file %s', args[3])
                if args[4] == 'save' then writeConfigToFile(myconfig, path, keyOrder) end
            end
        end
    end
    if args[1] == 'dropobs' then
        trotslib.DropObs()
    end
    -- command to export config lua to custom file
    if args[1] == 'export' then
        local exportpath = mq.configDir .. "\\" .. args[2]
        writeConfigToFile(myconfig, exportpath, keyOrder)
        print("Exporting my config to " .. exportpath)
    end
    -- /tb debug on (turns on debug lines and opens the gui)
    if args[1] == 'debug' then
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
    if args[1] == 'equipgear' then
        if args[2] == 'on' then
            mq.cmd('/dgt \ayTrotsbot:\axEnabling trotsbot auto equip, equiping any gear traded to me')
            EquipGear = true
        elseif args[2] == 'off' then
            mq.cmd('/dgt \ayTrotsbot:\axDisabling trotsbot auto equip')
            EquipGear = false
        else
            if EquipGear == true then
                mq.cmd('/dgt \ayTrotsbot:\axDisabling trotsbot auto equip')
                EquipGear = false
            elseif EquipGear == false then
                mq.cmd('/dgt \ayTrotsbot:\axEnabling trotsbot auto equip, equiping any gear traded to me')
                EquipGear = true
            end
        end
    end
    --show ui
    if args[1] == 'ui' or args[1] == 'show' then
        UIEnable()
    end
    -- /tb makecamp on/off (turns on the makecamp feature to set a camp at current location, bounded by acleash)
    if args[1] == 'makecamp' then
        if args[2] then
            trotsmove.MakeCamp(args[2])
        elseif not args[2] then
            if runconfig['campstatus'] then
                trotsmove.MakeCamp('off')
            else
                trotsmove.MakeCamp('on')
            end
        end
        if runconfig['followid'] or runconfig['followname'] then
            runconfig['followid'] = nil
            runconfig['followname'] = nil
        end
    end
    -- /tb follow followname on (follows the given follow name)
    if args[1] == 'follow' then
        if not mq.TLO.Navigation.MeshLoaded then
            mq.cmd('/echo No Mesh for this zone, cannot use TrotsFollow+!!')
            return
        end
        if mq.TLO.Spawn('=' .. args[2]).ID() then
            if runconfig['campstatus'] then trotsmove.MakeCamp('off') end
            runconfig['followid'] = mq.TLO.Spawn('=' .. args[2]).ID()
            runconfig['followname'] = args[2]
            stucktimer = mq.gettime() + 60000
        end
        mq.cmdf('/dgt \ayTrotsbot:\ax\auFollowing\ax ON %s', mq.TLO.Spawn(runconfig['followid']).CleanName())
    end
    if args[1] == 'stop' then
        if runconfig['followid'] or runconfig['followname'] then
            runconfig['followid'] = nil
            runconfig['followname'] = nil
        end
        if runconfig['campstatus'] then trotsmove.MakeCamp('off') end
        mq.cmd('/dgt \ayTrotsbot:\ax\arDisabling makecamp and follow')
    end
    -- /tb exclude (excludes mob from moblist and saves the list to tbcommon)
    if args[1] == 'exclude' then
        local excludemob = nil
        excludemob = args[2]
        if not args[2] then excludemob = mq.TLO.Target.CleanName() end
        if excludemob and not string.find(runconfig['ExcludeList'], excludemob) and args[2] ~= 'save' then
            mq.cmdf('/dgt \ayTrotsbot:\axExcluding %s from trotsbot', excludemob)
            runconfig['ExcludeList'] = runconfig['ExcludeList'] .. excludemob .. '|'
            if APTarget and APTarget.ID() then APTarget = nil end
            mq.cmd('/squelch /target clear ; /nav stop ; /stick off ; /attack off')
        end
        if args[3] == 'save' or args[2] == 'save' then
            mq.cmdf('/dgt \ayTrotsbot:\axSaving exclude list')
            ProcessExcludeList('save')
        else
            ProcessExcludeList()
        end
    end
    -- /tb xarc # (set's pull arc in degrees based on current heading)
    if args[1] == 'xarc' then
        trotspull.SetPullArc(args[2])
    end
    -- /tb priority (priority mob from moblist and saves the list to tbcommon)
    if args[1] == 'priority' then
        local prioritymob = nil
        prioritymob = args[2]
        if not args[2] then prioritymob = mq.TLO.Target.CleanName() end
        if prioritymob and not string.find(runconfig['PriorityList'], prioritymob) and args[2] ~= 'save' then
            mq.cmdf('/dgt \ayTrotsbot:\axPrioritizing %s in trotsbot', prioritymob)
            runconfig['PriorityList'] = runconfig['PriorityList'] .. prioritymob .. '|'
        end
        if args[3] == 'save' or args[2] == 'save' then
            mq.cmdf('/dgt \ayTrotsbot:\axSaving priority list')
            ProcessPriorityList('save')
        else
            ProcessPriorityList()
        end
    end
    -- abort command for disengaging
    if args[1] == 'abort' then
        if not args[2] then
            if mq.TLO.Me.CastTimeLeft() > 0 and CurSpell.sub and CurSpell.sub == 'ad' then mq.cmd('/stopcast') end
            if mq.TLO.Me.Combat() then mq.cmd('/attack off') end
            if mq.TLO.Target.ID() then mq.cmd('/squelch /target clear') end
            if runconfig['acmatarget'] then runconfig['acmatarget'] = nil end
            if myconfig.settings['domelee'] then
                myconfig.settings['domelee'] = false
                meleeabort = true
            end
            if myconfig.settings['dodebuff'] then
                myconfig.settings['dodebuff'] = false
                debuffabort = true
            end
            mq.cmd('/dgt \ayTrotsbot:\ax\arAbort+ called!\ax - DoDebuffs & DoMelee FALSE and leashing to camp')
        elseif args[2] == 'off' then
            if not myconfig.settings['domelee'] and meleeabort then myconfig.settings['domelee'] = true end
            if not myconfig.settings['dodebuff'] and debuffabort then myconfig.settings['dodebuff'] = true end
            mq.cmd('\arAbort\ax OFF, enabling dps sections again')
        end
    end
    -- leash command, if camp is set returns to anchor
    if args[1] == 'leash' then
        if runconfig['campstatus'] then
            mq.cmd('/dgt \ayTrotsbot:\ax\arLeash\ax called, returning to camp location')
            trotsmove.MakeCamp('return')
        else
            mq.cmd('/dgt \ayTrotsbot:\axNo camp set, cannot leash')
        end
    end
    -- attack command, force engage on tanks current target
    if args[1] == 'attack' then
        local KillTarget = mq.TLO.NetBots(myconfig.settings['TankName']).TargetID()
        runconfig['acmatarget'] = KillTarget
        if (KillTarget) then
            mq.cmdf('/dgt \ayTrotsbot:\ax\arEngaging\ax \ay%s\ax now', mq.TLO.Spawn(KillTarget).CleanName())
        else
            mq.cmd('/dgt \ayTrotsbot:\ax\ar Tank has no target, cannot engage')
        end
    end
    -- set tank command /tb tank name
    if args[1] == 'tank' then
        myconfig.settings['TankName'] = args[2]
        mq.cmdf('/dgt \ayTrotsbot:\axSetting tank to %s', myconfig.settings['TankName'])
        mq.TLO.Target.TargetOfTarget()
    end
    -- set stickcmd in memory
    if args[1] == 'stickcmd' then
        myconfig.melee.stickcmd = str:match('stickcmd' .. "%s+(.+)")
        mq.cmdf('/dgt \ayTrotsbot:\axSetting stickcmd to %s', myconfig.melee.stickcmd)
    end
    if args[1] == 'acleash' then
        myconfig.settings.acleash = tonumber(args[2])
        mq.cmdf('/dgt \ayTrotsbot:\axSetting acleash to %s', myconfig.settings.acleash)
    end
    if args[1] and string.lower(args[1]) == 'targetfilter' then
        myconfig.settings.TargetFilter = tonumber(args[2])
        mq.cmdf('/dgt \ayTrotsbot:\axSetting TargetFilter to %s', myconfig.settings.TargetFilter)
    end
    if args[1] == 'offtank' then
        if not args[2] then
            if myconfig.melee.offtank == true then
                myconfig.melee.offtank = false
            else
                myconfig.melee.offtank = true
            end
        elseif
            string.lower(args[2]) == 'true' or string.lower(args[2]) == 'on' then
            myconfig.melee.offtank = true
        elseif
            string.lower(args[2]) == 'false' or string.lower(args[2]) == 'off' then
            myconfig.melee.offtank = false
        else
            mq.cmdf(
            '/dgt \ayTrotsbot:\ax%s is an invalid value for offtank, please use true, on, false, off, or leave it blank to toggle',
                args[2])
            return false
        end
        mq.cmdf('/dgt \ayTrotsbot:\axSetting offtank to %s', myconfig.melee.offtank)
    end
    -- command to manually call cast by alias
    if args[1] == 'cast' then
        if args[2] then
            local target = args[3] and mq.TLO.Spawn(args[3]).ID() or mq.TLO.Target.ID()
            if myconfig.debuff['count'] and myconfig.debuff['count'] > 0 then
                for i = 1, myconfig.debuff['count'] do
                    for value in tostring(myconfig['ad' .. i]['alias']):gmatch("[^|]+") do
                        if value == args[2] and (args[3] ~= 'on' and args[3] ~= 'off') then
                            mq.cmdf('/dgt \ayTrotsbot:\ax\agCasting\ax %s on %s', myconfig['ad' .. i].spell,
                                mq.TLO.Spawn(target).CleanName())
                            if mq.TLO.Me.CastTimeLeft() > 0 then
                                while mq.TLO.Me.CastTimeLeft() > 0 do
                                    mq.delay(10)
                                    trotslib.InterruptCheck()
                                end
                            end
                            if trotslib.LoadSpell('ad', i) then trotslib.CastSpell(i, target, 'castcommand', 'ad') end
                        elseif args[3] and value == args[2] then
                            if args[3] == 'on' then
                                myconfig['ad' .. i].tarcnt = 1
                                mq.cmdf('/dgt \ayTrotsbot:\axEnabling \ag%s\ax', myconfig['ad' .. i].spell)
                                if not myconfig.settings.dodebuff then
                                    trotsdebuff.LoadDebuffConfig()
                                    myconfig.settings.dodebuff = true
                                end
                            end
                            if args[3] == 'off' then
                                myconfig['ad' .. i].tarcnt = 0
                                mq.cmdf('/dgt \ayTrotsbot:\axDisabling \ag%s\ax', myconfig['ad' .. i].spell)
                            end
                        end
                    end
                end
            end
            if myconfig.buff['count'] and myconfig.buff['count'] > 0 then
                for i = 1, myconfig.buff['count'] do
                    for value in tostring(myconfig['ab' .. i]['alias']):gmatch("[^|]+") do
                        if value == args[2] and (args[3] ~= 'on' and args[3] ~= 'off') then
                            mq.cmdf('/dgt \ayTrotsbot:\ax\agCasting\ax %s on %s', myconfig['ab' .. i].spell,
                                mq.TLO.Spawn(target).CleanName())
                            if not trotslib.LoadSpell('ab', i) then
                                mq.delay(3000)
                                if not trotslib.LoadSpell('ab', i) then
                                    mq.cmdf('/dgt \ayTrotsbot:\ax\arCast command spell %s not ready!',
                                        myconfig['ab' .. i].spell)
                                else
                                    trotslib.CastSpell(i, target, 'castcommand', 'ab')
                                end
                            else
                                trotslib.CastSpell(i, target, 'castcommand', 'ab')
                            end
                        elseif args[3] and value == args[2] then
                            if args[3] == 'on' then
                                myconfig['ab' .. i].tarcnt = 1
                                mq.cmdf('/dgt \ayTrotsbot:\axEnabling \ag%s\ax', myconfig['ab' .. i].spell)
                                if not myconfig.settings.dobuff then
                                    trotsbuff.LoadBuffConfig()
                                    myconfig.settings.dobuff = true
                                end
                            end
                            if args[3] == 'off' then
                                myconfig['ab' .. i].tarcnt = 0
                                mq.cmdf('/dgt \ayTrotsbot:\axDisabling \ag%s\ax', myconfig['ab' .. i].spell)
                            end
                        end
                    end
                end
            end
            if myconfig.heal['count'] and myconfig.heal['count'] > 0 then
                for i = 1, myconfig.heal['count'] do
                    for value in tostring(myconfig['ah' .. i]['alias']):gmatch("[^|]+") do
                        if value == args[2] and (args[3] ~= 'on' and args[3] ~= 'off') then
                            mq.cmdf('/dgt \ayTrotsbot:\ax\agCasting\ax %s on %s', myconfig['ah' .. i].spell,
                                mq.TLO.Spawn(target).CleanName())
                            if not trotslib.LoadSpell('ah', i) then
                                mq.delay(3000)
                                if not trotslib.LoadSpell('ah', i) then
                                    mq.cmdf('/dgt \ayTrotsbot:\ax\arCast command spell %s not ready!',
                                        myconfig['ah' .. i].spell)
                                else
                                    trotslib.CastSpell(i, target, 'castcommand', 'ah')
                                end
                            else
                                trotslib.CastSpell(i, target, 'castcommand', 'ah')
                            end
                        elseif args[3] and value == args[2] then
                            if args[3] == 'on' then
                                myconfig['ah' .. i].tarcnt = 1
                                mq.cmdf('/dgt \ayTrotsbot:\axEnabling \ag%s\ax', myconfig['ah' .. i].spell)
                                if not myconfig.settings.doheal then
                                    trotsheal.LoadHealConfig()
                                    myconfig.settings.doheal = true
                                end
                            end
                            if args[3] == 'off' then
                                myconfig['ah' .. i].tarcnt = 0
                                mq.cmdf('/dgt \ayTrotsbot:\axDisabling \ag%s\ax', myconfig['ah' .. i].spell)
                            end
                        end
                    end
                end
            end
            if myconfig.cure['count'] and myconfig.cure['count'] > 0 then
                for i = 1, myconfig.cure['count'] do
                    for value in tostring(myconfig['ac' .. i]['alias']):gmatch("[^|]+") do
                        if value == args[2] and (args[3] ~= 'on' and args[3] ~= 'off') then
                            mq.cmdf('/dgt \ayTrotsbot:\ax\agCasting\ax %s on %s', myconfig['ac' .. i].spell,
                                mq.TLO.Spawn(target).CleanName())
                            if not trotslib.LoadSpell('ac', i) then
                                mq.delay(3000)
                                if not trotslib.LoadSpell('ac', i) then
                                    mq.cmdf('/dgt \ayTrotsbot:\ax\arCast command spell %s not ready!',
                                        myconfig['ac' .. i].spell)
                                else
                                    trotslib.CastSpell(i, target, 'castcommand', 'ac')
                                end
                            else
                                trotslib.CastSpell(i, target, 'castcommand', 'ac')
                            end
                        elseif args[3] and value == args[2] then
                            if args[3] == 'on' then
                                myconfig['ac' .. i].tarcnt = 1
                                mq.cmdf('/dgt \ayTrotsbot:\axEnabling \ag%s\ax', myconfig['ac' .. i].spell)
                                if not myconfig.settings.docure then
                                    trotscure.LoadCureConfig()
                                    myconfig.settings.docure = true
                                end
                            end
                            if args[3] == 'off' then
                                myconfig['ac' .. i].tarcnt = 0
                                mq.cmdf('/dgt \ayTrotsbot:\axDisabling \ag%s\ax', myconfig['ac' .. i].spell)
                            end
                        end
                    end
                end
            end
            if myconfig.event['count'] and myconfig.event['count'] > 0 then
                for i = 1, myconfig.event['count'] do
                    for value in tostring(myconfig['ae' .. i]['alias']):gmatch("[^|]+") do
                        if value == args[2] and (args[3] ~= 'on' and args[3] ~= 'off') then
                            mq.cmdf('/dgt \ayTrotsbot:\ax\agCasting\ax %s on %s', myconfig['ae' .. i].spell,
                                mq.TLO.Spawn(target).CleanName())
                            if not trotslib.LoadSpell('ae', i) then
                                mq.delay(3000)
                                if not trotslib.LoadSpell('ae', i) then
                                    mq.cmdf('/dgt \ayTrotsbot:\ax\arCast command spell %s not ready!',
                                        myconfig['ae' .. i].spell)
                                else
                                    trotslib.CastSpell(i, target, 'castcommand', 'ae')
                                end
                            else
                                trotslib.CastSpell(i, target, 'castcommand', 'ae')
                            end
                        elseif args[3] and value == args[2] then
                            if args[3] == 'on' then
                                myconfig['ae' .. i].tarcnt = 1
                                mq.cmdf('/dgt \ayTrotsbot:\axEnabling \ag%s\ax', myconfig['ae' .. i].spell)
                                if not myconfig.settings.doevent then
                                    trotsevent.LoadEventConfig()
                                    myconfig.settings.doevent = true
                                end
                            end
                            if args[3] == 'off' then
                                myconfig['ae' .. i].tarcnt = 0
                                mq.cmdf('/dgt \ayTrotsbot:\axDisabling \ag%s\ax', myconfig['ae' .. i].spell)
                            end
                        end
                    end
                end
            end
        end
    end
    -- /tb setvar varname value(lets you set a variable in memory and in the ini in game
    if args[1] == 'setvar' then
        local valfound = false
        local sub = nil
        local key = nil
        local value = ''
        value = args[3]
        local tempconfig = {}
        local temploadconfig = loadfile(path)
        if args[2]:find("%.") ~= nil then
            local beforeDot, afterDot = args[2]:match("([^%.]+)%.(.+)")
            sub = beforeDot
            key = afterDot
        end
        if temploadconfig then
            tempconfig = temploadconfig()
        end
        for k, v in pairs(tempconfig) do
            if sub then
                if type(v) == "table" and k == sub then
                    for k2, v2 in pairs(tempconfig[k]) do
                        if key == k2 then
                            mq.cmdf('/dgt \ayTrotsbot:\axSetting \ag%s to \ay%s\ax', args[2], value)
                            valfound = true
                            if tonumber(value) then
                                tempconfig[k][k2] = tonumber(value)
                                myconfig[k][k2] = tonumber(value)
                            elseif value == "true" then
                                tempconfig[k][k2] = true
                                myconfig[k][k2] = true
                            elseif value == "false" then
                                tempconfig[k][k2] = false
                                myconfig[k][k2] = false
                            else
                                tempconfig[k][k2] = value
                                myconfig[k][k2] = value
                            end
                            if valfound then
                                writeConfigToFile(tempconfig, path, keyOrder)
                                if myconfig.settings['domelee'] then trotsmelee.LoadMeleeConfig() end
                                if myconfig.settings['doevent'] then trotsevent.LoadEventConfig() end
                                if myconfig.settings['dopull'] then trotspull.LoadPullConfig() end
                                if myconfig.settings['doheal'] then trotsheal.LoadHealConfig() end
                                if myconfig.settings['dobuff'] then trotsbuff.LoadBuffConfig() end
                                if myconfig.settings['dodebuff'] then trotsdebuff.LoadDebuffConfig() end
                            end
                        end
                    end
                end
            else
                if type(v) == "table" then
                    for k2, v2 in pairs(tempconfig[k]) do
                        if args[2] == k2 then
                            mq.cmdf('/dgt \ayTrotsbot:\axSetting \ag%s to \ay%s\ax', args[2], value)
                            valfound = true
                            if tonumber(value) then
                                tempconfig[k][k2] = tonumber(value)
                                myconfig[k][k2] = tonumber(value)
                            elseif value == "true" then
                                tempconfig[k][k2] = true
                                myconfig[k][k2] = true
                            elseif value == "false" then
                                tempconfig[k][k2] = false
                                myconfig[k][k2] = false
                            else
                                tempconfig[k][k2] = value
                                myconfig[k][k2] = value
                            end
                            if valfound then
                                writeConfigToFile(tempconfig, path, keyOrder)
                                if myconfig.settings['domelee'] then trotsmelee.LoadMeleeConfig() end
                                if myconfig.settings['doevent'] then trotsevent.LoadEventConfig() end
                                if myconfig.settings['dopull'] then trotspull.LoadPullConfig() end
                                if myconfig.settings['doheal'] then trotsheal.LoadHealConfig() end
                                if myconfig.settings['dobuff'] then trotsbuff.LoadBuffConfig() end
                                if myconfig.settings['dodebuff'] then trotsdebuff.LoadDebuffConfig() end
                                if myconfig.settings['docure'] then trotscure.LoadCureConfig() end
                            end
                        end
                    end
                end
            end
        end
        if dochchain then
            myconfig.settings['dodebuff'] = false
            myconfig.settings['dobuff'] = false
            myconfig.settings['domelee'] = false
            myconfig.settings['doheal'] = false
            myconfig.settings['doevent'] = false
            myconfig.settings['docure'] = false
            myconfig.settings['dopull'] = false
            myconfig.settings['dopet'] = false
        end
        if not valfound then mq.cmdf('/dgt \ayTrotsbot:\ax\ar%s not found', args[2]) end
    end
    --addspell logic for inserting new spell entrys to existing configs
    if args[1] == 'addspell' then
        local valfound = false
        local sub = args[2]
        local subltr = string.sub(sub, 1, 1)
        local key = args[3]
        local tempconfig = {}
        local sublist = { "heal", "cure", "event", "buff", "debuff" }
        local subfound = false
        for _, word in ipairs(sublist) do
            if word == sub then
                subfound = true
                break
            end
        end
        if not subfound then
            mq.cmdf('/dgt \ayTrotsbot:\ax%s is not a valid trotsbot sub please use heal, buff, debuff, event, or cure',
                sub)
            return false
        end
        if (not myconfig[sub].count and tonumber(key) > 1) or (tonumber(key) ~= 1 and myconfig[sub].count and (tonumber(key) > tonumber(myconfig[sub].count))) then
            mq.cmdf(
            '/dgt \ayTrotsbot:\ax%s is higher than the current spell count for %s, please use a valid existing entry key (ex: ab1 key would be 1)',
                key, sub)
            return false
        end
        local temploadconfig = loadfile(path)
        if temploadconfig then
            tempconfig = temploadconfig()
        end
        if tempconfig[sub].count then
            tempconfig[sub].count = tempconfig[sub].count + 1
            myconfig[sub].count = tempconfig[sub].count
        else
            tempconfig[sub].count = 1
            myconfig[sub].count = 1
        end
        local count = tempconfig[sub].count
        if sub == 'event' then
            trotsevent.LoadEventConfig()
            tempconfig['ae' .. count] = { gem = 0, spell = 0, minmana = 0, maxmana = 100, minhp = 0, maxhp = 100, minendur = 0, maxendur = 100, alias = false, announce = false, tarcnt = 0, class =
            'war brd clr pal shd shm rng rog ber mnk dru bst mag nec enc wiz', precondition = true }
        end
        if sub == 'heal' then
            trotsheal.LoadHealConfig()
            tempconfig['ah' .. count] = { gem = 0, spell = 0, minmana = 0, alias = false, announce = false, tarcnt = 0, class =
            'pc pet group hp50 war shd pal rng mnk rog brd bst ber shm clr dru wiz mag enc nec tnt mypet self', priority = false, precondition = true }
        end
        if sub == 'buff' then
            trotsbuff.LoadBuffConfig()
            tempconfig['ab' .. count] = { gem = 0, spell = 0, minmana = 0, alias = false, announce = false, tarcnt = 0, class =
            'war brd clr pal shd shm rng rog ber mnk dru bst mag nec enc wiz', spellicon = 0, precondition = true }
        end
        if sub == 'debuff' then
            trotsdebuff.LoadDebuffConfig()
            tempconfig['ad' .. count] = { gem = 0, spell = 0, minmana = 0, alias = false, announce = false, tarcnt = 0, tartype = 1, beghp = 99, endhp = 0, recast = 0, precondition = true }
        end
        if sub == 'cure' then
            trotscure.LoadCureConfig()
            tempconfig['ac' .. count] = { gem = 0, spell = 0, minmana = 0, alias = false, announce = false, curetype =
            "all", tarcnt = 0, class = 'war brd clr pal shd shm rng rog ber mnk dru bst mag nec enc wiz', priority = false, precondition = true }
        end
        writeConfigToFile(tempconfig, path, keyOrder)
        tempconfig = {}
        temploadconfig = loadfile(path)
        if temploadconfig then
            tempconfig = temploadconfig()
        end
        if debug then print('new entry added to ', sub) end
        for i = tempconfig[sub].count, key, -1 do
            local nextkey = i - 1
            if i > tonumber(key) then
                if debug then print('moving all entries in ', 'a' .. subltr .. nextkey, ' down one position to  ', sub, i) end
                for k, v in pairs(tempconfig['a' .. subltr .. i]) do
                    if debug then print('setting ', k, ' to value ', tempconfig['a' .. subltr .. nextkey][k]) end
                    tempconfig['a' .. subltr .. i][k] = tempconfig['a' .. subltr .. nextkey][k]
                    myconfig['a' .. subltr .. i][k] = myconfig['a' .. subltr .. nextkey][k]
                end
            elseif i == tonumber(key) then
                if debug then print('reached the key a' .. subltr, i) end
                if debug then print('setting ah', i, ' to default values') end
                if sub == 'event' then
                    myconfig['ae' .. i] = { gem = 0, spell = 0, minmana = 0, maxmana = 100, minhp = 0, maxhp = 100, minendur = 0, maxendur = 100, alias = false, announce = false, tarcnt = 0, class =
                    'war brd clr pal shd shm rng rog ber mnk dru bst mag nec enc wiz', precondition = true }
                    tempconfig['ae' .. i] = { gem = 0, spell = 0, minmana = 0, maxmana = 100, minhp = 0, maxhp = 100, minendur = 0, maxendur = 100, alias = false, announce = false, tarcnt = 0, class =
                    'war brd clr pal shd shm rng rog ber mnk dru bst mag nec enc wiz', precondition = true }
                end
                if sub == 'heal' then
                    tempconfig['ah' .. i] = { gem = 0, spell = 0, minmana = 0, alias = false, announce = false, tarcnt = 0, class =
                    'pc pet group hp50 war shd pal rng mnk rog brd bst ber shm clr dru wiz mag enc nec tnt mypet self', priority = false, precondition = true }
                    myconfig['ah' .. i] = { gem = 0, spell = 0, minmana = 0, alias = false, announce = false, tarcnt = 0, class =
                    'pc pet group hp50 war shd pal rng mnk rog brd bst ber shm clr dru wiz mag enc nec tnt mypet self', priority = false, precondition = true }
                end
                if sub == 'buff' then
                    myconfig['ab' .. i] = { gem = 0, spell = 0, minmana = 0, alias = false, announce = false, tarcnt = 0, class =
                    'war brd clr pal shd shm rng rog ber mnk dru bst mag nec enc wiz', spellicon = 0, precondition = true }
                    tempconfig['ab' .. i] = { gem = 0, spell = 0, minmana = 0, alias = false, announce = false, tarcnt = 0, class =
                    'war brd clr pal shd shm rng rog ber mnk dru bst mag nec enc wiz', spellicon = 0, precondition = true }
                end
                if sub == 'debuff' then
                    myconfig['ad' .. i] = { gem = 0, spell = 0, minmana = 0, alias = false, announce = false, tarcnt = 0, tartype = 1, beghp = 99, endhp = 0, recast = 0, precondition = true }
                    tempconfig['ad' .. i] = { gem = 0, spell = 0, minmana = 0, alias = false, announce = false, tarcnt = 0, tartype = 1, beghp = 99, endhp = 0, recast = 0, precondition = true }
                end
                if sub == 'cure' then
                    myconfig['ac' .. i] = { gem = 0, spell = 0, minmana = 0, alias = false, announce = false, curetype =
                    "all", tarcnt = 0, class = 'war brd clr pal shd shm rng rog ber mnk dru bst mag nec enc wiz', priority = false, precondition = true }
                    tempconfig['ac' .. i] = { gem = 0, spell = 0, minmana = 0, alias = false, announce = false, curetype =
                    "all", tarcnt = 0, class = 'war brd clr pal shd shm rng rog ber mnk dru bst mag nec enc wiz', priority = false, precondition = true }
                end
            end
        end
        writeConfigToFile(tempconfig, path, keyOrder)
        if sub == 'event' then trotsevent.LoadEventConfig() end
        if sub == 'heal' then trotsheal.LoadHealConfig() end
        if sub == 'buff' then trotsbuff.LoadBuffConfig() end
        if sub == 'debuff' then trotsdebuff.LoadDebuffConfig() end
        if sub == 'cure' then trotscure.LoadCureConfig() end
        mq.cmdf('/dgt \ayTrotsbot:\axadded new %s entry at a%s%s, all existing entries moved down 1 position', sub,
            subltr, key)
    end
    -- tb refresh for default configs (Blownt code)
    if args[1] == 'refresh' or args[1] == 'refreshspells' then
        trotslib.RefreshSpells()
    end
    if args[1] == 'echo' then
        local sub = nil
        local key = nil
        if args[2]:find("%.") ~= nil then
            local beforeDot, afterDot = args[2]:match("([^%.]+)%.(.+)")
            sub = beforeDot
            key = afterDot
        end
        if myconfig[sub][key] then
            mq.cmdf('/dgt \ayTrotsbot:\ax\ag%s\ax is set as \ay%s\ay', args[2], myconfig[sub][key])
        else
            mq.cmdf('/dgt \ayTrotsbot:\ax\ar%s\ar is not a valid trotsbot value', args[2])
        end
    end
    -- chchain setup and activation
    if args[1] == 'chchain' then
        if args[2] == 'stop' and dochchain then
            dochchain = false
            mq.cmdf('/dgt \ayTrotsbot:\ax\arDisabling\ax CHChain')
            mq.cmd('/rs CHCHain OFF')
            if PreCH['dodebuff'] then myconfig.settings['dodebuff'] = PreCH['dodebuff'] end
            if PreCH['dobuff'] then myconfig.settings['dobuff'] = PreCH['dobuff'] end
            if PreCH['domelee'] then myconfig.settings['domelee'] = PreCH['domelee'] end
            if PreCH['doheal'] then myconfig.settings['doheal'] = PreCH['doheal'] end
            if PreCH['doevent'] then myconfig.settings['doevent'] = PreCH['doevent'] end
            if PreCH['dopull'] then myconfig.settings['dopull'] = PreCH['dopull'] end
            if PreCH['dopet'] then myconfig.settings['dopet'] = PreCH['dopet'] end
            if PreCH['docure'] then myconfig.settings['docure'] = PreCH['docure'] end
        end
        if args[2] == 'setup' then
            local gem = 5
            local spell = 'complete heal'
            if not dochchain then PreCH = DeepCopy(myconfig['settings']) end
            local tmpchchainlist = args[3]
            local aminlist = false
            for v in string.gmatch(tmpchchainlist, "([^,]+)") do
                if string.lower(v) == string.lower(mq.TLO.Me.CleanName()) then
                    aminlist = true
                end
            end
            if not aminlist then return false end
            if mq.TLO.Me.Gem(spell)() ~= gem then
                if mq.TLO.Me.Book(spell)() then
                    mq.cmdf('/memspell %s "%s"', gem, spell)
                    function gemtest()
                        local curgem = mq.TLO.Me.Gem(gem)()
                        if curgem then curgem = string.lower(curgem) end
                        return curgem == string.lower(spell)
                    end

                    mq.delay(10000, gemtest)
                    gemInUse[gem] = (mq.gettime() + mq.TLO.Spell(spell).RecastTime())
                    local timer = mq.gettime() + 10000
                    local function timertest()
                        if timer <= mq.gettime() then return false else return true end
                    end
                    while (mq.TLO.Me.Gem(gem)() and string.lower(mq.TLO.Me.Gem(gem)()) ~= string.lower(spell)) and timertest() do
                        mq.delay(50)
                    end
                else
                    mq.cmdf(
                    '/dgt \ayTrotsbot:\axTrotsbot CHChain: Spell %s not found in your book, failed to start CHChain',
                        spell)
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
                local tankctr = 1
                for v in string.gmatch(args[5], "([^,]+)") do
                    if v:sub(-1) == "'" then
                        v = v:sub(1, -2)
                    end
                    if mq.TLO.Spawn('=' .. v).Type() == 'PC' then
                        table.insert(chtanklist, v)
                        print('adding ' .. v .. ' to tank list')
                        tankctr = tankctr + 1
                    end
                end
                chchaintank = chtanklist[1]
                local chtankstr = table.concat(chtanklist, ",")
                myconfig.settings['dodebuff'] = false
                myconfig.settings['dobuff'] = false
                myconfig.settings['domelee'] = false
                myconfig.settings['doheal'] = false
                --myconfig.settings['doevent'] = false
                myconfig.settings['docure'] = false
                myconfig.settings['dopull'] = false
                myconfig.settings['dopet'] = false
                mq.cmdf('/rs CHChain ON (NextClr: %s, Pause: %s, Tank: %s)', chnextclr, chchainpause, chtankstr)
            end
        end
        if args[2] == 'start' then
            if args[3] == mq.TLO.Me.Name() then
                Event_CHChain('start', mq.TLO.Me.Name())
            end
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
    if string.lower(args[1]) == 'draghack' then
        if args[2] then
            if args[2] == 'on' then DragHack = true end
            if args[2] == 'off' then DragHack = false end
        elseif not args[2] then
            if DragHack then DragHack = false else DragHack = true end
        end
        mq.cmdf('/dgt \ayTrotsbot:\axSet DragHack to %s', DragHack)
    end
    if string.lower(args[1]) == 'linkitem' then
        Event_LinkItem(args[1], args[2], args[3])
    end
    -- /tb linkaugs slotname (command for using dannet to have bots link their equipment and augments in that equipment by slot)
    if string.lower(args[1]) == 'linkaugs' then
        local itemslot = tonumber(mq.TLO.InvSlot(args[2])())
        local itemname = mq.TLO.InvSlot(args[2]).Item()
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
                mq.cmdf('/dgt \ayTrotsbot:\ax\ag%s\ax in slot \ay%s\ax augs: %s', itemlink, args[2], augstring)
            else
                mq.cmdf('/dgt \ayTrotsbot:\ax\arI have no augment in %s', itemlink)
            end
        end
    end
    -- /tb spread command - command to spread bots out in rows of 6 facing south
    if string.lower(args[1]) == 'spread' then
        local botcnt = mq.TLO.DanNet.PeerCount()
        local rowcnt = tonumber(1)
        local xiter = mq.TLO.Me.X()
        local yiter = mq.TLO.Me.Y()
        local bot = 'astring'
        local heading = mq.TLO.Me.Heading.Degrees()
        if not botcnt then return false end
        for i = 1, botcnt do
            bot = mq.TLO.DanNet.Peers(i)()
            xiter = xiter + 5
            if i % 6 == 0 then
                yiter = yiter + 5
                rowcnt = rowcnt + 1
                xiter = mq.TLO.Me.X()
            end
            mq.cmdf('/dex %s /nav locxy %s %s', bot, xiter, yiter)
        end
        mq.delay(3000)
        mq.cmdf('/dgae /face fast heading %s', heading)
    end
    -- /tb raid save/load raidname - command to save raid setup by name or load a saved raidsetup (saves to tbcommon)
    if string.lower(args[1]) == 'raid' then
        if string.lower(args[2]) == 'save' then
            local raidmembers = mq.TLO.Raid.Members() or 0
            if raidmembers > 0 and args[3] then
                mq.cmdf('/dgt \ayTrotsbot:\ax saving raidconfig \ag%s\ax', args[3])
                local raidname = args[3]
                comkeytable.raidlist[raidname] = {}
                comkeytable.raidlist[raidname].leaders = {}
                comkeytable.raidlist[raidname].groups = {}
                -- build leader table and member table
                for i = 1, raidmembers do
                    local raidmember = mq.TLO.Raid.Member(i)() or false
                    local spawnid = mq.TLO.Raid.Member(i).Spawn.ID() or 0
                    local groupldr = mq.TLO.Raid.Member(i).GroupLeader() or false
                    local groupnum = mq.TLO.Raid.Member(i).Group() or false
                    if groupldr and raidmember and groupnum then
                        if not comkeytable.raidlist[raidname].leaders[groupnum] then
                            comkeytable.raidlist[raidname].leaders[groupnum] = raidmember
                        end
                        comkeytable.raidlist[raidname].leaders[groupnum] = raidmember
                        if debug then printf('saving leader of group %s as %s', groupnum,
                                comkeytable.raidlist[raidname].leaders[groupnum]) end
                    elseif raidmember and groupnum then
                        if not comkeytable.raidlist[raidname].groups[groupnum] then
                            comkeytable.raidlist[raidname].groups[groupnum] = {}
                            if not comkeytable.raidlist[raidname].leaders[groupnum] then
                                comkeytable.raidlist[raidname].leaders[groupnum] = raidmember
                            end
                        end
                        comkeytable.raidlist[raidname].groups[groupnum][raidmember] = raidmember
                        if debug then printf('saving member of group %s as %s', groupnum,
                                comkeytable.raidlist[raidname].groups[groupnum][raidmember]) end
                    end
                end
                mq.pickle('TBCommon.lua', comkeytable)
            elseif raidmembers == 0 then
                mq.cmd('/dgt \ayTrotsbot:\ax Not in a raid, no raid to save')
            elseif not args[3] then
                mq.cmd('/dgt \ayTrotsbot:\ax Noname given, cant save raid (/tb raid save raidname)')
            end
        end
        if string.lower(args[2]) == 'load' then
            if args[3] then
                local raidname = args[3]
                if comkeytable.raidlist[raidname] then
                    mq.cmdf('/dgt \ayTrotsbot:\ax Loading raid setup \ag%s\ax', raidname)
                    local raidmembers = mq.TLO.Raid.Members() or 0
                    local myid = mq.TLO.Me.ID() or 0
                    if raidmembers and raidmembers > 0 then mq.cmd('/raiddisband') end
                    for disbanditer = 1, 12 do
                        local groupldr = comkeytable.raidlist[raidname].leaders[disbanditer] or false
                        mq.cmdf('/dex %s /squelch /multiline ; /disband ; /raiddisband', groupldr)
                        for raidmember, _ in pairs(comkeytable.raidlist[raidname].groups[disbanditer]) do
                            mq.cmdf('/dex %s /squelch /multiline ; /disband ; /raiddisband', raidmember)
                        end
                    end
                    mq.delay(500)
                    for i = 1, 12 do
                        local groupldr = comkeytable.raidlist[raidname].leaders[i] or false
                        local groupldrspawnid = groupldr and mq.TLO.Spawn('pc =' .. groupldr).ID() or 0
                        if groupldr then
                            if debug then printf('groupldr: %s', groupldr) end
                            trotslib.GroupInvite(groupldr, comkeytable.raidlist[raidname].groups[i], 'raid')
                            if groupldrspawnid > 0 and groupldrspawnid ~= myid then
                                mq.cmdf('/raidinv %s', groupldr)
                            elseif groupldrspawnid ~= myid then
                                mq.cmdf('/dgt \ayTrotsbot:\axGroup Leader \ar%s is not in zone, skipping group', groupldr)
                            end
                        end
                    end
                    mq.cmd('/dgae /squelch /multiline ; /target clear ; /timed 5 /inv')
                    mq.delay(1500)
                    mq.cmd('/dgae /yes')
                else
                    printf('no raid named %s found on this pc', raidname)
                end
            else
                print('no raid name giving /tb raid load raidname')
            end
        end
    end
end

function tbpause(...)
    local args = { ... }
    if args[1] and args[1] == 'off' then
        MasterPause = false
        mq.cmd('/echo Unpausing Trotsbot')
    elseif args[1] and args[1] == 'on' then
        MasterPause = true
        mq.cmd('/echo Pausing Trotsbot')
    else
        if MasterPause == false then
            MasterPause = true
            mq.cmd('/echo Pausing Trotsbot')
        else
            MasterPause = false
            mq.cmd('/echo Unpausing Trotsbot')
        end
    end
end

mq.bind('/tb', cmdparse)
mq.bind('/tbp', tbpause)
mq.bind('/tbshow', UIEnable)

mq.event('Invite', "#*#invites you to join a #1#.#*#", Event_Invite)
mq.event('Slain1', "#*#You have been slain by#*#", Event_Slain)
mq.event('Slain2', "#*#Returning to Bind Location#*#", Event_Slain)
mq.event('Slain3', "You died.", Event_Slain)
mq.event('DelayOnZone1', "#*#You have entered#*#", DelayOnZone)
mq.event('DelayOnZone2', "#*#LOADING, PLEASE WAIT.#*#", DelayOnZone)
mq.event('CastRst1', "Your target resisted the#*#", Event_CastRst)
mq.event('CastRst2', "#*#resisted your#*#!#*#", Event_CastRst)
mq.event('CastRst3', "#*#avoided your#*#!#*#", Event_CastRst)
mq.event('CastImm', "Your target cannot be#*#", Event_CastImm)
mq.event('SlowImm', "Your target is immune to changes in its attack speed", Event_CastImm)
mq.event('MissedNote', "You miss a note, bringing your#*#", Event_MissedNote)
mq.event('CastStn1', "You are stunned#*#", Event_CastStn)
mq.event('CastStn2', "You can't cast spells while stunned!#*#", Event_CastStn)
mq.event('CastStn3', "You miss a note#*#", Event_CastStn)
mq.event('CharmBroke', "Your #1# spell has worn off#*#", Event_CharmBroke)
mq.event('ResetMelee', "You cannot see your target.", Event_ResetMelee)
mq.event('WornOff', "#*#Your #1# spell has worn off of #2#.", Event_WornOff)
mq.event('Camping', "#*#more seconds to prepare your camp#*#", Event_Camping)
mq.event('GoM1', "#*#granted gift of #1# to #2#!", Event_GoM)
mq.event('GoM2', "#*#granted a gracious gift of #1# to #2#!", Event_GoM)
mq.event('LockedDoor', "It's locked and you're not holding the key.", Event_LockedDoor)
mq.event('EQBC1', "<#1#> #2#", Event_EQBC)
mq.event('EQBC2', "[#1#(msg)] #2#", Event_EQBC)
mq.event('EQBC3', "[MQ2] mb- #2#", Event_EQBC)
mq.event('EQBC4', "[MQ2] tb- #2#", Event_EQBC)
mq.event('DanChat1', "[ #*#_#1# #*# ] #2#", Event_DanChat)
mq.event('DanChat2', "[#1#(msg)] #2#", Event_DanChat)
mq.event('DanChat3', "[MQ2] tb- #2#", Event_DanChat)
mq.event('DanChat4', "[MQ2] mb- #2#", Event_DanChat)
mq.event('DanChat5', "<#1#> #2#", Event_DanChat)
mq.event('DanChat6', "MB- #2#", Event_DanChat)
mq.event('DanChat7', "TB- #2#", Event_DanChat)
mq.event('EQBC5', "MB- #2#", Event_EQBC)
mq.event('EQBC6', "TB- #2#", Event_EQBC)
mq.event('CHChain', "#*#Go #1#>>#*#", Event_CHChain)
mq.event('CHChainStop', "#*#chchain stop#*#", Event_CHChainStop)
mq.event('CHChainStart', "#*#chchain start #1#'", Event_CHChainStart)
mq.event('CHChainTank', "#*#chchain tank #1#'", Event_CHChainTank)
mq.event('CHChainPause', "#*#chchain pause #1#'", Event_CHChainPause)
mq.event('CHChainSetup', "#*#chchain #1# #2# #3# #4#", Event_CHChainSetup)
mq.event('LinkItem', "#*#LinkItem #1# #2#", Event_LinkItem)
mq.event('TooSteep', "The ground here is too steep to camp", Event_TooSteep)
mq.event('FTELock', "#*#your target is Encounter Locked to someone else#*#", Event_FTELocked)
mq.event('MountFailed', '#*#You cannot summon a mount here.#*#', Event_MountFailed)
--test
return trotslib
