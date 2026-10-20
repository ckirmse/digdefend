--!strict

-- The Stim Shot, the Ranger's gadget (GDD "Classes", 2026-10-19): an
-- injector in the GADGET tool slot the Ranger uses on themself. One press
-- brings their health up to a share of the maximum (never above it, and
-- never down), makes them invulnerable, and raises their move speed, both
-- for a while; one use per day-night cycle, back at dawn like a lost Auto
-- Turret (decided 2026-10-19). No upgrades (a utility gadget stays
-- fixed). Every number is a first guess until the Ranger is played with it.
return {
	-- health is raised to this share of the maximum; a player above it keeps what they have
	HEAL_TO_SHARE = 0.5,
	-- the move speed multiple, and how long the speed and the invulnerability last
	SPEED_MULTIPLIER = 1.3,
	EFFECT_SEC = 20,
}
