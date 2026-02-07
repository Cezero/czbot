local registry = require('actornet.command_registry')
local charinfo = require('actornet.charinfo')

local M = {}

function M.publish()
    charinfo.publish()
end

function M.cleanup()
    charinfo.remove()
    registry.clear()
end

M.charinfo = charinfo

return M
