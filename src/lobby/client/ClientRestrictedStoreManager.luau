--!strict

-- The rotating store: what a player restricted from paid random items
-- gets in place of the Supply Crate menu (designer, 2026-11-10). A
-- countdown ("NEW ITEMS IN: 5h 3m 9s") over the few things on
-- sale today, the same for every player: class cards and cosmetics, at
-- least one of each, each a card with its picture, its name, and BUY
-- with the Diamond price. A class card is the next step of its class
-- (the class itself when it is not owned, its next tier when it is, as
-- a crate's card would be), sold once per class per day and reading
-- PURCHASED after; a class with every tier open reads MAXED
-- OUT and a cosmetic already owned reads OWNED, on the card's
-- NotAvailable frame with the buttons hidden.
-- A purchase is shown as a crate opening on exactly what was bought:
-- this menu fades out, ClientGachaMenuManager glides the camera to the
-- crate, the crate opens by itself (no TAP TO OPEN), the card or the
-- skin comes out with the star animation for a tier, and after CLAIM
-- the camera goes back and this menu fades in again. The crate's result
-- message is the server's answer to the buy, so the show cannot run for
-- a purchase that did not happen.
-- Nothing here is random to the buyer and nothing asks the server what
-- it costs: the day's set is the DailyStore GameMetadata (pure
-- DailyStoreRules), the prices are the published gacha config
-- (GachaRules.Config_Published), the cosmetics' names and pictures are
-- the Key Store's catalogue, and what is owned and held are
-- CurrentPlayer attributes. The menu sends TryBuyStoreItem; the server
-- (GachaManager) refuses it for anyone not restricted and for anything
-- not on sale today. A price the Diamonds cannot cover is answered here
-- with the Diamond Store's short-balance flow and never sent.
-- The gui is RestrictedStoreGui (scripts/studio/
-- build_restricted_store_gui.luau, a copy of the live store gui, which
-- is why the inner names are the Key Store's constants). It has no
-- wallet: its overlay keeps the HUD up, whose Diamonds wallet is the
-- balance. ClientGachaMenuManager:openMenu hands a restricted player
-- here, so the Supply Crate stall arrives, and so do the Class Menu's
-- Rotating Store and Upgrade plates. The Gear Locker and the Class Menu
-- are their own menus, and neither sells anything.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local DailyStoreRules = require("@game/ReplicatedStorage/Shared/DailyStoreRules")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local GachaRules = require("@game/ReplicatedStorage/Shared/GachaRules")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local KeyStoreRules = require("@game/ReplicatedStorage/Shared/KeyStoreRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local utils = require("@game/ReplicatedStorage/Shared/utils")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientGuiFade = require(script.Parent.Parent.Client.ClientGuiFade)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientTicker = require(script.Parent.Parent.Client.ClientTicker)
local ClientDiamondStoreManager = require(script.Parent.ClientDiamondStoreManager)

local ClientRestrictedStoreManager = {}
ClientRestrictedStoreManager.__index = ClientRestrictedStoreManager

-- one card on sale: a class card or a cosmetic
type Item = {
	-- the card's instance name: "CLASS:<kind>" or the cosmetic's id
	id: string,
	name: string,
	-- a cosmetic's rarity colour for its name; nil keeps the authored one
	nameColor: Color3?,
	iconId: string,
	classKind: number?,
	cosmetic: KeyStoreRules.Entry?,
}

-- asks ClientGachaMenuManager to open the crate on the next result:
-- hideStore puts this menu away and calls on, onDone brings it back
type PurchaseRevealer = (hideStore: (next: () -> ()) -> (), onDone: () -> ()) -> ()

type View = {
	gui: ScreenGui,
	dialog: GuiObject,
	backButton: GuiButton,
	refreshTimer: TextLabel,
	itemList: GuiObject,
	itemTemplate: GuiButton,
}

export type ClientRestrictedStoreManager = typeof(setmetatable(
	{} :: {
		view: View?,
		overlay: ClientOverlayManager.Overlay?,
		isOpen: boolean,
		-- the cards' button connections, dropped with the cards
		cardConnections: { RBXScriptConnection },
		purchaseRevealer: PurchaseRevealer?,
	},
	ClientRestrictedStoreManager
))

local REFRESH_FORMAT = "NEW ITEMS IN: %s"
-- a class card unlocks a class the player does not own and raises the
-- tier of one they do
local TYPE_CLASS_UNLOCK_TEXT = "CLASS UNLOCK"
local TYPE_CLASS_UPGRADE_TEXT = "CLASS UPGRADE"
-- the card's backing gradients (designer, 2026-11-10): the template
-- carries one per look, tuned in the Explorer, and a card switches on
-- the one for what it holds, a class card the class one and a cosmetic
-- its rarity's
local CLASS_GRADIENT = "ClassGradient"
local GRADIENT_BY_RARITY = {
	[Enums.Rarity.COMMON] = "CommonGradient",
	[Enums.Rarity.UNCOMMON] = "UncommonGradient",
	[Enums.Rarity.RARE] = "RareGradient",
	[Enums.Rarity.EPIC] = "EpicGradient",
	[Enums.Rarity.LEGENDARY] = "LegendaryGradient",
}
-- a cosmetic is named with its rarity, as the Supply Crate names it
local RARITY_NAME_FORMAT = "%s (%s)"
local TYPE_COSMETIC_TEXT = "GEAR COSMETIC"
local REFRESH_TICK_SEC = 1
local BUY_TEXT = "Buy"
local MAXED_TEXT = "Maxed out"
local OWNED_TEXT = "Owned"
local PURCHASED_TEXT = "Purchased"
local CLASS_ID_PREFIX = "CLASS:"
-- the menu's fade out before the crate and in again after the claim
local REVEAL_FADE_SEC = 0.3

local function setLabel(parent: Instance, name: string, text: string)
	local label = parent:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

-- writes the one TextLabel inside a named frame, whatever it is called
local function setFrameText(parent: Instance, frameName: string, text: string, color: Color3?)
	local frame = parent:FindFirstChild(frameName)
	local label = if frame then frame:FindFirstChildWhichIsA("TextLabel") else nil
	if label then
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

function ClientRestrictedStoreManager:setPurchaseRevealer(revealer: PurchaseRevealer)
	self.purchaseRevealer = revealer
end

function ClientRestrictedStoreManager:getConfig(): GachaRules.Config_Published?
	return GachaRules.decodeConfig(ClientDataManager:getGameMetadata(Attributes.GACHA_CONFIG))
end

-- today's set as the server published it; nil before it has arrived
function ClientRestrictedStoreManager:getStore(): DailyStoreRules.Store?
	return DailyStoreRules.decode(ClientDataManager:getGameMetadata(Attributes.DAILY_STORE))
end

-- the cards on sale today, classes first, in the store's own order; an
-- id this client cannot name is left out
function ClientRestrictedStoreManager:getItems(): { Item }
	local store = self:getStore()
	local items: { Item } = {}
	if not store then
		return items
	end
	for _, classId in store.classIds do
		local classKind = Enums.getValueByName(Enums.ClassKind, classId)
		if classKind then
			table.insert(items, {
				id = CLASS_ID_PREFIX .. tostring(classKind),
				name = Enums.getPublicName(Enums.ClassKind, classKind) or "?",
				iconId = (Icons.CLASS_KIND :: { [number]: string })[classKind] or Icons.PLACEHOLDER,
				classKind = classKind,
			})
		end
	end
	local catalogue = KeyStoreRules.decode(ClientDataManager:getGameMetadata(Attributes.KEY_STORE_CATALOGUE)) or {}
	for _, cosmeticId in store.cosmeticIds do
		local entry = KeyStoreRules.findEntry(catalogue, cosmeticId)
		if entry then
			local rarityName = Enums.getPublicName(Enums.Rarity, entry.rarity)
			table.insert(items, {
				id = entry.id,
				name = if rarityName then string.format(RARITY_NAME_FORMAT, entry.name, rarityName) else entry.name,
				nameColor = (UiStyle.RARITY_COLORS :: { [number]: Color3 })[entry.rarity],
				iconId = entry.iconId,
				cosmetic = entry,
			})
		end
	end
	return items
end

-- what the card's button charges and says. A class card: the class's
-- price when it is not owned, its next tier's when it is, MAXED OUT
-- with no price when every tier is open. A cosmetic: its rarity's
-- price, or OWNED with no price
function ClientRestrictedStoreManager:getOffer(item: Item): (number?, string)
	local config = self:getConfig()
	if not config then
		return nil, BUY_TEXT
	end
	if item.classKind then
		-- one card per class per day: a class bought from today's set is
		-- done until the store changes, whatever tier it reached
		local store = self:getStore()
		local classId = Enums.getName(Enums.ClassKind, item.classKind)
		if store and classId and DailyStoreRules.hasBoughtClass(ClientDataManager:getStorePurchases(), store.day, classId) then
			return nil, PURCHASED_TEXT
		end
		local progress = ClientDataManager:getClassProgress()
		if not GachaRules.isClassOwned(progress, item.classKind) then
			return config.directClassPriceDiamonds, BUY_TEXT
		end
		local price = GachaRules.directUpgradePrice(config.directUpgradePriceDiamondsBySlot, progress, item.classKind, config.maxSkillSlots)
		return price, if price then BUY_TEXT else MAXED_TEXT
	end
	local entry = item.cosmetic
	if not entry or ClientDataManager:getOwnedCosmetics()[entry.id] == true then
		return nil, OWNED_TEXT
	end
	return GachaRules.directCosmeticPrice(config.directCosmeticPriceDiamondsByRarity, entry.rarity), BUY_TEXT
end

function ClientRestrictedStoreManager:dropCardConnections()
	for _, connection in self.cardConnections do
		connection:Disconnect()
	end
	table.clear(self.cardConnections)
end

-- this menu fades away for the crate, then calls on
function ClientRestrictedStoreManager:hideForReveal(next: () -> ())
	local view = self.view
	if not view or not self.isOpen then
		next()
		return
	end
	-- the helper puts the authored transparencies back once it is done,
	-- under a menu that is closed by then
	ClientGuiFade.fadeOut(
		view.dialog,
		REVEAL_FADE_SEC,
		function()
			self:closeMenu()
			next()
		end
	)
end

-- the prize is claimed: this menu comes back the way it left
function ClientRestrictedStoreManager:returnFromReveal()
	if self:openMenu() then
		local view = self.view
		if view then
			ClientGuiFade.fadeIn(view.dialog, REVEAL_FADE_SEC)
		end
	end
end

-- judged here first so a short balance never makes a round trip, and a
-- MAXED OUT or OWNED card (no price) does nothing; the server judges it
-- again on the saved state and on today's set
function ClientRestrictedStoreManager:requestBuy(item: Item)
	local price = self:getOffer(item)
	if not price then
		return
	end
	local diamonds = ClientDataManager:getDiamonds()
	if diamonds < price then
		ClientDiamondStoreManager:handleDiamondsShort(price, diamonds)
		return
	end
	local purchaseRevealer = self.purchaseRevealer
	if purchaseRevealer then
		purchaseRevealer(
			function(next: () -> ())
				self:hideForReveal(next)
			end,
			function()
				self:returnFromReveal()
			end
		)
	end
	ClientNetManager:fireServer(NetEventNames.TRY_BUY_STORE_ITEM, {
		classKind = item.classKind,
		cosmeticId = if item.cosmetic then item.cosmetic.id else nil,
	})
end

function ClientRestrictedStoreManager:renderCard(view: View, item: Item, order: number)
	local card = view.itemTemplate:Clone()
	card.Name = item.id
	card.LayoutOrder = order
	card.Visible = true
	-- the card is a frame for its button, not a button to press
	card.AutoButtonColor = false
	setImage(card, Constants.KEY_STORE_ITEM_ICON, item.iconId)
	-- the name and the type each sit in a designer's backing frame, as
	-- that frame's one label (both labels share a name, so each is found
	-- through its frame)
	setFrameText(card, Constants.RESTRICTED_STORE_ITEM_HEADER, item.name, item.nameColor)
	local typeText = TYPE_COSMETIC_TEXT
	if item.classKind then
		local isOwned = GachaRules.isClassOwned(ClientDataManager:getClassProgress(), item.classKind)
		typeText = if isOwned then TYPE_CLASS_UPGRADE_TEXT else TYPE_CLASS_UNLOCK_TEXT
	end
	setFrameText(card, Constants.RESTRICTED_STORE_ITEM_TYPE, typeText)
	local gradientName = if item.cosmetic then (GRADIENT_BY_RARITY :: { [number]: string })[item.cosmetic.rarity] else CLASS_GRADIENT
	for _, child in card:GetChildren() do
		if child:IsA("UIGradient") then
			child.Enabled = child.Name == gradientName
		end
	end
	-- the NotAvailable frame says OWNED; the corner tag would say it twice
	setVisible(card, Constants.KEY_STORE_ITEM_OWNED_LABEL, false)
	local price, word = self:getOffer(item)
	-- nothing to buy (a maxed class, an owned cosmetic): the designer's
	-- NotAvailable frame carries the word and the buttons leave the card
	-- (designer, 2026-11-10; the word sat on an inert Buy plate before)
	local isAvailable = price ~= nil
	local notAvailable = card:FindFirstChild(Constants.RESTRICTED_STORE_NOT_AVAILABLE)
	if notAvailable and notAvailable:IsA("GuiObject") then
		notAvailable.Visible = not isAvailable
		setLabel(notAvailable, Constants.EQUIP_BUTTON_LABEL, UiStyle.formatTitle(word))
	end
	local actions = card:FindFirstChild(Constants.RESTRICTED_STORE_ACTIONS)
	local buyButton = if actions then actions:FindFirstChild(Constants.KEY_STORE_BUY_BUTTON) else nil
	if actions and actions:IsA("GuiObject") then
		actions.Visible = isAvailable
		setVisible(actions, Constants.KEY_STORE_EQUIP_BUTTON, false)
	end
	if not isAvailable or not buyButton or not buyButton:IsA("GuiButton") then
		card.Parent = view.itemList
		return
	end
	buyButton.Visible = true
	setLabel(buyButton, Constants.EQUIP_BUTTON_LABEL, UiStyle.formatTitle(word))
	local priceLabel = buyButton:FindFirstChild(Constants.KEY_STORE_BUY_PRICE_LABEL, true)
	if price and priceLabel and priceLabel:IsA("TextLabel") then
		priceLabel.Text = utils.formatWithCommas(price)
		-- a price the Diamonds do not cover reads red, the plate still
		-- live so the tap can say why
		priceLabel.TextColor3 = if ClientDataManager:getDiamonds() >= price then UiStyle.TEXT_COLOR else UiStyle.NEGATIVE_COLOR
	end
	table.insert(
		self.cardConnections,
		buyButton.Activated:Connect(
			function()
				self:requestBuy(item)
			end
		)
	)
	card.Parent = view.itemList
end

-- the countdown to the next set, written on each redraw and each tick
function ClientRestrictedStoreManager:renderTimer(view: View)
	local store = self:getStore()
	local remaining = if store then store.refreshTime - workspace:GetServerTimeNow() else 0
	view.refreshTimer.Text = string.format(REFRESH_FORMAT, DailyStoreRules.formatRefresh(remaining))
end

function ClientRestrictedStoreManager:render()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	self:dropCardConnections()
	for _, child in view.itemList:GetChildren() do
		if child:IsA("GuiObject") and child ~= view.itemTemplate then
			child:Destroy()
		end
	end
	for order, item in self:getItems() do
		self:renderCard(view, item, order)
	end
	self:renderTimer(view)
end

-- true when the menu is this player's to see: only a player restricted
-- from paid random items shops by name
function ClientRestrictedStoreManager:openMenu(): boolean
	local view = self.view
	local overlay = self.overlay
	if not view or not overlay or self.isOpen or not ClientDataManager:isPaidRandomItemsRestricted() then
		return false
	end
	-- one menu at a time: a stall zone entered with another menu up waits
	if ClientOverlayManager:isOverlayActive() then
		return false
	end
	self.isOpen = true
	view.gui.Enabled = true
	self:render()
	ClientOverlayManager:notifyBeginOverlay(overlay)
	return true
end

-- everything a close leaves behind, whoever closed it
function ClientRestrictedStoreManager:cleanUp(view: View)
	self.isOpen = false
	view.gui.Enabled = false
	self:dropCardConnections()
end

function ClientRestrictedStoreManager:closeMenu()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	self:cleanUp(view)
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

function ClientRestrictedStoreManager:findView(playerGui: PlayerGui): View?
	local gui = playerGui:WaitForChild(Constants.RESTRICTED_STORE_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`ClientRestrictedStoreManager: no {Constants.RESTRICTED_STORE_GUI_NAME} ScreenGui; run build_restricted_store_gui`)
		return nil
	end
	local function find(parent: Instance?, name: string): Instance?
		return if parent then parent:FindFirstChild(name) else nil
	end
	local dialog = find(gui, Constants.MENU_DIALOG_FRAME)
	local backButton = find(dialog, Constants.KEY_STORE_BACK_BUTTON)
	local storePage = find(dialog, Constants.RESTRICTED_STORE_STORE_PAGE)
	local refreshTimer = find(storePage, Constants.RESTRICTED_STORE_REFRESH_TIMER)
	local itemList = find(storePage, Constants.KEY_STORE_ITEM_LIST)
	local itemTemplate = find(itemList, Constants.KEY_STORE_ITEM_TEMPLATE)
	if not dialog or not backButton or not refreshTimer or not refreshTimer:IsA("TextLabel") or not itemList or not itemTemplate then
		warn(`ClientRestrictedStoreManager: {Constants.RESTRICTED_STORE_GUI_NAME} is missing parts; see build_restricted_store_gui`)
		return nil
	end
	return {
		gui = gui,
		dialog = dialog :: GuiObject,
		backButton = backButton :: GuiButton,
		refreshTimer = refreshTimer,
		itemList = itemList :: GuiObject,
		itemTemplate = itemTemplate :: GuiButton,
	}
end

function ClientRestrictedStoreManager:init()
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

	local overlay: ClientOverlayManager.Overlay
	overlay = {
		getGuiRoot = function(_overlay)
			return view.dialog
		end,
		notifyForceEnd = function(_overlay)
			self:cleanUp(view)
		end,
		notifyClickOutside = function(_overlay)
			self:closeMenu()
		end,
		-- the HUD's Diamonds wallet is this menu's balance
		doesKeepHud = function(_overlay)
			return true
		end,
	}
	self.overlay = overlay

	-- the balance, what is owned, and the class progress redraw the cards
	for _, attribute in { Attributes.DIAMONDS, Attributes.OWNED_COSMETICS, Attributes.STORE_PURCHASES } do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			attribute,
			function()
				self:render()
			end
		)
	end
	ClientDataManager:subscribeClasses(
		function()
			self:render()
		end
	)
	-- the day turned: the server published the next set
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.DAILY_STORE,
		function()
			self:render()
		end
	)
	ClientTicker.every(
		REFRESH_TICK_SEC,
		function()
			if self.isOpen then
				self:renderTimer(view)
			end
		end
	)
	-- a player no longer restricted (the dev panel's checkbox) rolls again
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.IS_PAID_RANDOM_ITEMS_RESTRICTED,
		function()
			if not ClientDataManager:isPaidRandomItemsRestricted() then
				self:closeMenu()
			end
		end
	)
end

function ClientRestrictedStoreManager.new(): ClientRestrictedStoreManager
	local self = setmetatable({}, ClientRestrictedStoreManager) :: ClientRestrictedStoreManager
	self.view = nil
	self.overlay = nil
	self.isOpen = false
	self.cardConnections = {}
	self.purchaseRevealer = nil
	return self
end

return ClientRestrictedStoreManager.new()
