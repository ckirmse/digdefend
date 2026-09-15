--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- The global rock table (GDD "Rock definitions"). Authored once for the whole
-- game; mines never redefine these. Keyed by Enums.RockName, which is also the
-- template name under ReplicatedStorage/Rocks. Cluster radius is a property
-- of the rock, not the mine: Iron 3 clusters the same way everywhere.
--
-- FILLER_ORDER is load-bearing: the hardness kernel maps a center of 1.0 to
-- the first entry and a center equal to the list length to the last, so it
-- must stay sorted by HP. One filler rock, Stone, in five tiers (decided
-- 2026-09-15): several filler kinds did the same job and hid the ore.
return {
	FILLER_ORDER = {
		Enums.RockName.STONE_1,
		Enums.RockName.STONE_2,
		Enums.RockName.STONE_3,
		Enums.RockName.STONE_4,
		Enums.RockName.STONE_5,
	},

	-- resource -> tier -> rock, in the order the tierBias kernel walks them
	RESOURCE_TIERS = {
		[Enums.RawResource.IRON_ORE] = {
			Enums.RockName.IRON_1,
			Enums.RockName.IRON_2,
			Enums.RockName.IRON_3,
			Enums.RockName.IRON_4,
		},
		[Enums.RawResource.GOLD_ORE] = {
			Enums.RockName.GOLD_1,
			Enums.RockName.GOLD_2,
			Enums.RockName.GOLD_3,
			Enums.RockName.GOLD_4,
		},
		[Enums.RawResource.CRYSTAL] = {
			Enums.RockName.CRYSTAL_1,
			Enums.RockName.CRYSTAL_2,
			Enums.RockName.CRYSTAL_3,
			Enums.RockName.CRYSTAL_4,
		},
		-- uranium has no tiers; tierBias never applies to it
		[Enums.RawResource.URANIUM_ORE] = {
			Enums.RockName.URANIUM,
		},
	},

	ROCKS = {
		[Enums.RockName.STONE_1] = { kind = Enums.RockKind.FILLER, hp = 10 },
		[Enums.RockName.STONE_2] = { kind = Enums.RockKind.FILLER, hp = 20 },
		[Enums.RockName.STONE_3] = { kind = Enums.RockKind.FILLER, hp = 40 },
		[Enums.RockName.STONE_4] = { kind = Enums.RockKind.FILLER, hp = 80 },
		[Enums.RockName.STONE_5] = { kind = Enums.RockKind.FILLER, hp = 160 },

		[Enums.RockName.IRON_1] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.IRON_ORE,
			tier = 1,
			hp = 15,
			yield = 3,
			clusterRadiusMin = 1,
			clusterRadiusMax = 2,
		},
		[Enums.RockName.IRON_2] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.IRON_ORE,
			tier = 2,
			hp = 30,
			yield = 10,
			clusterRadiusMin = 1,
			clusterRadiusMax = 2,
		},
		[Enums.RockName.IRON_3] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.IRON_ORE,
			tier = 3,
			hp = 60,
			yield = 29,
			clusterRadiusMin = 1,
			clusterRadiusMax = 2,
		},
		[Enums.RockName.IRON_4] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.IRON_ORE,
			tier = 4,
			hp = 110,
			yield = 78,
			clusterRadiusMin = 0,
			clusterRadiusMax = 1,
		},

		[Enums.RockName.GOLD_1] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.GOLD_ORE,
			tier = 1,
			hp = 20,
			yield = 3,
			clusterRadiusMin = 1,
			clusterRadiusMax = 2,
		},
		[Enums.RockName.GOLD_2] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.GOLD_ORE,
			tier = 2,
			hp = 40,
			yield = 10,
			clusterRadiusMin = 1,
			clusterRadiusMax = 2,
		},
		[Enums.RockName.GOLD_3] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.GOLD_ORE,
			tier = 3,
			hp = 75,
			yield = 30,
			clusterRadiusMin = 1,
			clusterRadiusMax = 1,
		},
		[Enums.RockName.GOLD_4] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.GOLD_ORE,
			tier = 4,
			hp = 140,
			yield = 87,
			clusterRadiusMin = 0,
			clusterRadiusMax = 1,
		},

		[Enums.RockName.CRYSTAL_1] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.CRYSTAL,
			tier = 1,
			hp = 30,
			yield = 2,
			clusterRadiusMin = 1,
			clusterRadiusMax = 1,
		},
		[Enums.RockName.CRYSTAL_2] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.CRYSTAL,
			tier = 2,
			hp = 60,
			yield = 5,
			clusterRadiusMin = 1,
			clusterRadiusMax = 1,
		},
		[Enums.RockName.CRYSTAL_3] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.CRYSTAL,
			tier = 3,
			hp = 110,
			yield = 14,
			clusterRadiusMin = 0,
			clusterRadiusMax = 1,
		},
		[Enums.RockName.CRYSTAL_4] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.CRYSTAL,
			tier = 4,
			hp = 200,
			yield = 39,
			clusterRadiusMin = 0,
			clusterRadiusMax = 1,
		},

		[Enums.RockName.URANIUM] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.URANIUM_ORE,
			tier = 1,
			hp = 100,
			yield = 1,
			clusterRadiusMin = 0,
			clusterRadiusMax = 0,
		},

		-- structural rock: indestructible, no HP; the shell around the mine
		[Enums.RockName.BEDROCK] = { kind = Enums.RockKind.BEDROCK },
	},
}
