--!strict

-- The launch classes (GDD "Classes", designed 2026-10-15), M64. One entry
-- per Enums.ClassKind: the fixed kit a character of that class brings
-- into a run (KIT: the handheld weapon, the post weapon, one or two
-- towers, the gadget) and its buff and debuff as MODIFIERS, entries in the
-- Enums.ClassModifier table scaled from a default of 1.0 (a key that is
-- absent is 1.0). A buff is a modifier on something shared, never a
-- tuning number on the class's own kit.
--
-- Every weapon and post exists since 2026-10-16. The four new towers and
-- every gadget are not built yet: a tower row points at the nearest built
-- stand-in with the designed tower named beside it, and a gadget is named
-- for the record only, with no tool slot or behaviour yet.
--
-- Modifiers marked "not applied" in Enums.ClassModifier are recorded here
-- so the design is data, and do nothing until their system reads them.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	-- the class every new character is, and the one a save is repaired to
	DEFAULT_CLASS = Enums.ClassKind.RECRUIT,
	BY_KIND = {
		-- free; no roles, no buff, no debuff. The baseline every bought
		-- class must beat on a solo Normal run, and playable forever
		[Enums.ClassKind.RECRUIT] = {
			KIT = {
				WEAPON = Enums.WeaponKind.PISTOL,
				POST = Enums.PostWeaponKind.MACHINE_GUN,
				TOWERS = { Enums.TowerKind.SENTRY_GUN },
				GADGET = Enums.GadgetKind.NONE,
			},
			MODIFIERS = {},
		},
		-- Combat: Balanced / Building: Tower
		[Enums.ClassKind.GUNNER] = {
			KIT = {
				WEAPON = Enums.WeaponKind.RIFLE,
				POST = Enums.PostWeaponKind.MINI_GUN,
				TOWERS = { Enums.TowerKind.SENTRY_GUN, Enums.TowerKind.SNIPER_TOWER },
				GADGET = Enums.GadgetKind.AUTO_TURRET,
			},
			MODIFIERS = {
				[Enums.ClassModifier.POST_DAMAGE] = 1.25,
				[Enums.ClassModifier.MINING_POWER] = 0.8,
			},
		},
		-- Combat: Tank Destroyer / Support
		[Enums.ClassKind.SNIPER] = {
			KIT = {
				WEAPON = Enums.WeaponKind.SNIPER,
				POST = Enums.PostWeaponKind.RAIL_GUN,
				TOWERS = { Enums.TowerKind.SNIPER_TOWER },
				GADGET = Enums.GadgetKind.BINOCULARS,
			},
			MODIFIERS = {
				[Enums.ClassModifier.LARGE_MONSTER_DAMAGE] = 1.5,
				[Enums.ClassModifier.TOWER_BUILD_COST] = 1.3,
			},
		},
		-- Combat: Group Destroyer / Building: Trap
		[Enums.ClassKind.PYRO] = {
			KIT = {
				WEAPON = Enums.WeaponKind.FLAMETHROWER,
				POST = Enums.PostWeaponKind.MORTAR,
				TOWERS = { Enums.TowerKind.FLAMETHROWER },
				GADGET = Enums.GadgetKind.REMOTE_CHARGE,
			},
			MODIFIERS = {
				[Enums.ClassModifier.BURN_DURATION] = 1.5,
				[Enums.ClassModifier.TRAP_COST] = 0.5,
				[Enums.ClassModifier.MINING_POWER] = 0.8,
			},
		},
		-- Combat: Air Defender / Building: Tower
		[Enums.ClassKind.AIR_DEFENSE] = {
			KIT = {
				WEAPON = Enums.WeaponKind.RIFLE,
				POST = Enums.PostWeaponKind.AA_LAUNCHER,
				TOWERS = { Enums.TowerKind.AA_TURRET },
				GADGET = Enums.GadgetKind.GROUNDING_NET,
			},
			MODIFIERS = {
				[Enums.ClassModifier.FLYER_DAMAGE] = 1.5,
				[Enums.ClassModifier.GROUND_DAMAGE] = 0.85,
			},
		},
		-- Combat: Foot Soldier / Mining: Balanced
		[Enums.ClassKind.RANGER] = {
			KIT = {
				WEAPON = Enums.WeaponKind.ASSAULT_RIFLE,
				POST = Enums.PostWeaponKind.MACHINE_GUN_AUTOMATED,
				TOWERS = { Enums.TowerKind.SENTRY_GUN },
				GADGET = Enums.GadgetKind.STIM_SHOT,
			},
			MODIFIERS = {
				[Enums.ClassModifier.HANDHELD_DAMAGE] = 1.3,
				[Enums.ClassModifier.MOVE_SPEED] = 1.1,
				[Enums.ClassModifier.TOWER_BUILD_COST] = 1.3,
			},
		},
		-- Building: Tower / Combat: Balanced
		[Enums.ClassKind.ENGINEER] = {
			KIT = {
				WEAPON = Enums.WeaponKind.RIFLE,
				POST = Enums.PostWeaponKind.MINE_LAYER,
				TOWERS = { Enums.TowerKind.SENTRY_GUN }, -- designed: Mortar Tower
				GADGET = Enums.GadgetKind.BUILD_TABLET,
			},
			MODIFIERS = {
				[Enums.ClassModifier.TOWER_BUILD_COST] = 0.7,
				[Enums.ClassModifier.MINING_POWER] = 0.8,
			},
		},
		-- Building: Tower / Combat: Group Destroyer
		[Enums.ClassKind.ELECTRICIAN] = {
			KIT = {
				WEAPON = Enums.WeaponKind.RIFLE,
				POST = Enums.PostWeaponKind.TESLA_ARC,
				TOWERS = { Enums.TowerKind.TESLA_COIL },
				GADGET = Enums.GadgetKind.STORM_ROD,
			},
			MODIFIERS = {
				[Enums.ClassModifier.TOWER_FIRE_RATE] = 1.2,
				[Enums.ClassModifier.MINING_POWER] = 0.8,
			},
		},
		-- Mining: Balanced / Combat: Group Destroyer
		[Enums.ClassKind.PROSPECTOR] = {
			KIT = {
				WEAPON = Enums.WeaponKind.PISTOL,
				POST = Enums.PostWeaponKind.SALVAGE_GUN,
				TOWERS = { Enums.TowerKind.SENTRY_GUN }, -- designed: Drill Rig
				GADGET = Enums.GadgetKind.ORE_SCANNER,
			},
			MODIFIERS = {
				[Enums.ClassModifier.MINING_POWER] = 1.4,
				[Enums.ClassModifier.ORE_YIELD] = 1.2,
				[Enums.ClassModifier.TOWER_BUILD_COST] = 1.3,
			},
		},
		-- Mining: Clearing / Combat: Tank Destroyer. Its blasts clear one
		-- block further, a reach step rather than a scale, so that waits
		-- on dynamite becoming the gadget
		[Enums.ClassKind.DEMOLITIONIST] = {
			KIT = {
				WEAPON = Enums.WeaponKind.RIFLE,
				POST = Enums.PostWeaponKind.ROCKET_LAUNCHER,
				TOWERS = { Enums.TowerKind.FLAMETHROWER },
				GADGET = Enums.GadgetKind.DYNAMITE,
			},
			MODIFIERS = {
				[Enums.ClassModifier.DYNAMITE_DAMAGE] = 2.0,
				[Enums.ClassModifier.TOWER_BUILD_COST] = 1.3,
			},
		},
		-- Mining: Hauling / Support
		[Enums.ClassKind.HAULER] = {
			KIT = {
				WEAPON = Enums.WeaponKind.PISTOL,
				POST = Enums.PostWeaponKind.SAW_GUN,
				TOWERS = { Enums.TowerKind.FROST_TOWER }, -- designed: Rock Slide
				GADGET = Enums.GadgetKind.ORE_CART,
			},
			MODIFIERS = {
				[Enums.ClassModifier.BACKPACK_CAPACITY] = 2.0,
				[Enums.ClassModifier.HANDHELD_DAMAGE] = 0.7,
			},
		},
		-- Support: people and structures / Combat: Balanced
		[Enums.ClassKind.MEDIC] = {
			KIT = {
				WEAPON = Enums.WeaponKind.PISTOL,
				POST = Enums.PostWeaponKind.MAGNET_GUN,
				TOWERS = { Enums.TowerKind.FROST_TOWER }, -- designed: Repair Tower
				GADGET = Enums.GadgetKind.MEDKIT,
			},
			MODIFIERS = {
				[Enums.ClassModifier.REPAIR_SPEED] = 2.0,
				[Enums.ClassModifier.REPAIR_COST] = 0.5,
				[Enums.ClassModifier.MINING_POWER] = 0.8,
			},
		},
	},
}
