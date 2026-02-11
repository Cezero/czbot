-- Reusable validated edit popup (non-modal): text entry, optional validateFn, Save/Cancel, in-dialog error.
-- Uses BeginPopup so it can close on outside click or Escape without modal stack; avoids MQ/ImGui crash on Cancel.
-- validateFn(value) returns success (boolean), optional errorMessage (string).
-- Enter = Save (validate; if fail show error and keep open). Escape or outside click = Cancel.

local ImGui = require('ImGui')

local M = {}

local ImGuiInputTextFlags = ImGuiInputTextFlags or {}
local EnterReturnsTrue = ImGuiInputTextFlags.EnterReturnsTrue or 0
local POPUP_FLAGS = bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoResize)

-- Per-id: was the popup actually open last frame (so we can treat "now closed" as cancel)
local popupWasOpen = {}

---@param id string unique id for this popup (e.g. "pull_spell_name")
---@param state table { open: boolean, buffer: string, error: string|nil } caller-owned state
---@param validateFn fun(value: string): boolean, string? (success, errorMessage)
---@param onSave fun(value: string) called when Save/Enter and validation passes
---@param onCancel fun() called when Cancel/Escape/outside click
---@return boolean|nil true if saved this frame, false if cancelled, nil if still open or not open
function M.validatedEditModal(id, state, validateFn, onSave, onCancel)
    if not state.open then
        popupWasOpen[id] = false
        return nil
    end
    local popupId = '##ValidatedEditModal_' .. id
    if not ImGui.BeginPopup(popupId, POPUP_FLAGS) then
        if popupWasOpen[id] then
            popupWasOpen[id] = false
            state.open = false
            state.buffer = ''
            state.error = nil
            onCancel()
            return false
        end
        return nil
    end
    popupWasOpen[id] = true
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
            popupWasOpen[id] = false
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
        popupWasOpen[id] = false
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
