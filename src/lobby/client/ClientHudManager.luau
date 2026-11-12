--!strict

-- Drives the Studio-authored lobby HUD (GDD "HUD"): Diamonds balance with the
-- green/red change flash and sounds, the Keys wallet beside it (designer,
-- 2026-11-03: shown only while the player holds any Keys, the pair
-- centred as a group, the Diamonds wallet alone at the centre otherwise),
-- and the menu buttons (the loadout
-- strip along the bottom went with the Character redesign, 2026-10-12: the
-- character brings its gear, shown in the Character Menu). Slides off screen while a menu (overlay) is open. Menus arrive in
-- later milestones; until then the buttons give "coming soon" feedback.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local utils = require("@game/ReplicatedStorage/Shared/utils")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientClassMenuManager = require(script.Parent.ClientClassMenuManager)
local ClientDailyRewardManager = require(script.Parent.ClientDailyRewardManager)
local ClientStarterPackManager = require(script.Parent.ClientStarterPackManager)
local ClientLabelFlash = require(script.Parent.Parent.Client.ClientLabelFlash)
local ClientDiamondStoreManager = require(script.Parent.ClientDiamondStoreManager)
local ClientGuiFade = require(script.Parent.Parent.Client.ClientGuiFade)
local ClientGachaMenuManager = require(script.Parent.ClientGachaMenuManager)
local ClientGearMenuManager = require(script.Parent.ClientGearMenuManager)

local ClientHudManager = {}
ClientHudManager.__index = ClientHudManager

type HudGroup = {
	frame: GuiObject,
	basePosition: UDim2,
	offscreenPosition: UDim2,
}

export type ClientHudManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		diamondLabel: TextLabel?,
		lastDiamonds: number?,
		-- the two wallets' slide groups, re-centred as the Keys wallet
		-- comes and goes
		diamondGroup: HudGroup?,
		keysGroup: HudGroup?,
		keysLabel: TextLabel?,
		-- the Diamonds wallet's authored X, the centre of the pair
		walletCentreX: number,
		-- bumps per flash so an older restore cannot undo a newer flash
		flashGeneration: number,
		groups: { HudGroup },
		-- the open overlay asked for the wallets to stay on screen
		isWalletsKept: boolean,
		-- the Supply Crate has faded the wallets out for its reveal
		isWalletsFaded: boolean,
	},
	ClientHudManager
))

-- the number changes a beat after the colour and sound so the flash reads as
-- the cause and the new value as the effect
local BALANCE_UPDATE_DELAY_SEC = 0.15

function ClientHudManager:tweenGroup(group: HudGroup, position: UDim2)
	local tweenInfo = TweenInfo.new(UiStyle.HUD_TWEEN_SEC, Enum.EasingStyle.Quad)
	TweenService:Create(group.frame, tweenInfo, { Position = position }):Play()
end

function ClientHudManager:isWalletGroup(group: HudGroup): boolean
	return group == self.diamondGroup or group == self.keysGroup
end

-- an overlay that keeps the HUD leaves the two wallets where they are
-- (the Supply Crate's purchase screen, designer 2026-11-03)
function ClientHudManager:notifyBeginOverlay(overlay: ClientOverlayManager.Overlay)
	local doesKeepHudMethod = overlay.doesKeepHud
	self.isWalletsKept = doesKeepHudMethod ~= nil and doesKeepHudMethod(overlay)
	for _, group in self.groups do
		if self.isWalletsKept and self:isWalletGroup(group) then
			continue
		end
		self:tweenGroup(group, group.offscreenPosition)
	end
end

function ClientHudManager:notifyEndOverlay(_overlay: ClientOverlayManager.Overlay)
	self.isWalletsKept = false
	for _, group in self.groups do
		self:tweenGroup(group, group.basePosition)
	end
end

-- the wallets eased out for the crate's reveal and back in after the
-- claim; at a fadeSec of 0 they come back at once (the menu closing)
function ClientHudManager:setWalletsFaded(isFaded: boolean, fadeSec: number)
	self.isWalletsFaded = isFaded
	local frames: { GuiObject } = {}
	for _, group in { self.diamondGroup, self.keysGroup } do
		if group then
			table.insert(frames, group.frame)
		end
	end
	if isFaded then
		for _, frame in frames do
			if not frame.Visible then
				continue
			end
			ClientGuiFade.fadeOut(
				frame,
				fadeSec,
				function()
					if self.isWalletsFaded then
						frame.Visible = false
					end
				end
			)
		end
		return
	end
	-- the layout decides which wallet shows (Keys only above zero)
	self:layoutWallets()
	if fadeSec <= 0 then
		return
	end
	for _, frame in frames do
		if frame.Visible then
			ClientGuiFade.fadeIn(frame, fadeSec)
		end
	end
end

function ClientHudManager:renderDiamonds(diamonds: number)
	local label = self.diamondLabel
	if label then
		label.Text = utils.formatWithCommas(diamonds)
	end
end

-- GDD: an increase turns the text green with the coins sound, a decrease red
-- with the sale sound, then the value updates; the first value never flashes
function ClientHudManager:onDiamondsChanged(diamonds: number)
	local lastDiamonds = self.lastDiamonds
	self.lastDiamonds = diamonds
	local label = self.diamondLabel
	if not label or lastDiamonds == nil or diamonds == lastDiamonds then
		self:renderDiamonds(diamonds)
		return
	end

	self.flashGeneration += 1
	local generation = self.flashGeneration
	if diamonds > lastDiamonds then
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
				self:renderDiamonds(diamonds)
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

function ClientHudManager:addGroup(frame: GuiObject, offscreenPosition: UDim2): HudGroup
	local group = {
		frame = frame,
		basePosition = frame.Position,
		offscreenPosition = offscreenPosition,
	}
	table.insert(self.groups, group)
	return group
end

-- the Diamonds wallet sits at its authored centre alone; with Keys to show
-- the two share that centre, each half a wallet and half the gap out
function ClientHudManager:layoutWallets()
	local diamondGroup = self.diamondGroup
	local keysGroup = self.keysGroup
	local keysLabel = self.keysLabel
	if not diamondGroup then
		return
	end
	local keys = ClientDataManager:getKeys()
	local isKeysShown = keysGroup ~= nil and keys > 0
	local offsetX = 0
	if isKeysShown then
		offsetX = diamondGroup.frame.Size.X.Scale / 2 + UiStyle.HUD_WALLET_GAP_SCALE / 2
	end
	local isOverlayActive = ClientOverlayManager:isOverlayActive()
	local function place(group: HudGroup, x: number)
		group.basePosition = UDim2.new(x, 0, group.basePosition.Y.Scale, group.basePosition.Y.Offset)
		-- mid-overlay the wallets are off screen; the slide back lands them
		-- (unless the overlay kept them on screen)
		if not isOverlayActive or self.isWalletsKept then
			group.frame.Position = group.basePosition
		end
	end
	place(diamondGroup, self.walletCentreX - offsetX)
	diamondGroup.frame.Visible = not self.isWalletsFaded
	if keysGroup then
		place(keysGroup, self.walletCentreX + offsetX)
		keysGroup.frame.Visible = isKeysShown and not self.isWalletsFaded
	end
	if keysLabel then
		keysLabel.Text = utils.formatWithCommas(keys)
	end
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

-- a controller opens the HUD's menus by button while no menu is up
-- (designer, 2026-11-11), and each menu button shows that button's picture
-- to its left while a controller is the input in use. ClientOverlayManager
-- hands the presses out, so B closing a menu never reopens one
function ClientHudManager:wireGamepadShortcuts(menuButtons: Instance)
	local openByKeyCode: { [Enum.KeyCode]: () -> () } = {
		-- the gacha menu hands a restricted player on to the rotating store
		[Enum.KeyCode.ButtonY] = function()
			ClientGachaMenuManager:openMenu()
		end,
		[Enum.KeyCode.ButtonX] = function()
			ClientClassMenuManager:openMenu()
		end,
		[Enum.KeyCode.ButtonB] = function()
			ClientGearMenuManager:openMenu()
		end,
	}
	ClientOverlayManager:subscribeIdleGamepadButton(
		function(keyCode: Enum.KeyCode)
			local open = openByKeyCode[keyCode]
			if open then
				open()
			end
		end
	)
	local glyphsByButtonName = {
		[Constants.HUD_STORE_BUTTON] = { xbox = Icons.GAMEPAD.XBOX_Y, playStation = Icons.GAMEPAD.PLAYSTATION_TRIANGLE },
		[Constants.HUD_ROTATING_STORE_BUTTON] = { xbox = Icons.GAMEPAD.XBOX_Y, playStation = Icons.GAMEPAD.PLAYSTATION_TRIANGLE },
		[Constants.HUD_CLASSES_BUTTON] = { xbox = Icons.GAMEPAD.XBOX_X, playStation = Icons.GAMEPAD.PLAYSTATION_SQUARE },
		[Constants.HUD_GEAR_BUTTON] = { xbox = Icons.GAMEPAD.XBOX_B, playStation = Icons.GAMEPAD.PLAYSTATION_CIRCLE },
	}
	local function renderGlyphs()
		local isGamepad = string.find(UserInputService:GetLastInputType().Name, "^Gamepad") ~= nil
		-- Roblox names the bottom face button for the connected controller
		local isPlayStation = isGamepad and string.find(UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonA), "Cross") ~= nil
		for buttonName, images in glyphsByButtonName do
			local button = menuButtons:FindFirstChild(buttonName)
			local glyph = if button then button:FindFirstChild(Constants.HUD_MENU_BUTTON_GAMEPAD_GLYPH) else nil
			if glyph and glyph:IsA("ImageLabel") then
				glyph.Image = if isPlayStation then images.playStation else images.xbox
				glyph.Visible = isGamepad
			end
		end
	end
	renderGlyphs()
	UserInputService.LastInputTypeChanged:Connect(renderGlyphs)
end

-- the Class button's picture is the equipped class's icon (designer,
-- 2026-11-09); a class with no picture yet keeps whatever the designer
-- authored on the label
function ClientHudManager:renderClassIcon(menuButtons: Instance)
	local button = menuButtons:FindFirstChild(Constants.HUD_CLASSES_BUTTON)
	local icon = if button then button:FindFirstChild(Constants.HUD_MENU_BUTTON_ICON) else nil
	if not icon or not icon:IsA("ImageLabel") then
		return
	end
	local iconId = Icons.CLASS_KIND[ClientDataManager:getActiveClassKind()]
	if iconId and not Icons.isPlaceholder(iconId) then
		icon.Image = iconId
	end
end

function ClientHudManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.HUD_GUI_NAME) :: ScreenGui
	gui.ResetOnSpawn = false
	gui.Enabled = true
	self.gui = gui

	local diamondWallet = gui:WaitForChild(Constants.HUD_DIAMOND_WALLET) :: GuiObject
	self.diamondLabel = diamondWallet:WaitForChild(Constants.HUD_DIAMOND_AMOUNT_LABEL) :: TextLabel
	self.walletCentreX = diamondWallet.Position.X.Scale
	self.diamondGroup = self:addGroup(diamondWallet, UDim2.new(-0.5, 0, diamondWallet.Position.Y.Scale, 0))
	-- the Keys wallet is optional so an older copy of the HUD still runs
	local keysWallet = gui:FindFirstChild(Constants.HUD_KEYS_WALLET)
	if keysWallet and keysWallet:IsA("GuiObject") then
		local keysLabel = keysWallet:FindFirstChild(Constants.HUD_KEYS_AMOUNT_LABEL)
		self.keysLabel = if keysLabel and keysLabel:IsA("TextLabel") then keysLabel else nil
		self.keysGroup = self:addGroup(keysWallet, UDim2.new(-0.5, 0, keysWallet.Position.Y.Scale, 0))
	else
		warn(`ClientHudManager: {Constants.HUD_GUI_NAME} has no {Constants.HUD_KEYS_WALLET}; Keys stay off the HUD`)
	end
	-- the wallet is the other door to the Diamond Store (designer, 2026-11-03)
	if diamondWallet:IsA("GuiButton") then
		diamondWallet.Activated:Connect(
			function()
				ClientDiamondStoreManager:openMenu()
			end
		)
	end

	local menuButtons = gui:WaitForChild(Constants.HUD_MENU_BUTTONS) :: GuiObject
	self:addGroup(menuButtons, UDim2.new(1.5, 0, menuButtons.Position.Y.Scale, 0))
	-- the jet pack bar slides away with the menu buttons; its fill is
	-- ClientJetPackManager's
	local jetPackBar = gui:FindFirstChild(Constants.HUD_JET_PACK_BAR)
	if jetPackBar and jetPackBar:IsA("GuiObject") then
		self:addGroup(jetPackBar, UDim2.new(1.5, 0, jetPackBar.Position.Y.Scale, 0))
	end
	-- the left-hand stack (designer, 2026-11-12): Daily Rewards, sliding
	-- off the left edge for a menu. Its mark is ClientDailyRewardManager's
	local leftButtons = gui:FindFirstChild(Constants.HUD_LEFT_BUTTONS)
	if leftButtons and leftButtons:IsA("GuiObject") then
		self:addGroup(leftButtons, UDim2.new(-0.5, 0, leftButtons.Position.Y.Scale, 0))
		self:wireButton(
			leftButtons,
			Constants.HUD_DAILY_REWARDS_BUTTON,
			function()
				ClientDailyRewardManager:openMenu()
			end
		)
		-- under it, until the pack is bought (M79); showing and hiding it
		-- is ClientStarterPackManager's
		self:wireButton(
			leftButtons,
			Constants.HUD_STARTER_PACK_BUTTON,
			function()
				ClientStarterPackManager:openMenu()
			end
		)
	else
		warn(`ClientHudManager: the HUD has no {Constants.HUD_LEFT_BUTTONS}; run build_daily_rewards_gui`)
	end
	self:wireButton(
		menuButtons,
		Constants.HUD_CLASSES_BUTTON,
		function()
			ClientClassMenuManager:openMenu()
		end
	)
	-- the Store button opens the crate menu (designer, 2026-11-06; a choice
	-- screen between the crate and the Key Store stood in front for a day)
	self:wireButton(
		menuButtons,
		Constants.HUD_STORE_BUTTON,
		function()
			ClientGachaMenuManager:openMenu()
		end
	)
	self:wireButton(
		menuButtons,
		Constants.HUD_GEAR_BUTTON,
		function()
			ClientGearMenuManager:openMenu()
		end
	)
	-- the gacha menu hands a restricted player on to the rotating store,
	-- so this button never shows them a crate
	self:wireButton(
		menuButtons,
		Constants.HUD_ROTATING_STORE_BUTTON,
		function()
			ClientGachaMenuManager:openMenu()
		end
	)
	-- a player restricted from paid random items has no crates to open,
	-- so the Store button gives its place to the Rotating Store button
	-- (designer, 2026-11-10)
	local storeButton = menuButtons:FindFirstChild(Constants.HUD_STORE_BUTTON)
	local rotatingStoreButton = menuButtons:FindFirstChild(Constants.HUD_ROTATING_STORE_BUTTON)
	local function renderStoreButton()
		local isRestricted = ClientDataManager:isPaidRandomItemsRestricted()
		if storeButton and storeButton:IsA("GuiObject") then
			storeButton.Visible = not isRestricted
		end
		if rotatingStoreButton and rotatingStoreButton:IsA("GuiObject") then
			rotatingStoreButton.Visible = isRestricted
		end
	end
	renderStoreButton()
	ClientDataManager:subscribeCurrentPlayerAttribute(Attributes.IS_PAID_RANDOM_ITEMS_RESTRICTED, renderStoreButton)
	self:wireGamepadShortcuts(menuButtons)
	self:renderClassIcon(menuButtons)
	ClientDataManager:subscribeClasses(
		function()
			self:renderClassIcon(menuButtons)
		end
	)

	ClientOverlayManager:addOverlayNotifier(self)
	ClientGachaMenuManager:subscribeWalletsFaded(
		function(isFaded, fadeSec)
			self:setWalletsFaded(isFaded, fadeSec)
		end
	)
	ClientDiamondStoreManager:subscribeDiamondsShort(
		function()
			local label = self.diamondLabel
			if label then
				ClientLabelFlash.flashRed(label)
			end
		end
	)

	self:onDiamondsChanged(ClientDataManager:getDiamonds())
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.DIAMONDS,
		function()
			self:onDiamondsChanged(ClientDataManager:getDiamonds())
		end
	)
	self:layoutWallets()
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.KEYS,
		function()
			self:layoutWallets()
		end
	)
end

function ClientHudManager.new(): ClientHudManager
	local self = setmetatable({}, ClientHudManager) :: ClientHudManager
	self.gui = nil
	self.diamondLabel = nil
	self.lastDiamonds = nil
	self.diamondGroup = nil
	self.keysGroup = nil
	self.keysLabel = nil
	self.walletCentreX = 0.5
	self.flashGeneration = 0
	self.groups = {}
	self.isWalletsKept = false
	self.isWalletsFaded = false
	return self
end

return ClientHudManager.new()
