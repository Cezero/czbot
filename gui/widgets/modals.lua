-- Reusable validated edit modal: text entry, optional validateFn, Save/Cancel, in-dialog error.
-- Uses BeginPopupModal (rgmercs-style); Save/Cancel call CloseCurrentPopup() directly.
-- validateFn(value) returns success (boolean), optional errorMessage (string).
-- Enter = Save (validate; if fail show error and keep open). Cancel = close and onCancel().

local ImGui = require('ImGui')

local M = {}

local ImGuiInputTextFlags = ImGuiInputTextFlags or {}
local EnterReturnsTrue = ImGuiInputTextFlags.EnterReturnsTrue or 0
local POPUP_FLAGS = bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoResize)

---@param id string unique id for this popup (e.g. "pull_spell_name")
---@param state table { open: boolean, buffer: string, error: string|nil } caller-owned state
---@param validateFn fun(value: string): boolean, string? (success, errorMessage)
---@param onSave fun(value: string) called when Save/Enter and validation passes
---@param onCancel fun() called when Cancel
---@return boolean|nil true if saved this frame, false if cancelled, nil if still open or not open
function M.validatedEditModal(id, state, validateFn, onSave, onCancel)
    if not state.open then
        return nil
    end
    local popupId = '##ValidatedEditModal_' .. id
    ImGui.SetNextWindowSize(320, 0, ImGuiCond.Appearing)
    local show = ImGui.BeginPopupModal(popupId, nil, POPUP_FLAGS)
    if not show then
        return nil
    end
    if state.error and state.error ~= '' then
        ImGui.TextColored(1.0, 0.3, 0.3, 1.0, state.error)
        ImGui.Spacing()
    end
    ImGui.SetNextItemWidth(280)
    local buf, changed = ImGui.InputText('##value' .. popupId, state.buffer or '', EnterReturnsTrue)
    if changed then state.buffer = buf end
    ImGui.Spacing()
    if ImGui.Button('Save##ValidatedEditModal_Save_' .. id) then
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
    if ImGui.Button('Cancel##ValidatedEditModal_Cancel_' .. id) then
        onCancel()
        state.open = false
        state.buffer = ''
        ImGui.CloseCurrentPopup()
        return false
    end
    ImGui.EndPopup()
    return nil
end

--- Open the validated edit popup (call after setting state.open = true and state.buffer = initialValue).
---@param id string
function M.openValidatedEditModal(id)
    ImGui.OpenPopup('##ValidatedEditModal_' .. id)
end

return M
