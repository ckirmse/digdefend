--!strict

-- The cosmetics catalogue (GDD "Characters" cosmetics, M61 first pass,
-- 2026-11-04): every skin made from the game's own templates, keyed by
-- the id a save stores, so an id is never renamed once a save can hold
-- it. Each names its Enums.CosmeticSlot, the name shown, and the template
-- under GameAssets/Cosmetics/<SLOT>/<TEMPLATE> (built by
-- scripts/studio/build_cosmetic_templates.luau). Every entry here joins
-- the class gacha's pool (GachaManager); hats live in Characters/Hats.
-- The two entries are placeholders cut from the stock pick axe and jet
-- pack so the crate reveal can be tested; real skins replace them.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	BY_ID = {
		TEST_PICK_AXE = {
			SLOT = Enums.CosmeticSlot.PICK_AXE,
			NAME = "Test Pick Axe",
			TEMPLATE = "TEST_PICK_AXE",
		},
		TEST_JET_PACK = {
			SLOT = Enums.CosmeticSlot.JET_PACK,
			NAME = "Test Jet Pack",
			TEMPLATE = "TEST_JET_PACK",
		},
	},
}
