--!strict

-- The Starter Pack on the client (M79, designer 2026-11-12): the HUD's
-- Starter button under Daily Rewards, shown only until the pack is paid
-- (the HasClaimedStarterPack CurrentPlayer attribute) with its picture
-- wiggling every few seconds, and the StarterPack menu it opens: one card
-- per item (the class card, the Diamonds, the pick axe skin) over a buy
-- button with the pack's worth struck through beside the real Robux
-- price. Everything shown is the StarterPack GameMetadata JSON; the
-- button only asks the server for Roblox's purchase prompt
-- (TryBuyStarterPack). The server pays the contents and the attribute
-- turning true closes the menu and removes the button.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local KeyStoreRules = require("@game/ReplicatedStorage/Shared/KeyStoreRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local StarterPackRules = require("@game/ReplicatedStorage/Shared/StarterPackRules")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local utils = require("@game/ReplicatedStorage/Shared/utils")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientTicker = require(script.Parent.Parent.Client.ClientTicker)

local ClientStarterPackManager = {}
ClientStarterPackManager.__index = ClientStarterPackManager

type View = {
	gui: ScreenGui,
	dialog: GuiObject,
	backButton: GuiButton,
	items: GuiObject,
	buyButton: GuiButton,
	valueLabel: TextLabel,
	priceLabel: TextLabel,
}

export type ClientStarterPackManager = typeof(setmetatable(
	{} :: {
		view: View?,
		overlay: ClientOverlayManager.Overlay?,
		isOpen: boolean,
		hudButton: GuiObject?,
		hudIcon: GuiObject?,
	},
	ClientStarterPackManager
))

-- the HUD button's picture wiggles this often (designer, 2026-11-12)
local WIGGLE_INTERVAL_SEC = 3
local WIGGLE_DEGREES = 15
local WIGGLE_STEP_SEC = 0.08
local WIGGLE_CYCLES = 3
local FEEDBACK_SEC = 5

local STRUCK_FORMAT = "<s>%s</s>"
-- shown in the price tab until Roblox has answered with the price
local PRICE_LOADING_TEXT = "..."
local SKIN_FALLBACK_NAME = "Pick Axe skin"
local FEEDBACK_GRANTED = "Starter Pack unlocked"
local FEEDBACK_GRANTED_KEYS_FORMAT = "Starter Pack unlocked. Items you already had paid +%s"

function ClientStarterPackManager:getOffer(): StarterPackRules.Offer?
	return StarterPackRules.decodeOffer(ClientDataManager:getGameMetadata(Attributes.STARTER_PACK))
end

-- one card: its picture and the line under it
function ClientStarterPackManager:fillItem(view: View, itemName: string, iconId: string?, text: string)
	local card = view.items:FindFirstChild(itemName)
	if not card then
		return
	end
	local icon = card:FindFirstChild(Constants.STARTER_PACK_ITEM_ICON)
	if iconId and icon and icon:IsA("ImageLabel") then
		icon.Image = iconId
	end
	local label = card:FindFirstChild(Constants.STARTER_PACK_ITEM_LABEL)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

function ClientStarterPackManager:render()
	local view = self.view
	local offer = self:getOffer()
	if not view or not self.isOpen or not offer then
		return
	end
	-- the class card this account would get, by the same rule the server
	-- pays by; with every class maxed the card is its worth in Keys
	local classKind = StarterPackRules.pickClassKind(offer.classPriority, ClientDataManager:getClassProgress(), offer.maxSkillSlots)
	if classKind then
		local className = Enums.getPublicName(Enums.ClassKind, classKind) or ""
		self:fillItem(view, Constants.STARTER_PACK_ITEM_CLASS, Icons.CLASS_KIND[classKind], UiStyle.formatTitle(className))
	else
		self:fillItem(view, Constants.STARTER_PACK_ITEM_CLASS, Icons.UI.KEYS, utils.formatWithCommas(offer.keysPerCompleteClass))
	end
	self:fillItem(view, Constants.STARTER_PACK_ITEM_DIAMONDS, Icons.UI.DIAMONDS, utils.formatWithCommas(offer.diamonds))
	-- the skin's name and picture, from the Key Store's one list
	local entries = KeyStoreRules.decode(ClientDataManager:getGameMetadata(Attributes.KEY_STORE_CATALOGUE))
	local skin = if entries then KeyStoreRules.findEntry(entries, offer.cosmeticId) else nil
	self:fillItem(view, Constants.STARTER_PACK_ITEM_COSMETIC, if skin then skin.iconId else nil, UiStyle.formatTitle(if skin then skin.name else SKIN_FALLBACK_NAME))

	view.valueLabel.Text = string.format(STRUCK_FORMAT, UiStyle.ROBUX_GLYPH .. utils.formatWithCommas(offer.valueRobux))
	view.priceLabel.Text = if offer.priceRobux > 0 then UiStyle.ROBUX_GLYPH .. utils.formatWithCommas(offer.priceRobux) else PRICE_LOADING_TEXT
end

function ClientStarterPackManager:openMenu()
	local view = self.view
	local overlay = self.overlay
	if not view or not overlay or self.isOpen or ClientDataManager:hasClaimedStarterPack() then
		return
	end
	-- one menu at a time
	if ClientOverlayManager:isOverlayActive() then
		return
	end
	self.isOpen = true
	view.gui.Enabled = true
	self:render()
	ClientOverlayManager:notifyBeginOverlay(overlay)
end

-- everything a close leaves behind, whoever closed it
function ClientStarterPackManager:cleanUp(view: View)
	self.isOpen = false
	view.gui.Enabled = false
end

function ClientStarterPackManager:closeMenu()
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

-- the button is there only for an account the pack has not been paid to
function ClientStarterPackManager:renderHudButton()
	local button = self.hudButton
	if button then
		button.Visible = not ClientDataManager:hasClaimedStarterPack()
	end
end

-- the picture, not the button, which sits in a list layout
function ClientStarterPackManager:wiggle()
	local button = self.hudButton
	local icon = self.hudIcon
	if not button or not icon or not button.Visible then
		return
	end
	local tweenInfo = TweenInfo.new(WIGGLE_STEP_SEC, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, WIGGLE_CYCLES * 2 - 1, true)
	icon.Rotation = -WIGGLE_DEGREES
	local tween = TweenService:Create(icon, tweenInfo, { Rotation = WIGGLE_DEGREES })
	tween.Completed:Connect(
		function()
			icon.Rotation = 0
		end
	)
	tween:Play()
end

-- the contents landed: the menu goes, with the sound and one line
function ClientStarterPackManager:onGranted(payload: { [string]: any })
	self:closeMenu()
	ClientSoundManager:playSfx(SoundNames.Sfx.SALE_SUCCESS)
	local keys = if typeof(payload.keys) == "number" then payload.keys else 0
	if keys > 0 then
		ClientPlayerFeedbackManager:giveLocal(string.format(FEEDBACK_GRANTED_KEYS_FORMAT, utils.abbreviateNumber(keys)), FEEDBACK_SEC, Icons.UI.KEYS)
	else
		ClientPlayerFeedbackManager:giveLocal(FEEDBACK_GRANTED, FEEDBACK_SEC)
	end
end

function ClientStarterPackManager:findView(playerGui: PlayerGui): View?
	-- waited for, not found: on a live server the client starts before
	-- StarterGui is copied in
	local gui = playerGui:WaitForChild(Constants.STARTER_PACK_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`ClientStarterPackManager: no {Constants.STARTER_PACK_GUI_NAME} ScreenGui; run build_starter_pack_gui`)
		return nil
	end
	local dialog = gui:FindFirstChild(Constants.MENU_DIALOG_FRAME)
	local backButton = dialog and dialog:FindFirstChild(Constants.STARTER_PACK_BACK_BUTTON)
	local items = dialog and dialog:FindFirstChild(Constants.STARTER_PACK_ITEMS)
	local buyButton = dialog and dialog:FindFirstChild(Constants.STARTER_PACK_BUY_BUTTON)
	local valueLabel = buyButton and buyButton:FindFirstChild(Constants.STARTER_PACK_VALUE_LABEL, true)
	local priceLabel = buyButton and buyButton:FindFirstChild(Constants.STARTER_PACK_PRICE_LABEL, true)
	if
		not dialog
		or not backButton
		or not backButton:IsA("GuiButton")
		or not items
		or not buyButton
		or not buyButton:IsA("GuiButton")
		or not valueLabel
		or not valueLabel:IsA("TextLabel")
		or not priceLabel
		or not priceLabel:IsA("TextLabel")
	then
		warn(`ClientStarterPackManager: {Constants.STARTER_PACK_GUI_NAME} is missing parts; see build_starter_pack_gui`)
		return nil
	end
	return {
		gui = gui,
		dialog = dialog :: GuiObject,
		backButton = backButton,
		items = items :: GuiObject,
		buyButton = buyButton,
		valueLabel = valueLabel,
		priceLabel = priceLabel,
	}
end

-- the HUD manager wires the press, since it owns the HUD's buttons
function ClientStarterPackManager:findHudButton(playerGui: PlayerGui)
	local hud = playerGui:WaitForChild(Constants.HUD_GUI_NAME, Constants.GUI_WAIT_SEC)
	local leftButtons = hud and hud:FindFirstChild(Constants.HUD_LEFT_BUTTONS)
	local button = leftButtons and leftButtons:FindFirstChild(Constants.HUD_STARTER_PACK_BUTTON)
	if not button or not button:IsA("GuiObject") then
		warn(`ClientStarterPackManager: the HUD has no {Constants.HUD_STARTER_PACK_BUTTON}; run build_starter_pack_gui`)
		return
	end
	self.hudButton = button
	local icon = button:FindFirstChild(Constants.HUD_MENU_BUTTON_ICON)
	self.hudIcon = if icon and icon:IsA("GuiObject") then icon else nil
end

-- before the HUD, whose Starter button opens this menu
function ClientStarterPackManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	self:findHudButton(playerGui)
	self:renderHudButton()
	local view = self:findView(playerGui)
	if not view then
		return
	end
	self.view = view
	view.gui.Enabled = false
	-- the struck-through worth is rich text
	view.valueLabel.RichText = true

	view.backButton.Activated:Connect(
		function()
			self:closeMenu()
		end
	)
	view.buyButton.Activated:Connect(
		function()
			ClientNetManager:fireServer(NetEventNames.TRY_BUY_STARTER_PACK, {})
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
	}
	self.overlay = overlay

	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.HAS_CLAIMED_STARTER_PACK,
		function()
			self:renderHudButton()
			if ClientDataManager:hasClaimedStarterPack() then
				self:closeMenu()
			end
		end
	)
	-- a class unlocked with the menu open changes which card is on offer
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.CLASS_PROGRESS,
		function()
			self:render()
		end
	)
	-- the price arriving from Roblox with the menu already open
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.STARTER_PACK,
		function()
			self:render()
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_STARTER_PACK_GRANTED,
		function(payload: { [string]: any })
			self:onGranted(payload)
		end
	)
	ClientTicker.every(
		WIGGLE_INTERVAL_SEC,
		function()
			self:wiggle()
		end
	)
end

function ClientStarterPackManager.new(): ClientStarterPackManager
	local self = setmetatable({}, ClientStarterPackManager) :: ClientStarterPackManager
	self.isOpen = false
	return self
end

return ClientStarterPackManager.new()
