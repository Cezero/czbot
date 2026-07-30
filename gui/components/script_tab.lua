-- Advanced tab: Confirm before Exit, MA Anchor / ma_list / mt_list, and a type-aware editor for
-- the raw config.script table. Each leaf is rendered with a control matched to its Lua type -- a
-- checkbox for booleans, an Enter-to-commit numeric field for numbers, and a text field for strings
-- -- so edits PRESERVE the value's type. The previous editor pushed every value through
-- tostring/tonumber, which silently turned the string "123" into a number and "true" into a
-- boolean. Numbers/strings commit on Enter (no per-keystroke file writes); booleans commit on click.

local mq = require('mq')
local ImGui = require('ImGui')
local botconfig = require('lib.config')
local state = require('lib.state')
local rolelists = require('lib.rolelists')
local tankrole = require('lib.tankrole')
local inputs = require('gui.widgets.inputs')
local theme = require('gui.widgets.theme')
local section = require('gui.widgets.section')
local name_list = require('gui.widgets.name_list')

local M = {}

local YELLOW, WHITE, GREEN, RED, LIGHT_GREY =
    theme.YELLOW, theme.WHITE, theme.GREEN, theme.RED, theme.LIGHT_GREY
local NUMERIC_INPUT_WIDTH = theme.WIDTHS.numeric

local ImGuiInputTextFlags = ImGuiInputTextFlags or {}
local ENTER = ImGuiInputTextFlags.EnterReturnsTrue or 0
local DECIMAL = bit32.bor(ImGuiInputTextFlags.CharsDecimal or 0, ENTER)

local TABLE_FLAGS = bit32.bor(ImGuiTableFlags.ScrollY, ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersOuter,
    ImGuiTableFlags.BordersV, ImGuiTableFlags.SizingStretchSame, ImGuiTableFlags.Sortable,
    ImGuiTableFlags.Hideable, ImGuiTableFlags.Resizable, ImGuiTableFlags.Reorderable)

local EDIT_WIDTH = 160

local function runConfigLoaders()
    botconfig.ApplyAndPersist()
end

local function isPcName(name)
    if not name or name == '' then return false end
    return mq.TLO.Spawn('pc =' .. name).Type() == 'PC'
end

-- "Add target" candidate: the current target's clean name, but only when it's a PC.
local function currentPcTargetName()
    if mq.TLO.Target.ID() and mq.TLO.Target.ID() > 0 and mq.TLO.Target.Type() == 'PC' then
        return mq.TLO.Target.CleanName()
    end
    return nil
end

local function drawMaAnchorSection()
    section.header('MA anchor settings')
    ImGui.TextColored(WHITE, '%s', 'MA anchor: ')
    ImGui.SameLine(0, 2)
    local maAnchorOn = botconfig.config.settings.maCampAnchor ~= false
    local maAnchorChecked, maAnchorToggled = ImGui.Checkbox('##advanced_ma_camp_anchor', maAnchorOn)
    if maAnchorToggled then
        botconfig.config.settings.maCampAnchor = maAnchorChecked
        runConfigLoaders()
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'When on, mob bubble centers on nearby MA and injects MA ATTACK targets into the mob list.')
    end
    ImGui.SameLine()
    ImGui.TextColored(WHITE, '%s', 'MA leash: ')
    ImGui.SameLine(0, 2)
    ImGui.SetNextItemWidth(NUMERIC_INPUT_WIDTH)
    local maLeashVal = botconfig.config.settings.maAnchorLeash or botconfig.config.settings.acleash or 75
    local maLeashNew, maLeashCh = inputs.boundedInt('advanced_ma_anchor_leash', maLeashVal, 1, 10000, 5,
        '##advanced_ma_anchor_leash')
    if maLeashCh then
        botconfig.config.settings.maAnchorLeash = maLeashNew
        tankrole.bumpLeashGen()
        runConfigLoaders()
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Max MA distance for mob bubble anchor, combat inject, and ma_list/mt_list fallback (defaults to Radius).')
    end
    ImGui.Spacing()
end

local function drawRoleListSection(listType, runconfigKey, label)
    local rc = state.getRunconfig()
    if type(rc[runconfigKey]) ~= 'table' then rc[runconfigKey] = {} end
    name_list.draw({
        id = 'advanced_' .. listType,
        label = label,
        list = rc[runconfigKey],
        reorder = true,
        addNoun = 'PC name',
        validateName = isPcName,
        getTargetName = currentPcTargetName,
        onChange = function(action) rolelists.process(listType, action) end,
    })
end

-- Color the read-only Value cell by type so booleans/numbers/strings are scannable at a glance.
local function valueColor(v)
    local t = type(v)
    if t == 'boolean' then return v and GREEN or RED end
    if t == 'number' then return WHITE end
    return LIGHT_GREY
end

-- Draw the type-appropriate edit control for one leaf value tbl[k]. Returns true if it changed.
local function drawLeafEditor(tbl, k, v, id)
    local t = type(v)
    if t == 'boolean' then
        local nv, pressed = ImGui.Checkbox('##' .. id, v)
        if pressed then
            tbl[k] = nv
            return true
        end
    elseif t == 'number' then
        ImGui.SetNextItemWidth(EDIT_WIDTH)
        local nv, submitted = ImGui.InputText('##' .. id, tostring(v), DECIMAL)
        if submitted then
            local num = tonumber(nv)
            if num then -- ignore non-numeric input; keep prior value
                tbl[k] = num
                return true
            end
        end
    elseif t == 'string' then
        ImGui.SetNextItemWidth(EDIT_WIDTH)
        local nv, submitted = ImGui.InputText('##' .. id, v, ENTER)
        if submitted then
            tbl[k] = nv
            return true
        end
    else
        ImGui.TextColored(LIGHT_GREY, '%s', '(' .. t .. ')')
    end
    return false
end

local function drawNestedTableTree(tbl, path)
    for k, v in pairs(tbl) do
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        local id = path .. '.' .. tostring(k)
        if type(v) == 'table' then
            local open = ImGui.TreeNodeEx(tostring(k), ImGuiTreeNodeFlags.SpanFullWidth)
            if open then
                drawNestedTableTree(v, id)
                ImGui.TreePop()
            end
        else
            ImGui.TextColored(YELLOW, '%s', tostring(k))
            ImGui.TableNextColumn()
            ImGui.TextColored(valueColor(v), '%s', tostring(v))
            ImGui.TableNextColumn()
            if drawLeafEditor(tbl, k, v, id) then
                botconfig.ApplyAndPersist()
            end
        end
    end
end

local function drawScriptTree(tbl)
    ImGui.SetNextItemOpen(true, ImGuiCond.FirstUseEver)
    if ImGui.TreeNode('Script') then
        if ImGui.BeginTable('script table', 3, TABLE_FLAGS, -1, -1) then
            ImGui.TableSetupScrollFreeze(0, 1)
            ImGui.TableSetupColumn('Key', ImGuiTableColumnFlags.DefaultSort, 2, 1)
            ImGui.TableSetupColumn('Value', ImGuiTableColumnFlags.DefaultSort, 2, 2)
            ImGui.TableSetupColumn('Edit', ImGuiTableColumnFlags.DefaultSort, 2, 3)
            ImGui.TableHeadersRow()
            drawNestedTableTree(tbl, 'script')
            ImGui.EndTable()
        end
        ImGui.TreePop()
    end
end

function M.draw()
    local confirmOn = (botconfig.config.settings.confirmExit == true)
    local confirmVal, confirmPressed = ImGui.Checkbox('Confirm before Exit##confirm_exit', confirmOn)
    if confirmPressed then
        botconfig.config.settings.confirmExit = confirmVal
        botconfig.ApplyAndPersist()
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('When enabled, the Exit button asks for confirmation before stopping CZBot.')
    end
    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    drawMaAnchorSection()
    ImGui.TextWrapped(
        'Fallback lists are stored in cz_common.lua. After editing lists, run /cz reloadcommon on other bots. Order matters: first alive, in-zone name within MA leash wins when the assigned MA/MT is unavailable.')
    ImGui.Spacing()
    drawRoleListSection('ma', 'MaList', 'Main Assist fallback list (ma_list)')
    drawRoleListSection('mt', 'MtList', 'Main Tank fallback list (mt_list)')
    drawRoleListSection('ot', 'OtList', 'Offtank watch list (ot_list)')

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    local tbl = botconfig.config.script
    if not tbl then
        ImGui.TextColored(LIGHT_GREY, '%s', 'No script config loaded.')
        return
    end
    ImGui.TextWrapped(
        'Raw config.script values. Edits preserve each value\'s type and save immediately: booleans are checkboxes, numbers and strings commit on Enter.')
    ImGui.Spacing()
    drawScriptTree(tbl)
end

return M
