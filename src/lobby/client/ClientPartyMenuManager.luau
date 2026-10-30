--!strict

-- Drives the two pad menus (GDD "Create Party Menu" and "Queue Menu"). The
-- server says which menu to show (NotifyPartyMenu); everything shown comes
-- from the pad's replicated attributes and the party config on GameMetadata.
-- Selection state is client-side until Create sends it in one message. While
-- a menu is open the camera sits on the pad's CameraPositionPart and the
-- character stays in its helicopter seat (leaving the seat leaves the party).
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PartyRules = require("@game/ReplicatedStorage/Shared/PartyRules")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientLoadingScreenManager = require(script.Parent.Parent.Client.ClientLoadingScreenManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPadBillboardManager = require(script.Parent.ClientPadBillboardManager)

local ClientPartyMenuManager = {}
ClientPartyMenuManager.__index = ClientPartyMenuManager

type CarouselView = {
	-- optional: the map carousel has no arrows while there is one map
	-- (designer, 2026-10-30); the stepping stays for when they return
	previousButton: TextButton?,
	nextButton: TextButton?,
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
	-- the knob and the two marker frames it slides between
	toggleSwitch: GuiObject,
	toggleSwitchOff: GuiObject,
	toggleSwitchOn: GuiObject,
	-- optional: the creation countdown left the gui on 2026-10-30 (the
	-- timer runs on silently; the host hears of it only when it runs out)
	countdownLabel: TextLabel?,
	createButton: TextButton,
	cancelButton: TextButton,
}

type QueueView = {
	gui: ScreenGui,
	dialog: Frame,
	-- "<MAP> (<DIFFICULTY>)"
	mapLabel: TextLabel,
	visibilityLabel: TextLabel,
	-- "CREW (n/max)" over the slot row
	crewLabel: TextLabel,
	crewSlots: GuiObject,
	-- the designer's hidden templates: a member's picture and name, and an
	-- empty seat; both are resized to the party's size before cloning
	filledTemplate: GuiObject,
	emptyTemplate: GuiObject,
	-- the clones standing in the row, rebuilt whole on every change so the
	-- filled seats always run left to right in join order
	slotClones: { GuiObject },
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
		-- crew head shots by user id, fetched once (renderCrewSlots)
		thumbnailByUserId: { [number]: string },
		-- Create Party selection, client-side until Create
		mapIndex: number,
		difficultyIndex: number,
		maxPlayers: number,
		isFriendsOnly: boolean,
		-- set from launch until the teleport succeeds or fails: the camera stays
		-- on the pad with no menu while the helicopter flies off
		isDeparting: boolean,
		-- told when this player's pad launches with them aboard (the lobby
		-- music fades out, 2026-10-14), and when a failed teleport brings
		-- them back (it fades in again)
		departingHandlers: { () -> () },
		returnedHandlers: { () -> () },
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
-- a leaver stands this far above the ExitSpawn part, clear of it (the
-- server's fallback move uses the same lift)
local EXIT_LIFT = Vector3.new(0, 3, 0)
-- the Queue Menu's lines (designer, 2026-10-30), formatted as titles
local MAP_FORMAT = "%s (%s)"
local CREW_FORMAT = "Crew (%d/%d)"
local VISIBILITY_PRIVATE = "Private"
local VISIBILITY_PUBLIC = "Public"
-- a member whose name has not reached this client yet
local UNKNOWN_MEMBER_NAME = "?"
local DEPARTURE_CAPTION = "Flying to %s..."
-- players get a look at their helicopter lifting off before the screen comes in
local DEPARTURE_SCREEN_DELAY_SEC = 2
local MENU_FADE_SEC = 0.4
local MENU_FADE_SETTLE_SEC = 0.1
-- the switch's knob slides and its track recolours over this long; the
-- first draw of a menu snaps
local TOGGLE_TWEEN_SEC = UiStyle.HUD_TWEEN_SEC
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
	-- the arrows are looked up without a warning: a carousel with one entry
	-- is authored without them
	local previousButton = frame:FindFirstChild(Constants.CAROUSEL_PREVIOUS_BUTTON, true)
	local nextButton = frame:FindFirstChild(Constants.CAROUSEL_NEXT_BUTTON, true)
	local thumbnail = findChild(frame, Constants.CAROUSEL_THUMBNAIL, "ImageLabel")
	local nameLabel = findChild(frame, Constants.CAROUSEL_NAME_LABEL, "TextLabel")
	local lockIcon = findChild(frame, Constants.CAROUSEL_LOCK_ICON, "TextLabel")
	local requirementLabel = findChild(frame, Constants.CAROUSEL_REQUIREMENT_LABEL, "TextLabel")
	if not (thumbnail and nameLabel and lockIcon and requirementLabel) then
		return nil
	end
	return {
		previousButton = if previousButton and previousButton:IsA("TextButton") then previousButton else nil,
		nextButton = if nextButton and nextButton:IsA("TextButton") then nextButton else nil,
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

-- the Friends Only switch: the knob at the SwitchOn marker on a green
-- track when on, at SwitchOff on a red one when off (designer, 2026-10-30).
-- The markers are the designer's invisible frames, so the knob's resting
-- spots are tuned in the Explorer; a tap slides it, the menu opening snaps
function ClientPartyMenuManager:renderToggle(view: CreateView, isAnimated: boolean)
	local isOn = self.isFriendsOnly
	local marker = if isOn then view.toggleSwitchOn else view.toggleSwitchOff
	local trackColor = if isOn then UiStyle.TOGGLE_ON_COLOR else UiStyle.TOGGLE_OFF_COLOR
	if not isAnimated then
		view.toggleSwitch.Position = marker.Position
		view.toggle.BackgroundColor3 = trackColor
		return
	end
	local tweenInfo = TweenInfo.new(TOGGLE_TWEEN_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(view.toggleSwitch, tweenInfo, { Position = marker.Position }):Play()
	TweenService:Create(view.toggle, tweenInfo, { BackgroundColor3 = trackColor }):Play()
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

	self:renderToggle(view, false)

	local isUnlocked = self:isSelectionUnlocked()
	view.createButton.Active = isUnlocked
	view.createButton.AutoButtonColor = isUnlocked
	view.createButton.BackgroundColor3 = if isUnlocked then UiStyle.ACCENT_COLOR else UiStyle.DISABLED_COLOR
	self:renderCountdown()
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
	local mapName = Enums.getPublicName(Enums.Map, map) or ""
	local difficultyName = Enums.getPublicName(Enums.Difficulty, difficulty) or ""
	view.mapLabel.Text = UiStyle.formatTitle(string.format(MAP_FORMAT, mapName, difficultyName))
	local isPrivate = visibility == Enums.PartyVisibility.FRIENDS_ONLY
	view.visibilityLabel.Text = UiStyle.formatTitle(if isPrivate then VISIBILITY_PRIVATE else VISIBILITY_PUBLIC)
	view.visibilityLabel.TextColor3 = if isPrivate then UiStyle.NEGATIVE_COLOR else UiStyle.POSITIVE_COLOR
	local maxPlayers = getAttributeNumber(padModel, Attributes.PAD_MAX_PLAYERS)
	local memberUserIds = PartyRules.decodeMemberUserIds(padModel:GetAttribute(Attributes.PAD_MEMBER_USER_IDS))
	view.crewLabel.Text = UiStyle.formatTitle(string.format(CREW_FORMAT, #memberUserIds, maxPlayers))
	self:renderCrewSlots(view, memberUserIds, maxPlayers)
	view.launchButton.Visible = self.isHost
	self:renderCountdown()
end

-- a member's display name: the replicated public data first, then the
-- Player if they are in this place, else a placeholder
local function memberDisplayName(userId: number): string
	local publicData = ClientDataManager:getPlayerPublicData(userId)
	if publicData then
		return publicData.displayName
	end
	local player = Players:GetPlayerByUserId(userId)
	return if player then player.DisplayName else UNKNOWN_MEMBER_NAME
end

-- the crew row (designer, 2026-10-30): one slot per seat of the party, the
-- members in join order from the left (the host first) as Filled clones,
-- the rest Empty clones, each slot's LayoutOrder its seat number. The row is
-- rebuilt whole on every pad change: a join fills the first empty seat and
-- a leave closes the gap, with nothing to shuffle by hand
function ClientPartyMenuManager:renderCrewSlots(view: QueueView, memberUserIds: { number }, maxPlayers: number)
	for _, clone in view.slotClones do
		clone:Destroy()
	end
	table.clear(view.slotClones)
	local widthScale = PartyRules.crewSlotWidthScale(maxPlayers)
	for _, template in { view.filledTemplate, view.emptyTemplate } do
		template.Size = UDim2.fromScale(widthScale, template.Size.Y.Scale)
	end
	for seat = 1, maxPlayers do
		local userId = memberUserIds[seat]
		local template = if userId then view.filledTemplate else view.emptyTemplate
		local clone = template:Clone()
		clone.Name = `Slot{seat}`
		clone.LayoutOrder = seat
		clone.Visible = true
		if userId then
			local nameLabel = clone:FindFirstChild(Constants.QUEUE_CREW_DISPLAY_NAME, true)
			if nameLabel and nameLabel:IsA("TextLabel") then
				nameLabel.Text = UiStyle.formatTitle(memberDisplayName(userId))
			end
			local thumbnail = clone:FindFirstChild(Constants.QUEUE_CREW_THUMBNAIL, true)
			if thumbnail and thumbnail:IsA("ImageLabel") then
				self:applyThumbnail(thumbnail, userId)
			end
		end
		clone.Parent = view.crewSlots
		table.insert(view.slotClones, clone)
	end
end

-- the member's head shot, fetched once per user id and remembered, so a
-- rebuilt row never refetches; a label gone by the time it arrives is skipped
function ClientPartyMenuManager:applyThumbnail(label: ImageLabel, userId: number)
	local cached = self.thumbnailByUserId[userId]
	if cached then
		label.Image = cached
		return
	end
	task.spawn(
		function()
			local isSuccess, image = pcall(
				function()
					return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
				end
			)
			if not isSuccess or typeof(image) ~= "string" then
				return
			end
			self.thumbnailByUserId[userId] = image
			if label.Parent then
				label.Image = image
			end
		end
	)
end

function ClientPartyMenuManager:renderCountdown()
	local padModel = self.padModel
	if not padModel then
		return
	end
	local endTime = getAttributeNumber(padModel, Attributes.PAD_TIMER_END_TIME)
	local remaining = math.max(0, math.ceil(endTime - workspace:GetServerTimeNow()))
	local createView = self.createView
	if self.activeMenu == Enums.PartyMenu.CREATE and createView and createView.countdownLabel then
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
function ClientPartyMenuManager:setMovementLocked(isLocked: boolean, padModel: Model?)
	local character = Players.LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not character or not humanoid then
		return
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not isLocked)
	-- a humanoid leaves a seat by jumping, which the lock forbade, so one
	-- unseated by the server stayed Seated: stiff, and toppling once moved
	-- (2026-10-30). This client owns its character's state and physics, so it
	-- stands up itself once free and, in the same frame, steps clear to the
	-- pad's ExitSpawn with no momentum: the stand-up's hop inside the cabin
	-- caught the helicopter's geometry (Climbing) and a later move from the
	-- server sent the body off tumbling. The server's own move is a fallback
	if not isLocked and (humanoid.Sit or humanoid:GetState() == Enum.HumanoidStateType.Seated) then
		humanoid.Sit = false
		local exitSpawn = if padModel then padModel:FindFirstChild(Constants.PAD_EXIT_SPAWN_PART) else nil
		local root = humanoid.RootPart
		if exitSpawn and exitSpawn:IsA("BasePart") and root then
			local facing = exitSpawn.CFrame.LookVector * Vector3.new(1, 0, 1)
			local standPosition = exitSpawn.Position + EXIT_LIFT
			character:PivotTo(CFrame.lookAlong(standPosition, if facing.Magnitude > 0 then facing.Unit else Vector3.zAxis))
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end
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

-- fades every part of a dialog to invisible, then disables its ScreenGui and
-- puts the transparencies back so the next open is untouched
local function fadeOutGui(gui: ScreenGui, dialog: Frame)
	local tweenInfo = TweenInfo.new(MENU_FADE_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local originals: { [Instance]: { [string]: number } } = {}
	local tweens: { Tween } = {}
	local function fadeProperty(instance: Instance, property: string)
		local current = (instance :: any)[property]
		if typeof(current) ~= "number" then
			return
		end
		originals[instance] = originals[instance] or {}
		originals[instance][property] = current
		local tween = TweenService:Create(instance, tweenInfo, { [property] = 1 })
		table.insert(tweens, tween)
		tween:Play()
	end
	for _, descendant in dialog:GetDescendants() do
		if descendant:IsA("GuiObject") then
			fadeProperty(descendant, "BackgroundTransparency")
		end
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			fadeProperty(descendant, "TextTransparency")
		end
		if descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			fadeProperty(descendant, "ImageTransparency")
		end
		if descendant:IsA("UIStroke") then
			fadeProperty(descendant, "Transparency")
		end
	end
	fadeProperty(dialog, "BackgroundTransparency")
	-- the tweens are cancelled before the values go back, otherwise one that
	-- finishes a frame late writes "invisible" over the restored value and
	-- the next open shows an empty dialog
	task.delay(
		MENU_FADE_SEC + MENU_FADE_SETTLE_SEC,
		function()
			gui.Enabled = false
			for _, tween in tweens do
				tween:Cancel()
			end
			for instance, properties in originals do
				for property, value in properties do
					(instance :: any)[property] = value
				end
			end
		end
	)
end

function ClientPartyMenuManager:closeMenu()
	if self.activeMenu == Enums.PartyMenu.NONE and not self.isDeparting then
		return
	end
	local wasDeparting = self.isDeparting
	self.activeMenu = Enums.PartyMenu.NONE
	self.isDeparting = false
	if wasDeparting then
		for _, handler in self.returnedHandlers do
			handler()
		end
	end
	self:showGuis()
	local padConnection = self.padConnection
	if padConnection then
		padConnection:Disconnect()
		self.padConnection = nil
	end
	local padModel = self.padModel
	self.padModel = nil
	self:setCamera(nil)
	self:setMovementLocked(false, padModel)
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
				if self.activeMenu ~= Enums.PartyMenu.QUEUE then
					return
				end
				if padModel:GetAttribute(Attributes.PAD_STATE) == Enums.PadState.DEPARTING then
					self:onDeparting(padModel)
					return
				end
				self:renderQueue()
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

-- the pad launched with us aboard: the menu goes, the departure screen comes
-- in over the takeoff. Only a failed teleport brings us back (menu NONE).
function ClientPartyMenuManager:subscribeDeparting(handler: () -> ())
	table.insert(self.departingHandlers, handler)
end

function ClientPartyMenuManager:subscribeReturned(handler: () -> ())
	table.insert(self.returnedHandlers, handler)
end

function ClientPartyMenuManager:onDeparting(padModel: Model)
	for _, handler in self.departingHandlers do
		handler()
	end
	local map = getAttributeNumber(padModel, Attributes.PAD_MAP)
	local mapName = Enums.getPublicName(Enums.Map, map) or "the mine"
	-- the menu fades but everything else stays: camera on the pad, billboards
	-- hidden, HUD away, so the takeoff is watched from the pad's viewpoint
	self.activeMenu = Enums.PartyMenu.NONE
	self.isDeparting = true
	local queueView = self.queueView
	if queueView and queueView.gui.Enabled then
		fadeOutGui(queueView.gui, queueView.dialog)
	end
	task.delay(
		DEPARTURE_SCREEN_DELAY_SEC,
		function()
			if not self.isDeparting then
				return
			end
			ClientLoadingScreenManager:showDeparture(string.format(DEPARTURE_CAPTION, mapName))
		end
	)
end

function ClientPartyMenuManager:onNotifyPartyMenu(payload: any)
	local isValid, err = Validate.isTableShape(payload, NOTIFY_PARTY_MENU_SHAPE)
	if not isValid then
		warn("ClientPartyMenuManager: bad NotifyPartyMenu payload:", err)
		return
	end
	if payload.menu == Enums.PartyMenu.NONE then
		self:closeMenu()
		ClientLoadingScreenManager:hideDeparture()
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
	-- the tap slides the knob over the snap renderCreate just drew
	local view = self.createView
	if view then
		self:renderToggle(view, true)
	end
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
	local gui = playerGui:WaitForChild(Constants.CREATE_PARTY_GUI_NAME, Constants.GUI_WAIT_SEC)
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
	local toggleRow = findChild(gui, Constants.CREATE_PARTY_FRIENDS_ONLY_ROW, "Frame")
	local toggle = if toggleRow then findChild(toggleRow, Constants.CREATE_PARTY_FRIENDS_ONLY_TOGGLE, "TextButton") else nil
	local toggleSwitch = if toggle then findChild(toggle, Constants.TOGGLE_SWITCH, "GuiObject") else nil
	local toggleSwitchOff = if toggle then findChild(toggle, Constants.TOGGLE_SWITCH_OFF, "GuiObject") else nil
	local toggleSwitchOn = if toggle then findChild(toggle, Constants.TOGGLE_SWITCH_ON, "GuiObject") else nil
	-- looked up quietly: the gui is authored without it
	local countdownLabel = gui:FindFirstChild(Constants.CREATE_PARTY_COUNTDOWN_LABEL, true)
	local createButton = findChild(gui, Constants.CREATE_PARTY_CREATE_BUTTON, "TextButton")
	local cancelButton = findChild(gui, Constants.CREATE_PARTY_CANCEL_BUTTON, "TextButton")
	if not (dialog and map and difficulty and minusButton and plusButton and valueLabel and toggle and toggleSwitch and toggleSwitchOff and toggleSwitchOn and createButton and cancelButton) then
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
		toggleSwitch = toggleSwitch :: GuiObject,
		toggleSwitchOff = toggleSwitchOff :: GuiObject,
		toggleSwitchOn = toggleSwitchOn :: GuiObject,
		countdownLabel = if countdownLabel and countdownLabel:IsA("TextLabel") then countdownLabel else nil,
		createButton = createButton :: TextButton,
		cancelButton = cancelButton :: TextButton,
	}
end

function ClientPartyMenuManager:findQueueView(playerGui: PlayerGui): QueueView?
	local gui = playerGui:WaitForChild(Constants.QUEUE_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`ClientPartyMenuManager: no {Constants.QUEUE_GUI_NAME} ScreenGui; run scripts/studio/build_queue_gui.luau`)
		return nil
	end
	local dialog = findChild(gui, Constants.MENU_DIALOG_FRAME, "Frame")
	local mapLabel = findChild(gui, Constants.QUEUE_MAP_LABEL, "TextLabel")
	local visibilityLabel = findChild(gui, Constants.QUEUE_VISIBILITY_LABEL, "TextLabel")
	local crewFrame = findChild(gui, Constants.QUEUE_CREW_FRAME, "Frame")
	-- the heading is the panel's one TextLabel child, unnamed by design
	local crewLabel = if crewFrame then crewFrame:FindFirstChildWhichIsA("TextLabel") else nil
	if crewFrame and not crewLabel then
		warn(`ClientPartyMenuManager: {crewFrame:GetFullName()} has no TextLabel heading`)
	end
	local crewSlots = if crewFrame then findChild(crewFrame, Constants.QUEUE_CREW_SLOTS, "GuiObject") else nil
	local filledTemplate = if crewSlots then findChild(crewSlots, Constants.QUEUE_CREW_FILLED_TEMPLATE, "GuiObject") else nil
	local emptyTemplate = if crewSlots then findChild(crewSlots, Constants.QUEUE_CREW_EMPTY_TEMPLATE, "GuiObject") else nil
	-- the countdown and the buttons live in the Buttons frame (2026-10-30),
	-- found by name wherever the designer keeps them
	local buttons = findChild(gui, Constants.QUEUE_BUTTONS_FRAME, "Frame") or gui
	local countdownLabel = findChild(buttons, Constants.QUEUE_COUNTDOWN_LABEL, "TextLabel")
	local launchButton = findChild(buttons, Constants.QUEUE_LAUNCH_BUTTON, "TextButton")
	local exitButton = findChild(buttons, Constants.QUEUE_EXIT_BUTTON, "TextButton")
	if not (dialog and mapLabel and visibilityLabel and crewLabel and crewSlots and filledTemplate and emptyTemplate and countdownLabel and launchButton and exitButton) then
		return nil
	end
	return {
		gui = gui,
		dialog = dialog :: Frame,
		mapLabel = mapLabel :: TextLabel,
		visibilityLabel = visibilityLabel :: TextLabel,
		crewLabel = crewLabel :: TextLabel,
		crewSlots = crewSlots :: GuiObject,
		filledTemplate = filledTemplate :: GuiObject,
		emptyTemplate = emptyTemplate :: GuiObject,
		slotClones = {},
		countdownLabel = countdownLabel :: TextLabel,
		launchButton = launchButton :: TextButton,
		exitButton = exitButton :: TextButton,
	}
end

-- a carousel's arrows step it when the gui has them
local function connectCarousel(carousel: CarouselView, step: (number) -> ())
	if carousel.previousButton then
		carousel.previousButton.Activated:Connect(
			function()
				step(-1)
			end
		)
	end
	if carousel.nextButton then
		carousel.nextButton.Activated:Connect(
			function()
				step(1)
			end
		)
	end
end

function ClientPartyMenuManager:connectCreateView(view: CreateView)
	connectCarousel(
		view.map,
		function(direction: number)
			self:stepMap(direction)
		end
	)
	connectCarousel(
		view.difficulty,
		function(direction: number)
			self:stepDifficulty(direction)
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
				self:setMovementLocked(false, self.padModel)
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
	self.thumbnailByUserId = {}
	self.departingHandlers = {}
	self.returnedHandlers = {}
	self.mapIndex = 1
	self.difficultyIndex = 1
	self.maxPlayers = 1
	self.isFriendsOnly = false
	self.isDeparting = false
	return self
end

return ClientPartyMenuManager.new()
