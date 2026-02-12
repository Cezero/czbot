-- Zone 343: TSS (egg timer; Beltron, Hearol, Odeen, Gremlins, LTwo, Harfange)
local mq = require('mq') ---@cast mq mq

local M = {}

function HearolWalls() end

function OdeenBackOut() end

function GremlinsSpread() end

function LTwoMovement() end

function HarfangeClicks() end

function BeltronTimer() end

function BeltronCorner() end

function BeltronDone() end

mq.event('HearolWalls', "#*#HearolWallsGo#*#", HearolWalls)
mq.event('OdeenBackOut', "#*#You notice a glint from the steel arrowhead as an Archer of Zek levels his bow and takes#*#", OdeenBackOut)
mq.event('GremlinsSpread', "#*#GremlinsSpread#*#", GremlinsSpread)
mq.event('LTwoMovement', "#*#AGMove#*#", LTwoMovement)
mq.event('HarfangeClicks', "#*#HarfangeGoClick#*#", HarfangeClicks)
mq.event('HarfangeClicks2', "#*#Harfange calls to his guards sealed in the walls#*#", HarfangeClicks)
mq.event('BeltronTimer', "#*#Guards! Come deal with these pests!#*#", BeltronTimer)
mq.event('BeltronCorner', "#*#Guards! Come deal with these pests!#*#", BeltronCorner)
mq.event('BeltronCorner2', "#*#Beltron Four Corners#*#", BeltronCorner)
mq.event('BeltronDone', "#*#Beltron Back#*#", BeltronDone)

function M.raid_check()
    if mq.TLO.Zone.ID() ~= 343 then return false end
    if not mq.TLO.eggtimer and mq.TLO.Me.Class.ShortName():find("war") then
        if mq.TLO.Spawn("a tainted egg").ID() then
            mq.rs("EGG SPAWN!!")
            mq.varset("eggtimer", "30s")
        end
    end
    return raidsactive
end

return M
