-- Zone 162: Vyzh`dra the Cursed (Luclin)
local mq = require('mq')

local M = {}

function CursedIn()
end

mq.event('CursedIn', "#*#the Cursed begins casting Caustic Mist#*#", CursedIn)
mq.event('CursedIn2', "#*#Joust Engage#*#", CursedIn)

function CursedOut()
    -- Stub: implement or remove when zone logic is finalized
end

function M.raid_check()
    if mq.TLO.Zone.ID() ~= 162 then return false end
    if mq.TLO.Spawn("Vyzh`dra the Cursed").ID() and mq.TLO.Me.XTarget("Vyzh`dra the Cursed").ID() and not (raidtimer < mq.gettime()) and mq.TLO.Spawn("Vyzh`dra the Cursed").Distance() < 250 then
        CursedOut()
    end
    return raidsactive
end

return M
