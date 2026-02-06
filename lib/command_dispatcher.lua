-- Command dispatcher: registry of cmd -> handler(args, str). No dependency on commands/chchain/botevents.

local _handlers = {}

local M = {}

function M.RegisterCommand(cmd, handler)
    _handlers[string.lower(cmd)] = handler
end

function M.Dispatch(cmd, ...)
    local args = { cmd, ... }
    local str = table.concat(args, ' ')
    local fn = cmd and _handlers[string.lower(cmd)]
    if fn then
        local ok = fn(args, str)
        if ok == false then return false end
    end
end

return M
