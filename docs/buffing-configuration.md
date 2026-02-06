# Buffing Configuration

This document explains how to configure the bot’s **buffing** behavior: which buffs are cast, on whom, and when (idle vs combat). It is intended for operators who set up the config file and use runtime commands.

## Overview

- **Master switch:** Buffing runs only when **`settings.dobuff`** is `true`. Default is `false`.
- **Evaluation order:** The buff loop checks, in order: self (including **petspell** when you have no pet), buffs by **name**, tank, other bots by **class**, your pet (**mypet**), then other bots’ pets (**pet**). “Other bots” and “other bots’ pets” mean **all peers** (any character known via charinfo), not limited to group members. The bot will buff any peer in range that matches the band and needs the buff. The first valid target in range gets the buff.
- **When buffs run:** Each spell entry can be marked for **idle** only, **combat** only, or both (by band tokens **idle** and **cbt**). With no mobs in camp, idle-only and combat buffs can run; with mobs, only combat buffs run.

---

## Config file reference

### Settings

| Option | Default | Purpose |
|--------|--------|---------|
| **dobuff** | `false` | Boolean. Enables or disables the buff loop. |

### Buff section

All buff options are under **`config.buff.spells`**. Each spell entry can have:

| Field | Purpose |
|-------|---------|
| **gem** | Spell gem number (1–12), or `'item'`, `'alt'`, `'disc'`, `'script'`. |
| **spell** | Spell name (or item name if gem is `'item'`). |
| **alias** | Optional. Short name for `/cz cast <alias>`. Pipe-separated for multiple. |
| **announce** | Optional. If true, announce when casting. |
| **minmana** | Minimum mana (absolute) to cast. |
| **enabled** | Optional. When `true` or missing, the spell is used. When `false`, the spell is not used. Default is `true`. |
| **bands** | Who receives the buff. See [Buff bands](#buff-bands) below. |
| **spellicon** | Optional. Buff icon ID. If set (non-zero), the bot skips a target who already has that buff icon (avoids overwriting). |
| **precondition** | Optional. When missing or not set, defaults to `true` (cast is allowed). When **defined**: **boolean** — `true` = allow, `false` = skip; **string** — Lua script with `mq` and `EvalID` in scope; return truthy to allow the cast. |

### Buff bands

Bands use **class** only (no min/max). Each band is a table with **class** = list of tokens. Tokens include:

- **self** — Buff yourself (and for pet classes, **petspell** can be used to summon when you have no pet; see [Pets configuration](pets-configuration.md)).
- **petspell** — Summon pet: cast on self when you have **no pet**. Use with **self** in the same band. Documented in [Pets configuration](pets-configuration.md).
- **tank** — Main Tank (from TankName).
- **mypet** — Your pet.
- **pet** — Other peers’ pets (any peer, not only group members).
- **Class shorts** — e.g. `war`, `clr`, `shd`, `pal`, `rng`, `mnk`, `rog`, `brd`, `bst`, `ber`, `shm`, `dru`, `wiz`, `mag`, `enc`, `nec`. Restricts the buff to those classes.
- **name** — Buff specific characters by name (list their names in the band’s class list).
- **cbt** — This buff is allowed during combat (mobs in camp).
- **idle** — This buff is allowed when idle (no mobs in camp). If neither **cbt** nor **idle** is set, the spell may run in both.

Buffing is not restricted by group: any peer in range who matches the band and needs the buff can be buffed. See [Out-of-group peers](out-of-group-peers.md).

**Example: self buff, tank buff, and group class buff**

```lua
['buff'] = {
  ['spells'] = {
    {
      ['gem'] = 3,
      ['spell'] = 'Spirit of the Wolf',
      ['alias'] = 'sow',
      ['minmana'] = 0,
      ['bands'] = {
        { ['class'] = { 'self' } }
      },
      ['spellicon'] = 0
    },
    {
      ['gem'] = 4,
      ['spell'] = 'Talisman of the Tribunal',
      ['minmana'] = 0,
      ['bands'] = {
        { ['class'] = { 'tank', 'war', 'shd', 'pal', 'rng', 'mnk', 'rog', 'ber' } }
      },
      ['spellicon'] = 0
    }
  }
}
```

---

## Runtime control

- **Toggle buffing:** `/cz dobuff on` or `/cz dobuff off` (or `/cz dobuff` to toggle).
- **Cast by alias:** `/cz cast <alias> [target]` — cast a buff by alias. Use `/cz cast <alias> on` or `off` to enable or disable that spell (**enabled**).
- **Add a spell slot:** `/cz addspell buff <position>` — insert a new buff entry at the given position.

---

## Behavior summary

- **Spellicon:** When **spellicon** is set, the bot checks whether the candidate target already has that buff (by icon). If they do, the target is skipped so the same buff is not recast unnecessarily.
- **Combat vs idle:** Entries with **cbt** in bands run when there are mobs in the camp list; entries with **idle** run when there are none. Entries with both or neither can run in either case (subject to other checks).
