--!strict

-- The Camp Level (GDD "Camp Level"): Diamonds needed to go from each level
-- to the next, so entry 1 is the cost of reaching level 2 and the list
-- length fixes the top level (one more than its length); and what each
-- level unlocks (M22, table settled 2026-09-16). Every gate is a table the
-- stores read, never a formula, so lifting or loosening a cap is a one-line
-- change. Placeholder pacing numbers sized against the Deadmans Canyon
-- crystal counts, to tune in play.
return {
	DIAMONDS_REQUIRED_BY_LEVEL = { 20, 80, 250 },
	-- Mining Supplies Store tracks (Pick Axe, Boots, Backpack, Jet Pack):
	-- entry N is the Camp Level needed to buy level N. Entry 1 is unused
	-- (everyone starts at level 1); level N+1 needs Camp Level N so the
	-- first upgrade is never locked
	MINING_UPGRADE_REQUIRED_CAMP_LEVEL_BY_LEVEL = { 1, 1, 2, 3, 4 },
	-- Post weapon upgrades (M25): every attribute can be upgraded four times
	-- and upgrade N needs Camp Level N, so the first is never locked and the
	-- fourth is a top-level goal; the exclusive branch fork and capstone (a
	-- later milestone) need the top level too
	POST_UPGRADE_REQUIRED_CAMP_LEVEL_BY_LEVEL = { 1, 2, 3, 4 },
	POST_CAPSTONE_REQUIRED_CAMP_LEVEL = 4,
	-- Wall and gate tiers (M23) follow the posts: tier N needs Camp Level N.
	-- Repair is never gated
	STRUCTURE_TIER_REQUIRED_CAMP_LEVEL_BY_TIER = { 1, 2, 3 },
}
