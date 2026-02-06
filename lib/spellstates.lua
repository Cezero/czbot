local mq = require('mq')
local spellstates = {}

-- Module-local state: spawn/target -> spell duration tracking and debuff delay/recast counters
local DebuffList = {}
local recastcntr = {}
local DebuffDlyLst = {}

function spellstates.EnsureDebuffState()
    DebuffList = DebuffList or {}
    recastcntr = recastcntr or {}
    DebuffDlyLst = DebuffDlyLst or {}
end

function spellstates.DebuffListUpdate(spawnID, spell, duration)
    local spellid = mq.TLO.Spell(spell).ID() or mq.TLO.FindItem(spell).Spell.ID()
    local spelldur = tonumber(mq.TLO.Spell(spellid).MyDuration()) or 0
    if debug then print('debuff list update evalid:', spawnID, ' spellid:', spellid, ' duration:', duration) end
    if spelldur < 1 or not spellid or not duration then return false end
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

function spellstates.ClearDebuffList()
    DebuffList = {}
end

-- Cleans ADMobList (zone reset / debuff list clear); alias for ClearDebuffList for callers that used trotslib.CleanMobList.
function spellstates.CleanMobList()
    spellstates.ClearDebuffList()
end

function spellstates.ClearDebuffOnSpawn(spawnID, spellid)
    if DebuffList[spawnID] and DebuffList[spawnID][spellid] then
        DebuffList[spawnID][spellid] = nil
    end
end

return spellstates
