-- Debuff tab: dedicated panel for debuff config (On/Off toggle + one spell_entry per debuff).

local ImGui = require('ImGui')
local botconfig = require('lib.config')
local spell_entry = require('gui.widgets.spell_entry')

local M = {}

local GREEN = ImVec4(0, 0.8, 0, 1)
local RED = ImVec4(1, 0, 0, 1)

local function runConfigLoaders()
    botconfig.RunConfigLoaders()
end

--- Draw the full Debuff tab content.
function M.draw()
    local doDebuff = botconfig.config.settings.dodebuff == true
    local label = doDebuff and 'Debuff: On' or 'Debuff: Off'
    local color = doDebuff and GREEN or RED

    -- Right-align the toggle button on the first line
    local textW = select(1, ImGui.CalcTextSize(label))
    local avail = ImGui.GetContentRegionAvail()
    local buttonWidth = textW + 24
    if avail and avail > 0 and buttonWidth > 0 then
        ImGui.SetCursorPosX(ImGui.GetCursorPosX() + avail - buttonWidth)
    end
    ImGui.PushStyleColor(ImGuiCol.Button, color)
    if ImGui.Button(label) then
        botconfig.config.settings.dodebuff = not doDebuff
        runConfigLoaders()
    end
    ImGui.PopStyleColor(1)

    local spells = (botconfig.config.debuff and botconfig.config.debuff.spells) or {}
    for i, entry in ipairs(spells) do
        ImGui.Separator()
        spell_entry.draw(entry, {
            id = 'debuff_' .. i,
            label = 'Debuff ' .. i,
            primaryOptions = spell_entry.PRIMARY_OPTIONS_PULL,
            onChanged = runConfigLoaders,
            displayCommonFields = false,
        })
    end
end

return M
