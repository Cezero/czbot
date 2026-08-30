-- Activate the configured inventory bandolier when this bot's Main Tank role changes.
-- melee.bandolierTank / melee.bandolierDps: blank means no switch for that role.

local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')
local tankrole = require('lib.tankrole')
local log = require('lib.log')

local M = {}

local _lastAppliedName = nil

local function trimName(s)
    if type(s) ~= 'string' then return '' end
    return (s:match('^%s*(.-)%s*$')) or ''
end

--- Apply the configured bandolier for the current MT role. Safe to call every tick.
function M.tick()
    if state.isDeadOrHover() then return end
    local melee = botconfig.config.melee
    if not melee then return end

    local isMt = tankrole.AmIMainTank()
    local name = trimName(isMt and melee.bandolierTank or melee.bandolierDps)
    if name == '' then return end
    if name == _lastAppliedName then return end

    mq.cmdf('/bandolier activate "%s"', name)
    _lastAppliedName = name
    log.say('Bandolier: %s "%s"', isMt and 'tank' or 'dps', name)
end

return M
