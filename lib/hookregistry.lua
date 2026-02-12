-- Mainloop hook registry: modules require this and call registerMainloopHook.
-- Lower priority runs first. runWhenPaused = true runs every iteration even when MasterPause is set.
--
-- Always-run hooks (runWhenPaused = true): Must run every tick; never block. Use for:
--   - mqcharinfo (network sync)
--   - Any logic that must fire regardless of runState (pulling, casting, etc.)
-- Normal hooks: Skipped when MasterPause. When state is busy and payload has priority,
--   only hooks with hook.priority <= payload.priority run (higher-priority hooks and the busy-holding hook).
local _hooks = {}
local _hookFns = {} -- name -> function (implementations registered by modules)
local _sortedNormal = nil
local _sortedRunWhenPaused = nil

local function _rebuildSorted()
    local function byPriorityThenName(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return (a.name or '') < (b.name or '')
    end
    local runWhenPaused = {}
    local normal = {}
    for _, h in ipairs(_hooks) do
        if h.runWhenPaused then
            runWhenPaused[#runWhenPaused + 1] = h
        else
            normal[#normal + 1] = h
        end
    end
    table.sort(runWhenPaused, byPriorityThenName)
    table.sort(normal, byPriorityThenName)
    _sortedRunWhenPaused = runWhenPaused
    _sortedNormal = normal
end

local hookregistry = {}

function hookregistry.registerHookFn(name, fn)
    _hookFns[name] = fn
end

--- Wire all hooks from bothooks config. Call after built-in hooks have registerHookFn'd.
--- For entries with provider, requires that module and calls mod.getHookFn(entry.name).
function hookregistry.registerAllFromConfig()
    local bothooks = require('lib.bothooks')
    for _, entry in ipairs(bothooks.getHooks()) do
        local fn
        if entry.provider then
            local mod = require(entry.provider)
            if mod.getHookFn then fn = mod.getHookFn(entry.name) end
        else
            fn = _hookFns[entry.name]
        end
        if fn then
            hookregistry.registerMainloopHook(entry.name, fn, entry.priority, entry.runWhenPaused, entry.runWhenDead)
        end
    end
end

function hookregistry.registerMainloopHook(name, fn, priority, runWhenPaused, runWhenDead)
    _hooks[#_hooks + 1] = {
        name = name,
        fn = fn,
        priority = priority or 500,
        runWhenPaused = runWhenPaused == true,
        runWhenDead = runWhenDead == true,
    }
    _sortedNormal = nil
    _sortedRunWhenPaused = nil
end

function hookregistry.runRunWhenPausedHooks()
    if _sortedRunWhenPaused == nil then _rebuildSorted() end
    local list = _sortedRunWhenPaused or {}
    for _, h in ipairs(list) do
        h.fn(h.name)
    end
end

function hookregistry.runNormalHooks()
    if _sortedNormal == nil then _rebuildSorted() end
    local list = _sortedNormal or {}
    local state = require('lib.state')
    local runState = state.getRunState()
    if runState == 'dead' then
        for _, h in ipairs(list) do
            if h.runWhenDead then
                h.fn(h.name)
            end
        end
        return
    end
    local maxPriority = nil
    if state.isBusy() then
        local payload = state.getRunStatePayload()
        if payload and type(payload.priority) == 'number' then
            maxPriority = payload.priority
        end
    end
    for _, h in ipairs(list) do
        if maxPriority == nil or h.priority <= maxPriority then
            h.fn(h.name)
        end
    end
end

return hookregistry
