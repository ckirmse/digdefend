-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Attributes = require(game:GetService("ReplicatedStorage").Shared.Attributes)
local CharacterSchema = require(game:GetService("ReplicatedStorage").Shared.CharacterSchema)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local PlayerPublicSchema = require(game:GetService("ReplicatedStorage").Shared.PlayerPublicSchema)

local UNLOCK_NIGHTS = { 0, 15, 50 }

local function makeCharacter()
	return {
		id = "char-1",
		name = "Digger Dan",
		nightsSurvived = 20,
		gear = {
			WEAPON = { kind = "RIFLE", stars = 2 },
			POST = { kind = "ROCKET_LAUNCHER", stars = 4 },
			TOWER_1 = { kind = "TESLA_COIL", stars = 1 },
			TOWER_2 = { kind = "SNIPER_TOWER", stars = 3 },
		},
		skills = { ["1"] = { skillId = "GOLD_DIGGER", rarity = Enums.SkillRarity.RARE } },
		cosmetics = { HELMET = "lamp" },
	}
end

local function makeSnapshot()
	return {
		userId = 123,
		displayName = "Ada",
		isReady = true,
		isAdmin = true,
		diamonds = 4321,
		activeCharacter = makeCharacter(),
		skillSlotUnlockNights = UNLOCK_NIGHTS,
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
				expect(attributes[Attributes.CHARACTER_WEAPON_KIND]).toBeNil()
			end
		)
	end
)

describe(
	"PlayerPublicSchema.buildCharacterAttributes",
	function()
		it(
			"maps a character to enum values, the open slot count, and the codecs",
			function()
				local attributes = PlayerPublicSchema.buildCharacterAttributes(makeCharacter(), UNLOCK_NIGHTS)
				expect(attributes[Attributes.CHARACTER_ID]).toBe("char-1")
				expect(attributes[Attributes.CHARACTER_NAME]).toBe("Digger Dan")
				expect(attributes[Attributes.CHARACTER_NIGHTS_SURVIVED]).toBe(20)
				expect(attributes[Attributes.CHARACTER_WEAPON_KIND]).toBe(Enums.WeaponKind.RIFLE)
				expect(attributes[Attributes.CHARACTER_WEAPON_STARS]).toBe(2)
				expect(attributes[Attributes.CHARACTER_POST_KIND]).toBe(Enums.PostWeaponKind.ROCKET_LAUNCHER)
				expect(attributes[Attributes.CHARACTER_POST_STARS]).toBe(4)
				expect(attributes[Attributes.CHARACTER_TOWER_1_KIND]).toBe(Enums.TowerKind.TESLA_COIL)
				expect(attributes[Attributes.CHARACTER_TOWER_1_STARS]).toBe(1)
				expect(attributes[Attributes.CHARACTER_TOWER_2_KIND]).toBe(Enums.TowerKind.SNIPER_TOWER)
				expect(attributes[Attributes.CHARACTER_TOWER_2_STARS]).toBe(3)
				expect(attributes[Attributes.CHARACTER_SKILL_SLOTS_OPEN]).toBe(2)
				expect(CharacterSchema.decodeSkills(attributes[Attributes.CHARACTER_SKILLS])).toEqual(makeCharacter().skills)
				expect(CharacterSchema.decodeCosmetics(attributes[Attributes.CHARACTER_COSMETICS])).toEqual({ HELMET = "lamp" })
			end
		)

		it(
			"writes blanks for no character so stale values are overwritten",
			function()
				local attributes = PlayerPublicSchema.buildCharacterAttributes(nil, UNLOCK_NIGHTS)
				expect(attributes[Attributes.CHARACTER_ID]).toBe("")
				expect(attributes[Attributes.CHARACTER_WEAPON_KIND]).toBe(0)
				expect(attributes[Attributes.CHARACTER_SKILL_SLOTS_OPEN]).toBe(0)
				expect(attributes[Attributes.CHARACTER_SKILLS]).toBe("")
				expect(attributes[Attributes.CHARACTER_TOWER_2_STARS]).toBe(0)
				local filled = PlayerPublicSchema.buildCharacterAttributes(makeCharacter(), UNLOCK_NIGHTS)
				for name in filled do
					expect(attributes[name]).never.toBeNil()
				end
			end
		)
	end
)

describe(
	"PlayerPublicSchema.getGearAttributes",
	function()
		it(
			"names a kind and a stars attribute for every gear slot",
			function()
				for _, gearSlot in Enums.getAllValues(Enums.GearSlot) do
					local kindAttribute, starsAttribute = PlayerPublicSchema.getGearAttributes(gearSlot)
					expect(typeof(kindAttribute)).toBe("string")
					expect(typeof(starsAttribute)).toBe("string")
				end
				expect((PlayerPublicSchema.getGearAttributes(99))).toBeNil()
			end
		)
	end
)

describe(
	"PlayerPublicSchema.buildCurrentPlayerAttributes",
	function()
		it(
			"maps private fields and the active character",
			function()
				local attributes = PlayerPublicSchema.buildCurrentPlayerAttributes(makeSnapshot())
				expect(attributes[Attributes.USER_ID]).toBe(123)
				expect(attributes[Attributes.DIAMONDS]).toBe(4321)
				expect(attributes[Attributes.IS_ADMIN]).toBe(true)
				expect(attributes[Attributes.CHARACTER_ID]).toBe("char-1")
				expect(attributes[Attributes.CHARACTER_TOWER_2_KIND]).toBe(Enums.TowerKind.SNIPER_TOWER)
				expect(attributes[Attributes.DAILY_REWARD_LAST_CLAIMED_DAY]).toBe(3)
				expect(attributes[Attributes.DAILY_REWARD_NEXT_CLAIM_TIME]).toBe(1700000000)
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
				expect(attributes[Attributes.CHARACTER_ID]).toBe("")
				expect(attributes[Attributes.DAILY_REWARD_LAST_CLAIMED_DAY]).toBe(0)
			end
		)
	end
)
