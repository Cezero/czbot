-- Zone 128: Milas An`Rev (Velious)
local mq = require('mq')

local M = {}

function MilasIn()
end

mq.event('MilasIn', "#*#Milas An`Rev begins casting Devastating Frills#*#", MilasIn)
mq.event('MilasIn2', "#*#Joust Engage#*#", MilasIn)

function MilasOut()
    -- Stub: implement or remove when zone logic is finalized
end

function M.raid_check()
    if mq.TLO.Zone.ID() ~= 128 then return false end
    if mq.TLO.Spawn("Milas An`Rev").ID() and mq.TLO.Me.XTarget("Milas An`Rev").ID() and (raidtimer < mq.gettime()) and mq.TLO.Spawn("Milas An`Rev").Distance() < 400 then
        MilasOut()
    end
    return raidsactive
end

return M
