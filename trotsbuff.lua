local mq = require('mq')

local trotsbuff = {}

function trotsbuff.LoadBuffConfig()
    if (myconfig.buff['count'] == nil) then myconfig.buff['count'] = 2 end
    local buffkey = 'abx'
    BuffClass = {}
    for i = 1, myconfig.buff['count'] do
        if i <= myconfig.buff['count'] then
            BuffClass[i] = {}
            buffkey = "ab" .. i
            if not myconfig[buffkey] then myconfig[buffkey] = { gem = 0, spell = 0, minmana = 0, alias = false, announce = false, tarcnt = 0, class =
                'war brd clr pal shd shm rng rog ber mnk dru bst mag nec enc wiz', spellicon = 0, precondition = true } end
            if myconfig[buffkey]['gem'] == 'script' then
                if not myconfig['script'][myconfig[buffkey]['spell']] then
                    print('making script ', myconfig[buffkey]['spell'])
                    myconfig['script'][myconfig[buffkey]['spell']] = "test"
                end
                table.insert(runconfig['ScriptList'], myconfig[buffkey]['spell'])
            end
            for word in myconfig[buffkey].class:gmatch("%S+") do
                letters = word:match("(%a+)")
                BuffClass[i][letters] = true
            end
            for k, v in pairs(BuffClass[i]) do
                --print('for spell ',i,' class ',k,' buff them ',BuffClass[i][k])
            end
        end
    end
end

function IconCheck(index, EvalID)
    local spellicon = myconfig['ab' .. index]['spellicon']
    local spellname = mq.TLO.Spell(spellicon).Name()
    local botname = mq.TLO.Spawn(EvalID).Name()
    local netbuffs = mq.TLO.NetBots(botname).Buff() or 'none'
    local songid = nil
    local spellid = nil
    local shortbuff = mq.TLO.NetBots(botname).ShortBuff()
    if shortbuff then
        songid = string.find(shortbuff, spellicon)
    end
    if mq.TLO.NetBots(botname).Buff() then
        spellid = string.find(netbuffs, spellicon)
    end
    if spellicon == 0 then return true end
    if debug then print('iconcheck', botname, spellname, spellid, songid, index, EvalID) end
    if songid or spellid then
        return false
    else
        return true
    end
end

function trotsbuff.BuffEval(index)
    local botstr = mq.TLO.NetBots.Client()
    local bots = {}
    for bot in botstr:gmatch("%S+") do
        table.insert(bots, bot)
    end
    -- Shuffle the table so we're not casting in the same order, prevents multiple classes hitting the same targets
    for i = #bots, 2, -1 do
        local j = math.random(1, i)
        bots[i], bots[j] = bots[j], bots[i]
    end
    local gem = myconfig['ab' .. index]['gem']
    local spell = myconfig['ab' .. index]['spell']
    local spellrange = mq.TLO.Spell(spell).MyRange()
    local spelltartype = mq.TLO.Spell(spell).TargetType()
    if gem == 'item' then
        spell = mq.TLO.FindItem(spell).Spell.Name()
        spellrange = mq.TLO.FindItem(spell).Spell.MyRange()
        spelltartype = mq.TLO.FindItem(spell).Spell.TargetType()
    end
    local spellid = mq.TLO.Spell(spell).ID() or (gem == 'item' and mq.TLO.FindItem(spell).Spell.ID())
    --temp fix for heroic bond (id is wrong in mqnext spelldata)
    if spellid == 1536 then spellid = 1538 end
    local spellicon = myconfig['ab' .. index]['spellicon']
    local tank = myconfig.settings['TankName']
    local tankid = mq.TLO.Spawn('pc =' .. tank).ID()
    local myid = mq.TLO.Me.ID()
    local tanktar = mq.TLO.NetBots(tank).TargetID()
    local mypetid = mq.TLO.Me.Pet.ID()
    local myclass = mq.TLO.Me.Class.ShortName()
    local range = (mq.TLO.Spell(spell).MyRange() and mq.TLO.Spell(spell).MyRange() > 0) and mq.TLO.Spell(spell).MyRange() or
    mq.TLO.Spell(spell).AERange() or (gem == 'item' and mq.TLO.FindItem(spell).Spell.ID())
    local botcount = mq.TLO.NetBots.Counts()
    if not spellid then return end
    if debug then print('buffeval', spell) end
    if not BuffClass or not BuffClass[index] then return false end
    if myclass ~= 'BRD' then
        if BuffClass[index]['petspell'] then
            if IconCheck(index, myid) then
                if (mypetid == 0) then
                    return myid, 'petspell'
                end
            end
        end
        if BuffClass[index]['self'] then
            local buffdur = mq.TLO.Me.Buff(spell).Duration()
            local spelldur = mq.TLO.Spell(spell).MyDuration.TotalSeconds()
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
        if BuffClass[index]['name'] then
            for name, classlist in pairs(BuffClass[index]) do
                if mq.TLO.NetBots(name)() then
                    local buffstr = mq.TLO.NetBots(name).Buff()
                    local buffs = {}
                    if buffstr then
                        for buff in buffstr:gmatch("%S+") do
                            buffs[buff] = true
                        end
                    end
                    local botclass = mq.TLO.Spawn('pc =' .. name).Class.ShortName()
                    local botid = mq.TLO.Spawn('pc =' .. name).ID()
                    local spawnid = mq.TLO.Spawn(botid).ID()
                    local query = "Spell[" .. spellid .. "].Stacks"
                    --Making Dynamic global variable to hold dannet observe data so we don't query dnet directly all the time (caused varialble locks)
                    local resultname = name .. "-" .. spellid
                    if IconCheck(index, botid) and botid > 0 then
                        --print(query)
                        --mq.cmdf("/dquery %s -q %s", botname, query)
                        local botbuff = nil
                        --print('spell check',bots[i], spell, spellid)
                        botbuff = buffs[tostring(spellid)]
                        --mq.delay(2000, function () return mq.TLO.DanNet(botname).Q(query).Received() end)
                        --local botbuffdur = tonumber(mq.TLO.DanNet(botname).Q(query)())
                        --print(query, ' ',botname, ' ', mq.TLO.DanNet(botname).Q(query)())
                        local botbuffstack = mq.TLO.NetBots(name).Stacks(spellid)()
                        local botfreebuffslots = mq.TLO.NetBots(name).FreeBuffSlots()
                        --if not mq.TLO.DanNet(name).ObserveSet(query)()or not _G[resultname] then
                        --trotslib.MakeObs(resultname, name, query)
                        --print(_G[resultname],resultname)
                        --end
                        --if _G[resultname] ~= 'FALSE' then botbuffstack = true end
                        local botdist = mq.TLO.Spawn(spawnid).Distance()
                        --print('distance and stacking checks ', botdist, ' ', botbuffstack, ' ', range, ' ', IconCheck(index, spawnid))
                        --print('spawn and botid ', spawnid, ' ', botid, ' ', botbuff)
                        --print(spawnid , botbuffstack , IconCheck(index, spawnid) ,  botbuff , (botbuffdur))
                        if spawnid and botbuffstack and botfreebuffslots and botfreebuffslots > 0 and IconCheck(index, spawnid) and not botbuff then
                            if (range and botdist and botdist <= range) then
                                return botid, botclass:lower()
                            end
                        end
                    end
                end
            end
        end
        if string.find(myconfig['ab' .. index]['class'], 'tank') then
            if IconCheck(index, tankid) then
                local buffstr = mq.TLO.NetBots(tank).Buff()
                local buffs = {}
                if buffstr then
                    for buff in buffstr:gmatch("%S+") do
                        buffs[buff] = true
                    end
                end
                local tankbuff = buffs[tostring(spellid)]
                local nbtank = mq.TLO.NetBots(tank).ID()
                --local tankbuffdur = mq.TLO.NetBots(tank).Duration(spell)()
                local tankbuffstack = mq.TLO.NetBots(tank).Stacks(spellid)()
                local tankfreebuffslots = mq.TLO.NetBots(tank).FreeBuffSlots()
                local tankdist = mq.TLO.Spawn(tank).Distance()
                if ((nbtank) and not tankbuff) then
                    if tankid and tankbuffstack and tankfreebuffslots and tankfreebuffslots > 0 and (tankdist and tankdist <= range) then
                        return tankid, 'tank'
                    end
                end
            end
        end
        for i = 1, botcount do
            if bots[i] then
                local botname = mq.TLO.Spawn('pc =' .. bots[i]).Name()
                if botname then
                    local buffstr = mq.TLO.NetBots(bots[i]).Buff()
                    local buffs = {}
                    if buffstr then
                        for buff in buffstr:gmatch("%S+") do
                            buffs[buff] = true
                        end
                    end
                    local botclass = mq.TLO.Spawn('pc =' .. bots[i]).Class.ShortName()
                    local botid = mq.TLO.Spawn('pc =' .. bots[i]).ID()
                    local spawnid = mq.TLO.Spawn(botid).ID()
                    local query = "Spell[" .. spellid .. "].Stacks"
                    --Making Dynamic global variable to hold dannet observe data so we don't query dnet directly all the time (caused varialble locks)
                    local resultname = botname .. "-" .. spellid
                    if IconCheck(index, botid) and botid > 0 and botclass and BuffClass[index][botclass:lower()] then
                        --print(query)
                        --mq.cmdf("/dquery %s -q %s", botname, query)
                        local botbuff = nil
                        --print('spell check',bots[i], spell, spellid)
                        botbuff = buffs[tostring(spellid)]
                        local botbuffstack = mq.TLO.NetBots(botname).Stacks(spellid)()
                        local botfreebuffslots = mq.TLO.NetBots(botname).FreeBuffSlots()
                        local botdist = mq.TLO.Spawn(spawnid).Distance()
                        --print('distance and stacking checks ', botdist, ' ', botbuffstack, ' ', range, ' ', IconCheck(index, spawnid))
                        --print('spawn and botid ', spawnid, ' ', botid, ' ', botbuff)
                        --print(spawnid , botbuffstack , IconCheck(index, spawnid) ,  botbuff , (botbuffdur))
                        if spawnid and botbuffstack and botfreebuffslots and botfreebuffslots > 0 and IconCheck(index, spawnid) and not botbuff then
                            if (range and botdist and botdist <= range) then
                                return botid, botclass:lower()
                            end
                        end
                    end
                end
            end
        end
        if BuffClass[index]['mypet'] then
            local petbuff = mq.TLO.Me.Pet.Buff(spell)()
            local petrange = mq.TLO.Me.Pet.Distance()
            local petstacks = mq.TLO.NetBots(mq.TLO.Me.Name()).StacksPet(spellid)()
            if mypetid > 0 and petstacks and not petbuff and petrange and range >= petrange then
                return mypetid, 'mypet'
            end
        end
        if BuffClass[index]['pet'] then
            for i = 1, botcount do
                if bots[i] then
                    local botpet = mq.TLO.Spawn('pc =' .. bots[i]).Pet.ID()
                    local petrange = mq.TLO.Spawn(botpet).Distance()
                    local petbuffstr = mq.TLO.NetBots(bots[i]).PetBuff()
                    local buffs = {}
                    if petbuffstr then
                        for buff in petbuffstr:gmatch("%S+") do
                            buffs[buff] = true
                        end
                    end
                    local botid = mq.TLO.Spawn('pc =' .. bots[i]).ID()
                    local botname = mq.TLO.Spawn('pc =' .. bots[i]).Name()
                    local spawnid = mq.TLO.Spawn(botid).ID()
                    local query = '"Pet.BuffDuration[' .. spell .. ']"'
                    local petbuff = buffs[spellid]
                    local petstacks = mq.TLO.NetBots(bots[i]).StacksPet(spellid)()
                    if spawnid and spawnid > 0 and botpet and botpet > 0 and petstacks and IconCheck(index, spawnid) and not petbuff and range >= petrange then
                        return botpet, 'pet'
                    end
                end
            end
        end
    elseif myclass == 'BRD' then
        if BuffClass[index]['self'] then
            --print(mq.TLO.Me.Song(spell).Duration(),' ',mq.TLO.Me.Song(spell)(), spell )
            if IconCheck(index, myid) then
                local mysong = mq.TLO.Me.Song(spell)()
                if mq.TLO.Me.Song(spell)() then
                    mysong = mq.TLO.Me.Song(spell)()
                elseif mq.TLO.Me.Buff(spell)() then
                    mysong = mq.TLO.Me.Buff(spell)()
                end
                local mysongdur = false
                if mq.TLO.Me.Song(spell).Duration() then
                    mysongdur = mq.TLO.Me.Song(spell).Duration()
                elseif mq.TLO.Me.Buff(spell).Duration() then
                    mysongdur = mq.TLO.Me.Buff(spell).Duration()
                end
                local songtartype = mq.TLO.Spell(spell).TargetType()
                local songtype = mq.TLO.Spell(spell).SpellType()
                if (not mysong) or (mysongdur and mysongdur < 6100) then
                    if songtartype and (songtartype == 'Group v1' or songtartype == 'Group v2' or songtartype == 'Self' or songtartype == 'AE PC v2') then
                        return 1, 'self'
                    elseif songtype and songtype == 'Detrimental' then
                        mysongdur = mq.TLO.Target.MyBuff(spell).Duration()
                        mysong = mq.TLO.Target.MyBuff(spell)()
                        if tanktar and tanktar > 0 then
                            if (not mysong) or (mysongdur and mysongdur < 6100) then
                                return tanktar, 'self'
                            end
                        else
                            return false
                        end
                    else
                        return myid, 'self'
                    end
                end
            end
        end
    end
end

function trotsbuff.BuffCheck()
    if debug then print('buffcheck') end
    local EvalID    = nil
    local cbtspell  = false
    local idlespell = false
    local classhit  = nil
    --if SpellTimer > mq.gettime() then return false end
    for i = 1, myconfig.buff['count'] do
        EvalID = nil
        classhit = nil
        if MasterPause then return false end
        --if myconfig.settings['dodebuff'] and runconfig['MobList'][1] then trotsdebuff.DebuffCheck() end
        if (((type(myconfig['ab' .. i]['gem']) == 'number' and myconfig['ab' .. i]['gem'] ~= 0)) or type(myconfig['ab' .. i]['gem']) == 'string') and myconfig['ab' .. i].tarcnt > 0 then
            mq.doevents()
            cbtspell = BuffClass[i] and BuffClass[i]['cbt'] or false
            idlespell = BuffClass[i] and BuffClass[i]['idle'] or false
            if mq.TLO.Me.State() == 'DEAD' or mq.TLO.Me.State() == 'HOVER' then break end
            if mq.TLO.Me.Invulnerable() then
                print("/echo I'm DA, waiting")
                mq.delay(1000)
                break
            end
            if mq.TLO.Me.CastTimeLeft() > 0 and mq.TLO.Me.Class.ShortName() ~= 'BRD' then trotslib.InterruptCheck() end
            if trotslib.SpellCheck('ab', i) and ((not runconfig['MobList'][1] and (not cbtspell or idlespell)) or (runconfig['MobList'][1] and cbtspell)) then
                if trotsbuff.BuffEval(i) then
                    if trotslib.LoadSpell('ab', i) then EvalID, classhit = trotsbuff.BuffEval(i) end
                end
                if debug then print(EvalID, classhit, i) end
                if EvalID and classhit then
                    if trotslib.PreCondCheck('ab', i, EvalID) then
                        if trotslib.LoadSpell('ab', i) then trotslib.CastSpell(i, EvalID, classhit, 'ab') end
                        return true
                    end
                end
            end
        end
    end
end

return trotsbuff
