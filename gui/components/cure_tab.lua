-- Cure tab: dedicated panel for cure config (one spell_entry per cure).

local ImGui = require('ImGui')
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

--- Draw the full Cure tab content.
function M.draw()
    local cure = botconfig.config.cure
    if not cure then return end
    if not cure.spells then cure.spells = {} end
    local spells = cure.spells
    for i, entry in ipairs(spells) do
        spell_entry.draw(entry, {
            id = 'cure_' .. i,
            label = 'Cure ' .. i,
            primaryOptions = PRIMARY_OPTIONS,
            onChanged = runConfigLoaders,
            displayCommonFields = true,
            customSection = nil,
            targetphaseOptions = {},
            validtargetsOptions = {},
            showBandMinMax = false,
            showBandMinTarMaxtar = false,
            onDelete = function()
                table.remove(cure.spells, i); runConfigLoaders()
            end,
            deleteEntryLabel = 'Cure',
        })
        ImGui.Separator()
    end

    -- Right-align "Add cure" button after the list
    local addLabel = 'Add cure'
    local addTextW = select(1, ImGui.CalcTextSize(addLabel))
    local addAvail = ImGui.GetContentRegionAvail()
    local addButtonWidth = addTextW + 24
    if addAvail and addAvail > 0 and addButtonWidth > 0 then
        ImGui.SetCursorPosX(ImGui.GetCursorPosX() + addAvail - addButtonWidth)
    end
    if ImGui.Button(addLabel) then
        local defaultEntry = botconfig.getDefaultSpellEntry('cure')
        if defaultEntry then
            table.insert(cure.spells, defaultEntry)
            runConfigLoaders()
        end
    end
end

return M
