-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Constants = require(game:GetService("ReplicatedStorage").Shared.Constants)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

describe(
	"Constants.getPlaceKind",
	function()
		it(
			"matches the place id of the open place",
			function()
				local expected = Enums.PlaceKind.STUDIO
				if game.PlaceId == Constants.LOBBY_PLACE_ID then
					expected = Enums.PlaceKind.LOBBY
				elseif game.PlaceId == Constants.GAMEPLAY_PLACE_ID then
					expected = Enums.PlaceKind.GAMEPLAY
				end
				expect(Constants.getPlaceKind()).toBe(expected)
			end
		)

		it(
			"always returns a valid PlaceKind",
			function()
				expect(Enums.isValidValue(Enums.PlaceKind, Constants.getPlaceKind())).toBe(true)
			end
		)
	end
)

describe(
	"Constants values",
	function()
		it(
			"keeps the two place ids distinct",
			function()
				expect(Constants.LOBBY_PLACE_ID).never.toBe(Constants.GAMEPLAY_PLACE_ID)
			end
		)

		it(
			"defines a day in seconds",
			function()
				expect(Constants.DAY_SEC).toBe(24 * 60 * 60)
			end
		)
	end
)
