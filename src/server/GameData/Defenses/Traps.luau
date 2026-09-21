--!strict

-- Traps (GDD "Traps"), M26: consumable placements bought at the Defense
-- Store for Iron, placed on the Defensive Zone grid, sold back for a share
-- of the price, never upgraded. One entry per Enums.TrapKind; a new Trap
-- plugs in by adding its enum key, an entry here, a model of that key's
-- name under GameAssets/Traps, and a "<Key>Stand" in the store. A player
-- carries at most MAX_TRAP_KINDS_CARRIED different kinds, any number of
-- each. REQUIRED_CAMP_LEVEL is the stand's lock line; every kind sits at 1
-- because Traps are never capped (GDD "Camp Level"), and the field is here
-- so a designer can gate one without a code change. The trigger behaviour
-- is M27; placeholder numbers until enemies exist to tune against.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	PRICE_RESOURCE = Enums.RefinedResource.IRON_BAR,
	SELL_SHARE = 0.5,
	MAX_TRAP_KINDS_CARRIED = 3,
	-- the store stand's prompt, like the Mining Store's: held for a second
	-- so a walk-past never buys
	BUY_PROMPT_ACTION_TEXT = "Buy",
	BUY_PROMPT_HOLD_SEC = 1,
	BUY_PROMPT_MAX_DISTANCE_STUDS = 8,
	-- the placed Trap's prompt, only the owner sees it
	SELL_PROMPT_ACTION_FORMAT = "Sell: %d Iron Bars",
	SELL_PROMPT_HOLD_SEC = 1,
	SELL_PROMPT_MAX_DISTANCE_STUDS = 10,
	BY_KIND = {
		[Enums.TrapKind.TIGER_TEETH] = { PRICE_IRON = 12, MAX_HP = 300, FOOTPRINT_CELLS = { 2, 2 }, REQUIRED_CAMP_LEVEL = 1 },
		[Enums.TrapKind.SPIKE_TRAP] = { PRICE_IRON = 15, MAX_HP = 120, FOOTPRINT_CELLS = { 4, 4 }, REQUIRED_CAMP_LEVEL = 1 },
		[Enums.TrapKind.GOO_PIT] = { PRICE_IRON = 10, MAX_HP = 100, FOOTPRINT_CELLS = { 5, 2 }, REQUIRED_CAMP_LEVEL = 1 },
		[Enums.TrapKind.LAND_MINE] = { PRICE_IRON = 20, MAX_HP = 60, FOOTPRINT_CELLS = { 1, 1 }, REQUIRED_CAMP_LEVEL = 1 },
		[Enums.TrapKind.BEAR_TRAP] = { PRICE_IRON = 8, MAX_HP = 80, FOOTPRINT_CELLS = { 1, 1 }, REQUIRED_CAMP_LEVEL = 1 },
		[Enums.TrapKind.DECOY] = { PRICE_IRON = 18, MAX_HP = 400, FOOTPRINT_CELLS = { 2, 2 }, REQUIRED_CAMP_LEVEL = 1 },
	},
}
