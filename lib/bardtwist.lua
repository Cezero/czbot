-- Bard MQ2Twist integration: twist list builders, mode, ensure, stop/resume, twist once.
-- Requires mq, botconfig, state. No dependency on spellutils/botbuff to avoid circular refs.

local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')

local bardtwist = {}

--- Parse entry.bands for a phase token (buff: self, cbt, pull).
local function buffHasPhase(entry, phase)
    local bands = entry and entry.bands
    if not bands or type(bands) ~= 'table' then return false end
    for _, band in ipairs(bands) do
        local tp = band.targetphase
        if type(tp) == 'table' then
            for _, p in ipairs(tp) do
                if p == phase then return true end
            end
        end
    end
    return false
end

--- Parse entry.bands for tanktar (debuff).
local function debuffHasTanktar(entry)
    local bands = entry and entry.bands
    if not bands or type(bands) ~= 'table' then return false end
    for _, band in ipairs(bands) do
        local tp = band.targetphase
        if type(tp) == 'table' then
            for _, p in ipairs(tp) do
                if p == 'tanktar' then return true end
            end
        end
    end
    return false
end

function bardtwist.IsBard()
    return mq.TLO.Me.Class.ShortName() == 'BRD'
end

--- All buffs with self and numeric gem (enabled). Config order.
function bardtwist.BuildNoncombatTwistList()
    if not bardtwist.IsBard() then return {} end
    local spells = botconfig.config.buff and botconfig.config.buff.spells
    if not spells then return {} end
    local out = {}
    for i = 1, #spells do
        local entry = spells[i]
        if entry and entry.enabled ~= false and type(entry.gem) == 'number' and entry.gem >= 1 and entry.gem <= 12 then
            if buffHasPhase(entry, 'self') then
                out[#out + 1] = entry.gem
            end
        end
    end
    return out
end

--- Buffs with cbt then debuffs with tanktar (numeric gem, enabled). Config order.
function bardtwist.BuildCombatTwistList()
    if not bardtwist.IsBard() then return {} end
    local out = {}
    local buffs = botconfig.config.buff and botconfig.config.buff.spells
    if buffs then
        for i = 1, #buffs do
            local entry = buffs[i]
            if entry and entry.enabled ~= false and type(entry.gem) == 'number' and entry.gem >= 1 and entry.gem <= 12 then
                if buffHasPhase(entry, 'cbt') then
                    out[#out + 1] = entry.gem
                end
            end
        end
    end
    local debuffs = botconfig.config.debuff and botconfig.config.debuff.spells
    if debuffs then
        for i = 1, #debuffs do
            local entry = debuffs[i]
            if entry and entry.enabled ~= false and type(entry.gem) == 'number' and entry.gem >= 1 and entry.gem <= 12 then
                if debuffHasTanktar(entry) then
                    out[#out + 1] = entry.gem
                end
            end
        end
    end
    return out
end

--- Buffs with self and pull (numeric gem, enabled). Config order.
function bardtwist.BuildPullTwistList()
    if not bardtwist.IsBard() then return {} end
    local spells = botconfig.config.buff and botconfig.config.buff.spells
    if not spells then return {} end
    local out = {}
    for i = 1, #spells do
        local entry = spells[i]
        if entry and entry.enabled ~= false and type(entry.gem) == 'number' and entry.gem >= 1 and entry.gem <= 12 then
            if buffHasPhase(entry, 'self') and buffHasPhase(entry, 'pull') then
                out[#out + 1] = entry.gem
            end
        end
    end
    return out
end

function bardtwist.GetCurrentTwistMode()
    if not bardtwist.IsBard() then return nil end
    local rc = state.getRunconfig()
    if rc.pullState and rc.pullState ~= '' then return 'pull' end
    if rc.MobList and rc.MobList[1] then return 'combat' end
    return 'idle'
end

--- Build list for mode and return as string for comparison with Twist.List().
function bardtwist.GetTwistListStringForMode(mode)
    local list
    if mode == 'pull' then
        list = bardtwist.BuildPullTwistList()
    elseif mode == 'combat' then
        list = bardtwist.BuildCombatTwistList()
    else
        list = bardtwist.BuildNoncombatTwistList()
    end
    if not list or #list == 0 then return '' end
    return table.concat(list, ' ')
end

--- Set twist list for mode. Only issue /twist when not twisting or list differs (avoid restart every tick).
function bardtwist.EnsureTwistForMode(mode)
    if not bardtwist.IsBard() then return end
    if not mq.TLO.Plugin('MQ2Twist') or not mq.TLO.Plugin('MQ2Twist').IsLoaded() then return end
    local desiredList = bardtwist.GetTwistListStringForMode(mode)
    if desiredList == '' then return end
    local twisting = mq.TLO.Twist() and mq.TLO.Twist.Twisting()
    local currentList = (mq.TLO.Twist() and mq.TLO.Twist.List()) or ''
    if twisting and currentList == desiredList then return end
    mq.cmd('/squelch /twist ' .. desiredList)
end

function bardtwist.EnsureDefaultTwistRunning()
    local mode = bardtwist.GetCurrentTwistMode()
    if mode then bardtwist.EnsureTwistForMode(mode) end
end

function bardtwist.StopTwist()
    if not mq.TLO.Plugin('MQ2Twist') or not mq.TLO.Plugin('MQ2Twist').IsLoaded() then return end
    if mq.TLO.Twist() and mq.TLO.Twist.Twisting() then
        mq.cmd('/squelch /twist stop')
    end
end

--- Restore twist for current mode (e.g. after single cast). Set list if needed then start.
function bardtwist.ResumeTwist()
    if not bardtwist.IsBard() then return end
    if not mq.TLO.Plugin('MQ2Twist') or not mq.TLO.Plugin('MQ2Twist').IsLoaded() then return end
    local mode = bardtwist.GetCurrentTwistMode()
    if not mode then return end
    local desiredList = bardtwist.GetTwistListStringForMode(mode)
    if desiredList == '' then return end
    if mq.TLO.Twist() and mq.TLO.Twist.Twisting() then return end
    local currentList = (mq.TLO.Twist() and mq.TLO.Twist.List()) or ''
    if currentList ~= desiredList then
        mq.cmd('/squelch /twist ' .. desiredList)
    else
        mq.cmd('/squelch /twist start')
    end
end

function bardtwist.SetTwistOnce(gemList)
    if not mq.TLO.Plugin('MQ2Twist') or not mq.TLO.Plugin('MQ2Twist').IsLoaded() then return end
    if not gemList or #gemList == 0 then return end
    mq.cmd('/squelch /twist once ' .. table.concat(gemList, ' '))
end

function bardtwist.SetTwistOnceGem(gem)
    if gem then bardtwist.SetTwistOnce({ gem }) end
end

--- Resolve engage_gem or engage_spell from config.pull. Returns gem number or nil.
function bardtwist.GetEngageGem()
    ---@type { engage_gem?: number, engage_spell?: string }|nil
    local pull = botconfig.config.pull
    if not pull then return nil end
    if type(pull.engage_gem) == 'number' and pull.engage_gem >= 1 and pull.engage_gem <= 12 then
        return pull.engage_gem
    end
    if type(pull.engage_spell) == 'string' and pull.engage_spell ~= '' then
        local spell = pull.engage_spell
        for slot = 1, 12 do
            local mem = mq.TLO.Me.Gem(slot)()
            if mem and mem == spell then return slot end
        end
    end
    return nil
end

return bardtwist
