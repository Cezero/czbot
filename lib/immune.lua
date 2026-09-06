local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')
local log = require('lib.log')
local M = {}

--- Return immune table for current zone only: [spell][mobName] = true.
function M.get()
    botconfig.getCommon()
    local zone = mq.TLO.Zone.ShortName()
    local zb = botconfig.getZoneBlock(zone)
    if not zb or not zb.immune then return {} end
    return zb.immune
end

function M.load()
    botconfig.getCommon()
end

function M.add(spell, zone, mobName)
    if not spell or not zone or zone == '' or not mobName or mobName == '' then return end
    botconfig.mutateCommon(function(common)
        if not common.zones then common.zones = {} end
        if not common.zones[zone] then common.zones[zone] = {} end
        local zb = common.zones[zone]
        if not zb.immune then zb.immune = {} end
        if not zb.immune[spell] then zb.immune[spell] = {} end
        zb.immune[spell][mobName] = true
    end)
end

local function resolvedSpellForList(opts)
    if opts and opts.spellName and opts.spellName ~= '' then
        return mq.TLO.Spell(opts.spellName)() or opts.spellName
    end
    local spellutils = require('lib.spellutils')
    local rc = state.getRunconfig()
    local cur = rc and rc.CurSpell
    if cur and cur.sub and cur.spell then
        local entry = botconfig.getSpellEntry(cur.sub, cur.spell)
        if entry then
            return spellutils.GetResolvedSpellName(entry) or entry.spell
        end
    end
    local snap = spellutils.getLastCastSnapshot and spellutils.getLastCastSnapshot()
    if snap and snap.spellName and snap.spellName ~= '' then
        return mq.TLO.Spell(snap.spellName)() or snap.spellName
    end
    return nil
end

---@param immuneID number|nil spawn ID of immune target
---@param opts table|nil optional { spellName = string, reason = string } canonical spell name for immune list; else CurSpell/last-cast
function M.processList(immuneID, opts)
    local spell = resolvedSpellForList(opts)
    local zone = mq.TLO.Zone.ShortName()
    if immuneID and spell and mq.TLO.Spawn(immuneID).ID() and mq.TLO.Spawn(immuneID).Type() ~= 'Corpse' then
        local mobName = mq.TLO.Spawn(immuneID).CleanName()
        local t = M.get()
        if not t[spell] or not t[spell][mobName] then
            M.add(spell, zone, mobName)
            if opts and opts.reason == 'resists' then
                log.say('%s resisted \\ag%s\\ax 3 times in a row, adding to the ImmuneList', mobName, spell)
            else
                log.say('%s is \\arIMMUNE\\ax to spell \\ag%s\\ax, adding to the ImmuneList', mobName, spell)
            end
        end
    end
end

return M
