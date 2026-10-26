--!strict

-- The Drag (M68, designed 2026-10-26, GDD "Monster Types": Drag; the name
-- is a placeholder): the chase. COUNT of them sleep sealed in the deep
-- pockets of zone MIN_ZONE_INDEX and deeper, one per pocket, drawn from
-- the mine's seed. Opening the pocket wakes it; it hunts its waker through
-- the open air cells of the mine (the FLOAT traversal: any air cell, no
-- gravity) at just under a fresh player's run, cannot be hurt inside the
-- mine, is staggered by dynamite, and burns away the moment it crosses the
-- mine's mouth, day or night (designer, 2026-10-26). Its victim's death
-- sends it back to its pocket, sealed. Its kind's stats are in
-- Monsters/Roster.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	KIND = Enums.MonsterKind.DRAG,
	-- sleepers per mine (designer, 2026-10-26: two or three; three)
	COUNT = 3,
	-- the first zone (the mine file's index) a sleeper may lie in: zone 4
	-- in the designer's numbering
	MIN_ZONE_INDEX = 5,
	SEED_OFFSET = 4242,
	-- the chase search: a cheapest-first walk over air cells toward the
	-- victim, capped per step; when sight is lost it follows the victim's
	-- trail instead
	SEARCH_MAX_CELLS = 48,
	SEARCH_INTERVAL_SEC = 0.25,
	-- the victim's recent cells kept as the trail, oldest dropped first
	TRAIL_MAX_CELLS = 64,
	TRAIL_SAMPLE_SEC = 0.25,
	-- how long a woken Drag hangs in its room before the chase starts: the
	-- shriek, and the digger's one moment to turn and run (2026-10-26: with
	-- no delay a wake killed the digger before their next step)
	WAKE_DELAY_SEC = 1.5,
	-- a dynamite blast whose radius reaches it holds it still this long
	DYNAMITE_STAGGER_SEC = 3,
	-- a cell is reached within this of its centre
	ARRIVE_STUDS = 0.5,
	-- it floats this far above the cell centres it moves between, so its
	-- legs clear the floor of a corridor's lowest row (designer, 2026-10-26)
	FLOAT_LIFT_STUDS = 2,
	-- with no path and no sight it drifts toward the victim's last known
	-- cell by straight line this slowly, so it is never frozen in a room
	LOST_DRIFT_SHARE = 0.25,
}
