local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')
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

function M.save()
    botconfig.saveCommon()
end

function M.add(spell, zone, mobName)
    local zb = botconfig.ensureZoneBlock(zone)
    if not zb.immune then zb.immune = {} end
    if not zb.immune[spell] then zb.immune[spell] = {} end
    zb.immune[spell][mobName] = true
    M.save()
end

function M.processList(immuneID)
    local entry = botconfig.getSpellEntry(state.getRunconfig().CurSpell.sub, state.getRunconfig().CurSpell.spell)
    local spell = entry and mq.TLO.Spell(entry.spell)() or nil
    local zone = mq.TLO.Zone.ShortName()
    if immuneID and spell and mq.TLO.Spawn(immuneID).ID() and mq.TLO.Spawn(immuneID).Type() ~= 'Corpse' then
        local mobName = mq.TLO.Spawn(immuneID).CleanName()
        local t = M.get()
        if not t[spell] or not t[spell][mobName] then
            M.add(spell, zone, mobName)
            printf('\ayCZBot:\ax%s is \\arIMMUNE\\ax to spell \\ag%s\\ax, adding to the ImmuneList', mobName, spell)
        end
    end
end

return M
