-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Attributes = require(game:GetService("ReplicatedStorage").Shared.Attributes)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local PlayerPublicSchema = require(game:GetService("ReplicatedStorage").Shared.PlayerPublicSchema)

local function makeSnapshot()
	return {
		userId = 123,
		displayName = "Ada",
		isReady = true,
		isAdmin = true,
		cash = 4321,
		loadout = { WEAPON = "Pistol", DEFENSE_2 = "Spikes" },
		dailyRewardLastClaimedDay = 3,
		dailyRewardNextClaimTime = 1700000000,
	}
end

describe(
	"PlayerPublicSchema.buildPublicAttributes",
	function()
		it(
			"exposes only identity and readiness",
			function()
				local attributes = PlayerPublicSchema.buildPublicAttributes(makeSnapshot())
				expect(attributes).toEqual({
					[Attributes.USER_ID] = 123,
					[Attributes.DISPLAY_NAME] = "Ada",
					[Attributes.IS_READY] = true,
				})
			end
		)

		it(
			"never leaks private fields",
			function()
				local attributes = PlayerPublicSchema.buildPublicAttributes(makeSnapshot())
				expect(attributes[Attributes.IS_ADMIN]).toBeNil()
				expect(attributes[Attributes.CASH]).toBeNil()
				expect(attributes[Attributes.LOADOUT_WEAPON]).toBeNil()
			end
		)
	end
)

describe(
	"PlayerPublicSchema.buildCurrentPlayerAttributes",
	function()
		it(
			"maps private fields and every loadout slot",
			function()
				local attributes = PlayerPublicSchema.buildCurrentPlayerAttributes(makeSnapshot())
				expect(attributes[Attributes.USER_ID]).toBe(123)
				expect(attributes[Attributes.CASH]).toBe(4321)
				expect(attributes[Attributes.IS_ADMIN]).toBe(true)
				expect(attributes[Attributes.LOADOUT_WEAPON]).toBe("Pistol")
				expect(attributes[Attributes.LOADOUT_POST]).toBe("")
				expect(attributes[Attributes.LOADOUT_DEFENSE_1]).toBe("")
				expect(attributes[Attributes.LOADOUT_DEFENSE_2]).toBe("Spikes")
				expect(attributes[Attributes.LOADOUT_DEFENSE_3]).toBe("")
				expect(attributes[Attributes.DAILY_REWARD_LAST_CLAIMED_DAY]).toBe(3)
				expect(attributes[Attributes.DAILY_REWARD_NEXT_CLAIM_TIME]).toBe(1700000000)
			end
		)

		it(
			"defaults optional fields for a brand-new player",
			function()
				local attributes = PlayerPublicSchema.buildCurrentPlayerAttributes({
					userId = 7,
					displayName = "Bob",
					isReady = true,
				})
				expect(attributes[Attributes.CASH]).toBe(0)
				expect(attributes[Attributes.IS_ADMIN]).toBe(false)
				expect(attributes[Attributes.LOADOUT_WEAPON]).toBe("")
				expect(attributes[Attributes.DAILY_REWARD_LAST_CLAIMED_DAY]).toBe(0)
			end
		)

		it(
			"has one attribute per loadout slot",
			function()
				for _, slot in Enums.getAllValues(Enums.LoadoutSlot) do
					expect(typeof(PlayerPublicSchema.getLoadoutAttribute(slot))).toBe("string")
				end
				expect(PlayerPublicSchema.getLoadoutAttribute(99)).toBeNil()
			end
		)
	end
)
