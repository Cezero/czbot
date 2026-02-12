-- Generic spell/ability entry widget: gem type + spell name with type-based validation.
-- Signature: M.draw(spell, opts)
--   spell: spell entry table to read/write (e.g. config.pull.spell or config.heal.spells[i]).
--   opts: required id (string), primaryOptions (table); optional label, onChanged, displayCommonFields (default true),
--         showRange (default false), customSection, targetphaseOptions, validtargetsOptions,
--         showBandMinMax, showBandMinTarMaxtar. customSection(entry, idPrefix, onChanged) renders category-only fields.
--   targetphaseOptions / validtargetsOptions: each entry { key, label, tooltip }.
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
local ALIAS_INPUT_WIDTH = 120

local GREEN = ImVec4(0, 0.8, 0, 1)
local RED = ImVec4(1, 0, 0, 1)

--- Draw spell entry: label, type combo, spell/item/ability selectable; optionally range, common fields, customSection.
--- @param spell table spell entry to read/write
--- @param opts table required: id (string), primaryOptions (table). optional: label, onChanged, displayCommonFields (default true), showRange (default false), customSection(entry, idPrefix, onChanged), targetphaseOptions, validtargetsOptions, showBandMinMax, showBandMinTarMaxtar. targetphaseOptions/validtargetsOptions entries: { key, label, tooltip }.
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
    local function ensureEditBuffers()
        if state.aliasBuf == nil then
            state.aliasBuf = (type(spell.alias) == 'string' and spell.alias or '')
        end
        if state.preconditionBuf == nil then
            local p = spell.precondition
            state.preconditionBuf = (type(p) == 'string' and p or (p == true and 'true' or 'false'))
        end
    end

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

    if displayCommonFields then
        local enabledLabel = (spell.enabled ~= false) and 'On' or 'Off'
        local enabledColor = (spell.enabled ~= false) and GREEN or RED
        local enabledTextW = select(1, ImGui.CalcTextSize(enabledLabel))
        local enabledButtonWidth = (enabledTextW or 0) + 24
        local availEnabled = ImGui.GetContentRegionAvail()
        if availEnabled and availEnabled > enabledButtonWidth then
            ImGui.SameLine(ImGui.GetCursorPosX() + availEnabled - enabledButtonWidth)
        else
            ImGui.SameLine()
        end
        ImGui.PushStyleColor(ImGuiCol.Button, enabledColor)
        if ImGui.Button(enabledLabel .. '##' .. id .. '_enabled') then
            spell.enabled = not (spell.enabled ~= false)
            if onChanged then onChanged() end
        end
        ImGui.PopStyleColor(1)
    end

    if displayCommonFields then
        ensureEditBuffers()
        -- Second line: Alias, Min mana, Announce (order left to right)
        ImGui.Text('Alias')
        if ImGui.IsItemHovered() then ImGui.SetTooltip('Optional display name or key for spell DB lookup.') end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(ALIAS_INPUT_WIDTH)
        local aliasBuf, aliasChanged = ImGui.InputText('##' .. id .. '_alias', state.aliasBuf or '', 256)
        if aliasChanged then
            state.aliasBuf = aliasBuf
            spell.alias = (aliasBuf == '' and false or aliasBuf)
            if onChanged then onChanged() end
        end
        ImGui.SameLine()
        ImGui.Text('Min mana')
        if ImGui.IsItemHovered() then ImGui.SetTooltip('Minimum mana %% (or endurance) required to cast.') end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(NUMERIC_INPUT_WIDTH)
        local mn = spell.minmana or 0
        local newMn, mnChanged = inputs.boundedInt(id .. '_minmana', mn, 0, 100, 1, '##' .. id .. '_minmana')
        if mnChanged then
            spell.minmana = newMn
            if onChanged then onChanged() end
        end
        ImGui.SameLine()
        ImGui.Text('Announce')
        if ImGui.IsItemHovered() then ImGui.SetTooltip('Announce in chat when this spell is cast.') end
        ImGui.SameLine()
        local ann = spell.announce == true
        local annValue, annPressed = ImGui.Checkbox('##' .. id .. '_announce', ann)
        if annPressed then
            spell.announce = annValue
            if onChanged then onChanged() end
        end
        ImGui.Spacing()
        -- After this we'll put the caller-provided custom widgets.
        if opts.customSection then
            opts.customSection(spell, id .. '_custom', onChanged)
        end
        -- Bands widget
        local targetphaseOptions = opts.targetphaseOptions or {}
        local validtargetsOptions = opts.validtargetsOptions or {}
        local showBandMinMax = opts.showBandMinMax == true
        local showBandMinTarMaxtar = opts.showBandMinTarMaxtar == true
        if not spell.bands or #spell.bands == 0 then
            spell.bands = { { targetphase = {}, validtargets = {} } }
        end
        if #targetphaseOptions > 0 then
            for bi = 1, #spell.bands do
                local band = spell.bands[bi]
                if not band.targetphase then band.targetphase = {} end
                if not band.validtargets then band.validtargets = {} end
                -- Phases row: checkboxes + Delete (except first band)
                ImGui.Text('Phases:')
                ImGui.SameLine()
                for _, opt in ipairs(targetphaseOptions) do
                    local key, label, tooltip = opt.key, opt.label, opt.tooltip
                    local function hasKey(t, k) for _, v in ipairs(t) do if v == k then return true end end return false end
                    local checked = hasKey(band.targetphase, key)
                    local cNew, cPressed = ImGui.Checkbox((label or key) .. '##' .. id .. '_band' .. bi .. '_ph_' .. key, checked)
                    if tooltip and ImGui.IsItemHovered() then ImGui.SetTooltip('%s', tooltip) end
                    if cPressed then
                        if cNew then
                            band.targetphase[#band.targetphase + 1] = key
                        else
                            for i = #band.targetphase, 1, -1 do if band.targetphase[i] == key then table.remove(band.targetphase, i) break end end
                        end
                        if onChanged then onChanged() end
                    end
                    ImGui.SameLine()
                end
                if bi > 1 then
                    local delW = select(1, ImGui.CalcTextSize('Delete')) + 24
                    local availDel = ImGui.GetContentRegionAvail()
                    if availDel and availDel > delW then ImGui.SameLine(ImGui.GetCursorPosX() + availDel - delW) end
                    if ImGui.Button('Delete##' .. id .. '_band_del' .. bi) then
                        table.remove(spell.bands, bi)
                        if onChanged then onChanged() end
                        break
                    end
                end
                -- Targets row
                if #validtargetsOptions > 0 then
                    ImGui.Text('Targets:')
                    ImGui.SameLine()
                    for _, opt in ipairs(validtargetsOptions) do
                        local key, label, tooltip = opt.key, opt.label, opt.tooltip
                        local function hasKey(t, k) for _, v in ipairs(t) do if v == k then return true end end return false end
                        local checked = hasKey(band.validtargets, key)
                        local cNew, cPressed = ImGui.Checkbox((label or key) .. '##' .. id .. '_band' .. bi .. '_vt_' .. key, checked)
                        if tooltip and ImGui.IsItemHovered() then ImGui.SetTooltip('%s', tooltip) end
                        if cPressed then
                            if cNew then band.validtargets[#band.validtargets + 1] = key else for i = #band.validtargets, 1, -1 do if band.validtargets[i] == key then table.remove(band.validtargets, i) break end end end
                            if onChanged then onChanged() end
                        end
                        ImGui.SameLine()
                    end
                end
                -- HP % / # Targets row
                if showBandMinMax or showBandMinTarMaxtar then
                    if showBandMinMax then
                        ImGui.Text('HP %%:')
                        ImGui.SameLine()
                        ImGui.Text('Min')
                        ImGui.SameLine()
                        ImGui.SetNextItemWidth(NUMERIC_INPUT_WIDTH)
                        local bmin = band.min
                        if bmin == nil then bmin = 0 end
                        local newMin, minCh = inputs.boundedInt(id .. '_band' .. bi .. '_min', bmin, 0, 100, 1, '##' .. id .. '_band' .. bi .. '_min')
                        if minCh then band.min = newMin; if onChanged then onChanged() end end
                        ImGui.SameLine()
                        ImGui.Text('Max')
                        ImGui.SameLine()
                        ImGui.SetNextItemWidth(NUMERIC_INPUT_WIDTH)
                        local bmax = band.max
                        if bmax == nil then bmax = 100 end
                        local newMax, maxCh = inputs.boundedInt(id .. '_band' .. bi .. '_max', bmax, 0, 100, 1, '##' .. id .. '_band' .. bi .. '_max')
                        if maxCh then band.max = newMax; if onChanged then onChanged() end end
                        ImGui.SameLine()
                    end
                    if showBandMinTarMaxtar then
                        ImGui.Text('# Targets:')
                        ImGui.SameLine()
                        ImGui.Text('Min')
                        ImGui.SameLine()
                        ImGui.SetNextItemWidth(NUMERIC_INPUT_WIDTH)
                        local bmintar = band.mintar
                        if bmintar == nil then bmintar = 0 end
                        local newMinT, minTCh = inputs.boundedInt(id .. '_band' .. bi .. '_mintar', bmintar, 0, 50, 1, '##' .. id .. '_band' .. bi .. '_mintar')
                        if minTCh then band.mintar = newMinT; if onChanged then onChanged() end end
                        ImGui.SameLine()
                        ImGui.Text('Max')
                        ImGui.SameLine()
                        ImGui.SetNextItemWidth(NUMERIC_INPUT_WIDTH)
                        local bmaxtar = band.maxtar
                        if bmaxtar == nil then bmaxtar = 50 end
                        local newMaxT, maxTCh = inputs.boundedInt(id .. '_band' .. bi .. '_maxtar', bmaxtar, 0, 50, 1, '##' .. id .. '_band' .. bi .. '_maxtar')
                        if maxTCh then band.maxtar = newMaxT; if onChanged then onChanged() end end
                    end
                end
                if bi < #spell.bands then ImGui.Separator() end
            end
            -- Add Band button (right-aligned, below last band)
            local addLabel = 'Add Band'
            local addW = select(1, ImGui.CalcTextSize(addLabel)) + 24
            local availAdd = ImGui.GetContentRegionAvail()
            if availAdd and availAdd > addW then ImGui.SetCursorPosX(ImGui.GetCursorPosX() + availAdd - addW) end
            if ImGui.Button(addLabel .. '##' .. id .. '_add_band') then
                local first = spell.bands[1]
                local newBand = { targetphase = {}, validtargets = {} }
                if first then
                    for _, k in ipairs(first.targetphase or {}) do newBand.targetphase[#newBand.targetphase + 1] = k end
                    for _, k in ipairs(first.validtargets or {}) do newBand.validtargets[#newBand.validtargets + 1] = k end
                    newBand.min = first.min
                    newBand.max = first.max
                    newBand.mintar = first.mintar
                    newBand.maxtar = first.maxtar
                end
                spell.bands[#spell.bands + 1] = newBand
                if onChanged then onChanged() end
            end
        end
        -- Precondition line
        ImGui.Text('Preconditions:')
        if ImGui.IsItemHovered() then ImGui.SetTooltip('When to allow casting: true or a Lua expression (e.g. condition on EvalID).') end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(200)
        local preBuf, preChanged = ImGui.InputText('##' .. id .. '_precondition', state.preconditionBuf or '', 512)
        if preChanged then
            state.preconditionBuf = preBuf
            if preBuf == 'true' then spell.precondition = true
            elseif preBuf == 'false' then spell.precondition = false
            else spell.precondition = preBuf end
            if onChanged then onChanged() end
        end
    end
end

return M
