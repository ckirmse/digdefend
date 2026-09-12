--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- The global rock table (GDD "Rock definitions"). Authored once for the whole
-- game; mines never redefine these. Keyed by Enums.RockName, which is also the
-- template name under ReplicatedStorage/Rocks. Cluster radius is a property
-- of the rock, not the mine: Iron 3 clusters the same way everywhere.
--
-- FILLER_ORDER is load-bearing: the hardness kernel maps a center of 1.0 to
-- the first entry and 4.0 to the last, so it must stay sorted by HP.
return {
	FILLER_ORDER = {
		Enums.RockName.SHALE,
		Enums.RockName.SANDSTONE,
		Enums.RockName.GRANITE,
		Enums.RockName.BASALT,
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
		[Enums.RockName.SHALE] = { kind = Enums.RockKind.FILLER, hp = 10 },
		[Enums.RockName.SANDSTONE] = { kind = Enums.RockKind.FILLER, hp = 20 },
		[Enums.RockName.GRANITE] = { kind = Enums.RockKind.FILLER, hp = 40 },
		[Enums.RockName.BASALT] = { kind = Enums.RockKind.FILLER, hp = 80 },

		[Enums.RockName.IRON_1] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.IRON_ORE,
			tier = 1,
			hp = 15,
			yield = 5,
			clusterRadiusMin = 1,
			clusterRadiusMax = 2,
		},
		[Enums.RockName.IRON_2] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.IRON_ORE,
			tier = 2,
			hp = 30,
			yield = 16,
			clusterRadiusMin = 1,
			clusterRadiusMax = 2,
		},
		[Enums.RockName.IRON_3] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.IRON_ORE,
			tier = 3,
			hp = 60,
			yield = 48,
			clusterRadiusMin = 1,
			clusterRadiusMax = 2,
		},
		[Enums.RockName.IRON_4] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.IRON_ORE,
			tier = 4,
			hp = 110,
			yield = 130,
			clusterRadiusMin = 0,
			clusterRadiusMax = 1,
		},

		[Enums.RockName.GOLD_1] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.GOLD_ORE,
			tier = 1,
			hp = 20,
			yield = 5,
			clusterRadiusMin = 1,
			clusterRadiusMax = 2,
		},
		[Enums.RockName.GOLD_2] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.GOLD_ORE,
			tier = 2,
			hp = 40,
			yield = 17,
			clusterRadiusMin = 1,
			clusterRadiusMax = 2,
		},
		[Enums.RockName.GOLD_3] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.GOLD_ORE,
			tier = 3,
			hp = 75,
			yield = 50,
			clusterRadiusMin = 1,
			clusterRadiusMax = 1,
		},
		[Enums.RockName.GOLD_4] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.GOLD_ORE,
			tier = 4,
			hp = 140,
			yield = 145,
			clusterRadiusMin = 0,
			clusterRadiusMax = 1,
		},

		[Enums.RockName.CRYSTAL_1] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.CRYSTAL,
			tier = 1,
			hp = 30,
			yield = 3,
			clusterRadiusMin = 1,
			clusterRadiusMax = 1,
		},
		[Enums.RockName.CRYSTAL_2] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.CRYSTAL,
			tier = 2,
			hp = 60,
			yield = 9,
			clusterRadiusMin = 1,
			clusterRadiusMax = 1,
		},
		[Enums.RockName.CRYSTAL_3] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.CRYSTAL,
			tier = 3,
			hp = 110,
			yield = 24,
			clusterRadiusMin = 0,
			clusterRadiusMax = 1,
		},
		[Enums.RockName.CRYSTAL_4] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.CRYSTAL,
			tier = 4,
			hp = 200,
			yield = 65,
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

		-- structural rock: indestructible, no HP. Gate becomes air when its
		-- chamber unlocks.
		[Enums.RockName.BEDROCK] = { kind = Enums.RockKind.BEDROCK },
		[Enums.RockName.GATE] = { kind = Enums.RockKind.GATE },
	},
}
