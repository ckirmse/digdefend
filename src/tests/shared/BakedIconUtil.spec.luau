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
	"BakedIconUtil without a GameAssets folder",
	function()
		it(
			"returns nil for an empty or unknown asset path without yielding",
			function()
				expect(BakedIconUtil.findTemplate("")).toBeNil()
				expect(BakedIconUtil.findTemplate("NoSuchFolder.NoSuchItem")).toBeNil()
			end
		)

		it(
			"returns nil baked images and an empty asset list",
			function()
				expect(BakedIconUtil.getBakedImage("NoSuchFolder.NoSuchItem")).toBeNil()
				expect(BakedIconUtil.getAllBakeableAssetPaths()).toEqual({})
			end
		)
	end
)
