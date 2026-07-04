# CZBot Actor Channel

CZBot peers coordinate through a dedicated **Actor mailbox** (`czbot`) on the same MacroQuest Actor network as **MQCharinfo**. Independent clients (not on charinfo) are outside this system.

## Requirements

- **MQCharinfo** and the Lua **`actors`** module (loaded in [`init.lua`](../init.lua)).
- All coordinated bots must run CZBot so they register the `czbot` mailbox.

## Diagnostics

| Command | Purpose |
|---------|---------|
| `/cz actor ping` | Broadcast ping; list charinfo peers and last czbot reply time |
| `/cz actor status` | Peers, MA/MT Actor overrides, OT claims, rez claims, MA engaged target |

## Message types

| id | Purpose |
|----|---------|
| `ping` / `pong` | Peer discovery |
| `ot_claim` / `ot_release` / `ot_heartbeat` | Off-tank add coordination (last-writer-wins on conflicts) |
| `rez_claim` | Rez coordination — peer excludes claimed corpse for 60s ([Rez coordination](#rez-coordination)) |
| `ma_update` | Manual session MA override from `/cz assist <name>` (beats automatic claims) |
| `mt_update` | Manual session MT override from `/cz tank <name>`; also publishes `chchain_curtank` |
| `im_ma` | Automatic MA claim — holder heartbeats every 2s while eligible |
| `im_mt` | Automatic MT claim — holder heartbeats every 2s while eligible |
| `release_ma` | Holder relinquishing MA (death, hover, or ineligible) |
| `release_mt` | Holder relinquishing MT (death, hover, or ineligible) |
| `ma_engaged` | MA bot engaged a target — peers learn spawn ID immediately ([MA engage coordination](#ma-engage-coordination)) |
| `ma_disengage` | MA bot cleared engagement — peers resume follow-leash behavior |
| `attack` | Group/raid attack broadcast from `/cz attack` — peers engage spawn ID immediately ([Group attack](#group-attack)) |
| `follow_me` / `follow_me_off` | Leader follow broadcast (replaces `/rc` for `/cz followme`) |
| `camp_here` / `camp_here_off` | Leader camp broadcast (replaces `/rc` for `/cz camphere`) |
| `chchain_baton` | CH chain baton — sole trigger for next cleric cast ([CHChain configuration](chchain-configuration.md)) |
| `chchain_control` | CH chain start / stop / kickoff |
| `chchain_curtank` | CHChain shared tank index/name ([CHChain configuration](chchain-configuration.md)) |
| `common_sync` | Propagate `cz_common.lua` changes to peers (delta snapshot after any persisted edit) |

Protocol version: **1** (`ver` field on every message).

## cz_common sync (`common_sync`)

When any bot persists a change via `mutateCommon`, it broadcasts a **`common_sync`** message containing:

| Field | Purpose |
|-------|---------|
| `seq` | Monotonic sequence from the publishing bot |
| `publisher` | Clean character name of the bot that wrote disk |
| `delta` | Changed top-level keys and zone sub-keys (`{ top = {...}, zones = { [zone] = {...} } }`) |

Receivers:

1. Ignore stale messages (`seq` ≤ last seen for that `publisher`).
2. Read disk and compare to `delta`. If disk already matches (same machine / shared configDir), skip write.
3. Otherwise acquire **`cz_common.lock`**, re-check disk, apply delta, save, release lock.
4. Always reload in-memory state (`reloadAllFromCommon`).

Manual **`/cz reloadcommon`** remains a fallback when actor sync is unavailable.

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

## MA engage coordination

When the **Main Assist** bot sets an engage target, it broadcasts **`ma_engaged`** with the NPC spawn ID. In-scope peers (same group/raid, same zone) store this as `MaActorEngaged` and use it via `GetAssistInfo()` **before** charinfo target data.

| Field | Purpose |
|-------|---------|
| `spawnId` | NPC spawn ID the MA is engaging |
| `scope` | `group` or `raid` |
| `mobName` | Optional clean name (diagnostics) |
| `zone` | Sender zone (receivers accept only same-zone senders) |

**`ma_disengage`** clears peer engaged state. Sent when the MA disengages for any reason (mob death, `/cz disengage`, camp pin, etc.) or when **`release_ma`** is received from the engaged MA.

**Peer behavior while MA is engaged:**

- OT add selection, notmatar debuffing, and other MA-target-aware logic see the spawn ID immediately (no assist-at percentage wait).
- DPS melee still waits for **`melee.assistpct`** unless overridden with **`/cz attack`**.
- Follow-leash behavior is suppressed (`followdistance` disengage, follow nav, cast interrupts) until disengage or the engaged mob dies.

**Manual disengage:** `/cz disengage` on the MA broadcasts **`ma_disengage`** to peers. On a non-MA bot, it only disengages that bot locally.

## Group attack

When any peer runs **`/cz attack`**, it broadcasts **`attack`** with the resolved NPC spawn ID. In-scope peers (same group/raid, same zone) set `attackCommandEngage` and engage immediately, bypassing **`melee.assistpct`**.

| Field | Purpose |
|-------|---------|
| `spawnId` | NPC spawn ID all peers should attack |
| `scope` | `group` or `raid` |
| `issuer` | Character who ran `/cz attack` (scope filter) |
| `mobName` | Optional clean name |
| `assistName` | Optional: assist name used to resolve the target |
| `zone` | Sender zone (receivers accept only same-zone senders) |

Unlike **`ma_engaged`**, which informs peers of the MA target for OT/debuff without forcing DPS melee, **`attack`** forces immediate engagement on all receivers (same as local `/cz attack`).

## Rez coordination

When multiple bots have corpse rez configured, each rezzer:

1. Builds eligible corpses ordered by class priority (healers first).
2. Picks the first corpse not claimed by another peer in the same zone.
3. Broadcasts **`rez_claim`** with the corpse spawn ID.
4. Peers exclude that corpse from their available pool for **60 seconds** (TTL pruned automatically).

There is no release message — a successful rez removes the corpse from the candidate list; a failed rez becomes eligible again after the TTL expires. Simultaneous claims on the same corpse are allowed (first cast to land wins). See [Healing configuration](healing-configuration.md).

## Role overrides

When `AssistName` or `TankName` is **`automatic`**, MA/MT resolution uses **`im_ma`** / **`im_mt`** actor claims (see [Automatic MA/MT Selection](automatic-ma-mt-selection.md)).

**Claim messages (`im_ma` / `im_mt`):**

| Field | Purpose |
|-------|---------|
| `name` | Claimer character name |
| `seq` | Monotonic per-holder counter (heartbeat every 2s) |
| `scope` | `group` or `raid` |
| `source` | `primary` (EQ role) or `list` (`ma_list` / `mt_list`) |
| `listIndex` | 1-based list index; `0` for primary |
| `zone` | Claimer's zone (receivers accept only same-zone senders) |

**Release messages (`release_ma` / `release_mt`):** sent immediately on death/hover or when the holder becomes ineligible. Receivers run self-select and may publish a new `im_*` on the same tick.

**Receive rules:** scope filter (raid-strict; group allows cross-group assist when the group lacks an active MA/MT), sender same-zone filter, priority merge on conflict (in-group beats out-of-group). Receivers trust claims — no holder alive/leash re-check.

**Manual overrides:** `/cz assist <name>` and `/cz tank <name>` publish **`ma_update`** / **`mt_update`**, which beat automatic `im_*` claims until cleared.

## Healer OT band

Heal spells with **`offtank`** in **targetphase** target peers with a live OT claim (between **tank** and **groupmember** in evaluation order). HP comes from charinfo when available.

## Multibox test checklist

- [ ] `/cz actor ping` shows all box peers
- [ ] Two OTs on same camp pick different adds; conflict yields to newer claim
- [ ] OT idles when all adds claimed
- [ ] MA death: holder publishes `release_ma`; next eligible bot publishes `im_ma`; peers adopt within one heartbeat
- [ ] MA engages mob: peers show spawn in `/cz actor status`; OT/notmatar see target before assist-at
- [ ] `/cz disengage` on MA broadcasts `ma_disengage`; peers resume follow nav
- [ ] Melee bots sticking past followdistance do not disengage while MA engaged
- [ ] `/cz attack` on one box: all group/raid peers engage immediately (bypass assist-at)
- [x] `/cz followme` and `/cz camphere` work without MQRemote
- [ ] Healer with `offtank` phase heals OT peers in band

## See also

- [Offtank configuration](offtank-configuration.md)
- [Automatic MA/MT Selection](automatic-ma-mt-selection.md)
- [Healing configuration](healing-configuration.md)
