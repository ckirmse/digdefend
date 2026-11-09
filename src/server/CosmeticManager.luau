--!strict

-- Business logic for a player's cosmetic loadout (designer, 2026-11-04:
-- one loadout per account, worn with every class; it was a field of each
-- class record before). The record of truth is PlayerData's `cosmetics`
-- map; this manager is the one place that changes it, so every change is
-- followed by SplendidReplicationManager:replicateCosmetics and the
-- client's copy is never stale. The Gear Locker (M61) equips through
-- TrySetCosmetic; the skins are pick axes and jet packs (hats and
-- HatManager went 2026-11-09).
local CosmeticCatalogueData = require("@game/ServerScriptService/GameData/Cosmetics/Catalogue")
local CosmeticLoadoutSchema = require("@game/ReplicatedStorage/Shared/CosmeticLoadoutSchema")
local CosmeticRules = require("@game/ReplicatedStorage/Shared/CosmeticRules")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PlayerData = require(script.Parent.PlayerData)

local CosmeticManager = {}
CosmeticManager.__index = CosmeticManager

export type CosmeticManager = typeof(setmetatable({} :: {}, CosmeticManager))

local gameController: any -- prevent circular reference by not initializing here
local splendidReplicationManager: any

local SET_COSMETIC_SHAPE = {
	slot = { type = "enum", name = "CosmeticSlot" },
	skinId = "string",
}

function CosmeticManager:getNetHandlers()
	return {
		[NetEventNames.TRY_SET_COSMETIC] = {
			shape = SET_COSMETIC_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:setCosmetic(player, payload.slot, payload.skinId)
			end,
		},
	}
end

function CosmeticManager:getPlayerData(player: Player): PlayerData.PlayerData?
	return gameController:getPlayerData(player)
end

-- the live loadout, nil for a player who is not Ready
function CosmeticManager:getLoadout(player: Player): CosmeticLoadoutSchema.Loadout?
	local playerData = self:getPlayerData(player)
	return if playerData then playerData:getCosmetics() else nil
end

-- equips a skin on a cosmetic slot; "" clears the slot. A hat slot takes
-- a catalogue hat or the own-hat marker; any other slot a skin the
-- cosmetics catalogue lists for it. A catalogue item must also be owned
-- (the gacha's and the Key Store's ownedCosmetics set; M61, 2026-11-05):
-- the stock art is everyone's
function CosmeticManager:setCosmetic(player: Player, slot: number, skinId: string): boolean
	local playerData = self:getPlayerData(player)
	if not playerData then
		return false
	end
	local slotName = Enums.getName(Enums.CosmeticSlot, slot)
	if not slotName then
		return false
	end
	if skinId ~= "" then
		if not CosmeticRules.isSkinForSlot(CosmeticCatalogueData.BY_ID, CosmeticLoadoutSchema.DEFAULT_SKIN_ID, slot, skinId) then
			warn(`CosmeticManager: {player.Name} equipped unknown skin {skinId} on {slotName}`)
			return false
		end
		local isEveryones = skinId == CosmeticLoadoutSchema.DEFAULT_SKIN_ID
		if not isEveryones and not playerData:getOwnedCosmetics()[skinId] then
			warn(`CosmeticManager: {player.Name} equipped unowned skin {skinId} on {slotName}`)
			return false
		end
	end
	playerData:getCosmetics()[slotName] = if skinId ~= "" then skinId else nil
	splendidReplicationManager:replicateCosmetics(player)
	playerData:saveNow()
	return true
end

function CosmeticManager:init(gameControllerIn: any, splendidReplicationManagerIn: any)
	gameController = gameControllerIn
	splendidReplicationManager = splendidReplicationManagerIn
end

function CosmeticManager.new(): CosmeticManager
	local self = setmetatable({}, CosmeticManager) :: CosmeticManager
	return self
end

return CosmeticManager.new()
