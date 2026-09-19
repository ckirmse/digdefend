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

Icons.UI = {
	BACKPACK = Icons.PLACEHOLDER,
}

function Icons.isPlaceholder(id: string?): boolean
	return id == nil or id == Icons.PLACEHOLDER
end

return Icons
