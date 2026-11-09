--!strict

-- The Key Store (GDD "Class Unlock System", Keys; M61, 2026-11-05): the
-- lobby stall's second menu, where Keys buy a cosmetic by name. Every
-- skin of GameData/Cosmetics/Catalogue and every hat of
-- GameData/Characters/Hats is on sale at its PRICE_KEYS; pure
-- KeyStoreRules builds the list once and this manager publishes it as the
-- KeyStoreCatalogue GameMetadata JSON, so the menu draws without
-- requiring GameData. TryBuyCosmetic spends the Keys first (PlayerData is
-- the record of truth), marks the cosmetic owned in the same
-- ownedCosmetics set the gacha fills, saves at once, replicates through
-- replicateGacha (Keys and owned cosmetics travel together), and tells
-- the buyer with NotifyCosmeticBought for the sound. Equipping what is
-- owned is CosmeticManager's TrySetCosmetic, which checks ownership.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local KeyStoreRules = require("@game/ReplicatedStorage/Shared/KeyStoreRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local CosmeticCatalogueData = require("@game/ServerScriptService/GameData/Cosmetics/Catalogue")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local KeyStoreManager = {}
KeyStoreManager.__index = KeyStoreManager

export type KeyStoreManager = typeof(setmetatable(
	{} :: {
		entries: { KeyStoreRules.Entry },
	},
	KeyStoreManager
))

local BUY_COSMETIC_SHAPE = {
	cosmeticId = "string",
}

local FEEDBACK_KEYS_SHORT = "You don't have enough Keys"
local FEEDBACK_ALREADY_OWNED = "You already own that"
local FEEDBACK_UNKNOWN = "That is not for sale"

function KeyStoreManager:getNetHandlers()
	return {
		[NetEventNames.TRY_BUY_COSMETIC] = {
			shape = BUY_COSMETIC_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:buy(player, payload.cosmeticId)
			end,
		},
	}
end

-- one purchase: the refusal is judged on the saved state, the Keys come
-- off first, and the cosmetic is owned before the client hears of it
function KeyStoreManager:buy(player: Player, cosmeticId: string)
	local playerData = GameController:getPlayerData(player)
	if not playerData then
		return
	end
	local refusal = KeyStoreRules.buyRefusal(self.entries, playerData:getOwnedCosmetics(), playerData:getKeys(), cosmeticId)
	if refusal == "unknown" then
		warn(`KeyStoreManager: {player.Name} asked to buy unknown cosmetic {cosmeticId}`)
		PlayerFeedbackManager:give(player, FEEDBACK_UNKNOWN)
		return
	elseif refusal == "owned" then
		PlayerFeedbackManager:give(player, FEEDBACK_ALREADY_OWNED)
		return
	elseif refusal == "short" then
		PlayerFeedbackManager:give(player, FEEDBACK_KEYS_SHORT)
		return
	end
	local entry = KeyStoreRules.findEntry(self.entries, cosmeticId) :: KeyStoreRules.Entry
	if not playerData:spendKeys(entry.priceKeys) then
		PlayerFeedbackManager:give(player, FEEDBACK_KEYS_SHORT)
		return
	end
	playerData:addOwnedCosmetic(cosmeticId)
	playerData:saveNow()
	SplendidReplicationManager:replicateGacha(player)
	NetManager:notifyClient(player, NetEventNames.NOTIFY_COSMETIC_BOUGHT, { cosmeticId = cosmeticId })
end

function KeyStoreManager:init()
	local problems = KeyStoreRules.validate(CosmeticCatalogueData.BY_ID)
	if #problems > 0 then
		error("KeyStoreManager: a cosmetic has no Keys price: " .. table.concat(problems, "; "))
	end
	self.entries = KeyStoreRules.build(CosmeticCatalogueData.BY_ID, Icons.COSMETIC_SKIN, Icons.PLACEHOLDER)
	-- the list never changes at runtime, so one publish serves every client
	SplendidReplicationManager:setGameMetadata(Attributes.KEY_STORE_CATALOGUE, KeyStoreRules.encode(self.entries))
	GameController:registerPlaceManager(self)
end

function KeyStoreManager.new(): KeyStoreManager
	local self = setmetatable({}, KeyStoreManager) :: KeyStoreManager
	self.entries = {}
	return self
end

return KeyStoreManager.new()
