-- Single source of truth for mainloop hook names and priorities.
-- Hook registry wires implementations (registered by name) using this config.
-- Modules that set busy state use getPriority(ownerName) for payload.priority.
-- runWhenDead: when runState is 'dead' (DEAD/HOVER), only hooks with runWhenDead = true run; default false.

local hooks = {
    { name = 'zoneCheck', priority = 100 },
    { name = 'doEvents', priority = 200, runWhenDead = true },
    { name = 'charState', priority = 300, runWhenDead = true },
    { name = 'doRaid', priority = 350 },
    { name = 'ADSpawnCheck', priority = 400 },
    { name = 'chchainTick', priority = 500 },
    { name = 'doMelee', priority = 600 },
    { name = 'priorityCure', priority = 700 },
    { name = 'doPull', priority = 800 },
    { name = 'doHeal', priority = 900 },
    { name = 'doDebuff', priority = 1000 },
    { name = 'doBuff', priority = 1100 },
    { name = 'doCure', priority = 1200 },
    { name = 'doMiscTimer', priority = 1400 },
}

local bothooks = {}

function bothooks.getHooks()
    return hooks
end

function bothooks.getPriority(name)
    if not name then return nil end
    for _, entry in ipairs(hooks) do
        if entry.name == name then
            return entry.priority
        end
    end
    return nil
end

return bothooks
