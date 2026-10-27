--!strict

-- The helicopters' flight (M75), both places: the shape and timing of an
-- approach onto a pad and a departure from one, sampled by the clients
-- from pure HelicopterFlightRules (the same fields as its Config).
-- HelicopterManager publishes this table once as the HelicopterFlight
-- GameMetadata JSON. The rescue's approach begins APPROACH_SEC before
-- its landing time (GameData/Run/Rescue), so that must not exceed the
-- rescue flight; a departure must finish inside every
-- DEPARTED_HELICOPTER_LIFETIME_SEC.
return {
	APPROACH_SEC = 20,
	-- the point over the pad the approach drops from
	APPROACH_HOVER_HEIGHT_STUDS = 40,
	-- how far along the run-in the path keeps its height, as a share of
	-- the flat distance to the pad
	APPROACH_RUN_IN_SHARE = 0.45,
	APPROACH_NOSE_DOWN_DEGREES = 12,
	-- the nose-up flare as it settles
	APPROACH_FLARE_DEGREES = 8,
	-- the last share of the run-in over which the nose comes round toward
	-- the pad's facing
	APPROACH_TURN_IN_SHARE = 0.3,
	-- the last share of the approach spent sinking straight down from the
	-- hover point onto the pad, flaring as it settles
	APPROACH_DESCENT_SHARE = 0.3,
	DEPARTURE_SEC = 24,
	-- straight up this far, taking this long, before the lean forward
	-- (designer, 2026-10-27); the lean has the rest of DEPARTURE_SEC
	DEPARTURE_LIFT_HEIGHT_STUDS = 30,
	DEPARTURE_LIFT_SEC = 6,
	DEPARTURE_DISTANCE_STUDS = 1400,
	DEPARTURE_HEIGHT_STUDS = 260,
	DEPARTURE_NOSE_DOWN_DEGREES = 10,
	DEPARTURE_BANK_DEGREES = 22,
}
