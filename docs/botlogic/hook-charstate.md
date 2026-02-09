# Hook: charState

**Priority:** 300  
**Provider:** Built-in (botlogic.lua)  
**runWhenDead:** true

## Logic

CharState runs a long sequence of per-tick checks. Order of operations:

```mermaid
flowchart TB
    Start[CharState] --> Startup{args.startup?}
    Startup -->|Yes| HoverStart[hover/corpse check terminate]
    Startup -->|Yes| MoveStop[moving/combat stop]
    Startup -->|No| Loot
    HoverStart --> Loot
    MoveStop --> Loot
    Loot[LootWnd open? /clean]
    Loot --> Duck[ducking? /keypress duck]
    Duck --> CampReturn{runState == camp_return?}
    CampReturn -->|Yes| ClearCamp[clear if not moving or deadline]
    CampReturn -->|No| CampLeash[campstatus and beyond acleash? MakeCamp return]
    ClearCamp --> FollowStand
    CampLeash --> FollowStand
    FollowStand[followid and sitting and far? /stand]
    FollowStand --> Sit[dosit and not moving/cast/combat? sit check]
    Sit --> Cursor[cursor and inv? autoinv or OutOfSpace]
    Cursor --> Mount[domount? MountCheck]
    Mount --> Dead{DEAD or HOVER?}
    Dead -->|Yes| SetDead[setRunState dead, HoverEchoTimer, HoverTimer, Event_Slain]
    Dead -->|No| ClearDead{runState dead? clearRunState}
    SetDead --> Corpse
    ClearDead --> Corpse
    Corpse[target corpse? attack off, target clear, stick off]
    Corpse --> Feign[FEIGN? /stand]
    Feign --> Twist[Twist active? /twist stop]
    Twist --> Engage{engageTargetId and target match?}
    Engage -->|No| AttackOff[attack off, pet back]
    Engage -->|Yes| MobList{ MobList 1 and engageTargetId?}
    AttackOff --> MobList
    MobList -->|No| ClearEngage[engageTargetId = nil]
    MobList -->|Yes| GM
    ClearEngage --> GM
    GM[GMCheck? Event_GMDetected]
    GM --> Pet[pet ID change? /pet leader]
    Pet --> End[end]
```

- **Startup:** On first run with arg `startup`: if hovering/corpse, set terminate; stop nav/stick; if combat, attack off.
- **Camp return:** If runState is camp_return and (not moving or deadline passed), clearRunState. If campstatus and beyond acleash, call botmove.MakeCamp('return').
- **Sit:** If dosit, not moving, no cast, no combat, no autofire: if follow and far skip sit; else if mana/endur in band (and not 40% HP with mobs) then /sit on.
- **Dead:** If DEAD or HOVER, set runState 'dead', set HoverEchoTimer if unset, and if HoverTimer passed call Event_Slain. If we were dead and are now alive, clearRunState.
- **Engage:** If we have no engageTargetId or our target is not engageTargetId, attack off and pet back. If no MobList[1] and engageTargetId, clear engageTargetId.
- **Pet:** If pet ID changed (new pet or different), set MyPetID and /pet leader.

## See also

- [README](README.md)
- [Run state machine](run-state-machine.md) — dead, camp_return
- [Events](events.md) — Event_Slain, Event_GMDetected
- [Movement and misc state](movement-and-misc.md) — MakeCamp return
