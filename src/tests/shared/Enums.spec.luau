-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

describe(
	"Enums helpers",
	function()
		it(
			"counts only numeric entries so PublicNames is skipped",
			function()
				expect(Enums.getCount(Enums.Difficulty)).toBe(3)
				expect(Enums.getCount(Enums.PlaceKind)).toBe(3)
				expect(Enums.getCount(Enums.RawResource)).toBe(4)
			end
		)

		it(
			"lists all values sorted",
			function()
				expect(Enums.getAllValues(Enums.Difficulty)).toEqual({ 1, 2, 3 })
				expect(Enums.getAllValues(Enums.RefinedResource)).toEqual({ 1, 2, 3, 4 })
			end
		)

		it(
			"validates values and never matches the PublicNames table",
			function()
				expect(Enums.isValidValue(Enums.Difficulty, Enums.Difficulty.HARD)).toBe(true)
				expect(Enums.isValidValue(Enums.Difficulty, 0)).toBe(false)
				expect(Enums.isValidValue(Enums.Difficulty, 4)).toBe(false)
				expect(Enums.isValidValue(Enums.Difficulty, Enums.Difficulty.PublicNames)).toBe(false)
				expect(Enums.isValidValue(Enums.Difficulty, "HARD")).toBe(false)
			end
		)

		it(
			"maps values to key names and back",
			function()
				expect(Enums.getName(Enums.Map, Enums.Map.FROSTBITE_PASS)).toBe("FROSTBITE_PASS")
				expect(Enums.getValueByName(Enums.Map, "DEADMANS_CANYON")).toBe(Enums.Map.DEADMANS_CANYON)
				expect(Enums.getValueByName(Enums.Map, "PublicNames")).toBeNil()
				expect(Enums.getValueByName(Enums.Map, "NOT_A_MAP")).toBeNil()
				expect(Enums.getName(Enums.Map, 99)).toBeNil()
			end
		)

		it(
			"returns player-facing names when present",
			function()
				expect(Enums.getPublicName(Enums.Map, Enums.Map.DEADMANS_CANYON)).toBe("Deadman's Canyon")
				expect(Enums.getPublicName(Enums.RawResource, Enums.RawResource.URANIUM_ORE)).toBe("Uranium Ore")
				expect(Enums.getPublicName(Enums.Difficulty, nil)).toBeNil()
				expect(Enums.getPublicName(Enums.Difficulty, 99)).toBeNil()
			end
		)

		it(
			"returns nil public names for enums that have none",
			function()
				expect(Enums.getPublicName(Enums.RockKind, Enums.RockKind.BEDROCK)).toBeNil()
			end
		)

		it(
			"tolerates a non-table argument",
			function()
				expect(Enums.getCount(nil)).toBe(0)
				expect(Enums.getAllValues(5)).toEqual({})
				expect(Enums.isValidValue("x", 1)).toBe(false)
				expect(Enums.getName(nil, 1)).toBeNil()
				expect(Enums.getValueByName(nil, "X")).toBeNil()
				expect(Enums.getPublicName(nil, 1)).toBeNil()
			end
		)
	end
)

describe(
	"Enums content rules",
	function()
		local function isEnumTable(value: any): boolean
			if typeof(value) ~= "table" then
				return false
			end
			for _, entry in value do
				if typeof(entry) == "number" then
					return true
				end
			end
			return false
		end

		it(
			"uses SCREAMING_SNAKE_CASE keys and unique values in every enum",
			function()
				for enumName, enumTable in Enums :: { [string]: any } do
					if not isEnumTable(enumTable) then
						continue
					end
					local seenValues: { [number]: string } = {}
					for key, value in enumTable do
						if key == "PublicNames" then
							continue
						end
						expect(key).toMatch("^[A-Z][A-Z0-9_]*$")
						expect(seenValues[value]).toBeNil()
						seenValues[value] = key
					end
				end
			end
		)

		it(
			"only names keys that exist in PublicNames",
			function()
				for enumName, enumTable in Enums :: { [string]: any } do
					if not isEnumTable(enumTable) or not enumTable.PublicNames then
						continue
					end
					for key in enumTable.PublicNames do
						expect(typeof(enumTable[key])).toBe("number")
					end
				end
			end
		)
	end
)
