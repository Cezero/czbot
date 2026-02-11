-- Nested/cascading select: primary combo + conditional sub-combo (e.g. gem type -> gem slot 1-12).

local ImGui = require('ImGui')

local M = {}

--- Primary combo: select one of the options. options is array of strings (or stringifiable values).
---@param id string unique id
---@param currentIndex number 1-based index into options
---@param options string[] display strings
---@param label string|nil
---@return number newIndex, boolean changed
function M.combo(id, currentIndex, options, label)
    local idx = currentIndex
    if idx < 1 or idx > #options then idx = 1 end
    local preview = options[idx] or ''
    if label then ImGui.SetNextItemWidth(-1) end
    local changed = false
    if ImGui.BeginCombo(label or ('##' .. id), preview, 0) then
        for i, opt in ipairs(options) do
            local selected = (i == idx)
            if ImGui.Selectable(opt, selected) then
                idx = i
                changed = true
            end
            if selected then ImGui.SetItemDefaultFocus() end
        end
        ImGui.EndCombo()
    end
    return idx, changed
end

--- Nested select: primary options; when primaryIndex selects "gemKey" (e.g. "gem"), show sub-combo with subOptions (e.g. 1-12).
--- value: for "gem" slot store number 1-12; for others store primary key (string). So currentValue can be number (gem slot) or string (melee, ranged, etc).
--- primaryOptions: array of { value = string|number, label = string }. When value is "gem" (or gemKey), show sub-combo.
--- subOptions: array of strings for sub-combo (e.g. {"1","2",...,"12"}).
---@param id string
---@param primaryOptions table[] { value = string|number, label = string }
---@param gemKey string key that triggers sub-combo (e.g. "gem")
---@param subOptions string[] e.g. {"1","2",...,"12"}
---@param currentPrimary string|number current primary value (e.g. "melee", "gem")
---@param currentSub number 1-based sub index when primary is gem (e.g. 5 for gem 5)
---@param subComboWidth number|nil optional width in pixels for the sub-combo (e.g. narrow gem selector)
---@return string|number newPrimary, number newSub, boolean changed
function M.nestedCombo(id, primaryOptions, gemKey, subOptions, currentPrimary, currentSub, subComboWidth)
    local primaryIdx = 1
    for i, opt in ipairs(primaryOptions) do
        if opt.value == currentPrimary then primaryIdx = i break end
    end
    local primaryLabel = primaryOptions[primaryIdx] and primaryOptions[primaryIdx].label or tostring(currentPrimary)
    local changed = false
    if ImGui.BeginCombo('##primary_' .. id, primaryLabel, 0) then
        for i, opt in ipairs(primaryOptions) do
            local selected = (opt.value == currentPrimary)
            if ImGui.Selectable(opt.label, selected) then
                currentPrimary = opt.value
                primaryIdx = i
                changed = true
            end
            if selected then ImGui.SetItemDefaultFocus() end
        end
        ImGui.EndCombo()
    end
    local newSub = currentSub
    if currentPrimary == gemKey and #subOptions > 0 then
        ImGui.SameLine()
        local subIdx = currentSub
        if subIdx < 1 or subIdx > #subOptions then subIdx = 1 end
        local subPreview = subOptions[subIdx] or ''
        -- Button needs room for digit(s) + chevron; popup can stay narrow
        local buttonMinWidth = 36
        if subComboWidth and subComboWidth > 0 then
            ImGui.SetNextItemWidth(math.max(buttonMinWidth, subComboWidth))
        end
        if ImGui.BeginCombo('##sub_' .. id, subPreview, 0) then
            -- Keep popup narrow; button width is set above
            local popupW = (subComboWidth and subComboWidth > 0) and subComboWidth or 24
            local lineH = ImGui.GetTextLineHeightWithSpacing()
            ImGui.SetNextWindowSize(popupW, #subOptions * lineH + 4, ImGuiCond.Appearing)
            -- Draw options in reverse order (12 down to 1) so that lower gem numbers are at the
            -- bottom of the list; clicking items at the top of the popup can be consumed by combo
            -- close in some ImGui setups, so putting 1 at the bottom makes "select gem 1" reliable.
            for idx = #subOptions, 1, -1 do
                local opt = subOptions[idx]
                local selected = (idx == subIdx)
                local selectableId = opt .. '##sub_' .. id .. '_' .. idx
                if ImGui.Selectable(selectableId, selected) then
                    newSub = idx
                    changed = true
                end
                if selected then ImGui.SetItemDefaultFocus() end
            end
            ImGui.EndCombo()
        end
        if newSub ~= currentSub then changed = true end
    else
        newSub = 1
    end
    return currentPrimary, newSub, changed
end

return M
