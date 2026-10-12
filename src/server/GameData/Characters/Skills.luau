--!strict

-- The skill catalogue (GDD "Characters"), M55. Each entry is keyed by its
-- id, the string a character's save names, so an id is never renamed once
-- a save can hold it. Every skill belongs to one Enums.SkillFamily and has
-- one Enums.SkillRarity. These are placeholders, two or three per family,
-- so saves and rolls can be tested; the real 36 and what each one does
-- land in M56, when EFFECT grows into something the run reads.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	BY_ID = {
		GOLD_DIGGER = {
			FAMILY = Enums.SkillFamily.DIGGING,
			RARITY = Enums.SkillRarity.COMMON,
			NAME = "Gold Digger",
			DESCRIPTION = "Start a run with 20 Gold Bars",
		},
		STEADY_SWING = {
			FAMILY = Enums.SkillFamily.DIGGING,
			RARITY = Enums.SkillRarity.RARE,
			NAME = "Steady Swing",
			DESCRIPTION = "Pick axe swings 10% faster",
		},
		DEEP_POCKETS = {
			FAMILY = Enums.SkillFamily.HAULING,
			RARITY = Enums.SkillRarity.COMMON,
			NAME = "Deep Pockets",
			DESCRIPTION = "Backpack holds 2 more ore",
		},
		LONG_HAUL = {
			FAMILY = Enums.SkillFamily.HAULING,
			RARITY = Enums.SkillRarity.EPIC,
			NAME = "Long Haul",
			DESCRIPTION = "Walk 10% faster with a full backpack",
		},
		SHORT_FUSE = {
			FAMILY = Enums.SkillFamily.DEMOLITION,
			RARITY = Enums.SkillRarity.COMMON,
			NAME = "Short Fuse",
			DESCRIPTION = "Dynamite fuses burn 1 second shorter",
		},
		BIG_BANG = {
			FAMILY = Enums.SkillFamily.DEMOLITION,
			RARITY = Enums.SkillRarity.LEGENDARY,
			NAME = "Big Bang",
			DESCRIPTION = "Dynamite clears one block further",
		},
		HANDY = {
			FAMILY = Enums.SkillFamily.BUILDING,
			RARITY = Enums.SkillRarity.COMMON,
			NAME = "Handy",
			DESCRIPTION = "Repairs restore 20% more HP",
		},
		FOREMAN = {
			FAMILY = Enums.SkillFamily.BUILDING,
			RARITY = Enums.SkillRarity.RARE,
			NAME = "Foreman",
			DESCRIPTION = "Towers cost 10% less Iron",
		},
		QUICK_HANDS = {
			FAMILY = Enums.SkillFamily.GUNNERY,
			RARITY = Enums.SkillRarity.COMMON,
			NAME = "Quick Hands",
			DESCRIPTION = "Post weapons turn 15% faster",
		},
		COOL_BARREL = {
			FAMILY = Enums.SkillFamily.GUNNERY,
			RARITY = Enums.SkillRarity.EPIC,
			NAME = "Cool Barrel",
			DESCRIPTION = "The machine gun takes 1 second longer to overheat",
		},
		DEAD_EYE = {
			FAMILY = Enums.SkillFamily.MARKSMANSHIP,
			RARITY = Enums.SkillRarity.COMMON,
			NAME = "Dead Eye",
			DESCRIPTION = "Handheld weapons deal 5% more damage",
		},
		FAST_RELOAD = {
			FAMILY = Enums.SkillFamily.MARKSMANSHIP,
			RARITY = Enums.SkillRarity.RARE,
			NAME = "Fast Reload",
			DESCRIPTION = "Handheld weapons reload 20% faster",
		},
	},
}
