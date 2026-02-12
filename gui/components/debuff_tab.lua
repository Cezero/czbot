-- Debuff tab: dedicated panel for debuff config (On/Off toggle + one spell_entry per debuff).

local ImGui = require('ImGui')
local botconfig = require('lib.config')
local spell_entry = require('gui.widgets.spell_entry')

local M = {}

local PRIMARY_OPTIONS_DEBUFF = {
    { value = 'gem',     label = 'Gem' },
    { value = 'item',    label = 'Item' },
    { value = 'ability', label = 'Ability' },
    { value = 'alt',     label = 'Alt' },
    { value = 'disc',    label = 'Disc' },
    { value = 'script',  label = 'Script' },
}

local TARGETPHASE_OPTIONS_DEBUFF = {
    { key = 'tanktar',   label = "Tank's Target",  tooltip = "Use when tank has a target (e.g. debuff tank's target)." },
    { key = 'notanktar', label = "Not Tank's Target", tooltip = 'Use on mobs not targeted by the tank (e.g. mez adds).' },
    { key = 'named',     label = 'Named',          tooltip = 'Use on named mobs only.' },
}

local GREEN = ImVec4(0, 0.8, 0, 1)
local RED = ImVec4(1, 0, 0, 1)

local function runConfigLoaders()
    botconfig.RunConfigLoaders()
end

--- Draw the full Debuff tab content.
function M.draw()
    local doDebuff = botconfig.config.settings.dodebuff == true
    local label = doDebuff and 'Debuff: On' or 'Debuff: Off'
    local color = doDebuff and GREEN or RED

    -- Right-align the toggle button on the first line
    local textW = select(1, ImGui.CalcTextSize(label))
    local avail = ImGui.GetContentRegionAvail()
    local buttonWidth = textW + 24
    if avail and avail > 0 and buttonWidth > 0 then
        ImGui.SetCursorPosX(ImGui.GetCursorPosX() + avail - buttonWidth)
    end
    ImGui.PushStyleColor(ImGuiCol.Button, color)
    if ImGui.Button(label) then
        botconfig.config.settings.dodebuff = not doDebuff
        runConfigLoaders()
    end
    ImGui.PopStyleColor(1)

    local debuff = botconfig.config.debuff
    if not debuff then return end
    if not debuff.spells then debuff.spells = {} end
    local spells = debuff.spells

    for i, entry in ipairs(spells) do
        spell_entry.draw(entry, {
            id = 'debuff_' .. i,
            label = 'Debuff ' .. i,
            primaryOptions = PRIMARY_OPTIONS_DEBUFF,
            onChanged = runConfigLoaders,
            displayCommonFields = true,
            targetphaseOptions = TARGETPHASE_OPTIONS_DEBUFF,
            validtargetsOptions = {},
            showBandMinMax = true,
            showBandMinTarMaxtar = true,
        })
        ImGui.Separator()
    end

    -- Right-align "Add debuff" button after the list
    local addLabel = 'Add debuff'
    local addTextW = select(1, ImGui.CalcTextSize(addLabel))
    local addAvail = ImGui.GetContentRegionAvail()
    local addButtonWidth = addTextW + 24
    if addAvail and addAvail > 0 and addButtonWidth > 0 then
        ImGui.SetCursorPosX(ImGui.GetCursorPosX() + addAvail - addButtonWidth)
    end
    if ImGui.Button(addLabel) then
        local defaultEntry = botconfig.getDefaultSpellEntry('debuff')
        if defaultEntry then
            table.insert(debuff.spells, defaultEntry)
            runConfigLoaders()
        end
    end
end

return M
