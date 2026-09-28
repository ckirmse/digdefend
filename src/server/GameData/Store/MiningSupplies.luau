--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- The Mining Supplies Store (GDD "Mining Supplies Store"): one stand per
-- item, paid in Gold Bars. Upgrade tracks list the price of reaching each
-- level (entry 1 is unused: everyone starts at level 1) and their length is
-- the top level, so adding a level is adding a price. The Camp Level each
-- buy needs comes from GameData/Camp/Level. Placeholder prices sized against Gold rock
-- yields (3 / 10 / 30 / 87 ore per rock by tier), to tune in play.
return {
	PRICE_RESOURCE = Enums.RefinedResource.GOLD_BAR,
	UPGRADES = {
		-- tripling a level along with each upgrade's effect (2026-09-28, the
		-- simulator curve): the price is the brake now that no camp level
		-- gates a rung, and Gold per rock climbs deeper so the last rung is
		-- as reachable on day 9 as the first was on day 2
		[Enums.StoreItem.PICK_AXE] = { priceByLevel = { 0, 30, 90, 270, 800 } },
		[Enums.StoreItem.BOOTS] = { priceByLevel = { 0, 20, 60, 180, 540 } },
		[Enums.StoreItem.BACKPACK] = { priceByLevel = { 0, 20, 60, 180, 540 } },
		[Enums.StoreItem.JET_PACK] = { priceByLevel = { 0, 40, 120, 360, 1080 } },
	},
	-- one buy grants `amount` of the tool; never capped by Camp Level
	CONSUMABLES = {
		[Enums.StoreItem.TORCH] = { tool = Enums.ToolKind.TORCH, price = 5, amount = 4 },
		[Enums.StoreItem.DYNAMITE] = { tool = Enums.ToolKind.DYNAMITE, price = 12, amount = 1 },
	},
	-- the stand's proximity prompt: held for a second so a walk-past never buys
	PROMPT_ACTION_TEXT = "Buy",
	PROMPT_HOLD_SEC = 1,
	PROMPT_MAX_DISTANCE_STUDS = 8,
	-- the display model on each stand turns this fast (client only)
	DISPLAY_TURN_DEGREES_PER_SEC = 45,
}
