# Solo mining sim

`scripts/studio/solo_mining_sim.luau` simulates a scripted solo player mining Deadman's Canyon, 15 days at a time, over 200 real mines from `MineGenerator.generate`.

- **What it answers:** what a fixed, simple way of mining earns per day, when the player can afford each upgrade, and the day the uranium target falls.
- **What it reads:** every number comes from GameData. So a tuning change shows up in the next run, before anyone plays it.
- **What it isn't:** it is not shipped (`scripts/` is outside every Rojo project), and it changes nothing in the place.

It complements `BalanceModel` (docs/balance-plan.md). The model is an average over zones, driven by assumed play shares. The sim digs the real grid block by block, with the rules below. Where they disagree, see "Against BalanceModel".

## Running it

- **With Claude Code:**
  - Ask it to "run the solo sim", or type `/solo-sim`.
  - The project skill in `.claude/skills/solo-sim` has the steps.
  - It needs the Studio MCP connection, Studio's Gameplay place open in Edit mode, and the Rojo plugin connected to `scripts/serve.sh gameplay`.
- **By hand:**
  - Copy the whole file into Studio's Command Bar (Gameplay place, Edit mode) and press Enter. The report prints to the Output window.
  - To change a setting, edit the CONFIG block at the top, or set `_G.SoloMiningSimConfig = { SEEDS = 50 }` before pasting.
  - 200 seeds take a few minutes.

## The player's rules

All rules were agreed with the designer on 2026-10-28. Zones are counted 0–5 from the mine mouth: depths 1–8, 9–20, 21–44, 45–68, 69–96 and 97–136.

**Who and when**
- A solo Recruit (no class modifiers) on Normal difficulty.
- The mine is generated once per run and kept across days.

**The day**
- The player mines only during the 320 s day.
- The last load is walked home, refined and spent after dark, and counts for that day.
- Each morning's walk back into the mine counts against that day.

**Digging lines**
- Lines are 1 block wide and 2 tall, on the entrance floor rows.
- They are dug from a cross-cut at the entrance's back row toward the far bedrock.
- Line columns are the centreline ± 3k, inside the mine's width. That gives 8 lines, taken centre first and then alternating outward.
- Spacing 2 was tried and lost in every comparison, so only spacing 3 is run.

**When a line stops: 7 hits**
- A line stops when any stone block in its next cross-section needs 7 or more hits with the current pick. Ore never stops a line.
- Why 7: hits come in steps of 1–3 (stone at the pick's own tier), 6 (one tier harder), 18 (two tiers harder) and 54. So 7 means "stop on stone two tiers above the pick".
- One tier harder still pays 45–70% of the best gold per minute of swinging. Two tiers harder pays 27–51%, at 8 s or more per block.
- A 4-hit rule left 93–97% of seeds stuck on day 1 and ended about 20% behind over 15 days. A 19-hit rule was also about 20% behind.

**Mining ore**
- Every exposed iron, gold and uranium rock within 3 blocks of the tunnel is mined, whatever it costs, and each break can expose more.
- A pocket the line opens is entered. Stairs are cut past any step taller than one block, since the jump clears 7.2 studs. All visible ore in the pocket is mined, then the player returns to the line.

**Trips and shopping**
- When the backpack is full, the player walks to the Refinery and refines.
- They then buy the cheapest next level of the pick axe, the backpack and, once it is on sale, the Geiger Counter, as long as they can afford it. A tie goes to the pick axe, then the backpack.
- Ore that did not fit in the backpack is picked up on return within its 120 s lifetime.
- Iron is never spent.

**Boots** (added 2026-10-29)
- Once the pick axe and the backpack are both at least 2 levels above the boots, the next boots level is bought before anything else.
- If the player can't afford it yet, they save for it and buy nothing else until they have it.
- Boots set the walk speed: 16 / 20 / 24 / 28 / 32 studs a second.
- The backpack tops out at level 5, so the rule reaches boots level 4 at most.
- `IS_BOOTS_RULE_ENABLED = false` turns the rule off. Before the rule, the player never bought boots.

**After an upgrade**
- The deepest line whose blocking stone is now under 7 hits is dug next.

**Stuck**
- If every line is blocked and nothing is affordable, the player breaks through the cheapest blocking cross-section.
- Under the 7-hit rule this has never happened.

**Running out of lines**
- Once every line has reached the far bedrock, the player cuts stairs at the entrance and digs the same lines 3 rows higher (rows 17–18). That is the only other band whose cross-cut fits inside zone 0.

**The Geiger Counter: buying**
- The counter goes on the store list once a line first reaches zone 5.

**The Geiger Counter: hunting (method B, the T-branch)**
- From zone 4 down, a lit dial at the digging face starts a hunt:
  1. Sweep along the line, then sideways, then up or down, one axis at a time.
  2. On each axis, go one way while the rings hold or rise. Turn back only if the very first step drops them.
  3. Settle in the middle of the strongest stretch.
  4. If the first pass raised the rings, run a second pass.
  5. Only once every ring is lit, clear stone around the settled point, up to 25 blocks, until the rock shows. Otherwise give that rock up.
- Hunt tunnels keep the 7-hit rule.
- The player hunts while the dial stays lit, then returns to the line.
- The dial shows distance only, never direction, and only in 3 ring steps. That is why hunts are slow.

## Fixed inputs not taken from GameData

| Input | Value | Source |
|---|---|---|
| Mine mouth to the refine ring | 48 studs | Studio pathfinder on the Deadman's Canyon map, 2026-10-28 |
| Ring to the stands (pick / backpack / boots / Geiger) | 34 / 73 / 64 / 61 studs | pathfinder (boots measured 2026-10-29) |
| Between stands (pick–backpack / pick–boots / pick–Geiger / backpack–boots / backpack–Geiger / boots–Geiger) | 39 / 47 / 44 / 13 / 27 / 23 studs | pathfinder |
| Stand back to the mouth (pick / backpack / boots / Geiger) | 83 / 105 / 113 / 110 studs | pathfinder |
| Walking inside the mine | along the dug tunnels, 4 studs a block | the sim's own geometry |
| Pocket stairs | 2 blocks of the zone's commonest stone per step | approximation |

## Latest results

Run of 2026-10-29: spacing 3, 200 seeds, all rules on including boots. Figures are means, with p10–p90 in brackets.

| Day | Gold | Iron | Uranium | Total gold | Total uranium | Pick / backpack / boots / Geiger (median) |
|---|---|---|---|---|---|---|
| 1 | 68 (48–96) | 66 | 0 | 68 | 0 | 2 / 2 / 1 / – |
| 3 | 190 | 206 | 1 | 382 | 2 | 3 / 3 / 2 / – |
| 5 | 312 | 411 | 3 | 976 | 7 | 4 / 4 / 3 / – |
| 7 | 267 | 417 | 9 | 1538 | 23 (10–34) | 4 / 4 / 3 / 3 |
| 9 | 341 | 454 | 10 | 2179 | 41 (26–55) | 4 / 5 / 3 / 3 |
| 11 | 415 | 650 | 12 | 2987 | 64 (45–82) | 5 / 5 / 3 / 3 |
| 13 | 496 | 797 | 14 | 3968 | 92 (68–112) | 5 / 5 / 4 / 4 |
| 15 | 559 | 826 | 14 | 5074 (3946–6272) | 119 (98–143) | 5 / 5 / 4 / 4 |

**The win**
- Every seed refines the uranium target (35), on day 9.0 on average (p10 day 8, median day 9, p90 day 10).
- The rescue call is day-only, so the rescue is won on night 9.6 on average (p10 8, median 10, p90 11).

**Upgrades (median buy day)**

| Upgrade | Level 2 | Level 3 | Level 4 | Level 5 | Level 6 |
|---|---|---|---|---|---|
| Pick axe | 1 | 3 | 5 | 11 | 15 (14% of seeds by day 15) |
| Backpack | 1 | 2 | 4 | 9 | — |
| Boots | 3 | 5 | 12 | never (the rule cannot reach it) | — |
| Geiger Counter | 6 | 6 | 13 (95% of seeds) | — | — |

**What the boots rule changed** (same seeds, rule off against rule on):

| | Rule off | Rule on |
|---|---|---|
| Day 35 uranium is refined (mean) | 9.51 | **8.96** |
| Night the rescue is won (mean) | 10.26 | **9.59** |
| Total gold, day 15 | 4484 | **5074** (+13%) |
| Total uranium, day 15 | 106 | **119** |
| Pick 6 by day 15 | 6% | **14%** |

- Boots cost 285 gold in all (35 + 70 + 180), and the saved walking pays that back many times over.
- From day 3 on, walking drops by about 7–30 s a day: for example 78 s against 104 s on day 9, and 84 s against 114 s on day 15.

**Time**
- Walking takes 40–50% of each day before hunting starts.
- From day 7, hunting takes about 245–255 s of each 320 s day.

**Stalls**
- Pick 1 stops at depth about 23, on stone 3.
- Pick 2 stops at about 47, on stone 4.
- Pick 3 stops at about 71, on stone 5.
- From pick 4 on, nothing stops a line.

**Without the Geiger rule** (the plain line digger), for comparison:
- 91% of seeds reach the target, at a median of day 12.
- Total gold by day 15 is 6106, and pick 6 is bought in 95% of seeds.
- So hunting wins about 2 to 3 days on the target, and costs about a quarter of the gold.

## Against BalanceModel (Normal, solo)

**Gold and iron**
- The sim earns more gold early: +30–90% over days 2–8, down to about +10% by day 15 without the Geiger rule.
- It earns 3–10× the model's iron.
- Most of that comes from how fast the digging front goes deep. The model moves on only after mining 15% of a zone's HP (ZONE_ADVANCE_SHARE). A tunnelling player reaches the back of the mine by about day 7, where the rock holds bigger ore.

**Uranium**
- Without hunting, the sim mines about a third of the model's uranium, because the model assumes hunting by sound (URANIUM_SELECTIVITY 10).
- With the Geiger hunt and boots, the sim reaches the target around day 9.0. The model also says day 9, though it gets there with a different spending split (it puts 15% of gold into boots from the start).

**Walking**
- The model reserves 60 s of overhead a day plus short walks.
- The sim walks 100–160 s a day, mostly because its tunnels are deep.

## Caveats

- **Hunting efficiency.** Method B gives up on more rocks than it finds: about 17 against 10 per run. That is caused by the dial's coarse rings and by digging through stone 5 with pick 4. A sharper hunter would win sooner and lose less gold, so the day-9 figure is a cautious estimate.
- **Rough geometry.** Pocket stairs, the second band's stairs, and walks into hunt tunnels are approximations. Tunnel walks ignore shortcuts through pockets.
- **Built-in checks.** The run fails loudly if a check breaks: each day's time adds to 320 s, ore is conserved, bedrock is never mined, and the same seed always gives the same result.
