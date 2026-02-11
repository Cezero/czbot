-- Reusable validated edit modal: text entry, optional validateFn, Save/Cancel, in-dialog error.
-- validateFn(value) returns success (boolean), optional errorMessage (string).
-- Enter = Save (validate; if fail show error and keep open). Escape = Cancel.

local ImGui = require('ImGui')

local M = {}

local ImGuiInputTextFlags = ImGuiInputTextFlags or {}
local EnterReturnsTrue = ImGuiInputTextFlags.EnterReturnsTrue or 0

---@param id string unique id for this modal (e.g. "pull_spell_name")
---@param state table { open: boolean, buffer: string, error: string|nil } caller-owned state
---@param validateFn fun(value: string): boolean, string? (success, errorMessage)
---@param onSave fun(value: string) called when Save/Enter and validation passes
---@param onCancel fun() called when Cancel/Escape
---@return boolean|nil true if saved this frame, false if cancelled, nil if still open or not open
function M.validatedEditModal(id, state, validateFn, onSave, onCancel)
    if not state.open then return nil end
    local modalId = '##ValidatedEditModal_' .. id
    if ImGui.BeginPopupModal(modalId, nil, bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoResize)) then
        if state.error and state.error ~= '' then
            ImGui.TextColored(1.0, 0.3, 0.3, 1.0, state.error)
            ImGui.Spacing()
        end
        ImGui.SetNextItemWidth(280)
        local buf, changed = ImGui.InputText('##value' .. modalId, state.buffer or '', EnterReturnsTrue)
        if changed then state.buffer = buf end
        ImGui.Spacing()
        if ImGui.Button('Save##' .. modalId) then
            state.error = nil
            local ok, errMsg
            if validateFn then
                ok, errMsg = validateFn(state.buffer or '')
            else
                ok = true
            end
            if ok then
                onSave(state.buffer or '')
                state.open = false
                state.buffer = ''
                ImGui.CloseCurrentPopup()
                return true
            else
                state.error = errMsg or 'Invalid'
            end
        end
        ImGui.SameLine()
        if ImGui.Button('Cancel##' .. modalId) then
            onCancel()
            state.open = false
            state.buffer = ''
            ImGui.CloseCurrentPopup()
            return false
        end
        ImGui.EndPopup()
    end
    return nil
end

--- Open the validated edit modal (call after setting state.open = true and state.buffer = initialValue).
---@param id string
function M.openValidatedEditModal(id)
    ImGui.OpenPopup('##ValidatedEditModal_' .. id)
end

return M
