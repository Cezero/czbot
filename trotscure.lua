local mq = require('mq')
local trotscure = {}
function trotscure.LoadCureConfig()
    if (myconfig.cure['count'] == nil) then myconfig.cure['count'] = 2 end
    local curekey = 'acx'
    CureClass = {}
    CureType = {}
    for i = 1, myconfig.cure['count'] do
        if MasterPause then return false end
        if i <= myconfig.cure['count'] then
            CureClass[i] = {}
            CureType[i] = {}
            curekey = "ac" .. i
            if not myconfig[curekey] then myconfig[curekey] = { gem = 0, spell = 0, minmana = 0, alias = false, announce = false, curetype =
                "all", tarcnt = 0, class = 'war brd clr pal shd shm rng rog ber mnk dru bst mag nec enc wiz', priority = false, precondition = true } end
            if myconfig[curekey]['gem'] == 'script' then
                if not myconfig['script'][myconfig[curekey]['spell']] then
                    print('making script ', myconfig[curekey]['spell'])
                    myconfig['script'][myconfig[curekey]['spell']] = "test"
                end
                table.insert(runconfig['ScriptList'], myconfig[curekey]['spell'])
            end
            for word in myconfig[curekey].class:gmatch("%S+") do
                letters = word:match("(%a+)")
                CureClass[i][letters] = true
            end
            for word in myconfig[curekey].curetype:gmatch("%S+") do
                CureType[i][word] = word
            end
        end
    end
end

function trotscure.CureEval(index)
    if debug then print('cureeval') end
    local entry = myconfig['ac' .. index]
    local spell = myconfig['ac' .. index]['spell']
    local gem = myconfig['ac' .. index]['gem']
    local spellrange = mq.TLO.Spell(spell).MyRange()
    local spelltartype = mq.TLO.Spell(spell).TargetType()
    if gem == 'item' then
        spell = mq.TLO.FindItem(spell).Spell.Name()
        spellrange = mq.TLO.FindItem(spell).Spell.MyRange()
        spelltartype = mq.TLO.FindItem(spell).Spell.TargetType()
    end
    local botcount = mq.TLO.NetBots.Counts()
    local tank = myconfig.settings['TankName']
    local botstr = mq.TLO.NetBots.Client()
    local bots = {}
    local cureindex = CureClass[index]
    for bot in botstr:gmatch("%S+") do
        table.insert(bots, bot)
    end
    -- Shuffle the table so we're not casting in the same order, prevents multiple classes hitting the same targets
    for i = #bots, 2, -1 do
        local j = math.random(1, i)
        bots[i], bots[j] = bots[j], bots[i]
    end
    if cureindex and cureindex['self'] then
        for k, v in pairs(CureType[index]) do
            local curetype = mq.TLO.Me[v]
            if curetype then curetype = mq.TLO.Me[v]() end
            if
                string.lower(v) ~= 'all' and curetype and spelltartype == 'Self' then
                return 1, 'self'
            elseif
                string.lower(v) ~= 'all' and curetype then
                return mq.TLO.Me.ID(), 'self'
            end
        end
    end
    if cureindex and cureindex['tank'] then
        local tankid = mq.TLO.Spawn('pc =' .. tank).ID()
        local tankdtr = mq.TLO.NetBots(tank).Detrimentals()
        if tankid then
            for k, v in pairs(CureType[index]) do
                local curetype = mq.TLO.NetBots(tank)[v]
                if curetype then curetype = mq.TLO.NetBots(tank)[v]() end
                if string.lower(v) == "all" and tankdtr and tankdtr > 0 then return tankid, 'tank' end
                if string.lower(v) ~= 'all' and curetype and curetype > 0 then
                    if mq.TLO.Spawn(tankid).Type() == 'PC' and trotslib.DistanceCheck('ac', index, tankid) then
                        return tankid, 'tank'
                    end
                end
            end
        end
    end
    if cureindex and cureindex['group'] then
        if botcount then
            for i = 1, botcount do
                local botname = bots[i]
                local botid = mq.TLO.Spawn('pc =' .. botname).ID()
                local botclass = mq.TLO.Spawn('pc =' .. botname).Class.ShortName()
                local botdtr = mq.TLO.NetBots(botname).Detrimentals()
                if botclass then botclass = string.lower(mq.TLO.Spawn('pc =' .. botname).Class.ShortName()) end
                if cureindex[botclass] and botid then
                    if mq.TLO.Group.Member(botname).ID() then
                        for k, v in pairs(CureType[index]) do
                            local curetype = mq.TLO.NetBots(botname)[v]
                            if curetype then curetype = mq.TLO.NetBots(botname)[v]() end
                            if string.lower(v) == "all" and botdtr and botdtr > 0 and trotslib.DistanceCheck('ac', index, botid) then return
                                botid, 'group' end
                            if string.lower(v) ~= 'all' and curetype and curetype > 0 then
                                if trotslib.DistanceCheck('ac', index, botid) then return botid, 'group' end
                            end
                        end
                    end
                end
            end
        end
    end
    if botcount and cureindex then
        for i = 1, botcount do
            local botname = bots[i]
            if botname then
                local botid = mq.TLO.Spawn('pc =' .. botname).ID()
                local botclass = mq.TLO.Spawn('pc =' .. botname).Class.ShortName()
                local botdtr = mq.TLO.NetBots(botname).Detrimentals()
                if botclass then botclass = string.lower(botclass) end
                for k, v in pairs(CureType[index]) do
                    local curetype = mq.TLO.NetBots(botname)[v]
                    if curetype then curetype = mq.TLO.NetBots(botname)[v]() end
                    if botclass and v and type(v) == "string" then
                        if botid and string.lower(v) == "all" and botdtr and botdtr > 0 then return botid,
                                botclass:lower() end
                        if string.lower(v) ~= 'all' and curetype and curetype > 0 then
                            if mq.TLO.Spawn('pc =' .. botname).ID() and CureClass[index][botclass] and botid then
                                if trotslib.DistanceCheck('ac', index, botid) then return botid, botclass:lower() end
                            end
                        end
                    end
                end
            end
        end
    end
end

function trotscure.CureCheck()
    if debug then print('curecheck') end
    local EvalID = nil
    if SpellTimer > mq.gettime() then return false end
    local castcure = true
    for i = 1, myconfig.cure['count'] do
        castcure = true
        local classhit = nil
        while castcure do
            local curegem = myconfig['ac' .. i]['gem']
            if curegem then
                if (((type(myconfig['ac' .. i]['gem']) == 'number' and myconfig['ac' .. i]['gem'] ~= 0)) or type(myconfig['ac' .. i]['gem']) == 'string') and myconfig['ac' .. i].tarcnt > 0 then
                    mq.doevents()
                    if mq.TLO.Me.State() == 'DEAD' or mq.TLO.Me.State() == 'HOVER' then break end
                    if mq.TLO.Me.Invulnerable() then
                        print("/echo I'm DA, waiting")
                        mq.delay(1000)
                        break
                    end
                    if mq.TLO.Me.CastTimeLeft() > 0 and mq.TLO.Me.Class.ShortName() ~= 'BRD' then trotslib
                            .InterruptCheck() end
                    if trotslib.SpellCheck('ac', i) then
                        EvalID, classhit = trotscure.CureEval(i)
                        if debug then print(EvalID, classhit, i) end
                        if EvalID and classhit then
                            if trotslib.PreCondCheck('ac', i, EvalID) then
                                if trotslib.LoadSpell('ac', i) then
                                    trotslib.CastSpell(i, EvalID, classhit, 'ac')
                                end
                            end
                        end
                    end
                end
            end
            if trotscure.CureEval(i) and myconfig.cure.prioritycure then
                castcure = true
            else
                castcure = false
            end
        end
    end
end

return trotscure
