--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- The Mining Supplies Store (GDD "Mining Supplies Store"): one stand per
-- item, paid in Gold Bars. Upgrade tracks list the price of reaching each
-- level (entry 1 is unused: everyone starts at level 1) and their length is
-- the top level, so adding a level is adding a price. Level N+1 also needs
-- Camp Level N (StoreRules). Placeholder prices sized against Gold rock
-- yields (3 / 10 / 30 / 87 ore per rock by tier), to tune in play.
return {
	PRICE_RESOURCE = Enums.RefinedResource.GOLD_BAR,
	UPGRADES = {
		[Enums.StoreItem.PICK_AXE] = { priceByLevel = { 0, 15, 40, 100, 250 } },
		[Enums.StoreItem.BOOTS] = { priceByLevel = { 0, 10, 25, 60, 150 } },
		[Enums.StoreItem.BACKPACK] = { priceByLevel = { 0, 10, 30, 80, 200 } },
		[Enums.StoreItem.JET_PACK] = { priceByLevel = { 0, 20, 50, 120, 300 } },
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
