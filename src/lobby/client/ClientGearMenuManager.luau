--!strict

-- The Gear Locker (M61, 2026-11-06): where the player dresses their
-- account's cosmetics loadout, worn with every class. No economy lives
-- here: the Supply Crate stall is where cosmetics come from. On the left
-- a copy of the player's own character in a viewport, dressed in the
-- loadout and turned by dragging; on the right one row per slot the
-- locker shows (pick axes, jet packs; designer 2026-11-06): a fixed
-- icon-and-name header beside a sideways-scrolling strip of the slot's
-- cards, the stock look first, then every catalogue item for the slot, a
-- tap on an owned one wearing it (TrySetCosmetic), a locked one answering
-- with where it is found. Everything drawn is replicated already: the
-- list is the KeyStoreCatalogue GameMetadata, what is owned and what is
-- worn are CurrentPlayer attributes; pure GearLockerRules turns them into
-- cards. Opened by the GearSelection stall's touch zone
-- (ClientStoreZoneManager).
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local GearLockerRules = require("@game/ReplicatedStorage/Shared/GearLockerRules")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local KeyStoreRules = require("@game/ReplicatedStorage/Shared/KeyStoreRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local ClientAvatarViewport = require(script.Parent.Parent.Client.ClientAvatarViewport)
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientGearMenuManager = {}
ClientGearMenuManager.__index = ClientGearMenuManager

type View = {
	gui: ScreenGui,
	dialog: GuiObject,
	backButton: GuiButton,
	avatar: ViewportFrame,
	rows: GuiObject,
	rowTemplate: GuiObject,
}

export type ClientGearMenuManager = typeof(setmetatable(
	{} :: {
		view: View?,
		overlay: ClientOverlayManager.Overlay?,
		isOpen: boolean,
		-- the card buttons' connections, dropped on every redraw
		cloneConnections: { RBXScriptConnection },
	},
	ClientGearMenuManager
))

local LOCKED_TEXT = "Found in Supply Crates"
local LOCKED_TEXT_SEC = 2
-- a locked card's picture is dimmed under its lock
local LOCKED_ICON_COLOR = Color3.fromRGB(90, 90, 90)
-- a row's header word is the slot's name in the plural
local ROW_NAME_FORMAT = "%ss"

local function setLabel(parent: Instance, name: string, text: string)
	local label = parent:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		label.Text = text
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

local function clearClones(parent: GuiObject, template: GuiObject)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") and child ~= template then
			child:Destroy()
		end
	end
end

function ClientGearMenuManager:getCatalogue(): { KeyStoreRules.Entry }
	return KeyStoreRules.decode(ClientDataManager:getGameMetadata(Attributes.KEY_STORE_CATALOGUE)) or {}
end

function ClientGearMenuManager:addCloneConnection(connection: RBXScriptConnection)
	table.insert(self.cloneConnections, connection)
end

function ClientGearMenuManager:dropCloneConnections()
	for _, connection in self.cloneConnections do
		connection:Disconnect()
	end
	table.clear(self.cloneConnections)
end

-- a tap on a card: an owned one is worn (the redraw follows the Cosmetics
-- attribute), a locked one says where it comes from
function ClientGearMenuManager:onCardActivated(slot: number, card: GearLockerRules.Card)
	if not card.isOwned then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(LOCKED_TEXT, LOCKED_TEXT_SEC)
		return
	end
	if card.isEquipped then
		return
	end
	ClientNetManager:fireServer(NetEventNames.TRY_SET_COSMETIC, { slot = slot, skinId = card.id })
end

-- the avatar wears the loadout as saved; a change redresses it
function ClientGearMenuManager:renderAvatar(view: View)
	ClientAvatarViewport:fill(view.avatar, {
		cosmetics = ClientDataManager:getCosmetics(),
		isTurning = true,
		isDraggable = true,
	})
end

function ClientGearMenuManager:renderCards(row: Instance, slot: number, catalogue: { KeyStoreRules.Entry })
	local itemList = row:FindFirstChild(Constants.GEAR_MENU_ROW_ITEM_LIST)
	local itemTemplate = itemList and itemList:FindFirstChild(Constants.GEAR_MENU_ITEM_TEMPLATE)
	if not itemList or not itemList:IsA("GuiObject") or not itemTemplate or not itemTemplate:IsA("GuiButton") then
		return
	end
	clearClones(itemList, itemTemplate)
	local stockIconId = Icons.COSMETIC_DEFAULT_SKIN[slot] or Icons.PLACEHOLDER
	local cards = GearLockerRules.cardsForSlot(
		catalogue,
		ClientDataManager:getOwnedCosmetics(),
		ClientDataManager:getCosmetics(),
		slot,
		stockIconId
	)
	for order, card in cards do
		local button = itemTemplate:Clone()
		button.Name = card.id
		button.LayoutOrder = order
		button.Visible = true
		local icon = button:FindFirstChild(Constants.GEAR_MENU_ITEM_ICON)
		if icon and icon:IsA("ImageLabel") then
			icon.Image = card.iconId
			icon.ImageColor3 = if card.isOwned then Color3.new(1, 1, 1) else LOCKED_ICON_COLOR
		end
		setLabel(button, Constants.GEAR_MENU_ITEM_NAME_LABEL, card.name)
		setVisible(button, Constants.GEAR_MENU_ITEM_EQUIPPED_LABEL, card.isEquipped)
		setVisible(button, Constants.GEAR_MENU_ITEM_LOCK_ICON, not card.isOwned)
		-- the worn card is lit; the rest sit on the slot colour
		button.BackgroundColor3 = if card.isEquipped then UiStyle.PANEL_COLOR else UiStyle.EMPTY_SLOT_COLOR
		self:addCloneConnection(
			button.Activated:Connect(
				function()
					self:onCardActivated(slot, card)
				end
			)
		)
		button.Parent = itemList
	end
end

-- one row per locker slot: the header's icon is the slot's stock art and
-- its word the slot's name, then the slot's cards in the strip beside it
function ClientGearMenuManager:renderRows(view: View, catalogue: { KeyStoreRules.Entry })
	clearClones(view.rows, view.rowTemplate)
	for order, slot in GearLockerRules.LOCKER_SLOTS do
		local row = view.rowTemplate:Clone()
		row.Name = Enums.getName(Enums.CosmeticSlot, slot) or tostring(slot)
		row.LayoutOrder = order
		row.Visible = true
		setImage(row, Constants.GEAR_MENU_ROW_ICON, Icons.COSMETIC_DEFAULT_SKIN[slot] or Icons.PLACEHOLDER)
		setLabel(row, Constants.GEAR_MENU_ROW_NAME_LABEL, UiStyle.formatTitle(string.format(ROW_NAME_FORMAT, Enums.getPublicName(Enums.CosmeticSlot, slot) or "?")))
		self:renderCards(row, slot, catalogue)
		row.Parent = view.rows
	end
end

function ClientGearMenuManager:render()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	self:dropCloneConnections()
	self:renderRows(view, self:getCatalogue())
end

function ClientGearMenuManager:openMenu()
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
	self:renderAvatar(view)
	self:render()
	ClientOverlayManager:notifyBeginOverlay(overlay)
end

function ClientGearMenuManager:closeMenu()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	self.isOpen = false
	view.gui.Enabled = false
	self:dropCloneConnections()
	ClientAvatarViewport:clear(view.avatar)
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

function ClientGearMenuManager:findView(playerGui: PlayerGui): View?
	-- waited for, not found: on a live server the client starts before
	-- StarterGui is copied in
	local gui = playerGui:WaitForChild(Constants.GEAR_MENU_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`ClientGearMenuManager: no {Constants.GEAR_MENU_GUI_NAME} ScreenGui; run build_gear_menu_gui`)
		return nil
	end
	local function find(parent: Instance?, name: string): Instance?
		return if parent then parent:FindFirstChild(name) else nil
	end
	local dialog = find(gui, Constants.MENU_DIALOG_FRAME)
	local backButton = find(dialog, Constants.GEAR_MENU_BACK_BUTTON)
	local avatar = find(dialog, Constants.GEAR_MENU_AVATAR)
	local rows = find(dialog, Constants.GEAR_MENU_ROWS)
	local rowTemplate = find(rows, Constants.GEAR_MENU_ROW_TEMPLATE)
	local itemList = find(rowTemplate, Constants.GEAR_MENU_ROW_ITEM_LIST)
	local itemTemplate = find(itemList, Constants.GEAR_MENU_ITEM_TEMPLATE)
	if not dialog or not backButton or not avatar or not avatar:IsA("ViewportFrame") or not rows or not rowTemplate or not itemTemplate then
		warn(`ClientGearMenuManager: {Constants.GEAR_MENU_GUI_NAME} is missing parts; rerun build_gear_menu_gui`)
		return nil
	end
	return {
		gui = gui,
		dialog = dialog :: GuiObject,
		backButton = backButton :: GuiButton,
		avatar = avatar,
		rows = rows :: GuiObject,
		rowTemplate = rowTemplate :: GuiObject,
	}
end

function ClientGearMenuManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local view = self:findView(playerGui)
	if not view then
		return
	end
	self.view = view
	view.rowTemplate.Visible = false
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
			self:dropCloneConnections()
			ClientAvatarViewport:clear(view.avatar)
		end,
		notifyClickOutside = function(_overlay)
			self:closeMenu()
		end,
	}
	self.overlay = overlay

	-- what is worn redresses the avatar and redraws; what is owned redraws
	ClientDataManager:subscribeCosmetics(
		function()
			if self.isOpen then
				self:renderAvatar(view)
			end
			self:render()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.OWNED_COSMETICS,
		function()
			self:render()
		end
	)
end

function ClientGearMenuManager.new(): ClientGearMenuManager
	local self = setmetatable({}, ClientGearMenuManager) :: ClientGearMenuManager
	self.view = nil
	self.overlay = nil
	self.isOpen = false
	self.cloneConnections = {}
	return self
end

return ClientGearMenuManager.new()
