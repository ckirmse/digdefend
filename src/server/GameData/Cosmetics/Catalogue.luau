--!strict

-- The cosmetics catalogue (GDD "Characters" cosmetics, M61 first pass,
-- 2026-11-04): every skin made from the game's own templates, keyed by
-- the id a save stores, so an id is never renamed once a save can hold
-- it. Each names its Enums.CosmeticSlot, the name shown, and the template
-- under GameAssets/Cosmetics/<SLOT>/<TEMPLATE> (built by
-- scripts/studio/build_cosmetic_templates.luau). Every entry here joins
-- the class gacha's pool (GachaManager) and the Key Store (KeyStoreManager,
-- M61), which sells it for PRICE_KEYS Keys; hats live in Characters/Hats.
-- The two entries are placeholders cut from the stock pick axe and jet
-- pack so the crate reveal can be tested; real skins replace them. The
-- prices are placeholders too (2026-11-05). Every entry carries a RARITY
-- (Enums.Rarity; designer, 2026-11-09), shown on the crate's odds list and
-- its reveal in the rarity's colour; the draw odds do not read it.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	BY_ID = {
		TEST_PICK_AXE = {
			SLOT = Enums.CosmeticSlot.PICK_AXE,
			NAME = "Test Pick Axe",
			TEMPLATE = "TEST_PICK_AXE",
			PRICE_KEYS = 10,
			RARITY = Enums.Rarity.RARE,
		},
		TEST_JET_PACK = {
			SLOT = Enums.CosmeticSlot.JET_PACK,
			NAME = "Test Jet Pack",
			TEMPLATE = "TEST_JET_PACK",
			PRICE_KEYS = 10,
			RARITY = Enums.Rarity.EPIC,
		},
	},
}
