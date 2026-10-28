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
-- the rooster or the night bell. At dusk the clock slides up off the
-- screen and the Refinery HP bar (ClientRefineryHpManager, M33) comes
-- down in its place; at dawn they swap back. Nothing here decides anything.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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
local ClientHudSlide = require(script.Parent.Parent.Client.ClientHudSlide)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientRunCycleManager = {}
ClientRunCycleManager.__index = ClientRunCycleManager

export type ClientRunCycleManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		pausedGui: ScreenGui?,
		clockGroup: CanvasGroup?,
		-- the clock on stage by day and off the top of the screen by night
		slide: ClientHudSlide.ClientHudSlide?,
		numberGui: ScreenGui?,
		numberLabel: TextLabel?,
		numberGeneration: number,
		-- the local player's IsDead, for the night song
		isLocalPlayerDead: boolean,
		-- told when a card goes down (the rescue countdown waits on the
		-- FINAL NIGHT card)
		cardClosedCallbacks: { () -> () },
		-- the disc holding one picture and one gradient per phase
		phaseIcon: Frame?,
		fill: Frame?,
		dayLabel: TextLabel?,
		shownPhase: number?,
		-- the day whose dusk song has already started, so it plays once a day,
		-- the night fall it is heading for, and whether its fade has begun
		duskSongDay: number?,
		duskSongEndTime: number?,
		isDuskSongFading: boolean,
		-- run right after the presets are written each frame, before the
		-- render, with the sky stage and its share, for a manager that lays
		-- its own value over the preset's or moves with the sky (the sunset
		-- rays, the moon, 2026-10-21); a later Heartbeat write would be
		-- overwritten by the next RenderStepped before it was ever drawn
		skyAppliedHandlers: { (stage: number, share: number) -> () },
		-- the server time the sunset was frozen at, for the ride's final
		-- camera drift (designer, 2026-10-27); nil while it runs
		sunsetHeldAtTime: number?,
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
-- the clock waits off the top of the screen at night; well clear of its own height
local HIDDEN_POSITION_Y_SCALE = -0.3
-- the same label reads SUNSET once the clock turns to dusk (2026-09-29)
local SUNSET_FORMAT = "Sunset %d"
-- two spaces: the font sets the word and the number too close otherwise
local DAY_CARD_FORMAT = "Day  %d"
local NIGHT_CARD_FORMAT = "Night  %d"
-- the night the rescue is fought through (designer, 2026-10-27)
local FINAL_NIGHT_CARD_TEXT = "Final Night"
-- the card stays up this long; the clock fades over the HUD tween time
local CARD_SHOW_SEC = 3
-- day 1 gets no card: the crew has just landed and the run is plainly starting
local FIRST_DAY = 1
-- from day 2 the rooster crows as the day starts and the card with its
-- sting follows this much later (designer, 2026-10-21)
local ROOSTER_TO_CARD_SEC = 3
-- dusk is the last 40 s of a 300 s day; the server publishes the real numbers
local DEFAULT_DUSK_SHARE = 60 / 320
local DEFAULT_DUSK_SONG_LEAD_SEC = 60
local DEFAULT_DUSK_SONG_FADE_SEC = 10
local DEFAULT_DUSK_SONG_FADE_LEAD_SEC = 5
-- the dusk song eases in from silence to its authored volume (designer, 2026-10-21)
local DUSK_SONG_FADE_IN_SEC = 5
-- a dusk song still up when the rescue is called goes out this fast, so
-- the radio's dispatch and the flash play over silence (designer, 2026-10-27)
local DUSK_SONG_RESCUE_CALL_FADE_SEC = 3
-- the night song loops from night start to night end (designer, 2026-10-21)
local NIGHT_SONG_FADE_IN_SEC = 3
local NIGHT_SONG_FADE_OUT_SEC = 1
-- the night's loop goes out slower when the night is cut short for this
-- player: their death, the run lost, or the run won (designer, 2026-10-27)
local NIGHT_SONG_END_FADE_SEC = 3
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
	local pausedGui = playerGui:WaitForChild(Constants.RUN_PAUSED_GUI_NAME, 10)
	if pausedGui and pausedGui:IsA("ScreenGui") then
		pausedGui.Enabled = false
		self.pausedGui = pausedGui
	else
		warn("ClientRunCycleManager: no RunPaused ScreenGui; run scripts/studio/build_run_paused_gui.luau")
	end
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
		self.slide = ClientHudSlide.new(root, UDim2.new(root.Position.X.Scale, root.Position.X.Offset, HIDDEN_POSITION_Y_SCALE, 0))
	else
		warn("ClientRunCycleManager: the DayClock Root is not a CanvasGroup; rebuild it")
	end
	local numberGui = playerGui:WaitForChild(Constants.DAY_NIGHT_NUMBER_GUI_NAME, Constants.GUI_WAIT_SEC)
	if numberGui and numberGui:IsA("ScreenGui") then
		numberGui.Enabled = false
		self.numberGui = numberGui
		local label = numberGui:FindFirstChild(Constants.DAY_NIGHT_NUMBER_LABEL, true)
		self.numberLabel = if label and label:IsA("TextLabel") then label else nil
	else
		warn("ClientRunCycleManager: no DayNightNumber ScreenGui in StarterGui")
	end
end

-- the clock slides up off the screen for the night and, once the Refinery
-- HP bar has left again, back down at dawn
function ClientRunCycleManager:setClockShown(isShown: boolean)
	local slide = self.slide
	if slide then
		slide:setShown(isShown, if isShown then UiStyle.HUD_SLIDE_SEC else 0)
	end
end

-- the "DAY N" / "NIGHT N" card, up for a moment with its sound
-- the card, with every named sound played as it appears
function ClientRunCycleManager:showCard(text: string, sfxNames: { string })
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
	for _, sfxName in sfxNames do
		ClientSoundManager:playSfx(sfxName)
	end
	task.delay(
		CARD_SHOW_SEC,
		function()
			if self.numberGeneration ~= generation then
				return
			end
			gui.Enabled = false
			for _, callback in self.cardClosedCallbacks do
				callback()
			end
		end
	)
end

function ClientRunCycleManager:subscribeCardClosed(callback: () -> ())
	table.insert(self.cardClosedCallbacks, callback)
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
	self:refreshDay()
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
-- the full helicopter leaves into a sunset (designer, 2026-10-27): once
-- the run is won with the turn back begun, the sky goes from the night's
-- end look to the day's end over RescueSunsetToDayEndSec, then on back
-- to the day's start over RescueSunsetToDayStartSec, the clock turning
-- backward the whole way; true when it took the frame
function ClientRunCycleManager:stepSunsetIfNeeded(runState: number, now: number): boolean
	if runState ~= Enums.RunState.WON then
		self.sunsetHeldAtTime = nil
		return false
	end
	-- held: the sky and clock stay where they were at the hold
	now = self.sunsetHeldAtTime or now
	local sunsetStartTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RESCUE_SUNSET_START_TIME), 0)
	local toDayEndSec = readNumber(ClientDataManager:getGameMetadata(Attributes.RESCUE_SUNSET_TO_DAY_END_SEC), 0)
	local toDayStartSec = readNumber(ClientDataManager:getGameMetadata(Attributes.RESCUE_SUNSET_TO_DAY_START_SEC), 0)
	local stage, share = RunCycleRules.sunsetStage(sunsetStartTime, now, toDayEndSec, toDayStartSec)
	if not stage then
		return false
	end
	local presets = self:getMapPresets()
	local from = if stage == RunCycleRules.SUNSET_STAGE_TO_DAY_END then presets.NIGHT_END else presets.DAY_END
	local to = if stage == RunCycleRules.SUNSET_STAGE_TO_DAY_END then presets.DAY_END else presets.DAY_START
	self:applyBlend(Lighting, from.LIGHTING, to.LIGHTING, share)
	for childName, fromChild in from.CHILDREN do
		local child = Lighting:FindFirstChild(childName)
		local toChild = to.CHILDREN[childName]
		if child and toChild then
			self:applyBlend(child, fromChild, toChild, share)
		end
	end
	Lighting.ClockTime = RunCycleRules.clockTimeBackward(from.LIGHTING.ClockTime, to.LIGHTING.ClockTime, share)
	for _, handler in self.skyAppliedHandlers do
		handler(Enums.SkyStage.DAY, if stage == RunCycleRules.SUNSET_STAGE_TO_DAY_END then 1 else 1 - share)
	end
	return true
end

-- the ride's camera stops the sunset as it starts its final drift, so the
-- sky and the clock stand still under the title card and the menu
-- (designer, 2026-10-27); released when the ride ends or a new run starts
function ClientRunCycleManager:setSunsetHeld(isHeld: boolean)
	if isHeld then
		if not self.sunsetHeldAtTime then
			self.sunsetHeldAtTime = workspace:GetServerTimeNow()
		end
	else
		self.sunsetHeldAtTime = nil
	end
end

function ClientRunCycleManager:stepSky(runState: number, startTime: number, endTime: number, now: number)
	if self:stepSunsetIfNeeded(runState, now) then
		return
	end
	local presets = self:getMapPresets()
	local dawnTransitionSec = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_LIGHTING_DAWN_TRANSITION_SEC), DEFAULT_DAWN_TRANSITION_SEC)
	local duskTransitionSec = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_LIGHTING_DUSK_TRANSITION_SEC), DEFAULT_DUSK_TRANSITION_SEC)
	local spawnSec = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_NIGHT_SPAWN_SEC), DEFAULT_NIGHT_SPAWN_SEC)
	local heldDayShare = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_RESCUE_HELD_DAY_SHARE), -1)
	-- a Rescue Wait's sky holds through the call sequence, then eases to
	-- the day's end over the breather (M75)
	local breatherStartTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RESCUE_COUNTDOWN_START_TIME), startTime)
	local stage, share = RunCycleRules.skyStage(runState, startTime, endTime, now, dawnTransitionSec, duskTransitionSec, spawnSec, heldDayShare, breatherStartTime)
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
	for _, handler in self.skyAppliedHandlers do
		handler(stage, share)
	end
end

function ClientRunCycleManager:subscribeSkyApplied(handler: (stage: number, share: number) -> ())
	table.insert(self.skyAppliedHandlers, handler)
end

-- every frame: the bar from the published phase times against server time
-- the dusk song starts from the top the day's dusk before the night falls
-- (the day's published end time), once per day; a day cut short by the
-- dev tool starts it as soon as the lead is reached. It fades out over
-- the published fade, beginning the fade lead before night falls, so it
-- is silent that long again into the night (2026-10-02)
function ClientRunCycleManager:stepDuskSong(runState: number, endTime: number, now: number)
	local songEndTime = self.duskSongEndTime
	if songEndTime and not self.isDuskSongFading and runState == Enums.RunState.RESCUE_WAIT then
		-- the rescue is called under the dusk song: out quickly
		self.isDuskSongFading = true
		ClientSoundManager:fadeOutMusic(SoundNames.Music.DUSK_SONG_1, DUSK_SONG_RESCUE_CALL_FADE_SEC)
	end
	if songEndTime and not self.isDuskSongFading then
		local fadeLeadSec = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_DUSK_SONG_FADE_LEAD_SEC), DEFAULT_DUSK_SONG_FADE_LEAD_SEC)
		-- a day cut short by the dev tool brings the fall, and the fade, forward
		if runState == Enums.RunState.DAY and endTime > 0 and endTime < songEndTime then
			songEndTime = endTime
			self.duskSongEndTime = endTime
		end
		if now >= songEndTime - fadeLeadSec then
			self.isDuskSongFading = true
			ClientSoundManager:fadeOutMusic(SoundNames.Music.DUSK_SONG_1, readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_DUSK_SONG_FADE_SEC), DEFAULT_DUSK_SONG_FADE_SEC))
		end
	end
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
	self.duskSongEndTime = endTime
	self.isDuskSongFading = false
	ClientSoundManager:fadeInMusic(SoundNames.Music.DUSK_SONG_1, nil, DUSK_SONG_FADE_IN_SEC)
end

function ClientRunCycleManager:step()
	local runState = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_STATE), Enums.RunState.DAY)
	local startTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PHASE_START_TIME), 0)
	local endTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PHASE_END_TIME), 0)
	local duskShare = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_DUSK_SHARE), DEFAULT_DUSK_SHARE)
	local now = workspace:GetServerTimeNow()
	-- any hold on the run (the dev tool's pause, a crew wipe) keeps the
	-- clock at the moment it began; only the dev tool's shows the PAUSED
	-- word, since a wipe already has the Game Over screen up
	local pauseStartTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PAUSE_START_TIME), 0)
	if pauseStartTime > 0 then
		now = pauseStartTime
	end
	local isPausedByDevTool = pauseStartTime > 0 and ClientDataManager:getGameMetadata(Attributes.RUN_PAUSED_BY_DEV_TOOL) == true
	local pausedGui = self.pausedGui
	if pausedGui and pausedGui.Enabled ~= isPausedByDevTool then
		pausedGui.Enabled = isPausedByDevTool
	end
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
		local format = if self.shownPhase == Enums.ClockPhase.DUSK then SUNSET_FORMAT else DAY_FORMAT
		dayLabel.Text = UiStyle.formatTitle(string.format(format, RunCycleRules.shownDay(readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_DAY), 1))))
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
	-- every day has its card and the card's sting (designer, 2026-10-21;
	-- day 1 had no card before): day 1's as the clock starts, and from
	-- day 2 the rooster crows first and the card follows it
	local day = payload.day
	local startTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PHASE_START_TIME), 0)
	local delaySec = math.max(startTime - workspace:GetServerTimeNow(), 0)
	task.delay(
		delaySec,
		function()
			if day == FIRST_DAY then
				self:showCard(string.format(DAY_CARD_FORMAT, day), { SoundNames.Sfx.DAY_CARD })
				return
			end
			ClientSoundManager:playSfx(SoundNames.Sfx.ROOSTER)
			task.delay(
				ROOSTER_TO_CARD_SEC,
				function()
					self:showCard(string.format(DAY_CARD_FORMAT, day), { SoundNames.Sfx.DAY_CARD })
				end
			)
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
			-- the final wave's night is the rescue's (designer, 2026-10-27)
			local runState = ClientDataManager:getGameMetadata(Attributes.RUN_STATE)
			local text = if runState == Enums.RunState.RESCUE then FINAL_NIGHT_CARD_TEXT else string.format(NIGHT_CARD_FORMAT, day)
			self:showCard(text, { SoundNames.Sfx.NIGHT_BELL })
		end
	)
end

function ClientRunCycleManager:onRunEnded(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_RUN_ENDED_SHAPE) then
		warn("ClientRunCycleManager: malformed NotifyRunEnded")
		return
	end
	-- a run's end is told by the Game Over screen or the ride out and the
	-- Results Menu (ClientReviveManager, M32); a win had its line here too
	-- until 2026-10-27 (designer: the menu is the word), so the message
	-- is not shown
end

-- the night's loop follows the server's IsNight flag (the rescue counts
-- as night), eased to its authored volume as night falls and out again
-- from wherever it is at the night's end; it also goes out, slower, when
-- the night is over for this player before its end: they are dead (the
-- Game Over screen is up), the run is lost, or it is won (designer,
-- 2026-10-27). A revive at night brings it back
function ClientRunCycleManager:refreshNightSong()
	local isNight = ClientDataManager:getGameMetadata(Attributes.IS_NIGHT) == true
	local runState = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_STATE), Enums.RunState.DAY)
	local isCutShort = self.isLocalPlayerDead or RunCycleRules.isRunOver(runState)
	if isNight and not isCutShort then
		ClientSoundManager:fadeMusicTo(SoundNames.Music.NIGHT_SONG, 1, NIGHT_SONG_FADE_IN_SEC)
		return
	end
	ClientSoundManager:fadeMusicTo(SoundNames.Music.NIGHT_SONG, 0, if isCutShort then NIGHT_SONG_END_FADE_SEC else NIGHT_SONG_FADE_OUT_SEC)
end

function ClientRunCycleManager:init()
	self:findGui()
	local localUserId = Players.LocalPlayer.UserId
	ClientDataManager:subscribeAllPlayers({
		onAdded = function(userId: number, data: ClientDataManager.PublicData)
			if userId == localUserId then
				self.isLocalPlayerDead = data.isDead
				self:refreshNightSong()
			end
		end,
		onChanged = function(userId: number, data: ClientDataManager.PublicData)
			if userId == localUserId and data.isDead ~= self.isLocalPlayerDead then
				self.isLocalPlayerDead = data.isDead
				self:refreshNightSong()
			end
		end,
	})
	self:refreshNightSong()
	for _, key in { Attributes.IS_NIGHT, Attributes.RUN_STATE } do
		ClientDataManager:subscribeGameMetadataAttribute(
			key,
			function()
				self:refreshNightSong()
			end
		)
	end
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
	self.pausedGui = nil
	self.clockGroup = nil
	self.slide = nil
	self.numberGui = nil
	self.numberLabel = nil
	self.numberGeneration = 0
	self.cardClosedCallbacks = {}
	self.isLocalPlayerDead = false
	self.phaseIcon = nil
	self.fill = nil
	self.dayLabel = nil
	self.shownPhase = nil
	self.duskSongDay = nil
	self.duskSongEndTime = nil
	self.isDuskSongFading = false
	self.skyAppliedHandlers = {}
	self.sunsetHeldAtTime = nil
	self.warnedChildren = {}
	return self
end

return ClientRunCycleManager.new()
