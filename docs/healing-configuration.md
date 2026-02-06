# Healing Configuration

This document explains how to configure the bot’s **healing** behavior: which spells are used, who gets healed and at what HP, resurrection, and related options. It is intended for operators who set up the config file and use runtime commands.

## Overview

- **Master switch:** Healing runs only when **`settings.doheal`** is `true`. Default is `false`.
- **Heal target:** Healers always prioritize the **Main Tank** (from TankName). The heal loop evaluates targets in a fixed order: corpse (rez), self, group AE, tank, other PCs by class, your pet, other pets, then extended targets (XT).
- **Where to configure:** Set **`settings.doheal`** in the `settings` section and all heal options under the **`heal`** section. See [Config file reference](#config-file-reference) below.

---

## Config file reference

### Settings

| Option | Default | Purpose |
|--------|--------|---------|
| **doheal** | `false` | Boolean. Enables or disables the heal loop. When `true`, the `heal` section is used. |

### Heal section (top-level)

All heal options live under **`config.heal`**. Spell entries are in **`heal.spells`**.

| Option | Default | Purpose |
|--------|--------|---------|
| **rezoffset** | 0 | When multiple corpses are in range, skip this many before picking a rez target (e.g. rez the 2nd corpse when rezoffset is 1). |
| **interruptlevel** | 0.80 | Used when deciding whether to interrupt a cast (e.g. for a higher-priority heal). Target HP threshold. |
| **xttargets** | 0 | Comma- or digit-separated extended target slot numbers (e.g. `1,2,3` or `123`) that are valid for heals. When set, spells with band **xtgt** can heal those XTarget slots. |

### Heal spell entries

Each entry in **`heal.spells`** can have:

| Field | Purpose |
|-------|---------|
| **gem** | Spell gem number (1–12), or `'item'`, `'alt'`, `'disc'`, `'script'` for non-gem casts. |
| **spell** | Spell name (or item name if gem is `'item'`). |
| **alias** | Optional. Short name for `/cz cast <alias>`. Pipe-separated for multiple aliases. |
| **announce** | Optional. If true, announce when casting (e.g. to group). |
| **minmana** | Minimum mana (absolute) to cast. |
| **minmanapct** / **maxmanapct** | Your mana % must be within this range to use this spell (default 0–100). |
| **tarcnt** | Must be > 0 for the spell to be used. For group/AE heals, minimum number of group members in HP band to trigger. |
| **bands** | Who and at what HP % this spell applies. See [Heal bands](#heal-bands) below. |
| **priority** | If true, after casting the bot re-checks that the target still needs the heal (validate). |
| **precondition** | Optional. When false, the spell is skipped. |

### Heal bands

Bands define **who** can receive the spell and **at what HP %**. Each band has:

- **class:** List of target types. One or more of: `pc`, `pet`, `grp`, `group`, `self`, `tank`, `mypet`, class shorts (`war`, `shd`, `pal`, `clr`, `dru`, etc.), `tnt`, `corpse`, `bots`, `raid`, `cbt`, `all`, `xtgt`.
- **min** / **max:** HP % range (0–100). The target’s HP must be in this range to be considered. For **corpse**, **bots**, **raid**, **cbt**, **all** the effective max is treated as 200 (special).

**Special tokens:** **cbt** (combat) — When included in a **corpse** (rez) spell’s bands, the bot may rez even when there are mobs in the camp list. Without **cbt**, corpse rez is only considered when there are no mobs in camp (safe rez only). **all** — When used with corpse, rez any corpse in range (subject to rezoffset and filter).

Heal evaluation order: **corpse** (rez) → **self** → **grp** (group AE) → **tank** → **pc** by class → **mypet** → **pet** (other group pets) → **xtgt** (extended targets). The first matching target in range gets the heal. The **Main Tank** is always the resolved tank (see [Tank and Assist Roles](tank-and-assist-roles.md)).

**Example: single-target tank heal and group heal**

```lua
['heal'] = {
  ['rezoffset'] = 0,
  ['interruptlevel'] = 0.80,
  ['xttargets'] = 0,
  ['spells'] = {
    {
      ['gem'] = 1,
      ['spell'] = 'Superior Healing',
      ['alias'] = 'cht',
      ['minmana'] = 0,
      ['minmanapct'] = 0,
      ['maxmanapct'] = 100,
      ['tarcnt'] = 1,
      ['bands'] = {
        { ['class'] = { 'tank', 'pc' }, ['min'] = 0, ['max'] = 70 }
      },
      ['priority'] = false,
      ['precondition'] = true
    },
    {
      ['gem'] = 2,
      ['spell'] = 'Superior Group Heal',
      ['minmana'] = 0,
      ['minmanapct'] = 0,
      ['maxmanapct'] = 100,
      ['tarcnt'] = 2,
      ['bands'] = {
        { ['class'] = { 'grp' }, ['min'] = 0, ['max'] = 80 }
      },
      ['priority'] = false,
      ['precondition'] = true
    }
  }
}
```

---

## Runtime control

- **Toggle healing:** `/cz doheal on` or `/cz doheal off` (or `/cz doheal` to toggle).
- **Cast by alias:** `/cz cast <alias> [target]` — cast a heal spell by its alias. Use `/cz cast <alias> on` or `off` to enable or disable that spell’s use (tarcnt).
- **Add a spell slot:** `/cz addspell heal <position>` — insert a new heal entry at the given position (1 to count+1).

---

## Behavior summary

- **Corpse rez:** Spells with **corpse**, **bots**, or **raid** in bands can target corpses in range. **rezoffset** skips the first N matching corpses. Rez is only considered when the spell’s band allows it and (for non-**cbt**) no mobs are in the camp list if the band is not combat.
- **Interrupt:** **interruptlevel** is used when deciding whether to interrupt the current cast for another heal (e.g. tank drop).
- **XT targets:** If **xttargets** lists slot numbers, spells with **xtgt** in bands can heal those extended target slots when their HP is in the spell’s band.
