-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local Icons = require(game:GetService("ReplicatedStorage").Shared.Icons)

local ASSET_ID_PATTERN = "^rbxassetid://%d+$"

describe(
	"Icons",
	function()
		it(
			"has a well-formed entry for every raw resource",
			function()
				for _, value in Enums.getAllValues(Enums.RawResource) do
					expect(Icons.RAW_RESOURCE[value]).toMatch(ASSET_ID_PATTERN)
				end
			end
		)

		it(
			"has a well-formed entry for every refined resource",
			function()
				for _, value in Enums.getAllValues(Enums.RefinedResource) do
					expect(Icons.REFINED_RESOURCE[value]).toMatch(ASSET_ID_PATTERN)
				end
			end
		)

		it(
			"every UI glyph is a well-formed id or the placeholder",
			function()
				for _, id in Icons.UI do
					expect(id).toMatch(ASSET_ID_PATTERN)
				end
			end
		)

		it(
			"treats nil and the zero id as placeholders",
			function()
				expect(Icons.isPlaceholder(nil)).toBe(true)
				expect(Icons.isPlaceholder(Icons.PLACEHOLDER)).toBe(true)
				expect(Icons.isPlaceholder(Icons.RAW_RESOURCE[Enums.RawResource.IRON_ORE])).toBe(false)
			end
		)
	end
)
