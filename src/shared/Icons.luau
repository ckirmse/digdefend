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
	[Enums.RawResource.CRYSTAL] = "rbxassetid://137679245645054",
	[Enums.RawResource.URANIUM_ORE] = "rbxassetid://81326903056199",
}

Icons.REFINED_RESOURCE = {
	[Enums.RefinedResource.IRON_BAR] = "rbxassetid://94215413697416",
	[Enums.RefinedResource.GOLD_BAR] = "rbxassetid://137446117638753",
	[Enums.RefinedResource.DIAMOND] = "rbxassetid://101719152234191",
	[Enums.RefinedResource.URANIUM] = "rbxassetid://125767847132761",
}

-- standalone glyphs with no enum behind them
-- the reticle shown in Post Weapon Mode, by Enums.PostWeaponKind; a kind
-- without one borrows the mining dot (ClientPostManager)
Icons.POST_WEAPON_RETICLE = {
	[Enums.PostWeaponKind.MACHINE_GUN] = "rbxassetid://134742178329103",
	[Enums.PostWeaponKind.ROCKET_LAUNCHER] = "rbxassetid://105502906242582",
}

-- the tool bar slot picture per Enums.ToolKind (one for every pick axe
-- level); a kind without one shows its name instead (ClientToolBarManager)
Icons.TOOL = {
	[Enums.ToolKind.PICK_AXE] = "rbxassetid://80581106612931",
	[Enums.ToolKind.HAMMER] = "rbxassetid://96069694494045",
	[Enums.ToolKind.DEFENSES] = "rbxassetid://72202536661953",
}

-- the WEAPON slot's picture, by the Enums.WeaponKind carried
Icons.WEAPON = {
	[Enums.WeaponKind.RIFLE] = "rbxassetid://71757532147550",
}

Icons.UI = {
	-- the HUD backpack button and the jet pack fuel bar
	BACKPACK = "rbxassetid://135327278539325",
	JET_PACK = "rbxassetid://110721276111650",
	-- the Build Mode Tower counter and the kind badge on a build bar slot
	TOWER = "rbxassetid://72202536661953",
	TRAP = "rbxassetid://71088256703142",
	-- the day clock's circle (M28): placeholders until the art lands
	CLOCK_DAY = "rbxassetid://98516537326926",
	CLOCK_DUSK = "rbxassetid://91444734897924",
	CLOCK_NIGHT = "rbxassetid://72038436524050",
}

function Icons.isPlaceholder(id: string?): boolean
	return id == nil or id == Icons.PLACEHOLDER
end

return Icons
