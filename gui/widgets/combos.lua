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

--- Nested select: single combo with primary options; "gemKey" (e.g. "gem") is a BeginMenu with subOptions (e.g. 1-12).
--- All selection happens in one popup so there is no second combo and no click-stealing bug.
---@param id string
---@param primaryOptions table[] { value = string|number, label = string }
---@param gemKey string key that uses a submenu (e.g. "gem")
---@param subOptions string[] e.g. {"1","2",...,"12"}
---@param currentPrimary string|number current primary value (e.g. "melee", "gem")
---@param currentSub number 1-based sub index when primary is gem (e.g. 5 for gem 5)
---@param subComboWidth number|nil optional width in pixels for the combo button
---@return string|number newPrimary, number newSub, boolean changed
function M.nestedCombo(id, primaryOptions, gemKey, subOptions, currentPrimary, currentSub, subComboWidth)
    local primaryIdx = 1
    for i, opt in ipairs(primaryOptions) do
        if opt.value == currentPrimary then primaryIdx = i break end
    end
    local primaryLabel = primaryOptions[primaryIdx] and primaryOptions[primaryIdx].label or tostring(currentPrimary)
    local preview = (currentPrimary == gemKey) and ('Gem ' .. tostring(currentSub)) or primaryLabel
    local newSub = currentSub
    if newSub < 1 or newSub > #subOptions then newSub = 1 end
    local changed = false
    if subComboWidth and subComboWidth > 0 then
        ImGui.SetNextItemWidth(subComboWidth)
    end
    if ImGui.BeginCombo('##primary_' .. id, preview, 0) then
        for i, opt in ipairs(primaryOptions) do
            if opt.value == gemKey then
                if ImGui.BeginMenu(opt.label) then
                    for idx = 1, #subOptions do
                        local subLabel = subOptions[idx] or tostring(idx)
                        local selected = (currentPrimary == gemKey and idx == newSub)
                        if ImGui.Selectable(subLabel .. '##' .. id .. '_gem_' .. idx, selected) then
                            currentPrimary = gemKey
                            newSub = idx
                            changed = true
                        end
                        if selected then ImGui.SetItemDefaultFocus() end
                    end
                    ImGui.EndMenu()
                end
            else
                local selected = (opt.value == currentPrimary)
                if ImGui.Selectable(opt.label, selected) then
                    currentPrimary = opt.value
                    newSub = 1
                    changed = true
                end
                if selected then ImGui.SetItemDefaultFocus() end
            end
        end
        ImGui.EndCombo()
    end
    if currentPrimary ~= gemKey then newSub = 1 end
    return currentPrimary, newSub, changed
end

return M
