--!strict

-- The first-person viewmodel (M24): what makes a held weapon feel like an
-- FPS. The Roblox Tool in the avatar's hand only plays the stock hold pose
-- and knows nothing about the camera, so looking up left the gun pointing
-- at the horizon. Instead, while a weapon is shown and the camera is in
-- first person, a copy of its GameAssets/Tools template is placed relative
-- to the camera every frame, right after the camera moves, so it is locked
-- to the reticle; the real Tool is hidden on this client only (everyone
-- else still sees it, leaned by ClientAimManager). On top of the locked pose:
-- sway (the gun lags a turning camera, read from the camera's own rotation
-- so mouse, touch, and gamepad feel the same), a walk bob, a recoil kick,
-- and a lowered pose for reloading. Tracers start at the copy's Muzzle
-- attachment. Nothing here is weapon specific: any template with a Handle
-- can be shown, which is what mounted post weapons build on at M25.
-- The numbers are feel constants, not gameplay tuning.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")

local ClientViewModelManager = {}
ClientViewModelManager.__index = ClientViewModelManager

export type ClientViewModelManager = typeof(setmetatable(
	{} :: {
		model: Model?,
		templateName: string?,
		muzzle: Attachment?,
		isLowered: boolean,
		loweredShare: number,
		recoil: number,
		swayYaw: number,
		swayPitch: number,
		bobTime: number,
		lastCameraCFrame: CFrame?,
		isBound: boolean,
		warnedTemplates: { [string]: boolean },
	},
	ClientViewModelManager
))

local RENDER_STEP_NAME = "ViewModel"
-- where the Handle sits from the eye: right, down, forward; turned a touch
-- inward and up so the barrel points at the reticle, not parallel to it
local BASE_OFFSET = CFrame.new(0.75, -0.7, -1.2) * CFrame.Angles(math.rad(1.5), math.rad(2), 0)
-- the camera counts as first person when it is this close to its focus
local FIRST_PERSON_MAX_ZOOM_STUDS = 1.5
-- sway: degrees of lag per degree the camera turned this frame, its cap, and
-- how fast it settles back
local SWAY_PER_DEGREE = 0.9
local SWAY_MAX_DEGREES = 6
local SWAY_SETTLE_RATE = 9
local BOB_RATE = 9
local BOB_SIDE_STUDS = 0.03
local BOB_UP_STUDS = 0.02
local BOB_MIN_MOVE = 0.1
-- one shot: the gun jumps back and up, then settles
local RECOIL_PER_KICK = 1
local RECOIL_MAX = 2
local RECOIL_SETTLE_RATE = 14
local RECOIL_BACK_STUDS = 0.12
local RECOIL_UP_DEGREES = 3.5
local LOWER_RATE = 10
local LOWER_DOWN_STUDS = 0.5
local LOWER_PITCH_DEGREES = -40
local LOWER_ROLL_DEGREES = 15

function ClientViewModelManager:findTemplate(templateName: string): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local tools = if gameAssets then gameAssets:FindFirstChild(Constants.TOOL_TEMPLATES_FOLDER) else nil
	local template = if tools then tools:FindFirstChild(templateName) else nil
	if template and template:IsA("Model") and template:FindFirstChild(Constants.TOOL_HANDLE_PART) then
		return template
	end
	if not self.warnedTemplates[templateName] then
		self.warnedTemplates[templateName] = true
		warn(`ClientViewModelManager: no Model with a {Constants.TOOL_HANDLE_PART} named {templateName} under GameAssets.{Constants.TOOL_TEMPLATES_FOLDER}; run scripts/studio/build_tool_templates.luau`)
	end
	return nil
end

function ClientViewModelManager:getIsFirstPerson(): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.Focus.Position - camera.CFrame.Position).Magnitude <= FIRST_PERSON_MAX_ZOOM_STUDS
end

-- the shown copy's Muzzle attachment: where tracers start, with the flash
-- and smoke under it. Nil when nothing is shown (third person, no
-- template), and the caller falls back to the held Tool
function ClientViewModelManager:getMuzzle(): Attachment?
	local model = self.model
	local muzzle = self.muzzle
	return if model and muzzle and model.Parent then muzzle else nil
end

function ClientViewModelManager:kick()
	self.recoil = math.min(RECOIL_MAX, self.recoil + RECOIL_PER_KICK)
end

-- the reload pose: the gun drops out of the way until raised again
function ClientViewModelManager:setLowered(isLowered: boolean)
	self.isLowered = isLowered
end

function ClientViewModelManager:destroyModel()
	if self.model then
		self.model:Destroy()
	end
	self.model = nil
	self.muzzle = nil
end

function ClientViewModelManager:buildModel(templateName: string): Model?
	local template = self:findTemplate(templateName)
	if not template then
		return nil
	end
	local model: Model = template:Clone()
	model.Name = RENDER_STEP_NAME
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			-- every part is anchored and the whole copy is pivoted each frame,
			-- so physics never touches it
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		elseif descendant:IsA("WeldConstraint") or descendant:IsA("JointInstance") then
			descendant:Destroy()
		end
	end
	local handle = model:FindFirstChild(Constants.TOOL_HANDLE_PART)
	if handle and handle:IsA("BasePart") then
		model.PrimaryPart = handle
	end
	local muzzle = model:FindFirstChild(Constants.WEAPON_MUZZLE_ATTACHMENT, true)
	self.muzzle = if muzzle and muzzle:IsA("Attachment") then muzzle else nil
	return model
end

-- the real Tool stays in the hand for everyone else; on this client it would
-- double the gun, and Roblox keeps held tools visible in first person
function ClientViewModelManager:setHeldToolHidden(isHidden: boolean)
	local character = Players.LocalPlayer.Character
	local tool = if character then character:FindFirstChildOfClass("Tool") else nil
	if not tool then
		return
	end
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = if isHidden then 1 else 0
		end
	end
end

function ClientViewModelManager:getIsMoving(): boolean
	local character = Players.LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return humanoid ~= nil and humanoid.MoveDirection.Magnitude > BOB_MIN_MOVE and humanoid.FloorMaterial ~= Enum.Material.Air
end

function ClientViewModelManager:onRenderStep(deltaTime: number)
	local camera = workspace.CurrentCamera
	local model = self.model
	if not camera or not model then
		return
	end
	local isFirstPerson = self:getIsFirstPerson()
	model.Parent = if isFirstPerson then camera else nil
	self:setHeldToolHidden(isFirstPerson)
	local cameraCFrame = camera.CFrame
	local lastCameraCFrame = self.lastCameraCFrame or cameraCFrame
	self.lastCameraCFrame = cameraCFrame
	if not isFirstPerson then
		return
	end

	-- how far the camera turned this frame pushes the gun the other way
	local turnedPitch, turnedYaw = lastCameraCFrame:ToObjectSpace(cameraCFrame):ToOrientation()
	local settle = math.min(1, SWAY_SETTLE_RATE * deltaTime)
	self.swayYaw = math.clamp(self.swayYaw - math.deg(turnedYaw) * SWAY_PER_DEGREE, -SWAY_MAX_DEGREES, SWAY_MAX_DEGREES)
	self.swayPitch = math.clamp(self.swayPitch - math.deg(turnedPitch) * SWAY_PER_DEGREE, -SWAY_MAX_DEGREES, SWAY_MAX_DEGREES)
	self.swayYaw -= self.swayYaw * settle
	self.swayPitch -= self.swayPitch * settle

	self.recoil -= self.recoil * math.min(1, RECOIL_SETTLE_RATE * deltaTime)
	local lowerGoal = if self.isLowered then 1 else 0
	self.loweredShare += (lowerGoal - self.loweredShare) * math.min(1, LOWER_RATE * deltaTime)

	local bob = CFrame.identity
	if self:getIsMoving() then
		self.bobTime += deltaTime * BOB_RATE
		bob = CFrame.new(math.sin(self.bobTime) * BOB_SIDE_STUDS, math.sin(self.bobTime * 2) * BOB_UP_STUDS, 0)
	end

	local sway = CFrame.Angles(math.rad(self.swayPitch), math.rad(self.swayYaw), 0)
	local recoil = CFrame.new(0, 0, self.recoil * RECOIL_BACK_STUDS) * CFrame.Angles(math.rad(self.recoil * RECOIL_UP_DEGREES), 0, 0)
	local lowered = CFrame.new(0, -LOWER_DOWN_STUDS * self.loweredShare, 0) * CFrame.Angles(math.rad(LOWER_PITCH_DEGREES * self.loweredShare), 0, math.rad(LOWER_ROLL_DEGREES * self.loweredShare))
	model:PivotTo(cameraCFrame * bob * BASE_OFFSET * lowered * sway * recoil)
end

function ClientViewModelManager:bindIfNeeded()
	if self.isBound then
		return
	end
	self.isBound = true
	-- after the camera has moved this frame, or the gun trails it by a frame
	RunService:BindToRenderStep(
		RENDER_STEP_NAME,
		Enum.RenderPriority.Camera.Value + 1,
		function(deltaTime: number)
			self:onRenderStep(deltaTime)
		end
	)
end

function ClientViewModelManager:show(templateName: string)
	if self.templateName == templateName and self.model then
		return
	end
	self:destroyModel()
	self.templateName = templateName
	self.model = self:buildModel(templateName)
	self.recoil = 0
	self.swayYaw = 0
	self.swayPitch = 0
	self.loweredShare = 1
	self.lastCameraCFrame = nil
	if self.model then
		self:bindIfNeeded()
	end
end

function ClientViewModelManager:hide()
	if self.isBound then
		self.isBound = false
		RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	end
	self:destroyModel()
	self.templateName = nil
	self:setHeldToolHidden(false)
end

function ClientViewModelManager.new(): ClientViewModelManager
	local self = setmetatable({}, ClientViewModelManager) :: ClientViewModelManager
	self.model = nil
	self.templateName = nil
	self.muzzle = nil
	self.isLowered = false
	self.loweredShare = 0
	self.recoil = 0
	self.swayYaw = 0
	self.swayPitch = 0
	self.bobTime = 0
	self.lastCameraCFrame = nil
	self.isBound = false
	self.warnedTemplates = {}
	return self
end

return ClientViewModelManager.new()
