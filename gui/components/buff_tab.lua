-- Buff tab: dedicated panel for buff config (one spell_entry per buff).

local mq = require('mq')
local ImGui = require('ImGui')
local botconfig = require('lib.config')
local spellutils = require('lib.spellutils')
local buffphase = require('lib.buffphase')
local spell_entry = require('gui.widgets.spell_entry')
local inputs = require('gui.widgets.inputs')
local name_list = require('gui.widgets.name_list')

local charinfowatchers = require('lib.charinfowatchers')

local M = {}

local NUMERIC_INPUT_WIDTH = 80
local SPELICON_INPUT_WIDTH = 220

-- Per-spell-entry editable buffer for adding to `spellicon` list.
local spelliconTextState = {}

local function resolveSpelliconName(spellicon)
    local sid = tonumber(spellicon)
    if not sid or sid == 0 then return '' end
    local name = mq.TLO.Spell(sid).Name()
    if type(name) == 'string' and name ~= '' then return name end
    return tostring(sid)
end

local function ensureSpelliconList(entry)
    entry.spellicon = charinfowatchers.normalizeSpelliconList(entry.spellicon)
    return entry.spellicon
end

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
    { key = 'groupmember', label = 'Group',     tooltip = 'Buff your group members (class filter below).' },
    { key = 'pc',          label = 'All chars', tooltip = 'Single-target or Group v2 AE: buff networked characters from the CharInfo ALL watchlist (any group), class-filtered at register time.' },
    { key = 'mypet',       label = 'My Pet',   tooltip = 'Buff your pet.' },
    { key = 'pet',         label = 'Pet',      tooltip = 'Buff other group pets.' },
    { key = 'groupbuff',   label = 'Grp Buff', tooltip = 'Group v1 AE: cast on self (no target) when enough of your group need the buff. tarcnt includes self.' },
}

local TARGETPHASE_GROUPV2_PC = {
    key = 'pc',
    label = 'All chars',
    tooltip = 'Group v2 AE: cast on CharInfo ALL-watchlist peers; AE covers their group and they leave the watchlist when buffed.',
}

local TARGETPHASE_GROUPV2_GROUPBUFF = {
    key = 'groupbuff',
    label = 'Grp Buff',
    tooltip = 'Group v2 AE: cast on self when enough of your group need the buff. tarcnt includes self.',
}

local function getTargetPhaseOptionsForEntry(entry)
    local tt = spellutils.GetSpellTargetType(entry)
    if tt == 'Group v2' then
        return { TARGETPHASE_GROUPV2_GROUPBUFF, TARGETPHASE_GROUPV2_PC }
    end
    local out = {}
    for _, opt in ipairs(TARGETPHASE_OPTIONS_BUFF) do
        if tt == 'Group v1' then
            if opt.key ~= 'pc' then out[#out + 1] = opt end
        else
            if opt.key ~= 'groupbuff' then out[#out + 1] = opt end
        end
    end
    return out
end

local function isGroupAEBuffEntry(entry)
    return buffphase.getAllowedPhases(entry) ~= nil
end

--- Strip hidden targetphase tokens that the GUI no longer shows for Group AE buffs.
local function sanitizeBuffTargetPhases(entry)
    buffphase.sanitizeEntryTargetPhases(entry)
end

local function getDetectedTypeLabelForEntry(entry)
    local tt = spellutils.GetSpellTargetType(entry)
    if tt == 'Group v2' then return 'Group v2' end
    if tt == 'Group v1' then return 'Group v1' end
    if spellutils.IsPetSummonSpell(entry) then return 'Pet summon' end
    return nil
end

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

-- Twist reconcile runs from BuffCheck (yieldable); never EnsureDefaultTwistRunning from ImGui.
local function runConfigLoaders()
    botconfig.ApplyAndPersist()
end

local function buffCustomSection(entry, idPrefix, onChanged)
    -- spellicon list: equivalent buff IDs for "already has buff" detection
    ImGui.Text('Equivalent buffs')
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Spell IDs treated as the same buff for skip/refresh. Add by name or ID. Empty list = only the buff spell itself.')
    end
    local icons = ensureSpelliconList(entry)
    for i = #icons, 1, -1 do
        local sid = icons[i]
        ImGui.Text(('  %s'):format(resolveSpelliconName(sid)))
        ImGui.SameLine()
        if ImGui.SmallButton(('Remove##%s_icon_%d'):format(idPrefix, i)) then
            table.remove(icons, i)
            entry.spellicon = icons
            if onChanged then onChanged() end
        end
    end
    if not spelliconTextState[idPrefix] then
        spelliconTextState[idPrefix] = { buf = '', error = nil }
    end
    local s = spelliconTextState[idPrefix]
    ImGui.SetNextItemWidth(SPELICON_INPUT_WIDTH)
    local ImGuiInputTextFlags = ImGuiInputTextFlags or {}
    local flags = (ImGuiInputTextFlags.EnterReturnsTrue) or 0
    local newBuf, changed = ImGui.InputText('##'..idPrefix..'_spellicon_add', s.buf or '', flags)
    if changed and newBuf ~= nil then
        local trimmed = (newBuf:match('^%s*(.-)%s*$') or '')
        s.buf = newBuf
        if trimmed ~= '' and trimmed ~= '0' then
            local candidate = tonumber(trimmed) or trimmed
            local resolved = mq.TLO.Spell(candidate).ID()
            local sidNum = tonumber(resolved)
            if sidNum and sidNum > 0 then
                local found = false
                for _, id in ipairs(icons) do
                    if id == sidNum then found = true break end
                end
                if not found then
                    icons[#icons + 1] = sidNum
                    entry.spellicon = icons
                    if onChanged then onChanged() end
                end
                s.buf = ''
                s.error = nil
            else
                s.error = 'Invalid spell ID/name'
            end
        end
    elseif ImGui.IsItemHovered() and s.error then
        ImGui.SetTooltip(s.error)
    end
    ImGui.Spacing()
    if spellutils.IsShrinkSpell(entry) then
        ImGui.Text('Height')
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Cast when target Height exceeds this value (SPA 89 shrink). Peers use CharInfo Height; self uses Me.Height. Typical: 2.4–2.5.')
        end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(NUMERIC_INPUT_WIDTH)
        local h = tonumber(entry.height)
        if h == nil or h <= 0 then h = 2.4 end
        local newH, hCh = ImGui.InputFloat('##' .. idPrefix .. '_height', h, 0.1, 0.5, '%.2f')
        if hCh and newH ~= nil then
            local n = tonumber(newH)
            if n and n > 0 then
                entry.height = n
            else
                entry.height = nil
            end
            if onChanged then onChanged() end
        end
        ImGui.Spacing()
    end
    if isGroupAEBuffEntry(entry) then
        ImGui.Text('Target count')
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Minimum group members needing this buff before casting Grp Buff on self (tarcnt includes yourself). Peer All-chars targeting uses the CharInfo watchlist.')
        end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(NUMERIC_INPUT_WIDTH)
        local tc = entry.tarcnt
        if tc == nil then tc = 1 end
        local newTc, tcCh = inputs.boundedInt(idPrefix .. '_tarcnt', tc, 1, 10, 1, '##' .. idPrefix .. '_tarcnt')
        if tcCh then
            entry.tarcnt = newTc
            if onChanged then onChanged() end
        end
        ImGui.Spacing()
    end
    -- In combat: allow this buff when mobs are in camp
    ImGui.Text('Allow in combat')
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip('Allow this buff to be cast when mobs are in camp.')
    end
    ImGui.SameLine()
    local inCbt = entry.inCombat == true
    local inCbtVal, inCbtPressed = ImGui.Checkbox('##' .. idPrefix .. '_inCombat', inCbt)
    if inCbtPressed then
        entry.inCombat = inCbtVal
        if onChanged then onChanged() end
    end
    -- Combat only (non-Bard): auto buff loop considers this spell only when mobs are in camp
    if mq.TLO.Me.Class.ShortName() ~= 'BRD' then
        ImGui.Spacing()
        ImGui.Text('Combat only')
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                'Only consider this buff when mobs are in camp (not while idle). For short self buffs (e.g. Yaulp) so they are not refreshed every tick out of combat. Implies allow in combat for the auto buff loop.')
        end
        ImGui.SameLine()
        local cbtOnly = entry.combatOnly == true
        local cbtOnlyVal, cbtOnlyPressed = ImGui.Checkbox('##' .. idPrefix .. '_combatOnly', cbtOnly)
        if cbtOnlyPressed then
            entry.combatOnly = cbtOnlyVal
            if onChanged then onChanged() end
        end
    end
    -- In idle (Bard only): include in twist when no mobs in camp
    if mq.TLO.Me.Class.ShortName() == 'BRD' then
        ImGui.Text('In idle')
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip('Include in twist when no mobs in camp (Bard only).')
        end
        ImGui.SameLine()
        local inIdle = entry.inIdle == true
        local inIdleVal, inIdlePressed = ImGui.Checkbox('##' .. idPrefix .. '_inIdle', inIdle)
        if inIdlePressed then
            entry.inIdle = inIdleVal
            if onChanged then onChanged() end
        end
    end

    -- Managed name list (replaces the old raw-key "byname"): always buff these specific characters,
    -- in range, regardless of group -- works for networked toons AND non-network PCs (e.g. guildmates).
    -- Collapsed by default so it doesn't clutter buffs that don't need it.
    entry.buffNames = (type(entry.buffNames) == 'table') and entry.buffNames or {}
    ImGui.Spacing()
    local hdr = (#entry.buffNames > 0) and string.format('Buff extra names (%d)', #entry.buffNames) or 'Buff extra names'
    if ImGui.CollapsingHeader(hdr .. '##' .. idPrefix .. '_names_hdr') then
        name_list.draw({
            id = idPrefix .. '_names',
            label = 'Always buff these characters (any group / guildmates):',
            list = entry.buffNames,
            addNoun = 'PC name',
            getTargetName = function()
                if mq.TLO.Target.ID() and mq.TLO.Target.ID() > 0 and mq.TLO.Target.Type() == 'PC' then
                    return mq.TLO.Target.CleanName()
                end
                return nil
            end,
            onChange = function() if onChanged then onChanged() end end,
        })
    end
end

--- Draw the full Buff tab content.
function M.draw()
    local buff = botconfig.config.buff
    if not buff then return end
    local spells = buff.spells or {}
    buff.spells = spells
    spell_entry.drawTabIntro({ flagKey = 'dobuff', flagNoun = 'Buffing', isEmpty = #spells == 0,
        emptyHint = 'No buffs configured. Click "Add buff" below to create one.' })
    for i, entry in ipairs(spells) do
        sanitizeBuffTargetPhases(entry)
        spell_entry.draw(entry, {
            id = 'buff_' .. i,
            label = 'Buff ' .. i,
            collapsible = true,
            detectedTypeLabel = getDetectedTypeLabelForEntry(entry),
            primaryOptions = PRIMARY_OPTIONS,
            onChanged = runConfigLoaders,
            displayCommonFields = true,
            customSection = buffCustomSection,
            targetphaseOptionsFn = getTargetPhaseOptionsForEntry,
            validtargetsOptions = VALIDTARGETS_OPTIONS_PC_GROUP,
            showBandMinMax = false,
            showBandMinTarMaxtar = false,
            onDelete = function()
                table.remove(buff.spells, i); runConfigLoaders()
            end,
            deleteEntryLabel = 'Buff',
            entryIndex = i,
            entryCount = #spells,
            onMoveUp = (function(idx)
                return idx > 1 and function()
                    botconfig.swapSpellEntries('buff', idx, idx - 1)
                end or nil
            end)(i),
            onMoveDown = (function(idx)
                return idx < #spells and function()
                    botconfig.swapSpellEntries('buff', idx, idx + 1)
                end or nil
            end)(i),
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
