--!strict

-- Traps (GDD "Traps", "Trap Types"), M26 and M27: consumable placements
-- bought for Iron as they are placed from the Defense Table, on the
-- Defensive Zone grid, sold back for a share of the price, never upgraded.
-- One entry per Enums.TrapKind; a new Trap plugs in by adding its enum
-- key, an entry here, and a model of that key's name under
-- GameAssets/Traps.
-- IS_REPAIRABLE is whether the Hammer can mend the Trap like a Tower, a
-- chunk of HP for a few Iron per swing (2026-09-30): only the Wall for now,
-- since the rest are spent by doing their job.
-- REQUIRED_CAMP_LEVEL locks the Trap on the table's bar; every kind sits at 1
-- because Traps are never capped (GDD "Camp Level"), and the field is here
-- so a designer can gate one without a code change.
-- BEHAVIOR (Enums.TrapBehavior) is what the Trap does when an enemy's
-- footprint overlaps its cells (air units never touch a Trap):
--   BARRIER blocks walkers, who attack it; DRAWS_ATTACKS marks the Decoy
--     for enemy targeting (M29) and RANGE_STUDS is how far it draws from
--   SPIKES pop for UP_SEC dealing DAMAGE to everything on top, then
--     recharge for RECHARGE_SEC
--   GOO slows every crosser by SLOW_SHARE for SLOW_SEC after they leave
--   MINE deals DAMAGE to everything within RANGE_STUDS once, then is gone
--   SNARE deals DAMAGE to the one crosser and slows it by SLOW_SHARE for
--     SLOW_SEC once, then is gone
-- Every number is a placeholder until enemies exist to tune against (M30).
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	PRICE_RESOURCE = Enums.RefinedResource.IRON_BAR,
	SELL_SHARE = 0.5,
	BY_KIND = {
		[Enums.TrapKind.WALL] = {
			PRICE_IRON = 12,
			MAX_HP = 300,
			-- a run of wall, four cells along the zone's columns and two deep
			-- (2026-10-02; four by one from 2026-09-25, a 2 x 2 block before): the
			-- Defensive Zone's columns run across the monsters' approach, so a
			-- placed wall lies across it, and the player turns it with the Rotate
			-- button. Every footprint is whole PlacementRules.FOOTPRINT_UNIT_CELLS
			-- so the grid tiles. The template (GameAssets/Traps/WALL) is sized
			-- to the footprint's length with no gap, so a row of walls joins up
			FOOTPRINT_CELLS = { 4, 2 },
			REQUIRED_CAMP_LEVEL = 1,
			IS_REPAIRABLE = true,
			BEHAVIOR = Enums.TrapBehavior.BARRIER,
			DRAWS_ATTACKS = false,
		},
		[Enums.TrapKind.SPIKE_TRAP] = {
			PRICE_IRON = 15,
			MAX_HP = 120,
			FOOTPRINT_CELLS = { 4, 4 },
			REQUIRED_CAMP_LEVEL = 1,
			IS_REPAIRABLE = false,
			BEHAVIOR = Enums.TrapBehavior.SPIKES,
			DAMAGE = 25,
			UP_SEC = 1,
			RECHARGE_SEC = 3,
		},
		[Enums.TrapKind.GOO_PIT] = {
			PRICE_IRON = 10,
			MAX_HP = 100,
			-- 4 x 2 since 2026-10-02 (5 x 2 before) so it is whole units
			FOOTPRINT_CELLS = { 4, 2 },
			REQUIRED_CAMP_LEVEL = 1,
			IS_REPAIRABLE = false,
			BEHAVIOR = Enums.TrapBehavior.GOO,
			SLOW_SHARE = 0.5,
			SLOW_SEC = 1.5,
		},
		[Enums.TrapKind.LAND_MINE] = {
			PRICE_IRON = 20,
			MAX_HP = 60,
			-- 2 x 2 since 2026-10-02 (1 x 1 before): the smallest footprint
			FOOTPRINT_CELLS = { 2, 2 },
			REQUIRED_CAMP_LEVEL = 1,
			IS_REPAIRABLE = false,
			BEHAVIOR = Enums.TrapBehavior.MINE,
			DAMAGE = 120,
			RANGE_STUDS = 10,
		},
		[Enums.TrapKind.BEAR_TRAP] = {
			PRICE_IRON = 8,
			MAX_HP = 80,
			FOOTPRINT_CELLS = { 2, 2 },
			REQUIRED_CAMP_LEVEL = 1,
			IS_REPAIRABLE = false,
			BEHAVIOR = Enums.TrapBehavior.SNARE,
			DAMAGE = 40,
			SLOW_SHARE = 1,
			SLOW_SEC = 3,
		},
		[Enums.TrapKind.DECOY] = {
			PRICE_IRON = 18,
			MAX_HP = 400,
			FOOTPRINT_CELLS = { 2, 2 },
			REQUIRED_CAMP_LEVEL = 1,
			IS_REPAIRABLE = false,
			BEHAVIOR = Enums.TrapBehavior.BARRIER,
			DRAWS_ATTACKS = true,
			RANGE_STUDS = 30,
		},
	},
}
