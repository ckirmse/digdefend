--!strict

-- Gear stars (GDD "Characters"), M55. A character's weapon, post, and tower
-- each carry 1 to 5 stars, rolled for Diamonds on the sheet (M57). A star
-- adds BONUS_PER_STAR of the base damage per star above 1, so 5 stars is
-- +20%: modest, because it multiplies with the in-run Iron upgrades and
-- Normal must stay winnable with a 1-star character. Stored from M55,
-- applied to stats in M56.
return {
	MIN_STARS = 1,
	MAX_STARS = 5,
	BONUS_PER_STAR = 0.05,
}
