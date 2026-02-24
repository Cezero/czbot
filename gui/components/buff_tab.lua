-- Buff tab: dedicated panel for buff config (one spell_entry per buff).

local ImGui = require('ImGui')
local botconfig = require('lib.config')
local spell_entry = require('gui.widgets.spell_entry')
local inputs = require('gui.widgets.inputs')

local M = {}

local NUMERIC_INPUT_WIDTH = 80

local PRIMARY_OPTIONS = {
    { value = 'gem',     label = 'Gem' },
    { value = 'item',    label = 'Item' },
    { value = 'ability', label = 'Ability' },
    { value = 'alt',     label = 'Alt' },
    { value = 'disc',    label = 'Disc' },
    { value = 'script',  label = 'Script' },
}

-- Phases for buff bands. Keys match spellbands and config default.
local TARGETPHASE_OPTIONS_BUFF = {
    { key = 'self',        label = 'Self',     tooltip = 'Buff self.' },
    { key = 'tank',        label = 'Tank',     tooltip = 'Buff tank (main assist).' },
    { key = 'groupmember', label = 'Group',    tooltip = 'Buff group members (class filter below).' },
    { key = 'pc',          label = 'PC',       tooltip = 'Buff other PCs/bots (class filter below).' },
    { key = 'mypet',       label = 'My Pet',   tooltip = 'Buff your pet.' },
    { key = 'pet',         label = 'Pet',      tooltip = 'Buff other group pets.' },
    { key = 'idle',        label = 'Idle',     tooltip = 'Allow when no mobs in camp.' },
    { key = 'cbt',         label = 'Cbt',      tooltip = 'Allow when mobs in camp.' },
    { key = 'groupbuff',   label = 'Grp Buff', tooltip = 'Group AE buff.' },
}

-- PC/groupmember target options (class filter). Keys match spellbands CLASS_TOKENS.
local VALIDTARGETS_OPTIONS_PC_GROUP = {
    { key = 'all', label = 'All', tooltip = 'All classes.' },
    { key = 'war', label = 'WAR', tooltip = 'Warrior' },
    { key = 'shd', label = 'SHD', tooltip = 'Shadowknight' },
    { key = 'pal', label = 'PAL', tooltip = 'Paladin' },
    { key = 'rng', label = 'RNG', tooltip = 'Ranger' },
    { key = 'mnk', label = 'MNK', tooltip = 'Monk' },
    { key = 'rog', label = 'ROG', tooltip = 'Rogue' },
    { key = 'brd', label = 'BRD', tooltip = 'Bard' },
    { key = 'bst', label = 'BST', tooltip = 'Beastlord' },
    { key = 'ber', label = 'BER', tooltip = 'Berserker' },
    { key = 'shm', label = 'SHM', tooltip = 'Shaman' },
    { key = 'clr', label = 'CLR', tooltip = 'Cleric' },
    { key = 'dru', label = 'DRU', tooltip = 'Druid' },
    { key = 'wiz', label = 'WIZ', tooltip = 'Wizard' },
    { key = 'mag', label = 'MAG', tooltip = 'Mage' },
    { key = 'enc', label = 'ENC', tooltip = 'Enchanter' },
    { key = 'nec', label = 'NEC', tooltip = 'Necromancer' },
}

local function runConfigLoaders()
    botconfig.ApplyAndPersist()
end

local function buffCustomSection(entry, idPrefix, onChanged)
    -- spellicon row: 5-digit numeric input
    ImGui.Text('Spell icon')
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Icon index for UI/display. 0 = default.')
    end
    ImGui.SameLine()
    ImGui.SetNextItemWidth(NUMERIC_INPUT_WIDTH)
    local icon = entry.spellicon
    if icon == nil then icon = 0 end
    local newIcon, iconCh = inputs.boundedInt(idPrefix .. '_spellicon', icon, 0, 99999, 1, '##' .. idPrefix .. '_spellicon')
    if iconCh then
        entry.spellicon = newIcon
        if onChanged then onChanged() end
    end
    ImGui.Spacing()
    -- tarcnt row
    ImGui.Text('Target count')
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Minimum number of targets (e.g. group members in AE range) that must be present before this spell can be used. Used for group/AE buffs; 1 = no minimum.')
    end
    ImGui.SameLine()
    ImGui.SetNextItemWidth(NUMERIC_INPUT_WIDTH)
    local tc = entry.tarcnt
    if tc == nil then tc = 1 end
    local newTc, tcCh = inputs.boundedInt(idPrefix .. '_tarcnt', tc, 1, 24, 1, '##' .. idPrefix .. '_tarcnt')
    if tcCh then
        entry.tarcnt = newTc
        if onChanged then onChanged() end
    end
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
            customSection = buffCustomSection,
            targetphaseOptions = TARGETPHASE_OPTIONS_BUFF,
            validtargetsOptions = VALIDTARGETS_OPTIONS_PC_GROUP,
            showBandMinMax = false,
            showBandMinTarMaxtar = false,
            onDelete = function()
                table.remove(buff.spells, i); runConfigLoaders()
            end,
            deleteEntryLabel = 'Buff',
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
