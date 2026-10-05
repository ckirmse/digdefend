--!strict

-- Death and revives on this client (GDD "Health and Revives", "Results
-- Menu"), M32. The server owns who is dead; this draws it. When this
-- player's public IsDead turns true the Results Menu opens (StarterGui
-- .ResultsMenu, scripts/studio/build_results_menu_gui.luau): the run's
-- stats from CurrentPlayer, a countdown, the Revive button for whatever
-- the server is offering (the player's own Revive or the crew's Team
-- Revive, with its live Robux price from GameMetadata, or "FREE" when a
-- saved credit will pay), and Spectate. Pressing Revive only sends
-- TryRevive; the server opens Roblox's purchase prompt. The same menu
-- shows once more when the run ends, with Close in place of the buttons
-- (Return to Base is M33). Graves are dressed here too: each
-- Tags.TOMBSTONE shadow gets a clone of the designer's GameAssets.Grave
-- with the name, the face, and the day written on its stone. While this
-- player is dead and not spectating, the camera stands on their own
-- grave's CameraLocation part, so the stone shows beside the menu.
-- Roblox's own Reset Character is switched off, since a respawn would be
-- a free heal.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local RunStatsRules = require("@game/ReplicatedStorage/Shared/RunStatsRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local utils = require("@game/ReplicatedStorage/Shared/utils")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientSpectateManager = require(script.Parent.ClientSpectateManager)
local ClientStructureManager = require(script.Parent.ClientStructureManager)

local ClientReviveManager = {}
ClientReviveManager.__index = ClientReviveManager

type StatRow = {
	valueLabel: TextLabel,
	attribute: string,
	rankAttribute: string,
	-- this player's place in the crew, and where the number sits when
	-- that column shows
	rankLabel: TextLabel?,
	authoredValuePosition: UDim2,
	-- a resource row: its name and the icon that follows the name
	nameLabel: TextLabel?,
	icon: ImageLabel?,
}

type AuthoredLayout = {
	statsSize: UDim2,
	countdownPosition: UDim2,
	revivePosition: UDim2,
	reviveSize: UDim2,
}

export type ClientReviveManager = typeof(setmetatable(
	{} :: {
		menuGui: ScreenGui?,
		menuDialog: GuiObject?,
		titleLabel: TextLabel?,
		countdownLabel: TextLabel?,
		reviveButton: GuiButton?,
		reviveLabel: TextLabel?,
		revivePriceLabel: TextLabel?,
		spectateButton: GuiButton?,
		closeButton: GuiButton?,
		rankHeaderLabel: TextLabel?,
		statsFrame: GuiObject?,
		-- the layout as authored, so the filled one can be undone
		authoredLayout: AuthoredLayout?,
		isLayoutFilled: boolean,
		statRows: { StatRow },
		overlay: ClientOverlayManager.Overlay?,
		isMenuOpen: boolean,
		-- the HUD ScreenGuis switched off while the death menu is up, to switch back on
		hiddenHudGuis: { ScreenGui },
		isHudHidden: boolean,
		-- the Game Over screen: its gui and label, the black fade, the red
		-- tint on the camera, and a counter that cancels a screen in flight
		gameOverGui: ScreenGui?,
		gameOverLabel: TextLabel?,
		fadeGui: ScreenGui?,
		fadeFrame: GuiObject?,
		fadeTween: Tween?,
		colorCorrection: ColorCorrectionEffect?,
		gameOverGeneration: number,
		isGameOverPlaying: boolean,
		-- the death view: the camera circling the fallen body, and how far
		-- round it has gone, in radians
		isDeathViewOn: boolean,
		deathViewAngle: number,
		-- what it circles when that is not the player's own body: the Refinery
		deathViewTarget: Vector3?,
		-- the camera mode the death view replaced (the first-person lock)
		savedCameraMode: Enum.CameraMode?,
		isDead: boolean,
		hasShownRunEnd: boolean,
		stepAccumulatorSec: number,
		graveTemplate: Model?,
		graveFolder: Folder?,
		graveByShadow: { [Instance]: Model },
		-- this player's own grave, where the camera stands while they are dead
		ownGrave: Model?,
	},
	ClientReviveManager
))

local NOTIFY_REVIVE_ANNOUNCEMENT_SHAPE = {
	message = "string",
	displaySec = "positiveNumber",
	isAlert = "boolean",
}

local STEP_INTERVAL_SEC = 0.25
-- the space between a stat row's words and its resource icon, as a share
-- of the words' height
local ICON_GAP_SHARE_OF_ROW = 0.35
-- with the bottom slot empty, how much of the freed height the stat rows
-- take; the Revive button takes the rest
local LAYOUT_STATS_SHARE = 0.6
local GRAVE_FOLDER = "Graves"
local GRAVE_DAY_FORMAT = "Day %d"
-- the Game Over screen (designer's values, 2026-10-05): the words, the
-- red tint put on the camera, and how long to wait in the dark for the
-- player's own grave to stream in before showing the menu anyway
local GAME_OVER_DEAD_TEXT = "You died"
local GAME_OVER_REFINERY_TEXT = "The Refinery has been destroyed"
local GAME_OVER_TINT_BRIGHTNESS = 0.2
local GAME_OVER_TINT_CONTRAST = 0
local GAME_OVER_TINT_SATURATION = 0
local GAME_OVER_TINT_COLOR = Color3.fromRGB(255, 0, 4)
local GAME_OVER_TINT_NAME = "GameOverTint"
-- the camera's slow circle round the fallen body: how far out and how
-- high it sits, how fast it goes round, and how far it stays off a wall
local DEATH_VIEW_DISTANCE_STUDS = 12
local DEATH_VIEW_HEIGHT_STUDS = 7
local DEATH_VIEW_DEGREES_PER_SEC = 14
local DEATH_VIEW_WALL_GAP_STUDS = 0.5
-- Roblox's LocalScript in every character that plays its animations
local ANIMATE_SCRIPT = "Animate"
-- and round the Refinery when it is the Refinery that fell: further out
-- and higher, since it is a building
-- (35% closer since 2026-10-05: at 45 out the camera ran into the cliffs
-- round the camp; the height came down with it to keep the same angle)
local REFINERY_VIEW_DISTANCE_STUDS = 29
local REFINERY_VIEW_HEIGHT_STUDS = 16
-- the Game Over song starts as the fade to black begins and loops; this
-- is how long it takes to fade when the player leaves the Results Menu
local GAME_OVER_MUSIC_FADE_SEC = 3
local GAME_OVER_GRAVE_WAIT_SEC = 3
local GAME_OVER_GRAVE_POLL_SEC = 0.1
local DEFAULT_GAME_OVER_HOLD_SEC = 6
local DEFAULT_GAME_OVER_FADE_IN_SEC = 2
local DEFAULT_GAME_OVER_BLACK_HOLD_SEC = 3
local DEFAULT_GAME_OVER_FADE_OUT_SEC = 3
local TITLE_DEAD = "You died"
local TITLE_WON = "Run won"
local TITLE_LOST = "Run lost"
local REVIVE_SELF_TEXT = "Revive"
local REVIVE_TEAM_TEXT = "Revive crew and restart the day"
-- the Spectate bar's button is small, so the crew's revive is said shorter there
local SPECTATE_REVIVE_TEAM_TEXT = "Revive crew"
local SPECTATE_TIMER_FORMAT = "%d s"
local COUNTDOWN_SELF_FORMAT = "Revive available for %d s"
local COUNTDOWN_TEAM_FORMAT = "The whole crew is down. %d s to revive"
local COUNTDOWN_NONE_TEXT = "A crewmate can still revive you at your tombstone"
local PRICE_FREE_TEXT = "FREE"
-- the Robux mark, a glyph in Roblox's own fonts
local PRICE_FORMAT = "\u{E002} %d"
-- ScreenGuis the death menu leaves on: the data tree (not a HUD at all),
-- the overlay's click-catching backdrop, and the feedback text
local HUD_KEPT_GUI_NAMES: { [string]: boolean } = {
	[Constants.SPLENDID_GAMES_NAME] = true,
	[Constants.OVERLAY_BACKDROP_GUI_NAME] = true,
	[Constants.PLAYER_FEEDBACK_GUI_NAME] = true,
	[Constants.GAME_OVER_GUI_NAME] = true,
	-- the Spectate bar is what a dead player steers by
	[Constants.SPECTATE_GUI_NAME] = true,
}
local RESET_BUTTON_RETRY_SEC = 1
local RESET_BUTTON_ATTEMPTS = 10

local REVIVE_KIND_BY_OFFER: { [number]: number } = {
	[Enums.ReviveOffer.SELF] = Enums.ReviveKind.SELF,
	[Enums.ReviveOffer.TEAM] = Enums.ReviveKind.TEAM,
}

local PRICE_ATTRIBUTE_BY_KIND: { [number]: string } = {
	[Enums.ReviveKind.SELF] = Attributes.REVIVE_PRICE_SELF,
	[Enums.ReviveKind.TEAM] = Attributes.REVIVE_PRICE_TEAM,
}

local CREDIT_ATTRIBUTE_BY_KIND: { [number]: string } = {
	[Enums.ReviveKind.SELF] = Attributes.REVIVE_CREDITS_SELF,
	[Enums.ReviveKind.TEAM] = Attributes.REVIVE_CREDITS_TEAM,
}

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

local function readStat(attributeName: string): number
	return readNumber(ClientDataManager:getCurrentPlayerAttribute(attributeName), 0)
end

function ClientReviveManager:getIsDead(): boolean
	return self.isDead
end

function ClientReviveManager:getRunState(): number
	return readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_STATE), Enums.RunState.WAITING)
end

function ClientReviveManager:isRunOver(): boolean
	local state = self:getRunState()
	return state == Enums.RunState.WON or state == Enums.RunState.LOST
end

function ClientReviveManager:getOffer(): number
	return readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.REVIVE_OFFER), Enums.ReviveOffer.NONE)
end

function ClientReviveManager:renderStats()
	-- the Group Rank column is for a crew; a solo player's numbers take
	-- its place at the right edge
	local isGroup = ClientDataManager:getGameMetadata(Attributes.RUN_IS_GROUP) == true
	if self.rankHeaderLabel then
		self.rankHeaderLabel.Visible = isGroup
	end
	for _, row in self.statRows do
		row.valueLabel.Text = utils.abbreviateNumber(readStat(row.attribute))
		row.valueLabel.Position = if isGroup then row.authoredValuePosition else UDim2.new(1, 0, row.authoredValuePosition.Y.Scale, row.authoredValuePosition.Y.Offset)
		local rankLabel = row.rankLabel
		if rankLabel then
			rankLabel.Visible = isGroup
			rankLabel.Text = RunStatsRules.ordinal(readStat(row.rankAttribute))
		end
		-- the icon sits right after the row's words. Scaled text ends at a
		-- different place on every screen, so this is the one position set
		-- in pixels, from the measured width of the words
		local nameLabel = row.nameLabel
		local icon = row.icon
		if nameLabel and icon and icon.Visible then
			local gap = nameLabel.AbsoluteSize.Y * ICON_GAP_SHARE_OF_ROW
			icon.Position = UDim2.new(0, math.ceil(nameLabel.TextBounds.X + gap), 0.5, 0)
		end
	end
end

function ClientReviveManager:renderRevive()
	local isRunOver = self:isRunOver()
	local offer = if isRunOver or not self.isDead then Enums.ReviveOffer.NONE else self:getOffer()
	local reviveKind = REVIVE_KIND_BY_OFFER[offer]
	local reviveButton = self.reviveButton
	if reviveButton then
		reviveButton.Visible = reviveKind ~= nil
	end
	if reviveKind then
		if self.reviveLabel then
			self.reviveLabel.Text = UiStyle.formatTitle(if reviveKind == Enums.ReviveKind.TEAM then REVIVE_TEAM_TEXT else REVIVE_SELF_TEXT)
		end
		if self.revivePriceLabel then
			self.revivePriceLabel.Text = self:getPriceText(reviveKind)
		end
	end
	local countdownLabel = self.countdownLabel
	if countdownLabel then
		countdownLabel.Visible = self.isDead and not isRunOver
		local endTime = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.REVIVE_OFFER_END_TIME), 0)
		local secondsLeft = math.max(0, math.ceil(endTime - workspace:GetServerTimeNow()))
		if offer == Enums.ReviveOffer.TEAM then
			countdownLabel.Text = string.format(COUNTDOWN_TEAM_FORMAT, secondsLeft)
		elseif offer == Enums.ReviveOffer.SELF then
			countdownLabel.Text = string.format(COUNTDOWN_SELF_FORMAT, secondsLeft)
		else
			countdownLabel.Text = COUNTDOWN_NONE_TEXT
		end
	end
	-- Spectate while dead and someone is alive to watch; Close otherwise
	local canSpectate = self.isDead and not isRunOver and ClientSpectateManager:hasTargets()
	if self.spectateButton then
		self.spectateButton.Visible = canSpectate
	end
	if self.closeButton then
		self.closeButton.Visible = isRunOver
	end
	self:setLayoutFilled(not canSpectate and not isRunOver)
end

-- with neither Spectate nor Close showing, the slot at the bottom of the
-- panel is empty, so the stats and the Revive button grow into it: the
-- stats take LAYOUT_STATS_SHARE of the freed height and the button the
-- rest, and the countdown moves down between them. Everything is worked
-- out from the authored layout, so the designer's tuning carries over
function ClientReviveManager:setLayoutFilled(isFilled: boolean)
	local layout = self.authoredLayout
	local stats = self.statsFrame
	local countdown = self.countdownLabel
	local revive = self.reviveButton
	local spectate = self.spectateButton
	if not layout or not stats or not countdown or not revive or not spectate or isFilled == self.isLayoutFilled then
		return
	end
	self.isLayoutFilled = isFilled
	if not isFilled then
		stats.Size = layout.statsSize
		countdown.Position = layout.countdownPosition
		revive.Position = layout.revivePosition
		revive.Size = layout.reviveSize
		return
	end
	-- what is free below the authored Revive button, down to the panel's bottom
	local freed = 1 - (layout.revivePosition.Y.Scale + layout.reviveSize.Y.Scale)
	local statsGrowth = freed * LAYOUT_STATS_SHARE
	local function lower(position: UDim2): UDim2
		return UDim2.new(position.X.Scale, position.X.Offset, position.Y.Scale + statsGrowth, position.Y.Offset)
	end
	local function taller(size: UDim2, growth: number): UDim2
		return UDim2.new(size.X.Scale, size.X.Offset, size.Y.Scale + growth, size.Y.Offset)
	end
	stats.Size = taller(layout.statsSize, statsGrowth)
	countdown.Position = lower(layout.countdownPosition)
	revive.Position = lower(layout.revivePosition)
	revive.Size = taller(layout.reviveSize, freed - statsGrowth)
end

function ClientReviveManager:renderMenu()
	if self.titleLabel then
		local state = self:getRunState()
		local title = if state == Enums.RunState.WON then TITLE_WON elseif state == Enums.RunState.LOST then TITLE_LOST else TITLE_DEAD
		self.titleLabel.Text = UiStyle.formatTitle(title)
	end
	self:renderStats()
	self:renderRevive()
end

-- a dead player looking at the Results Menu sees the menu and their grave
-- and nothing else: every HUD ScreenGui (anything below the menu layer)
-- and Roblox's own health bar are switched off, and switched back on
-- when the menu closes. Feedback text stays, since it is how a purchase
-- or a revive answers. A HUD element that switches itself on meanwhile
-- (the day card) is switched off again and left off: its moment has passed
function ClientReviveManager:setHudHidden(isHidden: boolean)
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end
	if not isHidden then
		if not self.isHudHidden then
			return
		end
		self.isHudHidden = false
		for _, gui in self.hiddenHudGuis do
			if gui.Parent then
				gui.Enabled = true
			end
		end
		self.hiddenHudGuis = {}
		pcall(
			function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, true)
			end
		)
		return
	end
	local isFirstPass = not self.isHudHidden
	self.isHudHidden = true
	for _, gui in playerGui:GetChildren() do
		if not gui:IsA("ScreenGui") or not gui.Enabled or gui.DisplayOrder >= ClientOverlayManager.MENU_DISPLAY_ORDER or HUD_KEPT_GUI_NAMES[gui.Name] then
			continue
		end
		gui.Enabled = false
		if isFirstPass then
			table.insert(self.hiddenHudGuis, gui)
		end
	end
	if isFirstPass then
		pcall(
			function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			end
		)
	end
end

function ClientReviveManager:closeMenu()
	if not self.isMenuOpen then
		return
	end
	self.isMenuOpen = false
	-- the HUD stays away for as long as the player is dead: it is no use
	-- to them and sits over the Spectate bar
	if not self.isDead then
		self:setHudHidden(false)
	end
	if self.menuGui then
		self.menuGui.Enabled = false
	end
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

function ClientReviveManager:openMenu()
	local menuGui = self.menuGui
	local overlay = self.overlay
	if not menuGui or not overlay or self.isMenuOpen then
		return
	end
	ClientSpectateManager:stop()
	self.isMenuOpen = true
	self:renderMenu()
	menuGui.Enabled = true
	ClientOverlayManager:notifyBeginOverlay(overlay)
	self:setHudHidden(self.isDead)
end

-- a limp body must not be animated: the joint that holds the root part
-- stays live (the camera follows it), and the idle and walk animations
-- still playing on it kept shoving the body about, which read as the
-- body turning on the spot (2026-10-05). Roblox's Animate script is
-- switched off and every playing track stopped; switching the script
-- back on starts the animations again
function ClientReviveManager:setAnimationsStopped(character: Model, isStopped: boolean)
	local animate = character:FindFirstChild(ANIMATE_SCRIPT)
	if animate and animate:IsA("LocalScript") then
		animate.Enabled = not isStopped
	end
	if not isStopped then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
	end
end

-- the death view (designer, 2026-10-05): while the Game Over screen is up
-- the camera circles slowly from above (stepDeathView). For a death it
-- circles the player's own body: the server has made the body limp
-- (Ragdoll), and here its Humanoid is put in the Physics state so it
-- stops trying to stand and is told not to turn with the camera (in first
-- person Roblox turns the character to face where the camera looks, which
-- spun the body with the orbit). For the Refinery falling it circles the
-- Refinery, and the character is left alone. Turning the view off puts
-- the Humanoid back and leaves the camera to whoever takes it next: the
-- grave view, or the player's own eyes after a revive
function ClientReviveManager:setDeathView(isOn: boolean, refineryPosition: Vector3?)
	if isOn == self.isDeathViewOn then
		return
	end
	self.isDeathViewOn = isOn
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if isOn then
		self.deathViewTarget = refineryPosition
		-- the first-person lock keeps the player's own body invisible, so
		-- it is lifted for as long as the body is what they are looking at
		self.savedCameraMode = player.CameraMode
		player.CameraMode = Enum.CameraMode.Classic
		-- the orbit starts behind where the player was looking
		if camera then
			local look = camera.CFrame.LookVector
			self.deathViewAngle = math.atan2(-look.X, -look.Z)
			camera.CameraType = Enum.CameraType.Scriptable
		end
		if humanoid and character and not refineryPosition then
			humanoid.AutoRotate = false
			humanoid.PlatformStand = true
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			self:setAnimationsStopped(character, true)
		end
		-- first person leaves Roblox set to turn the character with the
		-- camera, and nothing resets that while the camera is scripted;
		-- Roblox's own camera puts it back once the player is in first
		-- person again
		UserGameSettings.RotationType = Enum.RotationType.MovementRelative
		return
	end
	local wasOnBody = self.deathViewTarget == nil
	self.deathViewTarget = nil
	player.CameraMode = self.savedCameraMode or Enum.CameraMode.LockFirstPerson
	if humanoid and character and wasOnBody then
		humanoid.AutoRotate = true
		humanoid.PlatformStand = false
		self:setAnimationsStopped(character, false)
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

-- one frame of the orbit: the camera sits out and up from what it is
-- circling, a little further round than last frame, looking at it. Round
-- the body, a wall or the mine's rock in the way pulls it in so the body
-- is never hidden
function ClientReviveManager:stepDeathView(deltaSec: number)
	if not self.isDeathViewOn then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	self.deathViewAngle += math.rad(DEATH_VIEW_DEGREES_PER_SEC) * deltaSec
	local refineryPosition = self.deathViewTarget
	if refineryPosition then
		local offset = Vector3.new(math.sin(self.deathViewAngle) * REFINERY_VIEW_DISTANCE_STUDS, REFINERY_VIEW_HEIGHT_STUDS, math.cos(self.deathViewAngle) * REFINERY_VIEW_DISTANCE_STUDS)
		camera.CFrame = CFrame.lookAt(refineryPosition + offset, refineryPosition)
		camera.Focus = CFrame.new(refineryPosition)
		return
	end
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not character or not root or not root:IsA("BasePart") then
		return
	end
	local target = root.Position
	local offset = Vector3.new(math.sin(self.deathViewAngle) * DEATH_VIEW_DISTANCE_STUDS, DEATH_VIEW_HEIGHT_STUDS, math.cos(self.deathViewAngle) * DEATH_VIEW_DISTANCE_STUDS)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(target, offset, params)
	local position = if hit then hit.Position - offset.Unit * DEATH_VIEW_WALL_GAP_STUDS else target + offset
	camera.CFrame = CFrame.lookAt(position, target)
	camera.Focus = CFrame.new(target)
	-- Roblox's camera scripts hid the local character for first person and
	-- stop updating that while the camera is scripted, so the body is
	-- shown again here, every frame, for as long as the view lasts
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			descendant.LocalTransparencyModifier = 0
		end
	end
end

-- the black frame to a transparency over a time; yields until it is there
function ClientReviveManager:fade(transparency: number, durationSec: number)
	local gui = self.fadeGui
	local frame = self.fadeFrame
	if not gui or not frame then
		task.wait(durationSec)
		return
	end
	gui.Enabled = true
	local tween = TweenService:Create(frame, TweenInfo.new(durationSec, Enum.EasingStyle.Linear), { BackgroundTransparency = transparency })
	self.fadeTween = tween
	tween:Play()
	tween.Completed:Wait()
	if self.fadeTween == tween then
		self.fadeTween = nil
		if transparency >= 1 then
			gui.Enabled = false
		end
	end
end

-- the red tint and the words come off
function ClientReviveManager:endGameOverEffects()
	local colorCorrection = self.colorCorrection
	if colorCorrection then
		colorCorrection:Destroy()
		self.colorCorrection = nil
	end
	if self.gameOverGui then
		self.gameOverGui.Enabled = false
	end
end

-- a Game Over screen in flight is dropped at once (the player was revived)
function ClientReviveManager:cancelGameOver()
	if not self.isGameOverPlaying then
		return
	end
	self.gameOverGeneration += 1
	self.isGameOverPlaying = false
	self:endGameOverEffects()
	local tween = self.fadeTween
	if tween then
		self.fadeTween = nil
		tween:Cancel()
	end
	if self.fadeFrame then
		self.fadeFrame.BackgroundTransparency = 1
	end
	if self.fadeGui then
		self.fadeGui.Enabled = false
	end
	self:setDeathView(false, nil)
	self:setHudHidden(false)
end

-- the Game Over screen (designer's sequence, 2026-10-05), for a death and
-- for the Refinery falling: the world turns red, the GameOver sound
-- plays, and the GameOver gui says why. After the hold the screen fades
-- to black; in the dark the tint comes off, a dead player's camera goes
-- to their grave, and the Results Menu opens; then the black fades away
function ClientReviveManager:playGameOver(isRefineryLost: boolean)
	self.gameOverGeneration += 1
	local generation = self.gameOverGeneration
	self.isGameOverPlaying = true
	self:closeMenu()
	ClientSpectateManager:stop()
	self:setHudHidden(true)
	-- until the screen is black: the Refinery from above when it fell, else
	-- a dead player's own body from outside
	local refineryPosition = if isRefineryLost then ClientDataManager:getGameMetadata(Attributes.COMPASS_HOME_POSITION) else nil
	if typeof(refineryPosition) == "Vector3" then
		self:setDeathView(true, refineryPosition)
	else
		self:setDeathView(self.isDead, nil)
	end
	local camera = workspace.CurrentCamera
	if camera then
		if not self.colorCorrection then
			local colorCorrection = Instance.new("ColorCorrectionEffect")
			colorCorrection.Name = GAME_OVER_TINT_NAME
			colorCorrection.Brightness = GAME_OVER_TINT_BRIGHTNESS
			colorCorrection.Contrast = GAME_OVER_TINT_CONTRAST
			colorCorrection.Saturation = GAME_OVER_TINT_SATURATION
			colorCorrection.TintColor = GAME_OVER_TINT_COLOR
			colorCorrection.Parent = camera
			self.colorCorrection = colorCorrection
		end
	end
	ClientSoundManager:playSfx(SoundNames.Sfx.GAME_OVER)
	if self.gameOverLabel then
		self.gameOverLabel.Text = UiStyle.formatTitle(if isRefineryLost then GAME_OVER_REFINERY_TEXT else GAME_OVER_DEAD_TEXT)
	end
	if self.gameOverGui then
		self.gameOverGui.Enabled = true
	end
	local holdSec = readNumber(ClientDataManager:getGameMetadata(Attributes.GAME_OVER_HOLD_SEC), DEFAULT_GAME_OVER_HOLD_SEC)
	local fadeInSec = readNumber(ClientDataManager:getGameMetadata(Attributes.GAME_OVER_FADE_IN_SEC), DEFAULT_GAME_OVER_FADE_IN_SEC)
	local blackHoldSec = readNumber(ClientDataManager:getGameMetadata(Attributes.GAME_OVER_BLACK_HOLD_SEC), DEFAULT_GAME_OVER_BLACK_HOLD_SEC)
	local fadeOutSec = readNumber(ClientDataManager:getGameMetadata(Attributes.GAME_OVER_FADE_OUT_SEC), DEFAULT_GAME_OVER_FADE_OUT_SEC)
	task.spawn(
		function()
			task.wait(holdSec)
			if generation ~= self.gameOverGeneration then
				return
			end
			-- the Game Over song comes in with the dark and plays out over the menu
			ClientSoundManager:playMusic(SoundNames.Music.GAME_OVER, true)
			self:fade(0, fadeInSec)
			if generation ~= self.gameOverGeneration then
				return
			end
			self:endGameOverEffects()
			self:setDeathView(false, nil)
			-- the black holds for a moment; the grave streams in meanwhile,
			-- once the server moves the focus to it, and a late one is waited for
			task.wait(blackHoldSec)
			local waitedSec = 0
			while self.isDead and not self.ownGrave and waitedSec < GAME_OVER_GRAVE_WAIT_SEC do
				task.wait(GAME_OVER_GRAVE_POLL_SEC)
				waitedSec += GAME_OVER_GRAVE_POLL_SEC
			end
			if generation ~= self.gameOverGeneration then
				return
			end
			self.isGameOverPlaying = false
			self:holdGraveCameraIfNeeded()
			self:openMenu()
			self:fade(1, fadeOutSec)
		end
	)
end

-- what the revive on offer costs, as the buttons show it: "FREE" when a
-- saved credit will pay, the Robux price, or nothing while Roblox has not
-- answered with one
function ClientReviveManager:getPriceText(reviveKind: number): string
	local credits = readStat(CREDIT_ATTRIBUTE_BY_KIND[reviveKind])
	local price = readNumber(ClientDataManager:getGameMetadata(PRICE_ATTRIBUTE_BY_KIND[reviveKind]), 0)
	return if credits > 0 then PRICE_FREE_TEXT elseif price > 0 then string.format(PRICE_FORMAT, price) else ""
end

-- the Spectate bar's Revive button: nil once nothing is on offer (the
-- player's own Revive has run out), so the button goes away
function ClientReviveManager:getSpectateReviveText(): string?
	if self:isRunOver() or not self.isDead then
		return nil
	end
	local reviveKind = REVIVE_KIND_BY_OFFER[self:getOffer()]
	if not reviveKind then
		return nil
	end
	local words = if reviveKind == Enums.ReviveKind.TEAM then SPECTATE_REVIVE_TEAM_TEXT else REVIVE_SELF_TEXT
	return UiStyle.formatTitle(words) .. "  " .. self:getPriceText(reviveKind)
end

-- the Return to Lobby button, on the Results Menu at the end of a run and
-- on the Spectate bar: the song fades and the server is asked for the trip
function ClientReviveManager:requestReturnToLobby()
	self:fadeOutGameOverMusic()
	ClientNetManager:fireServer(NetEventNames.TRY_RETURN_TO_LOBBY, {})
end

function ClientReviveManager:requestRevive()
	local reviveKind = REVIVE_KIND_BY_OFFER[self:getOffer()]
	if reviveKind then
		ClientNetManager:fireServer(NetEventNames.TRY_REVIVE, { reviveKind = reviveKind })
	end
end

-- the Game Over song loops under the Results Menu and belongs to it: it
-- fades out, stops, and rewinds when the player leaves the menu to
-- spectate, to return to the lobby, or because they were revived
function ClientReviveManager:fadeOutGameOverMusic()
	ClientSoundManager:fadeOutMusic(SoundNames.Music.GAME_OVER, GAME_OVER_MUSIC_FADE_SEC)
end

function ClientReviveManager:startSpectating()
	self:fadeOutGameOverMusic()
	self:closeMenu()
	if not ClientSpectateManager:start() then
		self:openMenu()
	end
end

function ClientReviveManager:onDeadChanged(isDead: boolean)
	if isDead == self.isDead then
		return
	end
	self.isDead = isDead
	self:applyDeadScreenState()
	if isDead then
		-- the Refinery falling buries everyone still standing: that is one
		-- Game Over screen, the Refinery's, whichever of the two arrives first
		local isRefineryLost = ClientDataManager:getGameMetadata(Attributes.RUN_END_REASON) == Enums.RunEndReason.REFINERY_DESTROYED
		if not self.isGameOverPlaying then
			self:playGameOver(isRefineryLost)
		else
			-- the screen is already up (the Refinery's, circling the
			-- Refinery); if it somehow is not circling anything yet, it
			-- steps outside the body now
			self:setDeathView(true, nil)
		end
		return
	end
	self:cancelGameOver()
	self:fadeOutGameOverMusic()
	ClientSpectateManager:stop()
	self:setHudHidden(false)
	self:releaseCamera()
	if not self:isRunOver() then
		self:closeMenu()
	end
end

-- the end of the run shows the same menu once, whoever is alive
function ClientReviveManager:onRunStateChanged()
	if not self:isRunOver() then
		self.hasShownRunEnd = false
		return
	end
	if self.hasShownRunEnd then
		return
	end
	self.hasShownRunEnd = true
	-- the Refinery falling is a Game Over screen for everyone, alive or dead
	if ClientDataManager:getGameMetadata(Attributes.RUN_END_REASON) == Enums.RunEndReason.REFINERY_DESTROYED then
		if not self.isGameOverPlaying then
			self:playGameOver(true)
		end
	elseif self.isGameOverPlaying then
		-- a death's own screen is still up; it opens the menu when it ends
		return
	elseif self.isMenuOpen then
		self:renderMenu()
	else
		self:openMenu()
	end
end

function ClientReviveManager:step(deltaSec: number)
	self:holdGraveCameraIfNeeded()
	if not self.isMenuOpen and not self.isDead then
		return
	end
	self.stepAccumulatorSec += deltaSec
	if self.stepAccumulatorSec < STEP_INTERVAL_SEC then
		return
	end
	self.stepAccumulatorSec = 0
	if self.isDead then
		self:setHudHidden(true)
	end
	self:applyDeadScreenState()
	if self.isMenuOpen then
		self:renderMenu()
	end
	if ClientSpectateManager:getIsSpectating() then
		ClientSpectateManager:setRevive(self:getSpectateReviveText(), self:getSpectateReviveTimerText())
	end
end

-- a dead player's Game Over screen and Results Menu show nothing else: no
-- messages, and no wall HP bars drawing through the world over them.
-- Both come back in Spectate Mode, where they are part of what is being
-- watched, and on a revive
function ClientReviveManager:applyDeadScreenState()
	local isOnDeadScreen = self.isDead and not ClientSpectateManager:getIsSpectating()
	ClientPlayerFeedbackManager:setSuppressed(isOnDeadScreen)
	ClientStructureManager:setBarsHidden(isOnDeadScreen)
	-- a dead player cannot move or jump, so a phone's thumbstick and jump
	-- button go away for the whole of it, Spectate Mode included (Roblox's
	-- own switch for that, which also hides its touch GUI)
	if UserInputService.ModalEnabled ~= self.isDead then
		UserInputService.ModalEnabled = self.isDead
	end
end

-- the seconds left on the revive on offer, for the Spectate bar's timer
function ClientReviveManager:getSpectateReviveTimerText(): string
	local endTime = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.REVIVE_OFFER_END_TIME), 0)
	return string.format(SPECTATE_TIMER_FORMAT, math.max(0, math.ceil(endTime - workspace:GetServerTimeNow())))
end

-- the designer's grave, laid on a tombstone shadow: the name and the day
-- in capitals, and the face once Roblox has fetched it
function ClientReviveManager:addGrave(shadow: Instance)
	local template = self.graveTemplate
	local folder = self.graveFolder
	if not template or not folder or not shadow:IsA("BasePart") or self.graveByShadow[shadow] then
		return
	end
	local grave = template:Clone()
	local displayName = shadow:GetAttribute(Attributes.TOMBSTONE_DISPLAY_NAME)
	local nameLabel = grave:FindFirstChild(Constants.GRAVE_DISPLAY_NAME_LABEL, true)
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = UiStyle.formatTitle(if typeof(displayName) == "string" then displayName else "")
	end
	local dayLabel = grave:FindFirstChild(Constants.GRAVE_DAY_LABEL, true)
	if dayLabel and dayLabel:IsA("TextLabel") then
		dayLabel.Text = UiStyle.formatTitle(string.format(GRAVE_DAY_FORMAT, readNumber(shadow:GetAttribute(Attributes.TOMBSTONE_DAY), 1)))
	end
	local thumbnail = grave:FindFirstChild(Constants.GRAVE_THUMBNAIL, true)
	local userId = shadow:GetAttribute(Attributes.TOMBSTONE_USER_ID)
	if thumbnail and thumbnail:IsA("ImageLabel") and typeof(userId) == "number" then
		thumbnail.Image = ""
		task.spawn(
			function()
				local isSuccess, image = pcall(
					function()
						return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
					end
				)
				if isSuccess and thumbnail.Parent then
					thumbnail.Image = image
				end
			end
		)
	end
	grave:PivotTo(shadow.CFrame)
	grave.Parent = folder
	self.graveByShadow[shadow] = grave
	if userId == Players.LocalPlayer.UserId then
		self.ownGrave = grave
	end
end

function ClientReviveManager:removeGrave(shadow: Instance)
	local grave = self.graveByShadow[shadow]
	if grave then
		self.graveByShadow[shadow] = nil
		if self.ownGrave == grave then
			self.ownGrave = nil
		end
		grave:Destroy()
	end
end

function ClientReviveManager:watchGraves()
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local template = if gameAssets then gameAssets:FindFirstChild(Constants.GRAVE_TEMPLATE) else nil
	if not template or not template:IsA("Model") then
		warn(`ClientReviveManager: no {Constants.GRAVE_TEMPLATE} Model under GameAssets`)
		return
	end
	self.graveTemplate = template
	local folder = Instance.new("Folder")
	folder.Name = GRAVE_FOLDER
	folder.Parent = workspace
	self.graveFolder = folder
	CollectionService:GetInstanceAddedSignal(Tags.TOMBSTONE):Connect(
		function(shadow: Instance)
			self:addGrave(shadow)
		end
	)
	CollectionService:GetInstanceRemovedSignal(Tags.TOMBSTONE):Connect(
		function(shadow: Instance)
			self:removeGrave(shadow)
		end
	)
	for _, shadow in CollectionService:GetTagged(Tags.TOMBSTONE) do
		self:addGrave(shadow)
	end
end

-- a dead player looking at the Results Menu sees their own grave: the
-- camera stands on the grave's CameraLocation part, facing the way it
-- faces. The grave streams in a moment after the death, so this is tried
-- again until it is there
function ClientReviveManager:holdGraveCameraIfNeeded()
	if not self.isDead or self.isGameOverPlaying or ClientSpectateManager:getIsSpectating() then
		return
	end
	local camera = workspace.CurrentCamera
	local grave = self.ownGrave
	local cameraPart = if grave then grave:FindFirstChild(Constants.GRAVE_CAMERA_PART) else nil
	if not camera or not cameraPart or not cameraPart:IsA("BasePart") then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	if camera.CFrame ~= cameraPart.CFrame then
		camera.CFrame = cameraPart.CFrame
	end
end

-- back behind the player's own eyes
function ClientReviveManager:releaseCamera()
	local camera = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

function ClientReviveManager:findMenu()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local menuGui = playerGui:WaitForChild(Constants.RESULTS_MENU_GUI_NAME, 10)
	if not menuGui or not menuGui:IsA("ScreenGui") then
		warn("ClientReviveManager: no ResultsMenu ScreenGui; run scripts/studio/build_results_menu_gui.luau")
		return
	end
	menuGui.Enabled = false
	self.menuGui = menuGui
	local gameOverGui = playerGui:WaitForChild(Constants.GAME_OVER_GUI_NAME, 10)
	if gameOverGui and gameOverGui:IsA("ScreenGui") then
		gameOverGui.Enabled = false
		self.gameOverGui = gameOverGui
		local label = gameOverGui:FindFirstChild(Constants.GAME_OVER_LABEL)
		self.gameOverLabel = if label and label:IsA("TextLabel") then label else nil
	else
		warn("ClientReviveManager: no GameOver ScreenGui in StarterGui")
	end
	local fadeGui = playerGui:WaitForChild(Constants.SCREEN_FADE_GUI_NAME, 10)
	local fadeFrame = if fadeGui then fadeGui:FindFirstChild(Constants.SCREEN_FADE_FRAME) else nil
	if fadeGui and fadeGui:IsA("ScreenGui") and fadeFrame and fadeFrame:IsA("GuiObject") then
		fadeGui.Enabled = false
		fadeFrame.BackgroundTransparency = 1
		self.fadeGui = fadeGui
		self.fadeFrame = fadeFrame
	else
		warn("ClientReviveManager: no ScreenFade ScreenGui; run scripts/studio/build_screen_fade_gui.luau")
	end
	local dialog = menuGui:FindFirstChild(Constants.RESULTS_MENU_DIALOG)
	if not dialog or not dialog:IsA("GuiObject") then
		warn("ClientReviveManager: the ResultsMenu has no Dialog")
		return
	end
	self.menuDialog = dialog
	local function findLabel(parent: Instance, name: string): TextLabel?
		local label = parent:FindFirstChild(name)
		return if label and label:IsA("TextLabel") then label else nil
	end
	local function findButton(name: string): GuiButton?
		local button = dialog:FindFirstChild(name)
		return if button and button:IsA("GuiButton") then button else nil
	end
	self.titleLabel = findLabel(dialog, Constants.RESULTS_MENU_TITLE_LABEL)
	self.countdownLabel = findLabel(dialog, Constants.RESULTS_MENU_COUNTDOWN_LABEL)
	self.reviveButton = findButton(Constants.RESULTS_MENU_REVIVE_BUTTON)
	self.spectateButton = findButton(Constants.RESULTS_MENU_SPECTATE_BUTTON)
	self.closeButton = findButton(Constants.RESULTS_MENU_CLOSE_BUTTON)
	local reviveButton = self.reviveButton
	if reviveButton then
		self.reviveLabel = findLabel(reviveButton, Constants.RESULTS_MENU_REVIVE_LABEL)
		self.revivePriceLabel = findLabel(reviveButton, Constants.RESULTS_MENU_REVIVE_PRICE_LABEL)
		reviveButton.Activated:Connect(
			function()
				self:requestRevive()
			end
		)
	end
	if self.spectateButton then
		self.spectateButton.Activated:Connect(
			function()
				self:startSpectating()
			end
		)
	end
	if self.closeButton then
		-- the end of the run: Return to Lobby
		self.closeButton.Activated:Connect(
			function()
				self:requestReturnToLobby()
				self:closeMenu()
			end
		)
	end

	-- each stat row: where its number comes from, and its resource icon if it has one
	local rowDefinitions: { { name: string, attribute: string, rankAttribute: string, icon: string? } } = {
		{
			name = Constants.RESULTS_MENU_ROW_URANIUM_REFINED,
			attribute = Attributes.RUN_STAT_URANIUM_REFINED,
			rankAttribute = Attributes.RUN_STAT_RANK_URANIUM_REFINED,
			icon = Icons.REFINED_RESOURCE[Enums.RefinedResource.URANIUM],
		},
		{
			name = Constants.RESULTS_MENU_ROW_CASH_EARNED,
			attribute = Attributes.RUN_STAT_CASH_EARNED,
			rankAttribute = Attributes.RUN_STAT_RANK_CASH_EARNED,
			icon = Icons.UI.CASH,
		},
		{
			name = Constants.RESULTS_MENU_ROW_GOLD_REFINED,
			attribute = Attributes.RUN_STAT_GOLD_REFINED,
			rankAttribute = Attributes.RUN_STAT_RANK_GOLD_REFINED,
			icon = Icons.REFINED_RESOURCE[Enums.RefinedResource.GOLD_BAR],
		},
		{
			name = Constants.RESULTS_MENU_ROW_IRON_REFINED,
			attribute = Attributes.RUN_STAT_IRON_REFINED,
			rankAttribute = Attributes.RUN_STAT_RANK_IRON_REFINED,
			icon = Icons.REFINED_RESOURCE[Enums.RefinedResource.IRON_BAR],
		},
		{
			name = Constants.RESULTS_MENU_ROW_ENEMIES_KILLED,
			attribute = Attributes.RUN_STAT_ENEMIES_KILLED,
			rankAttribute = Attributes.RUN_STAT_RANK_ENEMIES_KILLED,
		},
		{
			name = Constants.RESULTS_MENU_ROW_DAMAGE_GIVEN,
			attribute = Attributes.RUN_STAT_DAMAGE_GIVEN,
			rankAttribute = Attributes.RUN_STAT_RANK_DAMAGE_GIVEN,
		},
	}
	self.rankHeaderLabel = findLabel(dialog, Constants.RESULTS_MENU_RANK_HEADER_LABEL)
	local stats = dialog:FindFirstChild(Constants.RESULTS_MENU_STATS)
	self.statsFrame = if stats and stats:IsA("GuiObject") then stats else nil
	if self.statsFrame and self.countdownLabel and reviveButton then
		self.authoredLayout = {
			statsSize = self.statsFrame.Size,
			countdownPosition = self.countdownLabel.Position,
			revivePosition = reviveButton.Position,
			reviveSize = reviveButton.Size,
		}
	end
	for _, definition in rowDefinitions do
		local row = if stats then stats:FindFirstChild(definition.name) else nil
		local valueLabel = if row then findLabel(row, Constants.RESULTS_MENU_ROW_VALUE_LABEL) else nil
		if not row or not valueLabel then
			warn(`ClientReviveManager: the ResultsMenu has no Stats.{definition.name}.Value`)
			continue
		end
		local icon = row:FindFirstChild(Constants.RESULTS_MENU_ROW_ICON)
		if icon and icon:IsA("ImageLabel") then
			local isPlaceholder = Icons.isPlaceholder(definition.icon)
			icon.Image = if isPlaceholder or not definition.icon then "" else definition.icon
			icon.Visible = not isPlaceholder
		end
		table.insert(self.statRows, {
			valueLabel = valueLabel,
			attribute = definition.attribute,
			rankAttribute = definition.rankAttribute,
			rankLabel = findLabel(row, Constants.RESULTS_MENU_ROW_RANK_LABEL),
			authoredValuePosition = valueLabel.Position,
			nameLabel = findLabel(row, Constants.RESULTS_MENU_ROW_NAME_LABEL),
			icon = if icon and icon:IsA("ImageLabel") then icon else nil,
		})
	end

	local overlay: ClientOverlayManager.Overlay
	overlay = {
		getGuiRoot = function(_overlay)
			return self.menuDialog
		end,
		notifyForceEnd = function(_overlay)
			self:closeMenu()
		end,
		-- a dead player leaves the menu by a button, never by a stray click
		notifyClickOutside = function(_overlay)
			if self:isRunOver() then
				self:closeMenu()
			end
		end,
		-- a dead player is looking at their grave beside the menu, so the
		-- world stays sharp and the camera stays where the grave put it
		doesWantBlur = function(_overlay)
			return not self.isDead
		end,
		doZoomCamera = function(_overlay)
			return not self.isDead
		end,
	}
	self.overlay = overlay
end

-- Roblox's Reset Character would respawn the character at full health;
-- the call fails until the core scripts have loaded, so it is retried
function ClientReviveManager:disableResetButton()
	task.spawn(
		function()
			for _ = 1, RESET_BUTTON_ATTEMPTS do
				local isSuccess = pcall(
					function()
						StarterGui:SetCore("ResetButtonCallback", false)
					end
				)
				if isSuccess then
					return
				end
				task.wait(RESET_BUTTON_RETRY_SEC)
			end
			warn("ClientReviveManager: could not switch off Reset Character")
		end
	)
end

function ClientReviveManager:init()
	self:findMenu()
	self:watchGraves()
	self:disableResetButton()
	ClientSpectateManager:init(
		function()
			self:openMenu()
		end,
		-- nobody left to watch: back to the menu, where the wipe's offer is
		function()
			if self.isDead then
				self:openMenu()
			end
		end,
		function()
			self:requestRevive()
		end,
		function()
			self:requestReturnToLobby()
		end
	)
	local localUserId = Players.LocalPlayer.UserId
	ClientDataManager:subscribeAllPlayers({
		onAdded = function(userId: number, data: ClientDataManager.PublicData)
			if userId == localUserId then
				self:onDeadChanged(data.isDead)
			end
		end,
		onChanged = function(userId: number, data: ClientDataManager.PublicData)
			if userId == localUserId then
				self:onDeadChanged(data.isDead)
			end
		end,
	})
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.RUN_STATE,
		function()
			self:onRunStateChanged()
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_REVIVE_ANNOUNCEMENT,
		function(payload: any)
			local isValid, errorMessage = Validate.isTableShape(payload, NOTIFY_REVIVE_ANNOUNCEMENT_SHAPE)
			if not isValid then
				warn("ClientReviveManager: malformed NotifyReviveAnnouncement:", errorMessage)
				return
			end
			if payload.isAlert then
				ClientPlayerFeedbackManager:alertLocal(payload.message, payload.displaySec)
			else
				ClientPlayerFeedbackManager:announceLocal(payload.message, payload.displaySec)
			end
		end
	)
	-- the state is the IsDead attribute; nothing more to do on the notify
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_PLAYER_REVIVED,
		function(_payload: any)
		end
	)
	RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self:step(deltaSec)
		end
	)
	RunService.RenderStepped:Connect(
		function(deltaSec: number)
			self:stepDeathView(deltaSec)
		end
	)
end

function ClientReviveManager.new(): ClientReviveManager
	local self = setmetatable({}, ClientReviveManager) :: ClientReviveManager
	self.menuGui = nil
	self.menuDialog = nil
	self.titleLabel = nil
	self.countdownLabel = nil
	self.reviveButton = nil
	self.reviveLabel = nil
	self.revivePriceLabel = nil
	self.spectateButton = nil
	self.closeButton = nil
	self.rankHeaderLabel = nil
	self.statsFrame = nil
	self.authoredLayout = nil
	self.isLayoutFilled = false
	self.statRows = {}
	self.overlay = nil
	self.isMenuOpen = false
	self.hiddenHudGuis = {}
	self.isHudHidden = false
	self.gameOverGui = nil
	self.gameOverLabel = nil
	self.fadeGui = nil
	self.fadeFrame = nil
	self.fadeTween = nil
	self.colorCorrection = nil
	self.gameOverGeneration = 0
	self.isGameOverPlaying = false
	self.isDeathViewOn = false
	self.deathViewAngle = 0
	self.deathViewTarget = nil
	self.savedCameraMode = nil
	self.isDead = false
	self.hasShownRunEnd = false
	self.stepAccumulatorSec = 0
	self.graveTemplate = nil
	self.graveFolder = nil
	self.graveByShadow = {}
	self.ownGrave = nil
	return self
end

return ClientReviveManager.new()
