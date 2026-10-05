--!strict

-- The one place Robux developer products are handled (M32; M40 adds the
-- store's products to it). Roblox calls ProcessReceipt once per purchase,
-- and again later for any receipt it was not told was granted, possibly
-- in another server. So: the receipt's purchase id is recorded in the
-- buyer's save (PlayerData) and saved at once, and a receipt whose id is
-- already there is answered without granting again. A manager registers
-- the handler for its product id; a handler must never refuse (the Robux
-- is already spent), so one that cannot do what was bought keeps a credit
-- for the buyer instead. Until a place registers its own handler, the
-- three revive products simply become revive credits, so a receipt that
-- arrives in the lobby is still honoured.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local RevivesData = require("@game/ServerScriptService/GameData/Run/Revives")

local PurchaseManager = {}
PurchaseManager.__index = PurchaseManager

export type ProductHandler = (player: Player, productId: number) -> ()
export type PromptFinishedHandler = (player: Player, productId: number, isPurchased: boolean) -> ()

export type PurchaseManager = typeof(setmetatable(
	{} :: {
		handlerByProductId: { [number]: ProductHandler },
		promptFinishedHandlers: { PromptFinishedHandler },
		-- Robux prices read from Roblox, kept so a button's price is asked for once
		priceByProductId: { [number]: number },
	},
	PurchaseManager
))

local gameController: any -- prevent circular reference by not initializing here

-- the latest registration for a product id wins, so a place can take a
-- product over from the common default
function PurchaseManager:registerProduct(productId: number, handler: ProductHandler)
	self.handlerByProductId[productId] = handler
end

-- told when a purchase prompt closes, bought or not; a cancelled prompt
-- never reaches ProcessReceipt, so this is how a manager forgets what the
-- prompt was for
function PurchaseManager:subscribePromptFinished(handler: PromptFinishedHandler)
	table.insert(self.promptFinishedHandlers, handler)
end

-- opens Roblox's purchase prompt on the player's screen; the result
-- arrives through ProcessReceipt
function PurchaseManager:prompt(player: Player, productId: number)
	local isSuccess, err = pcall(
		function()
			MarketplaceService:PromptProductPurchase(player, productId)
		end
	)
	if not isSuccess then
		warn(`PurchaseManager: could not prompt product {productId} for {player.Name}: {err}`)
	end
end

-- the product's live Robux price, or nil when Roblox cannot say; yields
-- the first time a product is asked about
function PurchaseManager:fetchPriceRobux(productId: number): number?
	local known = self.priceByProductId[productId]
	if known then
		return known
	end
	local isSuccess, info = pcall(
		function()
			return MarketplaceService:GetProductInfoAsync(productId, Enum.InfoType.Product)
		end
	)
	local price = if isSuccess and typeof(info) == "table" then info.PriceInRobux else nil
	if typeof(price) ~= "number" then
		warn(`PurchaseManager: no price for product {productId} ({if isSuccess then "no PriceInRobux" else tostring(info)})`)
		return nil
	end
	self.priceByProductId[productId] = price
	return price
end

function PurchaseManager:processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	local playerData = if player then gameController:getPlayerData(player) else nil
	if not player or not playerData then
		-- the buyer has left or is still loading; Roblox sends the receipt again
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receiptInfo.PurchaseId)
	if playerData:hasProcessedPurchase(purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local productId = receiptInfo.ProductId
	local handler = self.handlerByProductId[productId]
	if not handler then
		warn(`PurchaseManager: no handler for product {productId} bought by {player.Name}; left for a later receipt`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local isSuccess, err = pcall(handler, player, productId)
	if not isSuccess then
		warn(`PurchaseManager: handler error for product {productId} bought by {player.Name}: {err}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	playerData:addProcessedPurchase(purchaseId)
	playerData:saveNow()
	print(`[PurchaseManager] granted product {productId} to {player.Name} (purchase {purchaseId}, {tostring(receiptInfo.CurrencySpent)} Robux)`)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function PurchaseManager:init(gameControllerIn: any)
	gameController = gameControllerIn
	for reviveKind, productId in RevivesData.PRODUCT_ID_BY_KIND :: { [number]: number } do
		self:registerProduct(
			productId,
			function(player: Player, _productId: number)
				local playerData = gameController:getPlayerData(player)
				if not playerData then
					error("buyer is not Ready")
				end
				playerData:addReviveCredit(reviveKind)
				print(`[PurchaseManager] {player.Name} keeps a {Enums.getPublicName(Enums.ReviveKind, reviveKind)} credit`)
			end
		)
	end
	MarketplaceService.ProcessReceipt = function(receiptInfo: any): Enum.ProductPurchaseDecision
		return self:processReceipt(receiptInfo)
	end
	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, productId: number, isPurchased: boolean)
			local player = Players:GetPlayerByUserId(userId)
			if not player then
				return
			end
			for _, handler in self.promptFinishedHandlers do
				handler(player, productId, isPurchased)
			end
		end
	)
end

function PurchaseManager.new(): PurchaseManager
	local self = setmetatable({}, PurchaseManager) :: PurchaseManager
	self.handlerByProductId = {}
	self.promptFinishedHandlers = {}
	self.priceByProductId = {}
	return self
end

return PurchaseManager.new()
