-- Allowed buff targetphase tokens for Group AE spells (v1/v2). Shared by runtime loader and GUI.

local spellutils = require('lib.spellutils')

local buffphase = {}

buffphase.GROUPV2_ALLOWED = { groupbuff = true, pc = true }
buffphase.GROUPV1_ALLOWED = {
    self = true, tank = true, groupbuff = true, groupmember = true, mypet = true, pet = true,
}

local RUNTIME_PHASE_KEYS = {
    'self', 'tank', 'groupbuff', 'groupmember', 'pc', 'mypet', 'pet', 'name', 'petspell',
}

function buffphase.getAllowedPhases(entry)
    if not entry then return nil end
    if spellutils.IsGroupV2BuffEntry(entry) then
        return buffphase.GROUPV2_ALLOWED
    end
    if spellutils.IsGroupV1BuffEntry(entry) then
        return buffphase.GROUPV1_ALLOWED
    end
    return nil
end

--- Strip disallowed targetphase tokens from config entry.bands (GUI save/display).
function buffphase.sanitizeEntryTargetPhases(entry)
    local allowed = buffphase.getAllowedPhases(entry)
    if not allowed or not entry.bands or type(entry.bands) ~= 'table' then return end
    for _, band in ipairs(entry.bands) do
        if band and type(band.targetphase) == 'table' then
            local out = {}
            local changed = false
            for _, p in ipairs(band.targetphase) do
                if allowed[p] then
                    out[#out + 1] = p
                else
                    changed = true
                end
            end
            if changed then band.targetphase = out end
        end
    end
end

--- Clear disallowed phase flags from spellbands runtime table (BuffClass[i]).
function buffphase.sanitizeRuntimePhases(entry, rt)
    local allowed = buffphase.getAllowedPhases(entry)
    if not allowed or not rt then return end
    for _, key in ipairs(RUNTIME_PHASE_KEYS) do
        if rt[key] and not allowed[key] then
            rt[key] = nil
        end
    end
end

return buffphase
