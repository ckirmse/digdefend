--!strict

-- Character slots (GDD "Characters", "Character Menu"), M37. Every player
-- has one character; the second slot is bought with Diamonds and every
-- slot after it with Robux only, up to Progression.MAX_CHARACTERS. A slot
-- with no Diamonds price here is a Robux slot. Placeholder prices until
-- the economy is tuned against the earn rate (GDD "Earning Diamonds").
return {
	DIAMOND_PRICE_BY_SLOT = {
		[2] = 300,
	},
	-- the Robux developer product for a slot, created on Roblox for the
	-- game (M40); 0 until it exists, and the menu says the slot is coming
	-- rather than prompting a purchase that cannot be
	ROBUX_PRODUCT_ID = 0,
}
