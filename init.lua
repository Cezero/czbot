local mq = require('mq')
local imgui = require 'ImGui'
trotslib = require('trotslib')
--local trots_spell_routines = require('trots_spell_routines')
trotsmelee = require('trotsmelee')
trotsheal = require 'trotsheal'
trotsdebuff = require('trotsdebuff')
trotsevent = require 'trotsevent'
trotsbuff = require 'trotsbuff'
trotscure = require 'trotscure'
trotspull = require 'trotspull'
--local trotsloot = require 'trotsloot'
trotsmove = require 'trotsmove'
--local trotsextra = require 'trotsextra'
trotsraid = require 'trotsraid'
--build variables for trotsbot
--startup >
-- initialize your config table
myconfig = {}
-- name of config file in config folder - NTA logic for shrouds
--path = 'tb_'..mq.TLO.Me.CleanName()..'.lua'
path = mq.configDir .. '\\tb_' .. mq.TLO.Me.CleanName() .. '.lua'
--call StartUp sub in trotslib
trotslib.StartUp(...)
local misctimer = mq.gettime()
stucktimer = 0
local inactivetimer = 0
MasterPause = false

--main loop
while not terminate do
    if MasterPause then
        while (MasterPause) do
            mq.delay(10)
        end
    end
    if runconfig['zonename'] ~= mq.TLO.Zone.ShortName() then
        mq.delay(1000)
        print('Zone detected')
        DelayOnZone()
    end
    mq.doevents()
    if myconfig.settings['doraid'] then
        while (trotsraid.RaidCheck()) do
            trotsraid.RaidCheck()
            mq.doevents()
            mq.delay(10)
        end
    end
    trotslib.CharState()
    trotsdebuff.ADSpawnCheck()
    if myconfig.settings['domelee'] and runconfig['MobList'][1] and myconfig.melee['minmana'] == 0 then
        trotsmelee.AdvCombat()
    elseif myconfig.settings['domelee'] and runconfig['MobList'][1] and myconfig.melee['minmana'] > 0 and myconfig.settings['TankName'] ~= mq.TLO.Me.Name() then
        if (tonumber(myconfig.melee['minmana']) < mq.TLO.Me.PctMana() or mq.TLO.Me.MaxMana() == 0) then trotsmelee
                .AdvCombat() end
    elseif myconfig.settings['TankName'] == mq.TLO.Me.Name() and runconfig['MobList'][1] then
        trotsmelee.AdvCombat()
    end
    if myconfig.settings['docure'] and myconfig.cure['count'] and myconfig.cure.prioritycure then trotscure.CureCheck() end
    if (myconfig.settings['dopull']) then
        if runconfig['MobCount'] <= myconfig.pull['chainpullcnt'] or myconfig.pull['chainpullcnt'] == 0 then
            if mq.TLO.Spawn(runconfig['acmatarget']).PctHPs() then
                local tempcnt = 0
                if myconfig.pull['chainpullcnt'] == 0 then tempcnt = myconfig.pull['chainpullcnt'] + 1 else tempcnt =
                    myconfig.pull['chainpullcnt'] end
                if (tonumber(mq.TLO.Spawn(runconfig['acmatarget']).PctHPs()) <= myconfig.pull['chainpullhp']) and runconfig['MobCount'] <= tempcnt then
                    trotspull.AdvPull() end
            end
        end
        if (runconfig['MobCount'] < myconfig.pull['chainpullcnt']) then trotspull.AdvPull() end
        if (runconfig['MobCount'] == 0) and not runconfig['acmatarget'] then trotspull.AdvPull() end
    end
    if myconfig.settings['doheal'] and myconfig.heal['count'] then trotsheal.HealCheck() end
    if myconfig.settings['dodebuff'] and myconfig.debuff['count'] and runconfig['MobList'][1] then trotsdebuff
            .DebuffCheck() end
    if myconfig.settings['dobuff'] and myconfig.buff['count'] then trotsbuff.BuffCheck() end
    if myconfig.settings['docure'] and myconfig.cure['count'] then trotscure.CureCheck() end
    if myconfig.settings['doevent'] and myconfig.event['count'] then trotsevent.EventCheck() end
    if misctimer <= mq.gettime() then
        --drag call
        if not runconfig['acmatarget'] and inactivetimer < mq.gettime() then
            inactivetimer = mq.gettime() + math.random(60000, 90000)
            mq.cmd('/click right center')
        end
        if myconfig.settings['dodrag'] then trotslib.DragCheck() end
        --follow logic
        if runconfig['followid'] and runconfig['followid'] > 0 then
            local followid = mq.TLO.Spawn(runconfig['followid']).ID() or 0
            local followdistance = mq.TLO.Spawn(runconfig['followid']).Distance() or 0
            local acmatar = runconfig['acmatarget'] or 0
            local followtype = mq.TLO.Spawn(runconfig['followid']).Type() or "none"
            if followid > 0 and (followid ~= runconfig['followid']) then runconfig['followid'] = followid end
            if followid > 0 then
                if followdistance > 0 and acmatar == 0 and runconfig['followid'] and followid and not (followtype == 'CORPSE') and (followdistance >= 35) then
                    --print('unstuck debug followid and followdistance: ', followid, followdistance)
                    trotsmove.FollowCall()
                end
            end
        end
        --stuck logic
        if runconfig['followid'] and runconfig['followid'] > 0 and (mq.TLO.Spawn(runconfig['followid']).Distance3D() and mq.TLO.Spawn(runconfig['followid']).Distance3D() <= myconfig.settings['acleash']) and stucktimer < mq.gettime() + 60000 then
            stucktimer = mq.gettime() + 60000
        end
        --makecamp check
        if runconfig['campstatus'] then
            if not runconfig['acmatarget'] and (mq.TLO.Me.Class.ShortName() == 'BRD' or not mq.TLO.Me.Casting.ID()) then
                if (mq.TLO.Math.Distance(mq.TLO.Me.X() .. ',' .. mq.TLO.Me.Y() .. ':' .. runconfig['makecampx'] .. ',' .. runconfig['makecampy'])() > (myconfig.settings['acleash'] * .20)) or not mq.TLO.LineOfSight(mq.TLO.Me.X() .. ',' .. mq.TLO.Me.Y() .. ',' .. mq.TLO.Me.Z() .. ':' .. runconfig['makecampx'] .. ',' .. runconfig['makecampy'] .. ',' .. runconfig['makecampz'])() then
                    print("\ar Exceeded ACLeash\ax, resetting combat")
                    if (mq.TLO.Stick.Active()) then mq.cmd('/squelch /stick off') end
                    if (mq.TLO.Me.Combat()) then mq.cmd('/squelch /attack off') end
                    if (mq.TLO.Me.Pet.Aggressive) then
                        mq.cmd('/squelch /pet back off')
                        mq.cmd('/squelch /pet follow')
                    end
                    if (mq.TLO.Target.Type() == 'NPC') then mq.cmd('/squelch /target clear') end
                    trotsmove.MakeCamp('return')
                end
            end
        end
        misctimer = mq.gettime() + 1000
    end
    --check state
    --are we dead?
    --is there a GM in zone?
    --check tankname
    --check doyell
    --check raids
    --check prioritycures
    --check campstatus
    --check if mobgot charmed?
    --check melee
    --check heals
    --(gated behind : brd or not moving or having an ACState)
    --check cure
    --check debuff
    --check event
    --check buff
    --check pulls

    --misc section
    --char state
    --trades
    --auto decline not in netbots
    --auto accept in netbots
    --clear cursor
    --not moving
    --not attacking
    --not dead\hovering
    --not charmed
    --not invunerable
    --not FD
    --gm in zone
    --open windows
    --sit check
    --zonechange check
    --followid reset
    --camp reset
    --pull disable
    --pullto disable
    --charm pet reset
    --acmatarget reset
    --ADMobList clean
    --dodrag
    --camp return
    --follow check
    --stuck check
    --pullto check
    --spawncheck
    --pet check
    --mount check
    --shrink check
end
