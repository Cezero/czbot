-- Generic spell/ability entry widget: gem type + spell name with type-based validation.
-- Used for pull now; will grow to support bands, targetphase, validtargets via opts (e.g. displayBands).
-- Caller must have started a two-column table; this widget draws two rows (Type/Gem, Spell/Item/Ability).

local mq = require('mq')
local ImGui = require('ImGui')
local combos = require('gui.widgets.combos')
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

--- Draw Type + Spell/Item/Ability. When opts.singleRow true, uses SameLine() for one row (no table). Otherwise uses table (TableNextRow/TableNextColumn).
--- opts: labelGem, labelSpell, onChanged, singleRow, typeComboWidth, spellSelectableWidth (all optional).
function M.draw(id, spell, primaryOptions, opts)
    opts = opts or {}
    local singleRow = opts.singleRow == true
    local labelGem = singleRow and 'Type' or (opts.labelGem or 'Type / Gem')
    local onChanged = opts.onChanged
    local typeComboWidth = opts.typeComboWidth or 100
    local spellSelectableWidth = opts.spellSelectableWidth or 140

    if not _modalState[id] then
        _modalState[id] = { open = false, buffer = '', error = nil }
    end
    local state = _modalState[id]

    local gemType = type(spell.gem) == 'number' and 'gem' or spell.gem
    local labelSpell = singleRow and fieldLabelForGemType(gemType) or (opts.labelSpell or 'Spell / Item / Ability')

    if not singleRow then
        ImGui.TableNextRow()
    end
    if singleRow then
        ImGui.Text('%s', labelGem)
        ImGui.SameLine()
    else
        ImGui.TableNextColumn()
        ImGui.Text('%s', labelGem)
        ImGui.TableNextColumn()
    end
    local primary, sub = gemToPrimarySub(spell.gem)
    ImGui.SetNextItemWidth(singleRow and typeComboWidth or -1)
    local newPrimary, newSub, gemChanged = combos.nestedCombo(id .. '_gem', primaryOptions, 'gem', GEM_SUB_OPTIONS, primary, sub, singleRow and typeComboWidth or -1)
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

    if singleRow and gemType ~= 'melee' then
        ImGui.SameLine()
        ImGui.Text('%s', fieldLabelForGemType(type(spell.gem) == 'number' and 'gem' or spell.gem))
        ImGui.SameLine()
    elseif not singleRow then
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('%s', labelSpell)
        ImGui.TableNextColumn()
    end
    if not singleRow or gemType ~= 'melee' then
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
        local w = singleRow and spellSelectableWidth or (ImGui.GetColumnWidth(-1) or 200)
        if not singleRow and (not w or w <= 0) then w = 200 end
        ImGui.SetNextItemWidth(w)
        ---@diagnostic disable-next-line: undefined-global
        if ImGui.Selectable(displayName .. '##' .. id .. '_ro', false, 0, ImVec2(w, 0)) then
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
end

M.PRIMARY_OPTIONS_PULL = {
    { value = 'melee', label = 'Melee' },
    { value = 'ranged', label = 'Ranged' },
    { value = 'gem', label = 'Gem' },
    { value = 'ability', label = 'Ability' },
    { value = 'item', label = 'Item' },
    { value = 'alt', label = 'Alt' },
    { value = 'disc', label = 'Disc' },
    { value = 'script', label = 'Script' },
}

return M
