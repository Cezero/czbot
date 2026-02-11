-- Pull tab: dedicated panel for pull config (con color, spell, distance, etc.).
-- Uses gui/widgets for modals, combos, inputs, layout, spell_entry.

local ImGui = require('ImGui')
local botconfig = require('lib.config')
local combos = require('gui.widgets.combos')
local inputs = require('gui.widgets.inputs')
local layout = require('gui.widgets.layout')
local spell_entry = require('gui.widgets.spell_entry')

local M = {}

local function runConfigLoaders()
    botconfig.RunConfigLoaders()
end

local function recomputePullSquared(pull)
    if not pull then return end
    pull.radiusSq = (pull.radius or 0) * (pull.radius or 0)
    local r40 = (pull.radius or 0) + 40
    pull.radiusPlus40Sq = r40 * r40
    pull.engageRadiusSq = (pull.engageRadius or 0) * (pull.engageRadius or 0)
    pull.leashSq = (pull.leash or 0) * (pull.leash or 0)
end

--- Draw the full Pull tab content.
function M.draw()
    local pull = botconfig.config.pull
    if not pull then return end
    local spell = pull.spell
    if not spell then spell = { gem = 'melee', spell = '', range = nil } end

    -- ----- Pull spell -----
    if layout.beginTwoColumn('pull_spell_table', 200) then
        ImGui.TableSetupColumn('Label', 0, 0.35)
        ImGui.TableSetupColumn('Value', 0, 0.65)
        spell_entry.draw('pull_spell', spell, spell_entry.PRIMARY_OPTIONS_PULL, { onChanged = runConfigLoaders })
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('Range')
        ImGui.TableNextColumn()
        local r = spell.range or 0
        local newR, rChanged = inputs.boundedInt('pull_range', r, 0, 500, 5, '##pull_range')
        if rChanged then
            spell.range = newR
            runConfigLoaders()
        end
        layout.endTwoColumn()
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Text('Distance')
    if layout.beginTwoColumn('pull_dist_table', 200) then
        for _, row in ipairs({
            { key = 'radius', label = 'Radius', min = 1, max = 10000, default = 400 },
            { key = 'engageRadius', label = 'Engage radius', min = 1, max = 500, default = 200 },
            { key = 'zrange', label = 'Z range', min = 1, max = 500, default = 150 },
        }) do
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.Text('%s', row.label)
            ImGui.TableNextColumn()
            local v = pull[row.key] or row.default
            local nv, ch = inputs.boundedInt('pull_' .. row.key, v, row.min, row.max, 10, '##' .. row.key)
            if ch then pull[row.key] = nv; recomputePullSquared(pull); runConfigLoaders() end
        end
        layout.endTwoColumn()
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Text('Targets (con / level)')
    if layout.beginTwoColumn('pull_targets_table', 200) then
        local conColors = botconfig.ConColors or {}
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('Pull Min Con')
        ImGui.TableNextColumn()
        local minC = pull.pullMinCon or 2
        if minC < 1 or minC > 7 then minC = 2 end
        local minCNew, minCCh = combos.combo('pull_mincon', minC, conColors, '##pull_mincon')
        if minCCh then pull.pullMinCon = minCNew; runConfigLoaders() end
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('Pull Max Con')
        ImGui.TableNextColumn()
        local maxC = pull.pullMaxCon or 5
        if maxC < 1 or maxC > 7 then maxC = 5 end
        local maxCNew, maxCCh = combos.combo('pull_maxcon', maxC, conColors, '##pull_maxcon')
        if maxCCh then pull.pullMaxCon = maxCNew; runConfigLoaders() end
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('Max Red Con Level Diff')
        ImGui.TableNextColumn()
        local mld = pull.maxLevelDiff or 6
        local mldNew, mldCh = inputs.boundedInt('pull_maxleveldiff', mld, 4, 125, 1, '##pull_maxleveldiff')
        if mldCh then pull.maxLevelDiff = mldNew; runConfigLoaders() end
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('Use Level-Based Pulling')
        ImGui.TableNextColumn()
        local useLvl = pull.usePullLevels == true
        local useLvlCh, useLvlNew = ImGui.Checkbox('##pull_uselevels', useLvl)
        if useLvlCh then pull.usePullLevels = useLvlCh; runConfigLoaders() end
        if pull.usePullLevels then
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.Text('Pull Min Level')
            ImGui.TableNextColumn()
            local pmin = pull.pullMinLevel or 1
            local pminNew, pminCh = inputs.boundedInt('pull_minlevel', pmin, 1, 125, 1, '##pull_minlevel')
            if pminCh then pull.pullMinLevel = pminNew; runConfigLoaders() end
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.Text('Pull Max Level')
            ImGui.TableNextColumn()
            local pmax = pull.pullMaxLevel or 125
            local pmaxNew, pmaxCh = inputs.boundedInt('pull_maxlevel', pmax, 1, 125, 1, '##pull_maxlevel')
            if pmaxCh then pull.pullMaxLevel = pmaxNew; runConfigLoaders() end
        end
        layout.endTwoColumn()
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Text('Other')
    if layout.beginTwoColumn('pull_other_table', 200) then
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('Chain pull HP %%')
        ImGui.TableNextColumn()
        local cph = pull.chainpullhp or 0
        local cphNew, cphCh = inputs.boundedInt('pull_chainpullhp', cph, 0, 100, 5, '##pull_chainpullhp')
        if cphCh then pull.chainpullhp = cphNew; runConfigLoaders() end
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('Chain pull count')
        ImGui.TableNextColumn()
        local cpc = pull.chainpullcnt or 0
        local cpcNew, cpcCh = inputs.boundedInt('pull_chainpullcnt', cpc, 0, 20, 1, '##pull_chainpullcnt')
        if cpcCh then pull.chainpullcnt = cpcNew; runConfigLoaders() end
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('Mana %%')
        ImGui.TableNextColumn()
        local mana = pull.mana or 60
        local manaNew, manaCh = inputs.boundedInt('pull_mana', mana, 0, 100, 5, '##pull_mana')
        if manaCh then pull.mana = manaNew; runConfigLoaders() end
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('Mana class')
        ImGui.TableNextColumn()
        local mc = pull.manaclass or 'clr, dru, shm'
        ImGui.SetNextItemWidth(-1)
        local newText, changed = ImGui.InputText('##pull_manaclass', mc, 0)
        if changed and newText then pull.manaclass = newText; runConfigLoaders() end
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('Leash')
        ImGui.TableNextColumn()
        local leash = pull.leash or 500
        local leashNew, leashCh = inputs.boundedInt('pull_leash', leash, 0, 2000, 50, '##pull_leash')
        if leashCh then pull.leash = leashNew; recomputePullSquared(pull); runConfigLoaders() end
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('Use priority list')
        ImGui.TableNextColumn()
        local up = pull.usepriority == true
        local upCh, upNew = ImGui.Checkbox('##pull_usepriority', up)
        if upCh then pull.usepriority = upCh; runConfigLoaders() end
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        ImGui.Text('Hunter mode')
        ImGui.TableNextColumn()
        local hunt = pull.hunter == true
        local huntCh, huntNew = ImGui.Checkbox('##pull_hunter', hunt)
        if huntCh then pull.hunter = huntCh; runConfigLoaders() end
        layout.endTwoColumn()
    end
end

return M
