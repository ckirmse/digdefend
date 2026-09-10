-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local PlayerSaveSchema = require(game:GetService("ReplicatedStorage").Shared.PlayerSaveSchema)

local DEFAULTS = { startingCash = 0 }

local function makeValidSave()
	return {
		cash = 250,
		ownedUnlocks = { Pistol = true, Turret = true },
		loadout = { WEAPON = "Pistol", POST = "Turret" },
		completions = { ["DEADMANS_CANYON/NORMAL"] = true },
		dailyReward = { lastClaimedDay = 3, nextClaimTime = 1700000000 },
		sessionMeta = { creationTime = 1690000000, sessions = 4, totalPlaySec = 3600, saveTime = 1700000000 },
	}
end

describe(
	"PlayerSaveSchema.getDefault",
	function()
		it(
			"starts a new player with the configured cash and nothing else",
			function()
				local data = PlayerSaveSchema.getDefault({ startingCash = 50 })
				expect(data.cash).toBe(50)
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
			"repairs corrupt cash",
			function()
				for _, badCash in { -5, 1.5, "100", nil, 0 / 0 } do
					local save = makeValidSave()
					save.cash = badCash
					local validated, repairs = PlayerSaveSchema.validate(save, DEFAULTS)
					expect(validated.cash).toBe(0)
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
				local validated, repairs = PlayerSaveSchema.validate({ cash = 10 }, DEFAULTS)
				expect(validated.cash).toBe(10)
				expect(validated.ownedUnlocks).toEqual({})
				expect(validated.loadout).toEqual({})
				expect(validated.completions).toEqual({})
				expect(validated.sessionMeta.sessions).toBe(0)
				expect(#repairs).toBe(5)
			end
		)
	end
)
