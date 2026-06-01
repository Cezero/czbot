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

--- Inclusive min/max band on Me.PctAggro. When TLO unavailable, returns true (gate disabled).
function aggro.inBand(minVal, maxVal)
    if not aggro.pctAggroAvailable() then return true end
    local pct = aggro.getPctAggro()
    if pct == nil then return true end
    return spellbands.hpInBand(pct, { min = minVal or 0, max = maxVal or 100 })
end

return aggro
