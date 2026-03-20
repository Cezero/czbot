# Hook: doDebuff

**Priority:** 1000  
**Provider:** botdebuff

## Logic

Runs the phase-first spell check for the **debuff** section. Phase order: charm, notmatar, matar, named. Charm recasts and charm targeting are evaluated first; then non-MA mobs (adds), then MA target, then named MA target.

```mermaid
flowchart TB
    Start[doDebuff] --> Guards{!dodebuff or no debuff spells or !MobList 1?}
    Guards -->|Yes| End[return]
    Guards -->|No| Zone{non-combat zone?}
    Zone -->|No| Status[statusMessage = Debuff Check]
    Status --> DebuffCheck[DebuffCheck runPriority]
    DebuffCheck --> RunPhase[RunPhaseFirstSpellCheck debuff DEBUFF_PHASE_ORDER]
    RunPhase --> PhaseLoop[phase order: charm notmatar matar named]
```

DebuffEval (per spell index): charm recast request → charm.EvalTarget → DebuffEvalMatar → DebuffEvalNotmatar → DebuffEvalNamedMatar. Bands control matar, notmatar, named, mobMin/mobMax. BeforeCast: recast check; for matar set engageTargetId (if not offtank) and pet attack. afterCast can increment resist counter and disable spell for spawn after N resists. Spell completion and interrupt (including MQ2Cast) are described in [Spell casting flow](spell-casting-flow.md); see charm module for charm-specific logic.

## See also

- [README](README.md)
- [Spell casting flow](spell-casting-flow.md)
- [Debuffing configuration](../debuffing-configuration.md)
- [Spell targeting and bands](../spell-targeting-and-bands.md)
