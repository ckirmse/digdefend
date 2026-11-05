--!strict

-- The words the Class Menu shows (GDD "Classes", the Class Equip Menu of
-- 2026-11-04): one sentence per class, and one per kit item for the
-- tooltip behind its slot. Every line is a placeholder for the designer
-- to rewrite; a class or item without a line shows nothing rather than a
-- stand-in. Kept apart from the roster so copy edits never touch tuning.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	BY_CLASS_KIND = {
		[Enums.ClassKind.RECRUIT] = "The free all-rounder: a pistol, a machine gun post, and a sentry gun.",
		[Enums.ClassKind.GUNNER] = "Steady firepower from a rifle, a minigun post, and an auto turret.",
		[Enums.ClassKind.SNIPER] = "Long shots that reward headshots, with binoculars that tag a monster for the whole crew.",
		[Enums.ClassKind.PYRO] = "Burns crowds with a flamethrower and remote charges that leave a pool of fire.",
		[Enums.ClassKind.AIR_DEFENSE] = "Keeps the sky clear with an anti-air turret and a flare gun that lights the ground.",
		[Enums.ClassKind.RANGER] = "Fast and self-reliant, with a stim shot that heals and speeds up in a pinch.",
		[Enums.ClassKind.ENGINEER] = "Builds cheaper and repairs faster, the backbone of a well-walled camp.",
		[Enums.ClassKind.ELECTRICIAN] = "Chains lightning between monsters from a tesla coil.",
		[Enums.ClassKind.PROSPECTOR] = "Swings fastest in the mine, with a drill rig that earns Iron and Gold on its own.",
		[Enums.ClassKind.DEMOLITIONIST] = "Clears rock and monsters alike with dynamite.",
		[Enums.ClassKind.HAULER] = "Carries more ore per trip, so the Refinery never waits.",
		[Enums.ClassKind.MEDIC] = "Keeps the crew on its feet with faster revives.",
	},
	-- Enums.GearSlot -> kind -> the tooltip's sentence
	BY_KIT_SLOT = {
		[Enums.GearSlot.WEAPON] = {
			[Enums.WeaponKind.PISTOL] = "A dependable sidearm with a quick reload.",
			[Enums.WeaponKind.RIFLE] = "A rifle that hits hard at range.",
			[Enums.WeaponKind.ASSAULT_RIFLE] = "A fast-firing rifle for close crowds.",
			[Enums.WeaponKind.FLAMETHROWER] = "Sprays fire that burns everything in front of it.",
		},
		[Enums.GearSlot.POST] = {
			[Enums.PostWeaponKind.MACHINE_GUN] = "A mounted machine gun with a wide arc.",
			[Enums.PostWeaponKind.MINI_GUN] = "Spins up to a wall of bullets.",
			[Enums.PostWeaponKind.ROCKET_LAUNCHER] = "Fires rockets that burst on impact.",
			[Enums.PostWeaponKind.RAIL_GUN] = "A charged shot that rewards a headshot.",
			[Enums.PostWeaponKind.DRILL_GUN] = "Fires a drill bit that cracks the ground along its path.",
		},
		[Enums.GearSlot.TOWER_1] = {
			[Enums.TowerKind.SENTRY_GUN] = "Shoots the nearest monster in range.",
			[Enums.TowerKind.FLAMETHROWER] = "Burns anything that walks past it.",
			[Enums.TowerKind.AA_TURRET] = "Shoots down flying monsters.",
			[Enums.TowerKind.FROST_TOWER] = "Slows every monster around it.",
			[Enums.TowerKind.TESLA_COIL] = "Arcs lightning between nearby monsters.",
			[Enums.TowerKind.SNIPER_TOWER] = "Picks off monsters from far away.",
		},
	},
	-- gadgets have no gear slot; keyed by Enums.GadgetKind
	BY_GADGET_KIND = {
		[Enums.GadgetKind.AUTO_TURRET] = "A turret you place anywhere, drawing monsters off the crew.",
		[Enums.GadgetKind.BINOCULARS] = "Tag a monster from a post so every hit on it does more.",
		[Enums.GadgetKind.STIM_SHOT] = "Heal up and move faster for a short while, once a day.",
		[Enums.GadgetKind.REMOTE_CHARGE] = "Plant a mine and set it off when the crowd is on it.",
		[Enums.GadgetKind.DYNAMITE] = "Throw a stick to clear rock or a crowd.",
		[Enums.GadgetKind.FLARE] = "Fire a flare that lights the ground where it lands.",
		[Enums.GadgetKind.ORE_SCANNER] = "Sweep the mine to show where the ore is.",
	},
}
