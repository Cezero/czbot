-- Zone 317: Ture, OMM (OoW)
local mq = require('mq') ---@cast mq mq

local M = {}

function OMMGaze() end

function TureBackOut() end

function TureBackIn() end

mq.event('OMMGaze', "#*#You feel a gaze of deadly power focusing on you.#*#", OMMGaze)
mq.event('TureBackOut', "#*#Ture roars with fury as it surveys its attackers.#*#", TureBackOut)
mq.event('TureBackIn', "#*#Ture calms and regains its focus.#*#", TureBackIn)

function M.raid_check()
    return false
end

return M
