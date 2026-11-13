--!strict

-- Badges (GDD "Earning Diamonds", M69; list agreed with the designer
-- 2026-11-12): one-time achievements, each a Roblox badge with a Diamond
-- reward the player claims once in the lobby's Badges menu. The whole set
-- pays 495, about five Supply Crates.
--
-- BY_KIND holds one entry per Enums.BadgeKind:
--   BADGE_ID   the badge on Roblox; 0 until it has been created there
--              (the badge is still earned and paid, the save being the
--              record)
--   DIAMONDS   paid once, when the earned badge's reward is claimed
--   STARS      how hard it is, 1 to 5, drawn in the Badges menu
--   DESCRIPTION  the menu's sentence. It repeats the numbers below and in
--              RULES in words, so change both together
--   ICON       the menu's picture ("rbxassetid://..."). Left out, it is
--              the Roblox badge's own icon once BADGE_ID is set, and
--              DEFAULT_ICON until then
--   COUNTER, THRESHOLD   a lifetime badge: earned when that saved counter
--              (Enums.BadgeCounter) reaches the threshold
--   NIGHT      a survival badge: earned by a player alive at the dawn
--              after that night of a run
-- A badge with none of the last three is judged by its own rule in the
-- gameplay BadgeTrackerManager or the lobby, with its numbers in RULES.
-- The names players read are Enums.BadgeKind.PublicNames.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	-- a placeholder until a badge has its own art
	DEFAULT_ICON = "rbxassetid://99730165827301",
	RULES = {
		-- Speed Run: board the rescue helicopter on this day or sooner
		SPEED_RUN_MAX_DAY = 10,
		-- Full Crew: the run held this many players at once
		FULL_CREW_SIZE = 6,
		-- Quiet Week: this many nights in a row, in one run, with no wall,
		-- gate, or Refinery damaged
		QUIET_WEEK_NIGHTS = 7,
		-- One-Man Army: kills credited to one player in a single night
		ONE_MAN_ARMY_KILLS = 100,
		-- Collector: classes owned, the Recruit included
		COLLECTOR_CLASSES = 8,
		-- Lucky 7: the Daily Rewards day whose claim earns it
		LUCKY_7_DAY = 7,
	},
	BY_KIND = {
		[Enums.BadgeKind.WELCOME] = {
			BADGE_ID = 0,
			DIAMONDS = 5,
			STARS = 1,
			DESCRIPTION = "Join Apocalyptic Mining Co.",
		},
		[Enums.BadgeKind.FIRST_SHIFT] = {
			BADGE_ID = 0,
			DIAMONDS = 5,
			STARS = 1,
			DESCRIPTION = "Survive your first night.",
			NIGHT = 1,
		},
		[Enums.BadgeKind.NIGHT_5] = {
			BADGE_ID = 0,
			DIAMONDS = 10,
			STARS = 2,
			DESCRIPTION = "Survive night 5 of a run.",
			NIGHT = 5,
		},
		[Enums.BadgeKind.NIGHT_10] = {
			BADGE_ID = 0,
			DIAMONDS = 15,
			STARS = 3,
			DESCRIPTION = "Survive night 10 of a run.",
			NIGHT = 10,
		},
		[Enums.BadgeKind.NIGHT_15] = {
			BADGE_ID = 0,
			DIAMONDS = 25,
			STARS = 4,
			DESCRIPTION = "Survive night 15 of a run.",
			NIGHT = 15,
		},
		[Enums.BadgeKind.RESCUED] = {
			BADGE_ID = 0,
			DIAMONDS = 10,
			STARS = 2,
			DESCRIPTION = "Board the rescue helicopter.",
		},
		[Enums.BadgeKind.HARD_RESCUE] = {
			BADGE_ID = 0,
			DIAMONDS = 25,
			STARS = 4,
			DESCRIPTION = "Get rescued on Hard.",
		},
		[Enums.BadgeKind.NIGHTMARE_RESCUE] = {
			BADGE_ID = 0,
			DIAMONDS = 35,
			STARS = 5,
			DESCRIPTION = "Get rescued on Nightmare.",
		},
		[Enums.BadgeKind.FULL_CREW] = {
			BADGE_ID = 0,
			DIAMONDS = 15,
			STARS = 3,
			DESCRIPTION = "Get rescued in a crew of 6.",
		},
		[Enums.BadgeKind.LONE_MINER] = {
			BADGE_ID = 0,
			DIAMONDS = 15,
			STARS = 3,
			DESCRIPTION = "Get rescued on a solo run.",
		},
		[Enums.BadgeKind.NOT_A_SCRATCH] = {
			BADGE_ID = 0,
			DIAMONDS = 35,
			STARS = 5,
			DESCRIPTION = "Get rescued without taking any damage.",
		},
		[Enums.BadgeKind.SPEED_RUN] = {
			BADGE_ID = 0,
			DIAMONDS = 25,
			STARS = 4,
			DESCRIPTION = "Get rescued by day 10.",
		},
		[Enums.BadgeKind.UNTOUCHED_REFINERY] = {
			BADGE_ID = 0,
			DIAMONDS = 25,
			STARS = 4,
			DESCRIPTION = "Get rescued with the Refinery never damaged.",
		},
		[Enums.BadgeKind.ROCK_BREAKER] = {
			BADGE_ID = 0,
			DIAMONDS = 10,
			STARS = 2,
			DESCRIPTION = "Break 1,000 blocks.",
			COUNTER = Enums.BadgeCounter.BLOCKS_BROKEN,
			THRESHOLD = 1000,
		},
		[Enums.BadgeKind.DEEP_MINER] = {
			BADGE_ID = 0,
			DIAMONDS = 15,
			STARS = 3,
			DESCRIPTION = "Break 10,000 blocks.",
			COUNTER = Enums.BadgeCounter.BLOCKS_BROKEN,
			THRESHOLD = 10000,
		},
		[Enums.BadgeKind.URANIUM_FEVER] = {
			BADGE_ID = 0,
			DIAMONDS = 15,
			STARS = 3,
			DESCRIPTION = "Refine 100 Uranium.",
			COUNTER = Enums.BadgeCounter.URANIUM_REFINED,
			THRESHOLD = 100,
		},
		[Enums.BadgeKind.EXTERMINATOR] = {
			BADGE_ID = 0,
			DIAMONDS = 10,
			STARS = 2,
			DESCRIPTION = "Kill 500 monsters.",
			COUNTER = Enums.BadgeCounter.MONSTERS_KILLED,
			THRESHOLD = 500,
		},
		[Enums.BadgeKind.PEST_CONTROL] = {
			BADGE_ID = 0,
			DIAMONDS = 15,
			STARS = 3,
			DESCRIPTION = "Kill 5,000 monsters.",
			COUNTER = Enums.BadgeCounter.MONSTERS_KILLED,
			THRESHOLD = 5000,
		},
		[Enums.BadgeKind.HOLY_PICK_AXE] = {
			BADGE_ID = 0,
			DIAMONDS = 10,
			STARS = 2,
			DESCRIPTION = "Upgrade your pick axe to its highest level in a run.",
		},
		[Enums.BadgeKind.CLASS_ACT] = {
			BADGE_ID = 0,
			DIAMONDS = 15,
			STARS = 3,
			DESCRIPTION = "Raise a class to 3 stars.",
		},
		[Enums.BadgeKind.COLLECTOR] = {
			BADGE_ID = 0,
			DIAMONDS = 25,
			STARS = 4,
			DESCRIPTION = "Unlock 8 classes.",
		},
		[Enums.BadgeKind.GHOST_MINER] = {
			BADGE_ID = 0,
			DIAMONDS = 10,
			STARS = 2,
			DESCRIPTION = "Survive an encounter with the Ghost Miner.",
		},
		[Enums.BadgeKind.GOLD_RUSH] = {
			BADGE_ID = 0,
			DIAMONDS = 10,
			STARS = 2,
			DESCRIPTION = "Refine 1,000 Gold Bars.",
			COUNTER = Enums.BadgeCounter.GOLD_REFINED,
			THRESHOLD = 1000,
		},
		[Enums.BadgeKind.ARCHITECT] = {
			BADGE_ID = 0,
			DIAMONDS = 15,
			STARS = 3,
			DESCRIPTION = "Survive a night with no one in the crew firing a handheld or Post Weapon.",
		},
		[Enums.BadgeKind.HANDYMAN] = {
			BADGE_ID = 0,
			DIAMONDS = 10,
			STARS = 2,
			DESCRIPTION = "Repair with the Hammer 500 times.",
			COUNTER = Enums.BadgeCounter.HAMMER_SWINGS,
			THRESHOLD = 500,
		},
		[Enums.BadgeKind.TEAM_PLAYER] = {
			BADGE_ID = 0,
			DIAMONDS = 5,
			STARS = 1,
			DESCRIPTION = "Give Gold or Iron to a crewmate.",
		},
		[Enums.BadgeKind.BUDDY_SYSTEM] = {
			BADGE_ID = 0,
			DIAMONDS = 5,
			STARS = 1,
			DESCRIPTION = "Play a run with a friend.",
		},
		[Enums.BadgeKind.QUIET_WEEK] = {
			BADGE_ID = 0,
			DIAMONDS = 35,
			STARS = 5,
			DESCRIPTION = "Survive 7 nights in a row with no wall, gate, or Refinery damaged.",
		},
		[Enums.BadgeKind.ONE_MAN_ARMY] = {
			BADGE_ID = 0,
			DIAMONDS = 10,
			STARS = 2,
			DESCRIPTION = "Kill 100 monsters in one night.",
		},
		[Enums.BadgeKind.VETERAN] = {
			BADGE_ID = 0,
			DIAMONDS = 25,
			STARS = 4,
			DESCRIPTION = "Get rescued 10 times.",
			COUNTER = Enums.BadgeCounter.RESCUES,
			THRESHOLD = 10,
		},
		[Enums.BadgeKind.LUCKY_7] = {
			BADGE_ID = 0,
			DIAMONDS = 10,
			STARS = 2,
			DESCRIPTION = "Claim the day 7 Daily Reward.",
		},
	},
}
