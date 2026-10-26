-- PctAggro helpers (Me.PctAggro is meaningful at level 20+).

local mq = require('mq')
local spellbands = require('lib.spellbands')

local aggro = {}

local PCT_AGGRO_MIN_LEVEL = 20

function aggro.pctAggroAvailable()
    return (tonumber(mq.TLO.Me.Level()) or 0) >= PCT_AGGRO_MIN_LEVEL
end

function aggro.getPctAggro()
    if not aggro.pctAggroAvailable() then return nil end
    local pct = mq.TLO.Me.PctAggro()
    if pct == nil then return nil end
    return tonumber(pct)
end

--- Aggro percent on one spawn. Current target uses Me.PctAggro. Otherwise the matching
--- XTarget slot. Nil when level < 20 or no reading exists; that is not "in band".
function aggro.getPctAggroOn(spawnId)
    if not aggro.pctAggroAvailable() then return nil end
    spawnId = tonumber(spawnId)
    if not spawnId or spawnId <= 0 then return nil end
    local targetId = tonumber(mq.TLO.Target.ID())
    if targetId and targetId == spawnId then
        return aggro.getPctAggro()
    end
    local n = tonumber(mq.TLO.Me.XTarget()) or 0
    for i = 1, n do
        local xt = mq.TLO.Me.XTarget(i)
        if xt and xt.ID() == spawnId then
            local ok, pct = pcall(function() return xt.PctAggro() end)
            if not ok or pct == nil then return nil end
            return tonumber(pct)
        end
    end
    return nil
end

--- True only when pct is a number inside the inclusive band. A missing reading is false.
function aggro.readingInBand(pct, minVal, maxVal)
    if pct == nil then return false end
    return spellbands.hpInBand(pct, { min = minVal or 0, max = maxVal or 100 })
end

--- Inclusive min/max band on Me.PctAggro. When TLO unavailable, returns true (gate disabled).
function aggro.inBand(minVal, maxVal)
    if not aggro.pctAggroAvailable() then return true end
    local pct = aggro.getPctAggro()
    if pct == nil then return true end
    return spellbands.hpInBand(pct, { min = minVal or 0, max = maxVal or 100 })
end

return aggro
