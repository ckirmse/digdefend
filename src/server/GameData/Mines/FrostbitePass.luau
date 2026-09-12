--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- PLACEHOLDER: a copy of Deadman's Canyon until Frostbite Pass is authored. Chambers inherit every
-- unspecified value from the previous chamber; chamber 1 from the defaults.
-- Uranium is spread over every chamber (GDD example had 3 / 8) so the
-- counter moves from chamber 1, while chambers 1-3 stay under uraniumTarget
-- so the last chamber is always required (decided 2026-09-12).
return {
	mineId = "frostbite_default",
	seed = nil,
	origin = Vector3.new(0, 0, 0),
	facing = Enums.MineFacing.NEGATIVE_X,

	startingCampLevel = 1,
	bedrockThickness = 1,
	veinCorridorClearance = 0,
	-- uranium rocks needed to call the rescue helicopter, solo
	uraniumTarget = 20,

	defaultChamberHeight = 8,
	defaultChamberWidth = 24,

	chambers = {
		{
			-- 1: soft, generous, everything reachable
			depth = 20,
			hardness = 1.2,
			tierBias = 1.0,
			iron = 34,
			gold = 12,
			crystal = 2,
			uranium = 2,
			corridorWidth = 3,
			corridorHeight = 3,
			handPlaced = {
				-- the upgrade advertisement: visible from the corridor, barely
				-- dentable with a starting pickaxe
				{ rock = Enums.RockName.CRYSTAL_3, depth = 6, height = 1, widthOffset = 2 },
			},
		},
		{
			-- 2: mixed rock, better ore
			depth = 24,
			hardness = 2.1,
			tierBias = 2.0,
			iron = 30,
			gold = 18,
			crystal = 6,
			uranium = 4,
		},
		{
			-- 3: taller, harder
			depth = 24,
			height = 12,
			hardness = 3.0,
			tierBias = 3.0,
			iron = 22,
			gold = 22,
			crystal = 12,
			uranium = 8,
			corridorHeight = 5,
		},
		{
			-- 4: cathedral. No corridor, just solid rock.
			depth = 28,
			height = 16,
			hardness = 3.7,
			tierBias = 4.0,
			iron = 16,
			gold = 20,
			crystal = 18,
			uranium = 14,
		},
	},
}
