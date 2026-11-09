--!strict

-- The skill catalogue (GDD "Classes", M56). Each entry is keyed by its
-- id, the string a class record's save names, so an id is never renamed
-- once a save can hold it. Every skill belongs to one Enums.SkillFamily
-- and has one Enums.Rarity. The 36 below were designed with the designer
-- on 2026-11-09 (twelve per family: four Common, three Uncommon, three
-- Rare, one Epic, one Legendary; the twelve placeholders of M55 folded in
-- or dropped, an unknown id in a save being dropped on load). Rules fixed
-- that day: every skill is class agnostic (nothing touches one class's
-- gadget or tower); a skill that changes a shared thing (the walls, every
-- Tower, the Tower pool, the Refinery) says "(cannot stack)" and the
-- server applies it once if anyone in the crew holds it; headshots exist
-- on a weapon only where its own data says so (the Railgun) or when the
-- shooter holds HEADHUNTER. DESCRIPTION is what the Class Menu shows; the
-- effect each one has on the run is M56's build, when a field for it
-- grows here. A title for two of a family and a set bonus for three
-- were in the first brief and dropped on 2026-11-09 (designer).
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	BY_ID = {
		-- Mining
		ROCKET_SCIENCE = {
			FAMILY = Enums.SkillFamily.MINING,
			RARITY = Enums.Rarity.COMMON,
			NAME = "Rocket Science",
			DESCRIPTION = "Jet pack fuel lasts 20% longer",
		},
		LONG_HAUL = {
			FAMILY = Enums.SkillFamily.MINING,
			RARITY = Enums.Rarity.COMMON,
			NAME = "Long Haul",
			DESCRIPTION = "Walk 10% faster with a full backpack",
		},
		QUICK_REFINER = {
			FAMILY = Enums.SkillFamily.MINING,
			RARITY = Enums.Rarity.COMMON,
			NAME = "Quick Refiner",
			DESCRIPTION = "Your ore refines in half the time",
		},
		HARDENED_PICK = {
			FAMILY = Enums.SkillFamily.MINING,
			RARITY = Enums.Rarity.COMMON,
			NAME = "Hardened Pick",
			DESCRIPTION = "Uranium rocks take 10% fewer hits",
		},
		RICH_SEAM = {
			FAMILY = Enums.SkillFamily.MINING,
			RARITY = Enums.Rarity.UNCOMMON,
			NAME = "Rich Seam",
			DESCRIPTION = "Gold rocks take 1 fewer hit to break",
		},
		THICK_SKULL = {
			FAMILY = Enums.SkillFamily.MINING,
			RARITY = Enums.Rarity.UNCOMMON,
			NAME = "Thick Skull",
			DESCRIPTION = "Mine monsters deal half damage to you",
		},
		URANIUM_SEEKER = {
			FAMILY = Enums.SkillFamily.MINING,
			RARITY = Enums.Rarity.UNCOMMON,
			NAME = "Uranium Seeker",
			DESCRIPTION = "The Geiger Counter's second ring shows whether the uranium is above or below",
		},
		GOLD_DIGGER = {
			FAMILY = Enums.SkillFamily.MINING,
			RARITY = Enums.Rarity.RARE,
			NAME = "Gold Digger",
			DESCRIPTION = "Start each run with 20 Gold Bars",
		},
		DEEP_POCKETS = {
			FAMILY = Enums.SkillFamily.MINING,
			RARITY = Enums.Rarity.RARE,
			NAME = "Deep Pockets",
			DESCRIPTION = "Backpack holds 10% more ore",
		},
		CLEAN_BREAK = {
			FAMILY = Enums.SkillFamily.MINING,
			RARITY = Enums.Rarity.RARE,
			NAME = "Clean Break",
			DESCRIPTION = "10% chance a rock breaks in one swing",
		},
		STEADY_SWING = {
			FAMILY = Enums.SkillFamily.MINING,
			RARITY = Enums.Rarity.EPIC,
			NAME = "Steady Swing",
			DESCRIPTION = "Pick axe swings 10% faster",
		},
		MOTHER_LODE = {
			FAMILY = Enums.SkillFamily.MINING,
			RARITY = Enums.Rarity.LEGENDARY,
			NAME = "Mother Lode",
			DESCRIPTION = "Every tenth rock broken drops double ore",
		},

		-- Combat
		FAST_RELOAD = {
			FAMILY = Enums.SkillFamily.COMBAT,
			RARITY = Enums.Rarity.COMMON,
			NAME = "Fast Reload",
			DESCRIPTION = "Handheld weapons reload 20% faster",
		},
		QUICK_HANDS = {
			FAMILY = Enums.SkillFamily.COMBAT,
			RARITY = Enums.Rarity.COMMON,
			NAME = "Quick Hands",
			DESCRIPTION = "Post weapons turn 15% faster",
		},
		DEEP_LUNGS = {
			FAMILY = Enums.SkillFamily.COMBAT,
			RARITY = Enums.Rarity.COMMON,
			NAME = "Deep Lungs",
			DESCRIPTION = "Sprint and jet pack fuel drain 20% slower at night",
		},
		BIG_CLIP = {
			FAMILY = Enums.SkillFamily.COMBAT,
			RARITY = Enums.Rarity.COMMON,
			NAME = "Big Clip",
			DESCRIPTION = "Handheld magazines hold 20% more",
		},
		COOL_BARREL = {
			FAMILY = Enums.SkillFamily.COMBAT,
			RARITY = Enums.Rarity.UNCOMMON,
			NAME = "Cool Barrel",
			DESCRIPTION = "Post weapons reload and cool 20% faster",
		},
		THICK_SKIN = {
			FAMILY = Enums.SkillFamily.COMBAT,
			RARITY = Enums.Rarity.UNCOMMON,
			NAME = "Thick Skin",
			DESCRIPTION = "Take 20% less damage from monsters at night, mine monsters included",
		},
		NIGHT_OWL = {
			FAMILY = Enums.SkillFamily.COMBAT,
			RARITY = Enums.Rarity.UNCOMMON,
			NAME = "Night Owl",
			DESCRIPTION = "Deal 10% more damage at night",
		},
		GUNSLINGER = {
			FAMILY = Enums.SkillFamily.COMBAT,
			RARITY = Enums.Rarity.RARE,
			NAME = "Gunslinger",
			DESCRIPTION = "Handheld weapons deal 10% more damage",
		},
		HEADHUNTER = {
			FAMILY = Enums.SkillFamily.COMBAT,
			RARITY = Enums.Rarity.RARE,
			NAME = "Headhunter",
			DESCRIPTION = "Headshots on every weapon",
		},
		POST_POWERHOUSE = {
			FAMILY = Enums.SkillFamily.COMBAT,
			RARITY = Enums.Rarity.RARE,
			NAME = "Post Powerhouse",
			DESCRIPTION = "Post weapons deal 10% more damage",
		},
		LAST_STAND = {
			FAMILY = Enums.SkillFamily.COMBAT,
			RARITY = Enums.Rarity.EPIC,
			NAME = "Last Stand",
			DESCRIPTION = "Below 25% health, all weapons fire 25% faster",
		},
		CHAIN_REACTION = {
			FAMILY = Enums.SkillFamily.COMBAT,
			RARITY = Enums.Rarity.LEGENDARY,
			NAME = "Chain Reaction",
			DESCRIPTION = "A killing blow deals 25% of its damage to every monster within 6 studs",
		},

		-- Building
		QUICK_FIX = {
			FAMILY = Enums.SkillFamily.BUILDING,
			RARITY = Enums.Rarity.COMMON,
			NAME = "Quick Fix",
			DESCRIPTION = "Repair swings 20% faster",
		},
		HANDY = {
			FAMILY = Enums.SkillFamily.BUILDING,
			RARITY = Enums.Rarity.COMMON,
			NAME = "Handy",
			DESCRIPTION = "Repairs restore 20% more HP",
		},
		SCRAP_SAVER = {
			FAMILY = Enums.SkillFamily.BUILDING,
			RARITY = Enums.Rarity.COMMON,
			NAME = "Scrap Saver",
			DESCRIPTION = "Traps cost 10% less Iron",
		},
		NIGHT_SHIFT = {
			FAMILY = Enums.SkillFamily.BUILDING,
			RARITY = Enums.Rarity.COMMON,
			NAME = "Night Shift",
			DESCRIPTION = "Walk 10% faster inside the camp at night",
		},
		FIELD_ENGINEER = {
			FAMILY = Enums.SkillFamily.BUILDING,
			RARITY = Enums.Rarity.UNCOMMON,
			NAME = "Field Engineer",
			DESCRIPTION = "The camp's Tower limit rises by 1 (cannot stack)",
		},
		REINFORCED = {
			FAMILY = Enums.SkillFamily.BUILDING,
			RARITY = Enums.Rarity.UNCOMMON,
			NAME = "Reinforced",
			DESCRIPTION = "Towers have 20% more HP (cannot stack)",
		},
		SPARE_PARTS = {
			FAMILY = Enums.SkillFamily.BUILDING,
			RARITY = Enums.Rarity.UNCOMMON,
			NAME = "Spare Parts",
			DESCRIPTION = "Repairs cost 10% less Iron",
		},
		STURDY_WALLS = {
			FAMILY = Enums.SkillFamily.BUILDING,
			RARITY = Enums.Rarity.RARE,
			NAME = "Sturdy Walls",
			DESCRIPTION = "Walls and the gate have 10% more HP (cannot stack)",
		},
		FOREMAN = {
			FAMILY = Enums.SkillFamily.BUILDING,
			RARITY = Enums.Rarity.RARE,
			NAME = "Foreman",
			DESCRIPTION = "Towers cost 10% less Iron",
		},
		GENEROUS = {
			FAMILY = Enums.SkillFamily.BUILDING,
			RARITY = Enums.Rarity.RARE,
			NAME = "Generous",
			DESCRIPTION = "Your fortification donations count 25% more",
		},
		FORTRESS = {
			FAMILY = Enums.SkillFamily.BUILDING,
			RARITY = Enums.Rarity.EPIC,
			NAME = "Fortress",
			DESCRIPTION = "The Refinery takes 15% less damage (cannot stack)",
		},
		MASTER_BUILDER = {
			FAMILY = Enums.SkillFamily.BUILDING,
			RARITY = Enums.Rarity.LEGENDARY,
			NAME = "Master Builder",
			DESCRIPTION = "Collapsed walls and the gate stand back up on your first repair swing, before they are fully rebuilt",
		},
	},
}
