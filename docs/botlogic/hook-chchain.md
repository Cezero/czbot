# Hook: chchainTick

**Priority:** 500  
**Provider:** lib.chchain

## Logic

Runs when runState is **chchain**. Cast is started by **`chchain_baton`** on the czactor channel (or local kickoff) via **`lib.casting`** (`/cast` gem), not MQ2Cast. The tick calls `casting.tick()`, then polls the cast: baton at delay, cancel window, fizzle/corpse handling.

```mermaid
flowchart TB
    Start[chchainTick] --> TickCast[casting.tick]
    TickCast --> State{runState == chchain?}
    State -->|No| End[return]
    State -->|Yes| Fizzle{CAST_FIZZLE?}
    Fizzle -->|Yes| Recast["casting.start Complete Heal"]
    Fizzle -->|No| Corpse{target corpse?}
    Corpse -->|Yes| Baton[passBaton czactor]
    Corpse -->|No| Casting{still casting?}
    Casting -->|Yes| Delay{broadcastDelayMs elapsed?}
    Delay -->|Yes| Baton
    Casting -->|No| Done[clicky optional clear state]
    Casting -->|Yes| CancelWindow{HP >= threshold in cancel window?}
    CancelWindow -->|Yes| StopCast[casting.interrupt clear]
```

**OnBaton:** czactor `chchain_baton` for this cleric → target first alive in-range tank from `mt_list` → `casting.start` Complete Heal → set runState with tank name and cast start time.

## See also

- [CHChain configuration](../chchain-configuration.md)
- [Spell casting flow](spell-casting-flow.md)
- [README](README.md)
