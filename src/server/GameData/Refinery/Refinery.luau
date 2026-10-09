--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- The Refinery (GDD "Refining Ore"): refined units per ore, and how long the
-- machine grinds before paying out. One to one for now (decided 2026-09-14).
return {
	RATE_BY_RAW = {
		[Enums.RawResource.IRON_ORE] = 1,
		[Enums.RawResource.GOLD_ORE] = 1,
		[Enums.RawResource.URANIUM_ORE] = 1,
	},
	-- the machine is busy while it grinds; the client flies the ore in, then
	-- spins the grinder with its sound until the payout flies out at this
	-- time (4 s since 2026-10-09, from 2)
	REFINE_DURATION_SEC = 4,
	-- refining is automatic (decided 2026-10-01, replacing the prompt): a
	-- player who steps inside this radius of the Refinery with ore in the
	-- backpack is refined on the spot. The server checks every POLL_SEC;
	-- the client draws the ring on the ground
	REFINE_RADIUS_STUDS = 14,
	REFINE_POLL_SEC = 0.25,
}
