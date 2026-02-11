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
local function gemToPrimarySub(gem)
    if type(gem) == 'number' and gem >= 1 and gem <= 12 then
        return 'gem', gem
    end
    local s = (type(gem) == 'string') and gem or 'melee'
    return s, 1
end

--- Map (primary, sub) to config gem value.
local function primarySubToGem(primary, sub)
    if primary == 'gem' then return sub end
    return primary
end

--- Validators return success, errorMessage.
local function validateSpellInBook(name)
    if not name or name:match('^%s*$') then return false, 'Enter a spell name' end
    name = name:match('^%s*(.-)%s*$')
    for i = 1, (mq.TLO.Me.BookSize() or 0) do
        local spell = mq.TLO.Me.Book(i)
        if spell and spell.Name() and spell.Name():lower() == name:lower() then
            return true
        end
    end
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

local _modalState = {}

--- Draw two rows in the current two-column table: Type/Gem, Spell/Item/Ability.
--- opts: labelGem, labelSpell, onChanged (all optional). Future: displayBands, displayTargetPhase, etc.
function M.draw(id, spell, primaryOptions, opts)
    opts = opts or {}
    local labelGem = opts.labelGem or 'Type / Gem'
    local labelSpell = opts.labelSpell or 'Spell / Item / Ability'
    local onChanged = opts.onChanged

    if not _modalState[id] then
        _modalState[id] = { open = false, buffer = '', error = nil }
    end
    local state = _modalState[id]

    -- Row 1: Type / Gem
    ImGui.TableNextRow()
    ImGui.TableNextColumn()
    ImGui.Text('%s', labelGem)
    ImGui.TableNextColumn()
    local primary, sub = gemToPrimarySub(spell.gem)
    local newPrimary, newSub, gemChanged = combos.nestedCombo(id .. '_gem', primaryOptions, 'gem', GEM_SUB_OPTIONS, primary, sub)
    if gemChanged then
        spell.gem = primarySubToGem(newPrimary, newSub)
        if onChanged then onChanged() end
    end

    -- Row 2: Spell / Item / Ability
    ImGui.TableNextRow()
    ImGui.TableNextColumn()
    ImGui.Text('%s', labelSpell)
    ImGui.TableNextColumn()
    local gemType = type(spell.gem) == 'number' and 'gem' or spell.gem
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
    local avail = ImGui.GetContentRegionAvailVec()
    local w = (avail and avail.x and avail.x > 0) and avail.x or 200
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
