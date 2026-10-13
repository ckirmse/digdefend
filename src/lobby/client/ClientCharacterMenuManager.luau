--!strict

-- The Character Select Menu (GDD "Character Menu", M37): the lobby HUD's
-- Character button opens it. One card per character the player owns
-- (name, avatar, Rank, Nights Survived), then the next slot to buy as a
-- dark card with an UNLOCK SLOT button. Everything shown is already
-- replicated (the Characters folder, the active id, the Diamonds balance,
-- the slot pricing in GameMetadata); the menu only sends the pick and the
-- buy. A tap on a card opens its sheet; the EQUIP button under a card
-- picks the character to bring, and the picked card says EQUIPPED inside
-- the accent stroke. With one character there is nothing to pick, so no
-- button, word, or stroke shows (designer, 2026-10-13).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local CharacterRules = require("@game/ReplicatedStorage/Shared/CharacterRules")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local utils = require("@game/ReplicatedStorage/Shared/utils")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientAvatarViewport = require(script.Parent.Parent.Client.ClientAvatarViewport)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientCharacterSheetManager = require(script.Parent.ClientCharacterSheetManager)

local ClientCharacterMenuManager = {}
ClientCharacterMenuManager.__index = ClientCharacterMenuManager

type View = {
	gui: ScreenGui,
	dialog: GuiObject,
	backButton: GuiButton,
	diamondLabel: TextLabel,
	cards: GuiObject,
	cardTemplate: GuiObject,
}

export type ClientCharacterMenuManager = typeof(setmetatable(
	{} :: {
		view: View?,
		overlay: ClientOverlayManager.Overlay?,
		isOpen: boolean,
		-- Robux prices read from Roblox, once per product
		robuxPriceByProductId: { [number]: number },
	},
	ClientCharacterMenuManager
))

local NIGHTS_TEXT = "Nights survived: %d"
local UNLOCK_TEXT = "Unlock Slot"
local COMING_SOON_TEXT = "Coming soon"
local SLOT_BOUGHT_MESSAGE = "New character slot unlocked"
local SLOT_BOUGHT_DISPLAY_SEC = 3

-- the Rank the card shows, from the replicated gear and skills and the
-- points table published with the reroll pricing
-- the Rank the card shows and the colour of its band
local function rankOf(character: ClientDataManager.CharacterData): (string, Color3)
	local pricing = CharacterRules.decodeRerollPricing(ClientDataManager:getGameMetadata(Attributes.CHARACTER_REROLL_PRICING))
	if not pricing then
		return "", UiStyle.TEXT_COLOR
	end
	local starsBySlot: { [number]: number } = {}
	for gearSlot, gear in character.gear do
		starsBySlot[gearSlot] = gear.stars
	end
	local skillRarities: { number } = {}
	for _, skill in character.skills do
		table.insert(skillRarities, skill.rarity)
	end
	local rank = CharacterRules.rankOfPricing(starsBySlot, skillRarities, pricing)
	local band = CharacterRules.rankBand(rank, pricing.rankBands)
	return CharacterRules.rankText(rank, pricing.rankBands), UiStyle.RARITY_COLORS[band] or UiStyle.TEXT_COLOR
end

function ClientCharacterMenuManager:getPricing(): CharacterRules.SlotPricing?
	return CharacterRules.decodePricing(ClientDataManager:getGameMetadata(Attributes.CHARACTER_SLOT_PRICING))
end

function ClientCharacterMenuManager:getRobuxPriceText(productId: number): string
	local known = self.robuxPriceByProductId[productId]
	if known then
		return tostring(known)
	end
	task.spawn(
		function()
			local isSuccess, info = pcall(
				function()
					return MarketplaceService:GetProductInfoAsync(productId, Enum.InfoType.Product)
				end
			)
			if isSuccess and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
				self.robuxPriceByProductId[productId] = info.PriceInRobux
				if self.isOpen then
					self:render()
				end
			end
		end
	)
	return "..."
end

function ClientCharacterMenuManager:makeCard(view: View, order: number): GuiObject
	local card = view.cardTemplate:Clone()
	card.Name = "Card" .. tostring(order)
	card.LayoutOrder = order
	card.Visible = true
	card.Parent = view.cards
	return card
end

function ClientCharacterMenuManager:renderOwnedCard(view: View, order: number, character: ClientDataManager.CharacterData, isActive: boolean, hasChoice: boolean)
	local card = self:makeCard(view, order)
	local title = card:FindFirstChild(Constants.CHARACTER_CARD_TITLE) :: TextLabel
	title.Text = UiStyle.formatTitle(character.name)
	local rankLabel = card:FindFirstChild(Constants.CHARACTER_CARD_RANK_LABEL) :: TextLabel
	local rankText, rankColor = rankOf(character)
	rankLabel.Text = UiStyle.formatTitle(rankText)
	rankLabel.TextColor3 = rankColor
	local nightsLabel = card:FindFirstChild(Constants.CHARACTER_CARD_NIGHTS_LABEL) :: TextLabel
	nightsLabel.Text = UiStyle.formatTitle(string.format(NIGHTS_TEXT, character.nightsSurvived))
	local unlockButton = card:FindFirstChild(Constants.CHARACTER_CARD_UNLOCK_BUTTON) :: GuiButton
	unlockButton.Visible = false
	local stroke = card:FindFirstChild(Constants.CHARACTER_CARD_SELECTED_STROKE) :: UIStroke
	stroke.Enabled = isActive and hasChoice
	local equipButton = card:FindFirstChild(Constants.CHARACTER_CARD_EQUIP_BUTTON) :: GuiButton
	equipButton.Visible = hasChoice and not isActive
	local equippedLabel = card:FindFirstChild(Constants.CHARACTER_CARD_EQUIPPED_LABEL) :: TextLabel
	equippedLabel.Visible = hasChoice and isActive
	ClientAvatarViewport:fill(card:FindFirstChild(Constants.CHARACTER_CARD_AVATAR) :: ViewportFrame, false, character.cosmetics)
	equipButton.Activated:Connect(
		function()
			ClientNetManager:fireServer(NetEventNames.TRY_SELECT_CHARACTER, { characterId = character.id })
		end
	)
	local cardButton = card :: GuiButton
	-- a tap opens the sheet; Back on the sheet returns here
	cardButton.Activated:Connect(
		function()
			self:closeMenu()
			ClientCharacterSheetManager:openMenu(character.id)
		end
	)
end

function ClientCharacterMenuManager:renderUnlockCard(view: View, order: number, offer: CharacterRules.SlotOffer)
	local card = self:makeCard(view, order)
	card.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
	local title = card:FindFirstChild(Constants.CHARACTER_CARD_TITLE) :: TextLabel
	title.Text = UiStyle.formatTitle("Character " .. tostring(offer.slot))
	local rankLabel = card:FindFirstChild(Constants.CHARACTER_CARD_RANK_LABEL) :: TextLabel
	rankLabel.Visible = false
	local nightsLabel = card:FindFirstChild(Constants.CHARACTER_CARD_NIGHTS_LABEL) :: TextLabel
	nightsLabel.Visible = false
	local stroke = card:FindFirstChild(Constants.CHARACTER_CARD_SELECTED_STROKE) :: UIStroke
	stroke.Enabled = false
	local equipButton = card:FindFirstChild(Constants.CHARACTER_CARD_EQUIP_BUTTON) :: GuiButton
	equipButton.Visible = false
	local equippedLabel = card:FindFirstChild(Constants.CHARACTER_CARD_EQUIPPED_LABEL) :: TextLabel
	equippedLabel.Visible = false
	ClientAvatarViewport:fill(card:FindFirstChild(Constants.CHARACTER_CARD_AVATAR) :: ViewportFrame, true, nil)

	local unlockButton = card:FindFirstChild(Constants.CHARACTER_CARD_UNLOCK_BUTTON) :: GuiButton
	local unlockLabel = unlockButton:FindFirstChild(Constants.CHARACTER_CARD_UNLOCK_LABEL) :: TextLabel
	local price = unlockButton:FindFirstChild(Constants.CHARACTER_CARD_PRICE_FRAME) :: GuiObject
	local priceLabel = price:FindFirstChild(Constants.CHARACTER_CARD_PRICE_LABEL) :: TextLabel
	local priceIcon = price:FindFirstChild(Constants.CHARACTER_CARD_PRICE_ICON) :: ImageLabel
	unlockButton.Visible = true
	local isAvailable = true
	if offer.currency == Enums.SlotCurrency.DIAMONDS then
		unlockLabel.Text = UiStyle.formatTitle(UNLOCK_TEXT)
		priceLabel.Text = utils.abbreviateNumber(offer.diamonds or 0)
		priceIcon.Image = Icons.UI.DIAMONDS
		priceIcon.Visible = true
	elseif (offer.productId or 0) ~= 0 then
		unlockLabel.Text = UiStyle.formatTitle(UNLOCK_TEXT)
		priceLabel.Text = utf8.char(0xE002) .. " " .. self:getRobuxPriceText(offer.productId :: number)
		priceIcon.Visible = false
	else
		unlockLabel.Text = UiStyle.formatTitle(COMING_SOON_TEXT)
		priceLabel.Text = utf8.char(0xE002)
		priceIcon.Visible = false
		isAvailable = false
	end
	unlockButton.AutoButtonColor = isAvailable
	unlockButton.BackgroundColor3 = if isAvailable then UiStyle.ACCENT_COLOR else UiStyle.DISABLED_COLOR
	unlockButton.Activated:Connect(
		function()
			if isAvailable then
				ClientNetManager:fireServer(NetEventNames.TRY_BUY_CHARACTER_SLOT, {})
			end
		end
	)
end

function ClientCharacterMenuManager:render()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	view.diamondLabel.Text = utils.abbreviateNumber(ClientDataManager:getDiamonds())
	for _, child in view.cards:GetChildren() do
		if child:IsA("GuiObject") and child ~= view.cardTemplate then
			child:Destroy()
		end
	end
	local characters = ClientDataManager:getCharacters()
	local activeId = ClientDataManager:getActiveCharacterId()
	-- a pick only means something between two or more
	local hasChoice = #characters >= 2
	for order, character in characters do
		self:renderOwnedCard(view, order, character, character.id == activeId, hasChoice)
	end
	local pricing = self:getPricing()
	local offer = if pricing then CharacterRules.nextSlotOffer(#characters, pricing) else nil
	if offer then
		self:renderUnlockCard(view, #characters + 1, offer)
	end
end

function ClientCharacterMenuManager:openMenu()
	local view = self.view
	local overlay = self.overlay
	if not view or not overlay or self.isOpen then
		return
	end
	self.isOpen = true
	view.gui.Enabled = true
	self:render()
	ClientOverlayManager:notifyBeginOverlay(overlay)
end

function ClientCharacterMenuManager:closeMenu()
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

function ClientCharacterMenuManager:onSlotBought()
	-- the lobby's purchase sound (the HUD plays it on a spend); StorePurchase
	-- is authored in the gameplay place only
	ClientSoundManager:playSfx(SoundNames.Sfx.SALE_SUCCESS)
	ClientPlayerFeedbackManager:giveLocal(SLOT_BOUGHT_MESSAGE, SLOT_BOUGHT_DISPLAY_SEC)
end

function ClientCharacterMenuManager:findView(playerGui: PlayerGui): View?
	-- waited for, not found: on a live server the client starts before
	-- StarterGui is copied in (2026-10-13)
	local gui = playerGui:WaitForChild(Constants.CHARACTER_SELECT_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`ClientCharacterMenuManager: no {Constants.CHARACTER_SELECT_GUI_NAME} ScreenGui; run build_character_select_gui`)
		return nil
	end
	local dialog = gui:FindFirstChild(Constants.MENU_DIALOG_FRAME)
	local backButton = dialog and dialog:FindFirstChild(Constants.CHARACTER_SELECT_BACK_BUTTON)
	local wallet = dialog and dialog:FindFirstChild(Constants.CHARACTER_SELECT_WALLET)
	local diamondLabel = wallet and wallet:FindFirstChild(Constants.HUD_DIAMOND_AMOUNT_LABEL)
	local cards = dialog and dialog:FindFirstChild(Constants.CHARACTER_SELECT_CARDS)
	local cardTemplate = cards and cards:FindFirstChild(Constants.CHARACTER_SELECT_CARD_TEMPLATE)
	if not dialog or not backButton or not diamondLabel or not cards or not cardTemplate then
		warn(`ClientCharacterMenuManager: {Constants.CHARACTER_SELECT_GUI_NAME} is missing parts; rerun build_character_select_gui`)
		return nil
	end
	return {
		gui = gui,
		dialog = dialog :: GuiObject,
		backButton = backButton :: GuiButton,
		diamondLabel = diamondLabel :: TextLabel,
		cards = cards :: GuiObject,
		cardTemplate = cardTemplate :: GuiObject,
	}
end

function ClientCharacterMenuManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local view = self:findView(playerGui)
	if not view then
		return
	end
	self.view = view
	view.cardTemplate.Visible = false
	view.gui.Enabled = false

	view.backButton.Activated:Connect(
		function()
			self:closeMenu()
		end
	)

	-- the whole screen is the menu, so there is no outside to click
	local overlay: ClientOverlayManager.Overlay
	overlay = {
		getGuiRoot = function(_overlay)
			return view.dialog
		end,
		notifyForceEnd = function(_overlay)
			self.isOpen = false
			view.gui.Enabled = false
		end,
		notifyClickOutside = function(_overlay) end,
	}
	self.overlay = overlay

	ClientCharacterSheetManager:setOnBack(
		function()
			self:openMenu()
		end
	)

	ClientDataManager:subscribeCharacters(
		function()
			self:render()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.DIAMONDS,
		function()
			self:render()
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_CHARACTER_SLOT_BOUGHT,
		function(_payload: any)
			self:onSlotBought()
		end
	)
end

function ClientCharacterMenuManager.new(): ClientCharacterMenuManager
	local self = setmetatable({}, ClientCharacterMenuManager) :: ClientCharacterMenuManager
	self.view = nil
	self.overlay = nil
	self.isOpen = false
	self.robuxPriceByProductId = {}
	return self
end

return ClientCharacterMenuManager.new()
