# Out-of-group peers

This document explains how the bot interacts with **peers** who are not in the bot’s group: who counts as a peer, how the bot sees their state, and how healing, buffing, curing, corpse rez, and corpse dragging treat them.

## What is a peer?

A **peer** is any character known to the bot via the **actor net** (charinfo). Other CZBot (or compatible) clients publish their character data (HP, buffs, detrimentals, pet state, etc.) to this shared state. The bot’s peer list is built from that data; peers do **not** have to be in the bot’s group. So you can have multiple bots in the same zone (or raid) on the same network, and they will see each other as peers even when they are in different groups.

## How the bot sees peers

The bot uses charinfo to know a peer’s current state without needing them in group: HP (`PctHPs`), buffs and short buffs, detrimentals (and cure-type counters), pet HP, and so on. That allows the bot to:

- Heal a peer when their HP is in the spell’s band (and in range).
- Cure a peer when they have a matching detrimental (and in range).
- Buff a peer when they need the buff and match the band (and in range).
- Rez or drag a peer’s corpse when the spell or drag logic allows it.

All of this works for peers who are outside the bot’s group, as long as the relevant configuration allows it (see below).

## Behavior by system

| System | Group restriction? | Out-of-group peers |
|--------|--------------------|--------------------|
| **Healing (PC)** | Only when **`group`** is in the heal band’s **validtargets** list. | If the band does **not** include **`group`**, the bot may heal any peer in range whose HP is in the band (HP from charinfo). See [Healing configuration](healing-configuration.md). |
| **Healing (pets)** | None. | Any peer’s pet in range with HP in band can be healed. |
| **Buffing** | None. | Any peer (and their pet) in range that matches the band and needs the buff can be buffed. See [Buffing configuration](buffing-configuration.md). |
| **Curing** | **`group`** in bands only affects the **first** pass: the bot considers only peers who are in the bot’s group. A **second** pass considers **all** peers by class (no group check). | Out-of-group peers can be cured in that second pass. See [Curing configuration](curing-configuration.md). |
| **Corpse rez** | No “in group” requirement for the **bots** filter. | With **bots** in the rez spell’s bands, any peer’s corpse in range can be rezzed. |
| **Corpse drag** | None. | Any peer’s corpse in range can be dragged. See [Corpse dragging](corpse-dragging.md). |

## Configuration knobs

- **Heal bands:** Include **`group`** in the band’s **validtargets** list to restrict single-target PC (and tank) heals to **peers who are in the bot’s group**. Omit **`group`** to allow healing any peer in range (including out-of-group) when their HP is in the band.
- **Cure bands:** Include **`group`** to add a first pass that only considers in-group peers (by class). The bot still runs a second pass over all peers by class, so out-of-group peers can be cured in that pass. Omit **`group`** to have only the all-peers pass.

For full details on bands and options, use the linked configuration documents above.
