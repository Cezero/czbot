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

-- Order matches botheal HEAL_PHASE_ORDER; cbt is optional (allow rez in combat with corpse).
local TARGETPHASE_OPTIONS_HEAL = {
    { key = 'corpse',      label = 'Corpse',      tooltip = 'Resurrect PC corpses.' },
    { key = 'self',        label = 'Self',        tooltip = 'Heal self.' },
    { key = 'groupheal',   label = 'Grp Heal',    tooltip = 'Group AE heals (group v1/v2).' },
    { key = 'tank',        label = 'Tank',        tooltip = 'Heal tank (main assist).' },
    { key = 'groupmember', label = 'Group',  tooltip = 'Heal group members (class filter below).' },
    { key = 'pc',          label = 'PC',          tooltip = 'Heal other PCs/bots (class filter below).' },
    { key = 'mypet',       label = 'My Pet',      tooltip = 'Heal your pet.' },
    { key = 'pet',         label = 'Pet',         tooltip = 'Heal other group pets.' },
    { key = 'xtgt',        label = 'XTarget',     tooltip = 'Heal extended targets (heal.xttargets).' },
    { key = 'cbt',         label = 'Cbt',         tooltip = 'With Corpse: allow rez in combat (MobList present).' },
}

-- Corpse-phase target options (who to rez).
local VALIDTARGETS_OPTIONS_CORPSE = {
    { key = 'all',  label = 'All',  tooltip = 'Any PC corpse in range.' },
    { key = 'bots', label = 'Bots', tooltip = 'Bot corpses only.' },
    { key = 'raid', label = 'Raid', tooltip = 'Raid member corpses only.' },
}

-- PC/groupmember-phase target options (class filter). Keys match spellbands CLASS_TOKENS.
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

-- Options per phase for Option B: show only targets relevant to selected phases.
local VALIDTARGETS_OPTIONS_PER_PHASE_HEAL = {
    corpse = VALIDTARGETS_OPTIONS_CORPSE,
    groupmember = VALIDTARGETS_OPTIONS_PC_GROUP,
    pc = VALIDTARGETS_OPTIONS_PC_GROUP,
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
            targetphaseOptions = TARGETPHASE_OPTIONS_HEAL,
            validtargetsOptions = {},
            validtargetsOptionsPerPhase = VALIDTARGETS_OPTIONS_PER_PHASE_HEAL,
            showBandMinMax = true,
            showBandMinTarMaxtar = false,
            onDelete = function() table.remove(heal.spells, i); runConfigLoaders() end,
            deleteEntryLabel = 'Heal',
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
