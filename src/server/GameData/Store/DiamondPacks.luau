--!strict

-- Diamonds packs (GDD "Monetization", "Store Menu"; M40, first pass
-- 2026-11-03): the Robux road to Diamonds, sold from the Diamond Store
-- stall in the lobby and the HUD's Diamonds wallet. Listed smallest to
-- largest, which is the order the menu shows them in. The Robux price is
-- never written here: it is read from Roblox through PurchaseManager. A
-- product id of 0 means the product does not exist on Roblox yet, and
-- the menu shows the pack as coming soon instead of prompting a purchase
-- that cannot be. Every amount is a placeholder until the economy is
-- tuned against the earn rate ("Earning Diamonds").
return {
	PACKS = {
		{
			-- names the pack in logs and the purchase record; never shown
			id = "SMALL",
			diamonds = 100,
			productId = 3728013173,
		},
		{
			id = "MEDIUM",
			diamonds = 300,
			productId = 3728013237,
		},
		{
			id = "LARGE",
			diamonds = 700,
			productId = 3728013286,
			-- an optional banner across the top of the card, shown as a
			-- title (caps); leave it out for no banner
			banner = "Popular",
		},
		{
			id = "HUGE",
			diamonds = 1500,
			productId = 3728013341,
			banner = "Best value",
		},
	},
}
