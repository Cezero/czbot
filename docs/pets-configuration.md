# Pets Configuration

This document explains how to configure **pet summoning**, **pet assist** (sending the pet on the engage target), and **pet buffing**. Charm (mez/charm that uses a mob as a pet) is configured in the debuff section; see [Debuffing configuration](debuffing-configuration.md) and the **charmnames** option.

## Overview

- **Summoning a pet:** Configured as a **buff** with the **petspell** band. The bot casts the summon spell on itself when it has no pet.
- **Pet assist:** When **petassist** is true and the bot has an engage target, the bot sends its pet to attack that target. When there is no engage target or the target is wrong, the bot calls pet back / follow.
- **Pet buffing:** Configured in the **buff** section with bands **mypet** (your pet) or **pet** (other group members’ pets). See [Buffing configuration](buffing-configuration.md).

---

## Summoning a pet

Pet summoning is a **self buff** that the bot casts when it has **no pet**.

1. In your config, ensure **`settings.dobuff`** is `true` (or turn buffing on with `/cz dobuff on`).
2. Add a spell entry under **`config.buff.spells`** with your **summon pet** spell:
   - Set **gem** and **spell** (e.g. gem 3, spell `"Summon Warder"`).
   - The spell is active by default (**enabled** is `true` when omitted). Set **enabled** to `false` to disable it.
   - In **bands**, include the class token **petspell** (and typically **self**). The bot will only cast this spell when it has no pet (`mypetid == 0`).

**Example: summon pet buff entry**

```lua
{
  ['gem'] = 3,
  ['spell'] = 'Summon Warder',
  ['alias'] = 'pet',
  ['minmana'] = 0,
  ['bands'] = {
    { ['validtargets'] = { 'self', 'petspell' } }
  },
  ['spellicon'] = 0
}
```

For all buff spell fields (gem, spell, alias, minmana, spellicon, etc.), see [Buffing configuration](buffing-configuration.md).

---

## Pet assist

When the bot is meleeing and has an **engage target** (e.g. the MA’s target), it can send its pet to attack that target.

| Option | Where | Default | Purpose |
|--------|--------|--------|---------|
| **petassist** | `settings.petassist` | `false` | When true, the bot sends its pet to attack the current engage target when it engages. When there is no engage target or the target changes, the bot calls pet back / follow. |

**Example (in settings):**

```lua
['settings'] = {
  ['petassist'] = true
}
```

At runtime you can set it with `/cz setvar settings.petassist true` (or edit the config file). There is no dedicated `/cz pet` command; the pet follows melee engagement. Use **`/cz attack`** to engage the MA’s target (pet will attack that target if **petassist** is true).

---

## Pet buffing

To buff **your pet** or **other group members’ pets**, add buff entries with bands **mypet** or **pet** in **`config.buff.spells`**. The bot will cast those buffs on your pet or other pets when they are in range and lack the buff. See [Buffing configuration](buffing-configuration.md) for spell entry format and band tokens.

---

## Charm (mez/charm pets)

When you use a **charm** spell (e.g. Enchanter mez that makes the mob your pet), it is configured in the **debuff** section:

- Add a debuff entry with the charm spell and set **charmnames** to a comma-separated list of mob names the bot is allowed to charm.
- Before casting charm, the bot issues **pet leave** so your current pet is released.
- When charm breaks, the bot can request a recast on that spawn.

See [Debuffing configuration](debuffing-configuration.md) for **charmnames**, **recast**, and **bands** (e.g. **notanktar** for adds), and [Spell targeting and bands](spell-targeting-and-bands.md) for band and targeting logic. For mezzing in particular, see [Mezzing configuration](mezzing-configuration.md).

---

## Runtime control

- **Toggle buffing (for summon):** `/cz dobuff on` or `/cz dobuff off`. Pet summon runs only when buffing is on and the petspell entry is **enabled** (default is true when omitted).
- **Enable/disable a buff by alias:** `/cz cast <alias> on` or `/cz cast <alias> off` — use the alias you gave the summon spell (or any buff).
- **Engage (pet follows):** `/cz attack` — engages the MA’s target; if **petassist** is true, the pet attacks that target.
