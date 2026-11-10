-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local PlayerSaveSchema = require(game:GetService("ReplicatedStorage").Shared.PlayerSaveSchema)

local DEFAULTS = {
	startingDiamonds = 0,
	class = {
		maxSkillSlots = 3,
		validSkillIds = { GOLD_DIGGER = true },
	},
	defaultCosmetics = {},
	defaultClassKind = Enums.ClassKind.RECRUIT,
}

local function makeClassRecord()
	return {
		skills = { ["1"] = { skillId = "GOLD_DIGGER", rarity = Enums.Rarity.COMMON } },
	}
end

local function makeValidSave()
	return {
		diamonds = 250,
		classes = { RECRUIT = makeClassRecord(), GUNNER = makeClassRecord() },
		cosmetics = { PICK_AXE = "LAMP" },
		activeClassKind = "GUNNER",
		completions = { ["DEADMANS_CANYON/NORMAL"] = true },
		dailyReward = { lastClaimedDay = 3, nextClaimTime = 1700000000 },
		sessionMeta = { creationTime = 1690000000, sessions = 4, totalPlaySec = 3600, saveTime = 1700000000 },
		processedPurchaseIds = { "purchase-1", "purchase-2" },
		reviveCredits = { SELF = 1, FRIEND = 0, TEAM = 2 },
		classProgress = { RECRUIT = 0, GUNNER = 2 },
		keys = 3,
		ownedCosmetics = { HARD_HAT = true, LAMP = true },
		hasFinishedTutorial = true,
	}
end

describe(
	"PlayerSaveSchema.getDefault",
	function()
		it(
			"starts a new player with the configured diamonds, no class records, and the free class equipped",
			function()
				local data = PlayerSaveSchema.getDefault({
					startingDiamonds = 50,
					class = DEFAULTS.class,
					defaultCosmetics = DEFAULTS.defaultCosmetics,
					defaultClassKind = Enums.ClassKind.RECRUIT,
				})
				expect(data.diamonds).toBe(50)
				expect(data.classes).toEqual({})
				expect(data.cosmetics).toEqual({})
				expect(data.activeClassKind).toBe("RECRUIT")
				expect(data.completions).toEqual({})
				expect(data.dailyReward).toEqual({ lastClaimedDay = 0, nextClaimTime = 0 })
				expect(data.sessionMeta.sessions).toBe(0)
				expect(data.classProgress).toEqual({ RECRUIT = 0 })
				expect(data.keys).toBe(0)
				expect(data.ownedCosmetics).toEqual({})
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
			"repairs the class gacha fields: unknown classes dropped, slots clamped, the free class and default cosmetics kept, bad keys zeroed",
			function()
				local save = makeValidSave()
				save.classProgress = { GUNNER = 9, SNIPER = "two", DRAGON = 1 }
				save.keys = -4
				save.ownedCosmetics = { LAMP = true, [""] = true, GLOVES = false }
				local validated, repairs = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(validated.classProgress).toEqual({ RECRUIT = 0, GUNNER = 3, SNIPER = 0 })
				expect(validated.keys).toBe(0)
				expect(validated.ownedCosmetics).toEqual({ LAMP = true })
				-- the clamp, the reset, the dropped class, the restored Recruit,
				-- the keys, the two dropped cosmetics
				expect(#repairs).toBe(7)
			end
		)

		it(
			"resets the class gacha fields that are not tables",
			function()
				local save = makeValidSave()
				save.classProgress = "none"
				save.ownedCosmetics = 7
				local validated, repairs = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(validated.classProgress).toEqual({ RECRUIT = 0 })
				expect(validated.ownedCosmetics).toEqual({})
				-- the Gunner is no longer owned, so the active class falls back too
				expect(validated.activeClassKind).toBe("RECRUIT")
				expect(#repairs).toBe(3)
			end
		)

		it(
			"repairs the cosmetic loadout and moves a class record's cosmetics onto it",
			function()
				local save = makeValidSave()
				save.cosmetics = { BOGUS = "x" }
				local validated, repairs = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(validated.cosmetics).toEqual({})
				expect(#repairs).toBe(1)

				save = makeValidSave()
				save.classes.GUNNER.cosmetics = { PICK_AXE = "lamp" }
				save.classes.RECRUIT.cosmetics = { PICK_AXE = "other" }
				validated, repairs = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(validated.cosmetics).toEqual({ PICK_AXE = "lamp" })
				expect(validated.classes.GUNNER).toEqual(makeClassRecord())
				expect(validated.classes.RECRUIT).toEqual(makeClassRecord())
				expect(repairs).toEqual({ "class cosmetics migrated to the account loadout" })
			end
		)

		it(
			"replaces a non-table save with defaults",
			function()
				local validated, repairs = PlayerSaveSchema.validate("garbage", DEFAULTS)
				expect(validated.diamonds).toBe(0)
				expect(validated.classes).toEqual({})
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
			"repairs class records: unknown classes dropped, a broken record defaulted, bad skills dropped",
			function()
				local save = makeValidSave()
				save.classes.DRAGON = makeClassRecord()
				save.classes.SNIPER = "junk"
				save.classes.GUNNER.skills["2"] = { skillId = "NOPE", rarity = 1 }
				local validated, repairs = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(validated.classes.DRAGON).toBeNil()
				expect(validated.classes.SNIPER).toEqual({ skills = {} })
				expect(validated.classes.GUNNER.skills["2"]).toBeNil()
				expect(#repairs).toBe(3)
			end
		)

		it(
			"resets a classes field that is not a table and keeps a save with no records",
			function()
				local save = makeValidSave()
				save.classes = 4
				local validated, repairs = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(validated.classes).toEqual({})
				expect(#repairs).toBe(1)
			end
		)

		it(
			"points the active class at the free one when it is unknown or not owned",
			function()
				for _, badKind in { "nobody", 7, nil, "SNIPER" } do
					local save = makeValidSave()
					save.activeClassKind = badKind
					local validated, repairs = PlayerSaveSchema.validate(save, DEFAULTS)
					expect(validated.activeClassKind).toBe("RECRUIT")
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
				expect(validated.classes).toEqual({})
				expect(validated.activeClassKind).toBe("RECRUIT")
				expect(validated.completions).toEqual({})
				expect(validated.sessionMeta.sessions).toBe(0)
				expect(validated.processedPurchaseIds).toEqual({})
				expect(validated.reviveCredits).toEqual({ SELF = 0, FRIEND = 0, TEAM = 0 })
				expect(validated.classProgress).toEqual({ RECRUIT = 0 })
				expect(validated.keys).toBe(0)
				expect(validated.ownedCosmetics).toEqual({})
				expect(validated.cosmetics).toEqual({})
				expect(validated.hasFinishedTutorial).toBe(false)
				expect(#repairs).toBe(12)
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

describe(
	"PlayerSaveSchema characters migration",
	function()
		local function makeOldCharacter(id, className, skillId)
			return {
				id = id,
				name = "Old " .. id,
				classKind = className,
				nightsSurvived = 4,
				gear = {},
				skills = if skillId then { ["1"] = { skillId = skillId, rarity = Enums.Rarity.COMMON } } else {},
				cosmetics = { PICK_AXE = "lamp" },
			}
		end

		it(
			"turns each character into its class's record and the active one into the active class",
			function()
				local save = makeValidSave()
				save.classes = {}
				save.activeClassKind = "RECRUIT"
				save.characters = { makeOldCharacter("a", "RECRUIT", nil), makeOldCharacter("b", "GUNNER", "GOLD_DIGGER") }
				save.activeCharacterId = "b"
				local validated, repairs = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(validated.characters).toBeNil()
				expect(validated.activeCharacterId).toBeNil()
				expect(validated.activeClassKind).toBe("GUNNER")
				expect(validated.classes.GUNNER.skills["1"].skillId).toBe("GOLD_DIGGER")
				expect(validated.cosmetics).toEqual({ PICK_AXE = "lamp" })
				expect(validated.classes.RECRUIT.skills).toEqual({})
				expect(table.find(repairs, "characters migrated to classes")).never.toBeNil()
			end
		)

		it(
			"keeps the first character seen for a class and ignores junk entries",
			function()
				local save = makeValidSave()
				save.classes = {}
				save.characters = { "junk", makeOldCharacter("a", "GUNNER", "GOLD_DIGGER"), makeOldCharacter("b", "GUNNER", nil) }
				save.activeCharacterId = "nobody"
				local validated = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(validated.classes.GUNNER.skills["1"].skillId).toBe("GOLD_DIGGER")
				expect(validated.activeClassKind).toBe("GUNNER")
			end
		)

		it(
			"never overwrites a class record that already exists",
			function()
				local save = makeValidSave()
				save.characters = { makeOldCharacter("a", "GUNNER", nil) }
				save.activeCharacterId = "a"
				local validated = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(validated.classes.GUNNER).toEqual(makeClassRecord())
			end
		)
	end
)
