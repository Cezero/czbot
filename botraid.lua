local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')
local bothooks = require('lib.bothooks')
local myconfig = botconfig.config

local botraid = {}

local current_zone_shortname = nil
local current_zone_module = nil

-- Raid state: zone modules (e.g. raid/sebilis.lua) set global raidsactive; optionally use runconfig.raidCtx.raidsactive.
function botraid.LoadRaidConfig()
    raidsactive = false
    raidtimer = 0
    local rc = state.getRunconfig()
    if not rc.raidCtx then rc.raidCtx = {} end
    rc.raidCtx.raidsactive = false
end

-- TODO: implement in thenest or shared when finalized.
local function BeltronDebuff()
end

function botraid.RaidCheck()
    local shortname = mq.TLO.Zone.ShortName()
    if shortname ~= current_zone_shortname then
        current_zone_shortname = shortname
        local ok, mod = pcall(require, 'raid.' .. shortname)
        if ok and mod and type(mod) == 'table' then
            current_zone_module = mod
        else
            current_zone_module = nil
        end
    end

    if current_zone_module and type(current_zone_module.raid_check) == 'function' then
        local zone_result = current_zone_module.raid_check()
        if zone_result then
            return true
        end
    end

    -- Shared logic: Touch of Shadows / Beltron debuff (does not depend on zone)
    if mq.TLO.Me.Buff("Touch of Shadows").ID() or mq.TLO.Me.Song("Touch of Shadows").ID() then
        local classskip = { war = 'war', shd = 'shd', pal = 'pal' }
        if not classskip[mq.TLO.Me.Class.ShortName()] then
            BeltronDebuff()
            if mq.TLO.Me.Buff("Touch of Shadows").ID() or mq.TLO.Me.Song("Touch of Shadows").ID() then
                return true
            end
        end
    end

    -- Hatchet/DoDH: raid/unknown.lua (or similar) sets hatchemote and Hatchet* globals when required.
    if hatchemote and mq.TLO.SpawnCount("Hatchet npc radius 5000 zradius 5000") then
        if type(HatchetKite) == 'function' and hatchetkite then HatchetKite() end
        if type(HatchetSafe) == 'function' and hatchetsafe then HatchetSafe() end
        if type(HatchetDuck) == 'function' and hatchetduck then HatchetDuck() end
        if type(HatchetClose) == 'function' and hatchetclose then HatchetClose() end
        if type(HatchetAway) == 'function' and hatchetaway then HatchetAway() end
        return true
    end

    local rc = state.getRunconfig()
    local raidsActive = (rc.raidCtx and rc.raidCtx.raidsactive) or raidsactive
    if raidsActive then
        return true
    end
    return false
end

function botraid.getHookFn(name)
    if name == 'doRaid' then
        return function(hookName)
            if not myconfig.settings.doraid then return end
            if botraid.RaidCheck() then
                state.setRunState(state.STATES.raid_mechanic, { priority = bothooks.getPriority('doRaid') })
            else
                state.setRunState(state.STATES.idle)
            end
        end
    end
    return nil
end

return botraid
