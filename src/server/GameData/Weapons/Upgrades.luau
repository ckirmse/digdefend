--!strict

-- Handheld weapon upgrades (GDD "Weapon Upgrades"), bought at the Weapons
-- Table in the defense building (decided 2026-10-01). Three attributes per
-- weapon, four upgrades each, like a post weapon's menu: upgrade N adds
-- BONUS_PER_LEVEL of the base stat (Ammo rounds to whole rounds) and costs
-- UPGRADE_PRICE_BY_LEVEL[N] Gold Bars. Weapon upgrades are Gold only and
-- never gated by Camp Level (GDD S12). They last the run, like a post's.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

return {
	-- the post ladder (2026-09-29), so the two menus read the same
	UPGRADE_PRICE_BY_LEVEL = { 15, 90, 270, 800 },
	BONUS_PER_LEVEL_BY_ATTRIBUTE = {
		[Enums.WeaponAttribute.DAMAGE] = 0.25,
		-- a fifth of the magazine per level: the Rifle's 5 rounds become 6 / 7 / 8 / 9
		[Enums.WeaponAttribute.AMMO] = 0.2,
		[Enums.WeaponAttribute.RANGE] = 0.2,
	},
	TABLE_PROMPT_ACTION_TEXT = "Upgrade Weapon",
	TABLE_PROMPT_OBJECT_TEXT = "Weapons Table",
	TABLE_PROMPT_MAX_DISTANCE_STUDS = 10,
}
