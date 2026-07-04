# Hook: doEvents

**Priority:** 200  
**Provider:** Built-in (botlogic.lua)  
**runWhenDead:** true

## Logic

```mermaid
flowchart LR
    A[doEvents] --> B[mq.doevents]
```

The hook calls **mq.doevents()**, which processes the MQ event queue. **`botlogic.mainloop`** also calls `mq.doevents()` at the start of each iteration (before hooks) so chat events are not delayed until priority 200. The doEvents hook drains any events that arrived during the rest of the tick. All game events registered in botevents.BindEvents() (and chchain/follow) are dispatched from here. Because doEvents has **runWhenDead = true**, it still runs when the character is DEAD or HOVER so that zone, slain, and other events continue to be processed.

## See also

- [README](README.md)
- [Events](events.md)
