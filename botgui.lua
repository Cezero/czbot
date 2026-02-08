local mq = require('mq')
local ImGui = require('ImGui')
local botconfig = require('lib.config')
local mobfilter = require('lib.mobfilter')
local botmelee = require('botmelee')
local botpull = require('botpull')
local botcast = require('botcast')
local state = require('lib.state')

local M = {}

local tbgui = false
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
                    botconfig.RunConfigLoaders()
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

-- Build a short human-readable status line from run state and runconfig.
local function getStatusLine()
    local rc = state.getRunconfig()
    if rc.statusMessage and rc.statusMessage ~= '' then return rc.statusMessage end
    local runState = state.getRunState()
    if runState == 'pulling' then return 'Pulling' end
    if runState == 'dragging' then
        local p = state.getRunStatePayload()
        return p and p.phase and ('Dragging corpse (' .. p.phase .. ')') or 'Dragging corpse'
    end
    if runState == 'camp_return' then return 'Returning to camp' end
    if runState == 'casting' then return 'Casting' end
    if runState == 'loading_gem' then return 'Loading gem' end
    if runState == 'melee' then return 'Melee' end
    if runState == 'engage_return_follow' then return 'Returning to follow' end
    if runState == 'zone_changing' then return 'Zone changing' end
    if runState == 'chchain' then return 'CH chain' end
    if runState == 'load_raid' then return 'Loading raid' end
    if runState == 'buffs_populate_wait' or runState == 'buffs_resume' or runState == 'cures_resume' then return 'Buffs/Cures' end
    if rc.campstatus then return 'Idle at camp' end
    if rc.followid and rc.followid > 0 then return 'Following' end
    return 'Idle'
end

-- Build key/value pairs for Status tab (read-only).
-- statusMessage (shown in getStatusLine) covers current cast and activity; no Payload or Current cast rows.
local function getStatusRows()
    local rc = state.getRunconfig()
    local runState = state.getRunState()
    local rows = {}
    rows[#rows + 1] = { 'Run state', runState }
    if rc.followid and rc.followid > 0 then
        rows[#rows + 1] = { 'Follow', rc.followname or tostring(rc.followid) }
    elseif rc.campstatus then
        local campVal = 'on'
        if rc.makecamp and (rc.makecamp.x or rc.makecamp.y or rc.makecamp.z) then
            campVal = string.format('on at %.1f, %.1f, %.1f', rc.makecamp.x or 0, rc.makecamp.y or 0, rc.makecamp.z or 0)
        end
        rows[#rows + 1] = { 'Camp', campVal }
    end
    rows[#rows + 1] = { 'Mob count', tostring(rc.MobCount or 0) }
    return rows
end

local function drawStatusTab()
    ImGui.TextColored(YELLOW, '%s', getStatusLine())
    ImGui.Spacing()
    if ImGui.BeginTable('status table', 2, bit32.bor(ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersOuter)) then
        ImGui.TableSetupColumn('Key', 0, 0.35)
        ImGui.TableSetupColumn('Value', 0, 0.65)
        ImGui.TableHeadersRow()
        for _, row in ipairs(getStatusRows()) do
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.TextColored(YELLOW, '%s', row[1])
            ImGui.TableNextColumn()
            ImGui.TextColored(RED, '%s', tostring(row[2]))
        end
        ImGui.EndTable()
    end
end

local CONFIG_SECTIONS = { { 'settings', 'Settings' }, { 'pull', 'Pull' }, { 'melee', 'Melee' }, { 'heal', 'Heal' }, { 'buff', 'Buff' }, { 'debuff', 'Debuff' }, { 'cure', 'Cure' }, { 'script', 'Script' } }

local function updateImGui()
    if not isOpen then return end
    if not tbgui then return end
    local window_settings = {
        x = 200,
        y = 200,
        w = 600,
        h = 800,
        collapsed = false
    }
    ImGui.SetNextWindowPos(ImVec2(window_settings.x, window_settings.y), ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowSize(ImVec2(window_settings.w, window_settings.h), ImGuiCond.FirstUseEver)
    isOpen, shouldDraw = ImGui.Begin(botconfig.getPath(), isOpen)
    if shouldDraw then
        if ImGui.Button('End CZBot') then
            state.getRunconfig().terminate = true
        end
        ImGui.SameLine()
        if ImGui.Button('Save Config') then
            botconfig.Save(botconfig.getPath())
            botconfig.RunConfigLoaders()
        end
        ImGui.SameLine()
        if ImGui.Button('Save Common') then
            mobfilter.process('exclude', 'save')
        end
        ImGui.SameLine()
        if ImGui.Button('Open Config') then
            os.execute('start "" "' .. botconfig.getPath() .. '"')
        end
        ImGui.Spacing()
        if ImGui.BeginTabBar('CZBot GUI') then
            if ImGui.BeginTabItem('Status') then
                drawStatusTab()
                ImGui.EndTabItem()
            end
            for _, sec in ipairs(CONFIG_SECTIONS) do
                local key, label = sec[1], sec[2]
                if ImGui.BeginTabItem(label) then
                    local tbl = botconfig.config[key]
                    if tbl then
                        if key == 'script' then
                            drawTableTree(tbl, label, nil)
                        elseif key == 'heal' or key == 'buff' or key == 'debuff' or key == 'cure' then
                            drawTableTree({ [key] = tbl }, label, { key })
                        else
                            local order = botconfig.getSubOrder() and botconfig.getSubOrder()[key]
                            drawTableTree(tbl, label, order)
                        end
                    end
                    ImGui.EndTabItem()
                end
            end
            ImGui.EndTabBar()
        end
    end
    ImGui.End()
end

local function UIEnable()
    isOpen = true
    tbgui = true
end

function M.getUpdateFn()
    return updateImGui
end

M.UIEnable = UIEnable

return M
