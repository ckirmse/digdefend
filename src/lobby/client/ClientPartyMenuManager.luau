--!strict

-- Drives the two pad menus (GDD "Create Party Menu" and "Queue Menu"). The
-- server says which menu to show (NotifyPartyMenu); everything shown comes
-- from the pad's replicated attributes and the party config on GameMetadata.
-- Selection state is client-side until Create sends it in one message. While
-- a menu is open the camera sits on the pad's CameraPositionPart and the
-- character stays in its helicopter seat (leaving the seat leaves the party).
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PartyRules = require("@game/ReplicatedStorage/Shared/PartyRules")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPadBillboardManager = require(script.Parent.ClientPadBillboardManager)

local ClientPartyMenuManager = {}
ClientPartyMenuManager.__index = ClientPartyMenuManager

type CarouselView = {
	previousButton: TextButton,
	nextButton: TextButton,
	thumbnail: ImageLabel,
	nameLabel: TextLabel,
	lockIcon: TextLabel,
	requirementLabel: TextLabel,
}

type CreateView = {
	gui: ScreenGui,
	dialog: Frame,
	map: CarouselView,
	difficulty: CarouselView,
	minusButton: TextButton,
	plusButton: TextButton,
	valueLabel: TextLabel,
	toggle: TextButton,
	toggleStateLabel: TextLabel,
	countdownLabel: TextLabel,
	createButton: TextButton,
	cancelButton: TextButton,
}

type QueueView = {
	gui: ScreenGui,
	dialog: Frame,
	mapLabel: TextLabel,
	difficultyLabel: TextLabel,
	playersLabel: TextLabel,
	visibilityLabel: TextLabel,
	hostLabel: TextLabel,
	countdownLabel: TextLabel,
	launchButton: TextButton,
	exitButton: TextButton,
}

export type ClientPartyMenuManager = typeof(setmetatable(
	{} :: {
		config: PartyRules.Config?,
		createView: CreateView?,
		queueView: QueueView?,
		overlay: ClientOverlayManager.Overlay?,
		activeMenu: number,
		padModel: Model?,
		padConnection: RBXScriptConnection?,
		isHost: boolean,
		-- Create Party selection, client-side until Create
		mapIndex: number,
		difficultyIndex: number,
		maxPlayers: number,
		isFriendsOnly: boolean,
	},
	ClientPartyMenuManager
))

local NOTIFY_PARTY_MENU_SHAPE = {
	menu = { type = "enum", name = "PartyMenu" },
	padIndex = "nonnegativeInteger",
	isHost = "boolean",
}

local COUNTDOWN_REFRESH_SEC = 0.25
local CANCELLING_IN = "Cancelling in %d seconds"
local DEPARTING_IN = "Departing in %d seconds"
local PLAYERS_FORMAT = "Players: %d / %d"
local HOST_FORMAT = "Host: %s"
local TOGGLE_ON = "On"
local TOGGLE_OFF = "Off"
local PLACEHOLDER_THUMBNAIL = "rbxassetid://0"
-- until map art exists each map gets its own flat colour so the carousel reads
local PLACEHOLDER_COLORS = {
	Color3.fromRGB(120, 80, 40),
	Color3.fromRGB(70, 110, 150),
	Color3.fromRGB(90, 120, 70),
}

local function findChild(parent: Instance, name: string, className: string): Instance?
	local child = parent:FindFirstChild(name, true)
	if child and child:IsA(className) then
		return child
	end
	warn(`ClientPartyMenuManager: {parent:GetFullName()} has no {className} named {name}`)
	return nil
end

local function getAttributeNumber(model: Model, name: string): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function hasCompletion(completionKey: string): boolean
	return ClientDataManager:hasCompletion(completionKey)
end

local function findCarousel(root: Instance, name: string): CarouselView?
	local frame = findChild(root, name, "Frame")
	if not frame then
		return nil
	end
	local previousButton = findChild(frame, Constants.CAROUSEL_PREVIOUS_BUTTON, "TextButton")
	local nextButton = findChild(frame, Constants.CAROUSEL_NEXT_BUTTON, "TextButton")
	local thumbnail = findChild(frame, Constants.CAROUSEL_THUMBNAIL, "ImageLabel")
	local nameLabel = findChild(frame, Constants.CAROUSEL_NAME_LABEL, "TextLabel")
	local lockIcon = findChild(frame, Constants.CAROUSEL_LOCK_ICON, "TextLabel")
	local requirementLabel = findChild(frame, Constants.CAROUSEL_REQUIREMENT_LABEL, "TextLabel")
	if not (previousButton and nextButton and thumbnail and nameLabel and lockIcon and requirementLabel) then
		return nil
	end
	return {
		previousButton = previousButton :: TextButton,
		nextButton = nextButton :: TextButton,
		thumbnail = thumbnail :: ImageLabel,
		nameLabel = nameLabel :: TextLabel,
		lockIcon = lockIcon :: TextLabel,
		requirementLabel = requirementLabel :: TextLabel,
	}
end

function ClientPartyMenuManager:getSelectedMap(): number?
	local config = self.config
	local entry = if config then config.MAPS[self.mapIndex] else nil
	return if entry then entry.map else nil
end

function ClientPartyMenuManager:getSelectedDifficulty(): number?
	local config = self.config
	local entry = if config then config.DIFFICULTIES[self.difficultyIndex] else nil
	return if entry then entry.difficulty else nil
end

function ClientPartyMenuManager:isSelectionUnlocked(): boolean
	local config = self.config
	local map = self:getSelectedMap()
	local difficulty = self:getSelectedDifficulty()
	if not config or not map or not difficulty then
		return false
	end
	return PartyRules.isMapUnlocked(config, map, hasCompletion)
		and PartyRules.isDifficultyUnlocked(config, map, difficulty, hasCompletion)
end

-- GDD: when the map changes, a difficulty locked on the new map falls back to
-- the first unlocked one
function ClientPartyMenuManager:resetDifficultyIfLocked()
	local config = self.config
	local map = self:getSelectedMap()
	local difficulty = self:getSelectedDifficulty()
	if not config or not map or not difficulty then
		return
	end
	if PartyRules.isDifficultyUnlocked(config, map, difficulty, hasCompletion) then
		return
	end
	local fallback = PartyRules.getFirstUnlockedDifficulty(config, map, hasCompletion)
	for index, entry in config.DIFFICULTIES do
		if entry.difficulty == fallback then
			self.difficultyIndex = index
			return
		end
	end
end

function ClientPartyMenuManager:renderCarousel(carousel: CarouselView, name: string, isLocked: boolean, requirementKey: string?, thumbnail: string?, placeholderColor: Color3?)
	carousel.nameLabel.Text = UiStyle.formatTitle(name)
	carousel.lockIcon.Visible = isLocked
	carousel.requirementLabel.Text = if isLocked and requirementKey then PartyRules.getRequirementText(requirementKey) else ""
	if thumbnail and thumbnail ~= PLACEHOLDER_THUMBNAIL then
		carousel.thumbnail.Image = thumbnail
		carousel.thumbnail.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
	else
		carousel.thumbnail.Image = ""
		carousel.thumbnail.BackgroundColor3 = placeholderColor or UiStyle.EMPTY_SLOT_COLOR
	end
	-- locked options stay visible but read as unavailable
	local tint = if isLocked then UiStyle.DISABLED_COLOR else UiStyle.TEXT_COLOR
	carousel.thumbnail.ImageColor3 = tint
	carousel.nameLabel.TextColor3 = tint
	if isLocked then
		carousel.thumbnail.BackgroundColor3 = carousel.thumbnail.BackgroundColor3:Lerp(UiStyle.DISABLED_COLOR, 0.6)
	end
end

function ClientPartyMenuManager:renderCreate()
	local view = self.createView
	local config = self.config
	if not view or not config then
		return
	end
	local mapEntry = config.MAPS[self.mapIndex]
	local map = mapEntry.map
	local isMapLocked = not PartyRules.isMapUnlocked(config, map, hasCompletion)
	self:renderCarousel(
		view.map,
		Enums.getPublicName(Enums.Map, map) or "?",
		isMapLocked,
		PartyRules.getMapRequirementKey(config, map),
		mapEntry.thumbnail,
		PLACEHOLDER_COLORS[((self.mapIndex - 1) % #PLACEHOLDER_COLORS) + 1]
	)

	local difficultyEntry = config.DIFFICULTIES[self.difficultyIndex]
	local difficulty = difficultyEntry.difficulty
	local isDifficultyLocked = not PartyRules.isDifficultyUnlocked(config, map, difficulty, hasCompletion)
	self:renderCarousel(
		view.difficulty,
		Enums.getPublicName(Enums.Difficulty, difficulty) or "?",
		isDifficultyLocked,
		PartyRules.getDifficultyRequirementKey(config, map, difficulty),
		nil,
		UiStyle.PANEL_COLOR
	)

	view.valueLabel.Text = tostring(self.maxPlayers)
	view.minusButton.TextColor3 = if self.maxPlayers > 1 then UiStyle.ACCENT_COLOR else UiStyle.DISABLED_COLOR
	view.plusButton.TextColor3 = if self.maxPlayers < config.MAX_PARTY_SIZE then UiStyle.ACCENT_COLOR else UiStyle.DISABLED_COLOR

	view.toggleStateLabel.Text = UiStyle.formatTitle(if self.isFriendsOnly then TOGGLE_ON else TOGGLE_OFF)
	view.toggleStateLabel.TextColor3 = if self.isFriendsOnly then UiStyle.ACCENT_COLOR else UiStyle.TEXT_MUTED_COLOR

	local isUnlocked = self:isSelectionUnlocked()
	view.createButton.Active = isUnlocked
	view.createButton.AutoButtonColor = isUnlocked
	view.createButton.BackgroundColor3 = if isUnlocked then UiStyle.ACCENT_COLOR else UiStyle.DISABLED_COLOR
	self:renderCountdown()
end

function ClientPartyMenuManager:getHostName(): string
	local padModel = self.padModel
	if not padModel then
		return ""
	end
	local hostUserId = getAttributeNumber(padModel, Attributes.PAD_HOST_USER_ID)
	local publicData = ClientDataManager:getPlayerPublicData(hostUserId)
	if publicData then
		return publicData.displayName
	end
	local player = Players:GetPlayerByUserId(hostUserId)
	return if player then player.DisplayName else ""
end

function ClientPartyMenuManager:renderQueue()
	local view = self.queueView
	local padModel = self.padModel
	if not view or not padModel then
		return
	end
	local map = getAttributeNumber(padModel, Attributes.PAD_MAP)
	local difficulty = getAttributeNumber(padModel, Attributes.PAD_DIFFICULTY)
	local visibility = getAttributeNumber(padModel, Attributes.PAD_VISIBILITY)
	view.mapLabel.Text = UiStyle.formatTitle(Enums.getPublicName(Enums.Map, map) or "")
	view.difficultyLabel.Text = Enums.getPublicName(Enums.Difficulty, difficulty) or ""
	view.playersLabel.Text = string.format(
		PLAYERS_FORMAT,
		getAttributeNumber(padModel, Attributes.PAD_PLAYER_COUNT),
		getAttributeNumber(padModel, Attributes.PAD_MAX_PLAYERS)
	)
	view.visibilityLabel.Text = Enums.getPublicName(Enums.PartyVisibility, visibility) or ""
	view.hostLabel.Text = string.format(HOST_FORMAT, self:getHostName())
	view.launchButton.Visible = self.isHost
	self:renderCountdown()
end

function ClientPartyMenuManager:renderCountdown()
	local padModel = self.padModel
	if not padModel then
		return
	end
	local endTime = getAttributeNumber(padModel, Attributes.PAD_TIMER_END_TIME)
	local remaining = math.max(0, math.ceil(endTime - workspace:GetServerTimeNow()))
	local createView = self.createView
	if self.activeMenu == Enums.PartyMenu.CREATE and createView then
		createView.countdownLabel.Text = string.format(CANCELLING_IN, remaining)
	end
	local queueView = self.queueView
	if self.activeMenu == Enums.PartyMenu.QUEUE and queueView then
		queueView.countdownLabel.Text = string.format(DEPARTING_IN, remaining)
	end
end

-- while in a party the only way off the pad is Exit or Cancel: jumping out
-- of the seat is disabled (the server still treats an unseated member as
-- having left, so death and other surprises stay covered)
function ClientPartyMenuManager:setMovementLocked(isLocked: boolean)
	local character = Players.LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid then
		return
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not isLocked)
end

function ClientPartyMenuManager:setCamera(padModel: Model?)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPart = if padModel then padModel:FindFirstChild(Constants.PAD_CAMERA_POSITION_PART) else nil
	if cameraPart and cameraPart:IsA("BasePart") then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = cameraPart.CFrame
		return
	end
	camera.CameraType = Enum.CameraType.Custom
	local character = Players.LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

function ClientPartyMenuManager:findPadModel(padIndex: number): Model?
	local padsFolder = workspace:FindFirstChild(Constants.HELICOPTER_PADS_FOLDER)
	if not padsFolder then
		return nil
	end
	for _, pad in padsFolder:GetChildren() do
		if pad:IsA("Model") and pad:GetAttribute(Attributes.PAD_INDEX) == padIndex then
			return pad
		end
	end
	return nil
end

function ClientPartyMenuManager:resetSelection()
	local config = self.config
	if not config then
		return
	end
	self.mapIndex = 1
	self.difficultyIndex = 1
	self.maxPlayers = config.DEFAULT_MAX_PLAYERS
	self.isFriendsOnly = config.DEFAULT_VISIBILITY == Enums.PartyVisibility.FRIENDS_ONLY
	self:resetDifficultyIfLocked()
end

function ClientPartyMenuManager:showGuis()
	local createView = self.createView
	if createView then
		createView.gui.Enabled = self.activeMenu == Enums.PartyMenu.CREATE
	end
	local queueView = self.queueView
	if queueView then
		queueView.gui.Enabled = self.activeMenu == Enums.PartyMenu.QUEUE
	end
end

function ClientPartyMenuManager:closeMenu()
	if self.activeMenu == Enums.PartyMenu.NONE then
		return
	end
	self.activeMenu = Enums.PartyMenu.NONE
	self:showGuis()
	local padConnection = self.padConnection
	if padConnection then
		padConnection:Disconnect()
		self.padConnection = nil
	end
	self.padModel = nil
	self:setCamera(nil)
	self:setMovementLocked(false)
	ClientPadBillboardManager:setBillboardsVisible(true)
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

function ClientPartyMenuManager:openMenu(menu: number, padIndex: number, isHost: boolean)
	local padModel = self:findPadModel(padIndex)
	if not padModel then
		warn(`ClientPartyMenuManager: no pad model with index {padIndex}`)
		return
	end
	if menu == Enums.PartyMenu.CREATE and not self.config then
		warn("ClientPartyMenuManager: no party config; cannot open the Create Party menu")
		return
	end
	local wasOpen = self.activeMenu ~= Enums.PartyMenu.NONE
	self.isHost = isHost
	if self.padModel ~= padModel then
		local padConnection = self.padConnection
		if padConnection then
			padConnection:Disconnect()
		end
		self.padModel = padModel
		self.padConnection = padModel.AttributeChanged:Connect(
			function()
				if self.activeMenu == Enums.PartyMenu.QUEUE then
					self:renderQueue()
				end
			end
		)
	end
	self.activeMenu = menu
	if menu == Enums.PartyMenu.CREATE then
		self:resetSelection()
		self:renderCreate()
	else
		self:renderQueue()
	end
	self:showGuis()
	self:setCamera(padModel)
	self:setMovementLocked(true)
	ClientPadBillboardManager:setBillboardsVisible(false)
	-- one overlay spans both menus so switching Create -> Queue is not a
	-- force-end of the first
	local overlay = self.overlay
	if not wasOpen and overlay then
		ClientOverlayManager:notifyBeginOverlay(overlay)
	end
end

function ClientPartyMenuManager:onNotifyPartyMenu(payload: any)
	local isValid, err = Validate.isTableShape(payload, NOTIFY_PARTY_MENU_SHAPE)
	if not isValid then
		warn("ClientPartyMenuManager: bad NotifyPartyMenu payload:", err)
		return
	end
	if payload.menu == Enums.PartyMenu.NONE then
		self:closeMenu()
		return
	end
	self:openMenu(payload.menu, payload.padIndex, payload.isHost)
end

function ClientPartyMenuManager:stepMap(delta: number)
	local config = self.config
	if not config then
		return
	end
	self.mapIndex = ((self.mapIndex - 1 + delta) % #config.MAPS) + 1
	self:resetDifficultyIfLocked()
	self:renderCreate()
end

function ClientPartyMenuManager:stepDifficulty(delta: number)
	local config = self.config
	if not config then
		return
	end
	self.difficultyIndex = ((self.difficultyIndex - 1 + delta) % #config.DIFFICULTIES) + 1
	self:renderCreate()
end

function ClientPartyMenuManager:stepPlayers(delta: number)
	local config = self.config
	if not config then
		return
	end
	self.maxPlayers = math.clamp(self.maxPlayers + delta, 1, config.MAX_PARTY_SIZE)
	self:renderCreate()
end

function ClientPartyMenuManager:toggleFriendsOnly()
	self.isFriendsOnly = not self.isFriendsOnly
	self:renderCreate()
end

function ClientPartyMenuManager:sendCreate()
	if not self:isSelectionUnlocked() then
		return
	end
	local map = self:getSelectedMap()
	local difficulty = self:getSelectedDifficulty()
	if not map or not difficulty then
		return
	end
	ClientNetManager:fireServer(
		NetEventNames.TRY_CREATE_PARTY,
		{
			map = map,
			difficulty = difficulty,
			maxPlayers = self.maxPlayers,
			visibility = if self.isFriendsOnly then Enums.PartyVisibility.FRIENDS_ONLY else Enums.PartyVisibility.PUBLIC,
		}
	)
end

function ClientPartyMenuManager:sendLeave()
	ClientNetManager:fireServer(NetEventNames.TRY_LEAVE_PARTY, {})
end

function ClientPartyMenuManager:sendLaunch()
	ClientNetManager:fireServer(NetEventNames.TRY_LAUNCH_PARTY, {})
end

function ClientPartyMenuManager:findCreateView(playerGui: PlayerGui): CreateView?
	local gui = playerGui:FindFirstChild(Constants.CREATE_PARTY_GUI_NAME)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`ClientPartyMenuManager: no {Constants.CREATE_PARTY_GUI_NAME} ScreenGui; run scripts/studio/build_create_party_gui.luau`)
		return nil
	end
	local dialog = findChild(gui, Constants.MENU_DIALOG_FRAME, "Frame")
	local map = findCarousel(gui, Constants.CREATE_PARTY_MAP_CAROUSEL)
	local difficulty = findCarousel(gui, Constants.CREATE_PARTY_DIFFICULTY_CAROUSEL)
	local minusButton = findChild(gui, Constants.STEPPER_MINUS_BUTTON, "TextButton")
	local plusButton = findChild(gui, Constants.STEPPER_PLUS_BUTTON, "TextButton")
	local valueLabel = findChild(gui, Constants.STEPPER_VALUE_LABEL, "TextLabel")
	local toggle = findChild(gui, Constants.CREATE_PARTY_FRIENDS_ONLY_TOGGLE, "TextButton")
	local toggleStateLabel = findChild(gui, Constants.TOGGLE_STATE_LABEL, "TextLabel")
	local countdownLabel = findChild(gui, Constants.CREATE_PARTY_COUNTDOWN_LABEL, "TextLabel")
	local createButton = findChild(gui, Constants.CREATE_PARTY_CREATE_BUTTON, "TextButton")
	local cancelButton = findChild(gui, Constants.CREATE_PARTY_CANCEL_BUTTON, "TextButton")
	if not (dialog and map and difficulty and minusButton and plusButton and valueLabel and toggle and toggleStateLabel and countdownLabel and createButton and cancelButton) then
		return nil
	end
	return {
		gui = gui,
		dialog = dialog :: Frame,
		map = map,
		difficulty = difficulty,
		minusButton = minusButton :: TextButton,
		plusButton = plusButton :: TextButton,
		valueLabel = valueLabel :: TextLabel,
		toggle = toggle :: TextButton,
		toggleStateLabel = toggleStateLabel :: TextLabel,
		countdownLabel = countdownLabel :: TextLabel,
		createButton = createButton :: TextButton,
		cancelButton = cancelButton :: TextButton,
	}
end

function ClientPartyMenuManager:findQueueView(playerGui: PlayerGui): QueueView?
	local gui = playerGui:FindFirstChild(Constants.QUEUE_GUI_NAME)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`ClientPartyMenuManager: no {Constants.QUEUE_GUI_NAME} ScreenGui; run scripts/studio/build_queue_gui.luau`)
		return nil
	end
	local dialog = findChild(gui, Constants.MENU_DIALOG_FRAME, "Frame")
	local mapLabel = findChild(gui, Constants.QUEUE_MAP_LABEL, "TextLabel")
	local difficultyLabel = findChild(gui, Constants.QUEUE_DIFFICULTY_LABEL, "TextLabel")
	local playersLabel = findChild(gui, Constants.QUEUE_PLAYERS_LABEL, "TextLabel")
	local visibilityLabel = findChild(gui, Constants.QUEUE_VISIBILITY_LABEL, "TextLabel")
	local hostLabel = findChild(gui, Constants.QUEUE_HOST_LABEL, "TextLabel")
	local countdownLabel = findChild(gui, Constants.QUEUE_COUNTDOWN_LABEL, "TextLabel")
	local launchButton = findChild(gui, Constants.QUEUE_LAUNCH_BUTTON, "TextButton")
	local exitButton = findChild(gui, Constants.QUEUE_EXIT_BUTTON, "TextButton")
	if not (dialog and mapLabel and difficultyLabel and playersLabel and visibilityLabel and hostLabel and countdownLabel and launchButton and exitButton) then
		return nil
	end
	return {
		gui = gui,
		dialog = dialog :: Frame,
		mapLabel = mapLabel :: TextLabel,
		difficultyLabel = difficultyLabel :: TextLabel,
		playersLabel = playersLabel :: TextLabel,
		visibilityLabel = visibilityLabel :: TextLabel,
		hostLabel = hostLabel :: TextLabel,
		countdownLabel = countdownLabel :: TextLabel,
		launchButton = launchButton :: TextButton,
		exitButton = exitButton :: TextButton,
	}
end

function ClientPartyMenuManager:connectCreateView(view: CreateView)
	view.map.previousButton.Activated:Connect(
		function()
			self:stepMap(-1)
		end
	)
	view.map.nextButton.Activated:Connect(
		function()
			self:stepMap(1)
		end
	)
	view.difficulty.previousButton.Activated:Connect(
		function()
			self:stepDifficulty(-1)
		end
	)
	view.difficulty.nextButton.Activated:Connect(
		function()
			self:stepDifficulty(1)
		end
	)
	view.minusButton.Activated:Connect(
		function()
			self:stepPlayers(-1)
		end
	)
	view.plusButton.Activated:Connect(
		function()
			self:stepPlayers(1)
		end
	)
	view.toggle.Activated:Connect(
		function()
			self:toggleFriendsOnly()
		end
	)
	view.createButton.Activated:Connect(
		function()
			self:sendCreate()
		end
	)
	-- GDD: Cancel behaves exactly like the creation timeout
	view.cancelButton.Activated:Connect(
		function()
			self:sendLeave()
		end
	)
end

function ClientPartyMenuManager:connectQueueView(view: QueueView)
	view.launchButton.Activated:Connect(
		function()
			self:sendLaunch()
		end
	)
	view.exitButton.Activated:Connect(
		function()
			self:sendLeave()
		end
	)
end

function ClientPartyMenuManager:loadConfig()
	local encoded = ClientDataManager:getGameMetadata(Attributes.PARTY_CONFIG)
	self.config = PartyRules.decodeConfig(encoded)
	if not self.config then
		warn("ClientPartyMenuManager: party config missing or invalid on GameMetadata")
	end
end

function ClientPartyMenuManager:init()
	self:loadConfig()
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.PARTY_CONFIG,
		function()
			self:loadConfig()
		end
	)

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local createView = self:findCreateView(playerGui)
	if createView then
		self.createView = createView
		self:connectCreateView(createView)
	end
	local queueView = self:findQueueView(playerGui)
	if queueView then
		self.queueView = queueView
		self:connectQueueView(queueView)
	end

	-- the seat holds the character and the camera is on the pad, so the
	-- overlay neither freezes, blurs, nor zooms; clicking outside does nothing
	-- because only the server ends a party menu
	local overlay: ClientOverlayManager.Overlay
	overlay = {
		getGuiRoot = function(_overlay)
			if self.activeMenu == Enums.PartyMenu.CREATE and self.createView then
				return self.createView.dialog
			end
			if self.activeMenu == Enums.PartyMenu.QUEUE and self.queueView then
				return self.queueView.dialog
			end
			return nil
		end,
		notifyForceEnd = function(_overlay)
			-- another menu took over; the pad cannot stay held behind it
			if self.activeMenu ~= Enums.PartyMenu.NONE then
				self.activeMenu = Enums.PartyMenu.NONE
				self:showGuis()
				self:setCamera(nil)
				self:setMovementLocked(false)
				ClientPadBillboardManager:setBillboardsVisible(true)
				self:sendLeave()
			end
		end,
		notifyClickOutside = function(_overlay) end,
		doesWantBlur = function(_overlay)
			return false
		end,
		doZoomCamera = function(_overlay)
			return false
		end,
		doAllowPlayerWorldActions = function(_overlay)
			return true
		end,
	}
	self.overlay = overlay

	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_PARTY_MENU,
		function(payload: any)
			self:onNotifyPartyMenu(payload)
		end
	)

	task.spawn(
		function()
			while true do
				task.wait(COUNTDOWN_REFRESH_SEC)
				if self.activeMenu ~= Enums.PartyMenu.NONE then
					self:renderCountdown()
				end
			end
		end
	)
end

function ClientPartyMenuManager.new(): ClientPartyMenuManager
	local self = setmetatable({}, ClientPartyMenuManager) :: ClientPartyMenuManager
	self.config = nil
	self.createView = nil
	self.queueView = nil
	self.overlay = nil
	self.activeMenu = Enums.PartyMenu.NONE
	self.padModel = nil
	self.padConnection = nil
	self.isHost = false
	self.mapIndex = 1
	self.difficultyIndex = 1
	self.maxPlayers = 1
	self.isFriendsOnly = false
	return self
end

return ClientPartyMenuManager.new()
