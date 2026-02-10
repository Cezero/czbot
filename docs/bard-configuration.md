# Bard Configuration

This document explains the nuances and considerations when configuring a **bard (BRD)** bot. The bot treats bards differently in several subsystems (buff targeting, casting, movement, melee, and interrupts). This page summarizes what matters for configuration and what is automatic.

## Overview

- **Buff targeting:** For bards, only the **self** phase is evaluated for buffs; tank, groupbuff, groupmember, pc, mypet, and pet are never tried. Use **self** (and **cbt** / **idle** as desired) in your buff bands.
- **Interrupts:** The bot does not interrupt bard casts (buff, debuff, cure). No configuration required.
- **Movement and casting:** Bards can move, use nav, and stick while "casting"; the bot does not force a stop before casting.
- **Melee:** Before casting, if **domelee** is on and the bard is not in combat, the bot re-engages melee. Set **settings.domelee** if the bard should melee when not casting.
- **Twist:** If MQ2Twist is loaded and twisting, the bot stops twist before casting a spell. No config.
- **Mez + melee:** Known limitation — when mezzing an add the bard may not re-engage melee until mez is cleared; the bard can stand there singing mez. No config workaround.

---

## Buff targeting

For **BRD**, only **self** is evaluated after the initial self check. The phases tank, groupbuff, groupmember, pc, mypet, and pet are **never** tried for bards. Put **self** (and **cbt** / **idle** as needed) in your buff bands; other phases in bands have no effect for bards.

There is built-in logic for **detrimental** songs (e.g. mez) on the tank's target: when the spell is detrimental and the tank has a target, the bot can cast that song on the tank's target if the debuff is missing or about to expire. That behavior is automatic.

For full targeting and band details, see [Spell targeting and bands](spell-targeting-and-bands.md) and [Buffing configuration](buffing-configuration.md).

---

## Song refresh

Songs are considered needing refresh when their duration is below about **6.1 seconds** (vs 24 seconds for other classes' buffs). There is no config option; this is informational only.

---

## Interrupts

The bot does **not** interrupt bard casts. The buff, debuff, and cure hooks all pass `skipInterruptForBRD`, so the bot will not stop a bard mid-cast to do something else. No configuration required.

---

## Movement and casting

Bards can move, use MQ2Nav, and stick while "casting." The **precast_wait_move** logic (stop nav/stick and wait before casting) is skipped for BRD, so the bard is not forced to stand still.

The **leash** check (return to camp when over leash) is **not** skipped for bards when casting. So the bard can still be called back to camp while singing. No config changes needed.

---

## Melee

The melee phase does **not** get the 5-second "moving_closer" deadline for bards that other classes get.

Before casting a spell, if **settings.domelee** is on, there are mobs in camp, the spell target is not a mez add (notanktar), and the bard is not in combat, the bot calls the combat logic to re-engage melee. So the bot tries to get the bard back into combat when about to cast a non-mez spell.

**Recommendation:** Set **settings.domelee** to `true` if you want the bard to melee when not casting.

---

## Twist

If the **MQ2Twist** plugin is loaded and the bard is twisting, the bot stops twist before casting a spell from its spell list. Your configured spells take over during the cast. No configuration required.

---

## Mez and melee (known limitation)

When mezzing a **notanktar** (an add), the bot turns attack off. The bard does **not** re-engage melee while mez is "active," so the bard can stand there singing mez until something else changes. The desired behavior (attack off → mez add → pulse mez → land → re-assist MA → attack on, then later cycle again) is not fully implemented. There is no config workaround; be aware of this when using a bard for mezzing.

---

## Debuff completion

The "already on target" and resist handling for debuffs treat bards specially (e.g. **MissedNote** is considered so the bot can still mark a debuff as complete appropriately). Your debuff config (bands, recast, delay, etc.) is unchanged; this is internal behavior only.

---

## Summary

| Area | What to do |
|------|------------|
| **Buffs** | Use **self** only (and **cbt** / **idle** as desired). Tank, groupbuff, groupmember, pc, mypet, pet in bands have no effect for bards. |
| **Song refresh** | Informational only; songs refresh when duration &lt; ~6.1s. |
| **Debuffs / mez** | Configure as usual; see [Debuffing configuration](debuffing-configuration.md) and [Mezzing configuration](mezzing-configuration.md). Be aware of the mez + melee limitation above. |
| **Cures** | No special config; the bot does not interrupt bard cures. |
| **Interrupts** | Automatic; the bot does not interrupt bard casts. |
| **Movement** | Automatic; bards can move while casting. |
| **Melee** | Set **settings.domelee** if you want the bard to re-engage melee when not casting. |
| **Twist** | Automatic; twist is stopped when the bot casts. |
