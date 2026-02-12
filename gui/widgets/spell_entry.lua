-- Generic spell/ability entry widget: gem type + spell name with type-based validation.
-- Signature: M.draw(spell, opts)
--   spell: spell entry table to read/write (e.g. config.pull.spell or config.heal.spells[i]).
--   opts: required id (string), primaryOptions (table); optional label, onChanged, displayCommonFields (default true),
--         showRange (default false), customSection, targetphaseOptions, validtargetsOptions,
--         showBandMinMax, showBandMintarMaxtar. customSection(entry, idPrefix, onChanged) renders category-only fields.
-- Widths are hardcoded; caller does not control layout. All widget IDs use opts.id as prefix.

local mq = require('mq')
local ImGui = require('ImGui')
local combos = require('gui.widgets.combos')
local inputs = require('gui.widgets.inputs')
local modals = require('gui.widgets.modals')

local M = {}

local GEM_SUB_OPTIONS = {}
for i = 1, 12 do GEM_SUB_OPTIONS[i] = tostring(i) end

--- Map config gem value to (primary, sub). Config gem is number 1-12 or string.
--- Accepts string "1"-"12" from config so selection of lower gem numbers persists after load.
local function gemToPrimarySub(gem)
    if type(gem) == 'number' and gem >= 1 and gem <= 12 then
        return 'gem', gem
    end
    if type(gem) == 'string' then
        local n = tonumber(gem)
        if n and n >= 1 and n <= 12 then
            return 'gem', n
        end
        return gem, 1
    end
    return 'melee', 1
end

--- Map (primary, sub) to config gem value.
local function primarySubToGem(primary, sub)
    if primary == 'gem' then return sub end
    return primary
end

--- Validators return success, errorMessage.
--- Me.Book(name) returns slot number if spell is in book (no BookSize in MQ Lua).
local function validateSpellInBook(name)
    if not name or name:match('^%s*$') then return false, 'Enter a spell name' end
    name = name:match('^%s*(.-)%s*$')
    local book = mq.TLO.Me and mq.TLO.Me.Book and mq.TLO.Me.Book(name)
    if not book then return false, 'Spell not in your spell book' end
    local ok, slot = pcall(function() return book() end)
    if ok and slot and slot > 0 then return true end
    return false, 'Spell not in your spell book'
end

local function validateFindItem(name)
    if not name or name:match('^%s*$') then return false, 'Enter an item name' end
    name = name:match('^%s*(.-)%s*$')
    if mq.TLO.FindItem(name)() and mq.TLO.FindItem(name)() > 0 then return true end
    return false, 'Item not found in inventory'
end

local function validateAltAbility(name)
    if not name or name:match('^%s*$') then return false, 'Enter an AA name' end
    name = name:match('^%s*(.-)%s*$')
    local aa = mq.TLO.Me.AltAbility(name)
    if aa and aa.ID() and aa.ID() > 0 then return true end
    return false, 'Alt ability not found'
end

local function validateDiscipline(name)
    if not name or name:match('^%s*$') then return false, 'Enter a discipline name' end
    name = name:match('^%s*(.-)%s*$')
    local disc = mq.TLO.Me.Discipline(name)
    if disc and disc.ID() and disc.ID() > 0 then return true end
    return false, 'Discipline not found'
end

local function validateAbility(name)
    if not name or name:match('^%s*$') then return false, 'Enter an ability name' end
    name = name:match('^%s*(.-)%s*$')
    for i = 1, 20 do
        local ab = mq.TLO.Me.Ability(i)
        if ab and ab.Name() and ab.Name():lower() == name:lower() then return true end
    end
    return false, 'Ability not found'
end

local function validateScriptKey(name)
    if not name or name:match('^%s*$') then return false, 'Enter a script key' end
    return true
end

local function validatorForGemType(gemType)
    if gemType == 'gem' then return validateSpellInBook end
    if gemType == 'ranged' or gemType == 'item' then return validateFindItem end
    if gemType == 'alt' then return validateAltAbility end
    if gemType == 'disc' then return validateDiscipline end
    if gemType == 'ability' then return validateAbility end
    if gemType == 'script' then return validateScriptKey end
    return nil
end

-- Gem types that do not use the spell/item/ability field (display "unused", not editable).
local UNUSED_SPELL_TYPES = { melee = true }

--- Short label for the spell/item/ability column based on gem type (for single-row layout).
local function fieldLabelForGemType(gemType)
    if gemType == 'gem' then return 'Spell' end
    if gemType == 'ranged' or gemType == 'item' then return 'Item' end
    if gemType == 'ability' then return 'Ability' end
    if gemType == 'alt' then return 'Alt' end
    if gemType == 'disc' then return 'Disc' end
    if gemType == 'script' then return 'Script' end
    return 'Spell'
end

local _modalState = {}

local TYPE_COMBO_WIDTH = 100
local SPELL_SELECTABLE_WIDTH = 140
local NUMERIC_INPUT_WIDTH = 80

--- Draw spell entry: label, type combo, spell/item/ability selectable; optionally range, common fields, customSection.
--- @param spell table spell entry to read/write
--- @param opts table required: id (string), primaryOptions (table). optional: label, onChanged, displayCommonFields (default true), showRange (default false), customSection(entry, idPrefix, onChanged), targetphaseOptions, validtargetsOptions, showBandMinMax, showBandMintarMaxtar.
function M.draw(spell, opts)
    opts = opts or {}
    local id = opts.id
    local primaryOptions = opts.primaryOptions
    if not id or not primaryOptions then return end
    local labelText = opts.label or 'Type'
    local onChanged = opts.onChanged
    local displayCommonFields = opts.displayCommonFields
    if displayCommonFields == nil then displayCommonFields = true end
    local showRange = opts.showRange or false

    if not _modalState[id] then
        _modalState[id] = { open = false, buffer = '', error = nil }
    end
    local state = _modalState[id]

    local gemType = type(spell.gem) == 'number' and 'gem' or spell.gem

    ImGui.Text('%s', labelText)
    ImGui.SameLine()
    local primary, sub = gemToPrimarySub(spell.gem)
    ImGui.SetNextItemWidth(TYPE_COMBO_WIDTH)
    local newPrimary, newSub, gemChanged = combos.nestedCombo(id .. '_gem', primaryOptions, 'gem', GEM_SUB_OPTIONS,
        primary, sub, TYPE_COMBO_WIDTH)
    if gemChanged then
        spell.gem = primarySubToGem(newPrimary, newSub)
        if newPrimary == 'gem' then
            local name = mq.TLO.Me and mq.TLO.Me.Gem and mq.TLO.Me.Gem(newSub)
            if name then
                local ok, spellName = pcall(function() return name() end)
                if ok and spellName and spellName ~= '' then
                    spell.spell = spellName
                else
                    spell.spell = spell.spell or ''
                end
            else
                spell.spell = spell.spell or ''
            end
        end
        if onChanged then onChanged() end
    end

    if gemType ~= 'melee' then
        ImGui.SameLine()
        ImGui.Text('%s', fieldLabelForGemType(type(spell.gem) == 'number' and 'gem' or spell.gem))
        ImGui.SameLine()
    end
    if gemType ~= 'melee' then
        local isUnused = UNUSED_SPELL_TYPES[gemType] == true
        local validator = validatorForGemType(gemType) or function() return true end
        local function onSave(value)
            spell.spell = (value or ''):match('^%s*(.-)%s*$')
            state.open = false
            state.buffer = ''
            if onChanged then onChanged() end
        end
        local function onCancel()
            state.open = false
            state.buffer = ''
            state.error = nil
        end

        local displayName
        if isUnused then
            displayName = 'unused'
        elseif not spell.spell or spell.spell:match('^%s*$') then
            displayName = 'unset'
        else
            displayName = spell.spell
        end
        ImGui.SetNextItemWidth(SPELL_SELECTABLE_WIDTH)
        ---@diagnostic disable-next-line: undefined-global
        if ImGui.Selectable(displayName .. '##' .. id .. '_ro', false, 0, ImVec2(SPELL_SELECTABLE_WIDTH, 0)) then
            if not isUnused then
                state.open = true
                state.buffer = spell.spell or ''
                state.error = nil
                modals.openValidatedEditModal(id)
            end
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(isUnused and 'Not used for this type' or 'Click to edit')
        end

        if state.open and not isUnused then
            modals.validatedEditModal(id, state, validator, onSave, onCancel)
        end
    end

    if showRange then
        local rangeLabelW = select(1, ImGui.CalcTextSize('Range'))
        local rangeLabelWidth = (rangeLabelW or 0) + 4
        local rangeTotalWidth = rangeLabelWidth + NUMERIC_INPUT_WIDTH
        local avail = ImGui.GetContentRegionAvail()
        if avail and avail > rangeTotalWidth then
            ImGui.SameLine(ImGui.GetCursorPosX() + avail - rangeTotalWidth)
        else
            ImGui.SameLine()
        end
        ImGui.Text('Range')
        if ImGui.IsItemHovered() then ImGui.SetTooltip(
            'Max range to use when casting the pull spell (0 = use spell default).') end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(NUMERIC_INPUT_WIDTH)
        local r = spell.range or 0
        local newR, rChanged = inputs.boundedInt(id .. '_range', r, 0, 500, 5, '##' .. id .. '_range')
        if rChanged then
            spell.range = newR
            if onChanged then onChanged() end
        end
    end

    if displayCommonFields and opts.customSection then
        opts.customSection(spell, id .. '_custom', onChanged)
    end
end

M.PRIMARY_OPTIONS_PULL = {
    { value = 'melee',   label = 'Melee' },
    { value = 'ranged',  label = 'Ranged' },
    { value = 'gem',     label = 'Gem' },
    { value = 'ability', label = 'Ability' },
    { value = 'item',    label = 'Item' },
    { value = 'alt',     label = 'Alt' },
    { value = 'disc',    label = 'Disc' },
    { value = 'script',  label = 'Script' },
}

return M
