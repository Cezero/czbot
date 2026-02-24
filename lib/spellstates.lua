local mq = require('mq')
local spellstates = {}

-- Module-local state: spawn/target -> spell duration tracking and debuff delay/recast counters
local DebuffList = {}
local recastcntr = {}
local concussionCounter = {}
local DebuffDlyLst = {}
local ReagentDlyLst = {}

function spellstates.EnsureDebuffState()
    DebuffList = DebuffList or {}
    recastcntr = recastcntr or {}
    concussionCounter = concussionCounter or {}
    DebuffDlyLst = DebuffDlyLst or {}
    ReagentDlyLst = ReagentDlyLst or {}
end

function spellstates.SetReagentDelay(sub, index, expireTime)
    if not ReagentDlyLst[sub] then ReagentDlyLst[sub] = {} end
    ReagentDlyLst[sub][index] = expireTime
end

function spellstates.GetReagentDelay(sub, index)
    if not ReagentDlyLst[sub] then return nil end
    return ReagentDlyLst[sub][index]
end

function spellstates.DebuffListUpdate(spawnID, spell, duration)
    local spellid = mq.TLO.Spell(spell).ID() or mq.TLO.FindItem(spell).Spell.ID()
    local sp = mq.TLO.Spell(spellid)
    local sec = 0
    if sp and sp.MyDuration then
        sec = tonumber(sp.MyDuration.TotalSeconds()) or 0 -- MyDuration() ALWAYS has TotalSeconds() we don't need to check for nil
    end
    if sec < 1 or not spellid or not duration then return false end
    if not DebuffList[spawnID] then DebuffList[spawnID] = {} end
    DebuffList[spawnID][spellid] = duration
    return true
end

function spellstates.GetDebuffExpire(spawnID, spellid)
    if not DebuffList[spawnID] then return nil end
    return DebuffList[spawnID][spellid]
end

function spellstates.HasDebuffLongerThan(spawnID, spellid, minRemainingMs)
    local expire = spellstates.GetDebuffExpire(spawnID, spellid)
    if not expire then return false end
    return expire > (mq.gettime() + minRemainingMs)
end

function spellstates.SetDebuffDelay(debuffIndex, expireTime)
    DebuffDlyLst[debuffIndex] = expireTime
end

function spellstates.GetDebuffDelay(debuffIndex)
    return DebuffDlyLst[debuffIndex]
end

function spellstates.GetRecastCounter(spawnID, debuffIndex)
    if not recastcntr[spawnID] or not recastcntr[spawnID][debuffIndex] then return 0 end
    return recastcntr[spawnID][debuffIndex].counter or 0
end

function spellstates.IncrementRecastCounter(spawnID, debuffIndex)
    if not recastcntr[spawnID] then recastcntr[spawnID] = {} end
    if not recastcntr[spawnID][debuffIndex] then recastcntr[spawnID][debuffIndex] = { counter = 0 } end
    recastcntr[spawnID][debuffIndex].counter = recastcntr[spawnID][debuffIndex].counter + 1
    return recastcntr[spawnID][debuffIndex].counter
end

function spellstates.ResetRecastCounter(spawnID, debuffIndex)
    if recastcntr[spawnID] and recastcntr[spawnID][debuffIndex] and recastcntr[spawnID][debuffIndex].counter then
        recastcntr[spawnID][debuffIndex].counter = 0
    end
end

function spellstates.GetConcussionCounter(spawnID)
    if not concussionCounter[spawnID] then return 0 end
    return concussionCounter[spawnID] or 0
end

function spellstates.IncrementConcussionCounter(spawnID)
    if not concussionCounter[spawnID] then concussionCounter[spawnID] = 0 end
    concussionCounter[spawnID] = concussionCounter[spawnID] + 1
    return concussionCounter[spawnID]
end

function spellstates.ResetConcussionCounter(spawnID)
    if concussionCounter[spawnID] then concussionCounter[spawnID] = nil end
end

--- Remove per-spawn debuff state for any spawn ID not in the current MobList (avoids spawn ID reuse bugs when mobs respawn).
function spellstates.PruneDebuffStateNotInMobList(mobList)
    local currentIds = {}
    if mobList and #mobList > 0 then
        for _, v in ipairs(mobList) do
            local id = v.ID and v.ID() or v
            if id then currentIds[id] = true end
        end
    end
    for spawnID, _ in pairs(DebuffList) do
        if not currentIds[spawnID] then DebuffList[spawnID] = nil end
    end
    for spawnID, _ in pairs(recastcntr) do
        if not currentIds[spawnID] then recastcntr[spawnID] = nil end
    end
    for spawnID, _ in pairs(concussionCounter) do
        if not currentIds[spawnID] then concussionCounter[spawnID] = nil end
    end
end

function spellstates.ClearDebuffList()
    DebuffList = {}
    recastcntr = {}
    concussionCounter = {}
end

-- Cleans ADMobList (zone reset / debuff list clear); alias for ClearDebuffList.
function spellstates.CleanMobList()
    spellstates.ClearDebuffList()
end

function spellstates.ClearDebuffOnSpawn(spawnID, spellid)
    if DebuffList[spawnID] and DebuffList[spawnID][spellid] then
        DebuffList[spawnID][spellid] = nil
    end
end

return spellstates
