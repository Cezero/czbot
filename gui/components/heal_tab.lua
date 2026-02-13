-- Heal tab: dedicated panel for heal config (one spell_entry per heal).

local ImGui = require('ImGui') ---@cast ImGui ImGui
local botconfig = require('lib.config')
local spell_entry = require('gui.widgets.spell_entry')

local M = {}

local PRIMARY_OPTIONS = {
    { value = 'gem',     label = 'Gem' },
    { value = 'item',    label = 'Item' },
    { value = 'ability', label = 'Ability' },
    { value = 'alt',     label = 'Alt' },
    { value = 'disc',    label = 'Disc' },
    { value = 'script',  label = 'Script' },
}

local function runConfigLoaders()
    botconfig.ApplyAndPersist()
end

--- Draw the full Heal tab content.
function M.draw()
    local heal = botconfig.config.heal
    if not heal then return end
    if not heal.spells then heal.spells = {} end
    local spells = heal.spells
    for i, entry in ipairs(spells) do
        spell_entry.draw(entry, {
            id = 'heal_' .. i,
            label = 'Heal ' .. i,
            primaryOptions = PRIMARY_OPTIONS,
            onChanged = runConfigLoaders,
            displayCommonFields = true,
            customSection = nil,
            targetphaseOptions = {},
            validtargetsOptions = {},
            showBandMinMax = false,
            showBandMinTarMaxtar = false,
        })
        ImGui.Separator()
    end

    -- Right-align "Add heal" button after the list
    local addLabel = 'Add heal'
    local addTextW = select(1, ImGui.CalcTextSize(addLabel))
    local addAvail = ImGui.GetContentRegionAvail()
    local addButtonWidth = addTextW + 24
    if addAvail and addAvail > 0 and addButtonWidth > 0 then
        ImGui.SetCursorPosX(ImGui.GetCursorPosX() + addAvail - addButtonWidth)
    end
    if ImGui.Button(addLabel) then
        local defaultEntry = botconfig.getDefaultSpellEntry('heal')
        if defaultEntry then
            table.insert(heal.spells, defaultEntry)
            runConfigLoaders()
        end
    end
end

return M
