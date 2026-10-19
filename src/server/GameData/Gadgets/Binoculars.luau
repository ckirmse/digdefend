--!strict

-- The Binoculars, the Sniper's gadget (GDD "Classes", 2026-10-19): fused
-- with the Railgun post (decided the same day; a tool-slot gadget cost
-- the Sniper their firing time). While manning the post, the aim button
-- tags the monster under the Railgun's reticle without interrupting the
-- charge. A tagged monster wears a callout every player sees ("TAGGED BY
-- <name>"), shows on the Camp Map and the compass, and takes more damage
-- from every player, Tower, and turret while the tag lasts. One tag per
-- Sniper; a new tag replaces the old. No upgrades: a flat multiple grows
-- with the crew's own damage. Every number is a first guess until played.
return {
	-- how long a tag lasts, and what the tagged monster takes
	TAG_SEC = 10,
	DAMAGE_MULTIPLIER = 1.3,
	-- a wasted tag costs this long before the next: a tag is a call the
	-- Sniper commits to, not a cursor (10 s, decided 2026-10-19, from 3)
	COOLDOWN_SEC = 10,
	-- how far a tag reaches: the whole camp from the post
	RANGE_STUDS = 600,
	-- how far from the post's muzzle the server lets the look ray start:
	-- the post camera sits a little above the barrel, the rest is latency
	ORIGIN_TOLERANCE_STUDS = 12,
}
