--!strict

-- The Diamond Store (GDD "Monetization", M40, first pass 2026-11-03):
-- Diamonds packs bought with Robux. The packs are GameData/Store/
-- DiamondPacks; this manager publishes them once as the
-- DiamondStoreCatalogue GameMetadata JSON (the Robux prices filled in
-- from Roblox as they arrive), opens Roblox's purchase prompt on
-- TryBuyDiamondPack, and on the receipt (PurchaseManager, which already
-- makes every receipt idempotent) adds the Diamonds to the save, saves
-- at once, and replicates the balance. The client only ever draws the
-- catalogue and sends the pack index; nothing about the price or the
-- amount is trusted from it.
local DiamondPacksData = require("@game/ServerScriptService/GameData/Store/DiamondPacks")
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local DiamondStoreRules = require("@game/ReplicatedStorage/Shared/DiamondStoreRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local PurchaseManager = require(script.Parent.Parent.Server.PurchaseManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local DiamondStoreManager = {}
DiamondStoreManager.__index = DiamondStoreManager

export type DiamondStoreManager = typeof(setmetatable(
	{} :: {
		packs: { DiamondStoreRules.Pack },
		-- the live Robux price per product, as Roblox answers
		priceByProductId: { [number]: number },
	},
	DiamondStoreManager
))

local BUY_PACK_SHAPE = {
	packIndex = "positiveInteger",
}

local FEEDBACK_COMING_SOON = "That pack is not on sale yet"
local FEEDBACK_BOUGHT_FORMAT = "+%d Diamonds"

function DiamondStoreManager:getNetHandlers()
	return {
		[NetEventNames.TRY_BUY_DIAMOND_PACK] = {
			shape = BUY_PACK_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:buyPack(player, payload.packIndex)
			end,
		},
	}
end

function DiamondStoreManager:publishCatalogue()
	local published = DiamondStoreRules.publish(self.packs, self.priceByProductId)
	SplendidReplicationManager:setGameMetadata(Attributes.DIAMOND_STORE_CATALOGUE, DiamondStoreRules.encodeCatalogue(published))
end

-- asks Roblox for every pack's price (yields per product) and republishes
-- once they are in, so a client that opened the menu early sees them land
function DiamondStoreManager:fetchPrices()
	local isAnyFetched = false
	for _, pack in self.packs do
		if pack.productId == 0 then
			continue
		end
		local price = PurchaseManager:fetchPriceRobux(pack.productId)
		if price then
			self.priceByProductId[pack.productId] = price
			isAnyFetched = true
		end
	end
	if isAnyFetched then
		self:publishCatalogue()
	end
end

function DiamondStoreManager:buyPack(player: Player, packIndex: number)
	if not GameController:getPlayerData(player) then
		return
	end
	local pack = self.packs[packIndex]
	if not pack then
		warn(`DiamondStoreManager: {player.Name} asked for pack {packIndex}, which does not exist`)
		return
	end
	if pack.productId == 0 then
		PlayerFeedbackManager:give(player, FEEDBACK_COMING_SOON)
		return
	end
	PurchaseManager:prompt(player, pack.productId)
end

-- the receipt: the Robux is spent, so the Diamonds are granted whatever
-- else is true, and saved at once so a crash cannot lose a purchase
function DiamondStoreManager:onPackBought(player: Player, pack: DiamondStoreRules.Pack)
	local playerData = GameController:getPlayerData(player)
	if not playerData then
		-- PurchaseManager only hands a receipt to a Ready player's handler
		-- after a load, so this is a race worth hearing about
		warn(`DiamondStoreManager: {player.Name} bought {pack.id} with no PlayerData; left for a later receipt`)
		error("no PlayerData")
	end
	playerData:addDiamonds(pack.diamonds)
	SplendidReplicationManager:replicateDiamonds(player)
	playerData:saveNow()
	PlayerFeedbackManager:give(player, string.format(FEEDBACK_BOUGHT_FORMAT, pack.diamonds))
	NetManager:notifyClient(player, NetEventNames.NOTIFY_DIAMOND_PACK_BOUGHT, {
		diamonds = pack.diamonds,
	})
end

function DiamondStoreManager:init()
	self.packs = DiamondPacksData.PACKS
	local problems = DiamondStoreRules.validatePacks(self.packs)
	if #problems > 0 then
		error("DiamondStoreManager: GameData/Store/DiamondPacks is malformed: " .. table.concat(problems, "; "))
	end
	-- the catalogue goes out at once with prices of 0, which the menu
	-- draws as loading, and again when Roblox answers
	self:publishCatalogue()
	task.spawn(
		function()
			self:fetchPrices()
		end
	)
	for _, pack in self.packs do
		if pack.productId == 0 then
			continue
		end
		PurchaseManager:registerProduct(
			pack.productId,
			function(buyer: Player, _productId: number)
				self:onPackBought(buyer, pack)
			end
		)
	end
	GameController:registerPlaceManager(self)
end

function DiamondStoreManager.new(): DiamondStoreManager
	local self = setmetatable({}, DiamondStoreManager) :: DiamondStoreManager
	self.packs = {}
	self.priceByProductId = {}
	return self
end

return DiamondStoreManager.new()
