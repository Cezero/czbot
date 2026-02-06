-- Zone 89: Trakanon (Kunark)
local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')
local myconfig = botconfig.config

local M = {}

function TrakBreathOut()
    local casterclass = { dru = true, enc = true, mag = true, nec = true, shm = true, wiz = true }
    local meleeclass = { brd = true, ber = true, bst = true, mnk = true, pal = true, rng = true, rog = true, shd = true, war = true }
    local myclass = string.lower(mq.TLO.Me.Class.ShortName())
    if myconfig.settings.doraid and mq.TLO.Zone.ID() == 89 then
        if casterclass[myclass] then mq.cmd('/interrupt') end
        if meleeclass[myclass] or casterclass[myclass] then
            raidsactive = true
            myconfig.settings.domelee = false
            state.getRunconfig().engageTargetId = nil
            mq.cmd('/multiline ; /stick off ; /attack off ; /pet back off')
            mq.cmd('/multiline ; /nav loc -1180 -75 -178 ; /echo TrotsRaid: Moving away from Trak')
            mq.delay(200)
        end
    end
end

function TrakBreathIn()
    local casterclass = { dru = true, enc = true, mag = true, nec = true, shm = true, wiz = true }
    local meleeclass = { brd = true, ber = true, bst = true, mnk = true, pal = true, rng = true, rog = true, shd = true, war = true }
    local myclass = string.lower(mq.TLO.Me.Class.ShortName())
    if myconfig.settings.doraid and mq.TLO.Zone.ID() == 89 then
        raidtimer = 30000 + mq.gettime()
        raidsactive = false
        if casterclass[myclass] then mq.cmd('/interrupt') end
        if meleeclass[myclass] or casterclass[myclass] then
            raidsactive = true
            if meleeclass[myclass] then myconfig.settings.domelee = true end
            state.getRunconfig().engageTargetId = nil
            mq.cmd('/multiline ; /stick off ; /attack off ; /pet back off')
            mq.cmd('/multiline ; /nav id ${Spawn[Trakanon].ID} distance=35 ; /echo TrotsRaid: Resuming Combat with Trak...')
            mq.delay(200)
        end
    end
end

mq.event('TrakBreathIn', "#*#Trakanon begins casting Poison Breath#*#", TrakBreathIn)
mq.event('TrakBreathIn2', "#*#Joust Engage#*#", TrakBreathIn)

function M.raid_check()
    if mq.TLO.Zone.ID() ~= 89 then return false end
    if (raidtimer < mq.gettime() and not raidsactive) and mq.TLO.Spawn("Trakanon").ID() and mq.TLO.Me.XTarget("Trakanon").ID() and mq.TLO.Spawn("Trakanon").Distance() < 400 then
        TrakBreathOut()
    end
    return raidsactive
end

return M
