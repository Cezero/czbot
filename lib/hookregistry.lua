-- Mainloop hook registry: modules require this and call registerMainloopHook.
-- Lower priority runs first. runWhenPaused = true runs every iteration even when MasterPause is set.
--
-- Always-run hooks (runWhenPaused = true): Must run every tick; never block. Use for:
--   - plugin.charinfo (network sync)
--   - Any logic that must fire regardless of runState (pulling, casting, etc.)
-- Normal hooks: Skipped when MasterPause; some skip when state.isBusy() (e.g. buff/heal/pull).
local _hooks = {}
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

function hookregistry.registerMainloopHook(name, fn, priority, runWhenPaused)
    _hooks[#_hooks + 1] = {
        name = name,
        fn = fn,
        priority = priority or 500,
        runWhenPaused = runWhenPaused == true,
    }
    _sortedNormal = nil
    _sortedRunWhenPaused = nil
end

function hookregistry.unregisterMainloopHook(name)
    for i = #_hooks, 1, -1 do
        if _hooks[i].name == name then
            table.remove(_hooks, i)
            break
        end
    end
    _sortedNormal = nil
    _sortedRunWhenPaused = nil
end

function hookregistry.runRunWhenPausedHooks()
    if _sortedRunWhenPaused == nil then _rebuildSorted() end
    for _, h in ipairs(_sortedRunWhenPaused) do
        h.fn()
    end
end

function hookregistry.runNormalHooks()
    if _sortedNormal == nil then _rebuildSorted() end
    for _, h in ipairs(_sortedNormal) do
        h.fn()
    end
end

return hookregistry
