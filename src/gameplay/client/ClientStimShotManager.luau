--!strict

-- The Stim Shot as the client sees it (2026-10-19). While the GADGET tool
-- is equipped and the class's gadget is the Stim Shot, the use input
-- (click, tap, or the right trigger) asks the server to use it
-- (TryUseStimShot), refused here with the fail sound and a line when the
-- server has already marked it used (StimShotIsUsed). When the server
-- says it landed (NotifyStimShotUsed) the StimVignette ScreenGui glows
-- for as long as the speed boost lasts: the white edges come in strong
-- over a second, settle to a softer glow over three, hold there, and
-- fade off as the boost ends (the designer's curve, 2026-10-19).
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientStimShotManager = {}
ClientStimShotManager.__index = ClientStimShotManager

export type ClientStimShotManager = typeof(setmetatable(
	{} :: {
		vignette: ScreenGui?,
		-- the edge frames the glow drives
		edges: { GuiObject },
		flashToken: number,
	},
	ClientStimShotManager
))

local NOTIFY_STIM_SHOT_USED_SHAPE = {
	speedSec = "number",
}

local FEEDBACK_USED = "Stim Shot used. Back at dawn."
local FEEDBACK_DISPLAY_SEC = 2
-- the glow's curve (designer, 2026-10-19): in to the strong level over
-- the first second, down to the held level over the next three, held
-- until the boost ends, then out over the last second
local GLOW_IN_TRANSPARENCY = 0.25
local GLOW_IN_SEC = 1
local GLOW_HOLD_TRANSPARENCY = 0.6
local GLOW_SETTLE_SEC = 3
local GLOW_OUT_SEC = 1

local function isUseInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.ButtonR2
end

function ClientStimShotManager:isActive(): boolean
	local equipped = ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL)
	local gadgetKind = ClientDataManager:getCurrentPlayerAttribute(Attributes.GADGET_KIND)
	return equipped == Enums.ToolKind.GADGET and gadgetKind == Enums.GadgetKind.STIM_SHOT
end

function ClientStimShotManager:use()
	if ClientDataManager:getCurrentPlayerAttribute(Attributes.STIM_SHOT_IS_USED) == true then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(FEEDBACK_USED, FEEDBACK_DISPLAY_SEC)
		return
	end
	ClientNetManager:fireServer(NetEventNames.TRY_USE_STIM_SHOT, {})
end

function ClientStimShotManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if isGameProcessed or ClientOverlayManager:isOverlayActive() or not isUseInput(input) or not self:isActive() then
		return
	end
	self:use()
end

-- every edge eased to one transparency over a time
function ClientStimShotManager:fadeEdges(toTransparency: number, seconds: number)
	for _, edge in self.edges do
		TweenService:Create(edge, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = toTransparency }):Play()
	end
end

-- the white glow for the boost's length, on the designer's curve; a
-- second shot inside it starts over
function ClientStimShotManager:pulse(durationSec: number)
	local vignette = self.vignette
	if not vignette then
		return
	end
	self.flashToken += 1
	local token = self.flashToken
	vignette.Enabled = true
	for _, edge in self.edges do
		edge.BackgroundTransparency = 1
	end
	task.spawn(
		function()
			local endTime = workspace:GetServerTimeNow() + durationSec
			self:fadeEdges(GLOW_IN_TRANSPARENCY, GLOW_IN_SEC)
			task.wait(GLOW_IN_SEC)
			if self.flashToken ~= token then
				return
			end
			self:fadeEdges(GLOW_HOLD_TRANSPARENCY, GLOW_SETTLE_SEC)
			local holdSec = endTime - GLOW_OUT_SEC - workspace:GetServerTimeNow()
			task.wait(math.max(GLOW_SETTLE_SEC, holdSec))
			if self.flashToken ~= token then
				return
			end
			self:fadeEdges(1, GLOW_OUT_SEC)
			task.wait(GLOW_OUT_SEC)
			if self.flashToken == token then
				vignette.Enabled = false
			end
		end
	)
end

function ClientStimShotManager:onUsed(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_STIM_SHOT_USED_SHAPE) then
		warn("ClientStimShotManager: malformed NotifyStimShotUsed")
		return
	end
	ClientSoundManager:playSfx(SoundNames.Sfx.STIM_SHOT_USE)
	self:pulse(payload.speedSec)
end

function ClientStimShotManager:findVignette()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.STIM_VIGNETTE_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientStimShotManager: no StimVignette ScreenGui; run scripts/studio/build_stim_vignette_gui.luau")
		return
	end
	gui.Enabled = false
	self.vignette = gui
	for _, child in gui:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(self.edges, child)
		end
	end
end

function ClientStimShotManager:init()
	self:findVignette()
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_STIM_SHOT_USED,
		function(payload: any)
			self:onUsed(payload)
		end
	)
	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			self:onInputBegan(input, isGameProcessed)
		end
	)
end

function ClientStimShotManager.new(): ClientStimShotManager
	local self = setmetatable({}, ClientStimShotManager) :: ClientStimShotManager
	self.vignette = nil
	self.edges = {}
	self.flashToken = 0
	return self
end

return ClientStimShotManager.new()
