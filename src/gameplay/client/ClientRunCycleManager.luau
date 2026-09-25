--!strict

-- The day clock on this client (GDD "Wave Cycle"), M28. The server
-- publishes the run state, the day number, and when the current phase
-- began and ends as GameMetadata; this manager draws the DayClock
-- ScreenGui from them every frame using server time, so every player sees
-- the same clock: the circle on the left cycles through the day, dusk,
-- and night pictures, the bar starts full at dawn and empties from right
-- to left until night (empty all night), and "Day N" reads under it. The
-- sky follows too: the run's map picks its shared LightingPresets, and
-- every frame the sky is set to the blend RunCycleRules.skyStage gives
-- for the phase times: day start gliding into day end over the day, day
-- end into night start over the night's first dusk seconds, night start
-- into night end over the spawn window then held until the wave is done,
-- and night end back to day start over the dawn stretch before the next
-- day starts.
-- Lighting.ClockTime blends the same way but the forward way round the
-- clock. Nothing tweens; every client computes the same sky from server
-- time. The day-start line and the end of the run arrive as
-- notifies and go to the announcement box; each also flashes the
-- designer's DayNightNumber card ("DAY N" / "NIGHT N") for a moment with
-- the rooster or the night bell, and the clock fades out for the night
-- and back in at dawn. Nothing here decides anything.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local LightingPresets = require("@game/ReplicatedStorage/Shared/LightingPresets")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local RunCycleRules = require("@game/ReplicatedStorage/Shared/RunCycleRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientRunCycleManager = {}
ClientRunCycleManager.__index = ClientRunCycleManager

export type ClientRunCycleManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		clockGroup: CanvasGroup?,
		-- whether the clock is shown (day) or faded out (night)
		isClockShown: boolean,
		numberGui: ScreenGui?,
		numberLabel: TextLabel?,
		numberGeneration: number,
		-- the disc holding one picture and one gradient per phase
		phaseIcon: Frame?,
		fill: Frame?,
		dayLabel: TextLabel?,
		shownPhase: number?,
		-- the day whose dusk song has already started, so it plays once a day
		duskSongDay: number?,
		-- which preset the sky was last sent toward (Enums.RunState DAY or NIGHT)
		warnedChildren: { [string]: boolean },
	},
	ClientRunCycleManager
))

local NOTIFY_RUN_DAY_STARTED_SHAPE = {
	day = "positiveInteger",
	message = "string",
	displaySec = "positiveNumber",
}
local NOTIFY_RUN_NIGHT_STARTED_SHAPE = {
	day = "positiveInteger",
}
local NOTIFY_RUN_ENDED_SHAPE = {
	isWon = "boolean",
	message = "string",
	displaySec = "positiveNumber",
}

local DAY_FORMAT = "Day %d"
-- two spaces: the font sets the word and the number too close otherwise
local DAY_CARD_FORMAT = "Day  %d"
local NIGHT_CARD_FORMAT = "Night  %d"
-- the card stays up this long; the clock fades over the HUD tween time
local CARD_SHOW_SEC = 3
-- day 1 gets no card: the crew has just landed and the run is plainly starting
local FIRST_DAY = 1
-- dusk is the last 40 s of a 300 s day; the server publishes the real numbers
local DEFAULT_DUSK_SHARE = 40 / 300
local DEFAULT_DUSK_SONG_LEAD_SEC = 40
local DEFAULT_DAWN_TRANSITION_SEC = 1
local DEFAULT_DUSK_TRANSITION_SEC = 1
local DEFAULT_NIGHT_SPAWN_SEC = 90
-- the designer-authored picture and disc gradient under PhaseIcon per phase
local PHASE_CHILD_NAMES: { [number]: { icon: string, gradient: string } } = {
	[Enums.ClockPhase.DAY] = {
		icon = Constants.DAY_CLOCK_PHASE_ICON_DAY,
		gradient = Constants.DAY_CLOCK_PHASE_GRADIENT_DAY,
	},
	[Enums.ClockPhase.DUSK] = {
		icon = Constants.DAY_CLOCK_PHASE_ICON_DUSK,
		gradient = Constants.DAY_CLOCK_PHASE_GRADIENT_DUSK,
	},
	[Enums.ClockPhase.NIGHT] = {
		icon = Constants.DAY_CLOCK_PHASE_ICON_NIGHT,
		gradient = Constants.DAY_CLOCK_PHASE_GRADIENT_NIGHT,
	},
}

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

function ClientRunCycleManager:findGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.DAY_CLOCK_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientRunCycleManager: no DayClock ScreenGui; run scripts/studio/build_day_clock_gui.luau")
		return
	end
	self.gui = gui
	local root = gui:FindFirstChild(Constants.DAY_CLOCK_ROOT_FRAME)
	local icon = if root then root:FindFirstChild(Constants.DAY_CLOCK_PHASE_ICON) else nil
	self.phaseIcon = if icon and icon:IsA("Frame") then icon else nil
	local bar = if root then root:FindFirstChild(Constants.DAY_CLOCK_BAR) else nil
	local fill = if bar then bar:FindFirstChild(Constants.DAY_CLOCK_FILL) else nil
	self.fill = if fill and fill:IsA("Frame") then fill else nil
	local dayLabel = if root then root:FindFirstChild(Constants.DAY_CLOCK_DAY_LABEL) else nil
	self.dayLabel = if dayLabel and dayLabel:IsA("TextLabel") then dayLabel else nil
	if root and root:IsA("CanvasGroup") then
		self.clockGroup = root
	else
		warn("ClientRunCycleManager: the DayClock Root is not a CanvasGroup, so the clock cannot fade; rebuild it")
	end
	local numberGui = playerGui:FindFirstChild(Constants.DAY_NIGHT_NUMBER_GUI_NAME)
	if numberGui and numberGui:IsA("ScreenGui") then
		numberGui.Enabled = false
		self.numberGui = numberGui
		local label = numberGui:FindFirstChild(Constants.DAY_NIGHT_NUMBER_LABEL, true)
		self.numberLabel = if label and label:IsA("TextLabel") then label else nil
	else
		warn("ClientRunCycleManager: no DayNightNumber ScreenGui in StarterGui")
	end
end

-- the clock fades out for the night and back in at dawn
function ClientRunCycleManager:setClockShown(isShown: boolean)
	if self.isClockShown == isShown then
		return
	end
	self.isClockShown = isShown
	local group = self.clockGroup
	if group then
		TweenService:Create(group, TweenInfo.new(UiStyle.HUD_TWEEN_SEC, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { GroupTransparency = if isShown then 0 else 1 }):Play()
	end
end

-- the "DAY N" / "NIGHT N" card, up for a moment with its sound
function ClientRunCycleManager:showCard(text: string, sfxName: string)
	local gui = self.numberGui
	local label = self.numberLabel
	if not gui then
		return
	end
	if label then
		label.Text = UiStyle.formatTitle(text)
	end
	self.numberGeneration += 1
	local generation = self.numberGeneration
	gui.Enabled = true
	ClientSoundManager:playSfx(sfxName)
	task.delay(
		CARD_SHOW_SEC,
		function()
			if self.numberGeneration == generation then
				gui.Enabled = false
			end
		end
	)
end

-- a GUI child the designer removed or renamed is reported once, not per phase
function ClientRunCycleManager:warnMissingChildOnce(childName: string)
	if self.warnedChildren[childName] then
		return
	end
	self.warnedChildren[childName] = true
	warn(`ClientRunCycleManager: DayClock PhaseIcon has no {childName}; rebuild it with scripts/studio/build_day_clock_gui.luau`)
end

function ClientRunCycleManager:setPhase(phase: number)
	if self.shownPhase == phase then
		return
	end
	self.shownPhase = phase
	local icon = self.phaseIcon
	if not icon then
		return
	end
	for childPhase, names in PHASE_CHILD_NAMES do
		local isShown = childPhase == phase
		local image = icon:FindFirstChild(names.icon)
		if image and image:IsA("ImageLabel") then
			image.Visible = isShown
		else
			self:warnMissingChildOnce(names.icon)
		end
		local gradient = icon:FindFirstChild(names.gradient)
		if gradient and gradient:IsA("UIGradient") then
			gradient.Enabled = isShown
		else
			self:warnMissingChildOnce(names.gradient)
		end
	end
end

function ClientRunCycleManager:getMapPresets(): LightingPresets.MapPresets
	local map = ClientDataManager:getGameMetadata(Attributes.RUN_MAP)
	return LightingPresets.forMap(if typeof(map) == "number" then map else nil)
end

-- one instance set to the blend of two looks at a share
function ClientRunCycleManager:applyBlend(instance: Instance, from: LightingPresets.Properties, to: LightingPresets.Properties, share: number)
	for name, value in LightingPresets.blend(from, to, share) do
		(instance :: any)[name] = value
	end
end

-- every frame: the whole look (Lighting and each named child) at the
-- stage and share the phase times give, and the clock turned forward
-- between the two looks' hours
function ClientRunCycleManager:stepSky(runState: number, startTime: number, endTime: number, now: number)
	local presets = self:getMapPresets()
	local dawnTransitionSec = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_LIGHTING_DAWN_TRANSITION_SEC), DEFAULT_DAWN_TRANSITION_SEC)
	local duskTransitionSec = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_LIGHTING_DUSK_TRANSITION_SEC), DEFAULT_DUSK_TRANSITION_SEC)
	local spawnSec = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_NIGHT_SPAWN_SEC), DEFAULT_NIGHT_SPAWN_SEC)
	local stage, share = RunCycleRules.skyStage(runState, startTime, endTime, now, dawnTransitionSec, duskTransitionSec, spawnSec)
	local from, to = LightingPresets.stageEnds(presets, stage)
	self:applyBlend(Lighting, from.LIGHTING, to.LIGHTING, share)
	for childName, fromChild in from.CHILDREN do
		local child = Lighting:FindFirstChild(childName)
		local toChild = to.CHILDREN[childName]
		if child and toChild then
			self:applyBlend(child, fromChild, toChild, share)
		elseif not child and not self.warnedChildren[childName] then
			self.warnedChildren[childName] = true
			warn(`ClientRunCycleManager: Lighting has no {childName} to apply the preset to`)
		end
	end
	Lighting.ClockTime = RunCycleRules.clockTimeBetween(from.LIGHTING.ClockTime, to.LIGHTING.ClockTime, share)
end

-- every frame: the bar from the published phase times against server time
-- the dusk song starts from the top a fixed lead before the night falls
-- (the day's published end time), once per day; a day cut short by the
-- dev tool starts it as soon as the lead is reached
function ClientRunCycleManager:stepDuskSong(runState: number, endTime: number, now: number)
	if runState ~= Enums.RunState.DAY then
		return
	end
	local day = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_DAY), 1)
	if self.duskSongDay == day then
		return
	end
	local leadSec = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_DUSK_SONG_LEAD_SEC), DEFAULT_DUSK_SONG_LEAD_SEC)
	if now < endTime - leadSec then
		return
	end
	self.duskSongDay = day
	ClientSoundManager:playMusic(SoundNames.Music.DUSK_SONG_1)
end

function ClientRunCycleManager:step()
	local runState = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_STATE), Enums.RunState.DAY)
	local startTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PHASE_START_TIME), 0)
	local endTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PHASE_END_TIME), 0)
	local duskShare = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_DUSK_SHARE), DEFAULT_DUSK_SHARE)
	local now = workspace:GetServerTimeNow()
	local shareLeft = if runState == Enums.RunState.DAY then RunCycleRules.dayShareLeft(startTime, endTime, now) elseif runState == Enums.RunState.WAITING then 1 else 0
	local fill = self.fill
	if fill then
		fill.Size = UDim2.fromScale(shareLeft, 1)
	end
	self:setPhase(RunCycleRules.clockPhase(runState, shareLeft, duskShare))
	self:setClockShown(runState == Enums.RunState.DAY or runState == Enums.RunState.WAITING)
	self:stepSky(runState, startTime, endTime, now)
	self:stepDuskSong(runState, endTime, now)
end

function ClientRunCycleManager:refreshDay()
	local dayLabel = self.dayLabel
	if dayLabel then
		dayLabel.Text = UiStyle.formatTitle(string.format(DAY_FORMAT, RunCycleRules.shownDay(readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_DAY), 1))))
	end
end

function ClientRunCycleManager:onDayStarted(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_RUN_DAY_STARTED_SHAPE) then
		warn("ClientRunCycleManager: malformed NotifyRunDayStarted")
		return
	end
	-- the multiplier line is not shown any more (2026-09-25): the day card
	-- and the clock say enough, and the numbers still go to the server Output
	-- the card waits for the dawn blend: the day's start is published a
	-- little ahead of the message, and the clock only runs from then
	local day = payload.day
	if day == FIRST_DAY then
		return
	end
	local startTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PHASE_START_TIME), 0)
	local delaySec = math.max(startTime - workspace:GetServerTimeNow(), 0)
	task.delay(
		delaySec,
		function()
			self:showCard(string.format(DAY_CARD_FORMAT, day), SoundNames.Sfx.ROOSTER)
		end
	)
end

function ClientRunCycleManager:onNightStarted(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_RUN_NIGHT_STARTED_SHAPE) then
		warn("ClientRunCycleManager: malformed NotifyRunNightStarted")
		return
	end
	-- the card waits for the dusk blend that opens the night
	local duskTransitionSec = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_LIGHTING_DUSK_TRANSITION_SEC), DEFAULT_DUSK_TRANSITION_SEC)
	local day = payload.day
	task.delay(
		duskTransitionSec,
		function()
			self:showCard(string.format(NIGHT_CARD_FORMAT, day), SoundNames.Sfx.NIGHT_BELL)
		end
	)
end

function ClientRunCycleManager:onRunEnded(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_RUN_ENDED_SHAPE) then
		warn("ClientRunCycleManager: malformed NotifyRunEnded")
		return
	end
	ClientPlayerFeedbackManager:announceLocal(payload.message, payload.displaySec)
end

function ClientRunCycleManager:init()
	self:findGui()
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_RUN_DAY_STARTED,
		function(payload: any)
			self:onDayStarted(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_RUN_NIGHT_STARTED,
		function(payload: any)
			self:onNightStarted(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_RUN_ENDED,
		function(payload: any)
			self:onRunEnded(payload)
		end
	)
	self:refreshDay()
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.RUN_DAY,
		function()
			self:refreshDay()
		end
	)
	if self.gui then
		self.gui.Enabled = true
		RunService.RenderStepped:Connect(
			function()
				self:step()
			end
		)
	end
end

function ClientRunCycleManager.new(): ClientRunCycleManager
	local self = setmetatable({}, ClientRunCycleManager) :: ClientRunCycleManager
	self.gui = nil
	self.clockGroup = nil
	self.isClockShown = true
	self.numberGui = nil
	self.numberLabel = nil
	self.numberGeneration = 0
	self.phaseIcon = nil
	self.fill = nil
	self.dayLabel = nil
	self.shownPhase = nil
	self.duskSongDay = nil
	self.warnedChildren = {}
	return self
end

return ClientRunCycleManager.new()
