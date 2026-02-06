# CZBot Documentation Index

Short index of all documentation pages. Use this to find the right doc for configuring healing, tanking, pulling, buffing, debuffing, curing, pets, nuking, mezzing, and melee combat abilities.

---

## Role and combat


| Document                                          | Description                                                                                                                   |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| [Tank and Assist Roles](tank-and-assist-roles.md) | How to configure Main Tank (MT), Main Assist (MA), and Puller; who gets heals, who picks targets, and how DPS/offtank follow. |
| [Tanking configuration](tanking-configuration.md) | Melee/tank settings: stick command, assist %, camp leash, and links to roles and pull.                                        |
| [Offtank configuration](offtank-configuration.md) | How to configure an offtank: same target (pick add) vs different target (tank MA’s target).                                   |


## Pulling and movement


| Document                                              | Description                                                                                                                             |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| [Pull Configuration and Logic](pull-configuration.md) | How pulling works: config options, when the bot starts a pull, pre-conditions, hunter mode, runtime commands (xarc, exclude, priority). |
| [Corpse dragging](corpse-dragging.md)                 | Automatic drag of peer corpses (dodrag); draghack uses sumcorpse.                                                                      |


## Raid


| Document                          | Description                                                                                                      |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| [Raid mode](raid-mode.md)         | What the doraid toggle does (raid mechanic mode), raid save/load commands, and how they affect bot behavior.   |


## Spells and effects


| Document                                              | Description                                                                                               |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| [Healing configuration](healing-configuration.md)     | Heal spells, bands (who and at what HP), rez, interrupt, XT targets, commands.                            |
| [Buffing configuration](buffing-configuration.md)     | Buff spells, bands (self, tank, validtargets, mypet, pet, petspell), spellicon, combat vs idle.                  |
| [Debuffing configuration](debuffing-configuration.md) | Debuff spells, bands (tanktar, notanktar, named), charmnames, recast, delay; links to nuking and mezzing. |
| [Spell targeting and bands](spell-targeting-and-bands.md) | Targeting logic and band tags for all spell types (heal, buff, debuff, cure); evaluation order, tarcnt, tanktar/notanktar. |
| [Curing configuration](curing-configuration.md)       | Cure spells, curetype (all / poison / disease / curse / corruption), prioritycure, bands.                 |
| [Out-of-group peers](out-of-group-peers.md)            | Who counts as a peer, how healing, buffing, curing, and corpse drag treat peers outside your group.      |


## Nuking and mezzing (first-order)


| Document                                          | Description                                                                            |
| ------------------------------------------------- | -------------------------------------------------------------------------------------- |
| [Nuking configuration](nuking-configuration.md)   | How to set up nuking: configure nukes as debuffs (tanktar, notanktar).                 |
| [Mezzing configuration](mezzing-configuration.md) | How to set up mezzing: configure mez as debuffs (notanktar, charmnames), level limits. |
| [Melee combat abilities](melee-combat-abilities.md) | How to set up melee combat abilities: configure disciplines and /doability as debuffs (gem disc/ability); domelee + dodebuff. |


## Pets


| Document                                    | Description                                                                   |
| ------------------------------------------- | ----------------------------------------------------------------------------- |
| [Pets configuration](pets-configuration.md) | Pet summon (buff + petspell), petassist, pet buffing, charm (link to debuff). |


## Reference


| Document                                                                        | Description                                                         |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| [Commands and configuration reference](commands-and-configuration-reference.md) | Full list of /cz commands and all config file options in one place. |


