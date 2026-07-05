# CHChain Configuration

CHChain rotates **Complete Heal** casts across clerics listed in **`ch_healers`** (cz_common), healing the first alive tank from **`mt_list`**. All chain control uses the **czbot actor channel**; optional chat mirror is display-only.

## Setup

1. **Roles** tab → populate `mt_list` (tank priority).
2. **CH Chain** tab → populate `ch_healers`, timing, options.
3. On each cleric in the list: enable **CH Chain** (or `/cz chchain on`).
4. Start the chain from the first cleric: **Start Chain** or `/cz chchain start`.

Changes to `ch_healers`, `ch_chain` settings, and shared lists persist to `cz_common.lua` and auto-sync to peers via **`common_sync`** on the czactor channel. Manual **`/cz reloadcommon`** remains a fallback.

## Commands

| Command | Action |
|---------|--------|
| `/cz chchain on` | Enable on this cleric (must be in `ch_healers`); publishes `chchain_control start` |
| `/cz chchain off` | Disable and restore PreCH settings; publishes stop |
| `/cz chchain start` | Kickoff cast + `chchain_control kickoff` |
| `/cz chchain test` | Single test cast (auto-enables if needed) |
| `/cz chchain delay [ms]` | Set/read baton delay (ms into cast) |

## Actor messages

| id | Purpose |
|----|---------|
| `chchain_baton` | Hand off to next cleric (sole cast trigger) |
| `chchain_control` | `start`, `stop`, `kickoff` |
| `chchain_curtank` | Tank index sync during active chain (failover while casting) |
| `common_sync` | Auto-sync `cz_common` fields (`ch_healers`, `ch_chain`, `mt_list`, etc.) |
| `mt_update` | Manual `/cz tank set <name>` — CH-enabled bots update local curtank (no `chchain_curtank` broadcast) |
| `im_mt` | Automatic MT claims — CH-enabled bots update local curtank on adoption (no `chchain_curtank` broadcast) |

## Cast behavior

- Poll-based cast: baton at `broadcastDelayMs`, cancel in final `cancelWindowMs` if tank HP ≥ threshold.
- Cast must start before baton is sent.
- Per-cleric CH range check on `mt_list`; mana skip; fizzle recast; corpse interrupt + baton.
- While active, normal heal/buff/debuff/melee/cure/pull are suppressed (restored on off).

## MT coordination

When **`mt_update`** or **`im_mt`** changes the MT, CH-enabled bots update **`chchainCurtank`** locally via `chchain.syncCurtankFromMtName`. **`chchain_curtank`** is broadcast only during active chain failover (`selectHealTank`) or when the chain is enabled. Manual `/cz tank set` also promotes the name to front of `mt_list` when reason is `manual`.

## See also

- [CZBot Actor channel](czbot-actor-channel.md)
- [Automatic MA/MT Selection](automatic-ma-mt-selection.md) — `mt_list`, `lib/auto_ma_mt.lua`
- [Hook: chchainTick](botlogic/hook-chchain.md)
