local mq = require('mq')
local trotsraid = {}
--Kunark Events

function TrakBreathOut()
    local casterclass = { dru = true, enc = true, mag = true, nec = true, shm = true, wiz = true }
    local meleeclass = { brd = true, ber = true, bst = true, mnk = true, pal = true, rng = true, rog = true, shd = true, war = true }
    local myclass = string.lower(mq.TLO.Me.Class.ShortName())
    if myconfig.settings['doraid'] and mq.TLO.Zone.ID() == 89 then
        if casterclass[myclass] then mq.cmd('/interrupt') end
        if meleeclass[myclass] or casterclass[myclass] then
            raidsactive = true
            myconfig.settings['domelee'] = false
            runconfig['acmatarget'] = nil
            mq.cmd('/multiline ; /stick off ; /attack off ; /pet back off')
            mq.cmd('/multiline ; /nav loc -1180 -75 -178 ; /echo TrotsRaid: Moving away from Trak')
            mq.delay(200)
        end
    end
end

function TrakBreathIn()
    local casterclass = { dru = true, enc = true, mag = true, nec = true, shm = true, wiz = true }
    local meleeclass = { brd = true, ber = true, bst = true, mnk = true, pal = true, rng = true, rog = true, shd = true, war = true }
    local myclass = string.lower(mq.TLO.Me.Class.ShortName())
    print('trakin ', myclass)
    if myconfig.settings['doraid'] and mq.TLO.Zone.ID() == 89 then
        raidtimer = 30000 + mq.gettime()
        raidsactive = false
        if casterclass[myclass] then mq.cmd('/interrupt') end
        if meleeclass[myclass] or casterclass[myclass] then
            raidsactive = true
            if meleeclass[myclass] then myconfig.settings['domelee'] = true end
            runconfig['acmatarget'] = nil
            mq.cmd('/multiline ; /stick off ; /attack off ; /pet back off')
            mq.cmd(
            '/multiline ; /nav id ${Spawn[Trakanon].ID} distance=35 ; /echo TrotsRaid: Resuming Combat with Trak...')
            mq.delay(200)
        end
    end
end

mq.event('TrakBreathIn', "#*#Trakanon begins casting Poison Breath#*#", TrakBreathIn)
mq.event('TrakBreathIn2', "#*#Joust Engage#*#", TrakBreathIn)

-- Velious Events
function LadyNevIn()
end

function MilasIn()
end

function DozeIn()
end

mq.event('LadyNevIn', "#*#Lady Nevederia begins casting Bellowing Winds#*#", LadyNevIn)
mq.event('LadyNevIn2', "#*#Joust Engage#*#", LadyNevIn)
mq.event('MilasIn', "#*#Milas An`Rev begins casting Devastating Frills#*#", MilasIn)
mq.event('MilasIn2', "#*#Joust Engage#*#", MilasIn)
mq.event('DozeIn', "#*#Dozekar the Cursed begins casting Silver Breath#*#", DozeIn)
mq.event('DozeIn2', "#*#Joust Engage#*#", DozeIn)

-- Luclin Events

function CursedIn()
end

function GriegIn()
end

mq.event('CursedIn', "#*#the Cursed begins casting Caustic Mist#*#", CursedIn)
mq.event('CursedIn2', "#*#Joust Engage#*#", CursedIn)
mq.event('GriegIn', "#*#Joust Engage#*#", GriegIn)
mq.event('GriegIn2', "#*#Grieg Veneficus begins casting Upheaval#*#", GriegIn)

-- PoP Events
function RatheKill()
end

mq.event('RatheKill', "#*#rkill engage#*#", RatheKill)

-- GoD/OoW Events (Half-Enabled)
function ForesightDuck() end

function ForesightStill() end

function OMMGaze() end

function TureBackOut() end

function TureBackIn() end

mq.event('ForesightDuck', "#*#From the corner of your eye, you notice a Kyv taking aim at your head. You should duck.#*#",
    ForesightDuck)
mq.event('ForesightStill',
    "#*#From the corner of your eye, you notice a Kyv taking aim near your position. He appears to be leading the target, anticipating your next movement. You should stand still.#*#",
    ForesightStill)
mq.event('OMMGaze', "#*#You feel a gaze of deadly power focusing on you.#*#", OMMGaze)
mq.event('TureBackOut', "#*#Ture roars with fury as it surveys its attackers.#*#", TureBackOut)
mq.event('TureBackIn', "#*#Ture calms and regains its focus.#*#", TureBackIn)

----- DoDH Events - DISABLED
-- DoDH Events (DISABLED)
function HatchetDuck()
end

function HatchetClose()
end

function HatchetAway()
end

function HatchetReturn()
end

function DevlinReturn()
end

function HatchetKite()
end

function HatchetSafe()
end

function HatchetResume()
end

function TrisIgnore()
end

function TrisFaceAway()
end

function TrisFaceAwayDone()
end

function TrisHeal()
end

function TrisCure()
end

function RoleyIgnore()
end

function EmpIgnore()
end

function PerfIgnore()
end

function PerfBritOne()
end

function PerfBritTwo()
end

function PerfBritThree()
end

function PerfBritFour()
end

function PerfBritFive()
end

function PerfBritSix()
end

function PerfAelfOne()
end

function PerfAelfTwo()
end

function PerfAelfThree()
end

function PerfAelfFour()
end

function PerfAelfFive()
end

function PerfSethOne()
end

function PerfSethTwo()
end

function PerfSethThree()
end

function PerfSethFour()
end

function PerfSethFive()
end

function PerfRandOne()
end

function PerfSethSix()
end

function PerfRandTwo()
end

function PerfRandThree()
end

function PerfRandFour()
end

function PerfRandFive()
end

mq.event('HatchetDuck', "#*#prepares#*#You should duck#*#", HatchetDuck)
mq.event('HatchetClose', "#*#You should hide#*#", HatchetClose)
mq.event('HatchetAway', "#*#weighted throwing axe#*#", HatchetAway)
mq.event('HatchetReturn', "#*#axe passes harmlessly#*#", HatchetReturn)
mq.event('DevlinReturn', "#*#whip passes harmlessly#*#", DevlinReturn)
mq.event('HatchetReturn2', "#*#he has no way to strike#*#", HatchetReturn)
mq.event('HatchetReturn3', "#*#reach of the throwing#*#", HatchetReturn)
mq.event('HatchetKite', "#*#locks eyes with you and snorts#*#", HatchetKite)
mq.event('HatchetKite2', "#*#He's about to charge#*#", HatchetKite)
mq.event('HatchetSafe', "#*#levels his horns at#*#", HatchetSafe)
mq.event('HatchetResume', "#*#FightHatchetNow#*#", HatchetResume)
mq.event('TrisIgnore', "#*#IgnoreTris#*#", TrisIgnore)
mq.event('TrisFaceAway', "#*#deeply into your eyes, and you feel her taking over your mind#*#", TrisFaceAway)
mq.event('TrisFaceAwayDone', "#*#averted your eyes from Tris#*#", TrisFaceAwayDone)
mq.event('TrisHeal', "#*#HealTris#*#", TrisHeal)
mq.event('TrisCure', "#*#CureTris#*#", TrisCure)
mq.event('RoleyIgnore', "#*#IgnoreRoley#*#", RoleyIgnore)
mq.event('EmpIgnore', "#*#IgnoreEmp#*#", EmpIgnore)
mq.event('PerfIgnore', "#*#IgnorePerf#*#", PerfIgnore)
mq.event('PerfBritOne', "#*#When she and I split ways,#*#", PerfBritOne)
mq.event('PerfBritTwo', "#*#it felt like the end of my days.#*#", PerfBritTwo)
mq.event('PerfBritThree', "#*#Until I suddenly,#*#", PerfBritThree)
mq.event('PerfBritFour', "#*#suddenly realized#*#", PerfBritFour)
mq.event('PerfBritFive', "#*#this life was better off alone.#*#", PerfBritFive)
mq.event('PerfBritSix', "#*#Solitude was the best gift you ever gave me.#*#", PerfBritSix)
mq.event('PerfAelfOne', "#*#Touched tenderly.#*#", PerfAelfOne)
mq.event('PerfAelfTwo', "#*#Where will you be?#*#", PerfAelfTwo)
mq.event('PerfAelfThree', "#*#Dreaming with me.#*#", PerfAelfThree)
mq.event('PerfAelfFour', "#*#Please,#*#", PerfAelfFour)
mq.event('PerfAelfFive', "#*#everybody, hear the music.#*#", PerfAelfFive)
mq.event('PerfSethOne', "#*#Another night, in eternal darkness.#*#", PerfSethOne)
mq.event('PerfSethTwo', "#*#Time bleeds like a wound that's lost all meaning.#*#", PerfSethTwo)
mq.event('PerfSethThree', "#*#It's a long winter in the swirling chaotic void.#*#", PerfSethThree)
mq.event('PerfSethFour', "#*#This is my torture,#*#", PerfSethFour)
mq.event('PerfSethFive', "#*#my pain and suffering!#*#", PerfSethFive)
mq.event('PerfSethSix', "#*#Pinch me, O' Death. . .#*#", PerfSethSix)
mq.event('PerfRandOne', "#*#Ol' Nilipus hailed from Misty Thicket.#*#", PerfRandOne)
mq.event('PerfRandTwo', "#*#Where'er he smelled Jumjum he'd pick it.#*#", PerfRandTwo)
mq.event('PerfRandThree', "#*#The halflings grew cross#*#", PerfRandThree)
mq.event('PerfRandFour', "#*#when their profits were lost,#*#", PerfRandFour)
mq.event('PerfRandFive', "#*#screamin', 'Where is that brownie? I'll kick it!'#*#", PerfRandFive)


-- PoR Events (ENABLED)
function DKOneMovement() end

function DKVertigoSetup() end

function DKVertigoSwapped() end

function DKBane() end

function AttackValikNow() end

mq.event('DKOneMovement', "#*#DKMove#*#", DKOneMovement)
mq.event('DKVertigoSetup', "#*#VertigoGroup#*#|${Me.CleanName}|#*#", DKVertigoSetup)
mq.event('DKVertigoSwapped', "#*#You find yourself somewhere new#*#", DKVertigoSwapped)
mq.event('DKBane', "#*#AyonaeBane#*#|${Me.CleanName}|#*#", DKBane)
mq.event('AttackValikNow', "#*#AttackValikNow#*#", AttackValikNow)

-- TSS Events (ENABLED)
function HearolWalls() end

function OdeenBackOut() end

function GremlinsSpread() end

function LTwoMovement() end

function HarfangeClicks() end

function BeltronTimer() end

function BeltronCorner() end

function BeltronDone() end

mq.event('HearolWalls', "#*#HearolWallsGo#*#", HearolWalls)
mq.event('OdeenBackOut', "#*#You notice a glint from the steel arrowhead as an Archer of Zek levels his bow and takes#*#",
    OdeenBackOut)
mq.event('GremlinsSpread', "#*#GremlinsSpread#*#", GremlinsSpread)
mq.event('LTwoMovement', "#*#AGMove#*#", LTwoMovement)
mq.event('HarfangeClicks', "#*#HarfangeGoClick#*#", HarfangeClicks)
mq.event('HarfangeClicks2', "#*#Harfange calls to his guards sealed in the walls#*#", HarfangeClicks)
mq.event('BeltronTimer', "#*#Guards! Come deal with these pests!#*#", BeltronTimer)
mq.event('BeltronCorner', "#*#Guards! Come deal with these pests!#*#", BeltronCorner)
mq.event('BeltronCorner2', "#*#Beltron Four Corners#*#", BeltronCorner)
mq.event('BeltronDone', "#*#Beltron Back#*#", BeltronDone)

-- Solteris Events + Mayong Mistmoore (ENABLED)
function MayongBaneSolt() end

function MayongBackOut() end

function MayongBackIn() end

function MayongBaneNow() end

function MayongBOTimer() end

function CommodusFour() end

function CommodusEight() end

function NearbyAdds() end

mq.event('MayongBaneSolt', "#*#MayongSolt#*#|${Me.CleanName}|#*#", MayongBaneSolt)
mq.event('MayongBackOut', "#*#MayongOut#*#", MayongBackOut)
mq.event('MayongBackIn', "#*#MayongIn#*#", MayongBackIn)
mq.event('MayongBaneNow', "#*#MayongBane#*#|${Me.CleanName}|#*#", MayongBaneNow)
mq.event('MayongBackOut2', "#*#The Master raises his sword, preparing#*#", MayongBackOut)
mq.event('MayongBOTimer', "#*#The Master raises his sword, preparing#*#", MayongBOTimer)
mq.event('CommodusFour', "#*#CommoFour#*#", CommodusFour)
mq.event('CommodusEight', "#*#CommoEight#*#", CommodusEight)
mq.event('NearbyAdds', "#*#NearbyAdds#*#", NearbyAdds)


-- Secrets of Faydwer Events (ENABLED)
function BreaknekDuck() end

function BreaknekDuckDone() end

function BreaknekCharge() end

function BreaknekOther() end

function BreaknekMove() end

function ClickFireStick() end

mq.event('BreaknekDuck', "#*#preparing to lob a weighted mallet in#*#", BreaknekDuck)
mq.event('BreaknekDuckDone', "#*#mallet passes harmlessly#*#", BreaknekDuckDone)
mq.event('BreaknekCharge', "#*#locks eyes with you and snorts#*#", BreaknekCharge)
mq.event('BreaknekOther', "#*#levels his horns at#*#", BreaknekOther)
mq.event('BreaknekMove', "#*#BNMove#*#", BreaknekMove)
mq.event('ClickFireStick', "#*#FireStick#*#", ClickFireStick)

function EarthTwoOut() end

function EarthTwoIn() end

mq.event('EarthTwoOut', "#*#A swirling vortex forms around Kildrukaun!#*#", EarthTwoOut)
mq.event('EarthTwoIn', "#*#Earth Back In#*#", EarthTwoIn)
mq.event('EarthTwoOut2', "#*#Earth Get Out#*#", EarthTwoOut)

function AirTwoMove() end

function KerafyrmMove() end

function KerafyrmTailRake() end

function KerafyrmCharge() end

function KerafyrmRoar() end

function KerafyrmBreath() end

mq.event('AirTwoMove', "#*#CATMove#*#", AirTwoMove)
mq.event('KerafyrmMove', "#*#KerafyrmMove#*#", KerafyrmMove)
--mq.event('KerafyrmWingFlap', "#*#Kerafyrm the Awakened flaps his wings and a mighty wind fills the chamber!#*#", KerafyrmWingFlap)
mq.event('KerafyrmTailRake', "#*#The mighty prismatic dragon prepares a terrible tail strike!#*#", KerafyrmTailRake)
mq.event('KerafyrmCharge', "#*#Kerafyrm tenses for a charge that will overwhelm his foes!#*#", KerafyrmCharge)
mq.event('KerafyrmRoar', "#*#Kerafyrm the Awakened prepares to roar!#*#", KerafyrmRoar)
mq.event('KerafyrmBreath',
    "#*#All in the room stagger forward as Kerafyrm draws in a long breath and prepares to exhale.#*#", KerafyrmBreath)


----- Seeds of Destruction - ENABLED

function Mindshear() end

function MindshearRespawn() end

mq.event("Mindshear", "You get the feeling that someone is watching you.", Mindshear)
mq.event("MindshearRespawn", "#*#the mindshear extends its power#*#", MindshearRespawn)
--mq.event("Venomlord", "#*#Kill Spirits#*#")

--mq.event("BlackburrowSplit", "#*#Split BB Now#*#")
--mq.event("BlackburrowTarget", "#*#BB Target Now#*#")
--mq.event("BrothersZek", "#*#appears to be taking aim at this#*#")
--mq.event("Kurg", "#*#boulders rain down upon#*#")
--mq.event("Towerguard", "#*#feel drawn to the#*#")
--mq.event("Brekt", "#*#shadow passes over#*#")
--mq.event("MalarianRun", "#*#You see the queen glare at you, aiming her sickening ball of fluids at you.#*#")

--mq.event("CheckTowerKey", "#*#Tower Keys?#*#")

function trotsraid.LoadRaidConfig()
    raidsactive = false
    raidtimer = 0
end

function trotsraid.RaidCheck()
    local zone = mq.TLO.Zone.ID()
    if mq.TLO.Zone.ID == 343 and not mq.TLO.eggtimer and mq.TLO.Me.Class.ShortName:find("war") then
        if mq.TLO.Spawn("a tainted egg").ID then
            mq.rs("EGG SPAWN!!")
            mq.varset("eggtimer", "30s")
        end
    end
    if zone == 89 and (raidtimer < mq.gettime() and not raidsactive) and mq.TLO.Spawn("Trakanon").ID() and mq.TLO.Me.XTarget("Trakanon").ID() and mq.TLO.Spawn("Trakanon").Distance() < 400 then
        TrakBreathOut()
    end

    if zone == 128 and mq.TLO.Spawn("Milas An`Rev").ID() and mq.TLO.Me.XTarget("Milas An`Rev").ID() and (raidtimer < mq.gettime()) and mq.TLO.Spawn("Milas An`Rev").Distance() < 400 then
        MilasOut()
    end

    if zone == 124 and mq.TLO.Spawn("Lady Nevederia").ID() and mq.TLO.Me.XTarget("Lady Nevederia").ID() and (raidtimer < mq.gettime()) and mq.TLO.Spawn("Lady Nevederia").Distance() < 250 then
        LadyNevBreathOut()
    end

    if zone == 124 and mq.TLO.Spawn("Dozekar the Cursed").ID() and mq.TLO.Me.XTarget("Dozekar the Cursed").ID() and (raidtimer < mq.gettime()) and mq.TLO.Spawn("Dozekar the Cursed").Distance() < 250 then
        DozeOut()
    end

    if zone == 162 and mq.TLO.Spawn("Vyzh`dra the Cursed").ID() and mq.TLO.Me.XTarget("Vyzh`dra the Cursed").ID() and not (raidtimer < mq.gettime()) and mq.TLO.Spawn("Vyzh`dra the Cursed").Distance() < 250 then
        CursedOut()
    end

    if zone == 163 and mq.TLO.Spawn("npc Grieg Veneficus").ID() and mq.TLO.Me.XTarget("Grieg Veneficus").ID() and not (raidtimer < mq.gettime()) and mq.TLO.Spawn("npc Grieg Veneficus").Distance() < 250 then
        GriegOut()
    end

    if zone == 222 and mq.TLO.Spawn("A Rathe Councilman").ID() and mq.TLO.Spawn("npc A Rathe Councilman").Distance() < 250 then
        RatheCouncil()
    end
    if mq.TLO.Me.Buff("Touch of Shadows").ID() or mq.TLO.Me.Song("Touch of Shadows").ID() then
        local classskip = { war = 'war', shd = 'shd', pal = 'pal' }
        if not classskip[mq.TLO.Me.Clas.ShortName()] then
            BeltronDebuff()
            if mq.TLO.Me.Buff("Touch of Shadows").ID() or mq.TLO.ME.Song("Touch of Shadows").ID() then return true end
        end
    end
    if hatchemote and mq.TLO.SpawnCount("Hatchet npc radius 5000 zradius 5000") then
        if hatchetkite then HatchetKite() end
        if hatchetsafe then HatchetSafe() end
        if hatchetduck then HatchetDuck() end
        if hatchetclose then HatchetClose() end
        if hatchetaway then HatchetAway() end
        return true
    end
    if raidsactive then return true end
end

return trotsraid
