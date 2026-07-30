# Tanking Configuration

This document explains how to configure the bot when it is the **Main Tank (MT)** or a melee character: stick command, assist threshold, and camp/leash. For who the MT is, how the MA selects targets, and how the Puller interacts, see [Tank and Assist Roles](tank-and-assist-roles.md).

## Overview

- **Tank role and target selection** (who is MT, puller priority, etc.) are configured as in [Tank and Assist Roles](tank-and-assist-roles.md): **TankName**, **AssistName**, and the group window Puller.
- **Melee/tank behavior** (stick, when to assist, camp distance) is configured in **`settings`** and **`melee`**. When this bot is the MT, it picks which mob to engage from the camp list; when it is DPS or offtank, it follows the MA (see [Offtank configuration](offtank-configuration.md)).

---

## Config file reference

### Settings (relevant to tanking)

| Option | Default | Purpose |
|--------|--------|---------|
| **TankName** | `"manual"` | Main Tank name or `"automatic"` / `"manual"`. See [Tank and Assist Roles](tank-and-assist-roles.md) and [Automatic MA/MT Selection](automatic-ma-mt-selection.md). |
| **acleash** | 75 | Max horizontal distance (X,Y) from camp for valid targets and mob list. Also used for corpse rez range and **bind-point stealth** radius (distance from primary bind coordinates). See [Safety and stealth](safety-and-stealth.md). |
| **zradius** | 75 | Max vertical (Z) difference from camp; mobs outside this are ignored for the mob list. |
| **protectCasters** | `false` | MA: mid-fight peel to an add beating a pure caster for **protectCastersSec**. See [Protect casters](#protect-casters). |
| **protectCastersSec** | `30` | Seconds a MobList add must keep the same pure-caster target before Protect casters peels. |

### Melee section

Under **`config.melee`**:

| Option | Default | Purpose |
|--------|--------|---------|
| **stickcmd** | `'hold uw 7'` | Stick command used when engaging (e.g. `hold`, `hold uw 7`, `snaproll`). |
| **stayBehind** | `false` | When on and this bot is **not** the Main Tank, append `behind` (rogue) or `!front` (other classes) to the stick command while engaging. |
| **behindAggroPct** | 90 | With **stayBehind** on: above this **Me.PctAggro** (level 20+), engage without the positioning token until aggro drops; stick is re-issued when crossing the threshold. |
| **assistpct** | 99 | MA’s target HP % at or below which this bot will sync to the MA’s target (for DPS/MA logic). |
| **offtank** | `false` | When true, this bot is an offtank (see [Offtank configuration](offtank-configuration.md)). |
| **minmana** | 0 | Minimum mana % to engage (melee). |

**Example: melee/tank-related config**

```lua
['settings'] = {
  ['TankName'] = "automatic",
  ['acleash'] = 75,
  ['zradius'] = 75
},
['melee'] = {
  ['stickcmd'] = 'hold uw 7',
  ['assistpct'] = 99,
  ['offtank'] = false,
  ['minmana'] = 0
}
```

---

## Using disciplines and combat abilities

To use **disciplines** or **combat abilities** (e.g. kick, bash, backstab), enable **`settings.dodebuff`** and add debuff entries under **`config.debuff.spells`** with **gem** `'disc'` (disciplines) or `'ability'` (combat abilities) and the desired **bands** (e.g. **matar** for the MA's target). Use a **burn** band phase for disciplines you only want during burn windows. See [Melee combat abilities](melee-combat-abilities.md) and [Debuffing configuration](debuffing-configuration.md#burn-window).

---

## Protect casters

When **`settings.protectCasters`** is `true` and this bot is the **Main Assist**, it monitors MobList adds with a scheduled one-mob-per-tick checker. If an **unmezzed** add continuously targets a **pure caster** (CLR, DRU, SHM, ENC, WIZ, MAG, NEC) in **group or raid** for **`settings.protectCastersSec`** seconds (default **30**), the MA switches onto that add — same mid-fight refocus pattern as the **named** override (publishes the new engage via the normal assist path). Sticky **named** targets are not abandoned for a trash peel.

**Always** (toggle on or off): when the MA’s engage target dies and it picks the next MobList mob, non-mezzed adds that currently have a pure caster targeted are preferred over other trash (after named / puller). With the toggle **on**, the add with the **longest accrued** caster-threat timer wins that re-pick.

- Toggle: **`/cz protectcasters on|off`** or Combat tab **Protect casters**.
- Seconds: **`/cz protectcasterssec <n>`** or Combat tab when enabled.

---

## Runtime control

- **Set Main Tank:** `/cz tank set <name>` or `/cz tank automatic`.
- **Set stick command:** `/cz stickcmd <string>` (e.g. `/cz stickcmd hold uw 7`).
- **Set camp leash:** `/cz acleash <number>` — max distance from camp for targeting and mob list.
- **Make camp / return:** Make camp is controlled via movement (e.g. makecamp on/off/return). When camp is set, the bot returns to camp when beyond leash; **acleash** and **zradius** define the valid area.

---

## Camp and leash

When **make camp** is on, the bot’s camp location is used as the center. **acleash** and **zradius** limit which mobs are considered in the mob list (and thus what the MT can pick). If the bot moves beyond that distance from camp, leash/camp-return behavior can run (e.g. return to camp). The same **acleash** value defines how close you must be to your primary bind point before bind stealth suppresses offense and buffing. For pulling, see [Pull Configuration and Logic](pull-configuration.md). For no-combat zones and protected NPCs, see [Safety and stealth](safety-and-stealth.md).
