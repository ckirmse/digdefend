-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local CompletionKeys = require(game:GetService("ReplicatedStorage").Shared.CompletionKeys)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local PartyRules = require(game:GetService("ReplicatedStorage").Shared.PartyRules)

-- mirrors GameData/Pads/Party at launch; GameData itself cannot load under
-- jest because it requires through the @game alias
local function makeConfig()
	return {
		CREATION_TIMEOUT_SEC = 30,
		BOARDING_TIMEOUT_SEC = 120,
		CAPACITY_TIME_SEC = 3,
		MAX_PARTY_SIZE = 6,
		DEFAULT_MAX_PLAYERS = 4,
		DEFAULT_VISIBILITY = Enums.PartyVisibility.PUBLIC,
		MAPS = {
			{ map = Enums.Map.DEADMANS_CANYON, thumbnail = "rbxassetid://0" },
			{
				map = Enums.Map.FROSTBITE_PASS,
				thumbnail = "rbxassetid://0",
				requires = { map = Enums.Map.DEADMANS_CANYON, difficulty = Enums.Difficulty.NORMAL },
			},
		},
		DIFFICULTIES = {
			{ difficulty = Enums.Difficulty.NORMAL },
			{ difficulty = Enums.Difficulty.HARD, requires = { difficulty = Enums.Difficulty.NORMAL } },
			{ difficulty = Enums.Difficulty.NIGHTMARE, requires = { difficulty = Enums.Difficulty.HARD } },
		},
	}
end

local function makeHasCompletion(keys)
	local set = {}
	for _, key in keys do
		set[key] = true
	end
	return function(key)
		return set[key] == true
	end
end

local CANYON_NORMAL = CompletionKeys.make(Enums.Map.DEADMANS_CANYON, Enums.Difficulty.NORMAL)
local CANYON_HARD = CompletionKeys.make(Enums.Map.DEADMANS_CANYON, Enums.Difficulty.HARD)
local FROSTBITE_NORMAL = CompletionKeys.make(Enums.Map.FROSTBITE_PASS, Enums.Difficulty.NORMAL)

describe(
	"PartyRules.validateConfig",
	function()
		it(
			"accepts the launch config",
			function()
				expect(PartyRules.validateConfig(makeConfig())).toEqual({})
			end
		)

		it(
			"rejects a non-table",
			function()
				expect(#PartyRules.validateConfig(nil)).toBe(1)
			end
		)

		it(
			"rejects duplicate maps and difficulties",
			function()
				local config = makeConfig()
				table.insert(config.MAPS, { map = Enums.Map.DEADMANS_CANYON, thumbnail = "" })
				table.insert(config.DIFFICULTIES, { difficulty = Enums.Difficulty.HARD })
				local problems = PartyRules.validateConfig(config)
				expect(#problems).toBe(2)
				expect(problems[1]).toContain("MAPS[3]")
				expect(problems[2]).toContain("DIFFICULTIES[4]")
			end
		)

		it(
			"rejects requirements that reference missing entries",
			function()
				local config = makeConfig()
				table.remove(config.DIFFICULTIES, 1)
				local problems = PartyRules.validateConfig(config)
				-- Frostbite requires NORMAL and Hard requires NORMAL
				expect(#problems).toBe(2)
				expect(problems[1]).toContain("MAPS[2].requires.difficulty")
				expect(problems[2]).toContain("DIFFICULTIES[1].requires.difficulty")
			end
		)

		it(
			"rejects self requirements and bad defaults",
			function()
				local config = makeConfig()
				config.DIFFICULTIES[2].requires = { difficulty = Enums.Difficulty.HARD }
				config.DEFAULT_MAX_PLAYERS = 7
				local problems = PartyRules.validateConfig(config)
				expect(#problems).toBe(2)
				expect(problems[1]).toContain("DEFAULT_MAX_PLAYERS")
				expect(problems[2]).toContain("requires itself")
			end
		)

		it(
			"rejects non-positive timers through the shape",
			function()
				local config = makeConfig()
				config.CAPACITY_TIME_SEC = 0
				local problems = PartyRules.validateConfig(config)
				expect(#problems).toBe(1)
				expect(problems[1]).toContain("CAPACITY_TIME_SEC")
			end
		)
	end
)

describe(
	"PartyRules unlocks",
	function()
		it(
			"unlocks the first map and difficulty for a new player",
			function()
				local config = makeConfig()
				local none = makeHasCompletion({})
				expect(PartyRules.isMapUnlocked(config, Enums.Map.DEADMANS_CANYON, none)).toBe(true)
				expect(PartyRules.isMapUnlocked(config, Enums.Map.FROSTBITE_PASS, none)).toBe(false)
				expect(PartyRules.isDifficultyUnlocked(config, Enums.Map.DEADMANS_CANYON, Enums.Difficulty.NORMAL, none)).toBe(true)
				expect(PartyRules.isDifficultyUnlocked(config, Enums.Map.DEADMANS_CANYON, Enums.Difficulty.HARD, none)).toBe(false)
				expect(PartyRules.getFirstUnlockedDifficulty(config, Enums.Map.DEADMANS_CANYON, none)).toBe(Enums.Difficulty.NORMAL)
			end
		)

		it(
			"follows the completion chain per map",
			function()
				local config = makeConfig()
				local hasCompletion = makeHasCompletion({ CANYON_NORMAL, CANYON_HARD })
				expect(PartyRules.isMapUnlocked(config, Enums.Map.FROSTBITE_PASS, hasCompletion)).toBe(true)
				expect(PartyRules.isDifficultyUnlocked(config, Enums.Map.DEADMANS_CANYON, Enums.Difficulty.NIGHTMARE, hasCompletion)).toBe(true)
				-- Hard on Frostbite needs Frostbite Normal, not Canyon Normal
				expect(PartyRules.isDifficultyUnlocked(config, Enums.Map.FROSTBITE_PASS, Enums.Difficulty.HARD, hasCompletion)).toBe(false)
				expect(PartyRules.isDifficultyUnlocked(config, Enums.Map.FROSTBITE_PASS, Enums.Difficulty.HARD, makeHasCompletion({ FROSTBITE_NORMAL }))).toBe(true)
			end
		)

		it(
			"rejects unknown maps and difficulties",
			function()
				local config = makeConfig()
				local all = function()
					return true
				end
				expect(PartyRules.isMapUnlocked(config, 99, all)).toBe(false)
				expect(PartyRules.isDifficultyUnlocked(config, Enums.Map.DEADMANS_CANYON, 99, all)).toBe(false)
			end
		)

		it(
			"names requirements for the menu",
			function()
				local config = makeConfig()
				local key = PartyRules.getDifficultyRequirementKey(config, Enums.Map.FROSTBITE_PASS, Enums.Difficulty.HARD)
				expect(key).toBe(FROSTBITE_NORMAL)
				expect(PartyRules.getRequirementText(key)).toBe("Complete Frostbite Pass on Normal")
				expect(PartyRules.getMapRequirementKey(config, Enums.Map.DEADMANS_CANYON)).toBeNil()
				expect(PartyRules.getRequirementText("garbage")).toBe("Locked")
			end
		)
	end
)

describe(
	"PartyRules.validateSelection",
	function()
		local function selection(overrides)
			local result = {
				map = Enums.Map.DEADMANS_CANYON,
				difficulty = Enums.Difficulty.NORMAL,
				maxPlayers = 4,
				visibility = Enums.PartyVisibility.PUBLIC,
			}
			for key, value in overrides or {} do
				result[key] = value
			end
			return result
		end

		it(
			"accepts a valid selection",
			function()
				local isValid, reason = PartyRules.validateSelection(makeConfig(), selection(), makeHasCompletion({}))
				expect(isValid).toBe(true)
				expect(reason).toBeNil()
			end
		)

		it(
			"rejects each failing rule with a reason",
			function()
				local config = makeConfig()
				local none = makeHasCompletion({})
				local cases = {
					{ selection({ map = "Canyon" }), "Invalid party settings" },
					{ selection({ maxPlayers = 0 }), "Invalid party settings" },
					{ selection({ visibility = 7 }), "Invalid party settings" },
					{ selection({ map = Enums.Map.FROSTBITE_PASS }), "Map is locked" },
					{ selection({ difficulty = Enums.Difficulty.HARD }), "Difficulty is locked" },
					{ selection({ maxPlayers = 7 }), "Party size too large" },
				}
				for _, case in cases do
					local isValid, reason = PartyRules.validateSelection(config, case[1], none)
					expect(isValid).toBe(false)
					expect(reason).toBe(case[2])
				end
			end
		)

		it(
			"reports maps missing from the config as unknown",
			function()
				local config = makeConfig()
				table.remove(config.MAPS, 2)
				local isValid, reason = PartyRules.validateSelection(config, selection({ map = Enums.Map.FROSTBITE_PASS }), makeHasCompletion({ CANYON_NORMAL }))
				expect(isValid).toBe(false)
				expect(reason).toBe("Unknown map")
			end
		)
	end
)
