--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- The Mining Supplies Store (GDD "Mining Supplies Store"): one stand per
-- item, paid in Gold Bars. Upgrade tracks list the price of reaching each
-- level (entry 1 is unused: everyone starts at level 1) and their length is
-- the top level, so adding a level is adding a price. A track marked
-- startsUnowned is an item nobody has until they buy it: level 1 is not
-- having it and entry 2 is the price of the item itself. Placeholder prices sized against Gold rock
-- yields (3 / 10 / 30 / 87 ore per rock by tier), to tune in play.
return {
	PRICE_RESOURCE = Enums.RefinedResource.GOLD_BAR,
	UPGRADES = {
		-- tripling a level along with each upgrade's effect (2026-09-28, the
		-- simulator curve): the price is the brake now that no camp level
		-- gates a rung, and Gold per rock climbs deeper so the last rung is
		-- as reachable on day 9 as the first was on day 2
		-- level 2 is 20 since 2026-10-02 (was 30), so the first pick is a day-1 buy
		[Enums.StoreItem.PICK_AXE] = { priceByLevel = { 0, 20, 90, 270, 800 } },
		[Enums.StoreItem.BOOTS] = { priceByLevel = { 0, 20, 60, 180, 540 } },
		[Enums.StoreItem.BACKPACK] = { priceByLevel = { 0, 20, 60, 180, 540 } },
		[Enums.StoreItem.JET_PACK] = { priceByLevel = { 0, 40, 120, 360, 1080 } },
		-- bought once, never upgraded: a track with a single rung, priced
		-- like the level 2 pick axe (2026-09-30)
		[Enums.StoreItem.COMPASS] = { priceByLevel = { 0, 30 }, startsUnowned = true },
		-- bought like the compass, then upgraded three times for more range
		-- (GameData/Mining/GeigerCounter): it starts at the level 3 pick axe
		-- price and triples on the pick axe's curve (2026-09-30)
		[Enums.StoreItem.GEIGER_COUNTER] = { priceByLevel = { 0, 90, 270, 800, 2400 }, startsUnowned = true },
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
