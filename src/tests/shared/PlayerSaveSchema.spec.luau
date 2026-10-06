-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local PlayerSaveSchema = require(game:GetService("ReplicatedStorage").Shared.PlayerSaveSchema)

local DEFAULTS = { startingDiamonds = 0 }

local function makeValidSave()
	return {
		diamonds = 250,
		ownedUnlocks = { Pistol = true, Turret = true },
		loadout = { WEAPON = "Pistol", POST = "Turret" },
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
			"starts a new player with the configured diamonds and nothing else",
			function()
				local data = PlayerSaveSchema.getDefault({ startingDiamonds = 50 })
				expect(data.diamonds).toBe(50)
				expect(data.ownedUnlocks).toEqual({})
				expect(data.loadout).toEqual({})
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
				expect(validated).toEqual(PlayerSaveSchema.getDefault(DEFAULTS))
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
			"drops corrupt unlock entries and keeps good ones",
			function()
				local save = makeValidSave()
				save.ownedUnlocks = { Pistol = true, Rifle = false, [7] = true, [""] = true }
				save.loadout = {}
				local validated = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(validated.ownedUnlocks).toEqual({ Pistol = true })
			end
		)

		it(
			"drops loadout slots that are unknown, empty, or not owned",
			function()
				local save = makeValidSave()
				save.loadout = {
					WEAPON = "Pistol",
					POST = "NotOwned",
					DEFENSE_1 = "",
					HAT = "Pistol",
					DEFENSE_2 = 5,
				}
				local validated = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(validated.loadout).toEqual({ WEAPON = "Pistol" })
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
			"drops unknown top-level fields",
			function()
				local save = makeValidSave()
				save.xp = 400
				save.level = 7
				local validated, repairs = PlayerSaveSchema.validate(save, DEFAULTS)
				expect(validated.xp).toBeNil()
				expect(validated.level).toBeNil()
				expect(#repairs).toBe(2)
			end
		)

		it(
			"fills a partially missing save with defaults",
			function()
				local validated, repairs = PlayerSaveSchema.validate({ diamonds = 10 }, DEFAULTS)
				expect(validated.diamonds).toBe(10)
				expect(validated.ownedUnlocks).toEqual({})
				expect(validated.loadout).toEqual({})
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
