--!strict

-- The Daily Rewards menu (GDD "Daily Rewards Menu", M39; the format of
-- Lucky Squares). Everything it draws is already on the client: the
-- tiles are the DailyRewardCatalogue GameMetadata JSON, the player's
-- record is two CurrentPlayer attributes (the last day claimed and the
-- server time the next one opens), and pure DailyRewardRules turns the
-- two into each tile's state on the shared server clock, so the server
-- never has to say "a day opened".
--
-- The grid is rebuilt from three hidden templates in the DailyRewards
-- gui, one per state (locked, ready, claimed), so the designer styles
-- each state as a whole card. The ready tile's Claim button sends
-- TryClaimDailyReward; NotifyDailyRewardClaimed brings back what landed
-- for the sound and the feedback line.
--
-- The HUD's Daily button (the left stack) opens the menu and wears a red
-- mark, its picture twitching now and then, while a reward is ready. The
-- menu also opens by itself once per visit, after the arrival loading
-- screen and after the group reward's claim menu if that is up.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local DailyRewardRules = require("@game/ReplicatedStorage/Shared/DailyRewardRules")
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
local ClientTicker = require(script.Parent.Parent.Client.ClientTicker)
local ClientGroupRewardManager = require(script.Parent.ClientGroupRewardManager)

local ClientDailyRewardManager = {}
ClientDailyRewardManager.__index = ClientDailyRewardManager

type View = {
	gui: ScreenGui,
	dialog: GuiObject,
	backButton: GuiButton,
	tileGrid: GuiObject,
	templateByState: { [DailyRewardRules.TileState]: GuiObject },
	nextRewardLabel: TextLabel,
}

export type ClientDailyRewardManager = typeof(setmetatable(
	{} :: {
		view: View?,
		overlay: ClientOverlayManager.Overlay?,
		isOpen: boolean,
		-- the tile whose claim is on its way to the server
		pendingTileIndex: number?,
		-- the states the grid was last built from, as one string, so the
		-- ticker rebuilds only when a tile changed
		renderedSignature: string,
		tiles: { GuiObject },
		tileConnections: { RBXScriptConnection },
		hudButton: GuiObject?,
		hudAlert: GuiObject?,
		hudIcon: GuiObject?,
		lastTwitchTime: number,
		-- the loading screen has gone and the pause after it has passed
		isArrivalDone: boolean,
		-- the one opening by itself this visit has happened (or there was
		-- nothing to claim on arrival)
		hasAutoOpened: boolean,
	},
	ClientDailyRewardManager
))

local TICK_SEC = 1
-- after the arrival loading screen has gone; longer than the group
-- reward's own pause, so its claim menu is up first when both apply
local ARRIVAL_DELAY_SEC = 1.5
local ARRIVAL_POLL_SEC = 0.1
-- the HUD button's picture while a reward waits: a short shake this often
local TWITCH_INTERVAL_SEC = 15
local TWITCH_DEGREES = 20
local TWITCH_STEP_SEC = 0.08
local TWITCH_CYCLES = 3
local FEEDBACK_SEC = 4

local DAY_FORMAT = "Day %d"
-- the last tile repeats for every day after it
local DAY_REPEATING_FORMAT = "Day %d+"
local READY_TEXT = "Ready to claim"
local NEXT_REWARD_FORMAT = "Next reward in %s"
local FEEDBACK_AMOUNT_FORMAT = "Daily reward: +%s"
local FEEDBACK_COSMETIC_FORMAT = "Daily reward: %s"
local FEEDBACK_DUPLICATE_FORMAT = "You already own %s: +%s"
local TILE_NAME_FORMAT = "Tile%d"

function ClientDailyRewardManager:getRewards(): { DailyRewardRules.PublishedReward }
	return DailyRewardRules.decodeCatalogue(ClientDataManager:getGameMetadata(Attributes.DAILY_REWARD_CATALOGUE)) or {}
end

function ClientDailyRewardManager:getState(): DailyRewardRules.State
	return {
		lastClaimedDay = ClientDataManager:getDailyRewardLastClaimedDay(),
		nextClaimTime = ClientDataManager:getDailyRewardNextClaimTime(),
	}
end

function ClientDailyRewardManager:isRewardReady(): boolean
	return #self:getRewards() > 0 and DailyRewardRules.getClaimableDay(self:getState(), workspace:GetServerTimeNow()) ~= nil
end

-- a cosmetic's name and picture, from the Key Store's one list
function ClientDailyRewardManager:findCosmetic(cosmeticId: string?): KeyStoreRules.Entry?
	local entries = KeyStoreRules.decode(ClientDataManager:getGameMetadata(Attributes.KEY_STORE_CATALOGUE))
	if not entries or not cosmeticId then
		return nil
	end
	return KeyStoreRules.findEntry(entries, cosmeticId)
end

function ClientDailyRewardManager:dropTiles()
	for _, connection in self.tileConnections do
		connection:Disconnect()
	end
	self.tileConnections = {}
	for _, tile in self.tiles do
		tile:Destroy()
	end
	self.tiles = {}
end

-- the picture and the words of one reward: a resource is its icon and a
-- number, a cosmetic its own picture and name
function ClientDailyRewardManager:fillTile(tile: GuiObject, reward: DailyRewardRules.PublishedReward)
	local icon = tile:FindFirstChild(Constants.DAILY_REWARDS_TILE_ICON)
	local amountLabel = tile:FindFirstChild(Constants.DAILY_REWARDS_TILE_AMOUNT_LABEL)
	local iconId = Icons.UI.DIAMONDS
	local text = utils.abbreviateNumber(reward.amount)
	if reward.kind == Enums.DailyRewardKind.KEYS then
		iconId = Icons.UI.KEYS
	elseif reward.kind == Enums.DailyRewardKind.COSMETIC then
		local cosmetic = self:findCosmetic(reward.cosmeticId)
		if cosmetic then
			iconId = cosmetic.iconId
			text = cosmetic.name
		else
			text = reward.cosmeticId or ""
		end
	end
	if icon and icon:IsA("ImageLabel") then
		icon.Image = iconId
	end
	if amountLabel and amountLabel:IsA("TextLabel") then
		amountLabel.Text = text
	end
end

function ClientDailyRewardManager:buildSignature(rewards: { DailyRewardRules.PublishedReward }, state: DailyRewardRules.State, now: number): string
	local states = {}
	for tileIndex in rewards do
		table.insert(states, DailyRewardRules.getTileState(state, now, tileIndex, #rewards))
	end
	return table.concat(states, ",") .. "|" .. tostring(self.pendingTileIndex)
end

function ClientDailyRewardManager:renderFooter(view: View)
	local remainingSec = DailyRewardRules.getRemainingSec(self:getState(), workspace:GetServerTimeNow())
	local text = READY_TEXT
	if remainingSec then
		-- the formatter pads a short time with a leading space
		local duration = string.gsub(utils.convertDurationSecToString(math.ceil(remainingSec)), "^%s+", "")
		text = string.format(NEXT_REWARD_FORMAT, duration)
	end
	view.nextRewardLabel.Text = UiStyle.formatTitle(text)
end

-- the whole grid again from the templates: one clone per tile, in the
-- state the rules give it
function ClientDailyRewardManager:render()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	local rewards = self:getRewards()
	local state = self:getState()
	local now = workspace:GetServerTimeNow()
	self:dropTiles()
	for tileIndex, reward in rewards do
		local tileState = DailyRewardRules.getTileState(state, now, tileIndex, #rewards)
		local tile = view.templateByState[tileState]:Clone()
		tile.Name = string.format(TILE_NAME_FORMAT, tileIndex)
		tile.LayoutOrder = tileIndex
		tile.Visible = true
		local dayLabel = tile:FindFirstChild(Constants.DAILY_REWARDS_TILE_DAY_LABEL, true)
		if dayLabel and dayLabel:IsA("TextLabel") then
			local isRepeating = tileIndex == #rewards
			dayLabel.Text = UiStyle.formatTitle(string.format(if isRepeating then DAY_REPEATING_FORMAT else DAY_FORMAT, tileIndex))
		end
		self:fillTile(tile, reward)
		local claimButton = tile:FindFirstChild(Constants.DAILY_REWARDS_TILE_CLAIM_BUTTON)
		if tileState == "READY" and claimButton and claimButton:IsA("GuiButton") then
			claimButton.Active = self.pendingTileIndex ~= tileIndex
			table.insert(
				self.tileConnections,
				claimButton.Activated:Connect(
					function()
						self:requestClaim(tileIndex)
					end
				)
			)
		end
		tile.Parent = view.tileGrid
		table.insert(self.tiles, tile)
	end
	self.renderedSignature = self:buildSignature(rewards, state, now)
	self:renderFooter(view)
end

function ClientDailyRewardManager:requestClaim(tileIndex: number)
	if self.pendingTileIndex then
		return
	end
	self.pendingTileIndex = tileIndex
	ClientNetManager:fireServer(NetEventNames.TRY_CLAIM_DAILY_REWARD, { tileIndex = tileIndex })
end

-- what landed, as the server says: the sound and one feedback line, a
-- resource shown as its icon after the number
function ClientDailyRewardManager:onClaimed(payload: { [string]: any })
	self.pendingTileIndex = nil
	ClientSoundManager:playSfx(SoundNames.Sfx.SALE_SUCCESS)
	local amountText = utils.abbreviateNumber(if typeof(payload.amount) == "number" then payload.amount else 0)
	local cosmetic = self:findCosmetic(payload.cosmeticId)
	local cosmeticName = if cosmetic then cosmetic.name else "that"
	if payload.isDuplicate then
		ClientPlayerFeedbackManager:giveLocal(string.format(FEEDBACK_DUPLICATE_FORMAT, cosmeticName, amountText), FEEDBACK_SEC, Icons.UI.DIAMONDS)
	elseif payload.kind == Enums.DailyRewardKind.COSMETIC then
		ClientPlayerFeedbackManager:giveLocal(string.format(FEEDBACK_COSMETIC_FORMAT, cosmeticName), FEEDBACK_SEC)
	else
		local iconId = if payload.kind == Enums.DailyRewardKind.KEYS then Icons.UI.KEYS else Icons.UI.DIAMONDS
		ClientPlayerFeedbackManager:giveLocal(string.format(FEEDBACK_AMOUNT_FORMAT, amountText), FEEDBACK_SEC, iconId)
	end
	self:render()
end

-- the HUD button's mark, and a shake of its picture every so often,
-- while a reward waits. The picture is shaken rather than the button
-- because the button sits in a list layout
function ClientDailyRewardManager:renderHudButton()
	local isReady = self:isRewardReady()
	local alert = self.hudAlert
	if alert then
		alert.Visible = isReady
	end
	local icon = self.hudIcon
	local now = workspace:GetServerTimeNow()
	if not isReady or not icon or self.isOpen or now - self.lastTwitchTime < TWITCH_INTERVAL_SEC then
		return
	end
	self.lastTwitchTime = now
	local tweenInfo = TweenInfo.new(TWITCH_STEP_SEC, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, TWITCH_CYCLES * 2 - 1, true)
	icon.Rotation = -TWITCH_DEGREES
	local tween = TweenService:Create(icon, tweenInfo, { Rotation = TWITCH_DEGREES })
	tween.Completed:Connect(
		function()
			icon.Rotation = 0
		end
	)
	tween:Play()
end

function ClientDailyRewardManager:onTick()
	self:renderHudButton()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	-- a tile changed state (the wait ran out with the menu open): the grid
	-- is rebuilt; otherwise only the countdown moves
	if self:buildSignature(self:getRewards(), self:getState(), workspace:GetServerTimeNow()) ~= self.renderedSignature then
		self:render()
	else
		self:renderFooter(view)
	end
end

function ClientDailyRewardManager:openMenu()
	local view = self.view
	local overlay = self.overlay
	if not view or not overlay or self.isOpen then
		return
	end
	-- one menu at a time
	if ClientOverlayManager:isOverlayActive() then
		return
	end
	self.isOpen = true
	-- opened by hand counts as the visit's opening
	self.hasAutoOpened = true
	view.gui.Enabled = true
	self:render()
	ClientOverlayManager:notifyBeginOverlay(overlay)
end

-- everything a close leaves behind, whoever closed it
function ClientDailyRewardManager:cleanUp(view: View)
	self.isOpen = false
	view.gui.Enabled = false
	self:dropTiles()
end

function ClientDailyRewardManager:closeMenu()
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

-- the menu opening by itself, once per visit: only with a reward ready,
-- never over another menu, and after the group reward's claim menu when
-- that one applies (it closing asks here again)
function ClientDailyRewardManager:openAutomaticallyIfNeeded()
	if self.hasAutoOpened or not self.isArrivalDone then
		return
	end
	if not self:isRewardReady() then
		-- nothing to claim on arrival: a day opening later only marks the
		-- HUD button
		self.hasAutoOpened = true
		return
	end
	if ClientGroupRewardManager:canClaim() or ClientOverlayManager:isOverlayActive() then
		return
	end
	self:openMenu()
end

function ClientDailyRewardManager:findView(playerGui: PlayerGui): View?
	-- waited for, not found: on a live server the client starts before
	-- StarterGui is copied in
	local gui = playerGui:WaitForChild(Constants.DAILY_REWARDS_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`ClientDailyRewardManager: no {Constants.DAILY_REWARDS_GUI_NAME} ScreenGui; run build_daily_rewards_gui`)
		return nil
	end
	local dialog = gui:FindFirstChild(Constants.MENU_DIALOG_FRAME)
	local backButton = dialog and dialog:FindFirstChild(Constants.DAILY_REWARDS_BACK_BUTTON)
	local tileGrid = dialog and dialog:FindFirstChild(Constants.DAILY_REWARDS_TILE_GRID)
	local lockedTemplate = tileGrid and tileGrid:FindFirstChild(Constants.DAILY_REWARDS_TILE_TEMPLATE_LOCKED)
	local readyTemplate = tileGrid and tileGrid:FindFirstChild(Constants.DAILY_REWARDS_TILE_TEMPLATE_READY)
	local claimedTemplate = tileGrid and tileGrid:FindFirstChild(Constants.DAILY_REWARDS_TILE_TEMPLATE_CLAIMED)
	local nextRewardLabel = dialog and dialog:FindFirstChild(Constants.DAILY_REWARDS_NEXT_REWARD_LABEL)
	if
		not dialog
		or not backButton
		or not backButton:IsA("GuiButton")
		or not tileGrid
		or not lockedTemplate
		or not lockedTemplate:IsA("GuiObject")
		or not readyTemplate
		or not readyTemplate:IsA("GuiObject")
		or not claimedTemplate
		or not claimedTemplate:IsA("GuiObject")
		or not nextRewardLabel
		or not nextRewardLabel:IsA("TextLabel")
	then
		warn(`ClientDailyRewardManager: {Constants.DAILY_REWARDS_GUI_NAME} is missing parts; see build_daily_rewards_gui`)
		return nil
	end
	return {
		gui = gui,
		dialog = dialog :: GuiObject,
		backButton = backButton,
		tileGrid = tileGrid :: GuiObject,
		templateByState = {
			LOCKED = lockedTemplate,
			READY = readyTemplate,
			CLAIMED = claimedTemplate,
		},
		nextRewardLabel = nextRewardLabel,
	}
end

-- the HUD's Daily button: its mark and the picture that shakes. The HUD
-- manager wires the press, since it owns the HUD's buttons
function ClientDailyRewardManager:findHudButton(playerGui: PlayerGui)
	local hud = playerGui:WaitForChild(Constants.HUD_GUI_NAME, Constants.GUI_WAIT_SEC)
	local leftButtons = hud and hud:FindFirstChild(Constants.HUD_LEFT_BUTTONS)
	local button = leftButtons and leftButtons:FindFirstChild(Constants.HUD_DAILY_REWARDS_BUTTON)
	if not button or not button:IsA("GuiObject") then
		warn(`ClientDailyRewardManager: the HUD has no {Constants.HUD_DAILY_REWARDS_BUTTON}; run build_daily_rewards_gui`)
		return
	end
	self.hudButton = button
	local alert = button:FindFirstChild(Constants.HUD_BUTTON_ALERT)
	self.hudAlert = if alert and alert:IsA("GuiObject") then alert else nil
	local icon = button:FindFirstChild(Constants.HUD_MENU_BUTTON_ICON)
	self.hudIcon = if icon and icon:IsA("GuiObject") then icon else nil
end

-- after ClientGroupRewardManager, whose claim menu goes first, and
-- before the HUD, whose Daily button opens this menu
function ClientDailyRewardManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local view = self:findView(playerGui)
	if not view then
		return
	end
	self.view = view
	for _, template in view.templateByState do
		template.Visible = false
	end
	view.gui.Enabled = false
	self:findHudButton(playerGui)

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
		-- the HUD's wallets are this menu's balances: a claim is seen
		-- landing in them
		doesKeepHud = function(_overlay)
			return true
		end,
	}
	self.overlay = overlay

	for _, attribute in { Attributes.DAILY_REWARD_LAST_CLAIMED_DAY, Attributes.DAILY_REWARD_NEXT_CLAIM_TIME, Attributes.OWNED_COSMETICS } do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			attribute,
			function()
				self:renderHudButton()
				self:render()
			end
		)
	end
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_DAILY_REWARD_CLAIMED,
		function(payload: { [string]: any })
			self:onClaimed(payload)
		end
	)
	ClientTicker.every(
		TICK_SEC,
		function()
			self:onTick()
		end
	)

	-- another menu closing (the group reward's claim menu above all) is
	-- the moment to try the automatic opening again; deferred because
	-- that menu is still mid-close here
	ClientOverlayManager:addOverlayNotifier(
		{
			notifyBeginOverlay = function(_notifier, _overlay) end,
			notifyEndOverlay = function(_notifier, endedOverlay)
				if endedOverlay ~= overlay then
					task.defer(
						function()
							self:openAutomaticallyIfNeeded()
						end
					)
				end
			end,
		}
	)
	-- the overlay manager holds menus back for exactly as long as the
	-- loading screen is up, so its flag is the screen's "gone" signal
	task.spawn(
		function()
			while ClientOverlayManager:getIsDeferringOverlays() do
				task.wait(ARRIVAL_POLL_SEC)
			end
			task.wait(ARRIVAL_DELAY_SEC)
			self.isArrivalDone = true
			self:openAutomaticallyIfNeeded()
		end
	)
	self:renderHudButton()
end

function ClientDailyRewardManager.new(): ClientDailyRewardManager
	local self = setmetatable({}, ClientDailyRewardManager) :: ClientDailyRewardManager
	self.isOpen = false
	self.renderedSignature = ""
	self.tiles = {}
	self.tileConnections = {}
	self.lastTwitchTime = 0
	self.isArrivalDone = false
	self.hasAutoOpened = false
	return self
end

return ClientDailyRewardManager.new()
