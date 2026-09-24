--!strict

-- The rescue as the crew sees it (GDD "Helicopter Pad"), M31: the radio's
-- billboard on Camp.Radio.GuiPart (the RescueRadio template under
-- GameAssets/Gui) showing the uranium count against the target and what
-- the radio is doing (waiting for the target, ready to call, the
-- helicopter's countdown, boarding), the radio's own screen and lamp
-- turning green with QUOTA COMPLETE once the target is met, all from
-- GameMetadata the server publishes; and the rescue announcements in the
-- announcement box. The prompts themselves are the server's.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)

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
	},
	ClientRescueManager
))

local NOTIFY_RESCUE_ANNOUNCEMENT_SHAPE = {
	message = "string",
	displaySec = "positiveNumber",
}

local STEP_INTERVAL_SEC = 0.25
-- the uranium icon sits beside this on the template (UI rule: icons, not words)
local URANIUM_FORMAT = "%d / %d"
local STATUS_WAITING = "Complete your Uranium quota to call in a rescue helicopter"
local STATUS_READY = "Quota Complete. Call in a rescue helicopter"
local STATUS_FLYING = "Rescue helicopter incoming. Hold the line until it arrives."
local STATUS_BOARDING_FORMAT = "Boarding  %d / %d aboard, leaving in %d s"
local STATUS_BOARDING_WAITING_FORMAT = "Boarding  %d / %d aboard"
local STATUS_WON = "Rescued"
local STATUS_LOST = "No rescue is coming"
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
		if aboard <= 0 then
			return string.format(STATUS_BOARDING_WAITING_FORMAT, aboard, crew)
		end
		return string.format(STATUS_BOARDING_FORMAT, aboard, crew, secondsLeft)
	end
	local total = readNumber(ClientDataManager:getGameMetadata(Attributes.URANIUM_TOTAL), 0)
	local target = readNumber(ClientDataManager:getGameMetadata(Attributes.URANIUM_TARGET), 0)
	return if target > 0 and total >= target then STATUS_READY else STATUS_WAITING
end

function ClientRescueManager:render()
	local now = workspace:GetServerTimeNow()
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
	ClientPlayerFeedbackManager:announceLocal(payload.message, payload.displaySec)
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
	return self
end

return ClientRescueManager.new()
