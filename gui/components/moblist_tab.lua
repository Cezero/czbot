-- Lists tab: exclude, priority, and charm lists for the current zone, plus global autoinv_list.

local mq = require('mq')
local ImGui = require('ImGui')
local state = require('lib.state')
local mobfilter = require('lib.mobfilter')
local nocombatzones = require('lib.nocombatzones')
local theme = require('gui.widgets.theme')
local section = require('gui.widgets.section')
local name_list = require('gui.widgets.name_list')
local autoinvlist = require('lib.autoinvlist')
local botconfig = require('lib.config')

local M = {}

local YELLOW = theme.YELLOW

-- "Add target" candidate for mob lists: any current target's clean name (mobs need not be PCs).
local function currentTargetName()
    if mq.TLO.Target.ID() and mq.TLO.Target.ID() > 0 then
        return mq.TLO.Target.CleanName()
    end
    return nil
end

local function drawMobListSection(listType, runconfigKey, label)
    local rc = state.getRunconfig()
    if type(rc[runconfigKey]) ~= 'table' then rc[runconfigKey] = {} end
    name_list.draw({
        id = 'mob_' .. listType,
        label = label,
        list = rc[runconfigKey],
        reverse = true,
        addNoun = 'Mob name',
        getTargetName = currentTargetName,
        onChange = function(action) mobfilter.process(listType, action) end,
    })
end

local function currentCursorItemName()
    if mq.TLO.Cursor.ID() and mq.TLO.Cursor.ID() > 0 then
        local name = mq.TLO.Cursor.Name()
        if name and name ~= '' then return name end
    end
    return nil
end

local function sameItemName(a, b)
    return type(a) == 'string' and type(b) == 'string' and a:lower() == b:lower()
end

local function drawAutoinvListSection()
    -- Copy so the widget does not mutate cz_common before mutateCommon reloads disk.
    local list = botconfig.copyStringList(autoinvlist.getList())
    name_list.draw({
        id = 'autoinv_list',
        label = 'Auto-inventory list',
        list = list,
        addNoun = 'Item name',
        addButtonLabel = 'Add cursor',
        manualAlways = true,
        getTargetName = currentCursorItemName,
        sameName = sameItemName,
        onChange = function(action)
            autoinvlist.save(list, action == 'save_replace')
        end,
    })
end

local function drawNoCombatZonesSection()
    local list = nocombatzones.getConfiguredZones()
    section.header('No combat zones')
    if ImGui.BeginTable('No combat zones table', 3, bit32.bor(ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersOuter), -1, 0) then
        ImGui.TableSetupColumn('Enabled', 0, 0.15)
        ImGui.TableSetupColumn('Zone', 0, 0.70)
        ImGui.TableSetupColumn('', 0, 0.15)
        ImGui.TableHeadersRow()
        for i = #list, 1, -1 do
            local name = list[i]
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            local enabled = nocombatzones.isZoneEnabled(name)
            local checked, toggled = ImGui.Checkbox('##nocombat_enabled' .. i, enabled)
            if toggled then
                nocombatzones.setZoneEnabled(name, checked)
            end
            ImGui.TableNextColumn()
            ImGui.Text('%s', name)
            ImGui.TableNextColumn()
            if ImGui.SmallButton('Remove##nocombat' .. i) then
                nocombatzones.removeZone(name)
            end
        end
        ImGui.EndTable()
    end
    if ImGui.Button('Add current zone') then
        local zone = mq.TLO.Zone.ShortName()
        if zone and zone ~= '' then
            nocombatzones.addZone(zone)
        end
    end
    ImGui.Spacing()
end

function M.draw()
    ImGui.TextColored(YELLOW, 'Current zone: %s', mq.TLO.Zone.ShortName() or '')
    ImGui.Spacing()
    drawMobListSection('exclude', 'ExcludeList', 'Exclude list')
    drawMobListSection('priority', 'PriorityList', 'Priority list')
    drawMobListSection('charm', 'CharmList', 'Charm list')
    drawAutoinvListSection()
    drawNoCombatZonesSection()
end

return M
