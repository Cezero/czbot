-- Activate the configured inventory bandolier for Main Tank role, or for a self buff
-- that still needs to proc. melee.bandolierTank / melee.bandolierDps / melee.bandolierBuff:
-- blank means no switch for that role. bandolierBuff also requires bandolierBuffSpell.

local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')
local tankrole = require('lib.tankrole')
local spellutils = require('lib.spellutils')
local log = require('lib.log')

local M = {}

local _lastAppliedName = nil
local _missingSpellLogged = nil

local function trimName(s)
    if type(s) ~= 'string' then return '' end
    return (s:match('^%s*(.-)%s*$')) or ''
end

--- Buff set while self still needs bandolierBuffSpell and it will stack; otherwise the MT role set.
--- @return string kind, string name
local function desiredBandolier(melee, isMt)
    local buffBand = trimName(melee.bandolierBuff)
    local buffSpell = trimName(melee.bandolierBuffSpell)
    if buffBand ~= '' and buffSpell ~= '' then
        local entry = { spell = buffSpell }
        if spellutils.SelfNeedsBuffEntry(entry) then
            if not mq.TLO.Spell(buffSpell)() then
                if _missingSpellLogged ~= buffSpell then
                    _missingSpellLogged = buffSpell
                    log.say('Bandolier: buff spell "%s" was not found', buffSpell)
                end
            else
                if _missingSpellLogged == buffSpell then _missingSpellLogged = nil end
                local myId = mq.TLO.Me.ID()
                if myId and spellutils.SpellStacksSpawn(entry, myId) then
                    return 'buff', buffBand
                end
            end
        end
    end
    local roleName = trimName(isMt and melee.bandolierTank or melee.bandolierDps)
    return isMt and 'tank' or 'dps', roleName
end

--- Apply the configured bandolier for buff need or the current MT role. Safe to call every tick.
function M.tick()
    if state.isDeadOrHover() then return end
    local melee = botconfig.config.melee
    if not melee then return end

    local isMt = tankrole.AmIMainTank()
    local kind, name = desiredBandolier(melee, isMt)
    if name == '' then return end
    if name == _lastAppliedName then return end

    mq.cmdf('/bandolier activate "%s"', name)
    _lastAppliedName = name
    log.say('Bandolier: %s "%s"', kind, name)
end

return M
