-- Zone 163: Grieg Veneficus (Luclin)
local mq = require('mq')
local utils = require('lib.utils')

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
    local greig = mq.TLO.Spawn("npc Grieg Veneficus")
    if mq.TLO.Spawn("npc Grieg Veneficus").ID() and mq.TLO.Me.XTarget("Grieg Veneficus").ID() and not (raidtimer < mq.gettime()) then
        local distSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), greig.X(), greig.Y())
        if distSq and distSq < (250 * 250) then GriegOut() end
    end
    return raidsactive
end

return M
