--!strict

-- The class gacha (GDD "Class Unlock System", M70, designed 2026-11-02):
-- the one loot box, rolled with Diamonds, whose pool holds every
-- launch class, the free Recruit included since 2026-11-05, every cosmetic in the catalogue, and Keys. A class result
-- steps that class forward (the class itself, then skill slots 1 to 3, in
-- order) and pays Keys once the class is complete; a duplicate cosmetic
-- pays Keys too. Classes and skill slots come only from the gacha; Keys
-- buy cosmetics by name (M61). Every number here is a placeholder until
-- the economy is tuned against the Diamonds earn rate ("Earning Diamonds").
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	-- what one roll costs
	ROLL_PRICE_DIAMONDS = 100,
	-- the relative weight of each kind of result in the pool; a kind with
	-- nothing to draw (no cosmetics in the catalogue yet) drops out and the
	-- rest share its odds. Within a kind every entry is equally likely
	POOL_WEIGHTS = {
		CLASS = 60,
		COSMETIC = 30,
		KEYS = 10,
	},
	-- Keys paid when the result is Keys outright
	KEYS_PER_KEYS_RESULT = 1,
	-- Keys paid for a class roll once that class and its three skill slots
	-- are all unlocked (the long-term player's steady road to cosmetics)
	KEYS_PER_COMPLETE_CLASS = 2,
	-- Keys paid for a cosmetic the player already owns
	KEYS_PER_DUPLICATE_COSMETIC = 1,
	-- the skill slots a class opens, one roll each after the class itself
	MAX_SKILL_SLOTS = 3,
	-- a player PolicyService reports as restricted from paid random items
	-- cannot roll (Diamonds are bought with Robux, so the gacha counts as
	-- one); they buy a class outright at this Diamonds price instead
	-- (decided 2026-11-02), the class arriving with no skill slots as a
	-- rolled one does. Their skill slots are the parked part of M56
	DIRECT_CLASS_PRICE_DIAMONDS = 400,
	-- the rest of the restricted player's road (designer, 2026-11-10): with
	-- no crate to draw a duplicate from, a tier (the next skill slot) is
	-- bought outright, the price of opening slot 1, 2, 3 in order; and a
	-- cosmetic, which the crate would have drawn or Keys bought (Keys
	-- only come from crates), is bought for Diamonds by its rarity.
	-- Placeholders like every number here
	DIRECT_UPGRADE_PRICE_DIAMONDS_BY_SLOT = { 400, 600, 800 },
	-- the restricted player's store rotates (designer, 2026-11-10): this
	-- many class cards and this many cosmetics on sale at a time, the
	-- same for everyone, changed every INTERVAL_SEC. A class card is the
	-- next step of that class (the class itself, then its tiers), at the
	-- prices above; nothing is on sale two days running while a shelf
	-- holds two days' worth or more (pure DailyStoreRules). Four cards
	-- every eight hours since the evening of 2026-11-10 (three a day
	-- before); a "day" in the rules is one interval, so the one card per
	-- class limit lifts at each change too
	DAILY_STORE = {
		CLASS_COUNT = 2,
		COSMETIC_COUNT = 2,
		INTERVAL_SEC = 28800,
	},
	DIRECT_COSMETIC_PRICE_DIAMONDS_BY_RARITY = {
		[Enums.Rarity.COMMON] = 200,
		[Enums.Rarity.UNCOMMON] = 300,
		[Enums.Rarity.RARE] = 500,
		[Enums.Rarity.EPIC] = 800,
		[Enums.Rarity.LEGENDARY] = 1200,
	},
	-- classes never in the pool. The Recruit was here until 2026-11-05: a
	-- free player could then never open their own class's perk slots, so
	-- its card is drawn like any other owned class (a tier up at once)
	EXCLUDED_KINDS = {},
}
