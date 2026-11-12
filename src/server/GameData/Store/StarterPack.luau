--!strict

-- The Starter Pack (M79, designer 2026-11-12): a Roblox game pass, so it
-- can be bought once per account, that pays a class card, Diamonds, and a
-- pick axe skin. Every item is named here, never drawn at random, so the
-- pack is the same for a player restricted from paid random items. The
-- contents are placeholders and expected to change.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	-- the game pass on Roblox (a temporary pass; M80 moves it with the game)
	GAME_PASS_ID = 2082974479,
	-- what the menu shows struck through beside the real price, as the
	-- pack's worth; the real price is read from Roblox, never written here
	VALUE_ROBUX = 499,
	-- the class card, by priority (designer, 2026-11-12): the first class
	-- here the player does not own; with every one owned, the first that
	-- is not maxed, which gets its next tier; with every one maxed, the
	-- Keys a crate pays for a complete class's card
	-- (GameData/Gacha/Gacha.KEYS_PER_COMPLETE_CLASS). Every class listed
	-- must be in the Supply Crate's pool
	CLASS_PRIORITY = {
		Enums.ClassKind.GUNNER,
		Enums.ClassKind.SNIPER,
		Enums.ClassKind.RANGER,
		Enums.ClassKind.PYRO,
		Enums.ClassKind.AIR_DEFENSE,
		Enums.ClassKind.PROSPECTOR,
		Enums.ClassKind.DEMOLITIONIST,
		Enums.ClassKind.RECRUIT,
	},
	DIAMONDS = 300,
	-- a pick axe skin from GameData/Cosmetics/Catalogue; a player who
	-- already owns it is paid Keys as a crate's duplicate would be
	COSMETIC_ID = "TEST_PICK_AXE",
}
