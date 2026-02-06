# Curing Configuration

This document explains how to configure the bot’s **curing** behavior: which cure spells are used, what types of detrimental effects they remove, and who gets cured. It is intended for operators who set up the config file and use runtime commands.

## Overview

- **Master switch:** Curing runs only when **`settings.docure`** is `true`. Default is `false`.
- **Cure types:** Each spell entry has **curetype**: either **all** (any detrimental) or space-separated types (e.g. **poison**, **disease**, **curse**, **corruption**). The bot only considers the spell when the target has a matching effect.
- **Priority cure:** When **prioritycure** is `true`, the cure loop runs in a higher-priority hook (before the normal cure hook), so cures can be processed before heals. After casting a cure, the bot may re-evaluate to cure again if needed.

---

## Config file reference

### Settings

| Option | Default | Purpose |
|--------|--------|---------|
| **docure** | `false` | Boolean. Enables or disables the cure loop. |

### Cure section (top-level)

| Option | Default | Purpose |
|--------|--------|---------|
| **prioritycure** | `false` | When true, cure runs in a higher-priority hook and can re-evaluate after each cast so multiple cures fire before heals. |

### Cure spell entries

Each entry in **`config.cure.spells`** can have:

| Field | Purpose |
|-------|---------|
| **gem** | Spell gem number (1–12), or `'item'`, `'alt'`, `'disc'`, `'script'`. |
| **spell** | Spell name (or item name if gem is `'item'`). |
| **alias** | Optional. Short name for `/cz cast <alias>`. Pipe-separated for multiple. |
| **announce** | Optional. If true, announce when casting. |
| **minmana** | Minimum mana (absolute) to cast. |
| **curetype** | **all** or space-separated types: e.g. **poison**, **disease**, **curse**, **corruption**. The spell is only used when the target has at least one matching detrimental. |
| **tarcnt** | Must be > 0 for the spell to be used. |
| **bands** | Who can be cured. See [Cure bands](#cure-bands) below. |
| **priority** | Optional. Affects post-cast behavior when **prioritycure** is true. |
| **precondition** | Optional. When false, the spell is skipped. |

### Cure bands

Bands use **class** only (no min/max). Each band is a table with **class** = list of tokens. Tokens include:

- **self** — Cure yourself.
- **tank** — Main Tank (from TankName).
- **group** — Any group member (in addition to class filters).
- **Class shorts** — e.g. `war`, `clr`, `shd`, `pal`, `shm`, `dru`, `rng`, `mnk`, `rog`, `brd`, `bst`, `ber`, `wiz`, `mag`, `enc`, `nec`. Restricts cures to those classes.

Evaluation order: **self** → **tank** → **group** (by class) → other bots by **class**.

**Example: poison/disease and all**

```lua
['cure'] = {
  ['prioritycure'] = true,
  ['spells'] = {
    {
      ['gem'] = 5,
      ['spell'] = 'Counteract Poison',
      ['alias'] = 'curepoison',
      ['minmana'] = 0,
      ['curetype'] = 'poison',
      ['tarcnt'] = 1,
      ['bands'] = {
        { ['class'] = { 'self', 'tank', 'war', 'shd', 'pal', 'clr', 'shm', 'dru', 'rng', 'mnk', 'rog', 'brd', 'bst', 'ber' } }
      },
      ['priority'] = false,
      ['precondition'] = true
    },
    {
      ['gem'] = 6,
      ['spell'] = 'Counteract Disease',
      ['alias'] = 'curedisease',
      ['minmana'] = 0,
      ['curetype'] = 'disease',
      ['tarcnt'] = 1,
      ['bands'] = {
        { ['class'] = { 'self', 'tank', 'group' } }
      },
      ['priority'] = false,
      ['precondition'] = true
    }
  }
}
```

---

## Runtime control

- **Toggle curing:** `/cz docure on` or `/cz docure off` (or `/cz docure` to toggle).
- **Cast by alias:** `/cz cast <alias> [target]` — cast a cure by alias. Use `/cz cast <alias> on` or `off` to enable or disable that spell (tarcnt).
- **Add a spell slot:** `/cz addspell cure <position>` — insert a new cure entry at the given position.

---

## Behavior summary

- **prioritycure:** When **prioritycure** is true, the cure loop runs in a higher-priority hook (before the main cure hook and before heals). After a cure is cast, the bot can re-evaluate and cast another cure if a target still has a matching detrimental. This helps clear multiple effects or multiple targets quickly.
- **Distance:** Targets must be within the spell’s range (and in group where applicable) to be considered.
