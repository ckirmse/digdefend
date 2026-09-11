--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- Helicopter pad party tuning (GDD "Helicopter Pads – Party Creation/Teleports").
-- Every pad is identical; the host configures the run from these lists.
-- MAPS and DIFFICULTIES are ordered: the Create Party carousels show them in
-- this order. A requirement names a completion the host must hold; a
-- difficulty requirement is checked on the selected map unless it names one.
-- PartyRules.validateConfig checks this table at lobby startup.
return {
	-- seconds a host has to press Create before the pad is released
	CREATION_TIMEOUT_SEC = 30,
	-- seconds after Create before the party auto-launches
	BOARDING_TIMEOUT_SEC = 20,
	-- countdown once the party is full
	CAPACITY_TIME_SEC = 3,
	-- upper bound of the players stepper; never above helicopter seat count
	MAX_PARTY_SIZE = 6,
	DEFAULT_MAX_PLAYERS = 4,
	DEFAULT_VISIBILITY = Enums.PartyVisibility.PUBLIC,
	-- JoinCollision fires every frame a character stands in it; one decision
	-- per player per this many seconds
	TOUCH_DEBOUNCE_SEC = 2,
	-- how often the server checks pad timers for expiry
	TIMER_POLL_SEC = 0.25,
	-- seconds the helicopter climbs (client visual) before characters are
	-- moved to the holding area and the teleport is attempted
	TAKEOFF_SEC = 4,
	-- reserve + teleport attempts before the party is given "Teleport failed"
	TELEPORT_RETRY_COUNT = 3,
	TELEPORT_RETRY_DELAY_SEC = 2,
	-- after a successful teleport call, how long members get to actually leave
	-- before anyone still here is treated as a failed teleport
	TELEPORT_SETTLE_SEC = 10,
	-- a departed helicopter keeps flying (client visual) this long after the
	-- pad has been reset with a fresh one, then the server destroys it
	DEPARTED_HELICOPTER_LIFETIME_SEC = 35,

	MAPS = {
		{
			map = Enums.Map.DEADMANS_CANYON,
			thumbnail = "rbxassetid://0",
		},
		{
			map = Enums.Map.FROSTBITE_PASS,
			thumbnail = "rbxassetid://0",
			requires = {
				map = Enums.Map.DEADMANS_CANYON,
				difficulty = Enums.Difficulty.NORMAL,
			},
		},
	},

	DIFFICULTIES = {
		{
			difficulty = Enums.Difficulty.NORMAL,
		},
		{
			difficulty = Enums.Difficulty.HARD,
			requires = {
				difficulty = Enums.Difficulty.NORMAL,
			},
		},
		{
			difficulty = Enums.Difficulty.NIGHTMARE,
			requires = {
				difficulty = Enums.Difficulty.HARD,
			},
		},
	},
}
