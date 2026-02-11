-- Labeled row for two-column layout: label on left, control on right.

local ImGui = require('ImGui')

local M = {}

--- Start a labeled row: draw label, then caller draws control in same row (e.g. ImGui.SameLine before control).
---@param label string
---@param width number|nil width for label column (default 180)
function M.labelRow(label, width)
    width = width or 180
    ImGui.SetNextItemWidth(width)
    ImGui.Text('%s', label)
    ImGui.SameLine(width + 8)
end

--- Optional: begin a two-column table for multiple rows. Caller uses TableNextColumn for label, then control.
---@param id string
---@param labelWidth number|nil
function M.beginTwoColumn(id, labelWidth)
    labelWidth = labelWidth or 180
    return ImGui.BeginTable(id, 2, ImGuiTableFlags.None, -1, -1)
end

function M.endTwoColumn()
    ImGui.EndTable()
end

return M
