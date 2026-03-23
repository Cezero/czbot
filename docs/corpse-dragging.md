# Corpse Dragging

This document explains **corpse dragging**: how the bot automatically finds and drags peer members’ corpses when **dodrag** is on, and the **draghack** option (use **sumcorpse** instead of walking to the corpse). It is intended for operators who want the bot to retrieve group/peer corpses.

## Overview

When **dodrag** is on, the bot periodically (about once per second) looks for a **peer bot’s corpse** within range. Peer bots are those known to the bot via the actor net (charinfo); they need not be in the bot’s group. Behavior depends on whether camp is set:

- **No camp set (carry mode):** The bot looks only nearby (within `settings.acleash`), picks one corpse with **/corpsedrag**, and keeps carrying it. While already carrying that corpse, it does not pick another.
- **Camp set (fetch-return mode):** The bot finds peer corpses up to 1500 distance, runs to one, targets it and uses **/corpsedrag**, then returns to camp, targets that corpse, and uses **/corpsedrop** before looking for another corpse.
- **DragHack path:** When **draghack** is on (runtime only), the bot instead targets the corpse and uses **/sumcorpse** to bring the corpse to the bot, so the bot does not need to walk to the corpse. This avoids needing a navigation path to the corpse.

Only one corpse is handled at a time. Only corpses of **peer** members are considered.

---

## Config file reference

### Settings

| Option | Default | Purpose |
|--------|--------|---------|
| **dodrag** | `false` | When `true`, enable automatic corpse dragging: the bot looks for peer corpses within range and drags them (or uses sumcorpse when draghack is on). |

There is no separate drag section; only **settings.dodrag** applies.

**Example (in settings):**

```lua
['settings'] = {
  ['dodrag'] = true
}
```

---

## Runtime control

- **Toggle corpse dragging:** `/cz dodrag on` or `/cz dodrag off` (or `/cz dodrag` to toggle).
- **Toggle DragHack (sumcorpse):** `/cz draghack on` or `/cz draghack off` (or `/cz draghack` to toggle). When on, the bot uses **/sumcorpse** to pull the corpse to the bot instead of walking to the corpse and using **/corpsedrag**. **DragHack** is not stored in the config file; it is runtime-only.

---

## Behavior summary

- **Which corpses:** The bot considers only corpses of **peer** members. A peer is any character on the actor net (charinfo); they need not be in the bot’s group. It evaluates each peer corpse (e.g. `<name>'s corpse`) and picks the **furthest** eligible corpse in the current mode. In camp fetch-return mode, corpses already at camp are ignored. See [Out-of-group peers](out-of-group-peers.md) for the definition of peer and other out-of-group behavior.
- **Distance by mode:** A corpse is only considered if it is between **10** and max range for the current mode. No-camp carry mode uses **settings.acleash**. Camp fetch-return mode uses **1500**.
- **Normal drag:** The bot targets the corpse, turns off attack and stick, (Rogue: activates sneak/hide), then navigates to the corpse. When the bot is within **90** distance of the corpse, it re-targets and issues **/corpsedrag**. In camp fetch-return mode, it then navigates back to camp, re-targets that corpse, issues **/corpsedrop**, and only then selects another corpse. A valid navigation path to the corpse is required; if the bot cannot path to the corpse, the walk method will not complete.
- **DragHack (sumcorpse):** When **draghack** is on, the bot targets the corpse and uses **/sumcorpse** so the corpse is summoned to the bot. This does not require moving to the corpse and works even when there is no navigation path.

---

## Caveats

- **One corpse at a time:** In camp fetch-return mode, the bot fetches one corpse, returns to camp, then looks for the next. In no-camp carry mode, it keeps one corpse and does not swap to another unless that carried corpse is gone.
- **Peers only:** Only corpses of characters that are peers (actor net / charinfo) are considered; they may be in or out of the bot’s group.
- **Path required (normal path):** The walk-to-corpse method requires a valid navigation path to the corpse. Use **draghack** (sumcorpse) if the corpse is in an area the bot cannot path to.
