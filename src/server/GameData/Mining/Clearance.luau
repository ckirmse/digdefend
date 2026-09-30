--!strict

-- The headroom a character needs (GDD "Mining", decided 2026-09-29). Only
-- an R15 character's torso collides; its head and limbs do not, so it
-- squeezed through a one-block (4-stud) hole with its head inside the rock
-- above and the camera looking into the unrendered mine. An invisible
-- collider welded to the head stands in for it, so a passage has to be
-- two blocks tall. Its top sits about LIFT_STUDS above the head's centre
-- plus half of HEIGHT_STUDS, about 5.7 studs above the feet on a default
-- R15, over a block's 4 and under two blocks' 8.
return {
	WIDTH_STUDS = 1.5,
	HEIGHT_STUDS = 2,
	LIFT_STUDS = 0.5,
}
