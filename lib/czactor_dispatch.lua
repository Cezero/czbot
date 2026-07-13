-- Extension handler registry for czbot actor messages (mirrors lib/command_dispatcher).
-- Feature modules RegisterHandler(id, fn); lib/czactor.lua Dispatch() delegates after core protocol.

local _handlers = {}

local M = {}

local SKIP_KEYS = { id = true, ver = true, ts = true, zone = true }

local ROLE_CLAIM_DEBUG_IDS = {
    im_ma = true,
    im_mt = true,
    whos_ma = true,
    whos_mt = true,
    release_ma = true,
    release_mt = true,
}

local _roleClaimLogDebug = false

function M.SetRoleClaimLogDebug(on)
    _roleClaimLogDebug = on and true or false
end

function M.IsRoleClaimLogDebug()
    return _roleClaimLogDebug
end

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

function M.isRoleClaimDebugId(id)
    return ROLE_CLAIM_DEBUG_IDS[id] == true
end

local function isChchainId(id)
    return type(id) == 'string' and id:find('^chchain_', 1, true) ~= nil
end

local function shouldLogChchain()
    if _roleClaimLogDebug then return true end
    local ok, st = pcall(require, 'lib.state')
    if ok then
        local rc = st.getRunconfig()
        if rc and rc.doChchain then return true end
    end
    return false
end

function M.logSend(id, fields)
    if ROLE_CLAIM_DEBUG_IDS[id] and not _roleClaimLogDebug then return end
    if isChchainId(id) and not shouldLogChchain() then return end
    printf('czactor send %s: %s', tostring(id), M.formatFields(fields))
end

function M.logRecv(id, sender, content)
    printf('czactor recv %s from %s: %s', tostring(id), tostring(sender), M.formatFields(content))
end

--- Gated recv log for core role-claim protocol (im_*, release_*).
function M.logRecvIfRoleClaimDebug(id, sender, content)
    if not _roleClaimLogDebug or not ROLE_CLAIM_DEBUG_IDS[id] then return end
    M.logRecv(id, sender, content)
end

--- Gated reject log when applyImMa / applyImMt decline a claim.
function M.logRoleClaimReject(messageId, reason, sender, detail)
    if not _roleClaimLogDebug then return end
    local msg = string.format('czactor %s rejected: %s (sender=%s)',
        tostring(messageId), tostring(reason), tostring(sender))
    if detail and detail ~= '' then
        msg = msg .. ' ' .. tostring(detail)
    end
    printf('%s', msg)
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
    if not isChchainId(id) or shouldLogChchain() then
        M.logRecv(id, sender, content)
    end
    fn(content, sender)
    return true
end

return M
