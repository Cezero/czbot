-- Lightweight spell-entry TLO helpers (TargetType, etc.).
-- Safe for castutils and other mid-layer modules: mq only — no spellutils/castutils cycle.

local mq = require('mq')

local spellentry = {}

local function targetTypeFromSpellRef(ref)
    if not ref or not ref.TargetType then return nil end
    local ok, tt = pcall(function() return ref.TargetType() end)
    if not ok or type(tt) ~= 'string' then return nil end
    tt = tt:match('^%s*(.-)%s*$')
    if tt == '' or tt == 'Unknown' then return nil end
    return tt
end

--- MQ TargetType() for a config spell entry (gem spell, item clicky, AA, disc, gem slot).
---@param entry table|nil
---@return string|nil
function spellentry.GetSpellTargetType(entry)
    if not entry then return nil end

    local gem = entry.gem
    local spell = entry.spell

    if gem == 'item' and spell and spell ~= '' then
        if mq.TLO.FindItem(spell)() then
            local tt = targetTypeFromSpellRef(mq.TLO.FindItem(spell).Spell)
            if tt then return tt end
        end
    elseif gem == 'alt' and spell and spell ~= '' then
        local aa = mq.TLO.Me.AltAbility(spell)
        if aa and aa() then
            local tt = targetTypeFromSpellRef(aa.Spell)
            if tt then return tt end
        end
    elseif gem == 'disc' and spell and spell ~= '' then
        local tt = targetTypeFromSpellRef(mq.TLO.Spell(spell))
        if tt then return tt end
    end

    if spell and spell ~= '' then
        local tt = targetTypeFromSpellRef(mq.TLO.Spell(spell))
        if tt then return tt end
        local n = tonumber(spell)
        if n and n > 0 then
            tt = targetTypeFromSpellRef(mq.TLO.Spell(n))
            if tt then return tt end
        end
    end

    local gemNum = type(gem) == 'number' and gem or tonumber(gem)
    if gemNum and gemNum >= 1 and gemNum <= 12 then
        local tt = targetTypeFromSpellRef(mq.TLO.Me.Gem(gemNum))
        if tt then return tt end
    end

    return nil
end

return spellentry
