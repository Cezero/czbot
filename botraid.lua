local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')
local bothooks = require('lib.bothooks')
local myconfig = botconfig.config

local botraid = {}

local current_zone_shortname = nil
local current_zone_module = nil

function botraid.LoadRaidConfig()
    raidsactive = false
    raidtimer = 0
end

local function BeltronDebuff()
    -- Stub: Touch of Shadows / Beltron debuff; implement in thenest or shared when finalized
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

    -- Hatchet emote block (DoDH; zone module not loaded - guard calls)
    if hatchemote and mq.TLO.SpawnCount("Hatchet npc radius 5000 zradius 5000") then
        if type(HatchetKite) == 'function' and hatchetkite then HatchetKite() end
        if type(HatchetSafe) == 'function' and hatchetsafe then HatchetSafe() end
        if type(HatchetDuck) == 'function' and hatchetduck then HatchetDuck() end
        if type(HatchetClose) == 'function' and hatchetclose then HatchetClose() end
        if type(HatchetAway) == 'function' and hatchetaway then HatchetAway() end
        return true
    end

    if raidsactive then
        return true
    end
end

do
    local hookregistry = require('lib.hookregistry')
    hookregistry.registerHookFn('doRaid', function(hookName)
        if not myconfig.settings.doraid then return end
        if botraid.RaidCheck() then
            state.setRunState('raid_mechanic', { priority = bothooks.getPriority('doRaid') })
        else
            state.setRunState('idle')
        end
    end)
end

return botraid
