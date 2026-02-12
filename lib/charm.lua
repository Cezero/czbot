-- Charm logic: target selection, before-cast (pet leave), and charm-broke recast request.
-- Used by botdebuff (debuff eval/beforeCast) and botevents (CharmBroke handler).

local mq = require('mq')
local state = require('lib.state')
local spellstates = require('lib.spellstates')
local spellutils = require('lib.spellutils')
local utils = require('lib.utils')

local charm = {}

-- Module state for charm-broke handler (set when EvalTarget picks a charm target).
local _charmspellid = nil
local _charmindex = nil
-- Recast request set when charm breaks; consumed by debuff loop for that index.
local _recastRequest = nil

function charm.EvalTarget(index, ctx)
    local entry = ctx.entry
    if not spellutils.IsCharmSpell(entry) then return nil, nil end
    local list = state.getRunconfig().CharmList or {}
    if #list == 0 then return nil, nil end
    local gem = entry.gem
    _charmspellid = mq.TLO.Spell(entry.spell).ID() or
        (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.ID())
    _charmindex = index
    local rc = state.getRunconfig()
    if not mq.TLO.Me.Pet.ID() and not mq.TLO.Me.Pet.IsSummoned() and rc.charmid then rc.charmid = nil end
    if mq.TLO.Me.Pet.ID() and mq.TLO.Me.Pet.ID() > 0 and not mq.TLO.Me.Pet.IsSummoned() and not rc.charmid then
        rc.charmid = mq.TLO.Me.Pet.ID()
    end
    if mq.TLO.Me.Pet.ID() and mq.TLO.Me.Pet.ID() > 0 and rc.charmid and mq.TLO.Me.Pet.ID() == rc.charmid then
        return nil, nil
    end
    for _, v in ipairs(ctx.mobList) do
        local tarstacks = mq.TLO.Spell(entry.spell).StacksSpawn(v.ID())() or
            (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.StacksSpawn(v.ID()))
        local overLevel = ctx.spellid and v.Level() and ctx.spellmaxlvl and ctx.spellmaxlvl ~= 0 and ctx.spellmaxlvl < v.Level()
        local distSq = utils.getDistanceSquared2D(mq.TLO.Me.X(), mq.TLO.Me.Y(), v.X(), v.Y())
        local outOfRange = ctx.myrange and distSq and distSq > (ctx.myrange * ctx.myrange)
        if not overLevel and not outOfRange and tarstacks and tonumber(ctx.spelldur) > 0 then
            local mobhp = v.PctHPs()
            if ctx.mobMin ~= nil and (mobhp == nil or mobhp < ctx.mobMin) then
                -- skip: mob below band
            elseif ctx.mobMax ~= nil and (mobhp == nil or mobhp > ctx.mobMax) then
                -- skip: mob above band
            elseif v.ID() then
                local expire = spellstates.GetDebuffExpire(v.ID(), ctx.spellid)
                local cleanName = v.CleanName()
                local mobnameLower = cleanName and string.lower(cleanName)
                if expire and expire < (mq.gettime() + 6000) then
                    for _, charmname in ipairs(list) do
                        local n = type(charmname) == 'string' and charmname:match('^%s*(.-)%s*$') or ''
                        if n ~= '' and (cleanName == n or (mobnameLower and string.lower(n) == mobnameLower)) then return v.ID(), 'charmtar' end
                    end
                elseif expire and expire >= (mq.gettime() + 6000) then
                    for _, charmname in ipairs(list) do
                        local n = type(charmname) == 'string' and charmname:match('^%s*(.-)%s*$') or ''
                        if n ~= '' and (cleanName == n or (mobnameLower and string.lower(n) == mobnameLower)) then return v.ID(), 'charmtar' end
                    end
                else
                    for _, charmname in ipairs(list) do
                        local n = type(charmname) == 'string' and charmname:match('^%s*(.-)%s*$') or ''
                        if n ~= '' and (cleanName == n or (mobnameLower and string.lower(n) == mobnameLower)) then return v.ID(), 'charmtar' end
                    end
                end
            else
                local cleanName = v.CleanName()
                local mobnameLower = cleanName and string.lower(cleanName)
                for _, charmname in ipairs(list) do
                    local n = type(charmname) == 'string' and charmname:match('^%s*(.-)%s*$') or ''
                    if n ~= '' and (cleanName == n or (mobnameLower and string.lower(n) == mobnameLower)) then return v.ID(), 'charmtar' end
                end
            end
        end
    end
    return nil, nil
end

function charm.BeforeCast(EvalID, targethit)
    if targethit == 'charmtar' and mq.TLO.Me.Pet.IsSummoned() then
        mq.cmd('/pet leave')
    end
    return true
end

function charm.OnCharmBroke(line, spellNameFromEvent)
    local rc = state.getRunconfig()
    if not _charmspellid or not rc.charmid then return end
    local charmspellname = mq.TLO.Spell(_charmspellid).Name()
    if spellNameFromEvent ~= charmspellname then return end
    spellstates.ClearDebuffOnSpawn(rc.charmid, _charmspellid)
    printf('\ayCZBot:\ax\arCHARM %s wore off!', spellNameFromEvent)
    _recastRequest = { index = _charmindex, spawnId = rc.charmid }
end

function charm.GetRecastRequestForIndex(index)
    if not _recastRequest or _recastRequest.index ~= index then return nil, nil end
    return _recastRequest.spawnId, 'charmtar'
end

function charm.ClearRecastRequest()
    _recastRequest = nil
end

return charm
