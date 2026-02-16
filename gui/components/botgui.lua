local mq = require('mq')
local ImGui = require('ImGui')
local botconfig = require('lib.config')
local state = require('lib.state')
local combat_tab = require('gui.components.combat_tab')
local debuff_tab = require('gui.components.debuff_tab')
local heal_tab = require('gui.components.heal_tab')
local buff_tab = require('gui.components.buff_tab')
local cure_tab = require('gui.components.cure_tab')
local moblist_tab = require('gui.components.moblist_tab')
local status_tab = require('gui.components.status_tab')
local ok, VERSION = pcall(require, 'version')
if not ok then VERSION = 'dev' end

local M = {}

local czgui = true
local isOpen, shouldDraw = true, true
local YELLOW = ImVec4(1, 1, 0, 1)
local RED = ImVec4(1, 0, 0, 1)
local TABLE_FLAGS = bit32.bor(ImGuiTableFlags.ScrollY, ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersOuter,
    ImGuiTableFlags.BordersV, ImGuiTableFlags.SizingStretchSame, ImGuiTableFlags.Sortable,
    ImGuiTableFlags.Hideable, ImGuiTableFlags.Resizable, ImGuiTableFlags.Reorderable)

local function drawNestedTableTree(tbl)
    for k, v in pairs(tbl) do
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
            if type(v) == 'number' or type(v) == 'string' or type(v) == 'boolean' then
                local buf = tostring(v)
                local flags = ImGuiInputTextFlags.EnterReturnsTrue
                local valueChanged, newValue = ImGui.InputText('##' .. k, buf, flags)
                if newValue then
                    local num = tonumber(valueChanged)
                    local strVal = valueChanged
                    if num then
                        tbl[k] = num
                    elseif strVal == 'true' then
                        tbl[k] = true
                    elseif strVal == 'false' then
                        tbl[k] = false
                    else
                        tbl[k] = strVal
                    end
                    botconfig.ApplyAndPersist()
                end
                ImGui.TableNextColumn()
            end
        end
    end
end

local function drawOrderedNestedTableTree(tbl, order)
    for k, v in ipairs(order) do
        local section
        local value
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        if (v == 'heal' or v == 'buff' or v == 'debuff' or v == 'cure') and type(tbl[v]) == 'table' then
            local section = v
            local sectionOpen = ImGui.TreeNodeEx(tostring(section), ImGuiTreeNodeFlags.SpanFullWidth)
            if sectionOpen then
                local subOrder = botconfig.getSubOrder() and botconfig.getSubOrder()[section]
                if subOrder then
                    for _, metakey in ipairs(subOrder) do
                        if metakey ~= 'spells' and tbl[section][metakey] ~= nil then
                            ImGui.TableNextRow()
                            ImGui.TableNextColumn()
                            ImGui.TextColored(YELLOW, '%s', metakey)
                            ImGui.TableNextColumn()
                            ImGui.TextColored(RED, '%s', tostring(tbl[section][metakey]))
                            ImGui.TableNextColumn()
                        end
                    end
                end
                local spells = tbl[section].spells or {}
                local slotOrder = botconfig.getSpellSlotOrder() and botconfig.getSpellSlotOrder()[section]
                for i, entry in ipairs(spells) do
                    if type(entry) == "table" and slotOrder then
                        ImGui.TableNextRow()
                        ImGui.TableNextColumn()
                        local open = ImGui.TreeNodeEx(tostring(section) .. ' ' .. tostring(i),
                            ImGuiTreeNodeFlags.SpanFullWidth)
                        if open then
                            drawOrderedNestedTableTree(entry, slotOrder)
                            ImGui.TreePop()
                        end
                    end
                end
                ImGui.TreePop()
            end
        elseif type(tbl[v]) == 'table' then
            local open = ImGui.TreeNodeEx(tostring(v), ImGuiTreeNodeFlags.SpanFullWidth)
            if open then
                local subOrder = botconfig.getSubOrder() and botconfig.getSubOrder()[v]
                if subOrder then
                    drawOrderedNestedTableTree(tbl[v], subOrder)
                else
                    drawNestedTableTree(tbl[v])
                end
                ImGui.TreePop()
            end
        else
            ImGui.TextColored(YELLOW, '%s', v)
            ImGui.TableNextColumn()
            ImGui.TextColored(RED, '%s', tbl[v])
            ImGui.TableNextColumn()
            if type(tbl[v]) == 'number' or type(tbl[v]) == 'string' or type(tbl[v]) == 'boolean' then
                local buf = tostring(tbl[v])
                local flags = ImGuiInputTextFlags.EnterReturnsTrue
                local valueChanged, newValue = ImGui.InputText('##' .. v, buf, flags)
                if newValue then
                    local num = tonumber(valueChanged)
                    local strVal = valueChanged
                    if num then
                        tbl[v] = num
                    elseif strVal == 'true' then
                        tbl[v] = true
                    elseif strVal == 'false' then
                        tbl[v] = false
                    else
                        tbl[v] = strVal
                    end
                    botconfig.ApplyAndPersist()
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
            local sortSpecs = ImGui.TableGetSortSpecs()
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

local CONFIG_SECTIONS = { { 'settings', 'Settings' }, { 'combat', 'Combat' }, { 'heal', 'Heal' }, { 'buff', 'Buff' }, { 'debuff', 'Debuff' }, { 'cure', 'Cure' }, { 'script', 'Script' }, { 'moblist', 'Mob lists' } }

local function updateImGui()
    if not isOpen then return end
    if not czgui then return end
    ImGui.SetNextWindowPos(ImVec2(200, 200), ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowSize(ImVec2(600, 800), ImGuiCond.FirstUseEver)
    isOpen, shouldDraw = ImGui.Begin('CZBot ' .. VERSION .. '###CZBotMain', isOpen)
    if shouldDraw then
        ImGui.Spacing()
        if ImGui.BeginTabBar('CZBot GUI') then
            if ImGui.BeginTabItem('Status') then
                status_tab.draw()
                ImGui.EndTabItem()
            end
            for _, sec in ipairs(CONFIG_SECTIONS) do
                local key, label = sec[1], sec[2]
                if ImGui.BeginTabItem(label) then
                    if key == 'combat' then
                        combat_tab.draw()
                    elseif key == 'debuff' then
                        debuff_tab.draw()
                    elseif key == 'heal' then
                        heal_tab.draw()
                    elseif key == 'buff' then
                        buff_tab.draw()
                    elseif key == 'cure' then
                        cure_tab.draw()
                    elseif key == 'moblist' then
                        moblist_tab.draw()
                    else
                        local tbl = botconfig.config[key]
                        if tbl then
                            if key == 'script' then
                                drawTableTree(tbl, label, nil)
                            else
                                local order = botconfig.getSubOrder() and botconfig.getSubOrder()[key]
                                drawTableTree(tbl, label, order)
                            end
                        end
                    end
                    ImGui.EndTabItem()
                end
            end
            ImGui.EndTabBar()
        end
        if botconfig.IsDirty() then
            botconfig.Save(botconfig.getPath())
            botconfig.ClearDirty()
        end
    end
    ImGui.End()
end

local function UIEnable()
    isOpen = true
    czgui = true
end

function M.getUpdateFn()
    return updateImGui
end

M.UIEnable = UIEnable

return M
