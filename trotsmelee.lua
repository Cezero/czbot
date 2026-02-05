local mq = require('mq')
local trotsmelee = {}

function trotsmelee.LoadMeleeConfig()
    if (myconfig.melee['stickcmd'] == nil) then myconfig.melee['stickcmd'] = 'hold uw 7' end
    if (myconfig.melee['offtank'] == nil) then myconfig.melee['offtank'] = false end
    if (myconfig.melee['otoffset'] == nil) then myconfig.melee['otoffset'] = 0 end
    if (myconfig.melee['minmana'] == nil) then myconfig.melee['minmana'] = 0 end
    if (myconfig.melee['assistpct'] == nil) then myconfig.melee['assistpct'] = 99 end
end

--declare trotsmelee vars
mobprobtimer = 0
--combatloop
function trotsmelee.AdvCombat()
    if debug then print('melee called') end
    --tank logic
    local tanktar = nil
    local tank = myconfig.settings['TankName']
    local assistpct = myconfig.melee['assistpct'] or 99
    local newacmafound = false
    if tank == mq.TLO.Me.Name() and mq.TLO.Target.Master.Type() == 'PC' then
        runconfig['acmatarget'] = nil
        if (mq.TLO.Stick.Active()) then mq.cmd('/squelch /stick off') end
        if (mq.TLO.Me.Combat()) then mq.cmd('/squelch /attack off') end
        if (mq.TLO.Me.Pet.Aggressive) then
            mq.cmd('/squelch /pet back off')
            mq.cmd('/squelch /pet follow')
        end
        if (mq.TLO.Target.Type() == 'NPC') then mq.cmd('/squelch /target clear') end
    end
    if tank == mq.TLO.Me.Name() and (mq.TLO.Raid.Members() or not mq.TLO.Group() or mq.TLO.Group.MainTank() == mq.TLO.Me.Name()) and not mq.TLO.Me.Combat() then
        if debug then print('tanklogic') end
        for _, v in ipairs(runconfig['MobList']) do
            if v.LineOfSight() and trotslib.IgnoreCheck() then
                if tanktar then
                    if v.ID() == runconfig['acmatarget'] then
                        tanktar = v
                        newacmafound = true
                    end
                    if v.Distance() < tanktar.Distance() then
                        tanktar = v
                    end
                else
                    tanktar = v
                end
            end
        end
        if tanktar then
            if tanktar.ID() then
                runconfig['acmatarget'] = tanktar.ID()
            end
        end
    end
    if newacmafound then
        local followdistance = 35
        local followid = mq.TLO.Spawn(runconfig['followid']).ID() or 0
        local followtype = mq.TLO.Spawn(runconfig['followid']).Type() or "none"
        local returntimer = mq.gettime() + 10000
        if followdistance > 0 and runconfig['followid'] and followid and not (followtype == 'CORPSE') and (followdistance >= 35) then
            mq.cmd('/multiline ; /stick off ; /squelch /attack off ; /target self')
            --print('unstuck debug: ', followid, followdistance)
            trotsmove.FollowCall()
            mq.delay(400)
            while (mq.TLO.Navigation.Active() and returntimer > mq.gettime()) do mq.delay(100) end
        end
    end
    --offtank logic
    if (myconfig.melee['offtank'] and tank ~= mq.TLO.Me.Name()) then
        if debug then print('offtank logic') end
        local actarid
        local acname
        local tanktarid = nil
        if mq.TLO.NetBots(tank).ID() then
            tanktarid = mq.TLO.NetBots(tank).TargetID()
        elseif mq.TLO.Spawn('pc =' .. tank).ID() then
            tanktarid = trotsmelee.GetTankTar(tank)
        end
        local otcounter = 0
        for _, v in ipairs(runconfig['MobList']) do
            --print('moblistid:', v.ID(), ' tanktarid:', tanktarid, ' otcounter:',otcounter)
            if v.ID() ~= tanktarid and not actarid then
                if otcounter == myconfig.melee['otoffset'] then
                    actarid = v.ID()
                    acname = v.CleanName()
                end
                otcounter = otcounter + 1
            end
        end
        if debug then print('offtank target: ', actarid) end
        if actarid then
            if actarid ~= mq.TLO.Target.ID() then mq.cmdf('/dgt \ayTrotsbot:\ax\arOff-tanking\ax a \ag%s id %s', acname,
                    actarid) end
            runconfig['acmatarget'] = actarid
        elseif mq.TLO.NetBots(tank).TargetHP() and (mq.TLO.NetBots(tank).TargetHP() <= assistpct) then
            if tanktarid > 0 then runconfig['acmatarget'] = tanktarid else runconfig['acmatarget'] = nil end
            if debug then print('nothing to offtank, acmatarget: ', runconfig['acmatarget']) end
        end
    end
    --melee logic
    if not myconfig.melee['offtank'] and not (tank == mq.TLO.Me.Name()) then
        if debug then print('meleelogic') end
        local tanktarid = mq.TLO.NetBots(tank).TargetID()
        if mq.TLO.NetBots(tank).ID() and (runconfig['acmatarget'] ~= tanktarid) then runconfig['acmatarget'] = nil end
        for _, v in ipairs(runconfig['MobList']) do
            if v.ID() == tanktarid and mq.TLO.NetBots(tank).TargetHP() and (mq.TLO.NetBots(tank).TargetHP() <= assistpct) then
                runconfig['acmatarget'] = tanktarid
            end
        end
        if not mq.TLO.NetBots(tank).ID() then
            runconfig['acmatarget'] = trotsmelee.GetTankTar(tank)
        end
    end
    --engage logic
    if runconfig['acmatarget'] then
        if mq.TLO.Me.Pet.ID() and myconfig.settings['petassist'] and not mq.TLO.Pet.Aggressive() then
            mq.cmdf('/pet attack %s', runconfig['acmatarget'])
        end
        if myconfig.settings['domelee'] then
            if mq.TLO.Target.ID() ~= runconfig['acmatarget'] then mq.cmdf('/tar id %s', runconfig['acmatarget']) end
            mq.delay(500, function() if mq.TLO.Target.ID() == runconfig['acmatarget'] then return true end end)
            if mq.TLO.Navigation.Active() then mq.cmd('/nav stop') end
            if mq.TLO.Me.Sitting() then mq.cmd('/stand on') end
            if not mq.TLO.Me.Combat() then mq.cmd('/squelch /attack on') end
            if not mq.TLO.Stick.Active() or (mq.TLO.Stick.StickTarget() ~= runconfig['acmatarget']) then mq.cmdf(
                '/squelch /multiline ; /attack on ; /stick %s', myconfig.melee['stickcmd']) end
            if mq.TLO.Me.Class.ShortName() ~= 'BRD' then
                mq.delay(5000,
                    function() if mq.TLO.Target.Distance() and mq.TLO.Target.Distance() < mq.TLO.Target.MaxMeleeTo() then return true end end)
            end
        end
        --combat reset (mob dead, mob despawn, zoning?)
    else
        --print(runconfig['acmatarget'])
        if (mq.TLO.Stick.Active()) then mq.cmd('/squelch /stick off') end
        if (mq.TLO.Me.Combat()) then mq.cmd('/squelch /attack off') end
        if (mq.TLO.Me.Pet.Aggressive) then
            mq.cmd('/squelch /pet back off')
            mq.cmd('/squelch /pet follow')
        end
        if (mq.TLO.Target.Type() == 'NPC') then mq.cmd('/squelch /target clear') end
    end
end

--GetAssistLogic (for non-bot tanks)
function trotsmelee.GetTankTar(tank)
    if debug then print('gettanktar sub called') end
    if tank and mq.TLO.Spawn('pc =' .. tank).ID() then
        if mq.TLO.Me.Assist() then mq.cmd('/squelch /assist off') end
        mq.cmdf('/assist %s', tank)
        mq.delay(500)
        for _, v in ipairs(runconfig['MobList']) do
            if mq.TLO.Target.ID() == v.ID() then return mq.TLO.Target.ID() end
        end
    end
end

--MobProb (cant hit target logic)
function Event_MobProb(line, arg1, arg2)
    if mobprobtimer <= mq.gettime() then return true end
    if runconfig['acmatarget'] then
        if mq.TLO.Navigation.PathLength('id ' .. runconfig['acmatarget'])() <= myconfig.settings['acleash'] then mq.cmdf(
            '/nav id %s dist=0 log=off', runconfig['acmatarget']) end
    end
    mobprobtimer = mq.gettime() + 3000
end

mq.event('MobProb1', "#*#Your target is too far away,#*#", Event_MobProb)
mq.event('MobProb2', "#*#You cannot see your target#*#", Event_MobProb)
mq.event('MobProb3', "#*#You can\'t hit them from here#*#", Event_MobProb)

return trotsmelee
