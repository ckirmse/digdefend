--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- The global rock table (GDD "Rock definitions"). Authored once for the whole
-- game; mines never redefine these. Keyed by Enums.RockName, which is also the
-- template name under ReplicatedStorage/Rocks. Cluster radius is a property
-- of the rock, not the mine: Iron 3 clusters the same way everywhere. Iron
-- and Gold clusters were shrunk a step on 2026-09-15 (radius 0-1, so one
-- to seven blocks) after play showed them clumping, and every ore vein
-- became a single block on 2026-09-28 with the mines holding four to six
-- times as many veins (a seven-block Gold II vein was a whole day of Gold
-- in one find; the designer wants more, smaller finds).
--
-- The mine is a simulator (decided 2026-09-28, docs/balance-plan.md):
-- rock HP triples a tier (10 to 810 for stone), matching the pick that
-- triples a level, so the deep mine is a wall until the pick has been
-- earned; Gold per rock quadruples a tier, so the deeper the
-- crew digs the faster they arrive, while Iron per rock only doubles a
-- tier, under the rock's HP, so a bigger pick in deeper rock does not
-- flood the tower budget (option 1 of
-- the simulator plan: the mining loop ramps, Iron does not). Uranium stays one a rock at 100 HP: a hunt, not a number.
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
			Enums.RockName.IRON_5,
		},
		[Enums.RawResource.GOLD_ORE] = {
			Enums.RockName.GOLD_1,
			Enums.RockName.GOLD_2,
			Enums.RockName.GOLD_3,
			Enums.RockName.GOLD_4,
			Enums.RockName.GOLD_5,
		},
		-- uranium has no tiers; tierBias never applies to it
		[Enums.RawResource.URANIUM_ORE] = {
			Enums.RockName.URANIUM,
		},
	},

	ROCKS = {
		[Enums.RockName.STONE_1] = { kind = Enums.RockKind.FILLER, hp = 10 },
		[Enums.RockName.STONE_2] = { kind = Enums.RockKind.FILLER, hp = 30 },
		[Enums.RockName.STONE_3] = { kind = Enums.RockKind.FILLER, hp = 90 },
		[Enums.RockName.STONE_4] = { kind = Enums.RockKind.FILLER, hp = 270 },
		[Enums.RockName.STONE_5] = { kind = Enums.RockKind.FILLER, hp = 810 },

		[Enums.RockName.IRON_1] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.IRON_ORE,
			tier = 1,
			hp = 15,
			yield = 3,
			clusterRadiusMin = 0,
			clusterRadiusMax = 0,
		},
		[Enums.RockName.IRON_2] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.IRON_ORE,
			tier = 2,
			hp = 45,
			yield = 6,
			clusterRadiusMin = 0,
			clusterRadiusMax = 0,
		},
		[Enums.RockName.IRON_3] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.IRON_ORE,
			tier = 3,
			hp = 135,
			yield = 12,
			clusterRadiusMin = 0,
			clusterRadiusMax = 0,
		},
		[Enums.RockName.IRON_4] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.IRON_ORE,
			tier = 4,
			hp = 405,
			yield = 24,
			clusterRadiusMin = 0,
			clusterRadiusMax = 0,
		},
		-- tier 5 (2026-10-06, after the first M34 run found zone 5 harder rock
		-- for zone 4's ore): Iron per rock triples here rather than doubling,
		-- since Iron is what starves a crew by day 10
		[Enums.RockName.IRON_5] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.IRON_ORE,
			tier = 5,
			hp = 1215,
			yield = 72,
			clusterRadiusMin = 0,
			clusterRadiusMax = 0,
		},

		[Enums.RockName.GOLD_1] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.GOLD_ORE,
			tier = 1,
			hp = 20,
			yield = 3,
			clusterRadiusMin = 0,
			clusterRadiusMax = 0,
		},
		[Enums.RockName.GOLD_2] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.GOLD_ORE,
			tier = 2,
			hp = 60,
			yield = 12,
			clusterRadiusMin = 0,
			clusterRadiusMax = 0,
		},
		[Enums.RockName.GOLD_3] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.GOLD_ORE,
			tier = 3,
			hp = 180,
			yield = 48,
			clusterRadiusMin = 0,
			clusterRadiusMax = 0,
		},
		[Enums.RockName.GOLD_4] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.GOLD_ORE,
			tier = 4,
			hp = 540,
			yield = 192,
			clusterRadiusMin = 0,
			clusterRadiusMax = 0,
		},
		[Enums.RockName.GOLD_5] = {
			kind = Enums.RockKind.RESOURCE,
			resource = Enums.RawResource.GOLD_ORE,
			tier = 5,
			hp = 1620,
			yield = 768,
			clusterRadiusMin = 0,
			clusterRadiusMax = 0,
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
