-- Extension handler registry for czbot actor messages (mirrors lib/command_dispatcher).
-- Feature modules RegisterHandler(id, fn); lib/czactor.lua Dispatch() delegates after core protocol.

local _handlers = {}

local M = {}

local SKIP_KEYS = { id = true, ver = true, ts = true, zone = true }

function M.formatFields(t)
    if type(t) ~= 'table' then return '' end
    local parts = {}
    for k, v in pairs(t) do
        if not SKIP_KEYS[k] then
            parts[#parts + 1] = string.format('%s=%s', tostring(k), tostring(v))
        end
    end
    table.sort(parts)
    return table.concat(parts, ' ')
end

function M.logSend(id, fields)
    printf('czactor send %s: %s', tostring(id), M.formatFields(fields))
end

function M.logRecv(id, sender, content)
    printf('czactor recv %s from %s: %s', tostring(id), tostring(sender), M.formatFields(content))
end

function M.RegisterHandler(messageId, fn)
    if messageId and fn then
        _handlers[messageId] = fn
    end
end

--- Returns true if a registered handler ran.
function M.Dispatch(content, sender)
    local id = content and content.id
    local fn = id and _handlers[id]
    if not fn then return false end
    M.logRecv(id, sender, content)
    fn(content, sender)
    return true
end

return M
