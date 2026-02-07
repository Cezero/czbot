-- Single parse/apply for spell bands across heal, buff, cure, event, debuff.
-- entry.bands = { { targetphase = { 'tank', 'pc' }, validtargets = { 'war', 'clr' }, min = 0, max = 80 }, ... }
-- targetphase = priority stages; validtargets = within-phase types (classes, or all/bots/raid for corpse).

local spellbands = {}

local DEBUFF_SPECIAL_MAX = 200
local HEAL_CORPSE_TARGETS = { all = true, bots = true, raid = true }

--- Apply entry.bands to build the runtime structure for this spell index.
--- @param section string 'heal'|'buff'|'cure'|'debuff'
--- @param entry table spell entry with .bands (array of { targetphase = {...}, validtargets? = {...}, min?, max? })
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
        local classesAll = false
        local classesSet = {}
        for _, band in ipairs(bands) do
            local targetPhase = band.targetphase
            if type(targetPhase) == 'table' then
                local minVal = band.min
                local maxVal = band.max
                if minVal == nil then minVal = 0 end
                if maxVal == nil then maxVal = 100 end
                local validTgts = band.validtargets
                for _, p in ipairs(targetPhase) do
                    if type(p) == 'string' and p ~= '' then
                        rt[p] = { min = minVal, max = maxVal }
                        if p == 'cbt' then
                            rt[p].max = DEBUFF_SPECIAL_MAX
                        elseif p == 'corpse' then
                            rt[p].max = DEBUFF_SPECIAL_MAX
                            if type(validTgts) == 'table' and #validTgts > 0 then
                                for _, v in ipairs(validTgts) do
                                    if type(v) == 'string' and HEAL_CORPSE_TARGETS[v] then
                                        rt[v] = { min = minVal, max = DEBUFF_SPECIAL_MAX }
                                    end
                                end
                            else
                                rt.all = { min = minVal, max = DEBUFF_SPECIAL_MAX }
                            end
                        elseif (p == 'pc' or p == 'groupmember') and type(validTgts) == 'table' then
                            for _, c in ipairs(validTgts) do
                                if type(c) == 'string' and c ~= '' then
                                    if c == 'all' then classesAll = true else classesSet[c:lower()] = true end
                                end
                            end
                        elseif (p == 'pc' or p == 'groupmember') and (not validTgts or (type(validTgts) == 'table' and #validTgts == 0)) then
                            classesAll = true
                        end
                    end
                end
            end
        end
        if classesAll then rt.classes = 'all' else rt.classes = classesSet end
        return rt
    end

    if section == 'buff' or section == 'cure' then
        local rt = {}
        local classesAll = false
        local classesSet = {}
        local CLASS_TOKENS = { war=1, shd=1, pal=1, rng=1, mnk=1, rog=1, brd=1, bst=1, ber=1, shm=1, clr=1, dru=1, wiz=1, mag=1, enc=1, nec=1 }
        for _, band in ipairs(bands) do
            local targetPhase = band.targetphase
            if type(targetPhase) == 'table' then
                local validTgts = band.validtargets
                local hasByname = false
                for _, p in ipairs(targetPhase) do
                    if type(p) == 'string' and p ~= '' then
                        rt[p] = true
                        if p == 'byname' then hasByname = true; rt.name = true end
                        if p == 'bots' then rt.pc = true end -- backward compat: bots and pc same for buff/cure
                    end
                end
                if type(validTgts) == 'table' then
                    for _, c in ipairs(validTgts) do
                        if type(c) == 'string' and c ~= '' then
                            local lc = c:lower()
                            if c == 'all' then classesAll = true
                            elseif CLASS_TOKENS[lc] then classesSet[lc] = true; rt[lc] = true
                            elseif hasByname then rt[c] = true
                            end
                        end
                    end
                else
                    classesAll = true
                end
            end
        end
        if classesAll then
            rt.classes = 'all'
            for cls, _ in pairs(CLASS_TOKENS) do rt[cls] = true end
        else
            rt.classes = classesSet
        end
        return rt
    end

    if section == 'debuff' then
        local mobMin, mobMax = 0, 100
        local tanktar, notanktar, named = false, false, false
        for _, band in ipairs(bands) do
            local targetPhase = band.targetphase
            if type(targetPhase) == 'table' then
                local mn = band.min
                local mx = band.max
                if mn ~= nil and (mobMin == nil or mn < mobMin) then mobMin = mn end
                if mx ~= nil and (mobMax == nil or mx > mobMax) then mobMax = mx end
                for _, c in ipairs(targetPhase) do
                    if c == 'tanktar' then tanktar = true
                    elseif c == 'notanktar' then notanktar = true
                    elseif c == 'named' then named = true
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
