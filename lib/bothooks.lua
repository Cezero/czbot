-- Single source of truth for mainloop hook names and priorities.
-- Hook registry wires implementations (registered by name) using this config.
-- Modules that set busy state use getPriority(ownerName) for payload.priority.
-- runWhenDead: when runState is 'dead' (DEAD/HOVER), only hooks with runWhenDead = true run; default false.
-- runWhenBusy: when state.isBusy(), these hooks run in a second pass after the priority loop (so e.g. movement runs even when casting).

-- Hook names and priorities. Optional 'provider': module name; registry will require it and call mod.getHookFn(name).
local hooks = {
    { name = 'zoneCheck', priority = 100 },
    { name = 'doEvents', priority = 200, runWhenDead = true },
    { name = 'charState', priority = 300, runWhenDead = true },
    { name = 'doRaid', priority = 350, provider = 'botraid' },
    { name = 'AddSpawnCheck', priority = 400, provider = 'lib.spawnutils' },
    { name = 'chchainTick', priority = 500, provider = 'lib.chchain' },
    { name = 'doMelee', priority = 600, provider = 'botmelee' },
    { name = 'priorityCure', priority = 700, provider = 'botcure' },
    { name = 'doPull', priority = 800, provider = 'botpull' },
    { name = 'doHeal', priority = 900, provider = 'botheal' },
    { name = 'doDebuff', priority = 1000, provider = 'botdebuff' },
    { name = 'doBuff', priority = 1100, provider = 'botbuff' },
    { name = 'doCure', priority = 1200, provider = 'botcure' },
    { name = 'doMovementCheck', priority = 1350, runWhenBusy = true },
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
