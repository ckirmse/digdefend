--!strict

-- Aim replication on this client (M24; AimManager on the server). Two jobs.
-- Sending: while a weapon is held, this player's look pitch goes to the
-- server a few times a second, only when it has changed (AimRules). Showing:
-- every other player holding a weapon is leaned by their public
-- AimPitchDegrees, split across the waist, the right shoulder, and the neck
-- so the weapon and the head both reach the full angle while the legs stay
-- planted. The joints' C0 is turned, not Transform, because animations
-- rewrite Transform every frame. This player's own body is never leaned: in
-- first person it is invisible and the viewmodel (ClientViewModelManager)
-- is what they see.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AimRules = require("@game/ReplicatedStorage/Shared/AimRules")
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)

local ClientAimManager = {}
ClientAimManager.__index = ClientAimManager

type Lean = {
	targetPitch: number,
	shownPitch: number,
	isAiming: boolean,
	-- each turned joint's authored C0, read before it first moves
	originalC0ByMotor: { [Motor6D]: CFrame },
}

export type ClientAimManager = typeof(setmetatable(
	{} :: {
		leanByUserId: { [number]: Lean },
		lastSentPitch: number?,
		lastSendTime: number,
	},
	ClientAimManager
))

local SEND_MIN_INTERVAL_SEC = 0.25
local SEND_MIN_CHANGE_DEGREES = 3
-- how fast a shown lean chases the last pitch heard, per second
local LEAN_FOLLOW_RATE = 10
local LEAN_DONE_DEGREES = 0.1
-- { part, joint, share of the pitch }: waist + shoulder = 1 for the weapon,
-- waist + neck = 1 for the head (R15)
local LEAN_JOINTS = {
	{ part = "UpperTorso", joint = "Waist", share = 0.5 },
	{ part = "RightUpperArm", joint = "RightShoulder", share = 0.5 },
	{ part = "Head", joint = "Neck", share = 0.5 },
}

function ClientAimManager:sendIfNeeded()
	local camera = workspace.CurrentCamera
	if not camera or ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL) ~= Enums.ToolKind.WEAPON then
		return
	end
	local pitch = AimRules.pitchFromLook(camera.CFrame.LookVector)
	local now = workspace:GetServerTimeNow()
	if not AimRules.shouldSend(self.lastSentPitch, pitch, self.lastSendTime, now, SEND_MIN_INTERVAL_SEC, SEND_MIN_CHANGE_DEGREES) then
		return
	end
	self.lastSentPitch = pitch
	self.lastSendTime = now
	ClientNetManager:fireServer(NetEventNames.TRY_SET_AIM, { pitchDegrees = pitch })
end

function ClientAimManager:applyLean(userId: number, lean: Lean)
	local player = Players:GetPlayerByUserId(userId)
	local character = if player then player.Character else nil
	if not character then
		return
	end
	-- a respawn brings new joints; the old ones are forgotten
	for motor in lean.originalC0ByMotor do
		if not motor:IsDescendantOf(character) then
			lean.originalC0ByMotor[motor] = nil
		end
	end
	for _, entry in LEAN_JOINTS do
		local part = character:FindFirstChild(entry.part)
		local motor = if part then part:FindFirstChild(entry.joint) else nil
		if not motor or not motor:IsA("Motor6D") then
			continue
		end
		local original = lean.originalC0ByMotor[motor]
		if not original then
			original = motor.C0
			lean.originalC0ByMotor[motor] = original
		end
		motor.C0 = original * CFrame.Angles(math.rad(lean.shownPitch * entry.share), 0, 0)
	end
end

function ClientAimManager:onRenderStep(deltaTime: number)
	for userId, lean in self.leanByUserId do
		local goal = if lean.isAiming then lean.targetPitch else 0
		if math.abs(goal - lean.shownPitch) < LEAN_DONE_DEGREES then
			if lean.shownPitch ~= goal then
				lean.shownPitch = goal
				self:applyLean(userId, lean)
			end
			continue
		end
		lean.shownPitch += (goal - lean.shownPitch) * math.min(1, LEAN_FOLLOW_RATE * deltaTime)
		self:applyLean(userId, lean)
	end
end

function ClientAimManager:onPublicData(userId: number, publicData: ClientDataManager.PublicData)
	if userId == Players.LocalPlayer.UserId then
		return
	end
	local lean = self.leanByUserId[userId]
	if not lean then
		lean = {
			targetPitch = 0,
			shownPitch = 0,
			isAiming = false,
			originalC0ByMotor = {},
		}
		self.leanByUserId[userId] = lean
	end
	lean.targetPitch = publicData.aimPitchDegrees
	lean.isAiming = publicData.equippedTool == Enums.ToolKind.WEAPON
end

function ClientAimManager:init()
	ClientDataManager:subscribeAllPlayers({
		onAdded = function(userId: number, publicData: ClientDataManager.PublicData)
			self:onPublicData(userId, publicData)
		end,
		onChanged = function(userId: number, publicData: ClientDataManager.PublicData)
			self:onPublicData(userId, publicData)
		end,
		onRemoved = function(userId: number)
			self.leanByUserId[userId] = nil
		end,
	})
	RunService.Heartbeat:Connect(
		function()
			self:sendIfNeeded()
		end
	)
	RunService.RenderStepped:Connect(
		function(deltaTime: number)
			self:onRenderStep(deltaTime)
		end
	)
end

function ClientAimManager.new(): ClientAimManager
	local self = setmetatable({}, ClientAimManager) :: ClientAimManager
	self.leanByUserId = {}
	self.lastSentPitch = nil
	self.lastSendTime = 0
	return self
end

return ClientAimManager.new()
