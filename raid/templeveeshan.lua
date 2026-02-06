-- Zone 124: Lady Nevederia, Dozekar (Velious)
local mq = require('mq')

local M = {}

function LadyNevIn()
end

function DozeIn()
end

mq.event('LadyNevIn', "#*#Lady Nevederia begins casting Bellowing Winds#*#", LadyNevIn)
mq.event('LadyNevIn2', "#*#Joust Engage#*#", LadyNevIn)
mq.event('DozeIn', "#*#Dozekar the Cursed begins casting Silver Breath#*#", DozeIn)
mq.event('DozeIn2', "#*#Joust Engage#*#", DozeIn)

function LadyNevBreathOut()
    -- Stub: implement or remove when zone logic is finalized
end

function DozeOut()
    -- Stub: implement or remove when zone logic is finalized
end

function M.raid_check()
    if mq.TLO.Zone.ID() ~= 124 then return false end
    if mq.TLO.Spawn("Lady Nevederia").ID() and mq.TLO.Me.XTarget("Lady Nevederia").ID() and (raidtimer < mq.gettime()) and mq.TLO.Spawn("Lady Nevederia").Distance() < 250 then
        LadyNevBreathOut()
    end
    if mq.TLO.Spawn("Dozekar the Cursed").ID() and mq.TLO.Me.XTarget("Dozekar the Cursed").ID() and (raidtimer < mq.gettime()) and mq.TLO.Spawn("Dozekar the Cursed").Distance() < 250 then
        DozeOut()
    end
    return raidsactive
end

return M
