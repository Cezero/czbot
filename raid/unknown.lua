-- Staging file: PoR, Solteris, SoF, SoD, DoDH events. Not loaded by botraid.
-- Split into zone-specific raid/<shortname>.lua files when zone ShortNames are known.

-- DoDH Events (DISABLED)
function HatchetDuck() end
function HatchetClose() end
function HatchetAway() end
function HatchetReturn() end
function DevlinReturn() end
function HatchetKite() end
function HatchetSafe() end
function HatchetResume() end
function TrisIgnore() end
function TrisFaceAway() end
function TrisFaceAwayDone() end
function TrisHeal() end
function TrisCure() end
function RoleyIgnore() end
function EmpIgnore() end
function PerfIgnore() end
function PerfBritOne() end
function PerfBritTwo() end
function PerfBritThree() end
function PerfBritFour() end
function PerfBritFive() end
function PerfBritSix() end
function PerfAelfOne() end
function PerfAelfTwo() end
function PerfAelfThree() end
function PerfAelfFour() end
function PerfAelfFive() end
function PerfSethOne() end
function PerfSethTwo() end
function PerfSethThree() end
function PerfSethFour() end
function PerfSethFive() end
function PerfRandOne() end
function PerfSethSix() end
function PerfRandTwo() end
function PerfRandThree() end
function PerfRandFour() end
function PerfRandFive() end

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

-- PoR Events
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

-- Solteris / Mayong
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

-- SoF
function BreaknekDuck() end
function BreaknekDuckDone() end
function BreaknekCharge() end
function BreaknekOther() end
function BreaknekMove() end
function ClickFireStick() end
function EarthTwoOut() end
function EarthTwoIn() end
function AirTwoMove() end
function KerafyrmMove() end
function KerafyrmTailRake() end
function KerafyrmCharge() end
function KerafyrmRoar() end
function KerafyrmBreath() end

mq.event('BreaknekDuck', "#*#preparing to lob a weighted mallet in#*#", BreaknekDuck)
mq.event('BreaknekDuckDone', "#*#mallet passes harmlessly#*#", BreaknekDuckDone)
mq.event('BreaknekCharge', "#*#locks eyes with you and snorts#*#", BreaknekCharge)
mq.event('BreaknekOther', "#*#levels his horns at#*#", BreaknekOther)
mq.event('BreaknekMove', "#*#BNMove#*#", BreaknekMove)
mq.event('ClickFireStick', "#*#FireStick#*#", ClickFireStick)
mq.event('EarthTwoOut', "#*#A swirling vortex forms around Kildrukaun!#*#", EarthTwoOut)
mq.event('EarthTwoIn', "#*#Earth Back In#*#", EarthTwoIn)
mq.event('EarthTwoOut2', "#*#Earth Get Out#*#", EarthTwoOut)
mq.event('AirTwoMove', "#*#CATMove#*#", AirTwoMove)
mq.event('KerafyrmMove', "#*#KerafyrmMove#*#", KerafyrmMove)
mq.event('KerafyrmTailRake', "#*#The mighty prismatic dragon prepares a terrible tail strike!#*#", KerafyrmTailRake)
mq.event('KerafyrmCharge', "#*#Kerafyrm tenses for a charge that will overwhelm his foes!#*#", KerafyrmCharge)
mq.event('KerafyrmRoar', "#*#Kerafyrm the Awakened prepares to roar!#*#", KerafyrmRoar)
mq.event('KerafyrmBreath', "#*#All in the room stagger forward as Kerafyrm draws in a long breath and prepares to exhale.#*#", KerafyrmBreath)

-- SoD
function Mindshear() end
function MindshearRespawn() end

mq.event("Mindshear", "You get the feeling that someone is watching you.", Mindshear)
mq.event("MindshearRespawn", "#*#the mindshear extends its power#*#", MindshearRespawn)

return {}
