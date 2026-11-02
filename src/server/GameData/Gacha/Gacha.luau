--!strict

-- The class gacha (GDD "Class Unlock System", M70, designed 2026-11-02):
-- the one loot box, rolled with Diamonds, whose pool holds every bought
-- launch class, every cosmetic in the catalogue, and Keys. A class result
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
	-- classes never in the pool: the free one every player starts with
	EXCLUDED_KINDS = {
		Enums.ClassKind.RECRUIT,
	},
}
