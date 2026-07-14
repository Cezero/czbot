# Hook: chchainTick

**Priority:** 500  
**Provider:** lib.chchain

## Logic

Runs whenever **`doChchain` and `chainActive`** (not only while casting). Each bot schedules its own Complete Heal from a shared start clock — no baton messages. Casts use **`lib.casting`** (`/cast` gem).

While **exclusive mode** is on (`chchainExclusive`), [`hookregistry.runNormalHooks`](../../lib/hookregistry.lua) only runs hooks with priority ≤ 500 and skips `runWhenBusy` (camp/follow).

```mermaid
flowchart TB
    Start[chchainTick] --> Active{doChchain and chainActive?}
    Active -->|No| CastOnly{runState == chchain?}
    CastOnly -->|Yes| Poll[castPollTick]
    CastOnly -->|No| End[return]
    Active -->|Yes| Slot[slotScheduleTick]
    Slot --> Due{"cycle > last and timeInto >= slotTime?"}
    Due -->|Yes| Cast[startCast catch-up ok]
    Due -->|No| Poll2[castPollTick]
    Cast --> Poll2
    Poll2 --> Fizzle{CAST_FIZZLE?}
    Fizzle -->|Yes| Recast[recast Complete Heal]
    Fizzle -->|No| Corpse{target corpse?}
    Corpse -->|Yes| Clear[interrupt clear]
    Corpse -->|No| Casting{still casting?}
    Casting -->|Yes| PreLand{preCastHpCheckMs elapsed?}
    PreLand -->|Yes and HP high| StopCast[interrupt]
    Casting -->|No| Done[clicky optional clear]
```

**Start/kickoff:** czactor `chchain_control` → `beginSchedule` (interrupt other casts, clear runState, set exclusive + `chainStart`). Slot *N* fires once per cycle when `timeIntoCycle >= (N-1)*delayMs`.

## See also

- [CHChain configuration](../chchain-configuration.md)
- [Spell casting flow](spell-casting-flow.md)
- [README](README.md)
