-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local PlayerSaveSchema = require(game:GetService("ReplicatedStorage").Shared.PlayerSaveSchema)

local nextId = 0
local function generateId()
	nextId += 1
	return "id" .. nextId
end

local DEFAULTS = {
	startingDiamonds = 0,
	character = {
		defaultClassKind = Enums.ClassKind.RECRUIT,
		defaultKindByGearSlot = {
			[Enums.GearSlot.WEAPON] = Enums.WeaponKind.RIFLE,
			[Enums.GearSlot.POST] = Enums.PostWeaponKind.MACHINE_GUN,
			[Enums.GearSlot.TOWER_1] = Enums.TowerKind.SENTRY_GUN,
			[Enums.GearSlot.TOWER_2] = Enums.TowerKind.FLAMETHROWER,
		},
		minStars = 1,
		maxStars = 5,
		skillSlotUnlockNights = { 0, 15, 50 },
		validSkillIds = { GOLD_DIGGER = true },
		maxNameLength = 20,
		defaultNamePrefix = "Character ",
		defaultCosmetics = { HELMET = "HARD_HAT" },
	},
	maxCharacters = 3,
	generateId = generateId,
}

local function makeCharacter(id, name)
	return {
		id = id,
		name = name,
		classKind = "RECRUIT",
		nightsSurvived = 4,
		gear = {
			WEAPON = { kind = "RIFLE", stars = 2 },
			POST = { kind = "MACHINE_GUN", stars = 1 },
			TOWER_1 = { kind = "SENTRY_GUN", stars = 1 },
			TOWER_2 = { kind = "FLAMETHROWER", stars = 1 },
		},
		skills = { ["1"] = { skillId = "GOLD_DIGGER", rarity = Enums.Rarity.COMMON } },
		cosmetics = { HELMET = "HARD_HAT" },
	}
end

local function makeValidSave()
	return {
		diamonds = 250,
		characters = { makeCharacter("a", "Ada"), makeCharacter("b", "Bob") },
		activeCharacterId = "b",
		completions = { ["DEADMANS_CANYON/NORMAL"] = true },
		dailyReward = { lastClaimedDay = 3, nextClaimTime = 1700000000 },
		sessionMeta = { creationTime = 1690000000, sessions = 4, totalPlaySec = 3600, saveTime = 1700000000 },
		processedPurchaseIds = { "purchase-1", "purchase-2" },
		reviveCredits = { SELF = 1, FRIEND = 0, TEAM = 2 },
	}
end

describe(
	"PlayerSaveSchema.getDefault",
	function()
		it(
			"starts a new player with the configured diamonds and one empty character",
			function()
				local data = PlayerSaveSchema.getDefault({
					startingDiamonds = 50,
					character = DEFAULTS.character,
					maxCharacters = 3,
					generateId = function()
						return "fresh"
					end,
				})
				expect(data.diamonds).toBe(50)
				expect(#data.characters).toBe(1)
				expect(data.characters[1].id).toBe("fresh")
				expect(data.characters[1].name).toBe("Character 1")
				expect(data.characters[1].nightsSurvived).toBe(0)
				expect(data.characters[1].classKind).toBe("RECRUIT")
				expect(data.activeCharacterId).toBe("fresh")
				expect(data.completions).toEqual({})
				expect(data.dailyReward).toEqual({ lastClaimedDay = 0, nextClaimTime = 0 })
				expect(data.sessionMeta.sessions).toBe(0)
			end
		)

		it(
			"returns a fresh table each call",
			function()
				expect(PlayerSaveSchema.getDefault(DEFAULTS)).never.toBe(PlayerSaveSchema.getDefault(DEFAULTS))
			end
		)
	end
)

describe(
	"PlayerSaveSchema.validate",
	function()
		it(
			"passes a valid save through untouched with no repairs",
			function()
				local save = makeValidSave()
				local validated, repairs = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(validated).toBe(save)
				expect(repairs).toEqual({})
				expect(validated).toEqual(makeValidSave())
			end
		)

		it(
			"replaces a non-table save with defaults",
			function()
				local validated, repairs = PlayerSaveSchema.validate("garbage", DEFAULTS)
				expect(validated.diamonds).toBe(0)
				expect(#validated.characters).toBe(1)
				expect(#repairs).toBe(1)
			end
		)

		it(
			"repairs corrupt diamonds",
			function()
				for _, badDiamonds in { -5, 1.5, "100", nil, 0 / 0 } do
					local save = makeValidSave()
					save.diamonds = badDiamonds
					local validated, repairs = PlayerSaveSchema.validate(save, DEFAULTS)
					expect(validated.diamonds).toBe(0)
					expect(#repairs).toBe(1)
				end
			end
		)

		it(
			"drops characters that cannot be repaired, duplicates, and non-list entries",
			function()
				local save = makeValidSave()
				save.characters = {
					makeCharacter("a", "Ada"),
					"junk",
					makeCharacter("a", "Twin"),
					makeCharacter("c", "Cid"),
					extra = makeCharacter("d", "Dee"),
				}
				save.activeCharacterId = "c"
				local validated, repairs = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(#validated.characters).toBe(2)
				expect(validated.characters[1].id).toBe("a")
				expect(validated.characters[2].id).toBe("c")
				expect(validated.activeCharacterId).toBe("c")
				expect(#repairs).toBe(3)
			end
		)

		it(
			"names a repaired character for its kept position",
			function()
				local save = makeValidSave()
				save.characters = { "junk", makeCharacter("z", "") }
				local validated = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(validated.characters[1].name).toBe("Character 1")
			end
		)

		it(
			"trims characters past the cap and keeps the first ones",
			function()
				local save = makeValidSave()
				save.characters = { makeCharacter("a", "A"), makeCharacter("b", "B"), makeCharacter("c", "C"), makeCharacter("d", "D") }
				save.activeCharacterId = "d"
				local validated, repairs = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(#validated.characters).toBe(3)
				expect(validated.characters[3].id).toBe("c")
				expect(validated.activeCharacterId).toBe("a")
				expect(#repairs).toBe(2)
			end
		)

		it(
			"never leaves a player without a character",
			function()
				local save = makeValidSave()
				save.characters = {}
				local validated, repairs = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(#validated.characters).toBe(1)
				expect(validated.characters[1].nightsSurvived).toBe(0)
				expect(validated.activeCharacterId).toBe(validated.characters[1].id)
				expect(#repairs).toBe(2)

				local missing = makeValidSave()
				missing.characters = nil
				local refilled = PlayerSaveSchema.validate(missing, DEFAULTS)
				expect(#refilled.characters).toBe(1)
			end
		)

		it(
			"points a stale active id at the first character",
			function()
				for _, badId in { "nobody", 7, nil } do
					local save = makeValidSave()
					save.activeCharacterId = badId
					local validated, repairs = PlayerSaveSchema.validate(save, DEFAULTS)
					expect(validated.activeCharacterId).toBe("a")
					expect(#repairs).toBe(1)
				end
			end
		)

		it(
			"drops completion keys that do not name a real map and difficulty",
			function()
				local save = makeValidSave()
				save.completions = {
					["DEADMANS_CANYON/NORMAL"] = true,
					["FROSTBITE_PASS/NIGHTMARE"] = true,
					["MOON_BASE/NORMAL"] = true,
					["DEADMANS_CANYON/EASY"] = true,
					["DEADMANS_CANYON/HARD"] = false,
					["junk"] = true,
				}
				local validated = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(validated.completions).toEqual({
					["DEADMANS_CANYON/NORMAL"] = true,
					["FROSTBITE_PASS/NIGHTMARE"] = true,
				})
			end
		)

		it(
			"resets missing sub-tables and repairs their fields individually",
			function()
				local save = makeValidSave()
				save.dailyReward = nil
				save.sessionMeta.sessions = -1
				save.sessionMeta.totalPlaySec = "lots"
				local validated = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(validated.dailyReward).toEqual({ lastClaimedDay = 0, nextClaimTime = 0 })
				expect(validated.sessionMeta.sessions).toBe(0)
				expect(validated.sessionMeta.totalPlaySec).toBe(0)
				expect(validated.sessionMeta.creationTime).toBe(1690000000)
			end
		)

		it(
			"drops unknown top-level fields, the pre-M55 loadout among them",
			function()
				local save = makeValidSave()
				save.ownedUnlocks = { RIFLE = true }
				save.loadout = { WEAPON = "RIFLE" }
				local validated, repairs = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(validated.ownedUnlocks).toBeNil()
				expect(validated.loadout).toBeNil()
				expect(#repairs).toBe(2)
			end
		)

		it(
			"fills a partially missing save with defaults",
			function()
				local validated, repairs = PlayerSaveSchema.validate({ diamonds = 10 }, DEFAULTS)
				expect(validated.diamonds).toBe(10)
				expect(#validated.characters).toBe(1)
				expect(validated.activeCharacterId).toBe(validated.characters[1].id)
				expect(validated.completions).toEqual({})
				expect(validated.sessionMeta.sessions).toBe(0)
				expect(validated.processedPurchaseIds).toEqual({})
				expect(validated.reviveCredits).toEqual({ SELF = 0, FRIEND = 0, TEAM = 0 })
				expect(#repairs).toBe(7)
			end
		)
		it(
			"keeps good purchase ids in order, drops bad ones, and trims to the newest",
			function()
				local data = makeValidSave()
				data.processedPurchaseIds = { "a", 7 :: any, "", "b" }
				local validated, repairs = PlayerSaveSchema.validate(data, DEFAULTS)
				expect(validated.processedPurchaseIds).toEqual({ "a", "b" })
				expect(#repairs).toBe(1)

				local long = makeValidSave()
				long.processedPurchaseIds = {}
				for index = 1, PlayerSaveSchema.MAX_PROCESSED_PURCHASE_IDS + 3 do
					table.insert(long.processedPurchaseIds, "id" .. index)
				end
				local trimmed = PlayerSaveSchema.validate(long, DEFAULTS)
				expect(#trimmed.processedPurchaseIds).toBe(PlayerSaveSchema.MAX_PROCESSED_PURCHASE_IDS)
				expect(trimmed.processedPurchaseIds[1]).toBe("id4")
			end
		)
		it(
			"repairs revive credits: unknown kinds dropped, bad counts zeroed, missing kinds filled quietly",
			function()
				local data = makeValidSave()
				data.reviveCredits = { SELF = 2, FRIEND = -1, BOGUS = 5 } :: any
				local validated, repairs = PlayerSaveSchema.validate(data, DEFAULTS)
				expect(validated.reviveCredits).toEqual({ SELF = 2, FRIEND = 0, TEAM = 0 })
				expect(#repairs).toBe(2)
			end
		)
	end
)

describe(
	"PlayerSaveSchema cash migration",
	function()
		it(
			"carries an older save's cash across as diamonds, once",
			function()
				local validated, repairs = PlayerSaveSchema.validate({ cash = 120 }, DEFAULTS)
				expect(validated.diamonds).toBe(120)
				expect((validated :: any).cash).toBeNil()
				expect(table.find(repairs, "cash migrated to diamonds")).never.toBeNil()
			end
		)
		it(
			"adds the cash onto a reconciled save's starting diamonds",
			function()
				-- GameController reconciles the profile against the defaults before
				-- validating, so an old save arrives with diamonds already present
				local validated = PlayerSaveSchema.validate({ diamonds = 0, cash = 120 }, DEFAULTS)
				expect(validated.diamonds).toBe(120)
				local bothValidated = PlayerSaveSchema.validate({ diamonds = 7, cash = 120 }, DEFAULTS)
				expect(bothValidated.diamonds).toBe(127)
			end
		)
		it(
			"leaves a save with no cash alone",
			function()
				local validated, repairs = PlayerSaveSchema.validate({ diamonds = 7 }, DEFAULTS)
				expect(validated.diamonds).toBe(7)
				expect(table.find(repairs, "cash migrated to diamonds")).toBeNil()
			end
		)
	end
)
