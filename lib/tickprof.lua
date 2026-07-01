-- Opt-in mainloop tick profiler: inter-tick gaps, processing time, per-hook breakdown.
local mq = require('mq')
local log = require('lib.log')

local TICK_MS = 100
local GAP_SLACK_MS = 50
local LOG_THROTTLE_MS = 1000
local HOOK_SLOW_MS = 5
local SUMMARY_INTERVAL_MS = 10000

local tickprof = {}

local _debug = false
local _verbose = false
local _lastTickStart = nil
local _lastProcMs = 0
local _currentTick = nil
local _delayedLogNextTime = 0

local _stats = {
    tickCount = 0,
    overCount = 0,
    delayedCount = 0,
    maxProc = 0,
    sumProc = 0,
}
local _summaryNextTime = 0

function tickprof.SetDebug(on)
    _debug = on and true or false
    if _debug then
        _summaryNextTime = mq.gettime() + SUMMARY_INTERVAL_MS
    else
        _currentTick = nil
    end
end

function tickprof.IsDebug()
    return _debug
end

function tickprof.SetVerbose(on)
    _verbose = on and true or false
end

function tickprof.IsVerbose()
    return _verbose
end

local function _formatHookBreakdown(hooks)
    if not hooks then return '' end
    local minMs = _verbose and 0 or HOOK_SLOW_MS
    local entries = {}
    for name, ms in pairs(hooks) do
        if ms >= minMs then
            entries[#entries + 1] = { name = name, ms = ms }
        end
    end
    table.sort(entries, function(a, b)
        if a.ms ~= b.ms then return a.ms > b.ms end
        return a.name < b.name
    end)
    if #entries == 0 then return '' end
    local parts = {}
    for _, e in ipairs(entries) do
        parts[#parts + 1] = string.format('%s=%dms', e.name, e.ms)
    end
    return ' hooks: ' .. table.concat(parts, ' ')
end

local function _runStateContext()
    local state = require('lib.state')
    local runState = state.getRunStateName() or 'nil'
    local busyCap = 'nil'
    if state.isBusy() then
        local payload = state.getRunStatePayload()
        if payload and type(payload.priority) == 'number' then
            busyCap = tostring(payload.priority)
        end
    end
    return runState, busyCap
end

local function _emitSummary(now)
    local ticks = _stats.tickCount
    if ticks == 0 then
        _summaryNextTime = now + SUMMARY_INTERVAL_MS
        return
    end
    local avgProc = math.floor(_stats.sumProc / ticks + 0.5)
    log.say('[tick] stats 10s: ticks=%d over=%d delayed=%d maxProc=%dms avgProc=%dms',
        ticks,
        _stats.overCount,
        _stats.delayedCount,
        _stats.maxProc,
        avgProc)
    _stats.tickCount = 0
    _stats.overCount = 0
    _stats.delayedCount = 0
    _stats.maxProc = 0
    _stats.sumProc = 0
    _summaryNextTime = now + SUMMARY_INTERVAL_MS
end

function tickprof.beginTick()
    if not _debug then return nil end
    local tickStart = mq.gettime()
    local gapMs = 0
    if _lastTickStart then
        gapMs = tickStart - _lastTickStart
    end
    _currentTick = {
        tickStart = tickStart,
        gapMs = gapMs,
        hooks = {},
    }
    return _currentTick
end

function tickprof.wrapHook(name, fn, arg)
    if not _debug or not _currentTick then
        fn(arg)
        return
    end
    local start = mq.gettime()
    fn(arg)
    local elapsed = mq.gettime() - start
    local hooks = _currentTick.hooks
    hooks[name] = (hooks[name] or 0) + elapsed
end

function tickprof.endTick(handle, paused)
    if not _debug or not handle then return end
    local now = mq.gettime()
    local procMs = now - handle.tickStart
    local gapMs = handle.gapMs or 0
    local expectedGap = _lastProcMs + TICK_MS
    local delayed = _lastTickStart ~= nil and gapMs > expectedGap + GAP_SLACK_MS
    local overBudget = procMs > TICK_MS

    _stats.tickCount = _stats.tickCount + 1
    _stats.sumProc = _stats.sumProc + procMs
    if procMs > _stats.maxProc then _stats.maxProc = procMs end
    if overBudget then _stats.overCount = _stats.overCount + 1 end
    if delayed then _stats.delayedCount = _stats.delayedCount + 1 end

    if overBudget then
        local runState, busyCap = _runStateContext()
        log.say('[tick] proc=%dms gap=%dms paused=%s runState=%s busyCap=%s%s',
            procMs,
            gapMs,
            tostring(paused == true),
            runState,
            busyCap,
            _formatHookBreakdown(handle.hooks))
    elseif delayed and now >= _delayedLogNextTime then
        _delayedLogNextTime = now + LOG_THROTTLE_MS
        log.say('[tick] delayed gap=%dms lastProc=%dms (expected ~%dms)',
            gapMs,
            _lastProcMs,
            expectedGap)
    end

    if now >= _summaryNextTime then
        _emitSummary(now)
    end

    _lastTickStart = handle.tickStart
    _lastProcMs = procMs
    _currentTick = nil
end

return tickprof
