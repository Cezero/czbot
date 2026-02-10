# Nuking Configuration

This document explains how to set up **nuking** (direct-damage spells on the tank’s or MA’s target, or on adds). In CZBot, nuking is configured using the **debuff** system: you add nuke spells as debuff entries and use **bands** to choose which mobs they hit.

## Overview

- **Nuking = debuffs.** There is no separate “nuke” section. You add your nuke spell(s) under **`config.debuff.spells`** and set **bands** to **tanktar** (MA/tank’s target), and optionally **notanktar** (adds) or **named** (named only).
- **Master switch:** Turn on debuffing with **`settings.dodebuff`** (or `/cz dodebuff on`).
- For all debuff options (recast, delay, charm, gem types, etc.), see [Debuffing configuration](debuffing-configuration.md).
- See [Spell targeting and bands](spell-targeting-and-bands.md) for how tanktar and notanktar interact and evaluation order.

---

## How to configure nuking

1. **Enable debuffing:** In config set **`settings.dodebuff`** to `true`, or run `/cz dodebuff on`.

2. **Add a debuff (nuke) spell entry** under **`config.debuff.spells`**:
   - **gem** — Spell gem number (1–12) or `'item'`, `'alt'`, `'disc'`.
   - **spell** — Exact spell name (e.g. `"Chaos Flame"`).
   - **enabled** — Optional; default is `true`. When `false`, the spell is not used.
   - **mintar** / **maxtar** — Optional; set in **bands**. Camp mob-count gate (only consider when mob count is in range). E.g. **mintar 2** = at least two mobs in camp. See [Debuffing configuration](debuffing-configuration.md).
   - **bands** — For nuking the main target use **tanktar**. For multi-target or add nuking add **notanktar**. For named-only nukes add **named**. Use **min**/ **max** to restrict by mob HP % (e.g. nuke only when mob is 5–100% HP).

3. **Optional:** **recast** (resist count before disabling for that spawn), **delay** (ms before same spell can be used again), **alias** (for `/cz cast <alias>`), **minmana**.

**Example: single-target nuke on tank target**

```lua
debuff = {
  spells = {
    {
      gem = 1,
      spell = 'Chaos Flame',
      alias = 'nuke',
      minmana = 0,
      bands = {
        { validtargets = { 'tanktar' }, min = 5, max = 100 }
      },
      charmnames = '',
      recast = 0,
      delay = 0
    }
  }
}
```

**Example: nuke tank target and adds**

Use **tanktar** and **notanktar** in the same band (or separate bands) so the nuke can fire on the MA’s target and on other mobs in the list:

```lua
bands = {
  { validtargets = { 'tanktar', 'notanktar' }, min = 10, max = 100 }
}
```

---

## Runtime control

- **Toggle debuffing (nuking):** `/cz dodebuff on` or `/cz dodebuff off`.
- **Cast by alias:** `/cz cast <alias> [target]` — cast the nuke by alias. `/cz cast <alias> on` or `off` to enable or disable the spell (**enabled**).
- **Add a spell slot:** `/cz addspell debuff <position>`.

---

## See also

For full debuff options (recast, delay, charm, immune check, level checks, etc.), see [Debuffing configuration](debuffing-configuration.md).
