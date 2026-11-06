--!strict

-- The Key Store menu (GDD "Class Unlock System", Keys; M61, 2026-11-05):
-- every cosmetic the game sells, each a card with its picture and name in
-- the scrolling grid on the left, and on the right a slim info panel for
-- the picked one: its picture, name, slot, and BUY with the Keys price,
-- or EQUIP once it is owned (EQUIPPED on the one worn). Everything drawn
-- is replicated already: the list is the KeyStoreCatalogue GameMetadata,
-- what is owned and the Keys balance are the gacha's CurrentPlayer
-- attributes, and what is worn is the Cosmetics attribute. The menu sends
-- only TryBuyCosmetic and TrySetCosmetic; a buy the Keys cannot cover is
-- refused here first (the fail sound and a line) and never sent.
-- NotifyCosmeticBought is the cue for the purchase sound; the redraw comes
-- from the attributes changing. Opened from the crate menu's KEY STORE
-- button (designer, 2026-11-06; the stall's choice screen for a day
-- before that): Keys are the crate's change, so they are spent beside it.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local KeyStoreRules = require("@game/ReplicatedStorage/Shared/KeyStoreRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local utils = require("@game/ReplicatedStorage/Shared/utils")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientKeyStoreManager = {}
ClientKeyStoreManager.__index = ClientKeyStoreManager

type View = {
	gui: ScreenGui,
	dialog: GuiObject,
	backButton: GuiButton,
	keysLabel: TextLabel,
	itemList: GuiObject,
	itemTemplate: GuiButton,
	infoPanel: GuiObject,
	infoIcon: ImageLabel,
	infoName: TextLabel,
	infoSlot: TextLabel,
	infoHint: TextLabel,
	buyButton: GuiButton,
	priceLabel: TextLabel,
	equipButton: GuiButton,
}

export type ClientKeyStoreManager = typeof(setmetatable(
	{} :: {
		view: View?,
		overlay: ClientOverlayManager.Overlay?,
		isOpen: boolean,
		-- the item the info panel shows, nil before a pick
		selectedId: string?,
		-- the card buttons' connections, dropped with the cards
		cardConnections: { RBXScriptConnection },
	},
	ClientKeyStoreManager
))

local EQUIP_TEXT = "Equip"
local EQUIPPED_TEXT = "Equipped"
local SHORT_TEXT = "You don't have enough Keys"
-- the designer's black word on a plate
local PLATE_WORD_COLOR = Color3.new(0, 0, 0)

local function setLabel(parent: Instance, name: string, text: string, color: Color3?)
	local label = parent:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		label.Text = text
		if color then
			label.TextColor3 = color
		end
	end
end

local function setImage(parent: Instance, name: string, image: string)
	local label = parent:FindFirstChild(name)
	if label and label:IsA("ImageLabel") then
		label.Image = image
	end
end

local function setVisible(parent: Instance, name: string, isVisible: boolean)
	local child = parent:FindFirstChild(name)
	if child and child:IsA("GuiObject") then
		child.Visible = isVisible
	end
end

local function clearCards(panel: GuiObject, template: GuiObject)
	for _, child in panel:GetChildren() do
		if child:IsA("GuiObject") and child ~= template then
			child:Destroy()
		end
	end
end

function ClientKeyStoreManager:getCatalogue(): { KeyStoreRules.Entry }?
	return KeyStoreRules.decode(ClientDataManager:getGameMetadata(Attributes.KEY_STORE_CATALOGUE))
end

function ClientKeyStoreManager:isOwned(id: string): boolean
	return ClientDataManager:getOwnedCosmetics()[id] == true
end

-- whether the item is the one worn in its slot
function ClientKeyStoreManager:isEquipped(entry: KeyStoreRules.Entry): boolean
	local slotName = Enums.getName(Enums.CosmeticSlot, entry.slot)
	if not slotName then
		return false
	end
	return ClientDataManager:getCosmetics()[slotName] == entry.id
end

function ClientKeyStoreManager:dropCardConnections()
	for _, connection in self.cardConnections do
		connection:Disconnect()
	end
	table.clear(self.cardConnections)
end

function ClientKeyStoreManager:select(id: string)
	self.selectedId = id
	self:renderInfo()
end

-- the buy is judged here first so a short balance never makes a round
-- trip; the server judges it again on the saved state
function ClientKeyStoreManager:requestBuy()
	local id = self.selectedId
	local catalogue = self:getCatalogue()
	if not id or not catalogue then
		return
	end
	local refusal = KeyStoreRules.buyRefusal(catalogue, ClientDataManager:getOwnedCosmetics(), ClientDataManager:getKeys(), id)
	if refusal == "short" then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:alertLocal(SHORT_TEXT)
		return
	elseif refusal ~= nil then
		return
	end
	ClientNetManager:fireServer(NetEventNames.TRY_BUY_COSMETIC, { cosmeticId = id })
end

function ClientKeyStoreManager:requestEquip()
	local id = self.selectedId
	local catalogue = self:getCatalogue()
	local entry = if id and catalogue then KeyStoreRules.findEntry(catalogue, id) else nil
	if not entry or not self:isOwned(entry.id) or self:isEquipped(entry) then
		return
	end
	ClientNetManager:fireServer(NetEventNames.TRY_SET_COSMETIC, { slot = entry.slot, skinId = entry.id })
end

function ClientKeyStoreManager:renderCard(view: View, entry: KeyStoreRules.Entry, order: number)
	local card = view.itemTemplate:Clone()
	card.Name = entry.id
	card.LayoutOrder = order
	card.Visible = true
	setImage(card, Constants.KEY_STORE_ITEM_ICON, entry.iconId)
	setLabel(card, Constants.KEY_STORE_ITEM_NAME_LABEL, entry.name)
	setVisible(card, Constants.KEY_STORE_ITEM_OWNED_LABEL, self:isOwned(entry.id))
	-- the picked card is lit; the rest sit on the slot colour
	card.BackgroundColor3 = if entry.id == self.selectedId then UiStyle.PANEL_COLOR else UiStyle.EMPTY_SLOT_COLOR
	table.insert(
		self.cardConnections,
		card.Activated:Connect(
			function()
				self:select(entry.id)
			end
		)
	)
	card.Parent = view.itemList
end

-- the info panel for the picked item: BUY with the price for one not
-- owned, EQUIP for one owned, EQUIPPED on a clear plate for the one worn
function ClientKeyStoreManager:renderInfo()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	local catalogue = self:getCatalogue()
	local entry = if self.selectedId and catalogue then KeyStoreRules.findEntry(catalogue, self.selectedId) else nil
	local isPicked = entry ~= nil
	view.infoHint.Visible = not isPicked
	view.infoIcon.Visible = isPicked
	view.infoName.Visible = isPicked
	view.infoSlot.Visible = isPicked
	if not entry then
		view.buyButton.Visible = false
		view.equipButton.Visible = false
		return
	end
	view.infoIcon.Image = entry.iconId
	view.infoName.Text = UiStyle.formatTitle(entry.name)
	view.infoSlot.Text = Enums.getPublicName(Enums.CosmeticSlot, entry.slot) or "?"
	local isOwned = self:isOwned(entry.id)
	view.buyButton.Visible = not isOwned
	view.equipButton.Visible = isOwned
	if not isOwned then
		view.priceLabel.Text = utils.formatWithCommas(entry.priceKeys)
		-- a price the Keys do not cover reads red, the plate still live so
		-- the tap can say why
		view.priceLabel.TextColor3 = if ClientDataManager:getKeys() >= entry.priceKeys then UiStyle.TEXT_COLOR else UiStyle.NEGATIVE_COLOR
		return
	end
	local isEquipped = self:isEquipped(entry)
	local word = if isEquipped then EQUIPPED_TEXT else EQUIP_TEXT
	setLabel(view.equipButton, Constants.EQUIP_BUTTON_LABEL, UiStyle.formatTitle(word), if isEquipped then UiStyle.POSITIVE_COLOR else PLATE_WORD_COLOR)
	if view.equipButton:IsA("ImageButton") then
		view.equipButton.ImageTransparency = if isEquipped then 1 else 0
	end
	view.equipButton.AutoButtonColor = not isEquipped

	for _, card in view.itemList:GetChildren() do
		if card:IsA("GuiObject") and card ~= view.itemTemplate then
			card.BackgroundColor3 = if card.Name == entry.id then UiStyle.PANEL_COLOR else UiStyle.EMPTY_SLOT_COLOR
		end
	end
end

function ClientKeyStoreManager:render()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	view.keysLabel.Text = utils.formatWithCommas(ClientDataManager:getKeys())
	self:dropCardConnections()
	clearCards(view.itemList, view.itemTemplate)
	local catalogue = self:getCatalogue()
	if not catalogue then
		warn("ClientKeyStoreManager: no catalogue in GameMetadata yet")
		return
	end
	for order, entry in catalogue do
		self:renderCard(view, entry, order)
	end
	self:renderInfo()
end

function ClientKeyStoreManager:openMenu()
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
	self.selectedId = nil
	view.gui.Enabled = true
	self:render()
	ClientOverlayManager:notifyBeginOverlay(overlay)
end

function ClientKeyStoreManager:closeMenu()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	self.isOpen = false
	view.gui.Enabled = false
	self:dropCardConnections()
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

function ClientKeyStoreManager:onCosmeticBought()
	-- the lobby authors SaleSuccess for its purchases
	ClientSoundManager:playSfx(SoundNames.Sfx.SALE_SUCCESS)
end

function ClientKeyStoreManager:findView(playerGui: PlayerGui): View?
	-- waited for, not found: on a live server the client starts before
	-- StarterGui is copied in
	local gui = playerGui:WaitForChild(Constants.KEY_STORE_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`ClientKeyStoreManager: no {Constants.KEY_STORE_GUI_NAME} ScreenGui; run build_key_store_gui`)
		return nil
	end
	local function find(parent: Instance?, name: string): Instance?
		return if parent then parent:FindFirstChild(name) else nil
	end
	local dialog = find(gui, Constants.MENU_DIALOG_FRAME)
	local backButton = find(dialog, Constants.KEY_STORE_BACK_BUTTON)
	local wallet = find(dialog, Constants.KEY_STORE_WALLET)
	local keysLabel = find(wallet, Constants.HUD_KEYS_AMOUNT_LABEL)
	local itemList = find(dialog, Constants.KEY_STORE_ITEM_LIST)
	local itemTemplate = find(itemList, Constants.KEY_STORE_ITEM_TEMPLATE)
	local infoPanel = find(dialog, Constants.KEY_STORE_INFO_PANEL)
	local infoIcon = find(infoPanel, Constants.KEY_STORE_INFO_ICON)
	local infoName = find(infoPanel, Constants.KEY_STORE_INFO_NAME_LABEL)
	local infoSlot = find(infoPanel, Constants.KEY_STORE_INFO_SLOT_LABEL)
	local infoHint = find(infoPanel, Constants.KEY_STORE_INFO_HINT_LABEL)
	local buyButton = find(infoPanel, Constants.KEY_STORE_BUY_BUTTON)
	local priceLabel = buyButton and buyButton:FindFirstChild(Constants.KEY_STORE_BUY_PRICE_LABEL, true)
	local equipButton = find(infoPanel, Constants.KEY_STORE_EQUIP_BUTTON)
	if
		not dialog
		or not backButton
		or not keysLabel
		or not itemList
		or not itemTemplate
		or not infoPanel
		or not infoIcon
		or not infoName
		or not infoSlot
		or not infoHint
		or not buyButton
		or not priceLabel
		or not equipButton
	then
		warn(`ClientKeyStoreManager: {Constants.KEY_STORE_GUI_NAME} is missing parts; rerun build_key_store_gui`)
		return nil
	end
	return {
		gui = gui,
		dialog = dialog :: GuiObject,
		backButton = backButton :: GuiButton,
		keysLabel = keysLabel :: TextLabel,
		itemList = itemList :: GuiObject,
		itemTemplate = itemTemplate :: GuiButton,
		infoPanel = infoPanel :: GuiObject,
		infoIcon = infoIcon :: ImageLabel,
		infoName = infoName :: TextLabel,
		infoSlot = infoSlot :: TextLabel,
		infoHint = infoHint :: TextLabel,
		buyButton = buyButton :: GuiButton,
		priceLabel = priceLabel :: TextLabel,
		equipButton = equipButton :: GuiButton,
	}
end

function ClientKeyStoreManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local view = self:findView(playerGui)
	if not view then
		return
	end
	self.view = view
	view.itemTemplate.Visible = false
	view.gui.Enabled = false

	view.backButton.Activated:Connect(
		function()
			self:closeMenu()
		end
	)
	view.buyButton.Activated:Connect(
		function()
			self:requestBuy()
		end
	)
	view.equipButton.Activated:Connect(
		function()
			self:requestEquip()
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
			self:dropCardConnections()
		end,
		notifyClickOutside = function(_overlay)
			self:closeMenu()
		end,
	}
	self.overlay = overlay

	-- the balance, what is owned, and what is worn each redraw the menu
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.KEYS,
		function()
			self:render()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.OWNED_COSMETICS,
		function()
			self:render()
		end
	)
	ClientDataManager:subscribeCosmetics(
		function()
			self:render()
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_COSMETIC_BOUGHT,
		function(_payload: any)
			self:onCosmeticBought()
		end
	)
end

function ClientKeyStoreManager.new(): ClientKeyStoreManager
	local self = setmetatable({}, ClientKeyStoreManager) :: ClientKeyStoreManager
	self.view = nil
	self.overlay = nil
	self.isOpen = false
	self.selectedId = nil
	self.cardConnections = {}
	return self
end

return ClientKeyStoreManager.new()
