local registry = require('actornet.command_registry')
local charinfo = require('actornet.charinfo')
local rexec = require('actornet.rexec')

local M = {}

function M.init()
    require('actornet.commands')
end

function M.publish()
    charinfo.publish()
end

function M.cleanup()
    charinfo.remove()
    registry.clear()
end

M.rexec = rexec
M.charinfo = charinfo

return M
