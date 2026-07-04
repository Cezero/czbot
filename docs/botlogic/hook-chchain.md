# Hook: chchainTick

**Priority:** 500  
**Provider:** lib.chchain

## Logic

Runs when runState is **chchain**. Cast is started by **`chchain_baton`** on the czactor channel (or local kickoff). The tick polls the cast: baton at delay, cancel window, fizzle/corpse handling.

```mermaid
flowchart TB
    Start[chchainTick] --> State{runState == chchain?}
    State -->|No| End[return]
    State -->|Yes| Fizzle{CAST_FIZZLE?}
    Fizzle -->|Yes| Recast[recast CH]
    Fizzle -->|No| Corpse{target corpse?}
    Corpse -->|Yes| Baton[passBaton czactor]
    Corpse -->|No| Casting{still casting?}
    Casting -->|Yes| Delay{broadcastDelayMs elapsed?}
    Delay -->|Yes| Baton
    Casting -->|No| Done[clicky optional clear state]
    Casting -->|Yes| CancelWindow{HP >= threshold in cancel window?}
    CancelWindow -->|Yes| StopCast[stopcast clear]
```

**OnBaton:** czactor `chchain_baton` for this cleric → target first alive in-range tank from `mt_list` → cast Complete Heal → set runState with tank name and cast start time.

## See also

- [CHChain configuration](../chchain-configuration.md)
- [README](README.md)
