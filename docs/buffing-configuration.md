# Buffing Configuration

This document explains how to configure the bot’s **buffing** behavior: which buffs are cast, on whom, and when (idle vs combat). It is intended for operators who set up the config file and use runtime commands.

## Overview

- **Master switch:** Buffing runs only when **`settings.dobuff`** is `true`. Default is `false`.
- **Evaluation order:** The buff loop evaluates **phases** in order (see [Buff bands](#buff-bands)): self → byname → tank → groupbuff → groupmember → pc → mypet → pet. For each phase it considers each target and checks **all** buff spells that have that phase in their bands before moving to the next phase. **pc** = all peers (any character known via charinfo), not limited to group members. **groupmember** = in-group only (including non-bot group members, via Group TLO). The only out-of-group non-bot PC we buff is the **explicitly configured tank** (TankName).
- **When buffs run:** Each spell entry can be marked for **idle** only, **combat** only, or both (by band tokens **idle** and **cbt**). With no mobs in camp, idle-only and combat buffs can run; with mobs, only combat buffs run.
- **Combat:** By default, no buffs are cast when mobs are in camp. To allow a specific buff during combat, add **cbt** to that spell's band.

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

Bands use **targetphase** (priority stages) and **validtargets** (classes or `all`). No min/max for buffs.

- **targetphase** tokens: **self**, **tank**, **groupbuff**, **groupmember**, **pc** (other PCs by class), **mypet**, **pet**, **byname**; **cbt** / **idle** control when the spell can run (combat vs no mobs in camp). **bots** in config is accepted for backward compatibility and treated as **pc**.
- **validtargets**: Class shorts (e.g. `war`, `clr`, …) or `all`. Restricts which classes get the buff for **groupmember** and **pc** phases. Absent = all classes.
- **petspell** — Summon pet: cast on self when you have **no pet**. Use with **self** in the same band. Documented in [Pets configuration](pets-configuration.md).
- **name** — Buff specific characters by name (list their names in **validtargets** when using **byname** in targetphase).
- **groupbuff** — Group AE buff: when the spell targets the group (e.g. Group v1), the bot counts group members in range who need the buff (peers from charinfo, non-peers from Spawn when BuffsPopulated); if the count is at least **tarcnt** (optional, default 1), it casts on self. **tarcnt** can be set on the spell entry.
- **groupmember** — Single-target buffs only for characters in the bot’s (EQ) group; includes non-bot group members. For non-peers, buff state comes only from **Spawn** after targeting (Spawn.BuffsPopulated must be true). Add **pc** in targetphase to also buff peers outside the group (evaluated after groupmember).
- **tank** — Can be a non-bot when explicitly named in config (TankName). Buff need for non-peers is only known from the **Spawn** TLO after you have targeted that spawn long enough for **Spawn.BuffsPopulated** to be true (same as mobs). When we have buff data we only cast if they need it; when out-of-group and we don’t have data we cast in range (best-effort).

**Evaluation order (priority)**

The bot evaluates buff targets in a **fixed, literal order**. The list below is the actual priority:

1. **self** (including **petspell** when no pet)
2. **byname**
3. **tank**
4. **groupbuff** (group AE)
5. **groupmember** (in-group only)
6. **pc** (all peers)
7. **mypet**
8. **pet**

**Bards:** Only the **self** phase is evaluated; tank, groupbuff, groupmember, pc, mypet, and pet are skipped. See [Bard configuration](bard-configuration.md).

The first phase in this list that has a valid, in-range target that needs the buff wins. See [Out-of-group peers](out-of-group-peers.md).

**Example: self buff, tank buff, and group class buff**

```lua
buff = {
  spells = {
    {
      gem = 3,
      spell = 'Spirit of the Wolf',
      alias = 'sow',
      minmana = 0,
      bands = {
        { targetphase = { 'self' }, validtargets = { 'all' } }
      },
      spellicon = 0
    },
    {
      gem = 4,
      spell = 'Talisman of the Tribunal',
      minmana = 0,
      bands = {
        { targetphase = { 'tank', 'pc' }, validtargets = { 'war', 'shd', 'pal', 'rng', 'mnk', 'rog', 'ber' } }
      },
      spellicon = 0
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
