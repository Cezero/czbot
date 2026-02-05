local mq = require('mq')

local trotspull = {}

function trotspull.LoadPullConfig()
    if (myconfig.pull['radius'] == nil) then myconfig.pull['radius'] = 400 end
    if (myconfig.pull['zrange'] == nil) then myconfig.pull['zrange'] = 150 end
    if (myconfig.pull['chainpullcnt'] == nil) then myconfig.pull['chainpullcnt'] = 0 end
    if (myconfig.pull['chainpullhp'] == nil) then myconfig.pull['chainpullhp'] = 0 end
    if (myconfig.pull['pullability'] == nil) then myconfig.pull['pullability'] = 'melee' end
    if (myconfig.pull['abilityrange'] == nil) then myconfig.pull['abilityrange'] = 60 end
    if (myconfig.pull['maxlevel'] == nil) then myconfig.pull['maxlevel'] = 200 end
    if (myconfig.pull['minlevel'] == nil) then myconfig.pull['minlevel'] = 0 end
    if (myconfig.pull['hunter'] == nil or myconfig.pull['hunter'] ~= (false or true)) then myconfig.pull['hunter'] = false end
    if (myconfig.pull['mana'] == nil) then myconfig.pull['mana'] = 60 end
    if (myconfig.pull['manaclass'] == nil) then myconfig.pull['manaclass'] = 'clr, dru, shm' end
    if (myconfig.pull['leash'] == nil) then myconfig.pull['leash'] = 500 end
    if (myconfig.pull['usepriority'] == nil or myconfig.pull['usepriority'] ~= (false or true)) then myconfig.pull['usepriority'] = false end
    runconfig['pulledmob'] = nil
    runconfig['pullreturntimer'] = nil
    if not runconfig['pullarc'] then runconfig['pullarc'] = nil end
    if not arcLside then arcLside = nil end
    if not arcRside then arcRside = nil end
    arcmid = nil
    manatimer = 1
    deadtimer = 0
    baddoor = false
    hptimer = 0
end

function trotspull.SetPullArc(arc)
    local fdir = mq.TLO.Me.Heading.Degrees()
    if not arc and runconfig['pullarc'] then
        mq.cmd('/echo \arTurning off Directional Pulling.')
        runconfig['pullarc'] = 0
    else
        runconfig['pullarc'] = tonumber(arc)
    end
    if not runconfig['pullarc'] then return end
    -- figure left side degrees
    if (fdir - (runconfig['pullarc'] * .5)) < 0 then
        arcLside = 360 - ((runconfig['pullarc'] * .5) - fdir)
    else
        arcLside = fdir - (runconfig['pullarc'] * .5)
    end
    -- figure left side degrees
    if (fdir + (runconfig['pullarc'] * .5)) > 360 then
        arcRside = ((runconfig['pullarc'] * .5) + fdir) - 360
    else
        arcRside = fdir + (runconfig['pullarc'] * .5)
    end
    -- set current heading
    arcMid = fdir
    if arc then printf('Setting Pull Arc to %s at heading %s', arc, fdir) end
end

function FigureMobAngle(spawn)
    if not spawn then return false end
    local DirToMob = 0
    DirToMob = spawn.HeadingTo(runconfig['makecampy'], runconfig['makecampx']).Degrees()
    if arcLside >= arcRside then
        if DirToMob < arcLside and DirToMob > arcRside then return false end
    else
        if DirToMob < arcLside or DirToMob > arcRside then return false end
    end
    return true
end

function trotspull.AdvPull()
    if debug then print('pull called') end
    local pullcount = 0
    local x = runconfig['makecampx']
    local y = runconfig['makecampy']
    local z = runconfig['makecampz']
    local radius = myconfig.pull['radius']
    local zrange = myconfig.pull['zrange']
    local minlevel = myconfig.pull['minlevel']
    local maxlevel = myconfig.pull['maxlevel']
    local excludelist = runconfig['ExcludeList']
    local moblist = runconfig['MobList']

    local function BuildMobList(spawn)
        if (spawn.Type() == 'NPC') then
            if spawn.Level() >= minlevel and spawn.Level() <= maxlevel then
                local pdist = trotslib.calcDist2D(spawn.X(), spawn.Y(), x, y)
                local xarctar = true
                local zdist = nil
                local pullarc = runconfig['pullarc']
                if pullarc and pullarc > 0 then
                    if not FigureMobAngle(spawn) then xarctar = false end
                end
                if z and spawn.Z() then zdist = math.sqrt((z - spawn.Z()) ^ 2) end
                if pdist and pdist <= radius and (zdist and zdist <= zrange) and xarctar then
                    if not trotspull.FTECheck(spawn.ID()) and not string.find(excludelist, spawn.CleanName()) then
                        if mq.TLO.Navigation.PathExists('id ' .. spawn.ID())() then
                            if not moblist then
                                return true
                            else
                                local moblisttest = false
                                for _, v in pairs(moblist) do
                                    if v.ID() == spawn.ID() then
                                        moblisttest = true
                                    end
                                end
                                if not moblisttest then return true end
                            end
                        end
                    end
                end
            end
        end
    end

    function TagTimeCalc(trip, spawn, x, y, z)
        local tmptagtime = 0
        if trip == 'pull' then
            tmptagtimer = (((mq.TLO.Navigation.PathLength('id ' .. spawn.ID())() + 100) / 100) * 9000) + mq.gettime()
        elseif x and y and z and trip == 'return' then
            tmptagtimer = (((mq.TLO.Navigation.PathLength('locxyz ' .. x .. ',' .. y .. ',' .. z)() + 100) / 100) * 18000) +
            mq.gettime()
        end
        return tmptagtimer
    end

    function trotspull.EngageCheck(spawn)
        --TargetTarget logic
        local target = mq.TLO.Target.CleanName()
        local targetid = mq.TLO.Target.ID()
        local tartar = mq.TLO.Me.TargetOfTarget()
        local tartarid = mq.TLO.Me.TargetOfTarget.ID()
        local tartartype = mq.TLO.Spawn(tartarid).Type()
        local bot = mq.TLO.NetBots(tartar).ID()
        local targetdist = nil
        local botdist = 0
        if bot then targetdist = trotslib.calcDist3D(mq.TLO.Spawn(targetid).X(), mq.TLO.Spawn(targetid).Y(),
                mq.TLO.Spawn(targetid).Z(), runconfig['makecampx'], runconfig['makecampy'], runconfig['makecampz']) end
        if debug then print('engage check called ', bot, botdist, (mq.TLO.Spawn(tartarid).Type() ~= 'NPC'), tartartype) end
        if bot and targetdist and targetdist > 200 and not myconfig.pull['hunter'] then return false end
        if tartarid and tartarid > 0 and tartarid ~= mq.TLO.Me.ID() and (mq.TLO.Spawn(tartarid).Type() ~= 'NPC') and tartartype ~= 'Corpse' then
            mq.cmdf('/dgt \ayTrotsbot:\ax\arUh Oh, \ag%s\ax is \arengaged\ax by someone else! Returning to camp!', target)
            runconfig['engagetracker'][targetid] = (mq.gettime() + 60000)
            mq.cmd('/multiline ; /squelch /target clear ; /nav stop log=off')
            return true
        end
    end

    -- FTE logic that both checks for FTE locked targets (added by event FTELocked) and clears the table of any mobs older than 60 seconds
    function trotspull.FTECheck(spawnid)
        if not spawnid then return true end
        for k, v in pairs(runconfig['engagetracker']) do
            if mq.gettime() > v then runconfig['engagetracker'][k] = nil end
            if k == spawnid then
                return true
            end
        end
        if spawnid and FTEList[spawnid] and (FTEList[spawnid].timer + 60000) > mq.gettime() + 60000 then return true end
        return false
    end

    local function BuildAggroList(spawn)
        if (spawn.Type() == 'NPC' and spawn.LineOfSight() and myconfig.pull['abilityrange'] > spawn.Distance3D()) and not string.find(runconfig['ExcludeList'], spawn.CleanName()) then
            if mq.TLO.Navigation.PathExists('id ' .. spawn.ID())() and spawn.Aggressive() then
                local matchfound = false
                for _, v in ipairs(runconfig['MobList']) do
                    if v.ID() == spawn.ID() then
                        matchfound = true
                    end
                end
                if not matchfound then return true end
            end
        end
    end
    -- function that checks for hostile mobs in los and inside pullabilityrange on the way to the APTarget
    function Aggro(timer)
        if debug then print('aggro called, APTarget is ' .. APTarget.ID()) end
        if not APTarget then return false end
        if APTarget() and APTarget.Distance() < myconfig.pull['abilityrange'] and APTarget.LineOfSight() then
            --get aptarget
            mq.cmdf('/multiline ; /nav stop log=off ; /squelch /tar id %s', APTarget.ID())
            mq.delay(1000, (function() if (APTarget.ID() == mq.TLO.Target.ID()) then return true end end))
            AggroMob(APTarget, timer)
            return true
        end
        --trotsdebuff.ADSpawnCheck()
        loslist = mq.getFilteredSpawns(BuildAggroList)
        table.sort(loslist, function(a, b)
            return mq.TLO.Navigation.PathLength('id ' .. a.ID())() < mq.TLO.Navigation.PathLength('id ' .. b.ID())()
        end)
        local engagedmob = false
        if loslist[1] and not trotspull.FTECheck(loslist[1]) and not engagedmob then
            -- check los targets
            if loslist[1] then
                APTarget = loslist[1]
                mq.cmdf('/multiline ; /echo prox aggro while running %s ; /nav stop log=off ; /squelch /tar id %s',
                    APTarget.Name(), APTarget.ID())
                mq.delay(1000, (function() if (APTarget.ID() == mq.TLO.Target.ID()) then return true end end))
                AggroMob(APTarget, timer)
                return true
            end
        else
            return false
        end
    end

    -- Aggro's aptarget and validates aggro was succesful
    function AggroMob(spawn, timer)
        local pullab = myconfig.pull['pullability']
        while APTarget and APTarget.Type() == 'NPC' and not APTarget.Aggressive() and (timer >= mq.gettime() and spawn.Type() == 'NPC') do
            mq.doevents()
            if MasterPause then break end
            if mq.TLO.Me.CombatAbilityReady(pullab)() then
                if debug then print('disc') end
                mq.cmdf('/multiline ; /nav stop log=off ; /disc %s', pullab)
                if not mq.TLO.Stick.Active() then mq.cmdf('/stick 5 uw moveback id %s', spawn.ID()) end
            end
            if mq.TLO.Me.AbilityReady(pullab)() then
                if debug then print('ability') end
                mq.cmdf('/multiline ; /nav stop log=off ; /attack on ; /doability %s', pullab)
                if not mq.TLO.Stick.Active() then mq.cmdf('/stick 5 uw moveback id %s', spawn.ID()) end
            end
            if mq.TLO.Me.AltAbilityReady(pullab)() then
                if debug then print('alt') end
                mq.cmd('/nav stop log=off')
                mq.delay(2000, function() return mq.TLO.Me.Moving() end)
                mq.cmdf('/multiline ; /nav stop log=off ; /alt act %s', mq.TLO.Me.AltAbility(pullab)())
            end
            if mq.TLO.Me.Gem(pullab)() and mq.TLO.Me.SpellReady(pullab)() then
                if debug then print('spell') end
                mq.cmd('/nav stop log=off')
                mq.delay(2000, function() return mq.TLO.Me.Moving() end)
                mq.cmdf('/multiline ; /nav stop log=off ; /casting "%s"', pullab)
                mq.delay(3000, function() return mq.TLO.Me.CastTimeLeft() ~= 0 end)
                mq.delay(20)
                mq.delay(8000, function() return mq.TLO.Me.CastTimeLeft() == 0 end)
            end
            if string.lower(pullab) == 'ranged' then mq.cmdf(
                '/multiline ; /squelch /nav stop log=off ; /face fast ; /squelch attack off ; /ranged on') end
            if string.lower(pullab) == 'melee' or string.lower(pullab) == 'warp' then
                mq.cmd('/multiline ; /squelch /nav stop log=off ; /attack on')
                if not mq.TLO.Stick.Active() then mq.cmdf('/stick 5 uw moveback id %s', spawn.ID()) end
            end
            if not (spawn.Aggressive()) and mq.TLO.Target.ID() == spawn.ID() and (spawn.Type() == 'NPC') and spawn.ID() ~= runconfig['acmatarget'] and (not mq.TLO.Stick.Active() or not spawn.LineOfSight()) then
                mq.cmdf('/nav id %s dist=5 log=off los=on', spawn.ID())
            end
            if APTarget and APTarget.Aggressive() then trotspull.EngageCheck() end
            mq.delay(10)
        end
        if debug then print('aggro mob exit') end
        return true
    end

    function CampReturn(timer)
        if mq.TLO.Stick.Active() then mq.cmd('/stick off') end
        if mq.TLO.Me.Combat() then mq.cmd('/squelch /attack off') end
        mq.cmdf('/multiline ; /echo \ayReturning to camp ; /nav locxyz %s %s %s log=off dist=0', runconfig['makecampx'],
            runconfig['makecampy'], runconfig['makecampz'])
        while mq.TLO.Navigation.Active() and (timer > mq.gettime()) do
            mq.doevents()
            if MasterPause then break end
            if myconfig.pull['pullability'] == 'warp' then mq.cmdf('/warp loc %s %s %s', runconfig['makecampy'],
                    runconfig['makecampx'], runconfig['makecampz']) end
            mq.delay(10)
            if not mq.TLO.Navigation.Paused() and APTarget and APTarget.Distance() and APTarget.Distance() > myconfig.pull['leash'] then
                mq.cmd('/nav pause on log=off')
            elseif mq.TLO.Navigation.Paused() and APTarget and APTarget.Distance() and APTarget.Distance() < myconfig.pull['leash'] then
                mq.cmd('/nav pause off log=off')
            end
        end
    end

    function WaitForCombat(timer)
        function IsAPTarInCamp()
            for _, v in ipairs(runconfig['MobList']) do
                if APTarget and v.ID() == APTarget.ID() then return true end
            end
            return false
        end

        while not IsAPTarInCamp() and APTarget and (APTarget.Type() == 'NPC') and APTarget.Aggressive() and (timer > mq.gettime()) do
            mq.doevents()
            if MasterPause then break end
            if mq.TLO.Math.Distance(runconfig.makecampy, runconfig.makecampx, runconfig.makecampz)() > myconfig.settings.acleash then
                if myconfig.pull['pullability'] ~= 'warp' then
                    mq.cmdf('/multiline ; /echo \ayReturning to camp ; /nav locxyz %s %s %s log=off dist=0',
                        runconfig['makecampx'], runconfig['makecampy'], runconfig['makecampz'])
                end
                if myconfig.pull['pullability'] == 'warp' then
                    mq.cmdf('/multiline ; /echo \ayReturning to camp ; /warp loc %s %s %s', runconfig['makecampy'],
                        runconfig['makecampx'], runconfig['makecampz'])
                end
            end
            if debug then print('wait for combat IsAPTarInCamp:', IsAPTarInCamp(), ' timer is:', timer, 'gettime is',
                    mq.gettime()) end
            trotsdebuff.ADSpawnCheck()
            if (runconfig['MobList'][1]) and myconfig.settings['domelee'] then trotsmelee.AdvCombat() end
            mq.delay(1000)
        end
    end

    if runconfig['pulledmob'] then
        if mq.TLO.Spawn(runconfig['pulledmob']).Distance3D() >= myconfig.settings['acleash'] then
            if runconfig['pullreturntimer'] >= mq.gettime() then return end
            mq.cmdf('/echo %s id %s never made it to camp, trying to pull a mob',
                mq.TLO.Spawn(runconfig['pulledmob']).CleanName(), runconfig['pulledmob'])
            runconfig['pulledmob'] = nil
        end
    end

    if MasterPause then return false end

    if mq.TLO.Me.PctHPs() <= 45 then
        APTarget = nil
        tagtimer = nil
        if hptimer and hptimer <= mq.gettime() then
            mq.cmd('/echo HP below 45%, holding pulls')
            hptimer = mq.gettime() + 30000
        end
        return false
    end

    if not mq.TLO.Navigation.MeshLoaded() then
        mq.cmd(
        '/dgt \ayTrotsbot:\axI have DoPull set TRUE but have \arno MQ2Nav Mesh loaded\ax, please generate a NavMesh before using DoPull, \arsetting DoPull to FALSE\ax')
        myconfig.settings['dopull'] = false
        return
    end
    --Dead group member check and group mana check
    if mq.TLO.Group() then
        local lowmana = ''
        local curmana = 100
        for iter = 1, mq.TLO.Group() do
            local grpname = mq.TLO.Group.Member(iter)
            if (grpname.Type() and string.lower(grpname.Type()) == 'corpse') then
                if deadtimer <= mq.gettime() then
                    mq.cmdf('/dgt \ayTrotsbot:\ax\ar%s\ax is in my group and \arDEAD\ax holding pulls',
                        'pc ' .. grpname.Name())
                    deadtimer = mq.gettime() + 60000
                end
                return false
            end
            if myconfig.pull['mana'] then
                if grpname.Type() and grpname.Class.ShortName() and string.find(myconfig.pull['manaclass'], string.lower(grpname.Class.ShortName())) then
                    if grpname.PctMana() and grpname.ID() then
                        lowmana = grpname()
                        curmana = grpname.PctMana()
                    end
                end
            end
            if curmana then
                if (myconfig.pull['mana'] > curmana) and (manatimer < mq.gettime()) then
                    mq.cmdf(
                    '/dgt \ayTrotsbot:\ax%s is a healer in my group with %s %% mana which is below my HealMana threshold, holding pulls (checking mana continously, but will message again in 60 seconds)',
                        lowmana, curmana)
                    manatimer = mq.gettime() + 60000
                end
                if (myconfig.pull['mana'] > curmana) then return false end
            end
        end
    end
    mq.cmdf('/squelch /mapfilter SpellRadius %s', myconfig.pull['radius'])
    mq.cmdf('/squelch /mapfilter CastRadius %s', mq.TLO.Spell(myconfig.pull['pullability']).MyRange())
    if not myconfig.pull['hunter'] and not runconfig['campstatus'] then trotsmove.MakeCamp('on') end
    if myconfig.pull['hunter'] and (not runconfig['makecampx'] or not runconfig['makecampy']) then
        mq.cmd('/echo setting HunterMode anchor')
        runconfig['makecampx'] = mq.TLO.Me.X()
        runconfig['makecampy'] = mq.TLO.Me.Y()
        runconfig['makecampz'] = mq.TLO.Me.Z()
        if runconfig['campstatus'] then trotsmove.MakeCamp('off') end
    end
    if myconfig.pull['hunter'] and runconfig['campstatus'] then
        print('Disabling makecamp because dopull is on with HunterMode enabled')
        trotsmove.MakeCamp('off')
    end
    if debug then print('buildmoblist') end
    local apmoblist = mq.getFilteredSpawns(BuildMobList)
    if debug then print('moblist built') end
    if not apmoblist[1] then return false end
    local pathlengthlist = {}
    for k, v in ipairs(apmoblist) do
        -- mq.delay(1)
        pathlengthlist[v.ID()] = mq.TLO.Navigation.PathLength('id ' .. v.ID())()
    end
    for _, _ in ipairs(apmoblist) do
        pullcount = pullcount + 1
    end
    if debug then print('moblist sorted') end
    local pulltardist = nil
    local pulltar = nil
    local pullindex = nil
    -- find the closest mob to us
    for k, v in pairs(pathlengthlist) do
        --print("mob id:", k, " distance:",v)
        if not pulltardist then pulltardist = v end
        if v and pulltardist >= v and v > 0 then
            --print("mob id:", k, " distance:",v)
            pulltardist = v
            pulltar = k
        end
    end
    for k, v in ipairs(apmoblist) do
        if v.ID() == pulltar then
            pullindex = k
        end
    end
    if pullcount == 0 then return false end

    if myconfig.pull['usepriority'] then
        if runconfig['PriorityList'] then
            for _, v in ipairs(apmoblist) do
                if string.find(runconfig['PriorityList'], v.CleanName()) then APTarget = v else end
            end
        end
        if not APTarget then APTarget = apmoblist[pullindex] end
    else
        APTarget = apmoblist[pullindex]
    end
    if not APTarget then
        return false
    end
    if debug then print('pull target found') end
    for _, v in pairs(runconfig['MobList']) do
        if v.ID() == APTarget.ID() then
            if debug then print(APTarget.Name(), APTarget.ID() .. ' is in the moblist') end
        end
    end
    local distance = APTarget.Distance()
    if distance then distance = math.floor(APTarget.Distance()) end
    mq.cmdf('/dgt \ayTrotsbot:\axAttempting to pull \ar%s \arid %s \auat %s', APTarget.Name(), APTarget.ID(), distance)
    mq.cmd('/multiline ; /attack off ; /stick off ; /squelch /target clear')
    mq.cmdf('/nav id %s dist= 7 log=off los=on', APTarget.ID())
    if string.lower(myconfig.pull['pullability']) == 'warp' then mq.cmdf('/warp id %s', APTarget.ID()) end
    local tagtimer = TagTimeCalc('pull', APTarget)
    if debug then print('timer is ' .. tagtimer .. ' gettime is ' .. mq.gettime()) end
    while (tagtimer and tagtimer >= mq.gettime() and APTarget) do
        if debug then print('pull loop, tag timer is ' ..
            tagtimer .. ' mqtime is ' .. mq.gettime() .. ' APTarget ID is ' .. APTarget.ID()) end
        mq.doevents()
        mq.delay(10)
        if MasterPause then break end
        if (APTarget and APTarget.ID() and APTarget.Distance3D() and (mq.TLO.Target.ID() ~= APTarget.ID()) and APTarget.Distance3D() <= 200) or (APTarget and APTarget.LineOfSight()) then
            if debug then print('timer update') end
            mq.cmdf('/squelch /tar id %s', APTarget.ID())
            --tagtimer = mq.gettime() + 5000
            mq.delay(1000, (function() return (mq.TLO.Target.ID() ~= APTarget.ID()) end))
        end
        if not mq.TLO.Navigation.Active() and APTarget.Distance() and APTarget.Distance() > myconfig.pull['abilityrange'] then
            mq.cmdf('/nav id %s dist= 7 log=off los=on', APTarget.ID()) end
        if mq.TLO.Me.Class.ID() == 7 and mq.TLO.Me.PctHPs() < 25 then
            mq.cmd('/multiline ; /doability "feign death" ; /doability "mend"')
            APTimer = 60000
        end
        if mq.TLO.Me.Class.ID() == 7 and mq.TLO.Me.PctHPs() > 60 then mq.cmd('/stand on') end
        if baddoor then
            mq.cmd('/squelch /doort')
            if (mq.TLO.DoorTarget.Distance3D() < 35) then mq.cmd('/squelch /click left door') end
        end
        if mq.TLO.Me.TargetOfTarget.ID() and mq.TLO.Target.ID() and mq.TLO.Target.Type() == 'NPC' and APTarget and APTarget.Distance() and APTarget.Distance() <= 200 or (APTarget and APTarget.LineOfSight()) then
            if trotspull.EngageCheck() then return end
        end
        if (tagtimer <= mq.gettime()) then
            mq.cmdf('/dgt \ayTrotsbot:\ax\arI have timed out trying to pull \ay%s', APTarget.Name())
            if string.lower(myconfig.pull['pullability']) == 'warp' then mq.cmdf('/warp loc %s %s %s',
                    runconfig['makecampy'], runconfig['makecampx'], runconfig['makecampz']) end
        end
        if runconfig['campstatus'] then
            if (trotslib.calcDist3D(runconfig['makecampx'], runconfig['makecampy'], runconfig['makecampz'], mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()) > (myconfig.pull['radius'] + 40)) then
                mq.cmdf('/dgt \ayTrotsbot:\ax\arI have gone too far from camp trying to pull \ay%s', APTarget.Name())
                APTarget = nil
                tagtimer = nil
                if string.lower(myconfig.pull['pullability']) == 'warp' then mq.cmdf('/warp loc %s %s %s',
                        runconfig['makecampy'], runconfig['makecampx'], runconfig['makecampz']) end
            end
        end
        if mq.TLO.Me.PctHPs() <= 45 then
            APTarget = nil
            tagtimer = nil
        end
        if APTarget then
            if not (APTarget.ID() or (APTarget.Type() == 'CORPSE') or (APTarget.Type() == 'PET')) then
                APTarget = nil
                tagtimer = nil
            end
        end
        if (APTarget) then
            if Aggro(tagtimer) then
                if tagtimer < mq.gettime() then APTarget = nil end
                tagtimer = 0
                if debug then print(tagtimer .. ' tag timer reset, got mob') end
            end
        end
    end
    local returntimer = TagTimeCalc('return', 'return', runconfig['makecampx'], runconfig['makecampy'],
        runconfig['makecampz'])
    if not myconfig.pull['hunter'] and APTarget and APTarget.Type ~= 'Corpse' and APTarget.ID() then
        if debug then print('camp return') end
        CampReturn(returntimer)
        if mq.TLO.Me.CombatState() == 'COMBAT' and APTarget then WaitForCombat(returntimer) end
    end
    if debug then print('pull exit') end
    APTarget = nil
end

return trotspull
