-- CH Chain tab: ch_healers list, timing/settings, tank priority display.

local mq = require('mq')
local ImGui = require('ImGui')
local botconfig = require('lib.config')
local state = require('lib.state')
local rolelists = require('lib.rolelists')
local chchain = require('lib.chchain')
local auto_ma_mt = require('lib.auto_ma_mt')
local inputs = require('gui.widgets.inputs')
local theme = require('gui.widgets.theme')
local section = require('gui.widgets.section')
local name_list = require('gui.widgets.name_list')

local M = {}

local YELLOW, WHITE, GREEN, RED = theme.YELLOW, theme.WHITE, theme.GREEN, theme.RED

local function isPcName(name)
    if not name or name == '' then return false end
    return mq.TLO.Spawn('pc =' .. name).Type() == 'PC'
end

local function currentPcTargetName()
    if mq.TLO.Target.ID() and mq.TLO.Target.ID() > 0 and mq.TLO.Target.Type() == 'PC' then
        return mq.TLO.Target.CleanName()
    end
    return nil
end

local function drawTankPriorityReadOnly()
    section.header('Tank priority (mt_list)')
    ImGui.TextWrapped('Edit tank order on the Roles tab. CH chain heals the first alive tank in this list.')
    local rc = state.getRunconfig()
    local list = rc.MtList or {}
    local activeName = nil
    for i, name in ipairs(list) do
        local alive = auto_ma_mt.isCandidateAvailable(name, false)
        if not activeName and alive then activeName = name end
        ImGui.TextColored(alive and GREEN or RED, '%d. %s  %s', i, name, alive and 'alive' or 'down')
    end
    ImGui.Text('Currently healing: %s', activeName or '(none up)')
    ImGui.Spacing()
end

local function drawTimingSection()
    section.header('Timing')
    local settings = chchain.getSettings()
    local function savePartial(partial)
        chchain.saveSettings(partial)
    end
    local delay, delayCh = inputs.boundedInt('ch_delay', settings.delayMs, 0, 30000, 100, '##ch_delay')
    if delayCh then savePartial({ delayMs = delay }) end
    ImGui.SameLine()
    ImGui.TextColored(WHITE, 'Slot delay (ms)')

    local countdown, cdCh = inputs.boundedInt('ch_countdown', settings.startCountdownMs, 0, 10000, 100, '##ch_countdown')
    if cdCh then savePartial({ startCountdownMs = countdown }) end
    ImGui.SameLine()
    ImGui.TextColored(WHITE, 'Start countdown (ms)')

    local preLand, plCh = inputs.boundedInt('ch_preland', settings.preCastHpCheckMs, 1000, 15000, 100, '##ch_preland')
    if plCh then savePartial({ preCastHpCheckMs = preLand }) end
    ImGui.SameLine()
    ImGui.TextColored(WHITE, 'Pre-land HP check (ms)')

    local hp, hpCh = inputs.boundedInt('ch_hp', settings.healthThreshold, 1, 100, 1, '##ch_hp')
    if hpCh then savePartial({ healthThreshold = hp }) end
    ImGui.SameLine()
    ImGui.TextColored(WHITE, 'Cancel if tank HP >= (%)')

    local castTo, castCh = inputs.boundedInt('ch_castto', settings.castStartTimeoutMs, 500, 5000, 100, '##ch_castto')
    if castCh then savePartial({ castStartTimeoutMs = castTo }) end
    ImGui.SameLine()
    ImGui.TextColored(WHITE, 'Cast-start timeout (ms)')
    ImGui.Spacing()
end

local function drawOptionsSection()
    section.header('Options')
    local settings = chchain.getSettings()
    local function savePartial(partial)
        chchain.saveSettings(partial)
    end

    local mirror, mirrorCh = ImGui.Checkbox('Chat mirror (display only)', settings.mirrorEnabled == true)
    if mirrorCh then savePartial({ mirrorEnabled = mirror }) end

    if settings.mirrorEnabled then
        ImGui.SetNextItemWidth(120)
        local curChannel = settings.mirrorChannel or 'rsay'
        if ImGui.BeginCombo('##ch_mirror_channel', curChannel) then
            for _, ch in ipairs(chchain.MIRROR_CHANNELS) do
                if ImGui.Selectable(ch, curChannel == ch) then
                    savePartial({ mirrorChannel = ch })
                end
            end
            ImGui.EndCombo()
        end
        ImGui.SameLine()
        ImGui.TextColored(WHITE, 'Mirror channel')
    end

    local mirrorCasts, mcCh = ImGui.Checkbox('Mirror each cast', settings.mirrorCasts == true)
    if mcCh then savePartial({ mirrorCasts = mirrorCasts }) end

    local clicky, clickyCh = ImGui.Checkbox('Clicky after cast', settings.clickyEnabled == true)
    if clickyCh then savePartial({ clickyEnabled = clicky }) end
    if settings.clickyEnabled then
        ImGui.SetNextItemWidth(220)
        local buf = settings.clickyItem or 'None'
        local newBuf, changed = ImGui.InputText('##ch_clicky_item', buf)
        if changed and type(newBuf) == 'string' then
            savePartial({ clickyItem = newBuf })
        end
    end
    ImGui.Spacing()
end

function M.draw()
    local rc = state.getRunconfig()
    if type(rc.ChHealers) ~= 'table' then rc.ChHealers = {} end

    section.header('CH Chain')
    ImGui.TextWrapped('Enable = participate when the chain runs (normal heals continue until Start). Start from any bot arms a shared slot clock; no baton messaging.')

    local enabled = rc.doChchain == true
    local enChecked, enToggled = ImGui.Checkbox('CH Chain enabled', enabled)
    if enToggled then
        if enChecked then
            chchain.enable()
        else
            chchain.disable()
        end
    end

    ImGui.SameLine()
    local active = rc.chainActive == true
    local actChecked, actToggled = ImGui.Checkbox('Chain active', active)
    if actToggled then
        if actChecked then
            if rc.doChchain or chchain.enable() then
                chchain.beginSchedule()
            end
            chchain.publishControl('start')
        else
            chchain.requestStop()
        end
    end

    if ImGui.Button('Start Chain') then
        chchain.requestKickoff()
    end
    ImGui.SameLine()
    if ImGui.Button('Stop Chain') then
        chchain.requestStop()
    end
    ImGui.SameLine()
    if ImGui.Button('Test Cast') then
        if rc.doChchain or chchain.enable() then
            chchain.startCast(true)
        end
    end

    local tankLabel = rc.chchainTank ~= '' and rc.chchainTank or '(none)'
    local slotLabel = rc.chchainMySlot and tostring(rc.chchainMySlot) or '-'
    local nextMs = (enabled and active) and chchain.timeUntilMyCH() or nil
    local nextLabel = nextMs and (nextMs < 999999 and string.format('%.1fs', nextMs / 1000) or '-') or '-'
    ImGui.TextColored(enabled and GREEN or WHITE, 'Status: %s  |  slot: %s  |  next CH: %s  |  tank: %s  |  %d healers',
        (enabled and active) and 'ACTIVE' or 'IDLE', slotLabel, nextLabel, tankLabel, #(rc.ChHealers or {}))

    ImGui.Separator()
    name_list.draw({
        id = 'chchain_healers',
        label = 'Healer rotation (ch_healers)',
        list = rc.ChHealers,
        reorder = true,
        addNoun = 'Cleric name',
        validateName = isPcName,
        getTargetName = currentPcTargetName,
        onChange = function(action)
            rolelists.process('ch', action)
        end,
    })

    drawTankPriorityReadOnly()
    drawTimingSection()
    drawOptionsSection()

    ImGui.TextWrapped('Lists and settings are stored in cz_common.lua and auto-sync to peers via czactor.')
end

return M
