-- Bounded integer input widget for range, radius, etc. Clamps to min/max.

local ImGui = require('ImGui')

local M = {}

local ImGuiInputTextFlags = ImGuiInputTextFlags or {}

---@param id string unique id
---@param value number current value
---@param minVal number minimum (inclusive)
---@param maxVal number maximum (inclusive)
---@param step number|nil step for arrows (default 1)
---@param label string|nil optional label
---@return number newValue, boolean changed
function M.boundedInt(id, value, minVal, maxVal, step, label)
    step = step or 1
    local v = value
    if type(v) ~= 'number' then v = tonumber(v) or minVal end
    local flags = ImGuiInputTextFlags.CharsDecimal
    local newVal, changed = ImGui.InputInt(label or ('##' .. id), v, step, step * 10, flags)
    if changed then
        v = tonumber(newVal) or v
        if v > maxVal then v = maxVal end
        if v < minVal then v = minVal end
        return v, true
    end
    return v, false
end

return M
