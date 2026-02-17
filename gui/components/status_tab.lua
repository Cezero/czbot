-- Status tab: status line, Camp section, and doXXX flag On/Off buttons.

local ImGui = require('ImGui')
local Icons = require('mq.ICONS')
local botconfig = require('lib.config')
local state = require('lib.state')
local tankrole = require('lib.tankrole')
local inputs = require('gui.widgets.inputs')

local M = {}

local function runConfigLoaders()
    botconfig.ApplyAndPersist()
end

local YELLOW = ImVec4(1, 1, 0, 1)
local RED = ImVec4(1, 0, 0, 1)
local GREEN = ImVec4(0, 0.8, 0, 1)
local BLACK = ImVec4(0, 0, 0, 1)
local WHITE = ImVec4(1, 1, 1, 1)
local LIGHT_GREY = ImVec4(0.75, 0.75, 0.75, 1)

local FLAGS_COLUMN_WIDTH = 65
local FLAGS_ROW_PADDING_Y = 2
local FLAGS_PANEL_WIDTH = 145
local NUMERIC_INPUT_WIDTH = 80

local DO_FLAGS = {
    { key = 'dopull', label = 'Pull' },
    { key = 'dodebuff', label = 'Debuff' },
    { key = 'doheal', label = 'Heal' },
    { key = 'dobuff', label = 'Buff' },
    { key = 'docure', label = 'Cure' },
    { key = 'domelee', label = 'Melee' },
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

function M.draw()
    ImGui.TextColored(YELLOW, '%s', getStatusLine())
    ImGui.SameLine()
    local style = ImGui.GetStyle()
    local exitLabelW = (select(1, ImGui.CalcTextSize('Exit')) or 0)
    local exitIconW = (select(1, ImGui.CalcTextSize(Icons.FA_POWER_OFF)) or 0) + style.FramePadding.x * 2
    local exitTotalW = exitLabelW + style.ItemSpacing.x + exitIconW
    local avail = ImGui.GetContentRegionAvail()
    if avail > 0 then
        ImGui.SetCursorPosX(ImGui.GetCursorPosX() + avail - exitTotalW)
    end
    ImGui.Text('%s', 'Exit')
    ImGui.SameLine()
    ImGui.PushStyleColor(ImGuiCol.Button, BLACK)
    ImGui.PushStyleColor(ImGuiCol.Text, RED)
    if ImGui.SmallButton(Icons.FA_POWER_OFF .. '##exit') then
        state.getRunconfig().terminate = true
    end
    ImGui.PopStyleColor(2)
    ImGui.Spacing()
    if ImGui.BeginTable('flags wrapper', 2, ImGuiTableFlags.None) then
        ImGui.TableSetupColumn('', ImGuiTableColumnFlags.WidthStretch, 0)
        ImGui.TableSetupColumn('', ImGuiTableColumnFlags.WidthFixed, FLAGS_PANEL_WIDTH)
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        -- Assist Name and Tank Name (same row, before Follow/Camp)
        local rc = state.getRunconfig()
        local assistName = tankrole.GetAssistTargetName()
        local assistDisplay = (assistName and assistName ~= '') and assistName or '—'
        if rc.AssistName == 'automatic' then
            assistDisplay = assistDisplay .. ' (auto)'
        end
        local tankName = tankrole.GetMainTankName()
        local tankDisplay = (tankName and tankName ~= '') and tankName or '—'
        if (botconfig.config.settings.TankName or rc.TankName) == 'automatic' then
            tankDisplay = tankDisplay .. ' (auto)'
        end
        ImGui.TextColored(WHITE, '%s', 'Assist Name: ')
        ImGui.SameLine(0, 2)
        ImGui.TextColored(LIGHT_GREY, '%s', assistDisplay)
        ImGui.SameLine()
        ImGui.TextColored(WHITE, '%s', 'Tank Name: ')
        ImGui.SameLine(0, 2)
        ImGui.TextColored(LIGHT_GREY, '%s', tankDisplay)
        ImGui.Spacing()
        -- Follow section
        local leftX, lineY = ImGui.GetCursorScreenPos()
        local availX = select(1, ImGui.GetContentRegionAvail())
        local followLabel = 'Follow'
        local textW, textH = ImGui.CalcTextSize(followLabel)
        local startX = ImGui.GetCursorPosX()
        ImGui.SetCursorPosX(startX + availX / 2 - textW / 2)
        ImGui.Text('%s', followLabel)
        local tMinX, tMinY = ImGui.GetItemRectMin()
        local tMaxX, tMaxY = ImGui.GetItemRectMax()
        local midY = (tMinY + tMaxY) / 2
        local pad = 4
        local rightX = leftX + availX
        local drawList = ImGui.GetWindowDrawList()
        local col = ImGui.GetColorU32(51/255, 105/255, 173/255, 1.0)
        local thickness = 1.0
        drawList:AddLine(ImVec2(leftX, midY), ImVec2(tMinX - pad, midY), col, thickness)
        drawList:AddLine(ImVec2(tMaxX + pad, midY), ImVec2(rightX, midY), col, thickness)
        ImGui.Spacing()
        ImGui.TextColored(WHITE, '%s', 'Following: ')
        ImGui.SameLine(0, 2)
        if rc.followid and rc.followid > 0 and rc.followname and rc.followname ~= '' then
            ImGui.TextColored(LIGHT_GREY, '%s', rc.followname)
        else
            ImGui.TextColored(LIGHT_GREY, '%s', 'unset')
        end
        ImGui.TextColored(WHITE, '%s', 'Distance: ')
        ImGui.SameLine(0, 2)
        ImGui.SetNextItemWidth(NUMERIC_INPUT_WIDTH)
        local followdistanceVal = botconfig.config.settings.followdistance or 35
        local followDistNew, followDistCh = inputs.boundedInt('follow_distance', followdistanceVal, 1, 500, 5, '##follow_distance')
        if followDistCh then botconfig.config.settings.followdistance = followDistNew; runConfigLoaders() end
        if ImGui.IsItemHovered() then ImGui.SetTooltip('Follow distance (units) before moving to catch up.') end
        ImGui.Spacing()
        -- Camp section in left column (same style as Pulling on combat_tab)
        leftX, lineY = ImGui.GetCursorScreenPos()
        availX = select(1, ImGui.GetContentRegionAvail())
        local campLabel = 'Camp'
        textW, textH = ImGui.CalcTextSize(campLabel)
        local startX = ImGui.GetCursorPosX()
        ImGui.SetCursorPosX(startX + availX / 2 - textW / 2)
        ImGui.Text('%s', campLabel)
        local tMinX, tMinY = ImGui.GetItemRectMin()
        local tMaxX, tMaxY = ImGui.GetItemRectMax()
        local midY = (tMinY + tMaxY) / 2
        local pad = 4
        local rightX = leftX + availX
        local drawList = ImGui.GetWindowDrawList()
        local col = ImGui.GetColorU32(51/255, 105/255, 173/255, 1.0)
        local thickness = 1.0
        drawList:AddLine(ImVec2(leftX, midY), ImVec2(tMinX - pad, midY), col, thickness)
        drawList:AddLine(ImVec2(tMaxX + pad, midY), ImVec2(rightX, midY), col, thickness)
        local locationStr = 'unset'
        if rc.makecamp and (rc.makecamp.x or rc.makecamp.y or rc.makecamp.z) then
            locationStr = string.format('%.1f, %.1f, %.1f', rc.makecamp.x or 0, rc.makecamp.y or 0, rc.makecamp.z or 0)
        end
        ImGui.Spacing()
        ImGui.TextColored(WHITE, '%s', 'Location: ')
        ImGui.SameLine(0,2)
        ImGui.TextColored(LIGHT_GREY, '%s', locationStr)
        ImGui.TextColored(WHITE, '%s', 'Radius: ')
        ImGui.SameLine(0, 2)
        ImGui.SetNextItemWidth(NUMERIC_INPUT_WIDTH)
        local acleashVal = botconfig.config.settings.acleash or 75
        local radiusNew, radiusCh = inputs.boundedInt('camp_radius', acleashVal, 1, 10000, 5, '##camp_radius')
        if radiusCh then botconfig.config.settings.acleash = radiusNew; runConfigLoaders() end
        if ImGui.IsItemHovered() then ImGui.SetTooltip('Camp radius for in-camp mob checks.') end
        ImGui.SameLine()
        ImGui.TextColored(WHITE, '%s', 'ZRadius: ')
        ImGui.SameLine(0, 2)
        ImGui.SetNextItemWidth(NUMERIC_INPUT_WIDTH)
        local zradiusVal = botconfig.config.settings.zradius or 75
        local zradiusNew, zradiusCh = inputs.boundedInt('camp_zradius', zradiusVal, 1, 10000, 5, '##camp_zradius')
        if zradiusCh then botconfig.config.settings.zradius = zradiusNew; runConfigLoaders() end
        if ImGui.IsItemHovered() then ImGui.SetTooltip('Camp Z (vertical) radius for in-camp mob checks.') end
        ImGui.TextColored(WHITE, '%s', '# Mobs: ')
        ImGui.SameLine(0,2)
        ImGui.TextColored(LIGHT_GREY, '%s', tostring(rc.MobCount or 0))
        ImGui.TableNextColumn()
        ImGui.PushStyleVar(ImGuiStyleVar.CellPadding, style.CellPadding.x, FLAGS_ROW_PADDING_Y)
        if ImGui.BeginTable('flags table', 2, ImGuiTableFlags.None) then
            ImGui.TableSetupColumn('', ImGuiTableColumnFlags.WidthFixed, FLAGS_COLUMN_WIDTH)
            ImGui.TableSetupColumn('', ImGuiTableColumnFlags.WidthFixed, FLAGS_COLUMN_WIDTH)
            for i, entry in ipairs(DO_FLAGS) do
                if (i - 1) % 2 == 0 then
                    ImGui.TableNextRow()
                end
                ImGui.TableNextColumn()
                local value = botconfig.config.settings[entry.key] == true
                local icon = value and Icons.FA_TOGGLE_ON or Icons.FA_TOGGLE_OFF
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
                ImGui.SameLine(0, 2)
                ImGui.Text('%s', entry.label)
            end
            ImGui.EndTable()
        end
        ImGui.PopStyleVar(1)
        ImGui.EndTable()
    end
end

return M
