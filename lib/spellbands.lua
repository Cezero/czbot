-- Single parse/apply for spell bands across heal, buff, cure, event, debuff.
-- entry.bands = { { validtargets = { 'tank', 'war' }, min = 0, max = 80 }, ... }
-- No legacy class string parsing; config is bands-only.

local spellbands = {}

local DEBUFF_SPECIAL_MAX = 200
local HEAL_SPECIAL_KEYS = { corpse = true, bots = true, raid = true, cbt = true, all = true }

--- Apply entry.bands to build the runtime structure for this spell index.
--- @param section string 'heal'|'buff'|'cure'|'debuff'
--- @param entry table spell entry with .bands (array of { validtargets = {...}, min?, max? })
--- @param index number spell index (for debuff: used by caller to store result)
--- @return table runtime structure for this section/index
function spellbands.applyBands(section, entry, index)
    local bands = entry.bands
    if not bands or type(bands) ~= 'table' then
        if section == 'heal' then return {} end
        if section == 'buff' or section == 'cure' then return {} end
        if section == 'debuff' then return { mobMin = 0, mobMax = 100, tanktar = false, notanktar = false, named = false } end
        return {}
    end

    if section == 'heal' then
        local rt = {}
        for _, band in ipairs(bands) do
            local targetList = band.validtargets
            if type(targetList) == 'table' then
                local minVal = band.min
                local maxVal = band.max
                if minVal == nil then minVal = 0 end
                if maxVal == nil then maxVal = 100 end
                for _, c in ipairs(targetList) do
                    if type(c) == 'string' and c ~= '' then
                        rt[c] = { min = minVal, max = maxVal }
                        if HEAL_SPECIAL_KEYS[c] then
                            rt[c].max = DEBUFF_SPECIAL_MAX
                        end
                    end
                end
            end
        end
        return rt
    end

    if section == 'buff' or section == 'cure' then
        local rt = {}
        for _, band in ipairs(bands) do
            local targetList = band.validtargets
            if type(targetList) == 'table' then
                for _, c in ipairs(targetList) do
                    if type(c) == 'string' and c ~= '' then rt[c] = true end
                end
            end
        end
        return rt
    end

    if section == 'debuff' then
        local mobMin, mobMax = 0, 100
        local tanktar, notanktar, named = false, false, false
        for _, band in ipairs(bands) do
            local targetList = band.validtargets
            if type(targetList) == 'table' then
                local mn = band.min
                local mx = band.max
                if mn ~= nil and (mobMin == nil or mn < mobMin) then mobMin = mn end
                if mx ~= nil and (mobMax == nil or mx > mobMax) then mobMax = mx end
                for _, c in ipairs(targetList) do
                    if c == 'tanktar' then
                        tanktar = true
                    elseif c == 'notanktar' then
                        notanktar = true
                    elseif c == 'named' then
                        named = true
                    end
                end
            end
        end
        if mobMin == nil then mobMin = 0 end
        if mobMax == nil then mobMax = 100 end
        return { mobMin = mobMin, mobMax = mobMax, tanktar = tanktar, notanktar = notanktar, named = named }
    end

    return {}
end

--- Check if HP percentage is within a band (for heal/debuff).
--- @param pct number target or mob PctHPs()
--- @param th table|number { min, max } or legacy single number (max only)
--- @return boolean
function spellbands.hpInBand(pct, th)
    if pct == nil then return false end
    if type(th) == 'table' then
        local minVal = th.min or 0
        local maxVal = th.max or 100
        return pct >= minVal and pct <= maxVal
    end
    return pct <= (th or 100)
end

return spellbands
