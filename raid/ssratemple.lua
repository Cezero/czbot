-- Zone 162: Vyzh`dra the Cursed (Luclin)
local mq = require('mq') ---@cast mq mq
local utils = require('lib.utils')

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
    local cursed = mq.TLO.Spawn("Vyzh`dra the Cursed")
    if cursed.ID() and mq.TLO.Me.XTarget("Vyzh`dra the Cursed").ID() and not (raidtimer < mq.gettime()) then
        local distSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), cursed.X(), cursed.Y())
        if distSq and distSq < (250 * 250) then CursedOut() end
    end
    return raidsactive
end

return M
