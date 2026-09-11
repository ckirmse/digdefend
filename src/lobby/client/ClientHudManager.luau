--!strict

-- Drives the Studio-authored lobby HUD (GDD "HUD"): Cash balance with the
-- green/red change flash and sounds, the five loadout slots, and the menu
-- buttons. Slides off screen while a menu (overlay) is open. Menus arrive in
-- later milestones; until then the buttons give "coming soon" feedback.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlayerPublicSchema = require("@game/ReplicatedStorage/Shared/PlayerPublicSchema")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local utils = require("@game/ReplicatedStorage/Shared/utils")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientHudManager = {}
ClientHudManager.__index = ClientHudManager

type HudGroup = {
	frame: GuiObject,
	basePosition: UDim2,
	offscreenPosition: UDim2,
}

type SlotView = {
	slot: number,
	icon: ImageLabel,
}

export type ClientHudManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		cashLabel: TextLabel?,
		lastCash: number?,
		-- bumps per flash so an older restore cannot undo a newer flash
		flashGeneration: number,
		groups: { HudGroup },
		slotViews: { SlotView },
	},
	ClientHudManager
))

local COMING_SOON_MESSAGE = "Coming soon"
local COMING_SOON_DISPLAY_SEC = 2
-- the number changes a beat after the colour and sound so the flash reads as
-- the cause and the new value as the effect
local BALANCE_UPDATE_DELAY_SEC = 0.15

function ClientHudManager:tweenGroup(group: HudGroup, position: UDim2)
	local tweenInfo = TweenInfo.new(UiStyle.HUD_TWEEN_SEC, Enum.EasingStyle.Quad)
	TweenService:Create(group.frame, tweenInfo, { Position = position }):Play()
end

function ClientHudManager:notifyBeginOverlay()
	for _, group in self.groups do
		self:tweenGroup(group, group.offscreenPosition)
	end
end

function ClientHudManager:notifyEndOverlay()
	for _, group in self.groups do
		self:tweenGroup(group, group.basePosition)
	end
end

function ClientHudManager:renderCash(cash: number)
	local label = self.cashLabel
	if label then
		label.Text = utils.abbreviateNumber(cash)
	end
end

-- GDD: an increase turns the text green with the coins sound, a decrease red
-- with the sale sound, then the value updates; the first value never flashes
function ClientHudManager:onCashChanged(cash: number)
	local lastCash = self.lastCash
	self.lastCash = cash
	local label = self.cashLabel
	if not label or lastCash == nil or cash == lastCash then
		self:renderCash(cash)
		return
	end

	self.flashGeneration += 1
	local generation = self.flashGeneration
	if cash > lastCash then
		label.TextColor3 = UiStyle.POSITIVE_COLOR
		ClientSoundManager:playSfx(SoundNames.Sfx.COINS_ADDED)
	else
		label.TextColor3 = UiStyle.NEGATIVE_COLOR
		ClientSoundManager:playSfx(SoundNames.Sfx.SALE_SUCCESS)
	end
	task.delay(
		BALANCE_UPDATE_DELAY_SEC,
		function()
			if self.flashGeneration == generation then
				self:renderCash(cash)
			end
		end
	)
	task.delay(
		UiStyle.BALANCE_FLASH_SEC,
		function()
			if self.flashGeneration == generation then
				label.TextColor3 = UiStyle.TEXT_COLOR
			end
		end
	)
end

function ClientHudManager:renderSlot(view: SlotView)
	local unlockName = ClientDataManager:getLoadoutSlot(view.slot)
	-- unlock icons arrive with the store (M35); an equipped slot shows the
	-- accent colour until then
	if unlockName then
		view.icon.BackgroundColor3 = UiStyle.ACCENT_COLOR
	else
		view.icon.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
	end
end

-- slot icons are the ImageLabels under the strip carrying the LoadoutSlot
-- attribute; the labels beneath are shared (one "Defense" spans three slots)
function ClientHudManager:findSlots(strip: Instance)
	for _, descendant in strip:GetDescendants() do
		local slot = descendant:GetAttribute(Attributes.LOADOUT_SLOT)
		if typeof(slot) ~= "number" or not Enums.isValidValue(Enums.LoadoutSlot, slot) then
			continue
		end
		if not descendant:IsA("ImageLabel") then
			warn(`ClientHudManager: {descendant:GetFullName()} carries {Attributes.LOADOUT_SLOT} but is not an ImageLabel`)
			continue
		end
		local view: SlotView = {
			slot = slot,
			icon = descendant,
		}
		table.insert(self.slotViews, view)
		self:renderSlot(view)
		local attributeName = PlayerPublicSchema.getLoadoutAttribute(slot)
		if attributeName then
			ClientDataManager:subscribeCurrentPlayerAttribute(
				attributeName,
				function()
					self:renderSlot(view)
				end
			)
		end
	end
end

function ClientHudManager:addGroup(frame: GuiObject, offscreenPosition: UDim2)
	table.insert(
		self.groups,
		{
			frame = frame,
			basePosition = frame.Position,
			offscreenPosition = offscreenPosition,
		}
	)
end

function ClientHudManager:wireButton(parent: Instance, name: string, onActivated: () -> ())
	local button = parent:FindFirstChild(name)
	if not button or not button:IsA("GuiButton") then
		warn(`ClientHudManager: {parent:GetFullName()} has no button {name}`)
		return
	end
	button.Activated:Connect(
		function()
			onActivated()
		end
	)
end

function ClientHudManager:giveComingSoon()
	ClientPlayerFeedbackManager:giveLocal(COMING_SOON_MESSAGE, COMING_SOON_DISPLAY_SEC)
end

function ClientHudManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.HUD_GUI_NAME) :: ScreenGui
	gui.ResetOnSpawn = false
	gui.Enabled = true
	self.gui = gui

	local cashWallet = gui:WaitForChild(Constants.HUD_CASH_WALLET) :: GuiObject
	self.cashLabel = cashWallet:WaitForChild(Constants.HUD_CASH_AMOUNT_LABEL) :: TextLabel
	self:addGroup(cashWallet, UDim2.new(-0.5, 0, cashWallet.Position.Y.Scale, 0))
	-- opens the store's currency section once the store exists (M35)
	if cashWallet:IsA("GuiButton") then
		cashWallet.Activated:Connect(
			function()
				self:giveComingSoon()
			end
		)
	end

	local menuButtons = gui:WaitForChild(Constants.HUD_MENU_BUTTONS) :: GuiObject
	self:addGroup(menuButtons, UDim2.new(1.5, 0, menuButtons.Position.Y.Scale, 0))
	for _, name in { Constants.HUD_STORE_BUTTON, Constants.HUD_LOADOUT_BUTTON, Constants.HUD_DAILY_REWARDS_BUTTON } do
		self:wireButton(
			menuButtons,
			name,
			function()
				self:giveComingSoon()
			end
		)
	end

	local loadoutStrip = gui:WaitForChild(Constants.HUD_LOADOUT_STRIP) :: GuiObject
	self:addGroup(loadoutStrip, UDim2.new(loadoutStrip.Position.X.Scale, 0, 1.5, 0))
	self:findSlots(loadoutStrip)

	ClientOverlayManager:addOverlayNotifier(self)

	self:onCashChanged(ClientDataManager:getCash())
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.CASH,
		function()
			self:onCashChanged(ClientDataManager:getCash())
		end
	)
end

function ClientHudManager.new(): ClientHudManager
	local self = setmetatable({}, ClientHudManager) :: ClientHudManager
	self.gui = nil
	self.cashLabel = nil
	self.lastCash = nil
	self.flashGeneration = 0
	self.groups = {}
	self.slotViews = {}
	return self
end

return ClientHudManager.new()
