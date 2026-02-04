local mq = require('mq')
local trotsdebuff = {}

function trotsdebuff.LoadDebuffConfig()
    if (myconfig.debuff['count'] == nil) then myconfig.debuff['count'] = 2 end
    local debuffkey = 'adx'
    DebuffList = {}
    recastcntr = {}
    DebuffDlyLst = {}
    for i=1, myconfig.debuff['count'] do
        if i <= myconfig.debuff['count'] then
            debuffkey = "ad"..i
            if not myconfig[debuffkey] then myconfig[debuffkey] = {gem = 0, spell = 0, minmana = 0, alias = false, announce = false, tarcnt = 0, tartype = 1 , beghp = 99 , endhp = 0, recast = 0 , delay=0,  precondition = true}  end
            if not myconfig[debuffkey].delay then myconfig[debuffkey].delay = 0 end
            if myconfig[debuffkey]['gem'] == 'script' then
                if not myconfig['script'][myconfig[debuffkey]['spell']] then 
                    print('making script ',myconfig[debuffkey]['spell'])
                    myconfig['script'][myconfig[debuffkey]['spell']] = "test" end
                table.insert(runconfig['ScriptList'], myconfig[debuffkey]['spell'])
            end
        end
    end
end

function trotsdebuff.ADSpawnCheck()
    local SpawnList = {}
    local prevMobList = {}
    local elapsedtime = mq.gettime()
    local  needtoyell = false
    local noncombatzones = {'GuildHall','GuildLobby','PoKnowledge','Nexus','Bazaar','AbysmalSea','potranquility'}

    if debug then 
        print('spawncheck') 
    end
    if runconfig['acmatarget'] then
        if not (mq.TLO.Spawn(runconfig['acmatarget']).ID()) or mq.TLO.Spawn(runconfig['acmatarget']).Type() == 'Corpse' then
            runconfig['acmatarget'] = nil
            if debug then print('clearing acmatarget') end
        end
    end

    if trotslib.isInList(mq.TLO.Zone.ShortName(), noncombatzones) then
        return false
    end
    local function BuildMobList(spawn)
        local distance2D = spawn.Distance() or 5000
        return distance2D <= myconfig.settings['acleash']
    end

    local function FilterMobList(spawnlist)
        for i, spawn in ipairs(spawnlist) do
            local distance2D = spawn.Distance() or 5000
            local distanceZ = spawn.DistanceZ() or 5000
            --local spawntype = spawn.Type()
            local spawnname = spawn.CleanName() or 'none'
            if runconfig['campstatus'] then
                local spawnx = spawn.X()
                local spawny = spawn.Y()
                local spawnz = spawn.Z()
                distance2D = trotslib.calcDist2D(spawnx, spawny, runconfig['makecampx'], runconfig['makecampy'])
                if spawnz then distanceZ = math.abs(spawnz - runconfig['makecampz']) end
            end
            if FTECount then
                --if FTEList[spawn.ID()] then print(FTEList[spawn.ID()],' ',spawn.ID(),' ',FTEList[spawn.ID()].timer) end
                if spawn.ID() and FTEList[spawn.ID()] and FTEList[spawn.ID()].timer > mq.gettime() then 
                    --print(FTEList[spawn.ID()],spawn.ID() )
                    goto ftecontinue 

                end
            end
            if (spawnname and distance2D and distanceZ and distance2D <= myconfig.settings['acleash'] and distanceZ <= myconfig.settings['zradius'] and not string.find(runconfig['ExcludeList'], spawnname)) then
                if myconfig.settings['TargetFilter'] == 2 then
                    if not string.find('pc,banner,campfire,mercenary,mount,aura,corpse',string.lower(spawn.Type())) then
                        if DoYell and not prevMobList[spawn.ID()] then needtoyell = true end
                        table.insert(runconfig['MobList'], spawn)
                    end
                end
                if myconfig.settings['TargetFilter'] == 1 then
                    if (spawn.Type() == 'NPC' or (spawn.Type() == 'Pet' and spawn.Master.Type() ~= 'PC')) and spawn.LineOfSight() then
                        if DoYell and not prevMobList[spawn.ID()] then needtoyell = true end
                        table.insert(runconfig['MobList'], spawn)
                    end
                end
                if myconfig.settings['TargetFilter'] == 0 then
                    if (spawn.Type() == 'NPC' or (spawn.Type() == 'Pet' and spawn.Master.Type() ~= 'PC')) and spawn.Aggressive() and spawn.LineOfSight() then
                        if DoYell and not prevMobList[spawn.ID()] then needtoyell = true end
                        table.insert(runconfig['MobList'], spawn)
                    end
                end
            end
            ::ftecontinue::
        end
    end
    -- Get filtered list using widest common value (acleash) for all TargetFilters 
    SpawnList = mq.getFilteredSpawns(BuildMobList)
    -- Create keylist of previous moblist for DoYell comparison
    if DoYell then
        for i, v in ipairs(runconfig['MobList']) do
            prevMobList[v.ID()] = v.ID()
        end
    end
    -- Sanitize current MobList (so we rebuild with fresh data)
    runconfig['MobList'] = {}
    -- Filter MobList down to valid targets only
    FilterMobList(SpawnList)
    if needtoyell then trotslib.DoYell() end
    if debug then 
        elapsedtime = (mq.gettime() - elapsedtime)/1000
        print('spawncheck done duration:', elapsedtime) 
    end

    -- Sort MobList by ID so we reliably know the order (mostly for offtank)
    table.sort(runconfig['MobList'], function(a, b)
        return a.ID() < b.ID()
    end)
    local mobcount = 0
    local killtarpresent = false
    if mq.TLO.Spawn(KillTarget).Type == 'Corpse' or not mq.TLO.Spawn(KillTarget).ID() then KillTarget = nil end
        for k, v in ipairs(runconfig['MobList']) do
            --if debug then print('name:'..v.Name()..' id:'..v.ID()) end
            mobcount = mobcount + 1
            if v.ID == KillTarget then killtarpresent = true end
        end
        if not killtarpresent and KillTarget then table.insert(runconfig['MobList'], mq.TLO.Spawn(KillTarget)) end
    runconfig['MobCount'] = mobcount
end

function trotsdebuff.DebuffListUpdate(EvalID, spell, duration)
    local spellid = mq.TLO.Spell(spell).ID() or mq.TLO.FindItem(spell).Spell.ID()
    local spelldur = tonumber(mq.TLO.Spell(spellid).MyDuration()) or 0
    if debug then print('debuff list update evalid:', EvalID, ' spellid:', spellid, ' duration:', duration) end
    if spelldur < 1 or not spellid or not duration then return false end
    if not DebuffList[EvalID] then DebuffList[EvalID] = {} end
    DebuffList[EvalID][spellid] = duration
end

function trotsdebuff.DebuffEval(index)
    if debug then print('debuff eval '.. index) end
    --trotsdebuff.ADSpawnCheck()
    local entry = myconfig['ad'..index]
    if entry == nil then return false end
    local gem =  entry.gem
    local spell = myconfig['ad'..index]['spell']
    local spellrange = mq.TLO.Spell(spell).MyRange()
    local spelltartype = mq.TLO.Spell(spell).TargetType()
    if gem == 'item' then 
        spell = mq.TLO.FindItem(spell).Spell.Name() 
        spellrange = mq.TLO.FindItem(spell).Spell.MyRange()
        spelltartype = mq.TLO.FindItem(spell).Spell.TargetType()
    end
    if spellrange == 0 and spelltartype == 'PB AE' then
        spellrange = mq.TLO.Spell(spell).AERange() or mq.TLO.FindItem(spell).Spell.AERange()
    end
    local spellid = mq.TLO.Spell(spell).ID() or (gem == 'item' and mq.TLO.FindItem(spell).Spell.ID())
    local spelldur = mq.TLO.Spell(entry.spell).MyDuration() or (entry.gem == 'item' and mq.TLO.FindItem(entry.spell).Spell.MyDuration())
    local tank = myconfig.settings['TankName']
    local tankid = mq.TLO.Spawn('pc ='..tank).ID()
    local tanktar = nil
    local tanktarhp = nil
    local tanktarlvl = nil
    if mq.TLO.NetBots(tank).ID() then 
        tanktar = mq.TLO.NetBots(tank).TargetID()
        tanktarhp = mq.TLO.NetBots(tank).TargetHP()
    elseif tankid then 
        tanktar = trotsmelee.GetTankTar(tank) 
        tanktarhp = mq.TLO.Spawn(tanktar).PctHPs()
    end
    if tanktar == 0 then tanktar = nil end
    tanktarlvl = mq.TLO.Spawn(tanktar).Level()
    if type(entry.gem) == 'number' or entry.gem == 'item' or entry.gem == 'disc' or entry.gem == 'alt' then spellid = mq.TLO.Spell(entry.spell).ID() or (entry.gem == 'item' and mq.TLO.FindItem(entry.spell).Spell.ID()) end
    local spellmaxlvl = mq.TLO.Spell(spellid).MaxLevel() or (entry.gem == 'item' and mq.TLO.FindItem(entry.spell).Spell.MaxLevel())
    local myrange = nil
    if type(entry.gem) == 'number' or entry.gem == 'item' or entry.gem == 'disc' or entry.gem == 'alt' then myrange = mq.TLO.Spell(spellid).MyRange() or (entry.gem == 'item' and mq.TLO.FindItem(entry.spell).Spell.MyRange())
    elseif entry.gem == 'ability' then myrange = 20 end -- this gets set to the spawns MaxRangeTo further down
    --check for 1 time pet spells (these have no range and are tartype self, super stupid)
    if mq.TLO.Spell(spellid).Category()=='Pet' then myrange = myconfig.acleash end
    if entry.tarcnt > runconfig['MobCount'] then return false end
    if tostring(entry.tartype) and string.find(entry.tartype, 'charm') then
        if debug then print('charm check') end
        if charmspellid ~= mq.TLO.Spell(entry.spell).ID() then charmspellid = mq.TLO.Spell(entry.spell).ID() or (entry.gem == 'item' and mq.TLO.FindItem(entry.spell).Spell.ID()) end
        if charmindex ~= index then charmindex = index end
        if not mq.TLO.Me.Pet.ID() and not mq.TLO.Me.Pet.IsSummoned() and runconfig['charmid'] then runconfig['charmid'] = nil end
        if mq.TLO.Me.Pet.ID() and mq.TLO.Me.Pet.ID()>0 and not mq.TLO.Me.Pet.IsSummoned() and not runconfig['charmid'] then runconfig['charmid'] = mq.TLO.Me.Pet.ID() end
        if mq.TLO.Me.Pet.ID() and mq.TLO.Me.Pet.ID()>0 and runconfig['charmid'] and mq.TLO.Me.Pet.ID() == runconfig['charmid'] then return false end
        local charmstr = entry.tartype
        local charmsettings = {}
        function splitString(inputStr, delimiter)
            local result = {}
            for match in (inputStr .. delimiter):gmatch("(.-)" .. delimiter) do
                table.insert(result, match:match("^%s*(.-)%s*$")) -- trim whitespace
            end
            return result
        end
        local delimiter = ","
        if charmstr then charmsettings = splitString(charmstr, delimiter) end
        for _, v in ipairs(runconfig['MobList']) do
            local tarstacks = mq.TLO.Spell(entry.spell).StacksSpawn(v.ID())() or (entry.gem == 'item' and mq.TLO.FindItem(entry.spell).Spell.StacksSpawn(v.ID()))
            if spellid and v.Level() and spellmaxlvl and spellmaxlvl ~= 0 and spellmaxlvl < v.Level() then goto charmcontinue end
            if myrange and DebuffList[v.Distance()] and DebuffList[v.Distance()] > myrange then goto charmcontinue end
            if not tarstacks then goto charmcontinue end
                if tonumber(spelldur) > 0 then
                    if v.ID()~=nil  and DebuffList[v.ID()] then 
                        if DebuffList[v.ID()][spellid] then 
                            if DebuffList[v.ID()][spellid] < (mq.gettime() + 6000) then
                                for _, charmname in ipairs(charmsettings) do
                                    if debug then print(charmname, v.CleanName()) end
                                    if charmname == v.CleanName() then
                                        if mq.TLO.Me.Pet.IsSummoned() then mq.cmd('/pet leave') end
                                        return v.ID(), 'charmtar'
                                    end
                                end
                            end
                        else
                            for _, charmname in ipairs(charmsettings) do
                                local mobname = v.CleanName()
                                if mobname then mobname = string.lower(v.CleanName()) end
                                if debug then print(charmname, mobname) end
                                if charmname == mobname then
                                    if mq.TLO.Me.Pet.IsSummoned() then mq.cmd('/pet leave') end
                                    return v.ID(), 'charmtar'
                                end
                            end
                        end
                    else
                        for _, charmname in ipairs(charmsettings) do
                            if debug then print(charmname, v.CleanName()) end
                            if charmname == v.CleanName() then
                                if mq.TLO.Me.Pet.IsSummoned() then mq.cmd('/pet leave') end
                                return v.ID(), 'charmtar'
                            end
                        end
                    end
                end
            ::charmcontinue::
        end
    end
    if (entry.tartype == 1 or entry.tartype == 11 or entry.tartype == 0 or entry.tartype == 10) and tanktar and tanktarhp < entry.beghp then
        if mq.TLO.Me.Pet.ID() then
            if tanktar and tanktar > 0 and mq.TLO.Pet.Target.ID() ~= tanktar and not mq.TLO.Me.Pet.Combat() then mq.cmd('/pet attack %s', tanktar) end
        end
        for _, v in ipairs(runconfig['MobList']) do
            if v.ID() == tanktar then
                if entry.gem == 'ability' then myrange = v.MaxRangeTo() end
                if myrange and v.Distance() and v.Distance() > myrange then goto continue end
                local tanktarstack = mq.TLO.Spell(entry.spell).StacksSpawn(tanktar)() or (entry.gem == 'item' and mq.TLO.FindItem(entry.spell).Spell.StacksSpawn(tanktar)())
                if tanktarlvl and mq.TLO.Spell(spellid).Subcategory() == 'Enthrall' and spellmaxlvl and spellmaxlvl ~= 0 and spellmaxlvl < tanktarlvl then return false end
                if (type(entry.gem) == 'number' or entry.gem =='alt' or entry.gem =='disc' or entry.gem == 'item') and not tanktarstack then return false end
                if spelldur and tonumber(spelldur) > 0 then
                    if DebuffList[v.ID()] and DebuffList[v.ID()][spellid] then
                        if mq.TLO.Target.ID() == v.ID() and mq.TLO.Target.BuffsPopulated() and not mq.TLO.Target.CachedBuff(spell).ID() then
                            local recastexceeded = false
                            if recastcntr[v.ID()] and recastcntr[v.ID()][index] and recastcntr[v.ID()][index].counter <= myconfig['ad'..index].recast then
                                recastexceeded = true
                            end
                            if not recastexceeded and not IgnoreMobBuff and DebuffList[v.ID()][spellid] > mq.gettime() then 
                                DebuffList[v.ID()][spellid] = 0 
                                print('clearing tank debuffs for targetid:', v.ID(),' spellid:', spellid)
                            end
                        end
                        if DebuffList[v.ID()][spellid] > (mq.gettime() + 6000) then goto continue end
                    end
                end 
                if not myconfig.melee['offtank'] then runconfig['acmatarget'] = tanktar end
                if tanktar and tanktar > 0 and mq.TLO.Pet.Target.ID() ~= tanktar and not mq.TLO.Me.Pet.Combat() then mq.cmdf('/pet attack %s', tanktar) end
                return runconfig['acmatarget'], 'tanktar'
            end
            ::continue::
        end
    end
    if (entry.tartype == 2 or entry.tartype == 12) and runconfig['MobList'][1] then
        for _, v in ipairs(runconfig['MobList']) do
            if v.ID() ~= tanktar then
                local tarstacks = mq.TLO.Spell(entry.spell).StacksSpawn(v.ID())() or (entry.gem == 'item' and mq.TLO.FindItem(entry.spell).Spell.StacksSpawn(v.ID())())
                if entry.gem == 'ability' then myrange = v.MaxRangeTo() end
                if myrange and v.Distance() and v.Distance() > myrange then goto continue end
                if debug then print('checking tartype 12/2/10/0, spell:', entry.spell, 'tarstacks?', tarstacks, 'spawnid:', v.ID(), 'spawnlevel', v.Level(), 'spellmaxlevel', spellmaxlvl) end
                if spellid and v.Level() and spellmaxlvl and spellmaxlvl ~= 0 and spellmaxlvl < v.Level() then goto continue end
                if (type(entry.gem) == 'number' or entry.gem =='alt' or entry.gem =='disc' or entry.gem == 'item') and not tarstacks then goto continue end
                if tonumber(spelldur) > 0 then
                    if v.ID()~=nil  and DebuffList[v.ID()] then 
                        if DebuffList[v.ID()][spellid] then 
                            if mq.TLO.Target.ID() == v.ID() and mq.TLO.Target.BuffsPopulated() and not mq.TLO.Target.CachedBuff(spell).ID() then
                                local recastexceeded = false
                                if recastcntr[v.ID()] and recastcntr[v.ID()][index] and recastcntr[v.ID()][index].counter <= myconfig['ad'..index].recast then
                                    recastexceeded = true
                                end
                                if not recastexceeded and not IgnoreMobBuff and DebuffList[v.ID()][spellid] > mq.gettime() then 
                                    DebuffList[v.ID()][spellid] = 0 
                                    print('clearing notanktar debuffs for targetid:', v.ID(),' spellid:', spellid)
                                end
                            end
                            if DebuffList[v.ID()][spellid] < (mq.gettime() + 6000) then
                                return v.ID(), 'notanktar'
                            end
                        else
                            return v.ID(), 'notanktar'
                        end
                    else
                        return v.ID(), 'notanktar'
                    end
                end
            end
        ::continue::
        end
    end
    if (entry.tartype == 3 or entry.tartype == 13) and tanktar and tanktarhp < entry.beghp then
        for _, v in ipairs(runconfig['MobList']) do
            if v.ID() == tanktar and v.Named() then
                local tanktarstack = mq.TLO.Spell(entry.spell).StacksSpawn(tanktar)() or (entry.gem == 'item' and mq.TLO.FindItem(entry.spell).Spell.StacksSpawn(tanktar)())
                if entry.gem == 'ability' then myrange = v.MaxRangeTo() end
                if myrange and v.Distance() and v.Distance() > myrange then return false end
                if tanktarlvl and mq.TLO.Spell(spellid).Subcategory() == 'Enthrall' and spellmaxlvl and spellmaxlvl ~= 0 and spellmaxlvl < tanktarlvl then return false end
                if (type(entry.gem) == 'number' or entry.gem =='alt' or entry.gem =='disc' or entry.gem == 'item') and not tanktarstack then return false end
                if spelldur and tonumber(spelldur) > 0 then
                    --if DebuffList[v.ID()] then print('debuffeval', spellid ,DebuffList[v.ID()][spellid]) end
                    if DebuffList[v.ID()] and DebuffList[v.ID()][spellid] then
                        if mq.TLO.Target.ID() == v.ID() and mq.TLO.Target.BuffsPopulated() and not mq.TLO.Target.CachedBuff(spell).ID() then
                            local recastexceeded = false
                            if recastcntr[v.ID()] and recastcntr[v.ID()][index] and recastcntr[v.ID()][index].counter <= myconfig['ad'..index].recast then
                                recastexceeded = true
                            end
                            if not recastexceeded and not IgnoreMobBuff and DebuffList[v.ID()][spellid] > mq.gettime() then 
                                DebuffList[v.ID()][spellid] = 0 
                                print('clearing named debuff for targetid:', v.ID(),' spellid:', spellid)
                            end
                        end
                        if DebuffList[v.ID()][spellid] > (mq.gettime() + 6000) then goto continue end
                    end
                end
                if not myconfig.melee['offtank'] then runconfig['acmatarget'] = tanktar end
                if tanktar and tanktar > 0 and mq.TLO.Pet.Target.ID() ~= tanktar and not mq.TLO.Me.Pet.Combat() then mq.cmdf('/pet attack %s', tanktar) end
                return runconfig['acmatarget'], 'tanktar'
            end
        ::continue::
        end
    end
end

function trotsdebuff.DebuffCheck()
    if debug then print('debuffcheck') end
    local EvalID = nil
    local castspell = true
    local mobcountstart = nil
    local prevID = nil
    local tank = myconfig.settings['TankName']
    local tanktar = nil
    local tanktarhp = nil
    local tankid = mq.TLO.Spawn('pc ='..tank).ID()
    if mq.TLO.NetBots(tank).ID() then 
        tanktar = mq.TLO.NetBots(tank).TargetID()
        tanktarhp = mq.TLO.NetBots(tank).TargetHP()
    elseif tankid then 
        tanktar = trotsmelee.GetTankTar(tank) 
        tanktarhp = mq.TLO.Spawn(tanktar).PctHPs()
    end
    if SpellTimer > mq.gettime() then return false end
    mobcountstart = runconfig['MobCount']
    if tanktar and tanktar > 0 and mq.TLO.Pet.Target.ID() ~= tanktar and not mq.TLO.Me.Pet.Combat() then trotsmelee.AdvCombat() end
    for i=1, myconfig.debuff['count'] do
        if MasterPause then return false end
        castspell = true
        if recastcntr[EvalID] and recastcntr[EvalID][i] and recastcntr[EvalID][i].counter >= myconfig['ad'..i].recast then castspell = false end
        local entry = myconfig['ad'..i]
        if ((type(myconfig['ad'..i]['gem']) == 'number' and myconfig['ad'..i]['gem'] ~= 0) or type(myconfig['ad'..i]['gem']) == 'string') and myconfig['ad'..i].tarcnt > 0 then 
            while castspell == true do
                if MasterPause then return false end
                if DebuffDlyLst[i] and DebuffDlyLst[i] > mq.gettime() then break end
                if mobcountstart < runconfig['MobCount'] then print('add detected, starting debuff from the top')i=1 break end
                mq.doevents()
                if mq.TLO.Me.State() == 'DEAD' or mq.TLO.Me.State() == 'HOVER' then break end
                if mq.TLO.Me.Invulnerable() then print("/echo I'm DA, waiting") mq.delay(1000) break end
                if mq.TLO.Me.CastTimeLeft() > 0 and mq.TLO.Me.Class.ShortName() ~= 'BRD' then trotslib.InterruptCheck() end
                if trotslib.SpellCheck('ad', i) then
                    EvalID, classhit = trotsdebuff.DebuffEval(i)
                    if debug then print('debuffeval result :',EvalID,classhit, i) end
                    if EvalID then
                        if not trotslib.ImmuneCheck('ad', i, EvalID) then 
                            if debug then print('immunecheck failed for debuffeval result :',EvalID,classhit, i) end
                            castspell = false break 
                        end
                        if not trotslib.PreCondCheck('ad', i, EvalID) then 
                            if debug then print('precond check failed for debuffeval result :',EvalID,classhit, i) end
                            castspell = false break 
                        end
                        if trotslib.LoadSpell('ad', i) then 
                            trotslib.CastSpell(i, EvalID, classhit, 'ad') 
                            --if myconfig['ad'..i].recast == 0 then return true end
                        end
                        prevID = EvalID
                        EvalID = nil
                        EvalID, classhit = trotsdebuff.DebuffEval(i)
                        if EvalID ~= nil and prevID == EvalID and myconfig['ad'..i].recast > 0 and CurSpell.spell==i and CurSpell.resisted then
                            if recastcntr[EvalID] and recastcntr[EvalID][i] then 
                                recastcntr[EvalID][i].counter = recastcntr[EvalID][i].counter + 1
                                CurSpell = {}
                                print('set recast counter to:', recastcntr[EvalID][i].counter, entry.spell)
                                if recastcntr[EvalID] and recastcntr[EvalID][i] and recastcntr[EvalID][i].counter >= myconfig['ad'..i].recast then 
                                    mq.cmdf('/dgt \ayTrotsbot:\ax\ar%s\ax has resisted spell \ar%s\ax ad%s \am%s\ax times, disabling spell for this spawn', mq.TLO.Spawn(EvalID).CleanName(), myconfig['ad'..i].spell, i, myconfig['ad'..i].recast)
                                    mq.delay(1)
                                    mq.cmdf('/dgt \ayTrotsbot:\axTo re-enable run \ag/tb setvar ad%s.recast 0\ax', i)
                                    local recastduration = 600000 + mq.gettime()
                                    local spellid = mq.TLO.Spell(entry.spell).ID() or (entry.gem == 'item' and mq.TLO.FindItem(entry.spell).Spell.ID())
                                    local spelldur = tonumber(mq.TLO.Spell(spellid).MyDuration()) or 0
                                    if spelldur > 0 then
                                        trotsdebuff.DebuffListUpdate(EvalID, myconfig['ad'..i].spell, recastduration)
                                        print('recast for EvalID:', EvalID, 'spellid', spellid, 'set to' , DebuffList[EvalID][spellid], 'curtime', mq.gettime()) 
                                    end
                                end
                                return true
                            else 
                                if not recastcntr[EvalID] then recastcntr[EvalID] ={} end
                                recastcntr[EvalID][i] ={}
                                recastcntr[EvalID][i].counter = 1
                                CurSpell = {}
                                print('set recast counter to:', recastcntr[EvalID][i].counter, ' spell:',entry.spell, ' spawnid:',EvalID)
                                if recastcntr[EvalID] and recastcntr[EvalID][i] and recastcntr[EvalID][i].counter >= myconfig['ad'..i].recast then 
                                    mq.cmdf('/dgt \ayTrotsbot:\ax\ar%s\ax has resisted spell \ar%s\ax ad%s \am%s\ax times, disabling spell for this spawn', mq.TLO.Spawn(EvalID).CleanName(), myconfig['ad'..i].spell, i, myconfig['ad'..i].recast)
                                    mq.delay(1)
                                    mq.cmdf('/dgt \ayTrotsbot:\axTo re-enable run \ag/tb setvar ad%s.recast 0\ax', i)
                                    local recastduration = 600000 + mq.gettime()
                                    local spellid = mq.TLO.Spell(entry.spell).ID() or (entry.gem == 'item' and mq.TLO.FindItem(entry.spell).Spell.ID())
                                    local spelldur = tonumber(mq.TLO.Spell(spellid).MyDuration()) or 0
                                    if spelldur > 0 then
                                        trotsdebuff.DebuffListUpdate(EvalID, myconfig['ad'..i].spell, recastduration)
                                        print('recast for EvalID:', EvalID, 'spellid', spellid, 'set to' , DebuffList[EvalID][spellid], 'curtime', mq.gettime()) 
                                    end
                                end
                                return true
                            end
                        end
                        if not EvalID or (tonumber(myconfig['ad'..i]['tartype']) and myconfig['ad'..i]['tartype'] < 10) then castspell = false end
                        -- repopulate spawn list for another debuff pass if priority spell (tartype > 9)
                        if tonumber(myconfig['ad'..i]['tartype']) and myconfig['ad'..i]['tartype'] > 9 then trotsdebuff.ADSpawnCheck() end
                    else
                        castspell = false break
                    end
                else castspell = false break
                end
            end
        end
    end
end
return trotsdebuff