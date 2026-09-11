-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local BakedIconUtil = require(game:GetService("ReplicatedStorage").Shared.BakedIconUtil)

describe(
	"BakedIconUtil.getImageUrlForImageId",
	function()
		it(
			"builds an rbxassetid url",
			function()
				expect(BakedIconUtil.getImageUrlForImageId(12345678)).toBe("rbxassetid://12345678")
			end
		)
	end
)

describe(
	-- the lobby place has a GameAssets folder since M8, so the scan is checked
	-- for consistency rather than emptiness
	"BakedIconUtil asset scan",
	function()
		it(
			"returns nil for an empty or unknown asset path without yielding",
			function()
				expect(BakedIconUtil.findTemplate("")).toBeNil()
				expect(BakedIconUtil.findTemplate("NoSuchFolder.NoSuchItem")).toBeNil()
			end
		)

		it(
			"returns nil baked images and only paths that resolve to templates",
			function()
				expect(BakedIconUtil.getBakedImage("NoSuchFolder.NoSuchItem")).toBeNil()
				local paths = BakedIconUtil.getAllBakeableAssetPaths()
				expect(paths).never.toContain("NoSuchFolder.NoSuchItem")
				for _, path in paths do
					expect(BakedIconUtil.findTemplate(path)).never.toBeNil()
				end
			end
		)
	end
)
