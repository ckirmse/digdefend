--!strict

-- Rerolls on the character sheet (GDD "Characters", "Character Menu"),
-- M37. A gear row rolls its stars; a skill row rolls one skill. Every roll
-- is one result the player keeps or undoes, the price spent either way,
-- and the result may be what the row already holds (designer,
-- 2026-10-12). Diamonds is the only reroll currency. Placeholders: flat
-- prices and even odds until M57 designs the odds and whether a price
-- rises with what the row holds.
return {
	GEAR_REROLL_PRICE_DIAMONDS = 10,
	SKILL_REROLL_PRICE_DIAMONDS = 10,
	-- the roll that fills an empty skill slot costs nothing (designer,
	-- 2026-10-12) and applies at once, with no undo, so a free roll can
	-- never be repeated for nothing; every roll after it is paid
	IS_FIRST_SKILL_ROLL_FREE = true,
}
