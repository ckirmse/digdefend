-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local BinocularsRules = require(game:GetService("ReplicatedStorage").Shared.BinocularsRules)

describe(
	"BinocularsRules timing",
	function()
		it(
			"keeps a tag live until its end time",
			function()
				expect(BinocularsRules.isTagLive(110, 100)).toBe(true)
				expect(BinocularsRules.isTagLive(110, 109.9)).toBe(true)
				expect(BinocularsRules.isTagLive(110, 110)).toBe(false)
			end
		)

		it(
			"lets a fresh player tag at once and holds a recent tagger for the cooldown",
			function()
				expect(BinocularsRules.isCooldownOver(nil, 100, 3)).toBe(true)
				expect(BinocularsRules.isCooldownOver(100, 102.9, 3)).toBe(false)
				expect(BinocularsRules.isCooldownOver(100, 103, 3)).toBe(true)
			end
		)

		it(
			"reports the cooldown left as a share from 1 to 0",
			function()
				expect(BinocularsRules.cooldownShare(103, 3, 100)).toBeCloseTo(1, 5)
				expect(BinocularsRules.cooldownShare(103, 3, 101.5)).toBeCloseTo(0.5, 5)
				expect(BinocularsRules.cooldownShare(103, 3, 103)).toBe(0)
				expect(BinocularsRules.cooldownShare(103, 3, 110)).toBe(0)
				expect(BinocularsRules.cooldownShare(103, 0, 100)).toBe(0)
			end
		)
	end
)

describe(
	"BinocularsRules tag codec",
	function()
		it(
			"round-trips a tag and reads nothing from an empty or foreign value",
			function()
				local tag = { damageableId = "Damageable12", endTime = 1234.5 }
				local decoded = BinocularsRules.decodeTag(BinocularsRules.encodeTag(tag))
				expect(decoded).toEqual(tag)
				expect(BinocularsRules.encodeTag(nil)).toBe(BinocularsRules.NO_TAG)
				expect(BinocularsRules.decodeTag(BinocularsRules.NO_TAG)).toBe(nil)
				expect(BinocularsRules.decodeTag(nil)).toBe(nil)
				expect(BinocularsRules.decodeTag("not json")).toBe(nil)
				expect(BinocularsRules.decodeTag('{"id":5}')).toBe(nil)
			end
		)
	end
)
