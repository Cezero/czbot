-- Status tab: status line, run state table, and doXXX flag On/Off buttons.

local ImGui = require('ImGui') ---@cast ImGui ImGui
local Icons = require('mq.ICONS')
local botconfig = require('lib.config')
local state = require('lib.state')

local M = {}

local YELLOW = ImVec4(1, 1, 0, 1)
local RED = ImVec4(1, 0, 0, 1)
local GREEN = ImVec4(0, 0.8, 0, 1)
local BLACK = ImVec4(0, 0, 0, 1)

local DO_FLAGS = {
    { key = 'dopull', label = 'Pull' },
    { key = 'dodebuff', label = 'Debuff' },
    { key = 'doheal', label = 'Heal' },
    { key = 'dobuff', label = 'Buff' },
    { key = 'docure', label = 'Cure' },
    { key = 'domelee', label = 'Melee' },
    { key = 'dopet', label = 'Pet' },
    { key = 'doraid', label = 'Raid' },
    { key = 'dodrag', label = 'Drag' },
    { key = 'domount', label = 'Mount' },
    { key = 'dosit', label = 'Sit' },
}

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
    if runState == 'melee' then return 'Melee' end
    if runState == 'engage_return_follow' then return 'Returning to follow' end
    if runState == 'zone_changing' then return 'Zone changing' end
    if runState == 'chchain' then return 'CH chain' end
    if runState == 'load_raid' then return 'Loading raid' end
    if runState == 'buffs_populate_wait' or runState == 'buffs_resume' or runState == 'cures_resume' or runState:match('_resume') then return
    'Buffs/Cures' end
    if rc.campstatus then return 'Idle at camp' end
    if rc.followid and rc.followid > 0 then return 'Following' end
    return 'Idle'
end

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

function M.draw()
    ImGui.TextColored(YELLOW, '%s', getStatusLine())
    ImGui.SameLine()
    local exitButtonLabel = Icons.FA_POWER_OFF .. ' Exit'
    local exitButtonWidth = (select(1, ImGui.CalcTextSize(exitButtonLabel)) or 0) + ImGui.GetStyle().FramePadding.x * 2
    local avail = ImGui.GetContentRegionAvail()
    if avail > 0 then
        ImGui.SetCursorPosX(ImGui.GetCursorPosX() + avail - exitButtonWidth)
    end
    ImGui.PushStyleColor(ImGuiCol.Button, BLACK)
    ImGui.PushStyleColor(ImGuiCol.Text, RED)
    if ImGui.Button(exitButtonLabel) then
        state.getRunconfig().terminate = true
    end
    ImGui.PopStyleColor(2)
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
    ImGui.Spacing()
    local style = ImGui.GetStyle()
    ImGui.PushStyleVar(ImGuiStyleVar.CellPadding, style.CellPadding.x, style.CellPadding.y + 3)
    if ImGui.BeginTable('flags table', 5, ImGuiTableFlags.None, -1, 0) then
        for _, entry in ipairs(DO_FLAGS) do
            ImGui.TableNextColumn()
            local value = botconfig.config.settings[entry.key] == true
            local icon = value and Icons.FA_TOGGLE_ON or Icons.FA_TOGGLE_OFF
            local labelW = select(1, ImGui.CalcTextSize(entry.label)) or 0
            local iconW = (select(1, ImGui.CalcTextSize(icon)) or 0) + style.FramePadding.x * 2
            local totalW = labelW + style.ItemSpacing.x + iconW
            local avail = ImGui.GetContentRegionAvail()
            if avail > 0 and totalW > 0 and avail > totalW then
                ImGui.SetCursorPosX(ImGui.GetCursorPosX() + avail - totalW)
            end
            ImGui.Text('%s', entry.label)
            ImGui.SameLine()
            ImGui.PushStyleColor(ImGuiCol.Button, BLACK)
            ImGui.PushStyleColor(ImGuiCol.Text, value and GREEN or RED)
            if ImGui.SmallButton(icon .. '##' .. entry.key) then
                botconfig.config.settings[entry.key] = not value
                botconfig.ApplyAndPersist()
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(value and 'On' or 'Off')
            end
            ImGui.PopStyleColor(2)
        end
        ImGui.EndTable()
    end
    ImGui.PopStyleVar(1)
end

return M
