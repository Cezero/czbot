# CZBot Actor Channel

CZBot peers coordinate through a dedicated **Actor mailbox** (`czbot`) on the same MacroQuest Actor network as **MQCharinfo**. Independent clients (not on charinfo) are outside this system.

## Requirements

- **MQCharinfo** and the Lua **`actors`** module (loaded in [`init.lua`](../init.lua)).
- All coordinated bots must run CZBot so they register the `czbot` mailbox.

## Diagnostics

| Command | Purpose |
|---------|---------|
| `/cz actor ping` | Broadcast ping (diagnostic); peers update liveness from any czbot message, not unicast replies |
| `/cz actor status` | Peers, manual MA/MT overrides, OT claims, rez claims, MA engaged target, queue depth/head/tail, drain/drop counters, inbound id histogram |
| `/cz actordebug on/off` | Log `ma_update` / `mt_update` send/recv when enabled |
| `/cz actordebug queue [on/off]` | Throttled inbound queue enqueue/drain/drop stats (not per-message spam) |

The `czbot` mailbox is registered once at macro startup and removed on macro exit. If `/cz actor status` shows **`mailbox=MISSING`**, registration failed at startup — **restart the czbot macro** (or the EQ client if a prior session left a stale mailbox). Actor coordination (`followme`, `camphere`, `attack`, MA/MT, etc.) will not work until registration succeeds.

**Peer liveness:** `CzActorPeers` timestamps update when **any** inbound czbot message is received (role claims, combat broadcasts, etc.). Periodic broadcast `ping` (every 60s, staggered per bot) is diagnostic only — receivers do **not** send unicast `pong` replies.

**Traffic / queue:** `/cz actor status` reports a rolling traffic window (age shown in ms) with `recv`, `enqueued`, `drained`, `dropped`, and send counters, plus inbound/dropped id histograms. Inbound messages use an O(1) head/tail queue (cap 1000, drain budget per tick); follow commands still front-insert on the same queue.

## Message types

| id | Purpose |
|----|---------|
| `ping` | Optional diagnostic broadcast (no unicast reply; liveness from any message) |
| `pong` | Deprecated (ignored if received from older peers) |
| `ot_claim` / `ot_release` / `ot_heartbeat` | Off-tank add coordination (first-claimer-wins on conflicts) |
| `rez_claim` | Rez coordination — peer excludes claimed corpse for 60s ([Rez coordination](#rez-coordination)) |
| `ma_update` | Manual MA override from `/cz assist set <name>` (peers on `automatic` follow until unavailable) |
| `mt_update` | Manual MT override from `/cz tank set <name>` |
| `ma_engaged` | MA bot engaged a target — one-shot signal; peers resolve ongoing target via Charinfo ([MA engage coordination](#ma-engage-coordination)) |
| `ma_disengage` | MA bot cleared engagement — peers resume follow-leash behavior |
| `attack` | Group/raid attack broadcast from `/cz attack` — peers engage spawn ID immediately ([Group attack](#group-attack)) |
| `follow_me` / `follow_me_off` | Leader follow broadcast (replaces `/rc` for `/cz followme`) |
| `camp_here` / `camp_here_off` | Leader camp broadcast (replaces `/rc` for `/cz camphere`) |
| `chchain_control` | CH chain start / stop / kickoff (arms local slot clocks) |
| `chchain_curtank` | CHChain tank index sync during active chain (failover, enable) — not sent for automatic local MT resolution / `mt_update` |
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

Offtanks **always** try to claim a free add first (regardless of whether MT and MA share a target):

1. Builds add candidates from `MobList` (excluding MA/MT targets, charm-skipped mobs, and mezzed spawns).
2. Skips adds already claimed by another peer (**first-claimer-wins**; live claims are not stolen).
3. Claims the lowest spawn ID among eligible adds via `ot_claim` (stores immutable `claimedAt`; heartbeats refresh TTL only).
4. Releases on disengage, mob death, or when yielding to an earlier peer claim (older `claimedAt`, or equal `claimedAt` + lower character name).

When **no free add** remains, the offtank assists the MA target. See [Offtank configuration](offtank-configuration.md).

## MA engage coordination

When the **Main Assist** bot sets an engage target, it broadcasts a single **`ma_engaged`** with the NPC spawn ID (once per spawn ID; no heartbeat). In-scope peers (same group/raid, same zone) store this as `MaActorEngaged` for **awareness and side effects only** (follow catch-up, `/cz attack` latch clear) — not as an engage or assistpct bypass. Ongoing MA target resolution in `GetAssistInfo()` prefers **Charinfo peer Target**; `MaActorEngaged` is only a fallback identity when Charinfo has no valid NPC yet (so mez/notmatar can skip the MA kill target). When the MA switches to a different valid in-radius NPC (client Target adopt), it publishes one new **`ma_engaged`** for that spawn ID so peers refresh latch/follow side effects; peers then follow the live target via Charinfo under normal engage gates.

| Field | Purpose |
|-------|---------|
| `spawnId` | NPC spawn ID the MA is engaging |
| `scope` | `group` or `raid` |
| `mobName` | Optional clean name (diagnostics) |
| `zone` | Sender zone (receivers accept only same-zone senders) |

**`ma_disengage`** clears peer engaged state. Sent when the MA disengages for any reason (mob death, `/cz disengage`, camp pin, etc.).

**Peer behavior while MA is engaged:**

- OT add selection, notmatar debuffing, and other MA-target-aware logic use Charinfo for the MA’s live Target (with `ma_engaged` as a short fallback when Charinfo lags).
- DPS melee still waits for **`melee.assistpct`** and normal radius/MobList gates; **`ma_engaged` does not bypass them**. Force engage is only via **`/cz attack`**.
- When **`ma_engaged`** arrives with a **new** `spawnId`, peers clear a local **`attackCommandEngage`** latch so they can follow the MA retarget (`mtSticky` / offtank sticky still apply in their resolvers).
- Follow-leash behavior while MA is engaged uses an explicit **`followCatchUp`** flag on followers with active follow:
  - On **`ma_engaged`**, if the bot is beyond **`followdistance`**, **`followCatchUp`** is set: follow nav continues, combat (`doMelee`) is deferred, and spell hooks defer while closing.
  - Once within **`followdistance`**, **`followCatchUp`** clears and follow nav stays suppressed for the rest of the engagement (combat maneuvering may exceed follow distance without re-following the leader).
  - Followers already within leash at engage start skip catch-up; follow is suppressed immediately.
  - Cleared on **`ma_disengage`**, local disengage, **`StopFollow`**, death, or zone reset.

**Manual disengage:** `/cz disengage` on the MA broadcasts **`ma_disengage`** to peers. On a non-MA bot, it only disengages that bot locally.

## Group attack

When any peer runs **`/cz attack`**, it resolves the assist’s **live** Target (not sticky `ma_engaged`) and broadcasts **`attack`** with that NPC spawn ID (`scope` = raid if the issuer is raided, else group; same-zone only). In-scope peers **silently** set `attackCommandEngage` and `engageTargetId` to that spawn and engage immediately, bypassing **`melee.assistpct`**. The issuer is the only chat announcer (`Engaging … now`); peers do not log engage. Prefer running **`/cz attack` on one box** — it already broadcasts (do not `/dgga`/`/bcaa` it).

| Field | Purpose |
|-------|---------|
| `spawnId` | NPC spawn ID all peers should attack |
| `scope` | `group` or `raid` |
| `issuer` | Character who ran `/cz attack` (scope filter) |
| `mobName` | Optional clean name |
| `assistName` | Optional: assist name used to resolve the target |
| `zone` | Sender zone (receivers accept only same-zone senders) |

Unlike **`ma_engaged`**, which is awareness/fallback identity (and follow/latch side effects) without forcing DPS melee, **`attack`** forces immediate engagement on all receivers (same as local `/cz attack`). Same-spawn republish is latched until disengage/abort/death so peers stay locked without engage re-fire chatter.

## Rez coordination

When multiple bots have corpse rez configured, each rezzer:

1. Builds eligible corpses ordered by class priority (healers first).
2. Picks the first corpse not claimed by another peer in the same zone.
3. Broadcasts **`rez_claim`** with the corpse spawn ID.
4. Peers exclude that corpse from their available pool for **60 seconds** (TTL pruned automatically).

There is no release message — a successful rez removes the corpse from the candidate list; a failed rez becomes eligible again after the TTL expires. Simultaneous claims on the same corpse are allowed (first cast to land wins). See [Healing configuration](healing-configuration.md).

## Manual MA/MT overrides (`ma_update` / `mt_update`)

Automatic MA/MT resolution is **local** on each bot (EQ roles + lists). See [Automatic MA/MT Selection](automatic-ma-mt-selection.md).

**`/cz assist set <name>`** and **`/cz tank set <name>`** publish **`ma_update`** / **`mt_update`** with `reason=manual`. Receivers on **`automatic`** store the name in `ActorMaOverride` / `ActorMtOverride` until that PC is dead/out of zone or a newer seq arrives. Manual overrides beat local automatic resolution while valid.

CH-enabled bots update local curtank from **`mt_update`** (and from automatic MT changes via `lib/tankrole.lua`) without a separate `chchain_curtank` broadcast for those events.

## Healer OT band

Heal spells with **`offtank`** in **targetphase** target peers with a live OT claim (between **tank** and **groupmember** in evaluation order). HP comes from charinfo when available.

## Multibox test checklist

- [ ] `/cz actor ping` shows all box peers
- [ ] Two OTs on same camp pick different adds; conflict yields to newer claim
- [ ] OT idles when all adds claimed
- [ ] MA death: each bot re-resolves MA from group role then `ma_list` on next refresh
- [ ] Startup / zone: automatic MA/MT available immediately from EQ + lists (no actor discovery)
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
