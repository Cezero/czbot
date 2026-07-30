# Buffing Configuration

This document explains how to configure the bot’s **buffing** behavior: which buffs are cast, on whom, and when (idle vs combat). It is intended for operators who set up the config file and use runtime commands.

## Overview

- **Master switch:** Buffing runs only when **`settings.dobuff`** is `true`. Default is `false`.
- **Evaluation order:** The buff loop evaluates **phases** in order (see [Buff bands](#buff-bands)): self → tank → groupbuff → groupmember → pc → (optional non-peer raid) → mypet → pet. Within each phase it is **spell-first**: for each buff that has that phase, cast it on every needy target before moving to the next buff (see [Spell targeting and bands](spell-targeting-and-bands.md)). **pc** = all peers (any character known via charinfo), not limited to group members. **groupmember** = in-group only (including non-bot group members, via Group TLO). When **`settings.buffNonPeerRaid`** is on, after the peer **pc** phase finishes the bot may also buff in-zone raid members who are not CharInfo peers (class-filtered, spawn-buff cache). The only out-of-group non-bot PC we buff via tank phase is the **explicitly configured tank** (TankName).
- **When buffs run:** By default, buffs are allowed when there are no mobs in camp and the bot is not in an active combat context (no alive engage target, not in melee run state, not `Me.Combat()`). Spell-level **inCombat** controls whether a buff can be cast when mobs are in camp or otherwise engaged: when `true`, the buff runs in both idle and combat; when `false` or unset, the buff runs only when idle. Spell-level **combatOnly** (non-bard) means the buff is **only** considered when mobs are in camp — not while idle — which implies combat allowance for the auto buff loop; use it for very short self buffs (e.g. Yaulp) so the bot does not refresh them every few seconds out of combat. **Bards** use **inCombat** / **inIdle** with twist instead; **combatOnly** is ignored for BRD (see [Bard configuration](bard-configuration.md)).
- **Self-target buffs (MQ TargetType Self):** During a cast, the bot does **not** interrupt solely because **StacksTarget** is false (refresh casts can still report “won’t stack” in MQ). Other mid-cast rules (e.g. buff already present with long duration left) still apply.

---

## Config file reference

### Settings

| Option | Default | Purpose |
|--------|--------|---------|
| **dobuff** | `false` | Boolean. Enables or disables the buff loop. |
| **buffNonPeerRaid** | `false` | Boolean. Advanced tab. When on, after peer **pc** buffing finishes, also buff in-zone raid members who are not CharInfo peers (same **pc** class filters / preconditions). Roster and spawn-buff durations are cached while idle (at most once a minute). Peers continue to use CharInfo watches. |

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
| **inCombat** | Optional. When `true`, this buff can be cast when mobs are in camp. Default is `false`. |
| **inIdle** | Optional. **Bard only.** When `true` (default), this buff is included in the idle twist list. When `false`, it is not twisted when idle. Ignored for non-bards. GUI shows "In idle" only for Bards. |
| **combatOnly** | Optional. **Non-bard only** (ignored for BRD). When `true`, the auto buff loop **only** considers this spell when mobs are in camp — never while idle. Implies combat allowance; you do not need **inCombat** for eligibility (you may still set **inCombat** for documentation clarity). Default is `false`. GUI shows "Combat only" for non-bards. |
| **spellicon** | Optional. List of spell IDs treated as equivalents for “already has buff” detection (e.g. `{ 1234, 5678 }`). Legacy scalar `spellicon = 1234` is normalized to a one-element list on load. Empty/`{}` = only the buff spell itself. |
| **height** | Optional. For shrink (SPA 89) buffs: cast when target `Height` exceeds this decimal (e.g. `2.4`). Peers use CharInfo `Height`; self uses `Me.Height`. The buff GUI shows this field automatically when the spell has SPA 89. Replaces a Height precondition. |
| **precondition** | Optional. When missing or not set, defaults to `true` (cast is allowed). When **defined**: **boolean** — `true` = allow, `false` = skip; **string** — Lua script with `mq` and `EvalID` in scope; return truthy to allow the cast. |

### Buff bands

Bands use **targetphase** (priority stages) and **validtargets** (classes or `all`). No min/max for buffs.

- **targetphase** tokens: **self**, **tank**, **groupbuff**, **groupmember**, **pc** (other PCs by class), **mypet**, **pet**. Do **not** put **cbt** or **idle** in targetphase — use spell-level **inCombat** and **inIdle** (Bard only) instead. **bots** in config is accepted for backward compatibility and treated as **pc**. Legacy **byname** / **buffNames** are ignored on load (replaced by **buffNonPeerRaid**).
- **validtargets**: Class shorts (e.g. `war`, `clr`, …) or `all`. Restricts which classes get the buff for **groupmember** and **pc** phases (including non-peer raid members when **buffNonPeerRaid** is on). Absent = all classes.
- **Pet summon:** Pet summon spells are **auto-detected** (spell Category Pet or SPA 33/103). For a summon, add a buff entry with **self** in targetphase; the bot only casts it when it has no pet. The token **petspell** in targetphase is deprecated (not a phase); if present it still sets the pet-summon flag for backward compatibility. See [Pets configuration](pets-configuration.md).
- **groupbuff** — Group AE buff (MQ **TargetType Group v1** or **Group v2**). Counts your EQ group members in AE range who need the buff (peers from charinfo, non-peers from Spawn when BuffsPopulated), **including yourself**. When the count is at least **tarcnt** (default 1), the bot casts on self. **Group v1** casts without retargeting (no friendly target required). **Group v2** retargets to self (v2 requires a group anchor). See [Group AE buffs (v1 vs v2)](#group-ae-buffs-v1-vs-v2) below.
- **groupmember** — Single-target buffs only for characters in the bot’s (EQ) group; includes non-bot group members. For non-peers, buff state comes only from **Spawn** after targeting (Spawn.BuffsPopulated must be true). Add **pc** in targetphase to also buff peers outside the group (evaluated after groupmember). Not used for Group v1/v2 AE spells (GUI hides it for those).
- **pc** — All networked peers by class (from validtargets), any group — including **Group v2** AE buffs. Cast on each watchlisted peer in range (CharInfo watch covers need/Stacks/FreeBuffSlots); after one successful Group v2 cast, CharInfo drops other group members from the watchlist when the buff lands. Not available for **Group v1** AE (GUI hides **pc**). When **buffNonPeerRaid** is on, a segregated post-**pc** pass also considers in-zone non-peer raid members via a spawn-buff duration cache (class filter first). See [Group AE buffs (v1 vs v2)](#group-ae-buffs-v1-vs-v2).
- **tank** — Can be a non-bot when explicitly named in config (TankName). Buff need for non-peers is only known from the **Spawn** TLO after you have targeted that spawn long enough for **Spawn.BuffsPopulated** to be true (same as mobs). When we have buff data we only cast if they need it; when out-of-group and we don’t have data we cast in range (best-effort). When this bot is the main tank, the tank phase has a single target (this bot), so you do not need **self** in targetphase for the MT to receive a tank-only buff.

**Evaluation order (priority)**

The bot evaluates buff targets in a **fixed, literal order**. The list below is the actual priority:

1. **self** (including auto-detected pet summon when no pet)
2. **tank**
3. **groupbuff** (group AE)
4. **groupmember** (in-group only)
5. **pc** (all peers)
6. **non-peer raid** (only when **buffNonPeerRaid** is on and the cached non-peer raid list is non-empty; same spells as **pc**)
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

**Example: short self buff (combat only, e.g. Yaulp)**

```lua
{
  gem = 2,
  spell = 'Yaulp VII',
  minmana = 0,
  combatOnly = true,
  bands = {
    { targetphase = { 'self' }, validtargets = { 'all' } }
  },
  spellicon = 0
}
```

Refreshes only when mobs are in camp, not every tick while idle. Manual `/cz cast` is unchanged and can still be used out of combat.

### Group AE buffs (v1 vs v2)

MQ **TargetType** controls which buff phases apply. The GUI shows only appropriate phases per spell.

| TargetType | Phases | Behavior |
|------------|--------|----------|
| **Group v1** | **groupbuff** (+ normal ST phases except **pc**) | Count your group (includes self); cast on self without retargeting when count ≥ **tarcnt**. |
| **Group v2** | **groupbuff** + **pc** | **groupbuff**: same count/cast-on-self for your group (retargets to self). **pc**: CharInfo **ALL** watchlist — cast on watchlisted peers in range (watch includes FreeBuffSlots); AE lands on their group and peers drop off the watchlist when the buff appears. |
| **Single / Self / etc.** | Normal ST phases; no **groupbuff** | Unchanged single-target logic. |

**tarcnt** is shown in the GUI only for Group v1/v2 spells. It includes the caster for **groupbuff**.

**Example: Group v2 AE (own group + remote groups)**

```lua
{
  gem = 5,
  spell = 'Group v2 Example Buff',
  minmana = 0,
  tarcnt = 3,
  bands = {
    { targetphase = { 'groupbuff', 'pc' }, validtargets = { 'all' } }
  },
  spellicon = 0
}
```

---

## Runtime control

- **Toggle buffing:** `/cz dobuff on` or `/cz dobuff off` (or `/cz dobuff` to toggle).
- **Cast by alias:** `/cz cast <alias> [target]` — cast a buff by alias. Use `/cz cast <alias> on` or `off` to enable or disable that spell (**enabled**).
- **Add a spell slot:** `/cz addspell buff <position>` — insert a new buff entry at the given position.

---

## Behavior summary

- **Spellicon:** When **spellicon** is set, the bot checks whether the candidate target already has that buff (by spell ID). If they do, the target is skipped so the same buff is not recast unnecessarily.
- **Combat vs idle:** By default, buffs are allowed when there are no mobs in camp. Set **inCombat** `true` on a spell entry to allow that buff when mobs are in camp. Set **combatOnly** `true` (non-bard) to **skip** that spell while idle and only run it when mobs are in camp. **inIdle** (Bard only) controls whether the buff is in the idle twist list; see [Bard configuration](bard-configuration.md).
