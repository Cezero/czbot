# Travel Mode

This document explains **travel mode**: a follow-only state where the bot disables melee, buff, debuff, heal, cure, sit, mount, and pull. It is intended for operators who want the bot to follow a character across zones without engaging in normal combat or support logic.

## Overview

**`/cz travel [name]`** (or **`/cz travel me`** or **`/cz travel`** to follow the tank) starts following the given character and enables travel mode. The bot follows only; most other bot logic is disabled. Travel mode **persists across zones**—when you zone, the bot remains in travel mode and continues to follow when the target is available.

---

## What is disabled

While in travel mode, the following are **off**:

- **Melee** (stick, attack, engage)
- **Buff** (doBuff)
- **Debuff**
- **Heal**
- **Cure**
- **Sit** (sit for mana/endurance)
- **Mount**
- **Pull**

**Buffs never run in travel mode**, even during the attack override described below.

---

## Attack override

**`/cz attack`** (with optional target name) temporarily enables **melee**, **heal**, **cure**, and **debuff** until the current target dies. When the target dies, travel mode resumes (follow-only, no melee/buff/debuff/heal/cure).

**doBuff remains off** during this override—only melee, heal, cure, and debuff are temporarily allowed.

---

## Turning off travel

Travel mode is cleared when:

- You run **`/cz stop`** (disables make camp and follow, and travel mode).
- You stop following (e.g. the Stop button in the GUI next to the Follow section).

---

## Bards

In travel mode, the bot uses a **travel twist**: a single song from your buff config. It looks for a buff spell with alias **`travel`**; if none, alias **`selos`**; if neither exists, no twist (twist is stopped). Config order; one gem.

To set the travel song, add a buff entry in **`config.buff.spells`** with **`alias = 'travel'`** (or **`alias = 'selos'`** for the fallback). See [Buffing configuration](buffing-configuration.md) and [Bard configuration](bard-configuration.md).
