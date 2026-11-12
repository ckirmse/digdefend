--!strict

-- The group reward (M78, designer 2026-11-12): Diamonds paid once per
-- account to a member of the game's Roblox group, claimed from a menu
-- the lobby raises on arrival. Diamonds rather than a Supply Crate so a
-- player restricted from paid random items gets the same reward.
return {
	-- the Roblox group a player must be in. The QA group's until the game
	-- moves to the live community (M80)
	GROUP_ID = 571203718,
	-- what the claim pays; the menus and the banners read it from the
	-- GroupRewardDiamonds GameMetadata, so this is the one place to change
	REWARD_DIAMONDS = 50,
	-- Roblox is asked about a player's groups no more often than this,
	-- however often their client opens a menu
	RECHECK_SEC = 10,
}
