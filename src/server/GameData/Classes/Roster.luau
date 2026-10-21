--!strict

-- The launch classes (GDD "Classes", designed 2026-10-15), M64. One entry
-- per Enums.ClassKind: the fixed kit a character of that class brings
-- into a run (KIT: one handheld weapon, one post weapon, one tower, one
-- gadget; exactly one of each, decided 2026-10-19, so no class is better
-- at building by kit alone) and its buff and debuff as MODIFIERS, entries in the
-- Enums.ClassModifier table scaled from a default of 1.0 (a key that is
-- absent is 1.0, except the two core stats, speed and mining strength,
-- which every class states outright since 2026-10-19 so they read side
-- by side; a row missing one is a startup error. Health was a third core
-- stat for an afternoon and was dropped the same day as one variable too
-- many: every class has the same health). A buff is a
-- modifier on something shared, never a
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
				TOWER = Enums.TowerKind.SENTRY_GUN,
				GADGET = Enums.GadgetKind.NONE,
			},
			MODIFIERS = {
				-- core stats
				[Enums.ClassModifier.MOVE_SPEED] = 1.0,
				[Enums.ClassModifier.MINING_POWER] = 1.0,
			},
		},
		-- Combat: Balanced / Building: Tower
		[Enums.ClassKind.GUNNER] = {
			KIT = {
				WEAPON = Enums.WeaponKind.RIFLE,
				POST = Enums.PostWeaponKind.MINI_GUN,
				TOWER = Enums.TowerKind.SENTRY_GUN,
				GADGET = Enums.GadgetKind.AUTO_TURRET,
			},
			MODIFIERS = {
				-- core stats. Mining 0.75 (2026-10-19, after 0.8 then 0.6 for a
				-- day each; a 0.7 move speed was tried the same day and felt
				-- like friction with no decision in it, so speed stays 1.0).
				-- The pick's damage rounds, so 0.75 reads as 0.8 at the low
				-- rungs (5 to 4, 15 to 11) and bites more from rung 3 up
				[Enums.ClassModifier.MOVE_SPEED] = 1.0,
				[Enums.ClassModifier.MINING_POWER] = 0.75,
			},
		},
		-- Combat: Tank Destroyer / Support
		[Enums.ClassKind.SNIPER] = {
			KIT = {
				-- the sidearm, not a second scope (2026-10-19): the Railgun
				-- post is the Sniper's gun, the Pistol is for the walk to it
				WEAPON = Enums.WeaponKind.PISTOL,
				POST = Enums.PostWeaponKind.RAIL_GUN,
				TOWER = Enums.TowerKind.SNIPER_TOWER,
				GADGET = Enums.GadgetKind.BINOCULARS,
			},
			MODIFIERS = {
				-- core stats
				[Enums.ClassModifier.MOVE_SPEED] = 1.0,
				[Enums.ClassModifier.MINING_POWER] = 1.0,
				[Enums.ClassModifier.LARGE_MONSTER_DAMAGE] = 1.5,
				[Enums.ClassModifier.TOWER_BUILD_COST] = 1.3,
			},
		},
		-- Combat: Group Destroyer / Building: Trap
		[Enums.ClassKind.PYRO] = {
			KIT = {
				WEAPON = Enums.WeaponKind.FLAMETHROWER,
				-- the direct post for the combat class; the TNT Launcher (the Napalm Mortar then) went
				-- to the Demolitionist (decided 2026-10-20)
				POST = Enums.PostWeaponKind.ROCKET_LAUNCHER,
				TOWER = Enums.TowerKind.FLAMETHROWER,
				GADGET = Enums.GadgetKind.REMOTE_CHARGE,
			},
			MODIFIERS = {
				-- core stats
				[Enums.ClassModifier.MOVE_SPEED] = 1.0,
				[Enums.ClassModifier.MINING_POWER] = 0.8,
				[Enums.ClassModifier.TRAP_COST] = 0.5,
			},
		},
		-- Combat: Air Defender / Building: Tower
		[Enums.ClassKind.AIR_DEFENSE] = {
			KIT = {
				WEAPON = Enums.WeaponKind.RIFLE,
				POST = Enums.PostWeaponKind.AA_LAUNCHER,
				TOWER = Enums.TowerKind.AA_TURRET,
				-- a thrown lure every monster in range goes for (2026-10-20,
				-- in place of the Grounding Net, which only mattered on a flyer night)
				GADGET = Enums.GadgetKind.FLARE,
			},
			MODIFIERS = {
				-- core stats
				[Enums.ClassModifier.MOVE_SPEED] = 1.0,
				[Enums.ClassModifier.MINING_POWER] = 1.0,
				-- no damage split (flyers 1.5, ground 0.85 until 2026-10-20):
				-- the Missile Launcher's own ground share carries it
			},
		},
		-- Combat: Foot Soldier / Mining: Balanced
		[Enums.ClassKind.RANGER] = {
			KIT = {
				WEAPON = Enums.WeaponKind.ASSAULT_RIFLE,
				POST = Enums.PostWeaponKind.MACHINE_GUN_AUTOMATED,
				TOWER = Enums.TowerKind.SENTRY_GUN,
				GADGET = Enums.GadgetKind.STIM_SHOT,
			},
			MODIFIERS = {
				-- core stats
				[Enums.ClassModifier.MOVE_SPEED] = 1.1,
				[Enums.ClassModifier.MINING_POWER] = 1.0,
				[Enums.ClassModifier.HANDHELD_DAMAGE] = 1.3,
				[Enums.ClassModifier.TOWER_BUILD_COST] = 1.3,
			},
		},
		-- Building: Tower / Combat: Balanced
		[Enums.ClassKind.ENGINEER] = {
			KIT = {
				WEAPON = Enums.WeaponKind.RIFLE,
				POST = Enums.PostWeaponKind.MINE_LAYER,
				TOWER = Enums.TowerKind.SENTRY_GUN, -- designed: Mortar Tower
				GADGET = Enums.GadgetKind.BUILD_TABLET,
			},
			MODIFIERS = {
				-- core stats
				[Enums.ClassModifier.MOVE_SPEED] = 1.0,
				[Enums.ClassModifier.MINING_POWER] = 0.8,
				[Enums.ClassModifier.TOWER_BUILD_COST] = 0.7,
			},
		},
		-- Building: Tower / Combat: Group Destroyer
		[Enums.ClassKind.ELECTRICIAN] = {
			KIT = {
				WEAPON = Enums.WeaponKind.RIFLE,
				POST = Enums.PostWeaponKind.TESLA_ARC,
				TOWER = Enums.TowerKind.TESLA_COIL,
				GADGET = Enums.GadgetKind.STORM_ROD,
			},
			MODIFIERS = {
				-- core stats
				[Enums.ClassModifier.MOVE_SPEED] = 1.0,
				[Enums.ClassModifier.MINING_POWER] = 0.8,
			},
		},
		-- Mining: Balanced / Combat: Group Destroyer
		[Enums.ClassKind.PROSPECTOR] = {
			KIT = {
				WEAPON = Enums.WeaponKind.PISTOL,
				POST = Enums.PostWeaponKind.SALVAGE_GUN,
				TOWER = Enums.TowerKind.SENTRY_GUN, -- designed: Drill Rig
				GADGET = Enums.GadgetKind.ORE_SCANNER,
			},
			MODIFIERS = {
				-- core stats
				[Enums.ClassModifier.MOVE_SPEED] = 1.0,
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
				-- the sidearm (2026-10-20; the Rifle until then): the post and
				-- the dynamite are the class's weapons
				WEAPON = Enums.WeaponKind.PISTOL,
				-- the lob, a TNT bomb in the air (2026-10-20, from the Pyro)
				POST = Enums.PostWeaponKind.MORTAR,
				TOWER = Enums.TowerKind.FLAMETHROWER,
				GADGET = Enums.GadgetKind.DYNAMITE,
			},
			MODIFIERS = {
				-- core stats
				[Enums.ClassModifier.MOVE_SPEED] = 1.0,
				[Enums.ClassModifier.MINING_POWER] = 1.0,
				[Enums.ClassModifier.TOWER_BUILD_COST] = 1.3,
			},
		},
		-- Mining: Hauling / Support
		[Enums.ClassKind.HAULER] = {
			KIT = {
				WEAPON = Enums.WeaponKind.PISTOL,
				POST = Enums.PostWeaponKind.SAW_GUN,
				TOWER = Enums.TowerKind.FROST_TOWER, -- designed: Rock Slide
				GADGET = Enums.GadgetKind.ORE_CART,
			},
			MODIFIERS = {
				-- core stats
				[Enums.ClassModifier.MOVE_SPEED] = 1.0,
				[Enums.ClassModifier.MINING_POWER] = 1.0,
				[Enums.ClassModifier.BACKPACK_CAPACITY] = 2.0,
				[Enums.ClassModifier.HANDHELD_DAMAGE] = 0.7,
			},
		},
		-- Support: people and structures / Combat: Balanced
		[Enums.ClassKind.MEDIC] = {
			KIT = {
				WEAPON = Enums.WeaponKind.PISTOL,
				POST = Enums.PostWeaponKind.MAGNET_GUN,
				TOWER = Enums.TowerKind.FROST_TOWER, -- designed: Repair Tower
				GADGET = Enums.GadgetKind.MEDKIT,
			},
			MODIFIERS = {
				-- core stats
				[Enums.ClassModifier.MOVE_SPEED] = 1.0,
				[Enums.ClassModifier.MINING_POWER] = 0.8,
				[Enums.ClassModifier.REPAIR_SPEED] = 2.0,
				[Enums.ClassModifier.REPAIR_COST] = 0.5,
			},
		},
	},
}
