-- Zone 163: Grieg Veneficus (Luclin)
local mq = require('mq')

local M = {}

function GriegIn()
end

mq.event('GriegIn', "#*#Joust Engage#*#", GriegIn)
mq.event('GriegIn2', "#*#Grieg Veneficus begins casting Upheaval#*#", GriegIn)

function GriegOut()
    -- Stub: implement or remove when zone logic is finalized
end

function M.raid_check()
    if mq.TLO.Zone.ID() ~= 163 then return false end
    if mq.TLO.Spawn("npc Grieg Veneficus").ID() and mq.TLO.Me.XTarget("Grieg Veneficus").ID() and not (raidtimer < mq.gettime()) and mq.TLO.Spawn("npc Grieg Veneficus").Distance() < 250 then
        GriegOut()
    end
    return raidsactive
end

return M
