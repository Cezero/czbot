-- Zone 128: Milas An`Rev (Velious)
local mq = require('mq')
local utils = require('lib.utils')

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
    local milas = mq.TLO.Spawn("Milas An`Rev")
    if milas.ID() and mq.TLO.Me.XTarget("Milas An`Rev").ID() and (raidtimer < mq.gettime()) then
        local distSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), milas.X(), milas.Y())
        if distSq and distSq < (400 * 400) then MilasOut() end
    end
    return raidsactive
end

return M
