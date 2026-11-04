--!strict

-- The Diamond Store menu (GDD "Monetization", M40, 2026-11-03): four
-- Diamonds packs, smallest to largest, each a card with its amount, an
-- optional banner (BEST VALUE and the like), and BUY with the Robux price.
-- Opened by the Diamond Store stall's touch zone (ClientStoreZoneManager)
-- and the HUD's Diamonds wallet. Everything drawn is the
-- DiamondStoreCatalogue GameMetadata the server publishes (republished
-- when the Robux prices arrive, so the cards redraw); the menu sends
-- only TryBuyDiamondPack, and the balance in the wallet is the Diamonds
-- attribute. The purchase itself is Roblox's prompt, raised by the
-- server; NotifyDiamondPackBought is only the cue for the sound.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local DiamondStoreRules = require("@game/ReplicatedStorage/Shared/DiamondStoreRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local utils = require("@game/ReplicatedStorage/Shared/utils")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientDiamondStoreManager = {}
ClientDiamondStoreManager.__index = ClientDiamondStoreManager

type View = {
	gui: ScreenGui,
	dialog: GuiObject,
	backButton: GuiButton,
	diamondLabel: TextLabel,
	packsPanel: GuiObject,
	packTemplate: GuiObject,
}

export type ClientDiamondStoreManager = typeof(setmetatable(
	{} :: {
		view: View?,
		overlay: ClientOverlayManager.Overlay?,
		isOpen: boolean,
	},
	ClientDiamondStoreManager
))

-- a pack whose product is not on Roblox yet, and one whose price has not
-- arrived (0 until Roblox answers; the catalogue is republished then)
local COMING_SOON_TEXT = "Coming soon"
local PRICE_LOADING_TEXT = "..."

local function clearCards(panel: GuiObject, template: GuiObject)
	for _, child in panel:GetChildren() do
		if child:IsA("GuiObject") and child ~= template then
			child:Destroy()
		end
	end
end

function ClientDiamondStoreManager:getCatalogue(): { DiamondStoreRules.PublishedPack }?
	return DiamondStoreRules.decodeCatalogue(ClientDataManager:getGameMetadata(Attributes.DIAMOND_STORE_CATALOGUE))
end

function ClientDiamondStoreManager:requestBuy(pack: DiamondStoreRules.PublishedPack)
	if not DiamondStoreRules.isOnSale(pack) then
		return
	end
	ClientNetManager:fireServer(NetEventNames.TRY_BUY_DIAMOND_PACK, {
		packIndex = pack.index,
	})
end

function ClientDiamondStoreManager:renderCard(view: View, pack: DiamondStoreRules.PublishedPack)
	local card = view.packTemplate:Clone()
	card.Name = pack.id
	card.LayoutOrder = pack.index
	card.Visible = true

	local amountLabel = card:FindFirstChild(Constants.DIAMOND_STORE_PACK_AMOUNT_LABEL)
	if amountLabel and amountLabel:IsA("TextLabel") then
		amountLabel.Text = utils.formatWithCommas(pack.diamonds)
	end

	local banner = card:FindFirstChild(Constants.DIAMOND_STORE_PACK_BANNER)
	if banner and banner:IsA("GuiObject") then
		local bannerText = banner:FindFirstChild(Constants.DIAMOND_STORE_PACK_BANNER_LABEL)
		banner.Visible = pack.banner ~= nil
		if bannerText and bannerText:IsA("TextLabel") and pack.banner then
			bannerText.Text = UiStyle.formatTitle(pack.banner)
		end
	end

	local buyButton = card:FindFirstChild(Constants.DIAMOND_STORE_PACK_BUY_BUTTON)
	if buyButton and buyButton:IsA("GuiButton") then
		local isOnSale = DiamondStoreRules.isOnSale(pack)
		local priceLabel = buyButton:FindFirstChild(Constants.DIAMOND_STORE_PACK_PRICE_LABEL)
		if priceLabel and priceLabel:IsA("TextLabel") then
			if not isOnSale then
				priceLabel.Text = UiStyle.formatTitle(COMING_SOON_TEXT)
			elseif pack.priceRobux <= 0 then
				priceLabel.Text = PRICE_LOADING_TEXT
			else
				priceLabel.Text = UiStyle.ROBUX_GLYPH .. utils.formatWithCommas(pack.priceRobux)
			end
		end
		buyButton.BackgroundColor3 = if isOnSale then UiStyle.ACCENT_COLOR else UiStyle.DISABLED_COLOR
		buyButton.AutoButtonColor = isOnSale
		buyButton.Activated:Connect(
			function()
				self:requestBuy(pack)
			end
		)
	end

	card.Parent = view.packsPanel
end

function ClientDiamondStoreManager:render()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	view.diamondLabel.Text = utils.formatWithCommas(ClientDataManager:getDiamonds())
	clearCards(view.packsPanel, view.packTemplate)
	local catalogue = self:getCatalogue()
	if not catalogue then
		warn("ClientDiamondStoreManager: no catalogue in GameMetadata yet")
		return
	end
	for _, pack in catalogue do
		self:renderCard(view, pack)
	end
end

function ClientDiamondStoreManager:openMenu()
	local view = self.view
	local overlay = self.overlay
	if not view or not overlay or self.isOpen then
		return
	end
	-- one menu at a time: a stall zone entered with another menu up waits
	if ClientOverlayManager:isOverlayActive() then
		return
	end
	self.isOpen = true
	view.gui.Enabled = true
	self:render()
	ClientOverlayManager:notifyBeginOverlay(overlay)
end

function ClientDiamondStoreManager:closeMenu()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	self.isOpen = false
	view.gui.Enabled = false
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

function ClientDiamondStoreManager:onPackBought()
	-- the lobby authors SaleSuccess for its purchases (the gameplay place
	-- has StorePurchase instead)
	ClientSoundManager:playSfx(SoundNames.Sfx.SALE_SUCCESS)
end

function ClientDiamondStoreManager:findView(playerGui: PlayerGui): View?
	-- waited for, not found: on a live server the client starts before
	-- StarterGui is copied in
	local gui = playerGui:WaitForChild(Constants.DIAMOND_STORE_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`ClientDiamondStoreManager: no {Constants.DIAMOND_STORE_GUI_NAME} ScreenGui; run build_diamond_store_gui`)
		return nil
	end
	local dialog = gui:FindFirstChild(Constants.MENU_DIALOG_FRAME)
	local backButton = dialog and dialog:FindFirstChild(Constants.DIAMOND_STORE_BACK_BUTTON)
	local wallet = dialog and dialog:FindFirstChild(Constants.DIAMOND_STORE_WALLET)
	local diamondLabel = wallet and wallet:FindFirstChild(Constants.HUD_DIAMOND_AMOUNT_LABEL)
	local packsPanel = dialog and dialog:FindFirstChild(Constants.DIAMOND_STORE_PACKS)
	local packTemplate = packsPanel and packsPanel:FindFirstChild(Constants.DIAMOND_STORE_PACK_TEMPLATE)
	if not dialog or not backButton or not diamondLabel or not packsPanel or not packTemplate then
		warn(`ClientDiamondStoreManager: {Constants.DIAMOND_STORE_GUI_NAME} is missing parts; rerun build_diamond_store_gui`)
		return nil
	end
	return {
		gui = gui,
		dialog = dialog :: GuiObject,
		backButton = backButton :: GuiButton,
		diamondLabel = diamondLabel :: TextLabel,
		packsPanel = packsPanel :: GuiObject,
		packTemplate = packTemplate :: GuiObject,
	}
end

function ClientDiamondStoreManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local view = self:findView(playerGui)
	if not view then
		return
	end
	self.view = view
	view.packTemplate.Visible = false
	view.gui.Enabled = false

	view.backButton.Activated:Connect(
		function()
			self:closeMenu()
		end
	)

	local overlay: ClientOverlayManager.Overlay
	overlay = {
		getGuiRoot = function(_overlay)
			return view.dialog
		end,
		notifyForceEnd = function(_overlay)
			self.isOpen = false
			view.gui.Enabled = false
		end,
		notifyClickOutside = function(_overlay)
			self:closeMenu()
		end,
	}
	self.overlay = overlay

	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.DIAMONDS,
		function()
			self:render()
		end
	)
	-- the prices land after the first publish
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.DIAMOND_STORE_CATALOGUE,
		function()
			self:render()
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_DIAMOND_PACK_BOUGHT,
		function(_payload: any)
			self:onPackBought()
		end
	)
end

function ClientDiamondStoreManager.new(): ClientDiamondStoreManager
	local self = setmetatable({}, ClientDiamondStoreManager) :: ClientDiamondStoreManager
	self.view = nil
	self.overlay = nil
	self.isOpen = false
	return self
end

return ClientDiamondStoreManager.new()
