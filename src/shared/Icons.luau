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
	-- the AA Launcher shares the Rocket Launcher's reticle (2026-10-20),
	-- coloured by what is under it and with the lock bar beside it
	[Enums.PostWeaponKind.AA_LAUNCHER] = "rbxassetid://105502906242582",
	-- the Salvage Gun shares the Machine Gun's reticle (designer, 2026-10-22)
	[Enums.PostWeaponKind.DRILL_GUN] = "rbxassetid://134742178329103",
}

-- the tool bar slot picture per Enums.ToolKind (one for every pick axe
-- level); a kind without one shows its name instead (ClientToolBarManager)
Icons.TOOL = {
	[Enums.ToolKind.PICK_AXE] = "rbxassetid://80581106612931",
	[Enums.ToolKind.HAMMER] = "rbxassetid://96069694494045",
	[Enums.ToolKind.DYNAMITE] = "rbxassetid://75555443248313",
}

-- the WEAPON slot's picture, by the Enums.WeaponKind carried
Icons.WEAPON = {
	[Enums.WeaponKind.RIFLE] = "rbxassetid://71757532147550",
	-- the sidearm of the Recruit, Sniper, Prospector, Hauler, and Medic (2026-10-19)
	[Enums.WeaponKind.PISTOL] = "rbxassetid://126590023979777",
	[Enums.WeaponKind.ASSAULT_RIFLE] = "rbxassetid://104253125783801",
	[Enums.WeaponKind.FLAMETHROWER] = "rbxassetid://77039042494300",
}

-- the GADGET slot's picture, by the Enums.GadgetKind carried (M66)
Icons.GADGET = {
	[Enums.GadgetKind.AUTO_TURRET] = "rbxassetid://84791820127176",
	[Enums.GadgetKind.STIM_SHOT] = "rbxassetid://136139239798345",
	[Enums.GadgetKind.REMOTE_CHARGE] = "rbxassetid://97927358319077",
	-- the flare gun (designer, 2026-10-21)
	[Enums.GadgetKind.FLARE] = "rbxassetid://139213612204269",
	-- the ore scanner (designer, 2026-10-23)
	[Enums.GadgetKind.ORE_SCANNER] = "rbxassetid://76127032736382",
}
-- the Remote Charge's slot once its mine is planted (2026-10-20), back
-- to the mine's picture after the detonation
Icons.GADGET_DETONATOR = "rbxassetid://110586066527047"

-- the Binoculars' tag callout over a tagged monster (2026-10-19): the
-- Sniper's reticle stands in until the Binoculars' own art lands
Icons.TAG_RETICLE = "rbxassetid://75294207181536"
-- the Missile Launcher's locked-target marker and lock counter (2026-10-20): the Machine Gun's reticle
Icons.LOCK_MARKER = "rbxassetid://134742178329103"

-- the scope glass drawn over the screen while a scope kind's scope is
-- raised (ScopeHud, 2026-10-19): the designer's reticle, black outside it
Icons.WEAPON_SCOPE = {
	[Enums.WeaponKind.SNIPER] = "rbxassetid://122058676594142",
}

-- the same glass while a scoped post is manned (the Railgun, the Sniper's
-- post, looks through the rifle's scope, decided 2026-10-19)
Icons.POST_WEAPON_SCOPE = {
	[Enums.PostWeaponKind.RAIL_GUN] = "rbxassetid://122058676594142",
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

-- the designer's class pictures (2026-11-04): the gacha's 3D class card;
-- a class without one keeps the card's authored placeholder
Icons.CLASS_KIND = {
	-- the first Prospector picture, handed to the Recruit on 2026-11-05
	[Enums.ClassKind.RECRUIT] = "rbxassetid://103204546509022",
	[Enums.ClassKind.SNIPER] = "rbxassetid://105683326705463",
	[Enums.ClassKind.RANGER] = "rbxassetid://84456092602659",
	[Enums.ClassKind.PYRO] = "rbxassetid://129584863380176",
	[Enums.ClassKind.PROSPECTOR] = "rbxassetid://137127089618818",
	[Enums.ClassKind.GUNNER] = "rbxassetid://137376924445466",
	[Enums.ClassKind.DEMOLITIONIST] = "rbxassetid://114125041037006",
	[Enums.ClassKind.AIR_DEFENSE] = "rbxassetid://110014529125871",
}

-- the type box of each cosmetic slot (designer's mock-up, 2026-10-13):
-- the slot's own art where it exists (the hat category icon went with
-- the hats, 2026-11-09)
Icons.COSMETIC_SLOT = {
	[Enums.CosmeticSlot.PICK_AXE] = "rbxassetid://80581106612931",
	[Enums.CosmeticSlot.HAMMER] = "rbxassetid://96069694494045",
	[Enums.CosmeticSlot.WEAPON] = "rbxassetid://71757532147550",
	[Enums.CosmeticSlot.POST_WEAPON] = "rbxassetid://88160356446112",
	[Enums.CosmeticSlot.TOWER] = "rbxassetid://72202536661953",
	[Enums.CosmeticSlot.JET_PACK] = "rbxassetid://110721276111650",
	[Enums.CosmeticSlot.BACKPACK] = "rbxassetid://135327278539325",
}

-- the one skin each slot offers so far, the game's existing
-- asset: renders of GameAssets/Tools/PICK_AXE_1 and
-- GameAssets/Wearables/JET_PACK captured on 2026-10-13 (placeholders
-- until the skin art lands; the type box keeps its white glyph above)
Icons.COSMETIC_DEFAULT_SKIN = {
	[Enums.CosmeticSlot.PICK_AXE] = "rbxassetid://140057314922013",
	[Enums.CosmeticSlot.JET_PACK] = "rbxassetid://74237324800322",
}

-- the Key Store's picture of each skin by catalogue id (M61, 2026-11-05):
-- the placeholder skins reuse the renders above until their art lands; a
-- skin with no entry shows the placeholder
Icons.COSMETIC_SKIN = {
	TEST_PICK_AXE = Icons.COSMETIC_DEFAULT_SKIN[Enums.CosmeticSlot.PICK_AXE],
	TEST_JET_PACK = Icons.COSMETIC_DEFAULT_SKIN[Enums.CosmeticSlot.JET_PACK],
}

-- the designer's controller button pictures (M72, 2026-11-11): the confirm
-- face buttons of each controller family
Icons.GAMEPAD = {
	XBOX_A = "rbxassetid://103422802557483",
	XBOX_B = "rbxassetid://122294829709383",
	XBOX_X = "rbxassetid://79041783517892",
	XBOX_Y = "rbxassetid://114161231687213",
	PLAYSTATION_SQUARE = "rbxassetid://88020642409607",
	PLAYSTATION_TRIANGLE = "rbxassetid://98631096120942",
	PLAYSTATION_CROSS = "rbxassetid://82419408093803",
	PLAYSTATION_CIRCLE = "rbxassetid://97949685878894",
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
	-- the left mouse button on the mouse scheme's Place key card (designer, 2026-10-29)
	MOUSE_LEFT_BUTTON = "rbxassetid://133479972513291",
	-- the day clock's circle (M28): placeholders until the art lands
	-- the day clock badge frame behind the phase pictures (designer, 2026-10-29)
	CLOCK_FRAME = "rbxassetid://90693046172973",
	-- the day clock track and fill pill (designer, 2026-10-29)
	CLOCK_BAR = "rbxassetid://129096785125881",
	-- the Refinery HP bar's pill, bar and fill alike (designer, 2026-10-29)
	HP_BAR = "rbxassetid://123932033889575",
	-- the Camp Map facing cone: a white sector fanning up from the picture's
	-- centre, fading outward (generated with ImageMagick, 2026-10-29)
	CAMP_MAP_FACING_CONE = "rbxassetid://77909401635814",
	-- the designer's rough-edged panel picture behind HUD boxes (2026-10-29)
	PANEL_BACKING = "rbxassetid://99484338119365",
	-- the tutorial's HUD arrow (M76, 2026-11-09): a white chevron with a dark edge, pointing down; ImageMagick
	TUTORIAL_ARROW = "rbxassetid://75040607043356",
	CLOCK_DAY = "rbxassetid://98516537326926",
	CLOCK_DUSK = "rbxassetid://91444734897924",
	CLOCK_NIGHT = "rbxassetid://72038436524050",
	-- the compass's Refinery marker (designer's art, 2026-09-30)
	COMPASS_HOME = "rbxassetid://98277990053980",
	-- the Assault Rifle's grenade launcher on the weapon HUD's cooldown bar (2026-10-19)
	GRENADE_LAUNCHER = "rbxassetid://74594220753133",
	-- Diamonds, the lobby currency (M33): the lobby HUD wallet and the
	-- Results Menu row; the art the in-run Diamond had before it was retired
	DIAMONDS = "rbxassetid://101719152234191",
	-- Keys, the gacha's third currency (M70): the designer's key (2026-11-05)
	KEYS = "rbxassetid://122757851945939",
	-- the padlock over a locked class or perk row in the Class Menu
	-- (the Missile Launcher's lock marker stood in before, 2026-11-05)
	LOCK = "rbxassetid://87535225906474",
	-- the Supply Crate: a capture of the designer's SupplyCrateScreenshot
	-- model through the icon pipeline (docs/icon-capture.md), 2026-11-09
	SUPPLY_CRATE = "rbxassetid://84556835168975",
}

-- the Diamond Store's pack pictures, by the pack's place in the list
-- (GameData/Store/DiamondPacks, smallest first; designer's art,
-- 2026-11-12). A pack with no entry keeps the picture authored on the
-- gui's PackTemplate
Icons.DIAMOND_PACK = {
	[1] = "rbxassetid://116986413085371",
	[2] = "rbxassetid://80418233826190",
	[3] = "rbxassetid://127742036371131",
	[4] = "rbxassetid://122502130840031",
}

function Icons.isPlaceholder(id: string?): boolean
	return id == nil or id == Icons.PLACEHOLDER
end

return Icons
