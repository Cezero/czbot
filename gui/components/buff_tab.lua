-- Buff tab: dedicated panel for buff config (one spell_entry per buff).

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

--- Draw the full Buff tab content.
function M.draw()
    local buff = botconfig.config.buff
    if not buff then return end
    if not buff.spells then buff.spells = {} end
    local spells = buff.spells
    for i, entry in ipairs(spells) do
        spell_entry.draw(entry, {
            id = 'buff_' .. i,
            label = 'Buff ' .. i,
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

    -- Right-align "Add buff" button after the list
    local addLabel = 'Add buff'
    local addTextW = select(1, ImGui.CalcTextSize(addLabel))
    local addAvail = ImGui.GetContentRegionAvail()
    local addButtonWidth = addTextW + 24
    if addAvail and addAvail > 0 and addButtonWidth > 0 then
        ImGui.SetCursorPosX(ImGui.GetCursorPosX() + addAvail - addButtonWidth)
    end
    if ImGui.Button(addLabel) then
        local defaultEntry = botconfig.getDefaultSpellEntry('buff')
        if defaultEntry then
            table.insert(buff.spells, defaultEntry)
            runConfigLoaders()
        end
    end
end

return M
