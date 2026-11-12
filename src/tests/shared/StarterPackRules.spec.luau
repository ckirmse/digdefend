-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local StarterPackRules = require(game:GetService("ReplicatedStorage").Shared.StarterPackRules)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

local GUNNER = Enums.ClassKind.GUNNER
local SNIPER = Enums.ClassKind.SNIPER
local RECRUIT = Enums.ClassKind.RECRUIT
local PRIORITY = { GUNNER, SNIPER, RECRUIT }
local MAX_SKILL_SLOTS = 3

local DEFINITION = {
	GAME_PASS_ID = 123,
	VALUE_ROBUX = 499,
	CLASS_PRIORITY = PRIORITY,
	DIAMONDS = 300,
	COSMETIC_ID = "KNOWN_SKIN",
}

local function isKnownClass(classKind: number): boolean
	return table.find(PRIORITY, classKind) ~= nil
end

local function isKnownCosmetic(cosmeticId: string): boolean
	return cosmeticId == "KNOWN_SKIN"
end

describe(
	"StarterPackRules.pickClassKind",
	function()
		it(
			"gives the first class in the priority the player does not own",
			function()
				expect(StarterPackRules.pickClassKind(PRIORITY, { RECRUIT = 0 }, MAX_SKILL_SLOTS)).toBe(GUNNER)
				expect(StarterPackRules.pickClassKind(PRIORITY, { RECRUIT = 0, GUNNER = 0 }, MAX_SKILL_SLOTS)).toBe(SNIPER)
				-- an owned class is skipped even when it is not maxed
				expect(StarterPackRules.pickClassKind(PRIORITY, { RECRUIT = 3, GUNNER = 1 }, MAX_SKILL_SLOTS)).toBe(SNIPER)
			end
		)

		it(
			"with every class owned, gives the first that is not maxed",
			function()
				expect(StarterPackRules.pickClassKind(PRIORITY, { RECRUIT = 0, GUNNER = 1, SNIPER = 0 }, MAX_SKILL_SLOTS)).toBe(GUNNER)
				expect(StarterPackRules.pickClassKind(PRIORITY, { RECRUIT = 0, GUNNER = 3, SNIPER = 2 }, MAX_SKILL_SLOTS)).toBe(SNIPER)
				expect(StarterPackRules.pickClassKind(PRIORITY, { RECRUIT = 2, GUNNER = 3, SNIPER = 3 }, MAX_SKILL_SLOTS)).toBe(RECRUIT)
			end
		)

		it(
			"gives no class when every one is maxed",
			function()
				expect(StarterPackRules.pickClassKind(PRIORITY, { RECRUIT = 3, GUNNER = 3, SNIPER = 3 }, MAX_SKILL_SLOTS)).toBeNil()
			end
		)
	end
)

describe(
	"StarterPackRules definition and offer",
	function()
		it(
			"accepts a well-formed definition",
			function()
				expect(#StarterPackRules.validate(DEFINITION, isKnownClass, isKnownCosmetic)).toBe(0)
			end
		)

		it(
			"names every malformed field",
			function()
				local problems = StarterPackRules.validate(
					{
						GAME_PASS_ID = 0,
						VALUE_ROBUX = 1.5,
						CLASS_PRIORITY = { GUNNER, 99, GUNNER },
						DIAMONDS = -1,
						COSMETIC_ID = "UNKNOWN",
					},
					isKnownClass,
					isKnownCosmetic
				)
				-- three numbers, an unknown class, a repeated class, the cosmetic
				expect(#problems).toBe(6)
				local empty = table.clone(DEFINITION)
				empty.CLASS_PRIORITY = {}
				expect(#StarterPackRules.validate(empty, isKnownClass, isKnownCosmetic)).toBe(1)
			end
		)

		it(
			"builds the offer with no price until Roblox answers",
			function()
				expect(StarterPackRules.buildOffer(DEFINITION, MAX_SKILL_SLOTS, 2, nil).priceRobux).toBe(0)
				expect(StarterPackRules.buildOffer(DEFINITION, MAX_SKILL_SLOTS, 2, 199)).toEqual(
					{
						classPriority = PRIORITY,
						maxSkillSlots = MAX_SKILL_SLOTS,
						keysPerCompleteClass = 2,
						diamonds = 300,
						cosmeticId = "KNOWN_SKIN",
						valueRobux = 499,
						priceRobux = 199,
					}
				)
			end
		)

		it(
			"survives the trip to the client",
			function()
				local offer = StarterPackRules.buildOffer(DEFINITION, MAX_SKILL_SLOTS, 2, 199)
				expect(StarterPackRules.decodeOffer(StarterPackRules.encodeOffer(offer))).toEqual(offer)
				expect(StarterPackRules.decodeOffer("")).toBeNil()
				expect(StarterPackRules.decodeOffer("not json")).toBeNil()
				expect(StarterPackRules.decodeOffer("{}")).toBeNil()
			end
		)
	end
)
