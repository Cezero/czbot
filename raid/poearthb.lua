-- Zone 222: Rathe Council (PoP)
local mq = require('mq') ---@cast mq mq
local utils = require('lib.utils')

local M = {}

function RatheKill()
end

mq.event('RatheKill', "#*#rkill engage#*#", RatheKill)

function RatheCouncil()
    -- Stub: implement or remove when zone logic is finalized
end

function M.raid_check()
    if mq.TLO.Zone.ID() ~= 222 then return false end
    local councilman = mq.TLO.Spawn("npc A Rathe Councilman")
    if mq.TLO.Spawn("A Rathe Councilman").ID() and councilman.ID() then
        local distSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), councilman.X(), councilman.Y())
        if distSq and distSq < (250 * 250) then
            RatheCouncil()
        end
    end
    return false
end

return M
