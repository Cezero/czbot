local mq = require('mq')

local trotsheal = {}

function trotsheal.LoadHealConfig()
    if (myconfig.heal['count'] == nil) then myconfig.heal['count'] = 2 end
    if (myconfig.heal['rezoffset'] == nil) then myconfig.heal['rezoffset'] = 0 end
    if (myconfig.heal['interruptlevel'] == nil) then myconfig.heal['interruptlevel'] = .80 end
    if (myconfig.heal['xttargets'] == nil) then myconfig.heal['xttargets'] = 0 end
    HealList = {}
    XTList = {}
    local healkey = 'ahx'
    AHThreshold = {}
    for i = 1, myconfig.heal['count'] do
        if i <= myconfig.heal['count'] then
            healkey = "ah" .. i
            AHThreshold[i] = {}
            local number = 0
            local letters = ''
            if not myconfig[healkey] then myconfig[healkey] = { gem = 0, spell = 0, minmana = 0, alias = false, announce = false, tarcnt = 0, class =
                'pc pet group hp50 war shd pal rng mnk rog brd bst ber shm clr dru wiz mag enc nec tnt mypet self', priority = false, precondition = true } end
            --AHThreshold table build
            if myconfig[healkey]['gem'] == 'script' then
                if not myconfig['script'][myconfig[healkey]['spell']] then
                    print('making script ', myconfig[healkey]['spell'])
                    myconfig['script'][myconfig[healkey]['spell']] = "test"
                end
                table.insert(runconfig['ScriptList'], myconfig[healkey]['spell'])
            end
            for word in myconfig[healkey].class:gmatch("%S+") do
                letters = word:match("(%a+)")
                numbers = tonumber(word:match("(%d+)"))
                if not numbers then numbers = 0 end
                --AHThreshold[i], letters)
                AHThreshold[i][letters] = numbers
            end
            for k, v in pairs(AHThreshold[i]) do
                if debug then print(k, v, AHThreshold[i].hp) end
                if k ~= 'hp' and v == 0 then AHThreshold[i][k] = AHThreshold[i].hp end
                if k == 'corpse' or k == 'bots' or k == 'raid' or k == 'cbt' or k == 'all' then AHThreshold[i][k] = 200 end
                --print('for spell ',i,' class ',k,' heal at ',AHThreshold[i][k],' percent hp')
            end
        end
    end
    if myconfig.heal['xttargets'] then
        local xttargets_str = myconfig.heal['xttargets'] -- e.g., "1 ,2 ,3 ,4 ,5"
        for num in string.gmatch(xttargets_str, "%d+") do
            local n = tonumber(num)
            if n then XTList[n] = n end
        end
    end
    -- threshold stuff - use 1-D array, value will be spell# of 1-D table maps, keys will be class, values will be thresholds
    -- build threshold array (old style) treshold(type, percentage), possible types are pc, pet, tank, grp, xtgt, or name
    -- pc
    -- check class line, otherwise use class# values (almost noone uses this today), or use hp#
    -- pet
    -- check class line, use mypet# for mypet, pet# for other pets, or hp#
    -- tank
    -- check tank# or hp#
    -- grp
    -- use grp#
    -- xtgt
    -- use hp#
    -- name
    -- use name#, or use hp#
end

-- checks for valid targets and builds heal list
function trotsheal.HPEval(index)
    if not index then return false end
    local entry = myconfig['ah' .. index]
    local tank = myconfig.settings['TankName']
    local tankid = mq.TLO.Spawn('pc =' .. tank).ID()
    local botcount = mq.TLO.NetBots.Counts()
    local spellrange = mq.TLO.Spell(entry.spell).MyRange()
    local botstr = mq.TLO.NetBots.Client()
    local tanknbid = string.find(botstr, tank)
    local bots = {}
    local spell = myconfig['ah' .. index]['spell']
    local spellrange = mq.TLO.Spell(spell).MyRange()
    local spelltartype = mq.TLO.Spell(spell).TargetType()
    if gem == 'item' then
        spell = mq.TLO.FindItem(spell).Spell.Name()
        spellrange = mq.TLO.FindItem(spell).Spell.MyRange()
        spelltartype = mq.TLO.FindItem(spell).Spell.TargetType()
    end
    local spellid = mq.TLO.Spell(spell).ID() or (gem == 'item' and mq.TLO.FindItem(spell).Spell.ID())
    for bot in botstr:gmatch("%S+") do
        table.insert(bots, bot)
    end
    -- Shuffle the table so we're not casting in the same order, prevents multiple classes hitting the same targets
    for i = #bots, 2, -1 do
        local j = math.random(1, i)
        bots[i], bots[j] = bots[j], bots[i]
    end
    if debug then print('hpeval ' .. index, entry.spell) end
    if AHThreshold[index]['corpse'] then
        local corpsecount = mq.TLO.SpawnCount('pccorpse radius ' .. myconfig.settings['acleash'])()
        if corpsecount and corpsecount > 0 then
            local corpsedist = myconfig.settings['acleash']
            local rezid = 0
            local matches = 0
            if not AHThreshold[index]['cbt'] and runconfig['MobList'][1] then return false end
            for i = 1, corpsecount do
                if AHThreshold[index]['all'] then
                    for k = 1, corpsecount do
                        local nearcorpse = mq.TLO.NearestSpawn(i, 'pccorpse radius ' .. corpsedist).CleanName()
                        if nearcorpse then
                            nearcorpse = string.gsub(nearcorpse, "'s corpse", "")
                        end
                        if debug then print('corpse found ' ..
                            nearcorpse .. ' netbots char is ' .. mq.TLO.NetBots(bots[k]).Name()) end
                        rezid = mq.TLO.NearestSpawn(i, 'pccorpse radius ' .. corpsedist).ID()
                        if myconfig.heal['rezoffset'] > 0 and matches < myconfig.heal['rezoffset'] and corpsecount > myconfig.heal['rezoffset'] then
                            matches = matches + 1
                        else
                            return rezid, 'corpse'
                        end
                    end
                end
                if AHThreshold[index]['bots'] and botcount then
                    for k = 1, botcount do
                        local nearcorpse = mq.TLO.NearestSpawn(i, 'pccorpse radius ' .. corpsedist).CleanName()
                        if nearcorpse then
                            nearcorpse = string.gsub(nearcorpse, "'s corpse", "")
                        end
                        if debug then print('corpse found ' ..
                            nearcorpse .. ' netbots char is ' .. mq.TLO.NetBots(bots[k]).Name()) end
                        if mq.TLO.NetBots(bots[k]).Name() == nearcorpse then
                            rezid = mq.TLO.NearestSpawn(i, 'pccorpse radius ' .. corpsedist).ID()
                            if myconfig.heal['rezoffset'] > 0 and matches < myconfig.heal['rezoffset'] and corpsecount > myconfig.heal['rezoffset'] then
                                matches = matches + 1
                            else
                                return rezid, 'corpse'
                            end
                        end
                    end
                end
                if AHThreshold[index]['raid'] and mq.TLO.Raid.Members() then
                    for k = 1, mq.TLO.Raid.Members() do
                        local nearcorpse = mq.TLO.NearestSpawn(i, 'pccorpse radius ' .. corpsedist).CleanName()
                        if nearcorpse then
                            nearcorpse = string.gsub(nearcorpse, "'s corpse", "")
                        end
                        if mq.TLO.NetBots(bots[k]).Name() == nearcorpse then
                            rezid = mq.TLO.NearestSpawn(i, 'pccorpse radius ' .. corpsedist).ID()
                            if myconfig.heal['rezoffset'] > 0 and matches < myconfig.heal['rezoffset'] and corpsecount > myconfig.heal['rezoffset'] then
                                matches = matches + 1
                            else
                                return rezid, 'corpse'
                            end
                        end
                    end
                end
            end
        end
    end
    if AHThreshold[index]['self'] and mq.TLO.Me.PctHPs() and mq.TLO.Me.PctHPs() <= AHThreshold[index]['self'] then
        if mq.TLO.Spell(entry.spell).TargetType() == 'Self' then
            return 1, 'self'
        else
            return mq.TLO.Me.ID(), 'self'
        end
    end
    if AHThreshold[index]['grp'] then
        local grpmatch = 0
        for k = 0, mq.TLO.Group.Members() do
            local grpmempcthp = mq.TLO.Group.Member(k).PctHPs()
            local grpmemdist = mq.TLO.Group.Member(k).Distance()
            spellrange = mq.TLO.Spell(entry.spell).AERange()
            if gem == 'item' then
                spellrange = mq.TLO.FindItem(spell).Spell.AERange()
            end
            if mq.TLO.Group.Member(k).Present() and grpmempcthp and grpmempcthp <= AHThreshold[index]['grp'] and grpmemdist and spellrange and grpmemdist <= mq.TLO.Spell(entry.spell).AERange() then
                if mq.TLO.Group.Member(k).Type() ~= 'Corpse' then grpmatch = grpmatch + 1 end
            end
        end
        if grpmatch >= entry.tarcnt then
            if mq.TLO.Spell(entry.spell).TargetType() == 'Group v1' then
                return 1, 'grp'
            else
                return mq.TLO.Me.ID(), 'grp'
            end
        end
    end
    if AHThreshold[index]['tank'] and AHThreshold[index]['pc'] then
        local tankhp = mq.TLO.Group.Member(tank).PctHPs()
        local tankdist = mq.TLO.Spawn(tankid).Distance()
        local tanknbhp = mq.TLO.NetBots(tank).PctHPs()
        if not tanknbid then
            if tankid and mq.TLO.Group.Member(tank).Index() then
                if (mq.TLO.Spawn(tankid).Type() == 'PC' and tankhp and tankhp <= AHThreshold[index]['tank']) and (tankdist and tankdist <= spellrange) then
                    return mq.TLO.Group.Member(tank).ID(), 'tank'
                end
            end
        elseif tanknbid then
            if (mq.TLO.Spawn(tankid).Type() == 'PC' and tanknbhp and tanknbhp <= AHThreshold[index]['tank']) and (tankdist and tankdist <= spellrange) then
                return mq.TLO.Spawn('pc =' .. tank).ID(), 'tank'
            end
        end
    end
    if AHThreshold[index]['pc'] and AHThreshold[index]['group'] then
        if botcount then
            for i = 1, botcount do
                local botid = mq.TLO.Spawn('pc =' .. bots[i]).ID()
                local botclass = mq.TLO.Spawn('pc =' .. bots[i]).Class.ShortName()
                local bothp = mq.TLO.NetBots(bots[i]).PctHPs()
                local botdist = mq.TLO.Spawn('pc =' .. bots[i]).Distance()
                if botclass and AHThreshold[index][botclass:lower()] and bothp and mq.TLO.Spawn(mq.TLO.Spawn('pc =' .. bots[i]).ID()).Type() == 'PC' and bothp <= AHThreshold[index][botclass:lower()] then
                    if mq.TLO.Group.Member(bots[i]).Present() then
                        if spellrange and botdist and botdist <= spellrange then return botid, botclass:lower() end
                    end
                end
            end
        elseif mq.TLO.Group.Members() > 0 then
            for i = 1, mq.TLO.Group.Members() do
                local grpclass = mq.TLO.Group(i).Class.ShortName()
                local grpid = mq.TLO.Group(i).ID()
                local grphp = mq.TLO.Group(i).PctHPs()
                local grpdist = mq.TLO.Group(i).Distance()
                if AHThreshold[index][grpclass:lower()] and mq.TLO.Spawn(grpid).Type() == 'PC' and grphp and grphp <= AHThreshold[index][string.lower(grpclass)] then
                    if spellrange and grpdist and grpdist <= spellrange then return grpid, grpclass:lower() end
                end
            end
        end
    elseif AHThreshold[index]['pc'] and not AHThreshold[index]['group'] then
        if botcount then
            for i = 1, botcount do
                local botid = mq.TLO.Spawn('pc =' .. bots[i]).ID()
                local botclass = mq.TLO.Spawn('pc =' .. bots[i]).Class.ShortName()
                local bothp = mq.TLO.NetBots(bots[i]).PctHPs()
                local botdist = mq.TLO.Spawn(bots[i]).Distance()
                if botid and botclass and AHThreshold[index] and AHThreshold[index][botclass:lower()] and mq.TLO.Spawn(botid).Type() == 'PC' and bothp <= AHThreshold[index][botclass:lower()] then
                    if botid and botdist and spellrange and botdist <= spellrange then return botid, botclass:lower() end
                end
            end
        end
    end
    if AHThreshold[index]['mypet'] then
        local mypetid = mq.TLO.Me.Pet.ID()
        local mypetdist = mq.TLO.Me.Pet.Distance()
        local mypethp = mq.TLO.Me.Pet.PctHPs()
        if mypetid and mypetid > 0 then
            if mypethp and mypethp <= AHThreshold[index]['mypet'] then
                if mypetdist <= spellrange then return mypetid, 'mypet' end
            end
        end
    end
    if AHThreshold[index]['pet'] then
        if botcount then
            for i = 1, botcount do
                local petid = mq.TLO.Spawn('pc =' .. bots[i]).Pet.ID()
                local pethp = mq.TLO.NetBots(bots[i]).PetHP()
                local petdist = mq.TLO.Spawn(petid).Distance()
                if petid then
                    if pethp and pethp > 0 and pethp <= AHThreshold[index]['pet'] then
                        if spellrange and petdist and petdist <= spellrange then return petid, 'pet' end
                    end
                end
            end
        end
    end
    if AHThreshold[index]['xtgt'] then
        local xtslots = mq.TLO.Me.XTargetSlots() or false
        for i = 1, xtslots do
            --print(XTList[i])
            if XTList[i] then
                local xtar = mq.TLO.Me.XTarget(i)()
                if xtar then
                    local xtpchpt = mq.TLO.Me.XTarget(i).PctHPs() or 101
                    local xtrange = mq.TLO.Me.XTarget(i).Distance() or 500
                    local xtid = mq.TLO.Me.XTarget(i).ID() or 0
                    --print('xthp:',xtpchpt, ' xtrange:',xtrange, ' xtid:',xtid)
                    if xtpchpt < AHThreshold[index]['xtgt'] and xtrange <= spellrange and xtid > 0 then
                        return xtid, 'xtgt'
                    end
                end
            end
        end
    end
    --self, tank, grp, group, pc, mypet, pet
end

function trotsheal.ValidateHeal()
    local target = CurSpell.target
    local index = CurSpell.spell
    local healtar, matchtype = trotsheal.HPEval(index)
    if debug then print('validateheal') end
    if healtar and healtar > 0 then return true end
    return false
end

-- function to validate I am good to cast heal entries, and then check for valid targets
function trotsheal.HealCheck()
    -- forloop through each entry
    local EvalID = nil
    for i = 1, myconfig.heal['count'] do
        local castspell = true
        if myconfig['ah' .. i] then
            if myconfig['ah' .. i].gem == 0 or myconfig['ah' .. i].tarcnt == 0 then castspell = false end
        end
        while castspell do
            if MasterPause then break end
            mq.doevents()
            if mq.TLO.Me.State() == 'DEAD' or mq.TLO.Me.State() == 'HOVER' then
                castspell = false
            end
            if mq.TLO.Me.Invulnerable() then
                print("/echo I'm DA, waiting")
                mq.delay(1000)
            end
            if mq.TLO.Me.CastTimeLeft() > 0 then trotslib.InterruptCheck() end
            --validate spell is loaded, we have mana, spell is ready, and precondition is met
            if trotslib.SpellCheck('ah', i) then
                if trotslib.LoadSpell('ah', i) then
                    -- find valid targets and build into targets table
                    EvalID, classhit = trotsheal.HPEval(i)
                    if debug then print(EvalID, classhit) end
                    if EvalID then
                        -- cast the spell
                        if not trotslib.PreCondCheck('ah', i, EvalID) then
                            castspell = false
                            break
                        end
                        trotslib.CastSpell(i, EvalID, classhit, 'ah')
                        -- if priority spell, check to see if we need to keep casting, else move to next spell
                        if myconfig['ah' .. i]['priority'] then
                            if (trotsheal.ValidateHeal())
                            then
                                castspell = true
                            end
                        else
                            castspell = false
                            return true
                        end
                    else
                        castspell = false
                    end
                else
                    castspell = false
                end
            else
                castspell = false
            end
        end
    end
end

return trotsheal
