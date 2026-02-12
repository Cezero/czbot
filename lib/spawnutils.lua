-- Centralized add/spawn detection, counting, and filtering.
-- AddSpawnCheck hook, buildCampMobList, buildPullMobList, and shared helpers.

local mq = require('mq') ---@cast mq mq
local botconfig = require('lib.config')
local state = require('lib.state')
local utils = require('lib.utils')

local spawnutils = {}

-- ---------------------------------------------------------------------------
-- Local helpers (DRY)
-- ---------------------------------------------------------------------------

local function spawnInArea(spawn, x, y, z, radius2DSq, radiusZ)
    if not spawn or not x or not y then return false end
    local sx, sy, sz = spawn.X(), spawn.Y(), spawn.Z()
    local pdistSq = utils.getDistanceSquared2D(sx, sy, x, y)
    if not pdistSq or not radius2DSq or pdistSq > radius2DSq then return false end
    if radiusZ and z and sz then
        local zdist = math.abs(sz - z)
        if zdist > radiusZ then return false end
    end
    return true
end

local function getSpawnsInArea(rc, radius2DSq, radiusZ)
    local cx, cy, cz
    if rc.campstatus and rc.makecamp and rc.makecamp.x and rc.makecamp.y then
        cx, cy, cz = rc.makecamp.x, rc.makecamp.y, rc.makecamp.z
    else
        cx, cy, cz = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
    end
    local function predicate(spawn)
        return spawnInArea(spawn, cx, cy, cz, radius2DSq, radiusZ)
    end
    return mq.getFilteredSpawns(predicate)
end

function spawnutils.FTECheck(spawnId, rc)
    if not spawnId then return true end
    rc = rc or state.getRunconfig()
    if rc.engagetracker then
        for k, v in pairs(rc.engagetracker) do
            if mq.gettime() > v then rc.engagetracker[k] = nil end
            if k == spawnId then return true end
        end
    end
    if spawnId and rc.FTEList and rc.FTEList[spawnId] and (rc.FTEList[spawnId].timer + 60000) > mq.gettime() + 60000 then
        return true
    end
    return false
end

function spawnutils.filterSpawnExcludeAndFTE(spawn, rc)
    rc = rc or state.getRunconfig()
    local spawnname = spawn.CleanName() or 'none'
    local list = rc.ExcludeList or {}
    for _, n in ipairs(list) do
        if n == spawnname then return false end
    end
    if spawnutils.FTECheck(spawn.ID(), rc) then return false end
    return true
end

local function filterSpawnTargetFilter(spawn, targetFilterNum)
    if targetFilterNum == 2 then
        return not string.find('pc,banner,campfire,mercenary,mount,aura,corpse', string.lower(spawn.Type()))
    end
    if targetFilterNum == 1 then
        return (spawn.Type() == 'NPC' or (spawn.Type() == 'Pet' and spawn.Master.Type() ~= 'PC')) and spawn.LineOfSight()
    end
    if targetFilterNum == 0 then
        return (spawn.Type() == 'NPC' or (spawn.Type() == 'Pet' and spawn.Master.Type() ~= 'PC')) and spawn.Aggressive() and spawn.LineOfSight()
    end
    return false
end

local function filterSpawnForCamp(spawn, rc)
    local myconfig = botconfig.config
    local acleashSq = myconfig.settings.acleashSq
    local zradius = myconfig.settings.zradius or 75
    local cx, cy, cz
    if rc.campstatus and rc.makecamp and rc.makecamp.x and rc.makecamp.y then
        cx, cy, cz = rc.makecamp.x, rc.makecamp.y, rc.makecamp.z
    else
        cx, cy, cz = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
    end
    if not spawnInArea(spawn, cx, cy, cz, acleashSq, zradius) then return false end
    if not spawnutils.filterSpawnExcludeAndFTE(spawn, rc) then return false end
    local tfNum = myconfig.settings.TargetFilter or 0
    return filterSpawnTargetFilter(spawn, tfNum)
end

local function spawnInPullArc(spawn, rc)
    if not spawn or not rc.pullarc or rc.pullarc <= 0 then return true end
    local campx, campy = rc.makecamp and rc.makecamp.x, rc.makecamp and rc.makecamp.y
    if not campx or not campy then return true end
    local fdir = mq.TLO.Me.Heading.Degrees()
    local arcLside, arcRside
    if (fdir - (rc.pullarc * 0.5)) < 0 then
        arcLside = 360 - ((rc.pullarc * 0.5) - fdir)
    else
        arcLside = fdir - (rc.pullarc * 0.5)
    end
    if (fdir + (rc.pullarc * 0.5)) > 360 then
        arcRside = ((rc.pullarc * 0.5) + fdir) - 360
    else
        arcRside = fdir + (rc.pullarc * 0.5)
    end
    local dirToMob = spawn.HeadingTo(campy, campx).Degrees()
    if arcLside >= arcRside then
        if dirToMob < arcLside and dirToMob > arcRside then return false end
    else
        if dirToMob < arcLside or dirToMob > arcRside then return false end
    end
    return true
end

local function filterSpawnForPull(spawn, rc)
    local myconfig = botconfig.config
    local pull = myconfig.pull
    if not pull then return false end
    if spawn.Type() ~= 'NPC' then return false end
    -- Level/con filtering: usePullLevels => min/max level; else con range + maxLevelDiff
    if pull.usePullLevels then
        local minl = pull.pullMinLevel or 0
        local maxl = pull.pullMaxLevel or 255
        if spawn.Level() < minl or spawn.Level() > maxl then return false end
    else
        local conName = spawn.ConColor()
        local conLevel = conName and botconfig.ConColorsNameToId[conName:upper()] or 0
        if conLevel < 1 then conLevel = 1 end
        local minCon = pull.pullMinCon or 1
        local maxCon = pull.pullMaxCon or 7
        if conLevel < minCon or conLevel > maxCon then return false end
        local maxLvl = mq.TLO.Me.Level() + (pull.maxLevelDiff or 6)
        if spawn.Level() > maxLvl then return false end
    end
    local radiusSq = pull.radiusSq
    local zrange = pull.zrange or 200
    local cx = (rc.makecamp and rc.makecamp.x) or mq.TLO.Me.X()
    local cy = (rc.makecamp and rc.makecamp.y) or mq.TLO.Me.Y()
    local cz = (rc.makecamp and rc.makecamp.z) or mq.TLO.Me.Z()
    if not spawnInArea(spawn, cx, cy, cz, radiusSq, zrange) then return false end
    if not spawnInPullArc(spawn, rc) then return false end
    if not spawnutils.filterSpawnExcludeAndFTE(spawn, rc) then return false end
    if not mq.TLO.Navigation.PathExists('id ' .. spawn.ID())() then return false end
    if rc.MobList then
        for _, v in pairs(rc.MobList) do
            if v.ID() == spawn.ID() then return false end
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function spawnutils.buildCampMobList(rc)
    rc = rc or state.getRunconfig()
    local myconfig = botconfig.config
    local acleashSq = myconfig.settings.acleashSq
    local zradius = myconfig.settings.zradius or 75
    local raw = getSpawnsInArea(rc, acleashSq, zradius)
    local out = {}
    for _, spawn in ipairs(raw) do
        if filterSpawnForCamp(spawn, rc) then
            table.insert(out, spawn)
        end
    end
    table.sort(out, function(a, b) return a.ID() < b.ID() end)
    return out, #out
end

function spawnutils.buildPullMobList(rc)
    rc = rc or state.getRunconfig()
    local myconfig = botconfig.config
    local pull = myconfig.pull
    if not pull then return {} end
    local radiusSq = pull.radiusSq
    local zrange = pull.zrange or 200
    local raw = getSpawnsInArea(rc, radiusSq, zrange)
    local out = {}
    for _, spawn in ipairs(raw) do
        if filterSpawnForPull(spawn, rc) then
            table.insert(out, spawn)
        end
    end
    return out
end

function spawnutils.selectNthAdd(mobList, excludeId, n)
    if not mobList or not n or n < 1 then return nil end
    local idx = 0
    for _, v in ipairs(mobList) do
        local id = v.ID and v.ID() or v
        if id and id ~= excludeId then
            idx = idx + 1
            if idx == n then return v end
        end
    end
    return nil
end

local function validateAcmTarget(rc)
    if rc.engageTargetId then
        if not mq.TLO.Spawn(rc.engageTargetId).ID() or mq.TLO.Spawn(rc.engageTargetId).Type() == 'Corpse' then
            rc.engageTargetId = nil
        end
    end
    if utils.isNonCombatZone(mq.TLO.Zone.ShortName()) then return false end
    return true
end

function spawnutils.AddSpawnCheck()
    local rc = state.getRunconfig()
    if not validateAcmTarget(rc) then return end
    local list, count = spawnutils.buildCampMobList(rc)
    rc.MobList = list
    local killtarpresent = false
    local KillTarget = rawget(_G, 'KillTarget')
    if KillTarget and (mq.TLO.Spawn(KillTarget).Type() == 'Corpse' or not mq.TLO.Spawn(KillTarget).ID()) then
        _G.KillTarget = nil
        KillTarget = nil
    end
    rc.MobCount = count
    for _, v in ipairs(rc.MobList) do
        if v.ID() == KillTarget then killtarpresent = true end
    end
    if not killtarpresent and KillTarget then
        table.insert(rc.MobList, mq.TLO.Spawn(KillTarget))
    end
end

function spawnutils.getHookFn(name)
    if name == 'AddSpawnCheck' then
        return function()
            spawnutils.AddSpawnCheck()
        end
    end
    return nil
end

return spawnutils
