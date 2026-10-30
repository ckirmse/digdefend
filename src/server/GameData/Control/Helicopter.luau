--!strict

-- The helicopters' flight (M75), both places: the shape and timing of an
-- approach onto a pad and a departure from one, sampled by the clients
-- from pure HelicopterFlightRules (the same fields as its Config).
-- HelicopterManager publishes this table once as the HelicopterFlight
-- GameMetadata JSON. The approach is the departure flown backwards
-- (designer, 2026-10-27; the rescue's comes back up the start's own exit,
-- straight down the canyon), so the DEPARTURE_* shape is both paths. The
-- rescue's approach begins APPROACH_SEC before its landing time
-- (GameData/Run/Rescue, which must agree), so that must not exceed the
-- rescue flight; a departure must finish inside every
-- DEPARTED_HELICOPTER_LIFETIME_SEC.
return {
	-- the whole way in from the far end of the departure path (20 before
	-- the path grew with the doubled departure speed, 2026-10-27)
	APPROACH_SEC = 30,
	APPROACH_NOSE_DOWN_DEGREES = 12,
	-- the nose-up flare as it settles
	APPROACH_FLARE_DEGREES = 8,
	-- the first share of the descent over which the nose comes round
	-- toward the pad's facing, hovering (the turn came over the run-in's
	-- end before, too early for the designer, 2026-10-27)
	APPROACH_TURN_IN_SHARE = 0.6,
	-- the last share of the approach spent sinking straight down the
	-- departure's lift onto the pad, flaring as it settles
	APPROACH_DESCENT_SHARE = 0.3,
	-- the lift plus the lean's 14.4 s (24 before the lean's ramp was
	-- shortened, 2026-10-27)
	DEPARTURE_SEC = 20.4,
	-- straight up this far, taking this long, before the lean forward
	-- (designer, 2026-10-27: 6 s, then 30% quicker at 4.6, then 30%
	-- longer again for the rescue's rise); the lean has the rest
	DEPARTURE_LIFT_HEIGHT_STUDS = 30,
	DEPARTURE_LIFT_SEC = 6,
	-- the lean is at full speed this long after it begins and holds it
	-- (designer, 2026-10-27: 2 s looked too fast, so 10), full being about
	-- twice the top speed it first had
	DEPARTURE_RAMP_SEC = 10,
	-- 1400 by 260 before 2026-10-27; the far end pushed out so the lean
	-- ends there at its doubled speed
	DEPARTURE_DISTANCE_STUDS = 1960,
	DEPARTURE_HEIGHT_STUDS = 350,
	DEPARTURE_NOSE_DOWN_DEGREES = 10,
	-- the departure's turn to its heading is a hovering one over the lift
	-- (designer, 2026-10-30; the bank into the lean's turn went with it)
}
