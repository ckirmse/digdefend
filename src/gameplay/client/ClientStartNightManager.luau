--!strict

-- The Start Night button on this client (designer, 2026-10-07): the
-- authored StartNightButton under the jet pack bar in the GameplayHud
-- shows in the last window of a day (the window, the votes, and how many
-- are needed are GameMetadata from StartNightManager), reads the count once
-- someone has pressed it, and sends TryStartNight on a press. Once this
-- player has voted the button stays up, greyed, until the night falls.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientTicker = require(script.Parent.Parent.Client.ClientTicker)

local ClientStartNightManager = {}
ClientStartNightManager.__index = ClientStartNightManager

export type ClientStartNightManager = typeof(setmetatable(
	{} :: {
		button: TextButton?,
		hasVoted: boolean,
		shownText: string,
	},
	ClientStartNightManager
))

local STEP_INTERVAL_SEC = 0.25
-- the votes always show, on their own line under the label (designer,
-- 2026-10-08; before, the count appeared only once someone had pressed)
local LABEL_FORMAT = "Start Night\n%d / %d"
local DEFAULT_WINDOW_SEC = 30

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

function ClientStartNightManager:isWindowOpen(): boolean
	local runState = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_STATE), Enums.RunState.DAY)
	if runState ~= Enums.RunState.DAY then
		return false
	end
	local endTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PHASE_END_TIME), 0)
	local windowSec = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_START_NIGHT_WINDOW_SEC), DEFAULT_WINDOW_SEC)
	local now = workspace:GetServerTimeNow()
	local pauseStartTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PAUSE_START_TIME), 0)
	if pauseStartTime > 0 then
		now = pauseStartTime
	end
	return endTime > 0 and endTime - now <= windowSec
end

function ClientStartNightManager:render()
	local button = self.button
	if not button then
		return
	end
	local isOpen = self:isWindowOpen()
	if not isOpen then
		self.hasVoted = false
	end
	if button.Visible ~= isOpen then
		button.Visible = isOpen
	end
	if not isOpen then
		return
	end
	local votes = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_START_NIGHT_VOTES), 0)
	local needed = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_START_NIGHT_NEEDED), 0)
	local text = UiStyle.formatTitle(string.format(LABEL_FORMAT, votes, needed))
	if text ~= self.shownText then
		self.shownText = text
		button.Text = text
	end
	button.AutoButtonColor = not self.hasVoted
	button.TextColor3 = if self.hasVoted then UiStyle.TEXT_MUTED_COLOR else UiStyle.TEXT_COLOR
end

function ClientStartNightManager:press()
	if self.hasVoted or not self:isWindowOpen() then
		return
	end
	self.hasVoted = true
	ClientNetManager:fireServer(NetEventNames.TRY_START_NIGHT, {})
	self:render()
end

function ClientStartNightManager:findButton()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.GAMEPLAY_HUD_GUI_NAME, 10)
	local button = if gui then gui:FindFirstChild(Constants.HUD_START_NIGHT_BUTTON, true) else nil
	if not button or not button:IsA("TextButton") then
		warn("ClientStartNightManager: GameplayHud is missing StartNightButton; run scripts/studio/build_gameplay_hud_gui.luau")
		return
	end
	button.Visible = false
	self.button = button
	button.Activated:Connect(
		function()
			self:press()
		end
	)
end

function ClientStartNightManager:init()
	self:findButton()
	ClientTicker.every(
		STEP_INTERVAL_SEC,
		function()
			self:render()
		end
	)
end

function ClientStartNightManager.new(): ClientStartNightManager
	local self = setmetatable({}, ClientStartNightManager) :: ClientStartNightManager
	self.button = nil
	self.hasVoted = false
	self.shownText = ""
	return self
end

return ClientStartNightManager.new()
