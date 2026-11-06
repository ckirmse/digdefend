--!strict

-- The Gear Locker's rows and cards (M61, 2026-11-06): one row per slot
-- the locker shows (pick axes and jet packs, designer 2026-11-06), each
-- the stock look first, then every catalogue item made for the slot,
-- each marked owned or not and worn or not. The locker sells nothing: a
-- card not owned is shown locked with where it comes from, and the Key
-- Store's published list (KeyStoreRules.Entry) is the one catalogue both
-- read.
local Enums = require(script.Parent.Enums)
local CosmeticLoadoutSchema = require(script.Parent.CosmeticLoadoutSchema)
local KeyStoreRules = require(script.Parent.KeyStoreRules)

local GearLockerRules = {}

export type Card = {
	id: string,
	name: string,
	iconId: string,
	isOwned: boolean,
	isEquipped: boolean,
}

-- the slots the locker lays out, top to bottom
GearLockerRules.LOCKER_SLOTS = {
	Enums.CosmeticSlot.PICK_AXE,
	Enums.CosmeticSlot.JET_PACK,
}

-- what the stock card of each slot is called
GearLockerRules.DEFAULT_NAME = "Standard issue"
GearLockerRules.OWN_HAT_NAME = "Your own hat"

-- the id a slot wears when its loadout entry is empty: the helmet slot
-- shows the player's own hat, any other its stock art
function GearLockerRules.stockIdForSlot(slot: number): string
	return if slot == Enums.CosmeticSlot.HELMET then CosmeticLoadoutSchema.OWN_HAT_ID else CosmeticLoadoutSchema.DEFAULT_SKIN_ID
end

-- the id worn in a slot, the stock one when nothing is saved there
function GearLockerRules.wornIdForSlot(loadout: { [string]: string }, slot: number): string
	local slotName = Enums.getName(Enums.CosmeticSlot, slot)
	local worn = if slotName then loadout[slotName] else nil
	return worn or GearLockerRules.stockIdForSlot(slot)
end

function GearLockerRules.cardsForSlot(
	entries: { KeyStoreRules.Entry },
	owned: { [string]: boolean },
	loadout: { [string]: string },
	slot: number,
	stockIconId: string
): { Card }
	local wornId = GearLockerRules.wornIdForSlot(loadout, slot)
	local stockId = GearLockerRules.stockIdForSlot(slot)
	local cards: { Card } = {
		{
			id = stockId,
			name = if slot == Enums.CosmeticSlot.HELMET then GearLockerRules.OWN_HAT_NAME else GearLockerRules.DEFAULT_NAME,
			iconId = stockIconId,
			isOwned = true,
			isEquipped = wornId == stockId,
		},
	}
	for _, entry in entries do
		if entry.slot ~= slot then
			continue
		end
		table.insert(cards, {
			id = entry.id,
			name = entry.name,
			iconId = entry.iconId,
			isOwned = owned[entry.id] == true,
			isEquipped = wornId == entry.id,
		})
	end
	return cards
end

return GearLockerRules
