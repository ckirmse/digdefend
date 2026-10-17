-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local ClassRules = require(game:GetService("ReplicatedStorage").Shared.ClassRules)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

local function makeGunner()
	return {
		KIT = {
			WEAPON = Enums.WeaponKind.RIFLE,
			POST = Enums.PostWeaponKind.MACHINE_GUN,
			TOWERS = { Enums.TowerKind.SENTRY_GUN, Enums.TowerKind.SNIPER_TOWER },
			GADGET = Enums.GadgetKind.AUTO_TURRET,
		},
		MODIFIERS = {
			[Enums.ClassModifier.POST_DAMAGE] = 1.25,
			[Enums.ClassModifier.MINING_POWER] = 0.8,
		},
	}
end

local function everyKindKnown()
	return true
end

describe(
	"ClassRules.modifier",
	function()
		it(
			"reads a set modifier and defaults every other stat to 1.0",
			function()
				local gunner = makeGunner()
				expect(ClassRules.modifier(gunner, Enums.ClassModifier.POST_DAMAGE)).toBe(1.25)
				expect(ClassRules.modifier(gunner, Enums.ClassModifier.MINING_POWER)).toBe(0.8)
				expect(ClassRules.modifier(gunner, Enums.ClassModifier.HANDHELD_DAMAGE)).toBe(1)
			end
		)

		it(
			"is 1.0 with no class at all",
			function()
				expect(ClassRules.modifier(nil, Enums.ClassModifier.POST_DAMAGE)).toBe(1)
			end
		)
	end
)

describe(
	"ClassRules.scaleAmount",
	function()
		it(
			"rounds a scaled amount to the nearest whole number",
			function()
				expect(ClassRules.scaleAmount(30, 0.7)).toBe(21)
				expect(ClassRules.scaleAmount(25, 0.5)).toBe(13)
				expect(ClassRules.scaleAmount(10, 1.3)).toBe(13)
				expect(ClassRules.scaleAmount(7, 1)).toBe(7)
			end
		)
	end
)

describe(
	"ClassRules.kitKind",
	function()
		it(
			"maps every gear slot onto the kit",
			function()
				local gunner = makeGunner()
				expect(ClassRules.kitKind(gunner, Enums.GearSlot.WEAPON)).toBe(Enums.WeaponKind.RIFLE)
				expect(ClassRules.kitKind(gunner, Enums.GearSlot.POST)).toBe(Enums.PostWeaponKind.MACHINE_GUN)
				expect(ClassRules.kitKind(gunner, Enums.GearSlot.TOWER_1)).toBe(Enums.TowerKind.SENTRY_GUN)
				expect(ClassRules.kitKind(gunner, Enums.GearSlot.TOWER_2)).toBe(Enums.TowerKind.SNIPER_TOWER)
			end
		)

		it(
			"has no second tower for a one-tower class and nothing for no class",
			function()
				local recruit = makeGunner()
				recruit.KIT.TOWERS = { Enums.TowerKind.SENTRY_GUN }
				expect(ClassRules.kitKind(recruit, Enums.GearSlot.TOWER_2)).toBeNil()
				expect(ClassRules.kitKind(nil, Enums.GearSlot.WEAPON)).toBeNil()
			end
		)
	end
)

describe(
	"ClassRules.towerKinds",
	function()
		it(
			"lists each tower once in roster order",
			function()
				local gunner = makeGunner()
				expect(ClassRules.towerKinds(gunner)).toEqual({ Enums.TowerKind.SENTRY_GUN, Enums.TowerKind.SNIPER_TOWER })
				gunner.KIT.TOWERS = { Enums.TowerKind.SENTRY_GUN, Enums.TowerKind.SENTRY_GUN }
				expect(ClassRules.towerKinds(gunner)).toEqual({ Enums.TowerKind.SENTRY_GUN })
				expect(ClassRules.towerKinds(nil)).toEqual({})
			end
		)
	end
)

describe(
	"ClassRules.rosterRowProblems",
	function()
		it(
			"accepts a sound row",
			function()
				expect(ClassRules.rosterRowProblems(makeGunner(), everyKindKnown)).toEqual({})
			end
		)

		it(
			"names a kit item with no data behind it",
			function()
				local gunner = makeGunner()
				local problems = ClassRules.rosterRowProblems(
					gunner,
					function(gearSlot, _kind)
						return gearSlot ~= Enums.GearSlot.POST
					end
				)
				expect(problems).toEqual({ "KIT.POST is not a built post weapon" })
			end
		)

		it(
			"names an unknown enum value, a bad tower list, and a bad modifier",
			function()
				local gunner = makeGunner()
				gunner.KIT.WEAPON = 999
				gunner.KIT.TOWERS = {}
				gunner.KIT.GADGET = 999
				gunner.MODIFIERS[999] = 1.5
				gunner.MODIFIERS[Enums.ClassModifier.MOVE_SPEED] = -1
				local problems = ClassRules.rosterRowProblems(gunner, everyKindKnown)
				expect(#problems).toBe(5)
				expect(table.find(problems, "KIT.WEAPON is not a built weapon")).never.toBeNil()
				expect(table.find(problems, "KIT.TOWERS must list one or two towers")).never.toBeNil()
				expect(table.find(problems, "KIT.GADGET is not a gadget")).never.toBeNil()
				expect(table.find(problems, "MODIFIERS has an unknown key 999")).never.toBeNil()
				expect(table.find(problems, "MODIFIERS[" .. tostring(Enums.ClassModifier.MOVE_SPEED) .. "] is not a non-negative number")).never.toBeNil()
			end
		)

		it(
			"stops at a row with no kit",
			function()
				expect(ClassRules.rosterRowProblems(nil, everyKindKnown)).toEqual({ "no KIT" })
				expect(ClassRules.rosterRowProblems({ MODIFIERS = {} }, everyKindKnown)).toEqual({ "no KIT" })
			end
		)
	end
)
