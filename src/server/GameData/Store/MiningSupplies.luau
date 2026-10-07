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
		-- the first rungs are cheap on purpose (designer, 2026-10-07): day 1
		-- should feel good, gold easy to find in the gold-only first zone and
		-- the first upgrade an easy buy; the second rungs are dearer to pay for it
		-- level 2 is 30 again (2026-10-07, after 15 and 20 the same day: two backpack
		-- trips, not one; 20 from 2026-10-02, 30 before that), so a new
		-- player's first run buys a pick before anything else
		-- level 6 (2026-10-06): the ladder's next step, the Gold sink a run
		-- past day 10 was missing
		[Enums.StoreItem.PICK_AXE] = { priceByLevel = { 0, 30, 100, 270, 800, 2400 } },
		-- boots and backpack first rungs 40 (2026-10-07; 20, then 25 earlier that
		-- day): day 1 gold is capped by the 15-ore pack times about 5 trips, near
		-- 75, so pick 30 + backpack 40 is a full excellent day and the three first
		-- rungs can never all land on day 1; the backpack's second rung 80 (75
		-- then 60 before; pick 100 and boots 70 the same day)
		[Enums.StoreItem.BOOTS] = { priceByLevel = { 0, 40, 70, 180, 540 } },
		[Enums.StoreItem.BACKPACK] = { priceByLevel = { 0, 40, 80, 225, 675 } },
		[Enums.StoreItem.JET_PACK] = { priceByLevel = { 0, 40, 120, 360, 1080 } },
		-- bought once, never upgraded: a track with a single rung, priced
		-- like the level 2 pick axe (2026-09-30)
		[Enums.StoreItem.COMPASS] = { priceByLevel = { 0, 30 }, startsUnowned = true },
		-- bought like the compass, then upgraded twice for more range
		-- (GameData/Mining/GeigerCounter): it starts at the level 3 pick axe
		-- price and triples on the pick axe's curve (2026-09-30)
		[Enums.StoreItem.GEIGER_COUNTER] = { priceByLevel = { 0, 90, 270, 800 }, startsUnowned = true },
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
