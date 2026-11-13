-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local BadgeRules = require(game:GetService("ReplicatedStorage").Shared.BadgeRules)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

local Badge = Enums.BadgeKind

local RULES = {
	SPEED_RUN_MAX_DAY = 10,
	FULL_CREW_SIZE = 6,
	QUIET_WEEK_NIGHTS = 7,
	ONE_MAN_ARMY_KILLS = 100,
	COLLECTOR_CLASSES = 8,
	LUCKY_7_DAY = 7,
}

local function buildDefinitions()
	local definitions = {}
	for _, kind in Enums.getAllValues(Badge) do
		definitions[kind] = { BADGE_ID = 0, DIAMONDS = 5, STARS = 1, DESCRIPTION = "Do the thing." }
	end
	definitions[Badge.FIRST_SHIFT].NIGHT = 1
	definitions[Badge.NIGHT_5].NIGHT = 5
	definitions[Badge.ROCK_BREAKER].COUNTER = Enums.BadgeCounter.BLOCKS_BROKEN
	definitions[Badge.ROCK_BREAKER].THRESHOLD = 1000
	definitions[Badge.DEEP_MINER].COUNTER = Enums.BadgeCounter.BLOCKS_BROKEN
	definitions[Badge.DEEP_MINER].THRESHOLD = 10000
	definitions[Badge.EXTERMINATOR].COUNTER = Enums.BadgeCounter.MONSTERS_KILLED
	definitions[Badge.EXTERMINATOR].THRESHOLD = 500
	return definitions
end

local function buildSummary()
	return {
		difficulty = Enums.Difficulty.NORMAL,
		crewSize = 3,
		day = 14,
		hasTakenDamage = true,
		isRefineryDamaged = true,
	}
end

describe(
	"BadgeRules.validate",
	function()
		it(
			"accepts a table with an entry for every badge",
			function()
				expect(#BadgeRules.validate(buildDefinitions(), RULES)).toBe(0)
			end
		)

		it(
			"names a missing badge, a bad amount, and a half-written counter",
			function()
				local definitions = buildDefinitions()
				definitions[Badge.WELCOME] = nil
				definitions[Badge.RESCUED].DIAMONDS = 0
				definitions[Badge.EXTERMINATOR].THRESHOLD = nil
				definitions[Badge.NIGHT_5].NIGHT = 0
				definitions[Badge.LUCKY_7].STARS = 6
				definitions[Badge.VETERAN].DESCRIPTION = ""
				expect(#BadgeRules.validate(definitions, RULES)).toBe(6)
				local rules = table.clone(RULES)
				rules.SPEED_RUN_MAX_DAY = 0
				expect(#BadgeRules.validate(buildDefinitions(), rules)).toBe(1)
			end
		)
	end
)

describe(
	"BadgeRules lifetime and survival badges",
	function()
		it(
			"earns each counter badge once its threshold is reached",
			function()
				local definitions = buildDefinitions()
				local counter = Enums.BadgeCounter.BLOCKS_BROKEN
				expect(BadgeRules.kindsForCounter(definitions, counter, 999)).toEqual({})
				expect(BadgeRules.kindsForCounter(definitions, counter, 1000)).toEqual({ Badge.ROCK_BREAKER })
				expect(BadgeRules.kindsForCounter(definitions, counter, 10000)).toEqual({ Badge.ROCK_BREAKER, Badge.DEEP_MINER })
				-- another counter's value earns nothing here
				expect(BadgeRules.kindsForCounter(definitions, Enums.BadgeCounter.RESCUES, 10000)).toEqual({})
			end
		)

		it(
			"earns every survival badge up to the night survived",
			function()
				local definitions = buildDefinitions()
				expect(BadgeRules.kindsForNight(definitions, 0)).toEqual({})
				expect(BadgeRules.kindsForNight(definitions, 1)).toEqual({ Badge.FIRST_SHIFT })
				expect(BadgeRules.kindsForNight(definitions, 7)).toEqual({ Badge.FIRST_SHIFT, Badge.NIGHT_5 })
			end
		)

		it(
			"counts quiet nights in a row and starts over on damage",
			function()
				expect(BadgeRules.nextQuietStreak(3, false)).toBe(4)
				expect(BadgeRules.nextQuietStreak(6, true)).toBe(0)
			end
		)
	end
)

describe(
	"BadgeRules.kindsForRescue",
	function()
		it(
			"earns only Rescued for a plain win",
			function()
				expect(BadgeRules.kindsForRescue(buildSummary(), RULES)).toEqual({ Badge.RESCUED })
			end
		)

		it(
			"counts a Nightmare win as a Hard one too",
			function()
				local summary = buildSummary()
				summary.difficulty = Enums.Difficulty.HARD
				expect(BadgeRules.kindsForRescue(summary, RULES)).toEqual({ Badge.RESCUED, Badge.HARD_RESCUE })
				summary.difficulty = Enums.Difficulty.NIGHTMARE
				expect(BadgeRules.kindsForRescue(summary, RULES)).toEqual({ Badge.RESCUED, Badge.HARD_RESCUE, Badge.NIGHTMARE_RESCUE })
			end
		)

		it(
			"earns the crew badges by the run's size",
			function()
				local summary = buildSummary()
				summary.crewSize = 6
				expect(BadgeRules.kindsForRescue(summary, RULES)).toEqual({ Badge.RESCUED, Badge.FULL_CREW })
				summary.crewSize = 1
				expect(BadgeRules.kindsForRescue(summary, RULES)).toEqual({ Badge.RESCUED, Badge.LONE_MINER })
			end
		)

		it(
			"earns the condition badges: no damage, by day 10, Refinery untouched",
			function()
				local summary = buildSummary()
				summary.hasTakenDamage = false
				summary.day = 10
				summary.isRefineryDamaged = false
				expect(BadgeRules.kindsForRescue(summary, RULES)).toEqual({ Badge.RESCUED, Badge.NOT_A_SCRATCH, Badge.SPEED_RUN, Badge.UNTOUCHED_REFINERY })
				summary.day = 11
				expect(BadgeRules.kindsForRescue(summary, RULES)).toEqual({ Badge.RESCUED, Badge.NOT_A_SCRATCH, Badge.UNTOUCHED_REFINERY })
			end
		)
	end
)

describe(
	"BadgeRules.kindsForClassProgress",
	function()
		it(
			"earns Class Act for one maxed class and Collector for eight owned",
			function()
				expect(BadgeRules.kindsForClassProgress({ RECRUIT = 0, GUNNER = 2 }, 3, RULES)).toEqual({})
				expect(BadgeRules.kindsForClassProgress({ RECRUIT = 0, GUNNER = 3 }, 3, RULES)).toEqual({ Badge.CLASS_ACT })
				local eight = { A = 0, B = 0, C = 0, D = 0, E = 0, F = 0, G = 0, H = 0 }
				expect(BadgeRules.kindsForClassProgress(eight, 3, RULES)).toEqual({ Badge.COLLECTOR })
				eight.A = 3
				expect(BadgeRules.kindsForClassProgress(eight, 3, RULES)).toEqual({ Badge.CLASS_ACT, Badge.COLLECTOR })
			end
		)
	end
)

describe(
	"BadgeRules.getState",
	function()
		it(
			"is locked until earned, claimable until paid, then claimed",
			function()
				expect(BadgeRules.getState(false, false)).toBe("LOCKED")
				expect(BadgeRules.getState(true, false)).toBe("CLAIMABLE")
				expect(BadgeRules.getState(true, true)).toBe("CLAIMED")
				-- a claimed mark without the badge is never a reward
				expect(BadgeRules.getState(false, true)).toBe("LOCKED")
				expect(BadgeRules.canClaim(true, false)).toBe(true)
				expect(BadgeRules.canClaim(true, true)).toBe(false)
				expect(BadgeRules.canClaim(false, false)).toBe(false)
			end
		)

		it(
			"counts the earned badges still holding their reward",
			function()
				local earned = { [Badge.WELCOME] = true, [Badge.RESCUED] = true, [Badge.LUCKY_7] = true }
				expect(BadgeRules.countClaimable(earned, {})).toBe(3)
				expect(BadgeRules.countClaimable(earned, { [Badge.RESCUED] = true })).toBe(2)
				expect(BadgeRules.countClaimable({}, {})).toBe(0)
			end
		)
	end
)

describe(
	"BadgeRules catalogue",
	function()
		it(
			"publishes every badge in enum order and survives the codec",
			function()
				local definitions = buildDefinitions()
				definitions[Badge.RESCUED].ICON = "rbxassetid://1"
				definitions[Badge.RESCUED].STARS = 2
				local published = BadgeRules.publish(definitions, { [Badge.RESCUED] = "rbxassetid://2", [Badge.WELCOME] = "rbxassetid://3" }, "rbxassetid://9")
				expect(#published).toBe(Enums.getCount(Badge))
				for index = 2, #published do
					expect(published[index].kind > published[index - 1].kind).toBe(true)
				end
				local byKind = {}
				for _, badge in published do
					byKind[badge.kind] = badge
				end
				-- its own ICON first, then the one found for it, then the default
				expect(byKind[Badge.RESCUED].icon).toBe("rbxassetid://1")
				expect(byKind[Badge.RESCUED].stars).toBe(2)
				expect(byKind[Badge.WELCOME].icon).toBe("rbxassetid://3")
				expect(byKind[Badge.LUCKY_7].icon).toBe("rbxassetid://9")
				expect(BadgeRules.decodeCatalogue(BadgeRules.encodeCatalogue(published))).toEqual(published)
			end
		)

		it(
			"sorts the menu's list earned first, then by stars, then by kind",
			function()
				local function badge(kind: number, stars: number)
					return {
						kind = kind,
						diamonds = 5,
						stars = stars,
						description = "x",
						icon = "y",
					}
				end
				local published = { badge(1, 3), badge(2, 1), badge(3, 5), badge(4, 1), badge(5, 2), badge(6, 1) }
				local kinds = {}
				for _, sortedBadge in BadgeRules.sortForMenu(published, { [3] = true, [5] = true, [6] = true }) do
					table.insert(kinds, sortedBadge.kind)
				end
				expect(kinds).toEqual({ 6, 5, 3, 2, 4, 1 })
				-- the list handed in keeps its order
				expect(published[1].kind).toBe(1)
			end
		)

		it(
			"decodes nothing from a malformed catalogue",
			function()
				expect(BadgeRules.decodeCatalogue(nil)).toBeNil()
				expect(BadgeRules.decodeCatalogue("")).toBeNil()
				expect(BadgeRules.decodeCatalogue("not json")).toBeNil()
				expect(BadgeRules.decodeCatalogue('[{"kind":9999,"diamonds":5,"stars":1,"description":"x","icon":"y"}]')).toBeNil()
			end
		)
	end
)

describe(
	"BadgeRules kind sets",
	function()
		it(
			"carries a save's set as enum values and back",
			function()
				local encoded = BadgeRules.encodeKinds({ WELCOME = true, RESCUED = true, NOT_A_BADGE = true })
				expect(BadgeRules.decodeKinds(encoded)).toEqual({ [Badge.WELCOME] = true, [Badge.RESCUED] = true })
				expect(BadgeRules.decodeKinds(BadgeRules.encodeKinds({}))).toEqual({})
				expect(BadgeRules.decodeKinds(nil)).toEqual({})
				expect(BadgeRules.decodeKinds("[1,9999]")).toEqual({ [1] = true })
			end
		)
	end
)
