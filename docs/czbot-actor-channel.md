# CZBot Actor Channel

CZBot peers coordinate through a dedicated **Actor mailbox** (`czbot`) on the same MacroQuest Actor network as **MQCharinfo**. Independent clients (not on charinfo) are outside this system.

## Requirements

- **MQCharinfo** and the Lua **`actors`** module (loaded in [`init.lua`](../init.lua)).
- All coordinated bots must run CZBot so they register the `czbot` mailbox.

## Diagnostics

| Command | Purpose |
|---------|---------|
| `/cz actor ping` | Broadcast ping; list charinfo peers and last czbot reply time |
| `/cz actor status` | Peers, MA/MT Actor overrides, OT claims |

## Message types

| id | Purpose |
|----|---------|
| `ping` / `pong` | Peer discovery |
| `ot_claim` / `ot_release` / `ot_heartbeat` | Off-tank add coordination (last-writer-wins on conflicts) |
| `ma_update` / `mt_update` | Session MA/MT override (seq increases; used for death handoff and manual `/cz assist` / `/cz tank`) |
| `follow_me` / `follow_me_off` | Leader follow broadcast (replaces `/rc` for `/cz followme`) |
| `camp_here` / `camp_here_off` | Leader camp broadcast (replaces `/rc` for `/cz camphere`) |
| `chchain_curtank` | CHChain shared tank index/name when the chain advances past dead tanks ([CHChain configuration](chchain-configuration.md)) |

Protocol version: **1** (`ver` field on every message).

## Extension handlers

Messages beyond the built-in ids above can register handlers via [`lib/czactor_dispatch.lua`](../lib/czactor_dispatch.lua):

```lua
require('lib.czactor_dispatch').RegisterHandler('my_message_id', function(content, sender) ... end)
```

Publish with `require('lib.czactor').publish('my_message_id', { ... })`. Send and receive are logged to the MQ console as `czactor send ...` / `czactor recv ...`.

## Off-tank add selection

When MT and MA are on the **same** mob, each offtank:

1. Builds add candidates from `MobList` (excluding MA/MT targets and charm-skipped mobs).
2. Skips adds claimed by another peer with a **newer** `ts` (last-writer-wins).
3. Claims the lowest spawn ID among eligible adds via `ot_claim`.
4. Releases on disengage, mob death, or when yielding to a newer peer claim.

When MT and MA are on **different** mobs, the offtank still tanks the MA target (unchanged). See [Offtank configuration](offtank-configuration.md).

## Role overrides

When `AssistName` or `TankName` is **`automatic`**, Actor `ma_update` / `mt_update` messages provide a fast session override after primary game roles fail (e.g. MA death). Order:

1. EQ group/raid Main Assist / Main Tank when available
2. Actor override (highest `seq`)
3. `ma_list` / `mt_list` in `cz_common.lua`

Manual `/cz assist <name>` and `/cz tank <name>` (non-automatic) publish updates to peers.

## Healer OT band

Heal spells with **`offtank`** in **targetphase** target peers with a live OT claim (between **tank** and **groupmember** in evaluation order). HP comes from charinfo when available.

## Multibox test checklist

- [ ] `/cz actor ping` shows all box peers
- [ ] Two OTs on same camp pick different adds; conflict yields to newer claim
- [ ] OT idles when all adds claimed
- [ ] MA death: next `ma_list` entry publishes `ma_update`; peers follow new MA
- [ ] `/cz followme` and `/cz camphere` work without MQRemote
- [ ] Healer with `offtank` phase heals OT peers in band

## See also

- [Offtank configuration](offtank-configuration.md)
- [Automatic MA/MT Selection](automatic-ma-mt-selection.md)
- [Healing configuration](healing-configuration.md)
