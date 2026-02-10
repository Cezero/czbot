-- Zone 124: Lady Nevederia, Dozekar (Velious)
local mq = require('mq')
local utils = require('lib.utils')

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
    local ladynev = mq.TLO.Spawn("Lady Nevederia")
    if ladynev.ID() and mq.TLO.Me.XTarget("Lady Nevederia").ID() and (raidtimer < mq.gettime()) then
        local distSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), ladynev.X(), ladynev.Y())
        if distSq and distSq < (250 * 250) then LadyNevBreathOut() end
    end
    local dozekar = mq.TLO.Spawn("Dozekar the Cursed")
    if dozekar.ID() and mq.TLO.Me.XTarget("Dozekar the Cursed").ID() and (raidtimer < mq.gettime()) then
        local distSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), dozekar.X(), dozekar.Y())
        if distSq and distSq < (250 * 250) then DozeOut() end
    end
    return raidsactive
end

return M
