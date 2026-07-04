local mq = require('mq')
local log = require('lib.log')

-- Require MQCharinfo before loading bot (so we can end macro if unavailable).
local ok, _ = pcall(require, 'plugin.charinfo')
if not ok then
    log.say('MQCharinfo (charinfo) is required but failed to load.')
    return
end

local okActors, _ = pcall(require, 'actors')
if not okActors then
    log.say('MQ actors module is required but failed to load.')
    return
end

-- Load required MQ plugins and end macro if any fail to load.
if not mq.TLO.Plugin('MQ2MoveUtils').IsLoaded() then mq.cmd('/squelch /plugin MQ2MoveUtils load') end
if not mq.TLO.Plugin('MQ2Twist').IsLoaded() then mq.cmd('/squelch /plugin MQ2Twist load') end
mq.delay(2000)
if not mq.TLO.Plugin('MQ2MoveUtils').IsLoaded() then
    log.say('MQ2MoveUtils is required but failed to load.')
    return
end
if not mq.TLO.Plugin('MQ2Twist').IsLoaded() then
    log.say('MQ2Twist is required but failed to load.')
    return
end

local botmelee = require('botmelee')
local botlogic = require('botlogic')
local spellutils = require('lib.spellutils')

botlogic.StartUp(...)
spellutils.Init({
    AdvCombat = botmelee.AdvCombat,
})
botlogic.mainloop()
