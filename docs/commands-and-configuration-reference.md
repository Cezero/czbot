# Commands and Configuration Reference

This document is a single reference for all **/cz** commands and the **configuration file** structure. For detailed behavior and examples, see the topic-specific docs (healing, tanking, buffing, etc.).

---

## Commands

All commands are used as **`/cz <command> [arguments]`**. Arguments are optional unless noted.

### Toggles

These turn a feature on or off. Use **`/cz <cmd> on`**, **`/cz <cmd> off`**, or **`/cz <cmd>`** to toggle.

| Command      | Purpose                                                                                                                                                                |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **domelee**  | Melee / engage (stick, attack, follow MA or tank logic).                                                                                                               |
| **dopull**   | Pulling loop (find mob, aggro, return to camp).                                                                                                                        |
| **dodebuff** | Debuff loop (nukes, slows, mez, etc.).                                                                                                                                 |
| **dobuff**   | Buff loop (buffs, pet summon).                                                                                                                                         |
| **doheal**   | Heal loop.                                                                                                                                                             |
| **doraid**   | Raid mode: enable zone-specific raid mechanic handling; when raid mechanics are active, pulling is suppressed and zone scripts may run. See [Raid mode](raid-mode.md). |
| **docure**   | Cure loop.                                                                                                                                                             |
| **dosit**    | Sit when not in combat (for mana/endurance).                                                                                                                           |
| **domount**  | Mount when not in combat.                                                                                                                                              |
| **dodrag**   | Corpse drag: automatically find and drag peer corpses within range. See [Corpse dragging](corpse-dragging.md).                                                         |

### Movement and camp

| Command      | Arguments                | Purpose                                                                                                                                                                                                                                                   |
| ------------ | ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **makecamp** | `on`, `off`, or `return` | Set or clear make camp; `return` sends bot back to camp.                                                                                                                                                                                                  |
| **follow**   | `<name>`, `me`, or omit  | Follow the named character (disables make camp). With `me` or no name, follow TankName. When the command is sent via MQRemote (e.g. `/rc +self group /cz follow`), sender is not available—use MQRemote `/rc` directly (no CZBot `/an*execute` commands). |
| **stop**     | —                        | Disable make camp and follow.                                                                                                                                                                                                                             |
| **leash**    | —                        | Return to camp (if camp is set).                                                                                                                                                                                                                          |

### Pull

| Command             | Arguments              | Purpose                                                                                                                                                 |
| ------------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **dopull**          | `on` / `off` or toggle | Enable/disable pulling.                                                                                                                                 |
| **xarc**            | `<degrees>` or none    | Directional pulling: restrict pulls to an arc in front of the bot (e.g. `90`). No argument turns it off. (This is the runtime “pullarc” setting.)       |
| **exclude**         | `<name>` or target     | Add a mob to the exclude list (pull and target selection skip it). Changes are saved automatically to the common config (cz_common.lua).                |
| **exclude remove**  | `<name>` or target     | Remove a mob from the exclude list.                                                                                                                     |
| **priority**        | `<name>` or target     | Add a mob to the priority list; when pull.usepriority is true, prefer these mobs. Changes are saved automatically to the common config (cz_common.lua). |
| **priority remove** | `<name>` or target     | Remove a mob from the priority list.                                                                                                                    |

### Combat and roles

| Command          | Arguments               | Purpose                                                                                                           |
| ---------------- | ----------------------- | ----------------------------------------------------------------------------------------------------------------- |
| **attack**       | —                       | Engage the Main Assist’s target.                                                                                  |
| **abort**        | optional `off`          | Abort: stop cast, clear target, turn off melee/debuff; return to camp. Use `abort off` to re-enable melee/debuff. |
| **tank**         | `<name>` or `automatic` | Set Main Tank.                                                                                                    |
| **assist**       | `<name>` or `automatic` | Set Main Assist.                                                                                                  |
| **offtank**      | `on` / `off` or toggle  | Enable/disable offtank behavior.                                                                                  |
| **stickcmd**     | `<string>`              | Set stick command (e.g. `hold uw 7`).                                                                             |
| **acleash**      | `<number>`              | Set camp leash distance (max distance from camp for mob list / targeting).                                        |
| **targetfilter** | `0` / `1` / `2`         | Filter for mob list: 0 = NPC + aggressive + LOS, 1 = NPC + LOS, 2 = exclude PCs/mercs/etc.                        |

### Spells and config

| Command                         | Arguments                                        | Purpose                                                                                                     |
| ------------------------------- | ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| **cast**                        | `<alias> [target]` or `<alias> on` / `off`       | Cast a spell by alias (heal/buff/debuff/cure). With `on`/`off`, enable or disable that spell (**enabled**). |
| **setvar**                      | `<path> <value>`                                 | Set a config value at runtime (e.g. `settings.petassist true`). Writes to config file.                      |
| **addspell**                    | `heal` / `buff` / `debuff` / `cure` `<position>` | Add a new spell entry at the given position (1 to count+1).                                                 |
| **refresh** / **refreshspells** | —                                                | Refresh spell state.                                                                                        |
| **echo**                        | `<config.path>`                                  | Print current value of a config path (e.g. `heal.interruptlevel`).                                          |

### Other

| Command           | Arguments                                     | Purpose                                                                                                             |
| ----------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| **import**        | `lua <filename> [save]`                       | Load config from a Lua file; optional `save` writes it to current config.                                           |
| **export**        | `<filename>`                                  | Export current config to a file in config directory.                                                                |
| **debug**         | `on` / `off` or toggle                        | Enable/disable debug messages.                                                                                      |
| **ui** / **show** | —                                             | Open the CZBot UI.                                                                                                  |
| **quit**          | —                                             | Terminate the bot.                                                                                                  |
| **chchain**       | `stop` / `setup` / `start` / `tank` / `pause` | Complete Heal chain control.                                                                                        |
| **draghack**      | `on` / `off` or toggle                        | Toggle use of sumcorpse instead of walk-to-corpse for dragging. See [Corpse dragging](corpse-dragging.md).          |
| **linkitem**      | —                                             | Link item (event).                                                                                                  |
| **linkaugs**      | `<slot>`                                      | Print augments in the given slot.                                                                                   |
| **spread**        | —                                             | Spread bots (nav to positions).                                                                                     |
| **raid**          | `save` / `load` `<name>`                      | Save or load a raid configuration by name. See [Raid mode](raid-mode.md) for save/load behavior and raid formation. |

### Master pause

- **`/czp`** or **`/czpause [on|off]`** — Pause or unpause the entire bot. No arguments toggles pause.

---

## Configuration file structure

The config file is a Lua script that returns a table. Path: **`cz_<CharName>.lua`** in your MacroQuest config directory (e.g. `config/cz_Yourname.lua`).

**Top-level keys:** `settings`, `pull`, `melee`, `heal`, `buff`, `debuff`, `cure`, `script`. Each section is a table; `heal`, `buff`, `debuff`, and `cure` contain a **spells** array of spell entries.

**Example: overall shape and settings**

```lua
StoredConfig = {
  ['settings'] = {
    ['domelee'] = false,
    ['doheal'] = false,
    ['dobuff'] = false,
    ['dodebuff'] = false,
    ['docure'] = false,
    ['dopull'] = false,
    ['doraid'] = false,
    ['dodrag'] = false,
    ['domount'] = false,
    ['mountcast'] = false,
    ['dosit'] = true,
    ['sitmana'] = 90,
    ['sitendur'] = 90,
    ['TankName'] = "manual",
    ['AssistName'] = nil,
    ['TargetFilter'] = '0',
    ['petassist'] = false,
    ['acleash'] = 75,
    ['followdistance'] = 35,
    ['zradius'] = 75
  },
  ['pull'] = { ... },
  ['melee'] = { ... },
  ['heal'] = { ['rezoffset'] = 0, ['interruptlevel'] = 0.80, ['xttargets'] = 0, ['spells'] = { ... } },
  ['buff'] = { ['spells'] = { ... } },
  ['debuff'] = { ['spells'] = { ... } },
  ['cure'] = { ['spells'] = { ... } },
  ['script'] = {}
}
return StoredConfig
```

### Settings (defaults)

| Option             | Default       | Purpose                                                                                                                 |
| ------------------ | ------------- | ----------------------------------------------------------------------------------------------------------------------- |
| **domelee**        | `false`       | Enable melee/engage.                                                                                                    |
| **doheal**         | `false`       | Enable heal loop.                                                                                                       |
| **dobuff**         | `false`       | Enable buff loop.                                                                                                       |
| **dodebuff**       | `false`       | Enable debuff loop.                                                                                                     |
| **docure**         | `false`       | Enable cure loop.                                                                                                       |
| **dopull**         | `false`       | Enable pull loop.                                                                                                       |
| **doraid**         | `false`       | Raid mode (zone-specific raid mechanics; when active, pulling is suppressed). See [Raid mode](raid-mode.md).            |
| **dodrag**         | `false`       | Corpse drag (automatically find and drag peer corpses). See [Corpse dragging](corpse-dragging.md).                      |
| **domount**        | `false`       | Auto mount.                                                                                                             |
| **mountcast**      | `false`       | Mount cast (e.g. spell\|item).                                                                                          |
| **dosit**          | `true`        | Sit when not in combat.                                                                                                 |
| **sitmana**        | 90            | Sit when mana % at or below this.                                                                                       |
| **sitendur**       | 90            | Sit when endurance % at or below this.                                                                                  |
| **TankName**       | `"manual"`    | Main Tank name or `"automatic"` / `"manual"`.                                                                           |
| **AssistName**     | (unset)       | Main Assist name or `"automatic"` / `"manual"`.                                                                         |
| **TargetFilter**   | `'0'`         | Mob list filter (0/1/2).                                                                                                |
| **petassist**      | `false`       | Send pet on engage target.                                                                                              |
| **acleash**        | 75            | Camp leash distance.                                                                                                    |
| **followdistance** | 35            | Follow distance: beyond this distance the bot stands and runs follow; within it, sit is allowed when mana &lt; sitmana. |
| **zradius**        | 75            | Vertical range from camp for mob list.                                                                                  |
| **spelldb**        | `'spells.db'` | Spell database file.                                                                                                    |

### Pull section

See [Pull Configuration and Logic](pull-configuration.md) for the full pull table. Options include: **spell** (single block: gem, spell, range), **radius**, **zrange**, **minlevel**, **maxlevel**, **chainpullcnt**, **chainpullhp**, **mana**, **manaclass**, **leash**, **usepriority**, **hunter**.

### Melee section

| Option        | Default       | Purpose                                       |
| ------------- | ------------- | --------------------------------------------- |
| **assistpct** | 99            | MA target HP % at or below which to sync.     |
| **stickcmd**  | `'hold uw 7'` | Stick command when engaging.                  |
| **offtank**   | `false`       | This bot is an offtank.                       |
| **otoffset**  | 0             | Which add to pick when MT and MA on same mob. |
| **minmana**   | 0             | Min mana % to engage.                         |

Combat abilities (disciplines, /doability) are configured as **debuff** entries with **gem** `'disc'` or `'ability'`; **dodebuff** must be on for them to run. See [Melee combat abilities](melee-combat-abilities.md).

### Heal / Buff / Debuff / Cure sections

- **heal:** Top-level: **rezoffset**, **interruptlevel**, **xttargets**. Spell entries: **gem**, **spell**, **alias**, **announce**, **minmana**, **minmanapct**, **maxmanapct**, **enabled**, **tarcnt** (optional; group heals only), **bands**, **precondition** (optional; default true; boolean or Lua script when set). See [Healing configuration](healing-configuration.md).
- **buff:** Spell entries: **gem**, **spell**, **alias**, **announce**, **minmana**, **enabled**, **bands**, **spellicon**, **precondition** (optional; default true; boolean or Lua script when set). See [Buffing configuration](buffing-configuration.md). Bards: see [Bard configuration](bard-configuration.md).
- **debuff:** Spell entries: **gem**, **spell**, **alias**, **announce**, **minmana**, **enabled**, **bands** (band options include **mintar**/**maxtar** for camp mob-count gate), **charmnames**, **recast**, **delay**, **precondition** (optional; default true; boolean or Lua script when set). See [Debuffing configuration](debuffing-configuration.md) and [Spell targeting and bands](spell-targeting-and-bands.md).
- **cure:** Spell entries: **gem**, **spell**, **alias**, **announce**, **minmana**, **curetype**, **enabled**, **bands** (add **priority** to band **targetphase** to run in the priority cure pass; no top-level setting), **precondition** (optional; default true; boolean or Lua script when set). See [Curing configuration](curing-configuration.md).

**Example: one heal spell entry**

```lua
{
  ['gem'] = 1,
  ['spell'] = 'Superior Healing',
  ['alias'] = 'cht',
  ['minmana'] = 0,
  ['minmanapct'] = 0,
  ['maxmanapct'] = 100,
  ['bands'] = {
    { ['targetphase'] = { 'tank', 'pc' }, ['validtargets'] = { 'all' }, ['min'] = 0, ['max'] = 70 }
  }
}
```

---

## Where to configure

- **Config file:** Edit **`cz_<CharName>.lua`** in your MQ config directory. Reload by re-running the bot or using **import** / **setvar**.
- **Runtime only (not in config file):** **ExcludeList**, **PriorityList** (pull exclude/priority), and **pullarc** (directional pull) are set at runtime via **/cz exclude**, **/cz priority** (add/remove), and **/cz xarc**. Exclude and priority lists are stored per zone in the common config file **cz_common.lua** and are saved automatically when you add or remove entries.
- **Both:** Most options can be set in the config file or at runtime via **/cz setvar** (e.g. **setvar settings.petassist true**), which writes back to the config file.
