-- Shared CZBot chat output with session-ms timestamp prefix.
local mq = require('mq')

local log = {}

local PREFIX = '\ayCZBot:\ax t=%s '

function log.say(fmt, ...)
    printf(PREFIX .. fmt, tostring(mq.gettime()), ...)
end

function log.fmt(fmt, ...)
    return string.format(PREFIX .. fmt, tostring(mq.gettime()), ...)
end

return log
