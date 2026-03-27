local mq = require('mq')

local casting = {}

local CAST_MEMO_TIMEOUT_MS = 16000
local CAST_BEGIN_TIMEOUT_MS = 1500
local CAST_FINISH_TIMEOUT_MS = 16000

local RETRYABLE_RESULTS = {
    CAST_FIZZLE = true,
    CAST_INTERRUPTED = true,
    CAST_ABORTED = true,
    CAST_RECOVER = true,
    CAST_RESIST = true,
}

---@class CastingOp
---@field request table
---@field status string
---@field result string
---@field phase string
---@field tries number
---@field maxTries number
---@field spellId number
---@field deadline number
---@field startedAt number
---@field wasCastingSeen boolean
---@type CastingOp|nil
local _active = nil
local _last = {
    status = '',
    result = '',
    storedSpellId = 0,
}

local function getSpellIdFromRequest(req)
    if req.spellId and req.spellId > 0 then return req.spellId end
    if req.gemType == 'item' and req.spellName and mq.TLO.FindItem(req.spellName)() then
        return mq.TLO.FindItem(req.spellName).Spell.ID() or 0
    end
    if req.gemType == 'alt' and req.spellName and mq.TLO.Me.AltAbility(req.spellName)() then
        return mq.TLO.Me.AltAbility(req.spellName).Spell.ID() or 0
    end
    if req.spellName then
        return mq.TLO.Spell(req.spellName).ID() or 0
    end
    return 0
end

local function applyTarget(req)
    if not req or not req.targetId or req.targetId <= 0 then return true end
    if req.allowNoTarget or req.isSelfTarget then return true end
    if mq.TLO.Target.ID() == req.targetId then return true end
    mq.cmdf('/squelch /tar id %s', tostring(req.targetId))
    return mq.TLO.Target.ID() == req.targetId
end

local function beginCast(req)
    local gemType = req.gemType
    if not _active then return false end
    if type(gemType) == 'number' then
        mq.cmdf('/multiline ; /nav stop log=off ; /cast %s', tostring(gemType))
    elseif gemType == 'item' then
        mq.cmdf('/multiline ; /nav stop log=off ; /cast item "%s"', tostring(req.spellName or ''))
    elseif gemType == 'alt' then
        local aaId = mq.TLO.Me.AltAbility(req.spellName)()
        if not aaId then
            _active.result = 'CAST_NOTREADY'
            _active.status = ''
            return false
        end
        mq.cmdf('/multiline ; /nav stop log=off ; /alt act %s', tostring(aaId))
    else
        _active.result = 'CAST_INVALID'
        _active.status = ''
        return false
    end
    _active.phase = 'cast_begin'
    _active.status = 'C'
    _active.wasCastingSeen = false
    _active.startedAt = mq.gettime()
    _active.deadline = _active.startedAt + CAST_BEGIN_TIMEOUT_MS
    return true
end

local function ensureMemorizedIfNeeded(req)
    if not _active then return false end
    if type(req.gemType) ~= 'number' then return true end
    local slot = req.gemType
    local spellName = req.spellName
    if not spellName or spellName == '' then return true end
    local inGem = mq.TLO.Me.Gem(slot)() or ''
    if string.lower(inGem) == string.lower(spellName) then
        return true
    end
    if not mq.TLO.Me.Book(spellName)() then
        _active.result = 'CAST_NOTMEMMED'
        _active.status = ''
        return false
    end
    mq.cmdf('/memspell %s "%s"', tostring(slot), spellName)
    _active.phase = 'memorizing'
    _active.status = 'M'
    _active.deadline = mq.gettime() + CAST_MEMO_TIMEOUT_MS
    return false
end

local function finishWithResult(result)
    if not _active then return end
    _active.result = result or _active.result or 'CAST_SUCCESS'
    _active.status = ''
    _active.phase = 'done'
    _last.status = _active.status
    _last.result = _active.result
    _last.storedSpellId = _active.spellId or 0
end

local function tryRetry()
    if not _active then return false end
    if not RETRYABLE_RESULTS[_active.result or ''] then return false end
    if (_active.tries or 1) >= (_active.maxTries or 1) then return false end
    _active.tries = (_active.tries or 1) + 1
    _active.result = ''
    if not ensureMemorizedIfNeeded(_active.request) then return true end
    return beginCast(_active.request)
end

function casting.start(request)
    if not request then return false end
    if _active and _active.phase and _active.phase ~= 'done' then return false end

    _active = {
        request = request,
        status = '',
        result = '',
        phase = 'init',
        tries = 1,
        maxTries = tonumber(request.maxTries) or 1,
        spellId = getSpellIdFromRequest(request),
        deadline = mq.gettime() + CAST_FINISH_TIMEOUT_MS,
        startedAt = mq.gettime(),
        wasCastingSeen = false,
    }
    _last.status = ''
    _last.result = ''
    _last.storedSpellId = _active.spellId or 0

    applyTarget(request)
    if not ensureMemorizedIfNeeded(request) then
        return true
    end
    return beginCast(request)
end

function casting.tick()
    if not _active then return end
    if _active.phase == 'done' then return end

    if _active.phase == 'memorizing' then
        local req = _active.request
        local inGem = mq.TLO.Me.Gem(req.gemType)() or ''
        if req.spellName and string.lower(inGem) == string.lower(req.spellName) then
            beginCast(req)
            return
        end
        if mq.gettime() >= (_active.deadline or 0) then
            _active.result = 'CAST_MEMORIZETIMEOUT'
            if not tryRetry() then finishWithResult(_active.result) end
            return
        end
        return
    end

    local castTimeLeft = mq.TLO.Me.CastTimeLeft() or 0
    local isCasting = mq.TLO.Me.Casting() or castTimeLeft > 0
    if isCasting then
        _active.wasCastingSeen = true
        _active.status = 'C'
        _active.deadline = mq.gettime() + CAST_FINISH_TIMEOUT_MS
        _last.status = _active.status
        return
    end

    if _active.phase == 'cast_begin' and not _active.wasCastingSeen then
        if mq.gettime() >= (_active.deadline or 0) then
            _active.result = _active.result ~= '' and _active.result or 'CAST_RECOVER'
            if not tryRetry() then finishWithResult(_active.result) end
        end
        return
    end

    if _active.result == '' then _active.result = 'CAST_SUCCESS' end
    if not tryRetry() then finishWithResult(_active.result) end
end

function casting.status()
    if _active and _active.phase ~= 'done' then return _active.status or '' end
    return _last.status or ''
end

function casting.result()
    if _active and _active.phase ~= 'done' then return _active.result or '' end
    return _last.result or ''
end

function casting.storedSpellId()
    if _active then return _active.spellId or 0 end
    return _last.storedSpellId or 0
end

function casting.isMemorizing()
    return (_active and _active.phase == 'memorizing') or false
end

function casting.interrupt()
    if not _active or _active.phase == 'done' then
        mq.cmd('/stopcast')
        _last.result = 'CAST_ABORTED'
        return
    end
    if _active.phase == 'memorizing' then
        _active.result = 'CAST_ABORTED'
        finishWithResult('CAST_ABORTED')
        return
    end
    mq.cmd('/stopcast')
    _active.result = 'CAST_INTERRUPTED'
    if not tryRetry() then finishWithResult(_active.result) end
end

function casting.notifyResult(result)
    if not result or result == '' then return end
    if _active and _active.phase ~= 'done' then
        _active.result = result
    else
        _last.result = result
    end
end

function casting.notifyResist()
    casting.notifyResult('CAST_RESIST')
end

function casting.notifyImmune()
    casting.notifyResult('CAST_IMMUNE')
end

function casting.notifyTakeHold()
    casting.notifyResult('CAST_TAKEHOLD')
end

function casting.clear()
    _active = nil
    _last.status = ''
    _last.result = ''
    _last.storedSpellId = 0
end

return casting
