local mq = require('mq')
local botconfig = require('lib.config')
local spellbands = require('lib.spellbands')
local spellutils = require('lib.spellutils')
local state = require('lib.state')
local charinfo = require('mqcharinfo')
local bothooks = require('lib.bothooks')
local castutils = require('lib.castutils')

local botbuff = {}
local BuffClass = {}

local function defaultBuffEntry()
    return botconfig.getDefaultSpellEntry('buff')
end

function botbuff.LoadBuffConfig()
    castutils.LoadSpellSectionConfig('buff', {
        defaultEntry = defaultBuffEntry,
        bandsKey = 'buff',
        storeIn = BuffClass,
    })
end

castutils.RegisterSectionLoader('buff', 'dobuff', botbuff.LoadBuffConfig)

local function IconCheck(index, EvalID)
    local entry = botconfig.getSpellEntry('buff', index)
    if not entry then return true end
    local spellicon = entry.spellicon
    if not spellicon or spellicon == 0 then return true end
    local botname = mq.TLO.Spawn(EvalID).Name()
    local info = charinfo.GetInfo(botname)
    local hasIcon = info and spellutils.PeerHasBuff(info, spellicon)
    return not hasIcon
end

local function BuffEvalBotNeedsBuff(botid, botname, spellid, range, index, targethit)
    local spawnid = mq.TLO.Spawn(botid).ID()
    local peer = charinfo.GetInfo(botname)
    if not peer then return nil, nil end
    local botbuff = spellutils.PeerHasBuff(peer, spellid)
    local botbuffstack = peer:Stacks(spellid)
    local botfreebuffslots = peer.FreeBuffSlots
    local botdist = spawnid and mq.TLO.Spawn(spawnid).Distance()
    if not (spawnid and botbuffstack and botfreebuffslots and botfreebuffslots > 0) then return nil, nil end
    if not IconCheck(index, spawnid) or botbuff then return nil, nil end
    if range and botdist and botdist <= range then return botid, targethit end
    return nil, nil
end

local function BuffEvalSelf(index, entry, spell, spellid, range, myid, myclass, tanktar)
    if not BuffClass[index] then return nil, nil end
    if myclass ~= 'BRD' then
        local mypetid = mq.TLO.Me.Pet.ID()
        if BuffClass[index].petspell and IconCheck(index, myid) and mypetid == 0 then
            return myid, 'petspell'
        end
        if BuffClass[index].self then
            local buffdur = mq.TLO.Me.Buff(spell).Duration()
            local mycasttime = mq.TLO.Spell(spell).MyCastTime()
            local buff = mq.TLO.Me.Buff(spell)() or mq.TLO.Me.Song(spell)()
            local stacks = mq.TLO.Spell(spell).Stacks()
            local tartype = mq.TLO.Spell(spell).TargetType()
            local freebuffslots = mq.TLO.Me.FreeBuffSlots()
            if (not buff) or (buffdur and buffdur < 24000 and mycasttime > 0 and freebuffslots > 0) then
                if IconCheck(index, myid) then
                    if tartype == 'Self' and stacks then return 1, 'self' end
                    if stacks then return myid, 'self' end
                end
            end
        end
        return nil, nil
    end
    if myclass == 'BRD' and BuffClass[index].self and IconCheck(index, myid) then
        local mysong = mq.TLO.Me.Song(spell)() or mq.TLO.Me.Buff(spell)()
        local mysongdur = mq.TLO.Me.Song(spell).Duration() or mq.TLO.Me.Buff(spell).Duration()
        local songtartype = mq.TLO.Spell(spell).TargetType()
        local songtype = mq.TLO.Spell(spell).SpellType()
        if (not mysong) or (mysongdur and mysongdur < 6100) then
            if songtartype and (songtartype == 'Group v1' or songtartype == 'Group v2' or songtartype == 'Self' or songtartype == 'AE PC v2') then
                return 1, 'self'
            elseif songtype and songtype == 'Detrimental' then
                local mysongdur2 = mq.TLO.Target.MyBuff(spell).Duration()
                local mysong2 = mq.TLO.Target.MyBuff(spell)()
                if tanktar and tanktar > 0 and ((not mysong2) or (mysongdur2 and mysongdur2 < 6100)) then
                    return tanktar, 'self'
                end
            else
                return myid, 'self'
            end
        end
    end
    return nil, nil
end

local function BuffEvalTank(index, entry, spell, spellid, range, tank, tankid)
    if not tank or not entry or not BuffClass[index].tank or not tankid or tankid <= 0 then return nil, nil end
    if not IconCheck(index, tankid) then return nil, nil end
    local peer = charinfo.GetInfo(tank)
    if peer then
        return BuffEvalBotNeedsBuff(tankid, tank, spellid, range, index, 'tank')
    end
    local tankdist = mq.TLO.Spawn(tankid).Distance()
    if not range or not tankdist or tankdist > range then return nil, nil end
    if not spellutils.EnsureSpawnBuffsPopulated(tankid, 'buff', index, 'tank', nil, 'after_tank', nil) then
        return nil, nil
    end
    if spellutils.SpawnNeedsBuff(tankid, spell, entry.spellicon) then return tankid, 'tank' end
    if not mq.TLO.Group.Member(tank).Index() then return tankid, 'tank' end
    return nil, nil
end

local function BuffEvalGroupBuff(index, entry, spell, spellid, range)
    local aeRange = mq.TLO.Spell(spell).AERange()
    if entry.gem == 'item' and mq.TLO.FindItem(entry.spell)() then aeRange = mq.TLO.FindItem(entry.spell).Spell.AERange() end
    if not aeRange or aeRange <= 0 then return nil, nil end
    local function needBuff(grpmember, grpid, grpname, peer)
        if peer then
            local hasBuff = spellutils.PeerHasBuff(peer, spellid)
            local stacks = peer:Stacks(spellid)
            local free = peer.FreeBuffSlots
            return not hasBuff and stacks and free and free > 0
        end
        return spellutils.SpawnNeedsBuff(grpid, spell, entry.spellicon)
    end
    return castutils.evalGroupAECount(entry, 'groupbuff', index, BuffClass, 'groupbuff', needBuff, { aeRange = aeRange })
end

local function BuffEvalMyPet(index, entry, spell, spellid, range)
    if not BuffClass[index].mypet then return nil, nil end
    local mypetid = mq.TLO.Me.Pet.ID()
    local petbuff = mq.TLO.Me.Pet.Buff(spell)()
    local petrange = mq.TLO.Me.Pet.Distance()
    local myPeer = charinfo.GetInfo(mq.TLO.Me.Name())
    local petstacks = myPeer and myPeer:StacksPet(spellid)
    if mypetid > 0 and petstacks and not petbuff and petrange and range and range >= petrange then
        return mypetid, 'mypet'
    end
    return nil, nil
end

local function BuffEvalPets(index, entry, spellid, range, bots, botcount)
    if not BuffClass[index].pet then return nil, nil end
    for i = 1, botcount do
        if bots[i] then
            local peer = charinfo.GetInfo(bots[i])
            if peer then
                local botpet = mq.TLO.Spawn('pc =' .. bots[i]).Pet.ID()
                local petrange = mq.TLO.Spawn(botpet).Distance()
                local petbuff = spellutils.PeerHasPetBuff(peer, spellid)
                local botid = mq.TLO.Spawn('pc =' .. bots[i]).ID()
                local spawnid = mq.TLO.Spawn(botid).ID()
                local petstacks = peer:StacksPet(spellid)
                if spawnid and spawnid > 0 and botpet and botpet > 0 and petstacks and IconCheck(index, spawnid) and not petbuff and range and range >= petrange then
                    return botpet, 'pet'
                end
            end
        end
    end
    return nil, nil
end

local BUFF_PHASE_ORDER = { 'self', 'byname', 'tank', 'groupbuff', 'groupmember', 'pc', 'mypet', 'pet' }

local function buffGetTargetsForPhase(phase, context)
    if phase == 'self' then return castutils.getTargetsSelf() end
    if phase == 'tank' then return castutils.getTargetsTank(context) end
    if phase == 'groupbuff' then return castutils.getTargetsGroupCaster('groupbuff') end
    if phase == 'groupmember' then return castutils.getTargetsGroupMember(context, {}) end
    if phase == 'pc' then return castutils.getTargetsPc(context) end
    if phase == 'mypet' then return castutils.getTargetsMypet() end
    if phase == 'pet' then return castutils.getTargetsPet(context) end
    if phase == 'byname' and context.buffCount then
        local out = {}
        local seen = {}
        for idx = 1, context.buffCount do
            if BuffClass[idx] and BuffClass[idx].name then
                for name, c in pairs(BuffClass[idx]) do
                    if name ~= 'name' and name ~= 'classes' and name ~= 'classesAll' and type(name) == 'string' and charinfo.GetInfo(name) and not seen[name] then
                        seen[name] = true
                        local botid = mq.TLO.Spawn('pc =' .. name).ID()
                        local botclass = mq.TLO.Spawn('pc =' .. name).Class.ShortName()
                        if botid and botid > 0 then out[#out + 1] = { id = botid, targethit = 'byname' } end
                    end
                end
            end
        end
        return out
    end
    return {}
end

local function buffBandHasPhase(spellIndex, phase)
    if phase == 'byname' then return BuffClass[spellIndex] and BuffClass[spellIndex].name and true or false end
    return castutils.bandHasPhaseSimple(BuffClass, spellIndex, phase)
end

local function buffTargetNeedsSpell(spellIndex, targetId, targethit, context)
    local entry = botconfig.getSpellEntry('buff', spellIndex)
    if not entry or not BuffClass[spellIndex] then return nil, nil end
    local spell, _, _, spellid = spellutils.GetSpellInfo(entry)
    if not spell or not spellid then return nil, nil end
    local sid = (spellid == 1536) and 1538 or spellid
    local gem = entry.gem
    local range = (mq.TLO.Spell(spell).MyRange() and mq.TLO.Spell(spell).MyRange() > 0) and mq.TLO.Spell(spell).MyRange()
        or mq.TLO.Spell(spell).AERange() or
        (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.MyRange())
    local tank, tankid, tanktar = spellutils.GetTankInfo(false)
    tanktar = tanktar or
    (tank and charinfo.GetInfo(tank) and charinfo.GetInfo(tank).Target and charinfo.GetInfo(tank).Target.ID or nil)
    local myid = mq.TLO.Me.ID()
    local myclass = mq.TLO.Me.Class.ShortName()

    if targethit == 'self' then
        return BuffEvalSelf(spellIndex, entry, spell, sid, range, myid, myclass, tanktar)
    end
    if targethit == 'tank' then
        local id, hit = BuffEvalTank(spellIndex, entry, spell, sid, range, context.tank, context.tankid)
        if id == targetId then return id, hit end
        return nil, nil
    end
    if targethit == 'groupbuff' then
        return BuffEvalGroupBuff(spellIndex, entry, spell, sid, range)
    end
    if targethit == 'mypet' then
        local id, hit = BuffEvalMyPet(spellIndex, entry, spell, sid, range)
        if id == targetId then return id, hit end
        return nil, nil
    end
    if targethit == 'pet' then
        local id, hit = BuffEvalPets(spellIndex, entry, sid, range, context.bots,
            context.botcount or #(context.bots or {}))
        if id == targetId then return id, hit end
        return nil, nil
    end
    if targethit == 'byname' then
        if not BuffClass[spellIndex].name then return nil, nil end
        local name = mq.TLO.Spawn(targetId).CleanName()
        if name then
            local id, hit = BuffEvalBotNeedsBuff(targetId, name, sid, range, spellIndex, 'byname')
            if id then return id, hit end
        end
        return nil, nil
    end
    if BuffClass[spellIndex].groupmember or BuffClass[spellIndex].pc then
        local grpname = mq.TLO.Spawn(targetId).CleanName()
        local lc = targethit
        if (BuffClass[spellIndex].classes == 'all' or (BuffClass[spellIndex].classes and BuffClass[spellIndex].classes[lc])) and IconCheck(spellIndex, targetId) then
            local peer = charinfo.GetInfo(grpname)
            if peer then
                local id, hit = BuffEvalBotNeedsBuff(targetId, grpname, sid, range, spellIndex, lc)
                if id then return id, hit end
            else
                if spellutils.EnsureSpawnBuffsPopulated(targetId, 'buff', spellIndex, lc, nil, nil, nil) and spellutils.SpawnNeedsBuff(targetId, spell, entry.spellicon) then
                    return targetId, lc
                end
            end
        end
    end
    return nil, nil
end

function botbuff.BuffCheck(runPriority)
    local myconfig = botconfig.config
    local mobList = state.getRunconfig().MobList
    local hasMob = mobList and mobList[1]
    local count = botconfig.getSpellCount('buff')
    if count <= 0 then return false end
    local tank, tankid = spellutils.GetTankInfo(false)
    local bots = spellutils.GetBotListShuffled()
    local ctx = { tank = tank, tankid = tankid, bots = bots, botcount = #bots, buffCount = count }
    local options = {
        skipInterruptForBRD = true,
        runPriority = runPriority,
        entryValid = function(i)
            local entry = botconfig.getSpellEntry('buff', i)
            if not entry then return false end
            local gem = entry.gem
            if entry.enabled == false then return false end
            if not ((type(gem) == 'number' and gem ~= 0) or type(gem) == 'string') then return false end
            local cbtspell = BuffClass[i] and BuffClass[i].cbt
            local idlespell = BuffClass[i] and BuffClass[i].idle
            return (not hasMob and (not cbtspell or idlespell)) or (hasMob and cbtspell)
        end,
    }
    local function getSpellIndices(phase)
        return spellutils.getSpellIndicesForPhase(count, phase, buffBandHasPhase)
    end
    return spellutils.RunPhaseFirstSpellCheck('buff', 'doBuff', BUFF_PHASE_ORDER, buffGetTargetsForPhase, getSpellIndices,
        buffTargetNeedsSpell, ctx, options)
end

function botbuff.getHookFn(name)
    if name == 'doBuff' then
        return function(hookName)
            local myconfig = botconfig.config
            if not myconfig.settings.dobuff or not (myconfig.buff.spells and #myconfig.buff.spells > 0) then return end
            if state.getRunState() == 'idle' then state.getRunconfig().statusMessage = 'Buff Check' end
            botbuff.BuffCheck(bothooks.getPriority(hookName))
        end
    end
    return nil
end

return botbuff
