---
name: solo-sim
description: Run the solo mining simulation (scripts/studio/solo_mining_sim.luau) in Roblox Studio and report per-day gold, iron, uranium, upgrade days, Geiger hunts, and the day the uranium target is reached. Use when someone asks to run, rerun, or tweak the solo sim, the mining sim, the scripted miner, or asks how a GameData change (pick axe, backpack, rock HP, prices, Geiger Counter, mine layout) moves a solo player's income or win day.
---

# Solo mining sim

`scripts/studio/solo_mining_sim.luau` simulates a scripted solo Recruit on Deadman's Canyon (Normal) for 15 days over many real mines from `MineGenerator.generate`. It reads every number from GameData, so a GameData edit shows up in the next run once Rojo has synced it. The rules it plays by, and the latest results, are in `docs/solo-mining-sim.md`. Read that first when someone asks what the sim assumes.

It is a tool, not shipped code. Never change GameData to make the sim run; change the sim's CONFIG instead.

## Before running

1. Studio's **Gameplay** place must be open in **Edit** mode (not Play), with the Rojo plugin connected to `scripts/serve.sh gameplay` (port 34873), so GameData in Studio matches the repo. Check with `get_studio_state` and `list_roblox_studios`. Pick the Gameplay studio's id. If Rojo is not connected, tell the user; do not restart their servers.
2. Never require `MineManager` or `GameController` from the Edit datamodel: they leave a stray RemoteEvent behind. The script only requires shared modules and GameData.

## Running

The script runs through the Studio MCP `execute_luau` tool in the `Edit` datamodel. Its source is passed as the `code` argument; Studio cannot read files from disk, and HTTP is off in this place (do not turn it on).

Settings are set through globals in the same call, ahead of the pasted source:

```lua
_G.SoloMiningSimDefineOnly = nil
_G.SoloMiningSimConfig = { SEEDS = 200 }   -- any CONFIG keys; nil for the defaults
_G.SoloMiningSimBackground = true
-- ...then the whole of scripts/studio/solo_mining_sim.luau...
```

- A full run (200 seeds with the Geiger rule) takes several minutes, longer than an `execute_luau` call may last. Always use `_G.SoloMiningSimBackground = true`. The call returns `started; poll _G.SoloMiningSimReport` straight away.
- Then poll with short calls until the report is there. Never wait in one long call:

```lua
for _ = 1, 25 do
	if _G.SoloMiningSimReport then break end
	task.wait(2)
end
return _G.SoloMiningSimReport or "still running"
```

- A report that starts with `ERROR:` is a failed run. The self-checks (each day's time adds to 320 s, ore is conserved, bedrock is never mined) raise errors on purpose, so read the message before rerunning.
- For a quick look, run `SEEDS = 20` first (well under a minute), then the full 200.
- The connection to Studio sometimes drops for a call ("Target is not reachable"). Retry the same small call. A background run keeps going in Studio meanwhile.

## CONFIG keys worth knowing

| Key | Default | What it does |
|---|---|---|
| `SEEDS` | 200 | mines simulated (seed i is i × 7919, the same seeds in every run, so two runs compare fairly) |
| `DAYS` | 15 | in-game days per run |
| `STALL_HITS` | 7 | a line stops on stone needing this many hits (7 means stone two tiers above the pick) |
| `IS_GEIGER_ENABLED` | true | false is the plain line digger with no Geiger Counter |
| `GEIGER_BUY_ZONE` / `HUNT_FROM_ZONE` | 5 / 4 | zones counted 0–5 from the mouth: where the counter goes on sale, and where hunts start |
| `HUNT_MAX_STEPS`, `HUNT_CLEAR_CELLS` | 10, 25 | limits on one hunt sweep and on the final dig around a rock |
| `SPACINGS` | `{ 3 }` | line spacing. Only spacing 3 is run (designer, 2026-10-28) |

An unknown key stops the run with an error, so a typo never passes silently.

## Reading and reporting the result

The report has these tables, each figure as mean (p10/p50/p90) across seeds:
- gold, iron and uranium per day and running totals;
- pick and backpack levels, gold spent and left, deepest block, lines, pockets;
- the time split per day (swinging stone, swinging ore, hunting, walking, refining and shopping, stuck, idle);
- Geiger level and hunts per day;
- upgrade buy days;
- the first stall per pick level;
- the day uranium 35 is refined and the night the rescue is won.

When reporting, lead with the answer to what was asked. Compare against the latest results in `docs/solo-mining-sim.md` whenever it helps. When a rerun changes the conclusions, offer to update that doc.

## Deeper checks

The same source with `_G.SoloMiningSimDefineOnly = true` only defines `_G.SoloMiningSim` (`simulateRun`, `runVariant`, `describe`, `traceSeed`, `stats`). Use it for one-off questions:
- `_G.SoloMiningSim.traceSeed(7919, 3, 7, 24)` prints day 1's event log, plus slices of the mine before and after, for checking by hand.
- `_G.SoloMiningSim.simulateRun(seed, 3, 7, events, day)` fills `events` with any one day's log, hunts included.
