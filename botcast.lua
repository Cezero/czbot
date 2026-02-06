local mq = require('mq')
local botconfig = require('lib.config')
local charm = require('lib.charm')
local spellbands = require('lib.spellbands')
local spellutils = require('lib.spellutils')
local spellstates = require('lib.spellstates')
local state = require('lib.state')
local utils = require('lib.utils')
local charinfo = require('actornet.charinfo')
local myconfig = botconfig.config

local botcast = {}

-- Module-level state for buff/cure/heal/debuff (used by evals and spellutils globals)
-- Runconfig fields used by botcast: engageTargetId (set in ADSpawnCheck when clearing invalid spawn, and in DebuffOnBeforeCast for tanktar);
-- charmid (set in charm.EvalTarget and spellutils on cast); MobList, MobCount (set in ADSpawnCheck); CurSpell (read-only here, set in spellutils).
local BuffClass = {}
local CureClass = {}
local CureType = {}
local AHThreshold = {}
local XTList = {}
local HealList = {}
local DebuffBands = {}

-- ---------------------------------------------------------------------------
-- Buff
-- ---------------------------------------------------------------------------

local function defaultBuffEntry()
    return {
        gem = 0,
        spell = 0,
        minmana = 0,
        alias = false,
        announce = false,
        enabled = true,
        bands = { { validtargets = { 'war', 'brd', 'clr', 'pal', 'shd', 'shm', 'rng', 'rog', 'ber', 'mnk', 'dru', 'bst', 'mag', 'nec', 'enc', 'wiz' } } },
        spellicon = 0,
        precondition = true
    }
end

function botcast.LoadBuffConfig()
    if not myconfig.buff.spells then myconfig.buff.spells = {} end
    while #myconfig.buff.spells < 2 do
        table.insert(myconfig.buff.spells, defaultBuffEntry())
    end
    for i = 1, #myconfig.buff.spells do
        local entry = myconfig.buff.spells[i]
        if not entry then
            myconfig.buff.spells[i] = defaultBuffEntry(); entry = myconfig.buff.spells[i]
        end
        if entry.gem == 'script' then
            if not myconfig.script[entry.spell] then
                print('making script ', entry.spell)
                myconfig.script[entry.spell] = "test"
            end
            table.insert(state.getRunconfig().ScriptList, entry.spell)
        end
        if entry.enabled == nil then entry.enabled = true end
        BuffClass[i] = spellbands.applyBands('buff', entry, i)
    end
end

botconfig.RegisterConfigLoader(function()
    if botconfig.config.settings.dobuff then botcast.LoadBuffConfig() end
end)

local function IconCheck(index, EvalID)
    local entry = botconfig.getSpellEntry('buff', index)
    if not entry then return true end
    local spellicon = entry.spellicon
    if spellicon == 0 then return true end
    local botname = mq.TLO.Spawn(EvalID).Name()
    local info = charinfo.GetInfo(botname)
    local hasIcon = info and spellutils.PeerHasBuff(info, spellicon)
    if debug then print('iconcheck', botname, hasIcon, index, EvalID) end
    return not hasIcon
end

local function BuffEvalBotNeedsBuff(botid, botname, spellid, range, index, targethit)
    local spawnid = mq.TLO.Spawn(botid).ID()
    local peer = charinfo(botname)
    if not peer then return nil, nil end
    local botbuff = spellutils.PeerHasBuff(peer, spellid)
    local botbuffstack = peer.Stacks(spellid)
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

local function BuffEvalByName(index, entry, spellid, range)
    if not BuffClass[index].name then return nil, nil end
    for name, _ in pairs(BuffClass[index]) do
        if name ~= 'name' and charinfo.GetInfo(name) then
            local botid = mq.TLO.Spawn('pc =' .. name).ID()
            local botclass = mq.TLO.Spawn('pc =' .. name).Class.ShortName()
            if botid and botclass then
                local id, hit = BuffEvalBotNeedsBuff(botid, name, spellid, range, index, botclass:lower())
                if id then return id, hit end
            end
        end
    end
    return nil, nil
end

local function BuffEvalTank(index, entry, spellid, range, tank, tankid)
    if not tank or not entry or not BuffClass[index].tank or not IconCheck(index, tankid) then return nil, nil end
    return BuffEvalBotNeedsBuff(tankid, tank, spellid, range, index, 'tank')
end

local function BuffEvalBots(index, entry, spellid, range, bots, botcount)
    for i = 1, botcount do
        if bots[i] then
            local botname = mq.TLO.Spawn('pc =' .. bots[i]).Name()
            if botname then
                local botid = mq.TLO.Spawn('pc =' .. bots[i]).ID()
                local botclass = mq.TLO.Spawn('pc =' .. bots[i]).Class.ShortName()
                if IconCheck(index, botid) and botid > 0 and botclass and BuffClass[index][botclass:lower()] then
                    local id, hit = BuffEvalBotNeedsBuff(botid, botname, spellid, range, index, botclass:lower())
                    if id then return id, hit end
                end
            end
        end
    end
    return nil, nil
end

local function BuffEvalMyPet(index, entry, spell, spellid, range)
    if not BuffClass[index].mypet then return nil, nil end
    local mypetid = mq.TLO.Me.Pet.ID()
    local petbuff = mq.TLO.Me.Pet.Buff(spell)()
    local petrange = mq.TLO.Me.Pet.Distance()
    local myPeer = charinfo(mq.TLO.Me.Name())
    local petstacks = myPeer and myPeer.StacksPet(spellid)
    if mypetid > 0 and petstacks and not petbuff and petrange and range and range >= petrange then
        return mypetid, 'mypet'
    end
    return nil, nil
end

local function BuffEvalPets(index, entry, spellid, range, bots, botcount)
    if not BuffClass[index].pet then return nil, nil end
    for i = 1, botcount do
        if bots[i] then
            local peer = charinfo(bots[i])
            if peer then
                local botpet = mq.TLO.Spawn('pc =' .. bots[i]).Pet.ID()
                local petrange = mq.TLO.Spawn(botpet).Distance()
                local petbuff = spellutils.PeerHasPetBuff(peer, spellid)
                local botid = mq.TLO.Spawn('pc =' .. bots[i]).ID()
                local spawnid = mq.TLO.Spawn(botid).ID()
                local petstacks = peer.StacksPet(spellid)
                if spawnid and spawnid > 0 and botpet and botpet > 0 and petstacks and IconCheck(index, spawnid) and not petbuff and range and range >= petrange then
                    return botpet, 'pet'
                end
            end
        end
    end
    return nil, nil
end

local function BuffEval(index)
    local entry = botconfig.getSpellEntry('buff', index)
    if not entry then return nil, nil end
    local bots = spellutils.GetBotListShuffled()
    local spell, spellrange, spelltartype, spellid = spellutils.GetSpellInfo(entry)
    if not spell or not spellid then return nil, nil end
    local sid = (spellid == 1536) and 1538 or spellid -- temp fix heroic bond
    local gem = entry.gem
    local tank, tankid, tanktar = spellutils.GetTankInfo(false)
    tanktar = tanktar or (tank and charinfo(tank) and charinfo(tank).Target and charinfo(tank).Target.ID or nil)
    local myid = mq.TLO.Me.ID()
    local myclass = mq.TLO.Me.Class.ShortName()
    local range = (mq.TLO.Spell(spell).MyRange() and mq.TLO.Spell(spell).MyRange() > 0) and mq.TLO.Spell(spell).MyRange()
        or mq.TLO.Spell(spell).AERange() or
        (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.MyRange())
    local botcount = charinfo.GetPeerCnt() or 0
    if not BuffClass[index] then return nil, nil end
    if myclass ~= 'BRD' then
        local id, hit = BuffEvalSelf(index, entry, spell, sid, range, myid, myclass, tanktar)
        if id then return id, hit end
        id, hit = BuffEvalByName(index, entry, sid, range)
        if id then return id, hit end
        id, hit = BuffEvalTank(index, entry, sid, range, tank, tankid)
        if id then return id, hit end
        id, hit = BuffEvalBots(index, entry, sid, range, bots, botcount)
        if id then return id, hit end
        id, hit = BuffEvalMyPet(index, entry, spell, sid, range)
        if id then return id, hit end
        id, hit = BuffEvalPets(index, entry, sid, range, bots, botcount)
        if id then return id, hit end
    else
        local id, hit = BuffEvalSelf(index, entry, spell, sid, range, myid, myclass, tanktar)
        if id then return id, hit end
    end
    return nil, nil
end

function botcast.BuffCheck()
    if debug then print('buffcheck') end
    local mobList = state.getRunconfig().MobList
    local hasMob = mobList and mobList[1]
    return spellutils.RunSpellCheckLoop('buff', botconfig.getSpellCount('buff'), BuffEval, {
        skipInterruptForBRD = true,
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
    })
end

-- ---------------------------------------------------------------------------
-- Cure
-- ---------------------------------------------------------------------------

local function defaultCureEntry()
    return {
        gem = 0,
        spell = 0,
        minmana = 0,
        alias = false,
        announce = false,
        curetype = "all",
        enabled = true,
        bands = { { validtargets = { 'war', 'brd', 'clr', 'pal', 'shd', 'shm', 'rng', 'rog', 'ber', 'mnk', 'dru', 'bst', 'mag', 'nec', 'enc', 'wiz' } } },
        priority = false,
        precondition = true
    }
end

function botcast.LoadCureConfig()
    if not myconfig.cure.spells then myconfig.cure.spells = {} end
    while #myconfig.cure.spells < 2 do
        table.insert(myconfig.cure.spells, defaultCureEntry())
    end
    for i = 1, #myconfig.cure.spells do
        local entry = myconfig.cure.spells[i]
        if not entry then
            myconfig.cure.spells[i] = defaultCureEntry(); entry = myconfig.cure.spells[i]
        end
        if entry.gem == 'script' then
            if not myconfig.script[entry.spell] then
                print('making script ', entry.spell)
                myconfig.script[entry.spell] = "test"
            end
            table.insert(state.getRunconfig().ScriptList, entry.spell)
        end
        if entry.enabled == nil then entry.enabled = true end
        CureClass[i] = spellbands.applyBands('cure', entry, i)
        CureType[i] = {}
        for word in (entry.curetype or 'all'):gmatch("%S+") do
            CureType[i][word] = word
        end
    end
end

botconfig.RegisterConfigLoader(function()
    if botconfig.config.settings.docure then botcast.LoadCureConfig() end
end)

local function CureEvalForTarget(index, botname, botid, botclass, targethit, spelltartype)
    local cureindex = CureClass[index]
    if not cureindex then return nil, nil end
    for _, v in pairs(CureType[index] or {}) do
        if not botname then
            local curetype = mq.TLO.Me[v] and mq.TLO.Me[v]()
            if string.lower(v) ~= 'all' and curetype then
                if spelltartype == 'Self' then return 1, 'self' end
                return mq.TLO.Me.ID(), 'self'
            end
        else
            local peer = charinfo.GetInfo(botname)
            local detrimentals = peer and peer.Detrimentals or nil
            local curetype = peer and peer[v] or nil
            if string.lower(v) == 'all' and detrimentals and detrimentals > 0 then
                if targethit == 'tank' then return botid, 'tank' end
                if targethit == 'group' and spellutils.DistanceCheck('cure', index, botid) then return botid, 'group' end
                if targethit == botclass and cureindex[botclass] and spellutils.DistanceCheck('cure', index, botid) then return botid, botclass end
            end
            if string.lower(v) ~= 'all' and curetype and curetype > 0 then
                if targethit == 'tank' and mq.TLO.Spawn(botid).Type() == 'PC' and spellutils.DistanceCheck('cure', index, botid) then return botid, 'tank' end
                if targethit == 'group' and spellutils.DistanceCheck('cure', index, botid) then return botid, 'group' end
                if targethit == botclass and cureindex[botclass] and spellutils.DistanceCheck('cure', index, botid) then return botid, botclass end
            end
        end
    end
    return nil, nil
end

local function CureEval(index)
    if debug then print('cureeval') end
    local entry = botconfig.getSpellEntry('cure', index)
    local spell, _, spelltartype = spellutils.GetSpellInfo(entry)
    if not spell then return nil, nil end
    local bots = spellutils.GetBotListShuffled()
    local botcount = charinfo.GetPeerCnt()
    local tank, tankid = spellutils.GetTankInfo(false)
    local cureindex = CureClass[index]
    if not cureindex then return nil, nil end
    if cureindex.self then
        local id, hit = CureEvalForTarget(index, nil, nil, nil, 'self', spelltartype)
        if id then return id, hit end
    end
    if cureindex.tank and tankid then
        local id, hit = CureEvalForTarget(index, tank, tankid, nil, 'tank', spelltartype)
        if id then return id, hit end
    end
    if cureindex.group and botcount then
        for i = 1, botcount do
            local botname = bots[i]
            local botid = mq.TLO.Spawn('pc =' .. botname).ID()
            local botclass = mq.TLO.Spawn('pc =' .. botname).Class.ShortName()
            if botclass then botclass = string.lower(botclass) end
            if cureindex[botclass] and botid and mq.TLO.Group.Member(botname).ID() then
                local id, hit = CureEvalForTarget(index, botname, botid, botclass, 'group', spelltartype)
                if id then return id, hit end
            end
        end
    end
    if botcount then
        for i = 1, botcount do
            local botname = bots[i]
            if botname then
                local botid = mq.TLO.Spawn('pc =' .. botname).ID()
                local botclass = mq.TLO.Spawn('pc =' .. botname).Class.ShortName()
                if botclass then botclass = string.lower(botclass) end
                if botclass and cureindex[botclass] then
                    local id, hit = CureEvalForTarget(index, botname, botid, botclass, botclass, spelltartype)
                    if id then return id, hit end
                end
            end
        end
    end
    return nil, nil
end

function botcast.CureCheck()
    if debug then print('curecheck') end
    if state.getRunconfig().SpellTimer > mq.gettime() then return false end
    local priority = myconfig.cure.prioritycure
    return spellutils.RunSpellCheckLoop('cure', botconfig.getSpellCount('cure'), CureEval, {
        skipInterruptForBRD = true,
        priority = priority,
        afterCast = priority and function(i)
            local e, c = CureEval(i)
            return e and c
        end or nil,
        entryValid = function(i)
            local entry = botconfig.getSpellEntry('cure', i)
            if not entry then return false end
            local gem = entry.gem
            return (entry.enabled ~= false) and ((type(gem) == 'number' and gem ~= 0) or type(gem) == 'string')
        end,
    })
end

-- ---------------------------------------------------------------------------
-- Heal
-- ---------------------------------------------------------------------------

local function defaultHealEntry()
    return {
        gem = 0,
        spell = 0,
        minmana = 0,
        minmanapct = 0,
        maxmanapct = 100,
        alias = false,
        announce = false,
        enabled = true,
        bands = { { validtargets = { 'pc', 'pet', 'grp', 'group', 'war', 'shd', 'pal', 'rng', 'mnk', 'rog', 'brd', 'bst', 'ber', 'shm', 'clr', 'dru', 'wiz', 'mag', 'enc', 'nec', 'mypet', 'self' }, min = 0, max = 60 } },
        priority = false,
        precondition = true
    }
end

function botcast.LoadHealConfig()
    if myconfig.heal.rezoffset == nil then myconfig.heal.rezoffset = 0 end
    if myconfig.heal.interruptlevel == nil then myconfig.heal.interruptlevel = 0.80 end
    if myconfig.heal.xttargets == nil then myconfig.heal.xttargets = 0 end
    if not myconfig.heal.spells then myconfig.heal.spells = {} end
    while #myconfig.heal.spells < 2 do
        table.insert(myconfig.heal.spells, defaultHealEntry())
    end
    for i = 1, #myconfig.heal.spells do
        local entry = myconfig.heal.spells[i]
        if not entry then
            myconfig.heal.spells[i] = defaultHealEntry(); entry = myconfig.heal.spells[i]
        end
        if entry.gem == 'script' then
            if not myconfig.script[entry.spell] then
                print('making script ', entry.spell)
                myconfig.script[entry.spell] = "test"
            end
            table.insert(state.getRunconfig().ScriptList, entry.spell)
        end
        if entry.enabled == nil then entry.enabled = true end
        AHThreshold[i] = spellbands.applyBands('heal', entry, i)
    end
    if myconfig.heal.xttargets then
        for num in string.gmatch(tostring(myconfig.heal.xttargets), "%d+") do
            local n = tonumber(num)
            if n then XTList[n] = n end
        end
    end
    _G.AHThreshold = AHThreshold
    _G.XTList = XTList
end

botconfig.RegisterConfigLoader(function()
    if botconfig.config.settings.doheal then botcast.LoadHealConfig() end
end)

local function hpInBand(pct, th)
    return spellbands.hpInBand(pct, th)
end

local function HPEvalContext(index)
    local entry = botconfig.getSpellEntry('heal', index)
    if not entry then return nil end
    local gem = entry.gem
    local tank, tankid = spellutils.GetTankInfo(true)
    local botcount = charinfo.GetPeerCnt()
    local bots = spellutils.GetBotListShuffled()
    local botstr = table.concat(charinfo.GetPeers(), " ")
    local tanknbid = tank and string.find(botstr, tank)
    local spell, spellrange = spellutils.GetSpellInfo(entry)
    if not spell then return nil end
    if gem == 'item' and mq.TLO.FindItem(entry.spell)() then
        spellrange = mq.TLO.FindItem(entry.spell).Spell.MyRange()
    end
    return {
        entry = entry,
        gem = gem,
        spell = spell,
        spellrange = spellrange,
        tank = tank,
        tankid = tankid,
        tanknbid = tanknbid,
        botcount = botcount,
        bots = bots,
    }
end

local function CorpseRezIdForFilter(index, ctx, filter)
    local corpsecount = mq.TLO.SpawnCount('pccorpse radius ' .. myconfig.settings.acleash)()
    if not corpsecount or corpsecount == 0 then return nil end
    local corpsedist = myconfig.settings.acleash
    local thresh = AHThreshold[index]
    local matches = 0
    for i = 1, corpsecount do
        local nearcorpse = mq.TLO.NearestSpawn(i, 'pccorpse radius ' .. corpsedist).CleanName()
        if nearcorpse then nearcorpse = string.gsub(nearcorpse, "'s corpse", "") end
        local rezid = mq.TLO.NearestSpawn(i, 'pccorpse radius ' .. corpsedist).ID()
        local match = false
        if filter == 'all' then
            match = true
        elseif filter == 'bots' and ctx.botcount then
            for k = 1, ctx.botcount do
                local peer = charinfo.GetInfo(ctx.bots[k])
                if peer and (peer.Name or peer.sender) == nearcorpse then match = true break end
            end
        elseif filter == 'raid' and mq.TLO.Raid.Members() and mq.TLO.Raid.Members() > 0 then
            for k = 1, mq.TLO.Raid.Members() do
                local raidname = mq.TLO.Raid.Member(k).Name()
                if raidname == nearcorpse then match = true break end
            end
        end
        if match then
            if myconfig.heal.rezoffset > 0 and matches < myconfig.heal.rezoffset and corpsecount > myconfig.heal.rezoffset then
                matches = matches + 1
            else
                return rezid
            end
        end
    end
    return nil
end

local function HPEvalCorpse(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].corpse then return nil, nil end
    if not AHThreshold[index].cbt and state.getRunconfig().MobList and state.getRunconfig().MobList[1] then return nil, nil end
    if AHThreshold[index].all then
        local rezid = CorpseRezIdForFilter(index, ctx, 'all')
        if rezid then return rezid, 'corpse' end
    end
    if AHThreshold[index].bots then
        local rezid = CorpseRezIdForFilter(index, ctx, 'bots')
        if rezid then return rezid, 'corpse' end
    end
    if AHThreshold[index].raid then
        local rezid = CorpseRezIdForFilter(index, ctx, 'raid')
        if rezid then return rezid, 'corpse' end
    end
    return nil, nil
end

local function HPEvalSelf(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].self then return nil, nil end
    local pct = mq.TLO.Me.PctHPs()
    if not hpInBand(pct, AHThreshold[index].self) then return nil, nil end
    if mq.TLO.Spell(ctx.entry.spell).TargetType() == 'Self' then return 1, 'self' end
    return mq.TLO.Me.ID(), 'self'
end

local function HPEvalGrp(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].grp then return nil, nil end
    local aeRange = mq.TLO.Spell(ctx.entry.spell).AERange()
    if ctx.gem == 'item' and mq.TLO.FindItem(ctx.entry.spell)() then aeRange = mq.TLO.FindItem(ctx.entry.spell).Spell.AERange() end
    local grpmatch = 0
    for k = 0, mq.TLO.Group.Members() do
        local grpmempcthp = mq.TLO.Group.Member(k).PctHPs()
        local grpmemdist = mq.TLO.Group.Member(k).Distance()
        if mq.TLO.Group.Member(k).Present() and grpmempcthp and hpInBand(grpmempcthp, AHThreshold[index].grp) and grpmemdist and aeRange and grpmemdist <= aeRange then
            if mq.TLO.Group.Member(k).Type() ~= 'Corpse' then grpmatch = grpmatch + 1 end
        end
    end
    if grpmatch >= (ctx.entry.tarcnt or 1) then
        if mq.TLO.Spell(ctx.entry.spell).TargetType() == 'Group v1' then return 1, 'grp' end
        return mq.TLO.Me.ID(), 'grp'
    end
    return nil, nil
end

local function HPEvalTank(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].tank or not AHThreshold[index].pc or not ctx.tank then return nil, nil end
    local tankhp = mq.TLO.Group.Member(ctx.tank).PctHPs()
    local tankdist = mq.TLO.Spawn(ctx.tankid).Distance()
    local tankinfo = charinfo.GetInfo(ctx.tank)
    local tanknbhp = tankinfo and tankinfo.PctHPs or nil
    if not ctx.tanknbid and ctx.tankid and mq.TLO.Group.Member(ctx.tank).Index() then
        if mq.TLO.Spawn(ctx.tankid).Type() == 'PC' and tankhp and hpInBand(tankhp, AHThreshold[index].tank) and tankdist and ctx.spellrange and tankdist <= ctx.spellrange then
            return mq.TLO.Group.Member(ctx.tank).ID(), 'tank'
        end
    elseif ctx.tanknbid then
        if mq.TLO.Spawn(ctx.tankid).Type() == 'PC' and tanknbhp and hpInBand(tanknbhp, AHThreshold[index].tank) and tankdist and ctx.spellrange and tankdist <= ctx.spellrange then
            return mq.TLO.Spawn('pc =' .. ctx.tank).ID(), 'tank'
        end
    end
    return nil, nil
end

local function HPEvalPc(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].pc then return nil, nil end
    if AHThreshold[index].group and ctx.botcount then
        for i = 1, ctx.botcount do
            local botid = mq.TLO.Spawn('pc =' .. ctx.bots[i]).ID()
            local botclass = mq.TLO.Spawn('pc =' .. ctx.bots[i]).Class.ShortName()
            local peer = charinfo.GetInfo(ctx.bots[i])
            local bothp = peer and peer.PctHPs or nil
            local botdist = mq.TLO.Spawn('pc =' .. ctx.bots[i]).Distance()
            if botclass and AHThreshold[index][botclass:lower()] and bothp and mq.TLO.Spawn(botid).Type() == 'PC' and hpInBand(bothp, AHThreshold[index][botclass:lower()]) then
                if mq.TLO.Group.Member(ctx.bots[i]).Present() and ctx.spellrange and botdist and botdist <= ctx.spellrange then
                    return botid, botclass:lower()
                end
            end
        end
    end
    if mq.TLO.Group.Members() > 0 then
        for i = 1, mq.TLO.Group.Members() do
            local grpclass = mq.TLO.Group(i).Class.ShortName()
            local grpid = mq.TLO.Group(i).ID()
            local grphp = mq.TLO.Group(i).PctHPs()
            local grpdist = mq.TLO.Group(i).Distance()
            if AHThreshold[index][grpclass:lower()] and mq.TLO.Spawn(grpid).Type() == 'PC' and grphp and hpInBand(grphp, AHThreshold[index][grpclass:lower()]) then
                if ctx.spellrange and grpdist and grpdist <= ctx.spellrange then return grpid, grpclass:lower() end
            end
        end
    end
    if not AHThreshold[index].group and ctx.botcount then
        for i = 1, ctx.botcount do
            local botid = mq.TLO.Spawn('pc =' .. ctx.bots[i]).ID()
            local botclass = mq.TLO.Spawn('pc =' .. ctx.bots[i]).Class.ShortName()
            local peer = charinfo.GetInfo(ctx.bots[i])
            local bothp = peer and peer.PctHPs or nil
            local botdist = mq.TLO.Spawn(ctx.bots[i]).Distance()
            if botid and botclass and AHThreshold[index][botclass:lower()] and mq.TLO.Spawn(botid).Type() == 'PC' and hpInBand(bothp, AHThreshold[index][botclass:lower()]) then
                if botdist and ctx.spellrange and botdist <= ctx.spellrange then return botid, botclass:lower() end
            end
        end
    end
    return nil, nil
end

local function HPEvalMyPet(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].mypet then return nil, nil end
    local mypetid = mq.TLO.Me.Pet.ID()
    local mypetdist = mq.TLO.Me.Pet.Distance()
    local mypethp = mq.TLO.Me.Pet.PctHPs()
    if mypetid and mypetid > 0 and mypethp and hpInBand(mypethp, AHThreshold[index].mypet) and mypetdist <= ctx.spellrange then
        return mypetid, 'mypet'
    end
    return nil, nil
end

local function HPEvalPets(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].pet or not ctx.botcount then return nil, nil end
    for i = 1, ctx.botcount do
        local petid = mq.TLO.Spawn('pc =' .. ctx.bots[i]).Pet.ID()
        local peer = charinfo.GetInfo(ctx.bots[i])
        local pethp = peer and peer.PetHP or nil
        local petdist = mq.TLO.Spawn(petid).Distance()
        if petid and pethp and pethp > 0 and hpInBand(pethp, AHThreshold[index].pet) and ctx.spellrange and petdist and petdist <= ctx.spellrange then
            return petid, 'pet'
        end
    end
    return nil, nil
end

local function HPEvalXtgt(index, ctx)
    if not AHThreshold[index] or not AHThreshold[index].xtgt then return nil, nil end
    local xtslots = mq.TLO.Me.XTargetSlots() or 0
    for i = 1, xtslots do
        if XTList[i] then
            local xtar = mq.TLO.Me.XTarget(i)()
            if xtar then
                local xtpchpt = mq.TLO.Me.XTarget(i).PctHPs() or 101
                local xtrange = mq.TLO.Me.XTarget(i).Distance() or 500
                local xtid = mq.TLO.Me.XTarget(i).ID() or 0
                if hpInBand(xtpchpt, AHThreshold[index].xtgt) and xtrange <= ctx.spellrange and xtid > 0 then
                    return xtid, 'xtgt'
                end
            end
        end
    end
    return nil, nil
end

local function HPEval(index)
    if not index then return nil, nil end
    if debug then print('hpeval ' .. index, botconfig.getSpellEntry('heal', index) and botconfig.getSpellEntry('heal', index).spell) end
    local ctx = HPEvalContext(index)
    if not ctx then return nil, nil end
    local id, hit = HPEvalCorpse(index, ctx)
    if id then return id, hit end
    id, hit = HPEvalSelf(index, ctx)
    if id then return id, hit end
    id, hit = HPEvalGrp(index, ctx)
    if id then return id, hit end
    id, hit = HPEvalTank(index, ctx)
    if id then return id, hit end
    id, hit = HPEvalPc(index, ctx)
    if id then return id, hit end
    id, hit = HPEvalMyPet(index, ctx)
    if id then return id, hit end
    id, hit = HPEvalPets(index, ctx)
    if id then return id, hit end
    id, hit = HPEvalXtgt(index, ctx)
    if id then return id, hit end
    return nil, nil
end

function botcast.ValidateHeal()
    local target = state.getRunconfig().CurSpell.target
    local index = state.getRunconfig().CurSpell.spell
    local healtar, matchtype = HPEval(index)
    if debug then print('validateheal') end
    return healtar and healtar > 0
end

function botcast.HealCheck()
    return spellutils.RunSpellCheckLoop('heal', botconfig.getSpellCount('heal'), HPEval, {
        priority = false,
        afterCast = function(i)
            local entry = botconfig.getSpellEntry('heal', i)
            if entry and entry.priority then return botcast.ValidateHeal() end
            return false
        end,
        entryValid = function(i)
            local entry = botconfig.getSpellEntry('heal', i)
            if not entry then return false end
            if entry.enabled == false or entry.gem == 0 then return false end
            local minmanapct = entry.minmanapct
            local maxmanapct = entry.maxmanapct
            if minmanapct == nil then minmanapct = 0 end
            if maxmanapct == nil then maxmanapct = 100 end
            local mymana = mq.TLO.Me.PctMana()
            if mymana and (mymana < minmanapct or mymana > maxmanapct) then return false end
            return true
        end,
    })
end

-- ---------------------------------------------------------------------------
-- Debuff
-- ---------------------------------------------------------------------------

local function defaultDebuffEntry()
    return {
        gem = 0,
        spell = 0,
        minmana = 0,
        alias = false,
        announce = false,
        enabled = true,
        bands = { { validtargets = { 'tanktar', 'notanktar', 'named' }, min = 20, max = 100 } },
        charmnames = '',
        recast = 0,
        delay = 0,
        precondition = true
    }
end

function botcast.LoadDebuffConfig()
    spellstates.EnsureDebuffState()
    if not myconfig.debuff.spells then myconfig.debuff.spells = {} end
    while #myconfig.debuff.spells < 2 do
        table.insert(myconfig.debuff.spells, defaultDebuffEntry())
    end
    for i = 1, #myconfig.debuff.spells do
        local entry = myconfig.debuff.spells[i]
        if not entry then
            myconfig.debuff.spells[i] = defaultDebuffEntry(); entry = myconfig.debuff.spells[i]
        end
        if not entry.delay then entry.delay = 0 end
        if entry.gem == 'script' then
            if not myconfig.script[entry.spell] then
                print('making script ', entry.spell)
                myconfig.script[entry.spell] = "test"
            end
            table.insert(state.getRunconfig().ScriptList, entry.spell)
        end
        if entry.enabled == nil then entry.enabled = true end
        DebuffBands[i] = spellbands.applyBands('debuff', entry, i)
    end
end

botconfig.RegisterConfigLoader(function()
    if botconfig.config.settings.dodebuff then botcast.LoadDebuffConfig() end
end)

local noncombatzones = { 'GuildHall', 'GuildLobby', 'PoKnowledge', 'Nexus', 'Bazaar', 'AbysmalSea', 'potranquility' }

local function ADSpawnCheck_ValidateAcmTarget(rc)
    if rc.engageTargetId then
        if not mq.TLO.Spawn(rc.engageTargetId).ID() or mq.TLO.Spawn(rc.engageTargetId).Type() == 'Corpse' then
            rc.engageTargetId = nil
            if debug then print('clearing engageTargetId') end
        end
    end
    if utils.isInList(mq.TLO.Zone.ShortName(), noncombatzones) then return false end
    return true
end

local function ADSpawnCheck_BuildSpawnList()
    local function buildMobListPredicate(spawn)
        local distance2D = spawn.Distance() or 5000
        return distance2D <= myconfig.settings.acleash
    end
    return mq.getFilteredSpawns(buildMobListPredicate)
end

local function ADSpawnCheck_FilterSpawn(spawn, rc)
    local distance2D = spawn.Distance() or 5000
    local distanceZ = spawn.DistanceZ() or 5000
    local spawnname = spawn.CleanName() or 'none'
    if rc.campstatus then
        local spawnx, spawny, spawnz = spawn.X(), spawn.Y(), spawn.Z()
        distance2D = utils.calcDist2D(spawnx, spawny, rc.makecamp.x, rc.makecamp.y)
        if spawnz then distanceZ = math.abs(spawnz - rc.makecamp.z) end
    end
    if rc.FTECount and spawn.ID() and rc.FTEList and rc.FTEList[spawn.ID()] and rc.FTEList[spawn.ID()].timer > mq.gettime() then
        return false
    end
    if not (spawnname and distance2D and distanceZ and distance2D <= myconfig.settings.acleash and distanceZ <= myconfig.settings.zradius) then
        return false
    end
    if string.find(rc.ExcludeList or '', spawnname) then return false end
    if myconfig.settings.TargetFilter == 2 then
        return not string.find('pc,banner,campfire,mercenary,mount,aura,corpse', string.lower(spawn.Type()))
    end
    if myconfig.settings.TargetFilter == 1 then
        return (spawn.Type() == 'NPC' or (spawn.Type() == 'Pet' and spawn.Master.Type() ~= 'PC')) and spawn.LineOfSight()
    end
    if myconfig.settings.TargetFilter == 0 then
        return (spawn.Type() == 'NPC' or (spawn.Type() == 'Pet' and spawn.Master.Type() ~= 'PC')) and spawn.Aggressive() and spawn.LineOfSight()
    end
    return false
end

local function ADSpawnCheck_ApplyFilter(spawnlist, rc)
    rc.MobList = {}
    for _, spawn in ipairs(spawnlist) do
        if ADSpawnCheck_FilterSpawn(spawn, rc) then
            table.insert(rc.MobList, spawn)
        end
    end
end

function botcast.ADSpawnCheck()
    local rc = state.getRunconfig()
    if not ADSpawnCheck_ValidateAcmTarget(rc) then return end
    local spawnlist = ADSpawnCheck_BuildSpawnList()
    ADSpawnCheck_ApplyFilter(spawnlist, rc)
    table.sort(rc.MobList, function(a, b) return a.ID() < b.ID() end)
    local mobcount = 0
    local killtarpresent = false
    if KillTarget and (mq.TLO.Spawn(KillTarget).Type() == 'Corpse' or not mq.TLO.Spawn(KillTarget).ID()) then KillTarget = nil end
    for k, v in ipairs(rc.MobList) do
        mobcount = mobcount + 1
        if v.ID() == KillTarget then killtarpresent = true end
    end
    if not killtarpresent and KillTarget then table.insert(rc.MobList, mq.TLO.Spawn(KillTarget)) end
    rc.MobCount = mobcount
end

local function DebuffEvalBuildContext(index)
    local entry = botconfig.getSpellEntry('debuff', index)
    if not entry then return nil end
    local spell, spellrange, spelltartype, spellid = spellutils.GetSpellInfo(entry)
    if not spell then return nil end
    local gem = entry.gem
    if spellrange == 0 and spelltartype == 'PB AE' then
        spellrange = mq.TLO.Spell(spell).AERange() or
        (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.AERange())
    end
    local spelldur = mq.TLO.Spell(entry.spell).MyDuration() or
        (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.MyDuration())
    local tank, tankid, tanktar, tanktarhp = spellutils.GetTankInfo(true)
    if tanktar == 0 then tanktar = nil end
    local tanktarlvl = tanktar and mq.TLO.Spawn(tanktar).Level()
    if type(gem) == 'number' or gem == 'item' or gem == 'disc' or gem == 'alt' then
        spellid = mq.TLO.Spell(entry.spell).ID() or
            (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.ID())
    end
    local spellmaxlvl = mq.TLO.Spell(spellid).MaxLevel() or
        (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.MaxLevel())
    local myrange = (type(gem) == 'number' or gem == 'item' or gem == 'disc' or gem == 'alt') and
        (mq.TLO.Spell(spellid).MyRange() or (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.MyRange()))
        or (gem == 'ability' and 20) or nil
    if mq.TLO.Spell(spellid).Category() == 'Pet' then myrange = myconfig.settings.acleash end
    local db = DebuffBands[index]
    local mobMin = db and db.mobMin or 0
    local mobMax = db and db.mobMax or 100
    return {
        entry = entry,
        spell = spell,
        spellid = spellid,
        spellrange = spellrange,
        spelldur = spelldur,
        gem = gem,
        tank = tank,
        tankid = tankid,
        tanktar = tanktar,
        tanktarhp = tanktarhp,
        tanktarlvl = tanktarlvl,
        spellmaxlvl = spellmaxlvl,
        myrange = myrange,
        mobList = state.getRunconfig().MobList or {},
        mobMin = mobMin,
        mobMax = mobMax,
    }
end

local function DebuffEvalTankTar(index, ctx)
    local entry = ctx.entry
    local gem = entry.gem
    local db = DebuffBands[index]
    local inMobList = false
    if debug then print('debuff tanktar', index, 'tanktar=', ctx.tanktar) end
    if ctx.tanktar then for _, v in ipairs(ctx.mobList or {}) do if v.ID() == ctx.tanktar then inMobList = true break end end end
    if debug then print('debuff tanktar', index, 'inMobList=', inMobList) end
    if not db or not db.tanktar or not ctx.tanktar then return nil, nil end
    local tanktarhp = ctx.tanktarhp
    if tanktarhp == nil then tanktarhp = mq.TLO.Spawn(ctx.tanktar).PctHPs() end
    if not spellbands.hpInBand(tanktarhp, { min = db.mobMin, max = db.mobMax }) then return nil, nil end
    for _, v in ipairs(ctx.mobList) do
        if v.ID() == ctx.tanktar then
            local myrange = ctx.myrange
            if entry.gem == 'ability' then myrange = v.MaxRangeTo() end
            if not (myrange and v.Distance() and v.Distance() > myrange) then
                if not (ctx.spelldur and tonumber(ctx.spelldur) > 0 and spellstates.HasDebuffLongerThan(v.ID(), ctx.spellid, 6000)) then
                    local tanktarstack = mq.TLO.Spell(entry.spell).StacksSpawn(ctx.tanktar)() or
                        (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.StacksSpawn(ctx.tanktar))
                    if ctx.tanktarlvl and mq.TLO.Spell(ctx.spellid).Subcategory() == 'Enthrall' and ctx.spellmaxlvl and ctx.spellmaxlvl ~= 0 and ctx.spellmaxlvl < ctx.tanktarlvl then
                        return nil, nil
                    end
                    if (type(gem) == 'number' or gem == 'alt' or gem == 'disc' or gem == 'item') and not tanktarstack then
                        if debug then print('debuff tanktar skip: stacks', index, entry.spell) end
                        return nil, nil
                    end
                    return state.getRunconfig().engageTargetId or ctx.tanktar, 'tanktar'
                end
            end
        end
    end
    return nil, nil
end

local function DebuffEvalNotanktar(index, ctx)
    local entry = ctx.entry
    local gem = entry.gem
    local db = DebuffBands[index]
    if not db or not db.notanktar or not ctx.mobList[1] then return nil, nil end
    for _, v in ipairs(ctx.mobList) do
        if v.ID() ~= ctx.tanktar then
            local mobhp = v.PctHPs()
            if spellbands.hpInBand(mobhp, { min = db.mobMin, max = db.mobMax }) then
                local myrange = ctx.myrange
                if entry.gem == 'ability' then myrange = v.MaxRangeTo() end
                if not (myrange and v.Distance() and v.Distance() > myrange) then
                    local tarstacks = mq.TLO.Spell(entry.spell).StacksSpawn(v.ID())() or
                        (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.StacksSpawn(v.ID()))
                    if not (ctx.spellid and v.Level() and ctx.spellmaxlvl and ctx.spellmaxlvl ~= 0 and ctx.spellmaxlvl < v.Level()) then
                        if not ((type(gem) == 'number' or gem == 'alt' or gem == 'disc' or gem == 'item') and not tarstacks) then
                            if not (tonumber(ctx.spelldur) > 0 and v.ID() and spellstates.HasDebuffLongerThan(v.ID(), ctx.spellid, 6000)) then
                                return v.ID(), 'notanktar'
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, nil
end

local function DebuffEvalNamedTankTar(index, ctx)
    local entry = ctx.entry
    local gem = entry.gem
    local db = DebuffBands[index]
    if not db or not db.named or not ctx.tanktar then return nil, nil end
    local tanktarhp = ctx.tanktarhp
    if tanktarhp == nil then tanktarhp = mq.TLO.Spawn(ctx.tanktar).PctHPs() end
    if not spellbands.hpInBand(tanktarhp, { min = db.mobMin, max = db.mobMax }) then return nil, nil end
    for _, v in ipairs(ctx.mobList) do
        if v.ID() == ctx.tanktar and v.Named() then
            local myrange = ctx.myrange
            if entry.gem == 'ability' then myrange = v.MaxRangeTo() end
            if myrange and v.Distance() and v.Distance() > myrange then return nil, nil end
            if not (ctx.spelldur and tonumber(ctx.spelldur) > 0 and spellstates.HasDebuffLongerThan(v.ID(), ctx.spellid, 6000)) then
                local tanktarstack = mq.TLO.Spell(entry.spell).StacksSpawn(ctx.tanktar)() or
                    (gem == 'item' and mq.TLO.FindItem(entry.spell)() and mq.TLO.FindItem(entry.spell).Spell.StacksSpawn(ctx.tanktar))
                if ctx.tanktarlvl and mq.TLO.Spell(ctx.spellid).Subcategory() == 'Enthrall' and ctx.spellmaxlvl and ctx.spellmaxlvl ~= 0 and ctx.spellmaxlvl < ctx.tanktarlvl then
                    return nil, nil
                end
                if (type(gem) == 'number' or gem == 'alt' or gem == 'disc' or gem == 'item') and not tanktarstack then
                    return nil, nil
                end
                return state.getRunconfig().engageTargetId or ctx.tanktar, 'tanktar'
            end
        end
    end
    return nil, nil
end

local function DebuffEval(index)
    if debug then print('debuff eval ', index) end
    local entry = botconfig.getSpellEntry('debuff', index)
    if not entry then return nil, nil end
    if entry.tarcnt and entry.tarcnt > state.getRunconfig().MobCount then return nil, nil end
    local id, hit = charm.GetRecastRequestForIndex(index)
    if id then
        charm.ClearRecastRequest()
        return id, hit
    end
    local ctx = DebuffEvalBuildContext(index)
    if not ctx then return nil, nil end
    id, hit = charm.EvalTarget(index, ctx)
    if id then return id, hit end
    id, hit = DebuffEvalTankTar(index, ctx)
    if id then return id, hit end
    id, hit = DebuffEvalNotanktar(index, ctx)
    if id then return id, hit end
    id, hit = DebuffEvalNamedTankTar(index, ctx)
    if id then return id, hit end
    return nil, nil
end

local function DebuffOnBeforeCast(i, EvalID, targethit)
    local entry = botconfig.getSpellEntry('debuff', i)
    if entry and spellstates.GetRecastCounter(EvalID, i) >= (entry.recast or 0) then
        return false
    end
    charm.BeforeCast(EvalID, targethit)
    if targethit == 'tanktar' and EvalID and EvalID > 0 then
        if not myconfig.melee.offtank then state.getRunconfig().engageTargetId = EvalID end
        if mq.TLO.Pet.Target.ID() ~= EvalID and not mq.TLO.Me.Pet.Combat() then
            mq.cmdf('/pet attack %s', EvalID)
        end
    end
    return true
end

function botcast.DebuffCheck()
    if debug then print('debuffcheck') end
    if state.getRunconfig().SpellTimer > mq.gettime() then return false end
    local mobcountstart = state.getRunconfig().MobCount
    local botmelee = require('botmelee')
    if state.getRunconfig().MobList and state.getRunconfig().MobList[1] then
        local tank, _, tanktar = spellutils.GetTankInfo(true)
        if tanktar and tanktar > 0 and mq.TLO.Pet.Target.ID() ~= tanktar and not mq.TLO.Me.Pet.Combat() then botmelee.AdvCombat() end
    end
    return spellutils.RunSpellCheckLoop('debuff', botconfig.getSpellCount('debuff'), DebuffEval, {
        skipInterruptForBRD = true,
        immuneCheck = true,
        beforeCast = DebuffOnBeforeCast,
        entryValid = function(i)
            local entry = botconfig.getSpellEntry('debuff', i)
            if not entry then return false end
            local gem = entry.gem
            return (entry.enabled ~= false) and ((type(gem) == 'number' and gem ~= 0) or type(gem) == 'string')
        end,
        afterCast = function(i, EvalID, targethit)
            if spellstates.GetDebuffDelay(i) and spellstates.GetDebuffDelay(i) > mq.gettime() then return false end
            if mobcountstart < state.getRunconfig().MobCount then return false end
            local prevID = EvalID
            local newEvalID, newTargethit = DebuffEval(i)
            local adEntry = botconfig.getSpellEntry('debuff', i)
            if newEvalID and prevID == newEvalID and adEntry and (adEntry.recast or 0) > 0 and state.getRunconfig().CurSpell and state.getRunconfig().CurSpell.spell == i and state.getRunconfig().CurSpell.resisted then
                local newCount = spellstates.IncrementRecastCounter(EvalID, i)
                state.getRunconfig().CurSpell = {}
                if newCount >= adEntry.recast then
                    printf(
                    '\ayCZBot:\ax\ar%s\ax has resisted spell \ar%s\ax debuff[%s] \am%s\ax times, disabling spell for this spawn',
                        mq.TLO.Spawn(EvalID).CleanName(), adEntry.spell, i, adEntry.recast)
                    local recastduration = 600000 + mq.gettime()
                    local spellid = mq.TLO.Spell(adEntry.spell).ID() or
                    (adEntry.gem == 'item' and mq.TLO.FindItem(adEntry.spell)() and mq.TLO.FindItem(adEntry.spell).Spell.ID())
                    local spelldur = tonumber(mq.TLO.Spell(spellid).MyDuration()) or 0
                    if spelldur > 0 then spellstates.DebuffListUpdate(EvalID, adEntry.spell, recastduration) end
                end
                return true
            end
            return false
        end,
    })
end

do
    local hookregistry = require('lib.hookregistry')
    hookregistry.registerMainloopHook('ADSpawnCheck', function()
        botcast.ADSpawnCheck()
    end, 400)
    hookregistry.registerMainloopHook('priorityCure', function()
        if not myconfig.settings.docure or not (myconfig.cure.spells and #myconfig.cure.spells > 0) or not myconfig.cure.prioritycure then return end
        if state.isBusy() then return end
        botcast.CureCheck()
    end, 700)
    hookregistry.registerMainloopHook('doHeal', function()
        if not myconfig.settings.doheal or not (myconfig.heal.spells and #myconfig.heal.spells > 0) then return end
        if state.isBusy() then return end
        botcast.HealCheck()
    end, 900)
    hookregistry.registerMainloopHook('doDebuff', function()
        if not myconfig.settings.dodebuff or not (myconfig.debuff.spells and #myconfig.debuff.spells > 0) or not state.getRunconfig().MobList[1] then return end
        if state.isBusy() then return end
        botcast.DebuffCheck()
    end, 1000)
    hookregistry.registerMainloopHook('doBuff', function()
        if not myconfig.settings.dobuff or not (myconfig.buff.spells and #myconfig.buff.spells > 0) then return end
        if state.isBusy() then return end
        botcast.BuffCheck()
    end, 1100)
    hookregistry.registerMainloopHook('doCure', function()
        if not myconfig.settings.docure or not (myconfig.cure.spells and #myconfig.cure.spells > 0) then return end
        if state.isBusy() then return end
        botcast.CureCheck()
    end, 1200)
end

return botcast
