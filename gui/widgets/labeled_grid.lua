-- Labeled grid: table with label in column 1 (first row only) and N columns of checkboxes per row.

local ImGui = require('ImGui')

local M = {}

local function hasKey(t, k)
    for _, v in ipairs(t) do
        if v == k then return true end
    end
    return false
end

--- Draw a checkbox grid with a label in the first column of the first row.
--- @param opts table id (string), label (string), labelTooltip (string|nil), options (array of { key, label, tooltip }), value (array of selected keys), onToggle(key, isChecked), columns (number|nil, default 5), maxWidth (number|nil)
function M.checkboxGrid(opts)
    opts = opts or {}
    local id = opts.id
    local options = opts.options or {}
    local value = opts.value or {}
    local columns = opts.columns or 5
    local tableWidth = (type(opts.maxWidth) == 'number' and opts.maxWidth > 0) and opts.maxWidth or -1
    if not id or #options == 0 then return end

    local numRows = math.ceil(#options / columns)
    local tableColumns = 1 + columns
    if ImGui.BeginTable(id .. '_table', tableColumns, ImGuiTableFlags.None, tableWidth, 0) then
        local labelText = opts.label or ''
        local labelW = select(1, ImGui.CalcTextSize(labelText))
        labelW = (labelW and labelW > 0) and (labelW + 8) or 80
        ImGui.TableSetupColumn('', ImGuiTableColumnFlags.WidthFixed, labelW)
        for _ = 1, columns do
            ImGui.TableSetupColumn('', ImGuiTableColumnFlags.WidthStretch, 0)
        end
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
