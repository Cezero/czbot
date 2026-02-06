# Mezzing Configuration

This document explains how to set up **mezzing** (crowd control: mez spells on adds, and charm). In CZBot, mezzing is configured using the **debuff** system: you add mez (and optionally charm) spells as debuff entries and use **bands** to choose which mobs they hit.

## Overview

- **Mezzing = debuffs.** There is no separate “mez” section. You add your mez spell(s) under **`config.debuff.spells`** and set **bands** to **notanktar** (adds) so the bot mezzes mobs other than the tank’s target. Optionally use **tanktar** or **named** for specific cases.
- **Charm** (mez that makes the mob your pet) uses the same debuff entries with **charmnames** set; when charm breaks, the bot can recast. See [Debuffing configuration](debuffing-configuration.md).
- **Level:** The bot checks the spell’s **MaxLevel** against the mob’s level for Enthrall-type spells; mobs above that level are skipped.
- For all debuff options (recast, delay, immune check, etc.), see [Debuffing configuration](debuffing-configuration.md).

---

## How to configure mezzing

1. **Enable debuffing:** In config set **`settings.dodebuff`** to `true`, or run `/cz dodebuff on`.

2. **Add a debuff (mez) spell entry** under **`config.debuff.spells`**:
   - **gem** — Spell gem number (1–12) or `'item'`, `'alt'`, `'disc'`.
   - **spell** — Exact spell name (e.g. an Enthrall or mez spell).
   - **tarcnt** — Set > 0. You can limit how many mobs must be in the list before mezzing (e.g. only mez when there are 2+ adds).
   - **bands** — For mezzing **adds**, use **notanktar**. Optionally add **named** to allow mezzing named mobs that are not the tank target. Use **min**/ **max** to restrict by mob HP % (e.g. mez only when mob is 20–100% HP so you don’t mez nearly-dead adds).

3. **Optional:** **recast** (after this many resists on the same spawn, the spell is disabled for that spawn for a duration), **delay** (ms before the spell can be used again), **charmnames** (for charm mez: comma-separated mob names; bot will **pet leave** before casting and can recast when charm breaks), **alias**, **minmana**.

**Example: mez adds only**

```lua
['debuff'] = {
  ['spells'] = {
    {
      ['gem'] = 2,
      ['spell'] = 'Bellow of the Mastruq',
      ['alias'] = 'mez',
      ['minmana'] = 0,
      ['tarcnt'] = 1,
      ['bands'] = {
        { ['class'] = { 'notanktar' }, ['min'] = 20, ['max'] = 100 }
      },
      ['charmnames'] = '',
      ['recast'] = 2,
      ['delay'] = 0,
      ['precondition'] = true
    }
  }
}
```

**Example: charm mez with recast**

Set **charmnames** to mob names the bot is allowed to charm. The bot will **pet leave** before casting and can request a recast when charm breaks:

```lua
['charmnames'] = 'a mob name,another mob',
['bands'] = {
  { ['class'] = { 'notanktar' }, ['min'] = 30, ['max'] = 100 }
}
```

---

## Level limits

For Enthrall-type (mez) spells, the bot uses the spell’s **MaxLevel** and the mob’s level. If the mob is above **MaxLevel**, the spell is not cast on that mob. This is handled automatically; you do not set level in the config.

---

## Runtime control

- **Toggle debuffing (mezzing):** `/cz dodebuff on` or `/cz dodebuff off`.
- **Cast by alias:** `/cz cast <alias> [target]` — cast the mez by alias. `/cz cast <alias> on` or `off` to enable or disable the spell (tarcnt).
- **Add a spell slot:** `/cz addspell debuff <position>`.

---

## See also

For full debuff options (recast, delay, charm, immune check, before-cast behavior, etc.), see [Debuffing configuration](debuffing-configuration.md). For charm as a pet, see [Pets configuration](pets-configuration.md).
