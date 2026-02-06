local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')
local M = {}

local LIST_CONFIG = {
    exclude = {
        commonKey = 'excludelist',
        runconfigKey = 'ExcludeList',
        onZoneLoad = function()
            mq.cmdf('/squelch /alert clear %s', state.getRunconfig().AlertList)
        end,
    },
    priority = {
        commonKey = 'prioritylist',
        runconfigKey = 'PriorityList',
        onZoneLoad = nil,
    },
}

local function saveList(listType)
    local opts = LIST_CONFIG[listType]
    if not opts then return end
    local comkeytable = botconfig.getCommon()
    if not comkeytable[opts.commonKey] then comkeytable[opts.commonKey] = {} end
    comkeytable[opts.commonKey][mq.TLO.Zone.ShortName()] = state.getRunconfig()[opts.runconfigKey]
    botconfig.saveCommon()
end

local function loadZone(listType)
    local opts = LIST_CONFIG[listType]
    if not opts then return end
    local comkeytable = botconfig.getCommon()
    local zone = mq.TLO.Zone.ShortName()
    state.getRunconfig()[opts.runconfigKey] = (comkeytable[opts.commonKey] and comkeytable[opts.commonKey][zone]) or ''
    if opts.onZoneLoad then opts.onZoneLoad() end
end

function M.process(listType, command)
    if command == 'save' then
        saveList(listType)
    elseif command == 'zone' then
        loadZone(listType)
    end
end

return M
