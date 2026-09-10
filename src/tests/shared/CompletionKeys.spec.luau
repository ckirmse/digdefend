-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local CompletionKeys = require(game:GetService("ReplicatedStorage").Shared.CompletionKeys)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

describe(
	"CompletionKeys",
	function()
		it(
			"round-trips every map and difficulty",
			function()
				for _, map in Enums.getAllValues(Enums.Map) do
					for _, difficulty in Enums.getAllValues(Enums.Difficulty) do
						local key = CompletionKeys.make(map, difficulty)
						expect(key).never.toBeNil()
						local parsedMap, parsedDifficulty = CompletionKeys.parse(key)
						expect(parsedMap).toBe(map)
						expect(parsedDifficulty).toBe(difficulty)
						expect(CompletionKeys.isValid(key)).toBe(true)
					end
				end
			end
		)

		it(
			"produces readable keys",
			function()
				expect(CompletionKeys.make(Enums.Map.DEADMANS_CANYON, Enums.Difficulty.NORMAL)).toBe("DEADMANS_CANYON/NORMAL")
			end
		)

		it(
			"rejects invalid inputs",
			function()
				expect(CompletionKeys.make(99, Enums.Difficulty.NORMAL)).toBeNil()
				expect(CompletionKeys.make(Enums.Map.DEADMANS_CANYON, 99)).toBeNil()
				expect(CompletionKeys.isValid("DEADMANS_CANYON")).toBe(false)
				expect(CompletionKeys.isValid("DEADMANS_CANYON/EASY")).toBe(false)
				expect(CompletionKeys.isValid("deadmans_canyon/normal")).toBe(false)
				expect(CompletionKeys.isValid("PublicNames/NORMAL")).toBe(false)
				expect(CompletionKeys.isValid(nil)).toBe(false)
				expect(CompletionKeys.isValid(5)).toBe(false)
			end
		)
	end
)
