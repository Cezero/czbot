-- Zone 305: Foresight trial (GoD)
local mq = require('mq') ---@cast mq mq

local M = {}

function ForesightDuck() end

function ForesightStill() end

mq.event('ForesightDuck', "#*#From the corner of your eye, you notice a Kyv taking aim at your head. You should duck.#*#", ForesightDuck)
mq.event('ForesightStill',
    "#*#From the corner of your eye, you notice a Kyv taking aim near your position. He appears to be leading the target, anticipating your next movement. You should stand still.#*#",
    ForesightStill)

function M.raid_check()
    return false
end

return M
