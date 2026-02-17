# Curing Configuration

This document explains how to configure the bot’s **curing** behavior: which cure spells are used, what types of detrimental effects they remove, and who gets cured. It is intended for operators who set up the config file and use runtime commands.

## Overview

- **Master switch:** Curing runs only when **`settings.docure`** is `true`. Default is `false`.
- **Cure types:** Each spell entry has **curetype**: a **table of strings**, e.g. **{ 'all' }** (any detrimental) or **{ 'poison', 'disease' }**. Default when unset or empty is **{ 'all' }**. The bot only considers the spell when the target has a matching effect.
- **Priority cure:** Spells that include the **priority** phase in a band’s **targetphase** run in a separate, higher-priority hook (before the normal cure hook and before heals). No top-level flag is required: if at least one cure spell has **priority** in its band, the priority pass runs. After casting a cure in the main pass, the bot may re-evaluate to cure again if needed.

---

## Config file reference

### Settings

| Option | Default | Purpose |
|--------|--------|---------|
| **docure** | `false` | Boolean. Enables or disables the cure loop. |

### Cure section (top-level)

The cure section has **spells** only. Priority behavior is controlled per spell via bands (see [Cure bands](#cure-bands)).

### Cure spell entries

Each entry in **`config.cure.spells`** can have:

| Field | Purpose |
|-------|---------|
| **gem** | Spell gem number (1–12), or `'item'`, `'alt'`, `'disc'`, `'script'`. |
| **spell** | Spell name (or item name if gem is `'item'`). |
| **alias** | Optional. Short name for `/cz cast <alias>`. Pipe-separated for multiple. |
| **announce** | Optional. If true, announce when casting. |
| **minmana** | Minimum mana (absolute) to cast. |
| **curetype** | Table of strings: e.g. **{ 'all' }** or **{ 'poison', 'disease', 'curse', 'corruption' }**. Default **{ 'all' }** when unset. The spell is only used when the target has at least one matching detrimental. |
| **enabled** | Optional. When `true` or missing, the spell is used. When `false`, the spell is not used. Default is `true`. |
| **bands** | Who can be cured. See [Cure bands](#cure-bands) below. |
| **priority** | Deprecated. Use the **priority** phase in a band’s **targetphase** instead (see [Cure bands](#cure-bands)). |
| **precondition** | Optional. When missing or not set, defaults to `true` (cast is allowed). When **defined**: **boolean** — `true` = allow, `false` = skip; **string** — Lua script with `mq` and `EvalID` in scope; return truthy to allow the cast. |

### Cure bands

Bands use **targetphase** (phase stages) and **validtargets** (classes or `all`). Each band is a table with **targetphase** = list of stage tokens and **validtargets** = list of class tokens or `all`. No min/max for cures.

- **targetphase** tokens: **self**, **tank**, **groupcure**, **groupmember**, **pc**, and **priority**. **groupmember** = in-group only (peers first, then non-peer group members via Group TLO); **pc** = all peers by class. **groupcure** = group AE cure (spell targets group; cast when at least **tarcnt** group members have a matching detrimental; optional **tarcnt** on spell entry, default 1). **priority** = this spell runs in the priority cure pass (before the main cure pass and before heals); include it alongside other phases (e.g. `{ 'priority', 'tank', 'groupmember' }`) so the spell runs in both the priority pass and the main pass for those targets.
- **validtargets**: Class shorts (e.g. `war`, `clr`, `shd`, …) or `all`. Absent = all classes.

**Phase order and how cures are chosen**

The bot uses the same phase-first logic as heal and buff. The **phase order** for the main cure pass is: self, tank, groupcure, groupmember, pc. For each phase, the bot gets the list of targets for that phase, then for **each target** checks **all** cure spells that have that phase in their bands (in config order). The first spell that the target needs (matching detrimental, in range) is cast. For non-peers (e.g. non-bot group members or tank), detrimentals are only known from the **Spawn** TLO after you have targeted that spawn until **Spawn.BuffsPopulated** is true (same as buffs/mobs). **tank** can be a non-bot when explicitly named (TankName); we only cure the configured tank when not a peer. See [Out-of-group peers](out-of-group-peers.md).

**Example: poison/disease with priority tank/groupmember**

```lua
cure = {
  spells = {
    {
      gem = 5,
      spell = 'Counteract Poison',
      alias = 'curepoison',
      minmana = 0,
      curetype = { 'poison' },
      bands = {
        { targetphase = { 'priority', 'self', 'tank', 'groupmember', 'pc' }, validtargets = { 'war', 'shd', 'pal', 'clr', 'shm', 'dru', 'rng', 'mnk', 'rog', 'brd', 'bst', 'ber' } }
      }
    },
    {
      gem = 6,
      spell = 'Counteract Disease',
      alias = 'curedisease',
      minmana = 0,
      curetype = { 'disease' },
      bands = {
        { targetphase = { 'self', 'tank', 'groupmember', 'pc' }, validtargets = { 'all' } }
      }
    }
  }
}
```

Spells that include **priority** in **targetphase** run in the priority pass (before heals); the first spell above runs in both the priority pass and the main cure pass for its targets.

---

## Runtime control

- **Toggle curing:** `/cz docure on` or `/cz docure off` (or `/cz docure` to toggle).
- **Cast by alias:** `/cz cast <alias> [target]` — cast a cure by alias. Use `/cz cast <alias> on` or `off` to enable or disable that spell (**enabled**).
- **Add a spell slot:** `/cz addspell cure <position>` — insert a new cure entry at the given position.

---

## Behavior summary

- **Priority pass:** If at least one cure spell has **priority** in a band’s **targetphase**, a separate priority cure pass runs before the main cure hook and before heals. Only those spells run in that pass; the main cure pass then runs (skipping the priority phase) so the same spell can run again for its other phases. No top-level flag is required.
- **Re-eval after cast:** After casting a cure in the main pass, the bot can re-evaluate and cast another cure if a target still has a matching detrimental.
- **Distance:** Targets must be within the spell’s range (and in group where applicable) to be considered.
