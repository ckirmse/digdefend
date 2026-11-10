-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Attributes = require(game:GetService("ReplicatedStorage").Shared.Attributes)
local ClassSchema = require(game:GetService("ReplicatedStorage").Shared.ClassSchema)
local CosmeticLoadoutSchema = require(game:GetService("ReplicatedStorage").Shared.CosmeticLoadoutSchema)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local GachaRules = require(game:GetService("ReplicatedStorage").Shared.GachaRules)
local PlayerPublicSchema = require(game:GetService("ReplicatedStorage").Shared.PlayerPublicSchema)

-- the account owns the Gunner with two skill slots open (M70)
local PROGRESS = { RECRUIT = 0, GUNNER = 2 }
local MAX_SKILL_SLOTS = 3

local function makeRecords()
	return {
		GUNNER = {
			skills = { ["1"] = { skillId = "GOLD_DIGGER", rarity = Enums.Rarity.RARE } },
		},
	}
end

local function makeSnapshot()
	return {
		userId = 123,
		displayName = "Ada",
		isReady = true,
		isAdmin = true,
		diamonds = 4321,
		classRecords = makeRecords(),
		activeClassKind = Enums.ClassKind.GUNNER,
		cosmetics = { PICK_AXE = "lamp" },
		classProgress = PROGRESS,
		maxSkillSlots = MAX_SKILL_SLOTS,
		keys = 5,
		ownedCosmetics = { HARD_HAT = true },
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
				expect(attributes[Attributes.DIAMONDS]).toBeNil()
				expect(attributes[Attributes.CLASS_RECORDS]).toBeNil()
			end
		)
	end
)

describe(
	"PlayerPublicSchema.buildClassAttributes",
	function()
		it(
			"carries the active class as a value and every record through the codec",
			function()
				local attributes = PlayerPublicSchema.buildClassAttributes(makeRecords(), Enums.ClassKind.GUNNER, MAX_SKILL_SLOTS)
				expect(attributes[Attributes.ACTIVE_CLASS_KIND]).toBe(Enums.ClassKind.GUNNER)
				expect(ClassSchema.decodeRecords(attributes[Attributes.CLASS_RECORDS])).toEqual(makeRecords())
			end
		)

		it(
			"writes blanks for no save so stale values are overwritten",
			function()
				local attributes = PlayerPublicSchema.buildClassAttributes(nil, nil, nil)
				expect(attributes[Attributes.ACTIVE_CLASS_KIND]).toBe(0)
				expect(attributes[Attributes.CLASS_RECORDS]).toBe("")
			end
		)
	end
)

describe(
	"PlayerPublicSchema.classKindOf",
	function()
		it(
			"resolves a class name and reads nil or an unknown name as 0",
			function()
				expect(PlayerPublicSchema.classKindOf("GUNNER")).toBe(Enums.ClassKind.GUNNER)
				expect(PlayerPublicSchema.classKindOf("NOPE")).toBe(0)
				expect(PlayerPublicSchema.classKindOf(nil)).toBe(0)
			end
		)
	end
)

describe(
	"PlayerPublicSchema.buildCurrentPlayerAttributes",
	function()
		it(
			"maps private fields, the gacha state, and the classes",
			function()
				local attributes = PlayerPublicSchema.buildCurrentPlayerAttributes(makeSnapshot())
				expect(attributes[Attributes.USER_ID]).toBe(123)
				expect(attributes[Attributes.DIAMONDS]).toBe(4321)
				expect(attributes[Attributes.IS_ADMIN]).toBe(true)
				expect(attributes[Attributes.ACTIVE_CLASS_KIND]).toBe(Enums.ClassKind.GUNNER)
				expect(ClassSchema.decodeRecords(attributes[Attributes.CLASS_RECORDS]).GUNNER.skills["1"].skillId).toBe("GOLD_DIGGER")
				expect(CosmeticLoadoutSchema.decode(attributes[Attributes.COSMETICS])).toEqual({ PICK_AXE = "lamp" })
				expect(attributes[Attributes.DAILY_REWARD_LAST_CLAIMED_DAY]).toBe(3)
				expect(attributes[Attributes.DAILY_REWARD_NEXT_CLAIM_TIME]).toBe(1700000000)
				expect(attributes[Attributes.KEYS]).toBe(5)
				expect(attributes[Attributes.HAS_FINISHED_TUTORIAL]).toBe(false)
				expect(GachaRules.decodeProgress(attributes[Attributes.CLASS_PROGRESS])).toEqual(PROGRESS)
				expect(GachaRules.decodeOwnedCosmetics(attributes[Attributes.OWNED_COSMETICS])).toEqual({ HARD_HAT = true })
			end
		)

		it(
			"defaults optional fields for a snapshot without a save",
			function()
				local attributes = PlayerPublicSchema.buildCurrentPlayerAttributes({
					userId = 7,
					displayName = "Bob",
					isReady = true,
				})
				expect(attributes[Attributes.DIAMONDS]).toBe(0)
				expect(attributes[Attributes.IS_ADMIN]).toBe(false)
				expect(attributes[Attributes.ACTIVE_CLASS_KIND]).toBe(0)
				expect(attributes[Attributes.CLASS_RECORDS]).toBe("")
				expect(attributes[Attributes.DAILY_REWARD_LAST_CLAIMED_DAY]).toBe(0)
				expect(attributes[Attributes.KEYS]).toBe(0)
				expect(GachaRules.decodeProgress(attributes[Attributes.CLASS_PROGRESS])).toEqual({})
			end
		)
	end
)
