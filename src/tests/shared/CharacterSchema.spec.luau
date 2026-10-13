-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local CharacterSchema = require(game:GetService("ReplicatedStorage").Shared.CharacterSchema)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

local DEFAULTS = {
	defaultKindByGearSlot = {
		[Enums.GearSlot.WEAPON] = Enums.WeaponKind.RIFLE,
		[Enums.GearSlot.POST] = Enums.PostWeaponKind.MACHINE_GUN,
		[Enums.GearSlot.TOWER_1] = Enums.TowerKind.SENTRY_GUN,
		[Enums.GearSlot.TOWER_2] = Enums.TowerKind.FLAMETHROWER,
	},
	minStars = 1,
	maxStars = 5,
	skillSlotUnlockNights = { 0, 15, 50 },
	validSkillIds = { GOLD_DIGGER = true, DEAD_EYE = true },
	maxNameLength = 20,
	defaultNamePrefix = "Character ",
	defaultCosmetics = { HELMET = "HARD_HAT" },
}

local function makeValidCharacter()
	return {
		id = "abc",
		name = "Digger Dan",
		nightsSurvived = 16,
		gear = {
			WEAPON = { kind = "RIFLE", stars = 3 },
			POST = { kind = "ROCKET_LAUNCHER", stars = 1 },
			TOWER_1 = { kind = "FLAMETHROWER", stars = 5 },
			TOWER_2 = { kind = "TESLA_COIL", stars = 2 },
		},
		skills = {
			["1"] = { skillId = "GOLD_DIGGER", rarity = Enums.Rarity.COMMON },
			["2"] = { skillId = "DEAD_EYE", rarity = Enums.Rarity.RARE },
		},
		cosmetics = { HELMET = "lamp_helmet" },
	}
end

local function validate(record)
	local repairs = {}
	local validated = CharacterSchema.validate(record, DEFAULTS, "Character 1", "c.", repairs)
	return validated, repairs
end

describe(
	"CharacterSchema.getDefault",
	function()
		it(
			"starts a character empty at 1 star with the default kinds in every gear slot",
			function()
				local record = CharacterSchema.getDefault(DEFAULTS, "id1", CharacterSchema.makeDefaultName(DEFAULTS, 2))
				expect(record.id).toBe("id1")
				expect(record.name).toBe("Character 2")
				expect(record.nightsSurvived).toBe(0)
				expect(record.gear).toEqual({
					WEAPON = { kind = "RIFLE", stars = 1 },
					POST = { kind = "MACHINE_GUN", stars = 1 },
					TOWER_1 = { kind = "SENTRY_GUN", stars = 1 },
					TOWER_2 = { kind = "FLAMETHROWER", stars = 1 },
				})
				expect(record.skills).toEqual({})
				expect(record.cosmetics).toEqual({ HELMET = "HARD_HAT" })
			end
		)

		it(
			"passes its own default through validate untouched",
			function()
				local record = CharacterSchema.getDefault(DEFAULTS, "id1", "Character 1")
				local validated, repairs = validate(record)
				expect(validated).toBe(record)
				expect(repairs).toEqual({})
			end
		)
	end
)

describe(
	"CharacterSchema.openSkillSlots",
	function()
		it(
			"opens slots as the thresholds are reached, in order",
			function()
				expect(CharacterSchema.openSkillSlots(0, { 0, 15, 50 })).toBe(1)
				expect(CharacterSchema.openSkillSlots(14, { 0, 15, 50 })).toBe(1)
				expect(CharacterSchema.openSkillSlots(15, { 0, 15, 50 })).toBe(2)
				expect(CharacterSchema.openSkillSlots(49, { 0, 15, 50 })).toBe(2)
				expect(CharacterSchema.openSkillSlots(50, { 0, 15, 50 })).toBe(3)
				expect(CharacterSchema.openSkillSlots(999, { 0, 15, 50 })).toBe(3)
			end
		)
	end
)

describe(
	"CharacterSchema.validate",
	function()
		it(
			"passes a valid record through untouched",
			function()
				local record = makeValidCharacter()
				local validated, repairs = validate(record)
				expect(validated).toBe(record)
				expect(repairs).toEqual({})
				expect(validated).toEqual(makeValidCharacter())
			end
		)

		it(
			"drops a record that is not a table or has no id",
			function()
				expect((validate("junk"))).toBeNil()
				expect((validate({ name = "x" }))).toBeNil()
				expect((validate({ id = "" }))).toBeNil()
				expect((validate({ id = 7 }))).toBeNil()
			end
		)

		it(
			"resets a bad, empty, or over-long name to the fallback",
			function()
				for _, badName in { "", 5, nil, string.rep("x", 21) } do
					local record = makeValidCharacter()
					record.name = badName
					local validated, repairs = validate(record)
					expect(validated.name).toBe("Character 1")
					expect(#repairs).toBe(1)
				end
			end
		)

		it(
			"resets corrupt nights survived to zero",
			function()
				for _, bad in { -1, 2.5, "9", nil } do
					local record = makeValidCharacter()
					record.nightsSurvived = bad
					local validated = validate(record)
					expect(validated.nightsSurvived).toBe(0)
				end
			end
		)

		it(
			"resets an unknown kind name to the slot's default kind",
			function()
				local record = makeValidCharacter()
				record.gear.WEAPON.kind = "LASER"
				record.gear.POST.kind = 2
				record.gear.TOWER_1.kind = nil
				record.gear.TOWER_2.kind = "RIFLE"
				local validated, repairs = validate(record)
				expect(validated.gear.WEAPON.kind).toBe("RIFLE")
				expect(validated.gear.POST.kind).toBe("MACHINE_GUN")
				expect(validated.gear.TOWER_1.kind).toBe("SENTRY_GUN")
				expect(validated.gear.TOWER_2.kind).toBe("FLAMETHROWER")
				expect(#repairs).toBe(4)
			end
		)

		it(
			"resets stars outside 1 to 5 to 1",
			function()
				local record = makeValidCharacter()
				record.gear.WEAPON.stars = 0
				record.gear.POST.stars = 6
				record.gear.TOWER_1.stars = 2.5
				local validated, repairs = validate(record)
				expect(validated.gear.WEAPON.stars).toBe(1)
				expect(validated.gear.POST.stars).toBe(1)
				expect(validated.gear.TOWER_1.stars).toBe(1)
				expect(validated.gear.TOWER_2.stars).toBe(2)
				expect(#repairs).toBe(3)
			end
		)

		it(
			"refills a missing gear row, drops an unknown slot, and drops extra row fields",
			function()
				local record = makeValidCharacter()
				record.gear.TOWER_2 = nil
				record.gear.HAT = { kind = "RIFLE", stars = 1 }
				record.gear.WEAPON.level = 4
				local validated, repairs = validate(record)
				expect(validated.gear.TOWER_2).toEqual({ kind = "FLAMETHROWER", stars = 1 })
				expect(validated.gear.HAT).toBeNil()
				expect(validated.gear.WEAPON).toEqual({ kind = "RIFLE", stars = 3 })
				expect(#repairs).toBe(3)

				local missing = makeValidCharacter()
				missing.gear = "none"
				local refilled = validate(missing)
				expect(refilled.gear.TOWER_1.kind).toBe("SENTRY_GUN")
			end
		)

		it(
			"drops skills in unknown slots, with unknown ids, or with a bad rarity",
			function()
				local record = makeValidCharacter()
				record.skills = {
					["1"] = { skillId = "GOLD_DIGGER", rarity = Enums.Rarity.EPIC },
					["4"] = { skillId = "GOLD_DIGGER", rarity = Enums.Rarity.COMMON },
					["2"] = { skillId = "NOPE", rarity = Enums.Rarity.COMMON },
					["3"] = { skillId = "DEAD_EYE", rarity = 99 },
					[1] = { skillId = "DEAD_EYE", rarity = Enums.Rarity.COMMON },
				}
				local validated, repairs = validate(record)
				expect(validated.skills).toEqual({
					["1"] = { skillId = "GOLD_DIGGER", rarity = Enums.Rarity.EPIC },
				})
				expect(#repairs).toBe(4)
			end
		)

		it(
			"drops extra fields on a skill",
			function()
				local record = makeValidCharacter()
				record.skills["1"].level = 3
				local validated, repairs = validate(record)
				expect(validated.skills["1"]).toEqual({ skillId = "GOLD_DIGGER", rarity = Enums.Rarity.COMMON })
				expect(#repairs).toBe(1)
			end
		)

		it(
			"keeps only cosmetics on real slots with a skin id",
			function()
				local record = makeValidCharacter()
				record.cosmetics = { HELMET = "lamp", HAT = "x", JET_PACK = "", BACKPACK = 4 }
				local bare = makeValidCharacter()
				bare.cosmetics = { JET_PACK = "chrome" }
				expect(validate(bare).cosmetics).toEqual({ JET_PACK = "chrome", HELMET = "HARD_HAT" })
				local own = makeValidCharacter()
				own.cosmetics = { HELMET = CharacterSchema.OWN_HAT_ID }
				expect(validate(own).cosmetics).toEqual({ HELMET = CharacterSchema.OWN_HAT_ID })
				local validated, repairs = validate(record)
				expect(validated.cosmetics).toEqual({ HELMET = "lamp" })
				expect(#repairs).toBe(3)
			end
		)

		it(
			"resets missing tables and drops unknown fields",
			function()
				local record = makeValidCharacter()
				record.skills = nil
				record.cosmetics = "none"
				record.level = 7
				record.xp = 100
				local validated, repairs = validate(record)
				expect(validated.skills).toEqual({})
				expect(validated.cosmetics).toEqual({ HELMET = "HARD_HAT" })
				expect(validated.level).toBeNil()
				expect(validated.xp).toBeNil()
				expect(#repairs).toBe(4)
			end
		)
	end
)

describe(
	"CharacterSchema.getGear",
	function()
		it(
			"resolves each gear slot to its enum value and stars",
			function()
				local record = makeValidCharacter()
				local weaponKind, weaponStars = CharacterSchema.getGear(record, Enums.GearSlot.WEAPON)
				expect(weaponKind).toBe(Enums.WeaponKind.RIFLE)
				expect(weaponStars).toBe(3)
				local postKind = CharacterSchema.getGear(record, Enums.GearSlot.POST)
				expect(postKind).toBe(Enums.PostWeaponKind.ROCKET_LAUNCHER)
				local tower1Kind, tower1Stars = CharacterSchema.getGear(record, Enums.GearSlot.TOWER_1)
				expect(tower1Kind).toBe(Enums.TowerKind.FLAMETHROWER)
				expect(tower1Stars).toBe(5)
				local tower2Kind = CharacterSchema.getGear(record, Enums.GearSlot.TOWER_2)
				expect(tower2Kind).toBe(Enums.TowerKind.TESLA_COIL)
				local noKind, noStars = CharacterSchema.getGear(record, 99)
				expect(noKind).toBeNil()
				expect(noStars).toBe(0)
			end
		)

		it(
			"knows the kind enum behind every slot",
			function()
				expect(CharacterSchema.getGearEnum(Enums.GearSlot.WEAPON)).toBe(Enums.WeaponKind)
				expect(CharacterSchema.getGearEnum(Enums.GearSlot.TOWER_2)).toBe(Enums.TowerKind)
				expect(CharacterSchema.getGearEnum(99)).toBeNil()
			end
		)
	end
)

describe(
	"CharacterSchema skill and cosmetic codecs",
	function()
		it(
			"round-trips skills with an empty row per unfilled slot",
			function()
				local record = makeValidCharacter()
				local encoded = CharacterSchema.encodeSkills(record.skills, 3)
				expect(CharacterSchema.decodeSkills(encoded)).toEqual(record.skills)
				expect(CharacterSchema.decodeSkills("")).toEqual({})
				expect(CharacterSchema.decodeSkills("not json")).toEqual({})
				expect(CharacterSchema.decodeSkills(nil)).toEqual({})
			end
		)

		it(
			"round-trips cosmetics",
			function()
				local cosmetics = { HELMET = "lamp", WEAPON = "gold" }
				expect(CharacterSchema.decodeCosmetics(CharacterSchema.encodeCosmetics(cosmetics))).toEqual(cosmetics)
				expect(CharacterSchema.decodeCosmetics("")).toEqual({})
				expect(CharacterSchema.decodeCosmetics(7)).toEqual({})
			end
		)
	end
)
