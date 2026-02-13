-- Labeled grid: table with label in column 1 (first row only) and N columns of checkboxes per row.

local ImGui = require('ImGui') ---@cast ImGui ImGui

local M = {}

local function hasKey(t, k)
    for _, v in ipairs(t) do
        if v == k then return true end
    end
    return false
end

--- Draw a checkbox grid with a label in the first column of the first row.
--- @param opts table id (string), label (string), labelTooltip (string|nil), options (array of { key, label, tooltip }), value (array of selected keys), onToggle(key, isChecked), columns (number|nil, default 5)
function M.checkboxGrid(opts)
    opts = opts or {}
    local id = opts.id
    local options = opts.options or {}
    local value = opts.value or {}
    local columns = opts.columns or 5
    if not id or #options == 0 then return end

    local numRows = math.ceil(#options / columns)
    local tableColumns = 1 + columns
    if ImGui.BeginTable(id .. '_table', tableColumns, ImGuiTableFlags.None, -1, 0) then
        for r = 1, numRows do
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            if r == 1 then
                ImGui.Text('%s', opts.label or '')
                if opts.labelTooltip and ImGui.IsItemHovered() then
                    ImGui.SetTooltip('%s', opts.labelTooltip)
                end
            end
            for c = 1, columns do
                ImGui.TableNextColumn()
                local vi = (r - 1) * columns + c
                if vi <= #options then
                    local opt = options[vi]
                    local key, label, tooltip = opt.key, opt.label, opt.tooltip
                    local checked = hasKey(value, key)
                    local cNew, cPressed = ImGui.Checkbox((label or key) .. '##' .. id .. '_' .. key, checked)
                    if tooltip and ImGui.IsItemHovered() then ImGui.SetTooltip('%s', tooltip) end
                    if cPressed and opts.onToggle then
                        opts.onToggle(key, cNew)
                    end
                end
            end
        end
        ImGui.EndTable()
    end
end

return M
