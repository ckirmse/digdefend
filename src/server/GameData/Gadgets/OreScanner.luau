--!strict

-- The Ore Scanner, the Prospector's gadget (GDD "Classes", designed
-- 2026-10-15, built 2026-10-22): held in the GADGET slot and used
-- anywhere in the mine. A red sphere sweeps out from the user to
-- RADIUS_STUDS over SWEEP_SEC, and REVEAL_DELAY_SEC after the trigger
-- (designer, 2026-10-22; the end of the sweep before that) every ore
-- block within it, buried or not, is highlighted through the rock by
-- its kind for the whole crew: faded in over FADE_SEC, held for
-- HOLD_SEC, faded out; that is one
-- pulse, and a use runs PULSE_COUNT of them back to back (one, held
-- 10 s; two short ones were tried the same day). Then a cooldown
-- of COOLDOWN_SEC (designer, 2026-10-22; once a day for an hour before
-- that). No upgrades (designer, 2026-10-22: a utility gadget stays
-- fixed). Every number is a first guess until the Prospector is played
-- with it.
return {
	COOLDOWN_SEC = 300,
	RADIUS_STUDS = 30,
	SWEEP_SEC = 1.2,
	REVEAL_DELAY_SEC = 0.5,
	HOLD_SEC = 10,
	FADE_SEC = 0.6,
	PULSE_COUNT = 1,
}
