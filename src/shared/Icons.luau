--!strict

-- Every 2D icon the game shows, by asset id, in one place: an artist swaps an
-- id here and every HUD row, menu, and flying icon follows. Data only, shared
-- so the client managers and the Studio build scripts under scripts/studio/
-- read the same ids. Keys are enum values where one exists, so code looks an
-- icon up by resource and never spells an icon name. The 3D tool icons
-- captured by the icon pipeline are not here; they live on each template's
-- IconImageId attribute (docs/icon-capture.md).
local Enums = require(script.Parent.Enums)

local Icons = {}

-- an entry that is still this shows the colour placeholder instead
Icons.PLACEHOLDER = "rbxassetid://0"

Icons.RAW_RESOURCE = {
	[Enums.RawResource.IRON_ORE] = "rbxassetid://139984344282023",
	[Enums.RawResource.GOLD_ORE] = "rbxassetid://83250762899012",
	[Enums.RawResource.URANIUM_ORE] = "rbxassetid://81326903056199",
}

Icons.REFINED_RESOURCE = {
	[Enums.RefinedResource.IRON_BAR] = "rbxassetid://94215413697416",
	[Enums.RefinedResource.GOLD_BAR] = "rbxassetid://137446117638753",
	[Enums.RefinedResource.URANIUM] = "rbxassetid://125767847132761",
}

-- standalone glyphs with no enum behind them
-- the reticle shown in Post Weapon Mode, by Enums.PostWeaponKind; a kind
-- without one borrows the mining dot (ClientPostManager)
Icons.POST_WEAPON_RETICLE = {
	[Enums.PostWeaponKind.MACHINE_GUN] = "rbxassetid://134742178329103",
	-- the Minigun shares the Machine Gun's reticle (2026-10-19)
	[Enums.PostWeaponKind.MINI_GUN] = "rbxassetid://134742178329103",
	[Enums.PostWeaponKind.ROCKET_LAUNCHER] = "rbxassetid://105502906242582",
}

-- the tool bar slot picture per Enums.ToolKind (one for every pick axe
-- level); a kind without one shows its name instead (ClientToolBarManager)
Icons.TOOL = {
	[Enums.ToolKind.PICK_AXE] = "rbxassetid://80581106612931",
	[Enums.ToolKind.HAMMER] = "rbxassetid://96069694494045",
}

-- the WEAPON slot's picture, by the Enums.WeaponKind carried
Icons.WEAPON = {
	[Enums.WeaponKind.RIFLE] = "rbxassetid://71757532147550",
}

-- the GADGET slot's picture, by the Enums.GadgetKind carried (M66)
Icons.GADGET = {
	[Enums.GadgetKind.AUTO_TURRET] = "rbxassetid://84791820127176",
}

-- the character sheet's gear cards show the item, never its type (designer,
-- 2026-10-12): the ids the icon pipeline (docs/icon-capture.md) baked onto
-- GameAssets/Towers/<KIND>, GameAssets/PostWeapons/<KIND>, and
-- GameAssets/Tools/WEAPON_<KIND> in the gameplay place, copied here because
-- the lobby has no GameAssets to read them from. Every gun faces right
-- (designer, 2026-10-12). Recapture an asset and update its id in both
-- places. WEAPON_KIND is the rendered gun; WEAPON above stays the tool
-- bar's own art
Icons.TOWER_KIND = {
	[Enums.TowerKind.SENTRY_GUN] = "rbxassetid://123552008549366",
	[Enums.TowerKind.FLAMETHROWER] = "rbxassetid://138549055728375",
	[Enums.TowerKind.AA_TURRET] = "rbxassetid://113913681124008",
	[Enums.TowerKind.FROST_TOWER] = "rbxassetid://122186464277976",
	[Enums.TowerKind.TESLA_COIL] = "rbxassetid://118033678404166",
	[Enums.TowerKind.SNIPER_TOWER] = "rbxassetid://117170402065913",
}

Icons.POST_WEAPON = {
	[Enums.PostWeaponKind.MACHINE_GUN] = "rbxassetid://88160356446112",
	[Enums.PostWeaponKind.ROCKET_LAUNCHER] = "rbxassetid://72633570515796",
}

Icons.WEAPON_KIND = {
	[Enums.WeaponKind.RIFLE] = "rbxassetid://126641049266938",
}

-- the type box of each row on the sheet's COSMETICS tab (designer's
-- mock-up, 2026-10-13): the slot's own art where it exists, the Hard Hat's
-- catalogue thumbnail for the Helmet, the placeholder for the rest
Icons.COSMETIC_SLOT = {
	[Enums.CosmeticSlot.PICK_AXE] = "rbxassetid://80581106612931",
	[Enums.CosmeticSlot.HAMMER] = "rbxassetid://96069694494045",
	[Enums.CosmeticSlot.WEAPON] = "rbxassetid://71757532147550",
	[Enums.CosmeticSlot.POST_WEAPON] = "rbxassetid://88160356446112",
	[Enums.CosmeticSlot.TOWER] = "rbxassetid://72202536661953",
	[Enums.CosmeticSlot.JET_PACK] = "rbxassetid://110721276111650",
	[Enums.CosmeticSlot.BACKPACK] = "rbxassetid://135327278539325",
	-- the designer's hat category icon (2026-10-13)
	[Enums.CosmeticSlot.HELMET] = "rbxassetid://94277531430593",
}

-- the one skin each non-hat slot offers so far, the game's existing
-- asset: renders of GameAssets/Tools/PICK_AXE_1 and
-- GameAssets/Wearables/JET_PACK captured on 2026-10-13 (placeholders
-- until the skin art lands; the type box keeps its white glyph above)
Icons.COSMETIC_DEFAULT_SKIN = {
	[Enums.CosmeticSlot.PICK_AXE] = "rbxassetid://140057314922013",
	[Enums.CosmeticSlot.JET_PACK] = "rbxassetid://74237324800322",
}

Icons.UI = {
	-- the first-person cursor in a run (ClientCursorManager, 2026-10-13): a
	-- 16 px white dot with a dark edge, so an aim point always shows
	CURSOR_DOT = "rbxassetid://70725934412881",
	-- the NONE item at the end of the sheet's hat row: the player's own
	-- avatar hat, whatever it is (designer's art, 2026-10-13)
	NO_HAT = "rbxassetid://109536655284287",
	-- the HUD backpack button and the jet pack fuel bar
	BACKPACK = "rbxassetid://135327278539325",
	JET_PACK = "rbxassetid://110721276111650",
	-- the Build Mode Tower counter and the kind badge on a build bar slot
	TOWER = "rbxassetid://72202536661953",
	TRAP = "rbxassetid://71088256703142",
	-- the Rotate button beside Place in Build Mode (designer's art, 2026-10-02)
	ROTATE = "rbxassetid://108992733643165",
	-- the day clock's circle (M28): placeholders until the art lands
	CLOCK_DAY = "rbxassetid://98516537326926",
	CLOCK_DUSK = "rbxassetid://91444734897924",
	CLOCK_NIGHT = "rbxassetid://72038436524050",
	-- the compass's Refinery marker (designer's art, 2026-09-30)
	COMPASS_HOME = "rbxassetid://98277990053980",
	-- Diamonds, the lobby currency (M33): the lobby HUD wallet and the
	-- Results Menu row; the art the in-run Diamond had before it was retired
	DIAMONDS = "rbxassetid://101719152234191",
}

function Icons.isPlaceholder(id: string?): boolean
	return id == nil or id == Icons.PLACEHOLDER
end

return Icons
