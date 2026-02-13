-- Debuff tab: dedicated panel for debuff config (On/Off toggle + one spell_entry per debuff).

local ImGui = require('ImGui') ---@cast ImGui ImGui
local botconfig = require('lib.config')
local labeled_grid = require('gui.widgets.labeled_grid')
local spell_entry = require('gui.widgets.spell_entry')
local inputs = require('gui.widgets.inputs')

local M = {}

local NUMERIC_INPUT_WIDTH = 80

-- Build ordered options for dontStack checkboxes from config allowlist (key, label, tooltip).
local function buildDontStackOptions()
    local allowed = botconfig.DEBUFF_DONTSTACK_ALLOWED
    local keys = {}
    for k in pairs(allowed) do keys[#keys + 1] = k end
    table.sort(keys)
    local opts = {}
    for _, key in ipairs(keys) do
        opts[#opts + 1] = { key = key, label = key, tooltip = "Do not overwrite existing " .. key .. "." }
    end
    return opts
end
local DONTSTACK_OPTIONS = buildDontStackOptions()

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

local function runConfigLoaders()
    botconfig.ApplyAndPersist()
end

--- Custom section for debuff entries: recast, delay, dontStack (passed to spell_entry as customSection).
local function debuffCustomSection(entry, idPrefix, onChanged)
    -- First line: Recast and Delay (SameLine)
    ImGui.Text('Recast')
    if ImGui.IsItemHovered() then ImGui.SetTooltip('After this many resists on the same spawn, disable this spell for that spawn. 0 = no limit.') end
    ImGui.SameLine()
    ImGui.SetNextItemWidth(NUMERIC_INPUT_WIDTH)
    local recast = entry.recast or 0
    local newRecast, recastCh = inputs.boundedInt(idPrefix .. '_recast', recast, 0, 999, 1, '##' .. idPrefix .. '_recast')
    if recastCh then entry.recast = newRecast; if onChanged then onChanged() end end
    ImGui.SameLine()
    ImGui.Text('Delay')
    if ImGui.IsItemHovered() then ImGui.SetTooltip('Delay (ms) before this spell can be used again after cast.') end
    ImGui.SameLine()
    ImGui.SetNextItemWidth(NUMERIC_INPUT_WIDTH + 28)
    local delay = entry.delay or 0
    local newDelay, delayCh = inputs.boundedInt(idPrefix .. '_delay', delay, 0, 60000, 100, '##' .. idPrefix .. '_delay')
    if delayCh then entry.delay = newDelay; if onChanged then onChanged() end end

    -- Don't stack: labeled grid (4 options per row)
    labeled_grid.checkboxGrid({
        id = idPrefix .. '_dontstack',
        label = "Don't stack:",
        labelTooltip = "If target already has any of these categories (e.g. Snared), don't cast this spell and interrupt if it appears while casting.",
        options = DONTSTACK_OPTIONS,
        value = entry.dontStack or {},
        columns = 4,
        onToggle = function(key, isChecked)
            if entry.dontStack == nil then entry.dontStack = {} end
            if isChecked then
                entry.dontStack[#entry.dontStack + 1] = key
            else
                for i = #entry.dontStack, 1, -1 do
                    if entry.dontStack[i] == key then table.remove(entry.dontStack, i) break end
                end
                if #entry.dontStack == 0 then entry.dontStack = nil end
            end
            if onChanged then onChanged() end
        end,
    })
end

--- Draw the full Debuff tab content.
function M.draw()
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
            customSection = debuffCustomSection,
            targetphaseOptions = TARGETPHASE_OPTIONS_DEBUFF,
            validtargetsOptions = {},
            showBandMinMax = true,
            showBandMinTarMaxtar = true,
            onDelete = function() table.remove(debuff.spells, i); runConfigLoaders() end,
            deleteEntryLabel = 'Debuff',
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
