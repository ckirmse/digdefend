--!strict

-- The rescue as the crew sees it (GDD "Helicopter Pad"), M31: the radio's
-- billboard on Camp.Radio.GuiPart (the RescueRadio template under
-- GameAssets/Gui) showing the uranium count against the target and what
-- the radio is doing (waiting for the target, ready to call, the
-- helicopter's countdown, boarding), the radio's own screen and lamp
-- turning green with QUOTA COMPLETE once the target is met, all from
-- GameMetadata the server publishes; the rescue announcements in the
-- announcement box; and the countdown in the day clock's spot once the
-- radio is used (2026-10-07): to the final wave, then to the helicopter,
-- then the call to board. The prompts themselves are the server's.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientHudSlide = require(script.Parent.Parent.Client.ClientHudSlide)
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientGuiFade = require(script.Parent.Parent.Client.ClientGuiFade)
local ClientRunCycleManager = require(script.Parent.ClientRunCycleManager)

local ClientRescueManager = {}
ClientRescueManager.__index = ClientRescueManager

export type ClientRescueManager = typeof(setmetatable(
	{} :: {
		billboard: BillboardGui?,
		uraniumLabel: TextLabel?,
		statusLabel: TextLabel?,
		-- the radio's screen, left as the designer set it until the quota is met
		screenBackground: Frame?,
		screenLabel: TextLabel?,
		screenLight: Light?,
		isQuotaShown: boolean,
		shownUranium: string,
		shownStatus: string,
		lastStepTime: number,
		countdownGui: ScreenGui?,
		countdownLabel: TextLabel?,
		countdownSlide: ClientHudSlide.ClientHudSlide?,
		isCountdownShown: boolean,
		shownCountdown: string,
		-- the countdown's text fades: out as the breather ends, in once the
		-- FINAL NIGHT card has gone (designer, 2026-10-27)
		countdownFadeTarget: number,
		countdownFade: Tween?,
		isHelicopterCountdownReleased: boolean,
		-- the label's authored spot (the clock's); the final night moves it
		-- below the Refinery HP bar while it is invisible
		countdownUpperPosition: UDim2?,
		isCountdownLowered: boolean,
		-- bumped by every billboard show or hide, so a fade's end that was
		-- overtaken by a show leaves it on
		billboardFadeGeneration: number,
		-- the final night's song runs from the flash going down until it
		-- fades across the night's fall
		isFinalNightSongPlaying: boolean,
		isFinalNightSongFading: boolean,
		-- the landed line's red flashes rung so far
		landedFlashCount: number,
		wasCountdownRed: boolean,
		-- how many were aboard last frame, so each new rider chimes once
		shownAboardCount: number,
		lastRunState: number,
		-- the call sequence: the designer's INCOMING gui, the tint while it
		-- is up, and a counter that lets a dropped sequence stop short
		incomingGui: ScreenGui?,
		incomingLabel: TextLabel?,
		incomingFirstText: string?,
		colorCorrection: ColorCorrectionEffect?,
		callGeneration: number,
		-- the countdown waits for the sequence to finish (designer, 2026-10-27)
		isCallSequenceRunning: boolean,
	},
	ClientRescueManager
))

local NOTIFY_RESCUE_ANNOUNCEMENT_SHAPE = {
	message = "string",
	displaySec = "positiveNumber",
	-- good news (the target reached, the rescue called) is green
	isGood = "boolean",
}

local STEP_INTERVAL_SEC = 0.25
-- the uranium icon sits beside this on the template (UI rule: icons, not words)
local URANIUM_FORMAT = "%d / %d"
local STATUS_WAITING = "Complete your Uranium quota to call in a rescue helicopter"
local STATUS_READY = "Quota Complete. Call in a rescue helicopter"
local STATUS_FLYING = "Rescue helicopter incoming. Hold the line until it arrives."
local STATUS_BOARDING_FORMAT = "Boarding  %d / %d aboard, leaving in %d s"
local STATUS_WON = "Rescued"
local STATUS_LOST = "No rescue is coming"
-- the countdown where the day clock was: it follows the clock up the
-- screen and comes down in its place (designer, 2026-10-07); its last
-- stretch names the approach, and once landed it counts the deadline
-- down (M75)
local COUNTDOWN_WAVE_FORMAT = "Final Night Begins In: %s"
-- the whole flight, the approach included (an INBOUND line was tried and
-- dropped, 2026-10-27)
local COUNTDOWN_HELICOPTER_FORMAT = "Helicopter Arrives In: %s"
-- once landed, flashing red (designer, 2026-10-27; the exclamation mark is
-- the designer's call)
local COUNTDOWN_BOARD_FORMAT = "Board Now! Leaving In: %s"
-- a seated rider's line while crewmates are still out (designer, 2026-10-27)
local COUNTDOWN_WAITING_FORMAT = "Waiting for Teammates. Leaving In: %s"
local COUNTDOWN_FLASH_HZ = 2
-- the landed alert rings with the first red flash only (three rings
-- were tried and dropped, designer 2026-10-27)
local LANDED_ALERT_FLASH_COUNT = 1
-- the final night's song fades out like the dusk song: over
-- FINAL_NIGHT_SONG_FADE_SEC, starting this far before the night falls
local FINAL_NIGHT_SONG_FADE_SEC = 10
local FINAL_NIGHT_SONG_FADE_LEAD_SEC = 5
local FINAL_NIGHT_SONG_FADE_IN_SEC = 5
-- the call sequence (designer, 2026-10-27): the green tint stays up
-- INCOMING_TEXT_SWAP_SEC, at which moment the gui's line changes to the
-- second one with the day card's sting, and the gui itself stays up
-- INCOMING_FLASH_SEC in all; then how long to wait on a dispatch Sound
-- whose length is unknown
local INCOMING_FLASH_SEC = 6
local INCOMING_TEXT_SWAP_SEC = 3
-- on two lines (designer, 2026-10-27)
local INCOMING_SECOND_TEXT = "Survive the\nfinal night"
local DISPATCH_FALLBACK_SEC = 8
local DISPATCH_END_GRACE_SEC = 0.5
local INCOMING_TINT_NAME = "RescueIncomingTint"
local INCOMING_TINT_COLOR = Color3.fromRGB(0, 255, 0)
local COUNTDOWN_HIDDEN_POSITION_Y_SCALE = -0.3
-- the radio's billboard fades out over this long when the call lands
-- (designer, 2026-10-27), every element together
local BILLBOARD_FADE_SEC = 1
-- the countdown's second spot on stage: below the Refinery HP bar, which
-- takes the clock's spot for the final night (the bar's authored box is
-- 0.10625 of the height from 0.012, build_refinery_hp_gui.luau)
local COUNTDOWN_LOWER_POSITION_Y_SCALE = 0.012 + 0.10625 + 0.01
-- the breather's last second fades the countdown out, and the
-- helicopter's fades in once the FINAL NIGHT card is down (designer,
-- 2026-10-27); a viewer who saw no card gets it this long into the night
local COUNTDOWN_FADE_SEC = 1
local COUNTDOWN_FADE_OUT_LEAD_SEC = 1
local HELICOPTER_COUNTDOWN_FALLBACK_SEC = 6
-- the radio's screen once the quota is met (the designer's colour)
local QUOTA_COMPLETE_TEXT = "QUOTA COMPLETE"
local QUOTA_COMPLETE_COLOR = Color3.fromRGB(76, 229, 112)

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

function ClientRescueManager:attachBillboard()
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.RESCUE_RADIO_BILLBOARD) else nil
	if not template or not template:IsA("BillboardGui") then
		warn(`ClientRescueManager: no {Constants.RESCUE_RADIO_BILLBOARD} BillboardGui under GameAssets.{Constants.GUI_TEMPLATES_FOLDER}; run scripts/studio/build_rescue_radio_billboard.luau`)
		return
	end
	local camp = workspace:WaitForChild(Constants.CAMP_FOLDER, 30)
	local radio = if camp then camp:WaitForChild(Constants.CAMP_RADIO_MODEL, 30) else nil
	-- with StreamingEnabled the Model can arrive before its parts on a real
	-- device, so wait for the part the map contract guarantees by name
	local adornee = if radio then radio:WaitForChild(Constants.RADIO_GUI_PART, 30) else nil
	if not radio or not adornee or not adornee:IsA("BasePart") then
		warn(`ClientRescueManager: no Camp.{Constants.CAMP_RADIO_MODEL}.{Constants.RADIO_GUI_PART} to hang the radio billboard on`)
		return
	end
	local billboard = template:Clone()
	-- the designer places GuiPart where the sign should float
	billboard.Adornee = adornee
	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- a run already past its call shows no sign (a late viewer)
	local runState = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_STATE), Enums.RunState.DAY)
	billboard.Enabled = runState == Enums.RunState.DAY or runState == Enums.RunState.NIGHT or runState == Enums.RunState.WAITING
	self:findScreen(radio)
	self.billboard = billboard
	local root = billboard:FindFirstChild(Constants.RESCUE_RADIO_ROOT_FRAME)
	local row = if root then root:FindFirstChild(Constants.RESCUE_RADIO_URANIUM_ROW) else nil
	local uranium = if row then row:FindFirstChild(Constants.RESCUE_RADIO_URANIUM_LABEL) else nil
	local status = if root then root:FindFirstChild(Constants.RESCUE_RADIO_STATUS_LABEL) else nil
	self.uraniumLabel = if uranium and uranium:IsA("TextLabel") then uranium else nil
	self.statusLabel = if status and status:IsA("TextLabel") then status else nil
	self.shownUranium = ""
	self.shownStatus = ""
	self:render()
end

-- the radio's own screen and lamp (Radio.Radio.Screen), if the model has them
function ClientRescueManager:findScreen(radio: Instance)
	local inner = radio:FindFirstChild(Constants.RADIO_INNER_MODEL)
	local screen = if inner then inner:FindFirstChild(Constants.RADIO_SCREEN_PART) else nil
	local gui = if screen then screen:FindFirstChild(Constants.RADIO_SCREEN_GUI) else nil
	local frame = if gui then gui:FindFirstChild(Constants.RADIO_SCREEN_FRAME) else nil
	local background = if frame then frame:FindFirstChild(Constants.RADIO_SCREEN_BACKGROUND) else nil
	local label = if background then background:FindFirstChild(Constants.RADIO_SCREEN_LABEL) else nil
	local light = if screen then screen:FindFirstChild(Constants.RADIO_SCREEN_LIGHT) else nil
	self.screenBackground = if background and background:IsA("Frame") then background else nil
	self.screenLabel = if label and label:IsA("TextLabel") then label else nil
	self.screenLight = if light and light:IsA("Light") then light else nil
	if not self.screenBackground or not self.screenLabel or not self.screenLight then
		warn(`ClientRescueManager: the radio has no {Constants.RADIO_INNER_MODEL}.{Constants.RADIO_SCREEN_PART} screen and lamp to turn green; it stays as authored`)
	end
end

-- once, when the quota is met: the screen and lamp go green
function ClientRescueManager:showQuotaComplete()
	if self.isQuotaShown then
		return
	end
	self.isQuotaShown = true
	local background = self.screenBackground
	if background then
		background.BackgroundColor3 = QUOTA_COMPLETE_COLOR
	end
	local label = self.screenLabel
	if label then
		label.Text = QUOTA_COMPLETE_TEXT
	end
	local light = self.screenLight
	if light then
		light.Color = QUOTA_COMPLETE_COLOR
	end
end

-- the status line for the run's state; the countdowns read the phase end
-- the server published, against server time
function ClientRescueManager:statusText(now: number): string
	local runState = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_STATE), Enums.RunState.DAY)
	if runState == Enums.RunState.WON then
		return STATUS_WON
	end
	if runState == Enums.RunState.LOST then
		return STATUS_LOST
	end
	if runState == Enums.RunState.RESCUE then
		local endTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PHASE_END_TIME), 0)
		local secondsLeft = math.max(0, math.ceil(endTime - now))
		local isLanded = ClientDataManager:getGameMetadata(Attributes.RESCUE_IS_LANDED) == true
		if not isLanded then
			return STATUS_FLYING
		end
		local aboard = readNumber(ClientDataManager:getGameMetadata(Attributes.RESCUE_ABOARD_COUNT), 0)
		local crew = readNumber(ClientDataManager:getGameMetadata(Attributes.RESCUE_CREW_COUNT), 0)
		return string.format(STATUS_BOARDING_FORMAT, aboard, crew, secondsLeft)
	end
	local total = readNumber(ClientDataManager:getGameMetadata(Attributes.URANIUM_TOTAL), 0)
	local target = readNumber(ClientDataManager:getGameMetadata(Attributes.URANIUM_TARGET), 0)
	return if target > 0 and total >= target then STATUS_READY else STATUS_WAITING
end

local function formatClock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%02d:%02d", whole // 60, whole % 60)
end

function ClientRescueManager:isLocalPlayerAboard(): boolean
	return ClientDataManager:getCurrentPlayerAttribute(Attributes.RESCUE_IS_ABOARD) == true
end

function ClientRescueManager:isHelicopterLanded(): boolean
	local runState = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_STATE), Enums.RunState.DAY)
	return runState == Enums.RunState.RESCUE and ClientDataManager:getGameMetadata(Attributes.RESCUE_IS_LANDED) == true
end

-- what the countdown reads, or nil while it has nothing to say
function ClientRescueManager:countdownText(now: number): string?
	local runState = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_STATE), Enums.RunState.DAY)
	local endTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PHASE_END_TIME), 0)
	local pauseStartTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PAUSE_START_TIME), 0)
	if pauseStartTime > 0 then
		now = pauseStartTime
	end
	if runState == Enums.RunState.RESCUE_WAIT then
		-- nothing until the call sequence has played out here and the
		-- breather has begun on the server (a late viewer sees it at once)
		local countdownStartTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RESCUE_COUNTDOWN_START_TIME), 0)
		if self.isCallSequenceRunning or now < countdownStartTime then
			return nil
		end
		return UiStyle.formatTitle(string.format(COUNTDOWN_WAVE_FORMAT, formatClock(endTime - now)))
	end
	if runState == Enums.RunState.RESCUE then
		local clock = formatClock(endTime - now)
		if self:isHelicopterLanded() then
			local format = if self:isLocalPlayerAboard() then COUNTDOWN_WAITING_FORMAT else COUNTDOWN_BOARD_FORMAT
			return UiStyle.formatTitle(string.format(format, clock))
		end
		return UiStyle.formatTitle(string.format(COUNTDOWN_HELICOPTER_FORMAT, clock))
	end
	return nil
end

-- each crewmate boarding chimes for everyone (M75); a count that falls
-- (a rider died or left) is quiet
function ClientRescueManager:chimeBoardingIfNeeded()
	local aboard = readNumber(ClientDataManager:getGameMetadata(Attributes.RESCUE_ABOARD_COUNT), 0)
	if aboard > self.shownAboardCount then
		ClientSoundManager:playSfx(SoundNames.Sfx.RESCUE_BOARD)
	end
	self.shownAboardCount = aboard
end

-- the designer's dispatch message on the radio model, a Sound under
-- Camp.Radio (3D, so it is heard from the table)
function ClientRescueManager:findDispatchSound(): Sound?
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	local radio = if camp then camp:FindFirstChild(Constants.CAMP_RADIO_MODEL) else nil
	local sound = if radio then radio:FindFirstChild(Constants.RADIO_DISPATCH_SOUND, true) else nil
	return if sound and sound:IsA("Sound") then sound else nil
end

-- the flash comes off: the gui (its first line put back for the next
-- call), the green tint
function ClientRescueManager:endIncomingFlash()
	local gui = self.incomingGui
	if gui then
		gui.Enabled = false
	end
	local label = self.incomingLabel
	if label and self.incomingFirstText then
		label.Text = self.incomingFirstText
	end
	self:endIncomingTint()
	self:endCallSequence()
end

function ClientRescueManager:endIncomingTint()
	local colorCorrection = self.colorCorrection
	if colorCorrection then
		colorCorrection:Destroy()
		self.colorCorrection = nil
	end
end

-- the green tint on the camera for the call's flash
function ClientRescueManager:beginIncomingTint()
	local camera = workspace.CurrentCamera
	if not camera or self.colorCorrection then
		return
	end
	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = INCOMING_TINT_NAME
	colorCorrection.TintColor = INCOMING_TINT_COLOR
	colorCorrection.Parent = camera
	self.colorCorrection = colorCorrection
end

-- the call sequence (designer, 2026-10-27): the radio's dispatch message
-- plays out from the table, then the RESCUE HELICOPTER INCOMING gui and
-- a green tint come up with the incoming sting; INCOMING_TEXT_SWAP_SEC in
-- the tint goes and the line becomes SURVIVE THE FINAL NIGHT with the day
-- card's sting, and INCOMING_FLASH_SEC after it came up the gui goes
-- away. A call that is over before the sequence finishes (the Team
-- Revive starting the day over) drops the rest of it
function ClientRescueManager:playCallSequence()
	self.callGeneration += 1
	local generation = self.callGeneration
	self.isCallSequenceRunning = true
	task.spawn(
		function()
			local dispatch = self:findDispatchSound()
			if dispatch then
				dispatch:Play()
				-- a Sound that has not loaded reports no length; the wait is
				-- bounded either way
				local waitSec = if dispatch.TimeLength > 0 then dispatch.TimeLength else DISPATCH_FALLBACK_SEC
				local deadline = workspace:GetServerTimeNow() + waitSec + DISPATCH_END_GRACE_SEC
				while dispatch.IsPlaying and workspace:GetServerTimeNow() < deadline do
					task.wait(0.1)
				end
			else
				warn(`ClientRescueManager: the radio has no {Constants.RADIO_DISPATCH_SOUND} Sound; the dispatch message is skipped`)
			end
			if generation ~= self.callGeneration then
				return
			end
			local gui = self.incomingGui
			if gui then
				gui.Enabled = true
			end
			self:beginIncomingTint()
			ClientSoundManager:playSfx(SoundNames.Sfx.RESCUE_INCOMING)
			task.wait(INCOMING_TEXT_SWAP_SEC)
			if generation ~= self.callGeneration then
				return
			end
			self:endIncomingTint()
			local label = self.incomingLabel
			if label then
				label.Text = UiStyle.formatTitle(INCOMING_SECOND_TEXT)
			end
			ClientSoundManager:playSfx(SoundNames.Sfx.DAY_CARD)
			task.wait(INCOMING_FLASH_SEC - INCOMING_TEXT_SWAP_SEC)
			if generation ~= self.callGeneration then
				return
			end
			self:endIncomingFlash()
			self:startFinalNightSong()
		end
	)
end

-- the final night's song takes over from the flash, up from silence to
-- its authored volume over FINAL_NIGHT_SONG_FADE_IN_SEC (designer, 2026-10-27)
function ClientRescueManager:startFinalNightSong()
	self.isFinalNightSongPlaying = true
	self.isFinalNightSongFading = false
	ClientSoundManager:fadeInMusic(SoundNames.Music.FINAL_NIGHT_SONG, nil, FINAL_NIGHT_SONG_FADE_IN_SEC, true)
end

-- the song fades out across the final night's fall the dusk song's way
-- (the fade lead before the breather ends), or at once when the breather
-- is cut short (the Team Revive, the run's end)
function ClientRescueManager:stepFinalNightSong(runState: number, endTime: number, now: number)
	if not self.isFinalNightSongPlaying or self.isFinalNightSongFading then
		return
	end
	local isBreather = runState == Enums.RunState.RESCUE_WAIT
	if isBreather and (endTime <= 0 or now < endTime - FINAL_NIGHT_SONG_FADE_LEAD_SEC) then
		return
	end
	self.isFinalNightSongFading = true
	ClientSoundManager:fadeOutMusic(SoundNames.Music.FINAL_NIGHT_SONG, FINAL_NIGHT_SONG_FADE_SEC)
end

-- the sequence is over (or dropped): the countdown may show
function ClientRescueManager:endCallSequence()
	self.isCallSequenceRunning = false
end

-- the call sequence starts as the run enters its Rescue Wait and is
-- dropped when the run leaves it: the final wave, the day starting over,
-- or the run's end
function ClientRescueManager:onRunStateChanged()
	local runState = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_STATE), Enums.RunState.DAY)
	if runState == self.lastRunState then
		return
	end
	local wasWaiting = self.lastRunState == Enums.RunState.RESCUE_WAIT
	self.lastRunState = runState
	if runState == Enums.RunState.RESCUE_WAIT then
		-- the radio has done its job: its sign goes (designer, 2026-10-27)
		self:setBillboardShown(false)
		self:playCallSequence()
		return
	end
	if wasWaiting then
		self.callGeneration += 1
		self:endIncomingFlash()
		-- the day starting over (the Team Revive) brings the sign back;
		-- the final wave and the run's end leave it off
		if runState == Enums.RunState.DAY or runState == Enums.RunState.NIGHT then
			self:setBillboardShown(true)
		end
	end
end

-- the billboard goes with a fade (designer, 2026-10-27; ClientGuiFade)
-- and is disabled after, the authored values back underneath so a day
-- starting over shows it whole; a show puts it back at once
function ClientRescueManager:setBillboardShown(isShown: boolean)
	local billboard = self.billboard
	if not billboard then
		return
	end
	self.billboardFadeGeneration += 1
	local generation = self.billboardFadeGeneration
	if isShown then
		billboard.Enabled = true
		return
	end
	if not billboard.Enabled then
		return
	end
	ClientGuiFade.fadeOut(
		billboard,
		BILLBOARD_FADE_SEC,
		function()
			-- a show in the meantime wins
			if self.billboardFadeGeneration == generation then
				billboard.Enabled = false
			end
		end
	)
end

function ClientRescueManager:findIncomingGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.RESCUE_INCOMING_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`ClientRescueManager: no {Constants.RESCUE_INCOMING_GUI_NAME} ScreenGui in StarterGui; the incoming flash is skipped`)
		return
	end
	gui.Enabled = false
	self.incomingGui = gui
	local label = gui:FindFirstChild(Constants.RESCUE_INCOMING_LABEL)
	if label and label:IsA("TextLabel") then
		self.incomingLabel = label
		-- the designer's own line, restored after each flash
		self.incomingFirstText = label.Text
	else
		warn(`ClientRescueManager: the {Constants.RESCUE_INCOMING_GUI_NAME} gui has no {Constants.RESCUE_INCOMING_LABEL}; its line cannot change`)
	end
end

-- the text's transparency eased to a target, at once for a fade of 0
function ClientRescueManager:fadeCountdownTo(target: number, fadeSec: number)
	local label = self.countdownLabel
	if not label or self.countdownFadeTarget == target then
		return
	end
	self.countdownFadeTarget = target
	local fade = self.countdownFade
	if fade then
		fade:Cancel()
		self.countdownFade = nil
	end
	if fadeSec <= 0 then
		label.TextTransparency = target
		return
	end
	local tween = TweenService:Create(label, TweenInfo.new(fadeSec, Enum.EasingStyle.Linear), { TextTransparency = target })
	self.countdownFade = tween
	tween:Play()
end

-- the label's spot on stage: the clock's, or below the Refinery HP bar
-- for the final night (moved while it is invisible, designer 2026-10-27);
-- with a slideSec it slides there in view (the landing, 2026-10-28)
function ClientRescueManager:setCountdownLowered(isLowered: boolean, slideSec: number?)
	local slide = self.countdownSlide
	local upper = self.countdownUpperPosition
	if not slide or not upper or self.isCountdownLowered == isLowered then
		return
	end
	self.isCountdownLowered = isLowered
	slide:setShownPosition(if isLowered then UDim2.new(upper.X.Scale, upper.X.Offset, COUNTDOWN_LOWER_POSITION_Y_SCALE, 0) else upper, slideSec)
end

-- the handover from the breather's countdown to the helicopter's
-- (designer, 2026-10-27): the first fades out over its last second in the
-- clock's spot, the second is held invisible under the FINAL NIGHT card,
-- moved below the Refinery HP bar, and fades in there once the card is
-- down (or, for a viewer who saw no card, a little into the night)
function ClientRescueManager:renderCountdownFade(now: number)
	local runState = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_STATE), Enums.RunState.DAY)
	local endTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PHASE_END_TIME), 0)
	if runState == Enums.RunState.RESCUE_WAIT then
		self:setCountdownLowered(false)
		if endTime - now <= COUNTDOWN_FADE_OUT_LEAD_SEC then
			self:fadeCountdownTo(1, COUNTDOWN_FADE_SEC)
		else
			self:fadeCountdownTo(0, 0)
		end
		return
	end
	if runState == Enums.RunState.RESCUE then
		local startTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PHASE_START_TIME), 0)
		if not self.isHelicopterCountdownReleased and now - startTime >= HELICOPTER_COUNTDOWN_FALLBACK_SEC then
			self.isHelicopterCountdownReleased = true
		end
		if self:isHelicopterLanded() then
			-- the Refinery HP bar leaves with the landing and the countdown
			-- climbs back to the clock's spot beside it (designer, 2026-10-28)
			self:setCountdownLowered(false, UiStyle.HUD_SLIDE_SEC)
			self:fadeCountdownTo(0, COUNTDOWN_FADE_SEC)
		elseif self.isHelicopterCountdownReleased then
			self:setCountdownLowered(true)
			self:fadeCountdownTo(0, COUNTDOWN_FADE_SEC)
		else
			self:fadeCountdownTo(1, 0)
			self:setCountdownLowered(true)
		end
		return
	end
	self.isHelicopterCountdownReleased = false
	self:setCountdownLowered(false)
	self:fadeCountdownTo(0, 0)
end

-- the landed line flashes red (designer, 2026-10-27)
function ClientRescueManager:renderCountdownColor(now: number)
	local label = self.countdownLabel
	if not label then
		return
	end
	-- the flash is for a player still on the ground
	local isLanded = self:isHelicopterLanded() and not self:isLocalPlayerAboard()
	local isRed = isLanded and math.floor(now * COUNTDOWN_FLASH_HZ) % 2 == 0
	local color = if isRed then UiStyle.NEGATIVE_COLOR else UiStyle.TEXT_COLOR
	if label.TextColor3 ~= color then
		label.TextColor3 = color
	end
	if not isLanded then
		self.landedFlashCount = 0
	elseif isRed and not self.wasCountdownRed and self.landedFlashCount < LANDED_ALERT_FLASH_COUNT then
		-- the first flash rings so nobody misses the landing
		self.landedFlashCount += 1
		ClientSoundManager:playSfx(SoundNames.Sfx.RESCUE_LANDED)
	end
	self.wasCountdownRed = isRed
end

function ClientRescueManager:renderCountdown(now: number)
	local label = self.countdownLabel
	local slide = self.countdownSlide
	if not label or not slide then
		return
	end
	local text = self:countdownText(now)
	local isShown = text ~= nil
	if isShown ~= self.isCountdownShown then
		self.isCountdownShown = isShown
		-- down once the day clock has slid away, like the Refinery HP bar
		slide:setShown(isShown, if isShown then UiStyle.HUD_SLIDE_SEC else 0)
	end
	if text and text ~= self.shownCountdown then
		self.shownCountdown = text
		label.Text = text
	end
	self:renderCountdownFade(now)
	self:renderCountdownColor(now)
	local runState = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_STATE), Enums.RunState.DAY)
	self:stepFinalNightSong(runState, readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PHASE_END_TIME), 0), now)
end

function ClientRescueManager:findCountdownGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.RESCUE_COUNTDOWN_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientRescueManager: no RescueCountdown ScreenGui; run scripts/studio/build_rescue_countdown_gui.luau")
		return
	end
	local label = gui:FindFirstChild(Constants.RESCUE_COUNTDOWN_LABEL)
	if not label or not label:IsA("TextLabel") then
		warn("ClientRescueManager: the RescueCountdown gui has no Label; rebuild it")
		return
	end
	self.countdownGui = gui
	self.countdownLabel = label
	-- the authored spot is read before the snap moves the label off stage
	-- (it was read after, so the climb back after the landing went to the
	-- hidden spot, 2026-10-28)
	self.countdownUpperPosition = label.Position
	self.countdownSlide = ClientHudSlide.new(label, UDim2.new(label.Position.X.Scale, label.Position.X.Offset, COUNTDOWN_HIDDEN_POSITION_Y_SCALE, 0))
	self.countdownSlide:snap(false)
	self.countdownFadeTarget = label.TextTransparency
	self.isCountdownLowered = false
	gui.Enabled = true
end

-- the FINAL NIGHT card going down releases the helicopter's countdown
function ClientRescueManager:onCardClosed()
	local runState = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_STATE), Enums.RunState.DAY)
	if runState == Enums.RunState.RESCUE then
		self.isHelicopterCountdownReleased = true
	end
end

function ClientRescueManager:render()
	local now = workspace:GetServerTimeNow()
	self:renderCountdown(now)
	self:chimeBoardingIfNeeded()
	self:onRunStateChanged()
	local total = readNumber(ClientDataManager:getGameMetadata(Attributes.URANIUM_TOTAL), 0)
	local target = readNumber(ClientDataManager:getGameMetadata(Attributes.URANIUM_TARGET), 0)
	local uraniumText = string.format(URANIUM_FORMAT, total, target)
	local isReached = target > 0 and total >= target
	local uraniumLabel = self.uraniumLabel
	if uraniumLabel and uraniumText ~= self.shownUranium then
		self.shownUranium = uraniumText
		uraniumLabel.Text = uraniumText
		uraniumLabel.TextColor3 = if isReached then UiStyle.POSITIVE_COLOR else UiStyle.TEXT_COLOR
	end
	if isReached then
		self:showQuotaComplete()
	end
	local statusText = self:statusText(now)
	local statusLabel = self.statusLabel
	if statusLabel and statusText ~= self.shownStatus then
		self.shownStatus = statusText
		statusLabel.Text = statusText
	end
end

function ClientRescueManager:step()
	local now = workspace:GetServerTimeNow()
	if now - self.lastStepTime < STEP_INTERVAL_SEC then
		return
	end
	self.lastStepTime = now
	self:render()
end

function ClientRescueManager:onAnnouncement(payload: any)
	local isValid, errorMessage = Validate.isTableShape(payload, NOTIFY_RESCUE_ANNOUNCEMENT_SHAPE)
	if not isValid then
		warn("ClientRescueManager: malformed NotifyRescueAnnouncement:", errorMessage)
		return
	end
	if payload.isGood then
		ClientPlayerFeedbackManager:successLocal(payload.message, payload.displaySec)
	else
		ClientPlayerFeedbackManager:announceLocal(payload.message, payload.displaySec)
	end
end

function ClientRescueManager:init()
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_RESCUE_ANNOUNCEMENT,
		function(payload: any)
			self:onAnnouncement(payload)
		end
	)
	task.spawn(
		function()
			self:attachBillboard()
		end
	)
	task.spawn(
		function()
			self:findCountdownGui()
		end
	)
	task.spawn(
		function()
			self:findIncomingGui()
		end
	)
	ClientRunCycleManager:subscribeCardClosed(
		function()
			self:onCardClosed()
		end
	)
	RunService.Heartbeat:Connect(
		function()
			self:step()
		end
	)
end

function ClientRescueManager.new(): ClientRescueManager
	local self = setmetatable({}, ClientRescueManager) :: ClientRescueManager
	self.billboard = nil
	self.uraniumLabel = nil
	self.statusLabel = nil
	self.screenBackground = nil
	self.screenLabel = nil
	self.screenLight = nil
	self.isQuotaShown = false
	self.shownUranium = ""
	self.shownStatus = ""
	self.lastStepTime = 0
	self.countdownGui = nil
	self.countdownLabel = nil
	self.countdownSlide = nil
	self.isCountdownShown = false
	self.shownCountdown = ""
	self.countdownFadeTarget = 0
	self.countdownFade = nil
	self.isHelicopterCountdownReleased = false
	self.countdownUpperPosition = nil
	self.isCountdownLowered = false
	self.billboardFadeGeneration = 0
	self.isFinalNightSongPlaying = false
	self.isFinalNightSongFading = false
	self.landedFlashCount = 0
	self.wasCountdownRed = false
	self.shownAboardCount = 0
	self.lastRunState = Enums.RunState.DAY
	self.incomingGui = nil
	self.incomingLabel = nil
	self.incomingFirstText = nil
	self.colorCorrection = nil
	self.callGeneration = 0
	self.isCallSequenceRunning = false
	return self
end

return ClientRescueManager.new()
