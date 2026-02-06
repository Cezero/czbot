local mq = require('mq')
local botconfig = require('lib.config')
local state = require('lib.state')
local M = {}
M._immune = nil

function M.get()
    if M._immune == nil then M.load() end
    return M._immune
end

function M.load()
    local immuneData, errr = loadfile(mq.configDir .. '/' .. 'czimmune.lua')
    if errr then
        M._immune = {}
        mq.pickle('czimmune.lua', M._immune)
    elseif immuneData then
        M._immune = immuneData()
        if not M._immune then M._immune = {} end
    else
        M._immune = {}
    end
    return M._immune
end

function M.save()
    if M._immune then mq.pickle('czimmune.lua', M._immune) end
end

function M.add(spell, zone, mobName)
    local t = M.get()
    if not t[spell] then t[spell] = {} end
    if not t[spell][zone] then t[spell][zone] = {} end
    t[spell][zone][mobName] = true
    M.save()
end

function M.processList(immuneID)
    local entry = botconfig.getSpellEntry(state.getRunconfig().CurSpell.sub, state.getRunconfig().CurSpell.spell)
    local spell = entry and mq.TLO.Spell(entry.spell)() or nil
    local zone = mq.TLO.Zone.ShortName()
    if immuneID and spell and mq.TLO.Spawn(immuneID).ID() and mq.TLO.Spawn(immuneID).Type() ~= 'Corpse' then
        local mobName = mq.TLO.Spawn(immuneID).CleanName()
        local t = M.get()
        if not t[spell] or not t[spell][zone] or not t[spell][zone][mobName] then
            M.add(spell, zone, mobName)
            printf('\ayCZBot:\ax%s is \\arIMMUNE\\ax to spell \\ag%s\\ax, adding to the ImmuneList', mobName, spell)
        end
    end
end

return M
