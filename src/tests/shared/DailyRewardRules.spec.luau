-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local DailyRewardRules = require(game:GetService("ReplicatedStorage").Shared.DailyRewardRules)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

local DAY_SEC = 86400
local TILE_COUNT = 8

local function isKnownCosmetic(cosmeticId: string): boolean
	return cosmeticId == "KNOWN_SKIN"
end

describe(
	"DailyRewardRules claims",
	function()
		it(
			"lets a new account claim day 1 at once",
			function()
				expect(DailyRewardRules.getClaimableDay({ lastClaimedDay = 0, nextClaimTime = 0 }, 1000)).toBe(1)
			end
		)

		it(
			"locks the next day until the wait is over, and opens exactly on it",
			function()
				local state = { lastClaimedDay = 2, nextClaimTime = 5000 }
				expect(DailyRewardRules.getClaimableDay(state, 4999)).toBeNil()
				expect(DailyRewardRules.getClaimableDay(state, 5000)).toBe(3)
			end
		)

		it(
			"gives only the next day after a month away",
			function()
				local state = { lastClaimedDay = 3, nextClaimTime = 5000 }
				expect(DailyRewardRules.getClaimableDay(state, 5000 + 30 * DAY_SEC)).toBe(4)
			end
		)

		it(
			"starts the wait from the claim, floored, without changing its input",
			function()
				local state = { lastClaimedDay = 1, nextClaimTime = 0 }
				local claimed = DailyRewardRules.applyClaim(state, 1000.9, DAY_SEC)
				expect(claimed).toEqual({ lastClaimedDay = 2, nextClaimTime = 1000 + DAY_SEC })
				expect(state).toEqual({ lastClaimedDay = 1, nextClaimTime = 0 })
			end
		)

		it(
			"counts down to the next claim and reports none when one is ready",
			function()
				local state = { lastClaimedDay = 1, nextClaimTime = 5000 }
				expect(DailyRewardRules.getRemainingSec(state, 4400)).toBe(600)
				expect(DailyRewardRules.getRemainingSec(state, 5000)).toBeNil()
			end
		)
	end
)

describe(
	"DailyRewardRules tiles",
	function()
		it(
			"pays every day past the list's end from the last tile",
			function()
				expect(DailyRewardRules.getTileForDay(1, TILE_COUNT)).toBe(1)
				expect(DailyRewardRules.getTileForDay(8, TILE_COUNT)).toBe(8)
				expect(DailyRewardRules.getTileForDay(9, TILE_COUNT)).toBe(8)
				expect(DailyRewardRules.getTileForDay(100, TILE_COUNT)).toBe(8)
			end
		)

		it(
			"draws the claimed days, the ready one, and the ones ahead",
			function()
				local state = { lastClaimedDay = 2, nextClaimTime = 5000 }
				expect(DailyRewardRules.getTileState(state, 6000, 2, TILE_COUNT)).toBe("CLAIMED")
				expect(DailyRewardRules.getTileState(state, 6000, 3, TILE_COUNT)).toBe("READY")
				expect(DailyRewardRules.getTileState(state, 6000, 4, TILE_COUNT)).toBe("LOCKED")
				-- during the wait the next day is still ahead
				expect(DailyRewardRules.getTileState(state, 4000, 3, TILE_COUNT)).toBe("LOCKED")
			end
		)

		it(
			"alternates the last tile between claimed and ready past the end",
			function()
				local state = { lastClaimedDay = 12, nextClaimTime = 5000 }
				expect(DailyRewardRules.getTileState(state, 4000, 8, TILE_COUNT)).toBe("CLAIMED")
				expect(DailyRewardRules.getTileState(state, 6000, 8, TILE_COUNT)).toBe("READY")
				expect(DailyRewardRules.getTileState(state, 6000, 7, TILE_COUNT)).toBe("CLAIMED")
			end
		)
	end
)

describe(
	"DailyRewardRules catalogue",
	function()
		local REWARDS = {
			{ KIND = Enums.DailyRewardKind.DIAMONDS, AMOUNT = 10 },
			{ KIND = Enums.DailyRewardKind.KEYS, AMOUNT = 1 },
			{ KIND = Enums.DailyRewardKind.COSMETIC, COSMETIC_ID = "KNOWN_SKIN", DUPLICATE_DIAMONDS = 50 },
		}

		it(
			"accepts a well-formed list",
			function()
				expect(#DailyRewardRules.validate(REWARDS, isKnownCosmetic)).toBe(0)
			end
		)

		it(
			"names every malformed tile",
			function()
				local problems = DailyRewardRules.validate(
					{
						{ KIND = Enums.DailyRewardKind.DIAMONDS, AMOUNT = 0 },
						{ KIND = Enums.DailyRewardKind.KEYS, AMOUNT = 1.5 },
						{ KIND = Enums.DailyRewardKind.COSMETIC, COSMETIC_ID = "UNKNOWN", DUPLICATE_DIAMONDS = 50 },
						{ KIND = Enums.DailyRewardKind.COSMETIC, COSMETIC_ID = "KNOWN_SKIN" },
						{ KIND = 99 },
					},
					isKnownCosmetic
				)
				expect(#problems).toBe(5)
				expect(#DailyRewardRules.validate({}, isKnownCosmetic)).toBe(1)
			end
		)

		it(
			"survives the trip to the client",
			function()
				local published = DailyRewardRules.publish(REWARDS)
				expect(published[3]).toEqual({ kind = Enums.DailyRewardKind.COSMETIC, amount = 50, cosmeticId = "KNOWN_SKIN" })
				expect(DailyRewardRules.decodeCatalogue(DailyRewardRules.encodeCatalogue(published))).toEqual(published)
				expect(DailyRewardRules.decodeCatalogue("")).toBeNil()
				expect(DailyRewardRules.decodeCatalogue("not json")).toBeNil()
			end
		)
	end
)
