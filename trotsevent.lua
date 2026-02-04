local mq = require('mq')
local trotsevent = {}
function trotsevent.LoadEventConfig()
    if (myconfig.event['count'] == nil) then myconfig.event['count'] = 2 end
    EventClass = {}
    local eventkey = 'aex'
    for i=1, myconfig.event['count'] do
        if MasterPause then return false end
        if i <= myconfig.event['count'] then
            EventClass[i] = {}
            eventkey = "ae"..i
            if not myconfig[eventkey] then myconfig[eventkey] = {gem = 0, spell = 0, minmana = 0, maxmana = 100, minhp = 0, maxhp = 100, minendur = 0, maxendur = 100, alias = false, announce = false, tarcnt = 0, class = 'war brd clr pal shd shm rng rog ber mnk dru bst mag nec enc wiz' , precondition = true}  end
            if myconfig[eventkey]['gem'] == 'script' then
                if not myconfig['script'][myconfig[eventkey]['spell']] then 
                    print('making script ',myconfig[eventkey]['spell'])
                    myconfig['script'][myconfig[eventkey]['spell']] = "test" end
                table.insert(runconfig['ScriptList'], myconfig[eventkey]['spell'])
            end
            for word in myconfig[eventkey].class:gmatch("%S+") do
                letters = word:match("(%a+)")
                EventClass[i][letters] =  true
            end
        end
    end
end

function trotsevent.EventEval(index)
    local entry = myconfig['ae'..index]
    local tank = myconfig.settings['TankName']
    local botcount = mq.TLO.NetBots.Counts()
    local botstr = mq.TLO.NetBots.Client()
    local bots = {}
    for bot in botstr:gmatch("%S+") do
        table.insert(bots, bot)
    end
    if debug then print('eventeval '..entry.spell) end
    if EventClass[index] and EventClass[index]['self'] and mq.TLO.Me.PctHPs() and mq.TLO.Me.PctHPs() < entry.maxhp and mq.TLO.Me.PctHPs() > entry.minhp then 
        if mq.TLO.Me.PctEndurance() and mq.TLO.Me.PctEndurance() < entry.maxendur and mq.TLO.Me.PctEndurance() > entry.minendur then
            if mq.TLO.Me.PctMana() and mq.TLO.Me.PctMana() < entry.maxmana and mq.TLO.Me.PctMana() > entry.minmana then
                if mq.TLO.Spell(entry.spell).TargetType() == 'Self' then return 1, 'self'
                else return mq.TLO.Me.ID(), 'self' end
            end
        end
    end
    if EventClass[index]['tank'] then 
        local tankid = mq.TLO.Spawn('pc ='..tank).ID()
        local tankhp = mq.TLO.NetBots(tank).PctHPs()
        local tankmana = mq.TLO.NetBots(tank).PctMana()
        local tankend = mq.TLO.NetBots(tank).PctEndurance()
        if not tankid then
            if tankid and mq.TLO.Group.Member(tank).Index() then 
                if (mq.TLO.Spawn('pc ='..tank).Type() == 'PC' and mq.TLO.Group.Member(tank).PctHPs() and mq.TLO.Group.Member(tank).PctHPs() < entry.maxhp) and trotslib.DistanceCheck('ae', index, mq.TLO.Spawn('pc ='..tank).ID()) then
                    if mq.TLO.Group(tank).PctEndurance() and mq.TLO.Group(tank).PctEndurance() < entry.maxendur and mq.TLO.Group(tank).PctEndurance() > entry.minendur then
                        if mq.TLO.Group(tank).PctMana() and mq.TLO.Group(tank).PctMana() < entry.maxmana and mq.TLO.Group(tank).PctMana() > entry.minmana then
                            return mq.TLO.Group.Member(tank).ID(), 'tank'
                        end
                    end
                end
            end
        elseif tankid then
            if (mq.TLO.Spawn(tankid).Type() == 'PC' and tankhp and tankhp <= EventClass[index]['tank']) and trotslib.DistanceCheck('ae', index, tankid) then
                if tankend and tankend < entry.maxendur and tankend > entry.minendur then
                    if tankmana and tankmana < entry.maxmana and tankmana > entry.minmana then
                        return tankid, 'tank'
                    end
                end
            end
        end
    end
    if EventClass[index]['group'] then
        if botcount then
            for i=1, botcount do
                local botname = bots[i]
                local botid = mq.TLO.Spawn('pc ='..botname).ID()
                local botclass = mq.TLO.Spawn(botid).Class.ShortName()
                local bothp = mq.TLO.NetBots(botname).PctHPs()
                local botend = mq.TLO.NetBots(botname).PctEndurance()
                local botmana = mq.TLO.NetBots(botname).PctMana()
                if botclass then botclass = string.lower(mq.TLO.Spawn('pc ='..botname).Class.ShortName()) end
                if EventClass[index][botclass] and botid and bothp <= EventClass[index][botclass] then
                    if mq.TLO.Group.Member(botname).ID() then
                        if botend and botend < entry.maxendur and botend > entry.minendur then
                            if botmana and botmana < entry.maxmana and botmana > entry.minmana then
                                if trotslib.DistanceCheck('ae', index, botid) then  return botid, botclass end
                            end
                        end
                    end
                end
            end
        elseif mq.TLO.Group.Members() > 0 then
            for i=1, mq.TLO.Group.Members() do
                if EventClass[index][string.lower(mq.TLO.Group(i).Class.ShortName())] and mq.TLO.Spawn(mq.TLO.Group(i).ID()).Type() == 'PC' and mq.TLO.Group(i).PctHPs() <= EventClass[index][string.lower(mq.TLO.Group(i).Class.ShortName())] then
                    if mq.TLO.Group(i).PctEndurance() and mq.TLO.Group(i).PctEndurance() < entry.maxendur and mq.TLO.Group(i).PctEndurance() > entry.minendur then
                        if mq.TLO.Group(i).PctMana() and mq.TLO.Group(i).PctMana() < entry.maxmana and mq.TLO.Group(i).PctMana() > entry.minmana then
                            if trotslib.DistanceCheck('ae', index, mq.TLO.Group(i).ID()) then return mq.TLO.Group(i).ID(), string.lower(mq.TLO.Group(i).Class.ShortName()) end
                        end
                    end
                end
            end
        end
    elseif EventClass[index]['pc'] then
        if botcount then
            for i=1, botcount do
                local botname = bots[i]
                local botid = mq.TLO.Spawn('pc ='..botname).ID()
                local botclass = mq.TLO.Spawn(botid).Class.ShortName()
                local bothp = mq.TLO.NetBots(botname).PctHPs()
                local botend = mq.TLO.NetBots(botname).PctEndurance()
                local botmana = mq.TLO.NetBots(botname).PctMana()
                if botid and EventClass[index][botclass] and botid and bothp <= EventClass[index][botclass] then
                    if botend and botend < entry.maxendur and botend > entry.minendur then
                        if botmana and botmana < entry.maxmana and botmana > entry.minmana then
                            if trotslib.DistanceCheck('ae', index, botid) then  return botid, botclass end
                        end
                    end
                end
            end
        end
    end
end

function trotsevent.EventCheck()
    if debug then print('eventcheck') end
    local EvalID = nil
    local castspell = true
    local mobcountstart = nil
    local doeventeval = false
    local cbtspell = false
    local idlespell  = false
    if SpellTimer > mq.gettime() then return false end
    mobcountstart = runconfig['MobCount']
    for i=1, myconfig.event['count'] do
        castspell = true
        doeventeval = false
        if ((type(myconfig['ae'..i]['gem']) == 'number' and myconfig['ae'..i]['gem'] ~= 0) or type(myconfig['ae'..i]['gem']) == 'string') and myconfig['ae'..i].tarcnt > 0 then
            if mobcountstart < runconfig['MobCount'] then print('add detected, starting debuff from the top')i=i break end
            mq.doevents()
            cbtspell = EventClass[i] and EventClass[i]['cbt'] or false
            idlespell = EventClass[i] and EventClass[i]['idle'] or false
            if mq.TLO.Me.State() == 'DEAD' or mq.TLO.Me.State() == 'HOVER' then break end
            if mq.TLO.Me.Invulnerable() then print("/echo I'm DA, waiting") mq.delay(1000) break end
            if mq.TLO.Me.CastTimeLeft() > 0  and mq.TLO.Me.Class.ShortName() ~= 'BRD' then trotslib.InterruptCheck() end
            if trotslib.SpellCheck('ae', i) and ((not runconfig['MobList'][1] and (not cbtspell or idlespell)) or (runconfig['MobList'][1] and cbtspell)) then
                doeventeval = true
            end
            if doeventeval then
                EvalID, classhit = trotsevent.EventEval(i)
                if debug then print('eventeval result :',EvalID,classhit, i) end
                if EvalID then
                    if trotslib.PreCondCheck('ae', i, EvalID) then
                        if trotslib.LoadSpell('ae', i) then 
                            trotslib.CastSpell(i, EvalID, classhit, 'ae') 
                            return true
                        end
                    end
                end
            end
        end
    end
end
return trotsevent