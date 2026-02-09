# Debuffing Configuration

This document explains how to configure the bot’s **debuffing** behavior: which detrimental spells are cast on which mobs (tank target, adds, named) and options such as charm, recast, and delay. **Nuking**, **mezzing**, and **melee combat abilities** use this same debuff system; see [Nuking configuration](nuking-configuration.md), [Mezzing configuration](mezzing-configuration.md), and [Melee combat abilities](melee-combat-abilities.md) for those use cases.

## Overview

- **Master switch:** Debuffing runs only when **`settings.dodebuff`** is `true`. Default is `false`.
- **Mob list:** The bot builds a list of valid mobs (within **acleash** and **zradius** of camp, filtered by **TargetFilter**). Debuffs are only cast on mobs in this list.
- **Evaluation order:** The bot evaluates **phases** in order: charm (if **charmnames** is set) → **tanktar** (MA/tank’s current target) → **notanktar** (other mobs / adds) → **named** (named mobs that are the tank target). For each phase it considers each mob target and checks **all** debuff spells that have that phase in their bands before moving on. For a detailed explanation of spell targeting logic and how band tags interact, see [Spell targeting and bands](spell-targeting-and-bands.md).
- **Melee combat abilities** (disciplines, kick/bash-style abilities) use this same debuff system with **gem** `'disc'` or `'ability'`; see [Melee combat abilities](melee-combat-abilities.md).

---

## Config file reference

### Settings

| Option | Default | Purpose |
|--------|--------|---------|
| **dodebuff** | `false` | Boolean. Enables or disables the debuff loop. |

### Debuff section

All debuff options are under **`config.debuff.spells`**. Each spell entry can have:

| Field | Purpose |
|-------|---------|
| **gem** | Spell gem number (1–12), or `'item'`, `'alt'`, `'disc'`, `'ability'`, `'script'`. |
| **spell** | Spell name (or item name if gem is `'item'`). |
| **alias** | Optional. Short name for `/cz cast <alias>`. Pipe-separated for multiple. |
| **announce** | Optional. If true, announce when casting. |
| **minmana** | Minimum mana (absolute) to cast. |
| **enabled** | Optional. When `true` or missing, the spell is used. When `false`, the spell is not used. Default is `true`. |
| **tarcnt** | Optional. When set, the spell is only considered when total mobs in camp is **≥ tarcnt**. The count includes the MA’s target plus all adds (the full camp list). So e.g. **tarcnt 2** = at least 2 mobs in camp = one add. When omitted, no mob-count minimum is applied. |
| **bands** | Which mobs and at what HP %. See [Debuff bands](#debuff-bands) below. |
| **charmnames** | Optional. Comma-separated mob **names**. When set, the bot can target those mobs for charm (recast when charm breaks). Before casting charm, the bot sends **pet leave** if your pet is charmed. |
| **recast** | Optional. After this many resists on the **same** spawn, the bot disables this spell for that spawn for a duration. 0 = no limit. |
| **delay** | Optional. Delay (ms) before the spell can be used again after cast (per-index/spell). |
| **precondition** | Optional. When missing or not set, defaults to `true` (cast is allowed). When **defined**: **boolean** — `true` = allow, `false` = skip; **string** — Lua script with `mq` and `EvalID` in scope; return truthy to allow the cast. |

### Debuff bands

Bands define **which mobs** and **at what HP %** the debuff is allowed. Debuff uses **targetphase** only (no validtargets; target is always mobs). Each band has:

- **targetphase:** One or more of: **tanktar**, **notanktar**, **named**.
  - **tanktar** — The Main Tank’s (or MA’s) current target.
  - **notanktar** — Any other mob in the list (adds).
  - **named** — Only named mobs; when used with tanktar, only the tank target if it is named.
- **min** / **max:** Mob HP % range (0–100). The mob’s HP must be in this range to be considered.

**Example: nuke on tank target and slow on adds**

```lua
['debuff'] = {
  ['spells'] = {
    {
      ['gem'] = 1,
      ['spell'] = 'Chaos Flame',
      ['alias'] = 'nuke',
      ['minmana'] = 0,
      ['tarcnt'] = 10,
      ['bands'] = {
        { ['targetphase'] = { 'tanktar' }, ['min'] = 5, ['max'] = 100 }
      },
      ['charmnames'] = '',
      ['recast'] = 0,
      ['delay'] = 0,
      ['precondition'] = true
    },
    {
      ['gem'] = 2,
      ['spell'] = 'Turgur\'s Insects',
      ['alias'] = 'slow',
      ['minmana'] = 0,
      ['tarcnt'] = 5,
      ['bands'] = {
        { ['targetphase'] = { 'notanktar' }, ['min'] = 20, ['max'] = 100 }
      },
      ['charmnames'] = '',
      ['recast'] = 2,
      ['delay'] = 0,
      ['precondition'] = true
    }
  }
}
```

---

## Charm (special case)

When **charmnames** is set to a comma-separated list of mob names, the debuff logic can target those mobs for charm. When charm breaks, the bot can request a recast on that spawn. Before casting charm, the bot issues **pet leave** so your current pet is released. Charm is a debuff entry like any other; the only difference is the use of **charmnames** and the pet-leave/recast behavior. See also [Pets configuration](pets-configuration.md) for charm in context.

---

## MQ2Cast and -maxtries

When the **MQ2Cast** plugin is loaded, the bot uses `/casting` for debuff spells and appends **`-maxtries|2`** so MQ2Cast may retry once on resist/fizzle before returning a final result. The bot still sees one “logical” cast completion: **recast** (disable after N resists per spawn) and **afterCast** logic run once per cast using the final `Cast.Result`. Without MQ2Cast, the bot uses `/cast` and chat events (CastRst) for resist.

---

## Runtime control

- **Toggle debuffing:** `/cz dodebuff on` or `/cz dodebuff off` (or `/cz dodebuff` to toggle).
- **Cast by alias:** `/cz cast <alias> [target]` — cast a debuff by alias. Use `/cz cast <alias> on` or `off` to enable or disable that spell (**enabled**).
- **Add a spell slot:** `/cz addspell debuff <position>` — insert a new debuff entry at the given position.

---

## Behavior summary

- **Immune check:** The bot can skip mobs marked immune to the spell (per zone/target in immune data).
- **Before cast (tanktar):** When casting on the tank target, the bot may set **engageTargetId** to that mob (so melee/pet follow) and send pet attack if **petassist** is on.
- **Recast:** After **recast** resists on the same spawn, the spell is disabled for that spawn for a duration.
- **Level:** For some spell types (e.g. Enthrall/mez), the spell’s **MaxLevel** is checked against the mob’s level; over-level mobs are skipped.

---

## See also

- [Nuking configuration](nuking-configuration.md) — Configure nukes as debuffs (typically **tanktar**, optionally **notanktar**).
- [Mezzing configuration](mezzing-configuration.md) — Configure mez as debuffs (typically **notanktar**; **charmnames** for charm mez).
- [Melee combat abilities](melee-combat-abilities.md) — Configure disciplines and /doability-style abilities as debuffs (typically **tanktar**).
