# CHChain Configuration

CHChain rotates **Complete Heal** casts across clerics listed in **`ch_healers`** (cz_common), healing the first alive tank from **`mt_list`**. Each participating cleric runs an **absolute slot clock** locally after a shared start — there is no per-cast baton messaging. Start/stop use the **czbot actor channel**; optional chat mirror is display-only.

## Setup

1. **Roles** tab → populate `mt_list` (tank priority).
2. **CH Chain** tab → populate `ch_healers`, timing, options.
3. On each cleric in the list: turn on **CH Chain enabled** (or `/cz chchain on`). This is a doHeal-style feature flag — normal heals/buffs continue until the chain starts. Persists in char settings.
4. Start the chain from **any bot** (e.g. driving toon hotkey): **Start Chain** or `/cz chchain start`. That publishes `kickoff`; enabled clerics arm a local clock (`now + startCountdownMs`), enter exclusive mode, and fire by slot after countdown.

Changes to `ch_healers`, `ch_chain` settings, and shared lists persist to `cz_common.lua` and auto-sync to peers via **`common_sync`** on the czactor channel. Manual **`/cz reloadcommon`** remains a fallback.

## Commands

| Command | Action |
|---------|--------|
| `/cz chchain on` | Local opt-in (`settings.doChchain`); must be in `ch_healers`. Does not start the chain or suppress heals. |
| `/cz chchain off` | Local opt-out only (does not stop peers' chain). |
| `/cz chchain start` | From any bot: publish `chchain_control kickoff`. Participants arm slot clocks (countdown then fire by slot). |
| `/cz chchain stop` | Deactivate chain + interrupt local cast if slotted; publishes stop. Participation flag stays on. |
| `/cz chchain test` | Single test cast (auto-enables if needed). |
| `/cz chchain delay [ms]` | Set/read **slot delay** (`delayMs` — spacing between healer slots). |

## Actor messages

| id | Purpose |
|----|---------|
| `chchain_control` | `start`, `stop`, `kickoff` — arm or clear the shared schedule |
| `chchain_curtank` | Tank index sync during active chain (failover while casting) |
| `common_sync` | Auto-sync `cz_common` fields (`ch_healers`, `ch_chain`, `mt_list`, etc.) |
| `mt_update` | Manual `/cz tank set <name>` — CH-enabled bots update local curtank (no `chchain_curtank` broadcast) |
| *(none)* | Automatic MT resolution updates local curtank via `tankrole` refresh (no `chchain_curtank` broadcast) |

## Timing model

- On start/kickoff each enabled bot sets `chainStart = now + startCountdownMs` (default 3000).
- Cycle length: `delayMs * #ch_healers`. Slot *N* fires once per cycle when `timeIntoCycle >= (N-1)*delayMs` (**catch-up**: a late tick still fires; it does not wait a full rotation). Ideal timing is within 250ms of slot time.
- No baton / `your next` handoff for timing. Optional chat mirror may still announce casts/cancels.
- Pre-land cancel: after cast starts, once `preCastHpCheckMs` elapsed, if tank HP ≥ `healthThreshold` → interrupt.
- **Exclusive mode:** while the chain is active on a participating cleric, start interrupts other casts, and the mainloop only runs hooks with priority ≤ `chchainTick` (500). Camp/follow (`runWhenBusy`) is skipped so the slot clock stays accurate. PreCH also disables heal/buff/melee/cure/pull flags; both restore on **stop**.
- **Debug:** `ch_chain.debug` defaults to **true** and prints `[CHChain]` console lines for control, schedule, fire, cast, and cancel. Toggle on the CH Chain tab.

Legacy `broadcastDelayMs` / `cancelWindowMs` in `cz_common` are migrated: delay copies into `delayMs`; cancel window is dropped in favor of `preCastHpCheckMs`.

## MT coordination

When **`mt_update`** or automatic MT resolution changes the MT, CH-enabled bots update **`chchainCurtank`** locally via `chchain.syncCurtankFromMtName`. **`chchain_curtank`** is broadcast only during active chain failover (`selectHealTank`). Manual `/cz tank set` also promotes the name to front of `mt_list` when reason is `manual`.

## See also

- [CZBot Actor channel](czbot-actor-channel.md)
- [Automatic MA/MT Selection](automatic-ma-mt-selection.md) — `mt_list`, `lib/auto_ma_mt.lua`
- [Hook: chchainTick](botlogic/hook-chchain.md)
