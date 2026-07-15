# Hook: doHeal

**Priority:** 900  
**Provider:** botheal

## Logic

Runs the phase-first spell check for the **heal** section in two resource passes. **Pass 1 (HP)** runs living HP phases (self, groupheal, tank, offtank, groupmember, pc, mypet, pet, xtgt) and a dedicated **corpse** sub-pass whose position depends on combat rez. **Pass 2 (Mana)** runs the non-corpse phases only.

```mermaid
flowchart TB
    Start[doHeal] --> Guards{!doheal or no heal config?}
    Guards -->|Yes| End[return]
    Guards -->|No| Status[statusMessage = Heal Check]
    Status --> HealCheck[HealCheck runPriority]
    HealCheck --> CombatDefer{Combat rez deferred?}
    CombatDefer -->|No safe rez| CorpseFirst[Pass 1a: corpse only HP]
    CorpseFirst --> CorpseCast{Cast started?}
    CorpseCast -->|Yes| End
    CorpseCast -->|No| CorpseHold{Pending corpse hold?}
    CorpseHold -->|Yes| End
    CorpseHold -->|No| HpPass[Pass 1b: living HP phases]
    CombatDefer -->|Yes| HpPass
    HpPass --> HpCast{Cast started?}
    HpCast -->|Yes| End
    HpCast -->|No| AfterHp{Combat defer and corpses?}
    AfterHp -->|Yes| CorpseLast[Pass 1c: corpse only HP]
    CorpseLast --> ManaPass[Pass 2: mana spells only]
    AfterHp -->|No| ManaPass
    ManaPass --> End
```

HealCheck builds context (tank, bots, spell ranges, etc.) and calls `RunPhaseFirstSpellCheck` as needed:

1. **Safe rez corpse pass** — only when combat rez is **not** deferred: **corpse** phase with HP spells (rez) first.
2. **HP hold** — if eligible corpses remain on the safe-rez path (not combat-deferred), the heal hook returns without running living HP phases (retries corpse next tick).
3. **HP pass** — living phases (self through xtgt) with HP spells.
4. **Combat rez corpse pass** — when **inCombat** corpse spell + mobs in camp: **corpse** after living HP if no cast started (no hold).
5. **Mana pass** — same non-corpse phases with **healResource** `'mana'` spells (e.g. cannibalize); runs only if prior passes did not start a cast.

When corpses are pending on the **safe rez** path and a heal resume cursor points at a later phase, the resume is cleared so corpse is re-evaluated. Combat rez does not clear a living-heal resume. Each pass uses heal-specific `getTargetsForPhase`, filtered `getSpellIndicesForPhase`, and `targetNeedsSpell` (HP bands, corpse rez filters, group/xt). Each phase returns targets (e.g. corpse IDs, self, tank, group members); spells that have that phase in their bands are tried in order; first valid (beforeCast, immuneCheck, PreCondCheck) triggers CastSpell. Resume after a cast continues the pass matching the stored spell's resource type. Spell completion and interrupt (including MQ2Cast) are described in [Spell casting flow](spell-casting-flow.md).

## See also

- [README](README.md)
- [Spell casting flow](spell-casting-flow.md)
- [Healing configuration](../healing-configuration.md)
- [Spell targeting and bands](../spell-targeting-and-bands.md)
