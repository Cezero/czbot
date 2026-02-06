---@class ConfigSettings
---@field dodebuff boolean|nil
---@field doheal boolean|nil
---@field dobuff boolean|nil
---@field docure boolean|nil
---@field domelee boolean|nil
---@field dopull boolean|nil
---@field doraid boolean|nil
---@field dodrag boolean|nil
---@field domount boolean|nil
---@field mountcast boolean|nil
---@field dosit boolean|nil
---@field sitmana number|nil
---@field sitendur number|nil
---@field TankName string|nil
---@field AssistName string|nil
---@field TargetFilter string|nil
---@field petassist boolean|nil
---@field acleash number|nil
---@field zradius number|nil
---@field spelldb string|nil
---@field dopet boolean|nil

---@class ConfigPull
---@field pullability string|nil
---@field abilityrange number|nil
---@field radius number|nil
---@field zrange number|nil
---@field maxlevel number|nil
---@field minlevel number|nil
---@field chainpullhp number|nil
---@field chainpullcnt number|nil
---@field mana number|nil
---@field manaclass string|nil
---@field leash number|nil
---@field usepriority boolean|nil
---@field hunter boolean|nil

---@class ConfigMelee
---@field assistpct number|nil
---@field stickcmd string|nil
---@field offtank boolean|nil
---@field minmana number|nil
---@field otoffset number|nil

---@class ConfigHeal
---@field spells table[]|nil
---@field rezoffset number|nil
---@field interruptlevel number|nil
---@field xttargets number|nil

---@class ConfigBuff
---@field spells table[]|nil

---@class ConfigDebuff
---@field spells table[]|nil

---@class ConfigCure
---@field spells table[]|nil
---@field prioritycure boolean|nil

---@class Config
---@field settings ConfigSettings|nil
---@field pull ConfigPull|nil
---@field melee ConfigMelee|nil
---@field heal ConfigHeal|nil
---@field buff ConfigBuff|nil
---@field debuff ConfigDebuff|nil
---@field cure ConfigCure|nil
---@field script table|nil

local mq = require('mq')
local state = require('lib.state')
local M = {}
---@type Config
M.config = {}
M._configLoaders = {}
M._common = nil

local keyOrder = { 'settings', 'pull', 'melee', 'heal', 'buff', 'debuff', 'cure', 'script' }

local subOrder = {
    settings = { 'dodebuff', 'doheal', 'dobuff', 'docure', 'domelee', 'dopull', 'doraid', 'dodrag', 'domount', 'mountcast', 'dosit', 'sitmana', 'sitendur', 'TankName', 'AssistName', 'TargetFilter', 'petassist', 'acleash', 'zradius' },
    pull = { 'pullability', 'abilityrange', 'radius', 'zrange', 'maxlevel', 'minlevel', 'chainpullhp', 'chainpullcnt', 'mana', 'manaclass', 'leash', 'usepriority', 'hunter' },
    melee = { 'assistpct', 'stickcmd', 'offtank', 'minmana', 'otoffset' },
    heal = { 'rezoffset', 'interruptlevel', 'xttargets', 'spells' },
    buff = { 'spells' },
    debuff = { 'spells' },
    cure = { 'prioritycure', 'spells' },
    script = {}
}

local spellSlotOrder = {
    heal = { 'gem', 'spell', 'alias', 'announce', 'minmana', 'minmanapct', 'maxmanapct', 'tarcnt', 'bands', 'priority', 'precondition' },
    buff = { 'gem', 'spell', 'alias', 'announce', 'minmana', 'tarcnt', 'bands', 'spellicon', 'precondition' },
    debuff = { 'gem', 'spell', 'alias', 'announce', 'minmana', 'tarcnt', 'bands', 'charmnames', 'recast', 'delay', 'precondition' },
    cure = { 'gem', 'spell', 'alias', 'announce', 'minmana', 'curetype', 'tarcnt', 'bands', 'priority', 'precondition' },
}

function M.getPath()
    return mq.configDir .. '\\cz_' .. mq.TLO.Me.CleanName() .. '.lua'
end

function M.getCommon()
    if M._common == nil then M.loadCommon() end
    return M._common
end

function M.loadCommon()
    local commonData, errr = loadfile(mq.configDir .. '/' .. 'TBCommon.lua')
    if errr then
        M._common = {}
        mq.pickle('TBCommon.lua', M._common)
    elseif commonData then
        M._common = commonData()
        if not M._common then M._common = {} end
    else
        M._common = {}
    end
    return M._common
end

function M.saveCommon()
    if M._common then mq.pickle('TBCommon.lua', M._common) end
end

function M.getKeyOrder()
    return keyOrder
end

function M.getSubOrder()
    return subOrder
end

function M.getSpellSlotOrder()
    return spellSlotOrder
end

function M.getSpellEntry(section, index)
    if not M.config[section] or not M.config[section].spells then return nil end
    return M.config[section].spells[index]
end

function M.getSpellCount(section)
    if not M.config[section] or not M.config[section].spells then return 0 end
    return #M.config[section].spells
end

function M.RegisterConfigLoader(fn)
    table.insert(M._configLoaders, fn)
end

function M.RunConfigLoaders()
    for _, fn in ipairs(M._configLoaders) do
        fn()
    end
end

local function sanitizeConfigFile(filepath)
    local file, err = io.open(filepath, "r")
    if not file then
        print("Error opening file:", err)
        return nil
    end
    local content = file:read("*all")
    file:close()
    content = content:gsub("%['%w+'%]%s*=%s*table: 0x[%w]+%s*,?", function(entry)
        print("Sanitizing invalid entry:", entry)
        return entry:gsub("table: 0x[%w]+", "nil")
    end)
    local configData, loadErr = load(content)
    if not configData then
        print("Error loading sanitized config:", loadErr)
        return nil
    end
    print("Config repaired and reloaded successfully")
    return configData()
end

local function writeConfigToFile(config, filename)
    local file = io.open(filename, "w")
    if not file then
        return false, "Could not open file for writing."
    end

    local function writeBands(bands, indent)
        if type(bands) ~= "table" then return end
        file:write(indent .. "['bands'] = {\n")
        file:flush()
        for _, band in ipairs(bands) do
            if type(band) == "table" then
                file:write(indent .. "  {\n")
                if type(band.class) == "table" then
                    file:write(indent .. "    ['class'] = { ")
                    local parts = {}
                    for _, c in ipairs(band.class) do
                        parts[#parts + 1] = "'" .. tostring(c):gsub("'", "\\'") .. "'"
                    end
                    file:write(table.concat(parts, ", "))
                    file:write(" },\n")
                end
                if band.min ~= nil then
                    file:write(indent .. "    ['min'] = " .. tonumber(band.min) .. ",\n")
                end
                if band.max ~= nil then
                    file:write(indent .. "    ['max'] = " .. tonumber(band.max) .. ",\n")
                end
                file:write(indent .. "  },\n")
            end
        end
        file:write(indent .. "},\n")
        file:flush()
    end

    local function writesubTable(t, order2, indent)
        indent = indent or ""
        if type(order2) == "table" then
            local value = ''
            local valueStr = nil
            for _, key in ipairs(order2) do
                value = t[key]
                if key == 'bands' and type(value) == "table" then
                    writeBands(value, indent)
                elseif type(value) == "table" then
                    print("detected a corrupted value for:", key, " = ", value)
                    print("setting ", key, " to nil, please check your config")
                    valueStr = nil
                    file:write(indent .. "['" .. key .. "'] =  nil ,\n")
                    file:flush()
                else
                    if tonumber(value) then
                        valueStr = tonumber(value)
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
                        file:write(indent .. "['" .. key .. "'] = " .. valueStr .. ",\n")
                        file:flush()
                    end
                end
            end
        end
    end

    local function writeTable(t, order1)
        local indent = ""
        if type(order1) == "table" then
            local value = ''
            for _, key in ipairs(order1) do
                value = t[key]
                if type(value) == "table" then
                    file:write(indent .. "['" .. key .. "'] = {\n")
                    file:flush()
                    if key == 'heal' or key == 'buff' or key == 'debuff' or key == 'cure' then
                        for _, subkey in ipairs(subOrder[key]) do
                            if subkey ~= 'spells' then
                                local subval = value[subkey]
                                if tonumber(subval) then
                                    file:write(indent .. "  ['" .. subkey .. "'] = ", tonumber(subval), ",\n")
                                elseif subval == true then
                                    file:write(indent .. "  ['" .. subkey .. "'] = true,\n")
                                elseif subval == false then
                                    file:write(indent .. "  ['" .. subkey .. "'] = false ,\n")
                                else
                                    local subvalStr = type(subval) == "string" and '"' .. subval .. '"' or
                                    tostring(subval)
                                    file:write(indent .. "  ['" .. subkey .. "'] = " .. subvalStr .. ",\n")
                                end
                                file:flush()
                            else
                                file:write(indent .. "  ['spells'] = {\n")
                                file:flush()
                                local spells = value.spells or {}
                                for si, entry in ipairs(spells) do
                                    if type(entry) == "table" then
                                        file:write(indent .. "    {\n")
                                        file:flush()
                                        writesubTable(entry, spellSlotOrder[key], indent .. "      ")
                                        file:write(indent .. "    },\n")
                                        file:flush()
                                    end
                                end
                                file:write(indent .. "  },\n")
                                file:flush()
                            end
                        end
                    else
                        writesubTable(value, subOrder[key], indent .. "  ")
                    end
                    file:write(indent .. "},\n")
                    file:flush()
                else
                    local valueStr = type(value) == "string" and '"' .. value .. '"' or tostring(value)
                    if tonumber(value) then
                        file:write(indent .. "['" .. key .. "'] = ", tonumber(value), ",\n")
                    elseif value == true then
                        file:write(indent .. "['" .. key .. "'] = true,\n")
                    elseif value == false then
                        file:write(indent .. "['" .. key .. "'] = false ,\n")
                    else
                        file:write(indent .. "['" .. key .. "'] = " .. valueStr .. ",\n")
                    end
                    file:flush()
                end
            end
        end
    end

    file:write("StoredConfig =  {\n")
    file:flush()
    writeTable(config, keyOrder)
    file:write("}\n")
    file:flush()
    file:write("return StoredConfig")
    file:flush()
    file:close()
    return true
end

function M.Load(path)
    local newconfig
    local configData, err = loadfile(path)
    if err then
        print('load failed')
        newconfig = sanitizeConfigFile(path)
    elseif configData then
        newconfig = configData()
    end
    if not newconfig then
        print('making new config')
        newconfig = {}
    end
    for k in pairs(M.config) do
        M.config[k] = nil
    end
    for k, v in pairs(newconfig) do
        M.config[k] = v
    end
    if not M.config.settings then M.config.settings = {} end
    if not M.config.melee then M.config.melee = {} end
    if not M.config.pull then M.config.pull = {} end
    if not M.config.heal then M.config.heal = {} end
    if not M.config.buff then M.config.buff = {} end
    if not M.config.debuff then M.config.debuff = {} end
    if not M.config.script then M.config.script = {} end
    if not M.config.cure then M.config.cure = {} end
    for _, section in ipairs({ 'heal', 'buff', 'debuff', 'cure' }) do
        if not M.config[section].spells then M.config[section].spells = {} end
    end
    if (M.config.settings.domelee == nil) then M.config.settings.domelee = false end
    if (M.config.settings.doheal == nil) then M.config.settings.doheal = false end
    if (M.config.settings.dobuff == nil) then M.config.settings.dobuff = false end
    if (M.config.settings.dodebuff == nil) then M.config.settings.dodebuff = false end
    if (M.config.settings.docure == nil) then M.config.settings.docure = false end
    if (M.config.settings.dopull == nil) then M.config.settings.dopull = false end
    if (M.config.settings.doraid == nil) then M.config.settings.doraid = false end
    if (M.config.settings.dodrag == nil) then M.config.settings.dodrag = false end
    if (M.config.settings.domount == nil) then M.config.settings.domount = false end
    if (M.config.settings.mountcast == nil) then M.config.settings.mountcast = false end
    if (M.config.settings.dosit == nil) then M.config.settings.dosit = true end
    if (M.config.settings.sitmana == nil) then M.config.settings.sitmana = 90 end
    if (M.config.settings.sitendur == nil) then M.config.settings.sitendur = 90 end
    if (M.config.settings.acleash == nil) then M.config.settings.acleash = 75 end
    if (M.config.settings.zradius == nil) then M.config.settings.zradius = 75 end
    if (M.config.settings.TankName == nil) then M.config.settings.TankName = "manual" end
    if (M.config.settings.TargetFilter == nil) then M.config.settings.TargetFilter = '0' end
    if (M.config.settings.petassist == nil) then M.config.settings.petassist = false end
    if (M.config.settings.spelldb == nil) then M.config.settings.spelldb = 'spells.db' end
end

function M.Save(path)
    return writeConfigToFile(M.config, path)
end

function M.WriteToFile(config, path)
    return writeConfigToFile(config, path)
end

-- Full config load: main config, subsystem configs, script order, TBCommon. Immune data is owned by lib/immune.lua.
function M.LoadConfig()
    local path = M.getPath()
    M.Load(path)
    M.RunConfigLoaders()
    ---@type RunConfig
    local runconfig = state.getRunconfig()
    for k, v in ipairs(runconfig.ScriptList) do
        runconfig.SubOrder[v] = v
    end
    for k, v in ipairs(runconfig.ScriptList) do
        table.insert(M.getSubOrder().script, v)
    end
    M.Save(path)
    M.loadCommon()
end

return M
