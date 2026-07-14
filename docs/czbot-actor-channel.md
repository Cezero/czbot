# CZBot Actor Channel

CZBot peers coordinate through a dedicated **Actor mailbox** (`czbot`) on the same MacroQuest Actor network as **MQCharinfo**. Independent clients (not on charinfo) are outside this system.

## Requirements

- **MQCharinfo** and the Lua **`actors`** module (loaded in [`init.lua`](../init.lua)).
- All coordinated bots must run CZBot so they register the `czbot` mailbox.

## Diagnostics

| Command | Purpose |
|---------|---------|
| `/cz actor ping` | Broadcast ping (diagnostic); peers update liveness from any czbot message, not unicast replies |
| `/cz actor status` | Peers, MA/MT Actor overrides, OT claims, rez claims, MA engaged target, queue depth/head/tail, drain/drop counters, inbound id histogram, whos backoff |
| `/cz actordebug on/off` | Role-claim send/recv/reject logging (`im_*`, `whos_*`, `release_*`) |
| `/cz actordebug queue [on/off]` | Throttled inbound queue enqueue/drain/drop stats (not per-message spam) |

The `czbot` mailbox is registered once at macro startup and removed on macro exit. If `/cz actor status` shows **`mailbox=MISSING`**, registration failed at startup — **restart the czbot macro** (or the EQ client if a prior session left a stale mailbox). Actor coordination (`followme`, `camphere`, `attack`, MA/MT, etc.) will not work until registration succeeds.

**Peer liveness:** `CzActorPeers` timestamps update when **any** inbound czbot message is received (role claims, combat broadcasts, etc.). Periodic broadcast `ping` (every 60s, staggered per bot) is diagnostic only — receivers do **not** send unicast `pong` replies.

**Traffic / queue:** `/cz actor status` reports a rolling traffic window (age shown in ms) with `recv`, `enqueued`, `drained`, `dropped`, and send counters, plus inbound/dropped id histograms. Inbound messages use an O(1) head/tail queue (cap 1000, drain budget per tick); follow commands still front-insert on the same queue.

## Message types

| id | Purpose |
|----|---------|
| `ping` | Optional diagnostic broadcast (no unicast reply; liveness from any message) |
| `pong` | Deprecated (ignored if received from older peers) |
| `ot_claim` / `ot_release` / `ot_heartbeat` | Off-tank add coordination (last-writer-wins on conflicts) |
| `rez_claim` | Rez coordination — peer excludes claimed corpse for 60s ([Rez coordination](#rez-coordination)) |
| `ma_update` | Manual session MA override from `/cz assist set <name>` (beats automatic claims) |
| `mt_update` | Manual session MT override from `/cz tank set <name>` |
| `im_ma` | Automatic MA claim — published once on claim / takeover and when answering `whos_ma` |
| `im_mt` | Automatic MT claim — published once on claim / takeover and when answering `whos_mt` |
| `whos_ma` | Peer asking who holds MA (automatic mode, no usable actor override) |
| `whos_mt` | Peer asking who holds MT (automatic mode, no usable actor override) |
| `release_ma` | Holder relinquishing MA (death, hover, or ineligible) |
| `release_mt` | Holder relinquishing MT (death, hover, or ineligible) |
| `ma_engaged` | MA bot engaged a target — peers learn spawn ID immediately ([MA engage coordination](#ma-engage-coordination)) |
| `ma_disengage` | MA bot cleared engagement — peers resume follow-leash behavior |
| `attack` | Group/raid attack broadcast from `/cz attack` — peers engage spawn ID immediately ([Group attack](#group-attack)) |
| `follow_me` / `follow_me_off` | Leader follow broadcast (replaces `/rc` for `/cz followme`) |
| `camp_here` / `camp_here_off` | Leader camp broadcast (replaces `/rc` for `/cz camphere`) |
| `chchain_control` | CH chain start / stop / kickoff (arms local slot clocks) |
| `chchain_curtank` | CHChain tank index sync during active chain (failover, enable) — not sent for `im_mt` / `mt_update` |
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
- Follow-leash behavior while MA is engaged uses an explicit **`followCatchUp`** flag on followers with active follow:
  - On **`ma_engaged`**, if the bot is beyond **`followdistance`**, **`followCatchUp`** is set: follow nav continues, combat (`doMelee`) is deferred, and spell hooks defer while closing.
  - Once within **`followdistance`**, **`followCatchUp`** clears and follow nav stays suppressed for the rest of the engagement (combat maneuvering may exceed follow distance without re-following the leader).
  - Followers already within leash at engage start skip catch-up; follow is suppressed immediately.
  - Cleared on **`ma_disengage`**, local disengage, **`StopFollow`**, death, or zone reset.

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

**Claim messages (`im_ma` / `im_mt`):** published once when a bot first claims the role (or takes over after `release_*`), and once when answering a scoped `whos_*` request. Holders do **not** periodically rebroadcast.

| Field | Purpose |
|-------|---------|
| `name` | Claimer character name |
| `seq` | Monotonic per-holder counter |
| `scope` | `group` or `raid` |
| `source` | `primary` (EQ role) or `list` (`ma_list` / `mt_list`) |
| `listIndex` | 1-based list index; `0` for primary |
| `zone` | Claimer's zone (receivers accept only same-zone senders) |

**Who-is messages (`whos_ma` / `whos_mt`):** automatic peers with no usable actor override publish these with exponential backoff (~2s → ~30s; reset on successful `im_*`) until an `im_*` arrives. Same `scope` / `zone` envelope as claims. The current holder (or eligible claimer) responds with one `im_*` broadcast; in-scope peers adopt it. EQ primary / lists do not suppress these asks — they only decide claim eligibility.

**Release messages (`release_ma` / `release_mt`):** sent immediately on death/hover or when the holder becomes ineligible. Receivers run self-select and the next eligible bot may publish a new `im_*` on the same tick. Peers that still lack an override after that ask `whos_*` on the next periodic tick.

**Unavailable holder:** Overrides are cleared when the holder is dead/out of zone (missed `release_*`, e.g. crash). That triggers the same re-claim / `whos_*` path. Manual `ma_update` / `mt_update` overrides are not cleared by availability sweep the same way claim overrides are.

**Receive rules:** scope filter (raid-strict; group allows cross-group assist when the group lacks an active MA/MT), sender same-zone filter, priority merge on conflict (in-group beats out-of-group).

**Manual overrides:** `/cz assist set <name>` and `/cz tank set <name>` publish **`ma_update`** / **`mt_update`**, which beat automatic `im_*` claims until cleared. CH-enabled bots update local curtank from these messages without a separate `chchain_curtank` broadcast.

## Healer OT band

Heal spells with **`offtank`** in **targetphase** target peers with a live OT claim (between **tank** and **groupmember** in evaluation order). HP comes from charinfo when available.

## Multibox test checklist

- [ ] `/cz actor ping` shows all box peers
- [ ] Two OTs on same camp pick different adds; conflict yields to newer claim
- [ ] OT idles when all adds claimed
- [ ] MA death: holder publishes `release_ma`; next eligible bot publishes `im_ma`; peers adopt
- [ ] MA holder gone without release (kill, `/czp off`): peers clear override when holder unavailable; next claim or `whos_ma` → `im_ma` failover
- [ ] Startup / zone: peers without MA publish `whos_ma`; holder answers once with `im_ma`; then quiet until death/release
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
