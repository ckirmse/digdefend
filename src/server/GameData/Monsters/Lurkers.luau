--!strict

-- Pocket lurkers (GDD "Pocket lurkers", M62, 2026-10-08): the monster that
-- sleeps in some of the mine's pockets and hunts whoever opens one. The
-- pockets are chosen from the mine's seed at run start, so a mine always
-- holds the same lurkers for the same seed; the kind's stats are its
-- Roster entry. A lurker is stepped at the monster tick rate but never
-- uses the camp's path field: it sees a player down a straight line of
-- air cells, and when the line breaks it searches the air round it a few
-- cells at a time (shared LurkerRules).
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	KIND = Enums.MonsterKind.CAVE_SPIDER,
	-- how many pockets hold one: a fixed count by crew size, never a chance
	-- (designer, 2026-10-08, replacing one pocket in five): 10 for a solo
	-- player and 2 more per extra crew member, 20 at most, drawn from the
	-- eligible pockets in the mine's seed order
	BASE_COUNT = 10,
	COUNT_PER_EXTRA_CREW = 2,
	MAX_COUNT = 20,
	-- the first zone whose pockets may hold one, as the mine file lists
	-- them (1 is the starter band, the designer's zone 0): 4 is the
	-- designer's zone 3, so the first three zones are spider-free
	-- (designer, 2026-10-08: a new player learns the mine before the
	-- mine bites back)
	MIN_ZONE_INDEX = 4,
	-- added to the mine seed for the pocket draw, so the pick is its own
	-- stream and a change here does not move the ore
	SEED_OFFSET = 7777,
	-- how far (in cells) the search goes when the player is out of sight;
	-- the mine's air is a thin web, so this is tens of cells, not thousands
	-- 24 since 2026-10-08 (was 12, sized for the old six-cell pockets): a
	-- 4 by 4 room and a wide tunnel put a player 40 studs away 17 cells along
	-- the rock, and the spider sat drifting with no route
	SEARCH_MAX_CELLS = 24,
	-- how often a chasing lurker that cannot see its player searches again
	SEARCH_INTERVAL_SEC = 0.5,
	-- a wandering lurker picks a new neighbouring cell this often
	WANDER_INTERVAL_SEC = 1.5,
	-- how far from the next cell's centre counts as arrived
	ARRIVE_STUDS = 0.3,
	-- a player (or a dev spawn) in open air is hunted at the first cell
	-- under them that touches rock, looking down this many cells
	GOAL_MAX_DROP_CELLS = 6,
	-- the alert cry is sent to clients when a lurker takes a new player as
	-- its target, and no sooner than this after the last one
	ALERT_COOLDOWN_SEC = 4,
	-- a sleeping pocket skitters (the kind's WALK sound, 3D from where the
	-- lurker rests) this often to any player within SLEEPING_SOUND_SILENT_STUDS
	-- of it, so a close player gets a warning before opening the wall
	-- (designer, 2026-10-08); the server plays it, so clients never learn
	-- where the pockets are
	SLEEPING_SOUND_INTERVAL_SEC = 10,
	SLEEPING_SOUND_FULL_VOLUME_STUDS = 6,
	SLEEPING_SOUND_SILENT_STUDS = 20,
}
