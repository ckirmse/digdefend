--!strict

-- Dynamite on this client (GDD "Mining Tools"): while the dynamite is held,
-- a click, the gamepad trigger, or the touch action button (use) asks the
-- server to throw one (TryThrowDynamite). The stick
-- itself is a server part tagged Tags.DYNAMITE, so its sparks start when
-- the tag appears; the blast (NotifyDynamiteExploded) draws the smoke and
-- flash. The fuse hiss and the bang are 3D emitters the server attaches, so
-- there is nothing to play here. The rocks it clears arrive as the
-- usual NotifyRockBroken and are handled by ClientMiningManager.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientHeldToolManager = require(script.Parent.ClientHeldToolManager)

local ClientDynamiteManager = {}
ClientDynamiteManager.__index = ClientDynamiteManager

export type ClientDynamiteManager = typeof(setmetatable(
	{} :: {
		isActive: boolean,
	},
	ClientDynamiteManager
))

local NOTIFY_DYNAMITE_EXPLODED_SHAPE = {
	position = "vector3",
}

-- placeholder effects until Phase 9 art
local EFFECT_RANGE_STUDS = 120
local SMOKE_COUNT = 40
local SMOKE_LIFETIME_SEC = 2.5
local FLASH_SEC = 0.15
local SPARK_RATE = 30

local function isUseInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.ButtonR2
end

function ClientDynamiteManager:isNear(position: Vector3): boolean
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - position).Magnitude <= EFFECT_RANGE_STUDS
end

function ClientDynamiteManager:use()
	if not self.isActive or ClientOverlayManager:isOverlayActive() then
		return
	end
	ClientHeldToolManager:playSwing()
	ClientNetManager:fireServer(NetEventNames.TRY_THROW_DYNAMITE, {})
end

function ClientDynamiteManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if isGameProcessed or not isUseInput(input) then
		return
	end
	self:use()
end

-- a lit stick: sparks from its fuse end, and the hiss if it is close
function ClientDynamiteManager:onStickAdded(stick: Instance)
	if not stick:IsA("BasePart") then
		return
	end
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "FuseSparks"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 120, 40))
	sparks.Size = NumberSequence.new(0.15, 0)
	sparks.Lifetime = NumberRange.new(0.2, 0.5)
	sparks.Speed = NumberRange.new(2, 5)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = SPARK_RATE
	sparks.LightEmission = 1
	sparks.Parent = stick
end

function ClientDynamiteManager:onExploded(payload: any)
	local isValid = Validate.isTableShape(payload, NOTIFY_DYNAMITE_EXPLODED_SHAPE)
	if not isValid then
		warn("ClientDynamiteManager: malformed NotifyDynamiteExploded")
		return
	end
	local position = payload.position :: Vector3
	if not self:isNear(position) then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "DynamiteBlast"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 85, 80), Color3.fromRGB(40, 38, 36))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, 7),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(1.2, SMOKE_LIFETIME_SEC)
	smoke.Speed = NumberRange.new(6, 14)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rate = 0
	smoke.Parent = anchor
	smoke:Emit(SMOKE_COUNT)
	local flash = Instance.new("PointLight")
	flash.Brightness = 8
	flash.Range = 30
	flash.Color = Color3.fromRGB(255, 200, 120)
	flash.Parent = anchor
	task.delay(
		FLASH_SEC,
		function()
			flash:Destroy()
		end
	)
	task.delay(
		SMOKE_LIFETIME_SEC + 0.2,
		function()
			anchor:Destroy()
		end
	)
end

function ClientDynamiteManager:init()
	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			self:onInputBegan(input, isGameProcessed)
		end
	)
	for _, stick in CollectionService:GetTagged(Tags.DYNAMITE) do
		self:onStickAdded(stick)
	end
	CollectionService:GetInstanceAddedSignal(Tags.DYNAMITE):Connect(
		function(stick: Instance)
			self:onStickAdded(stick)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_DYNAMITE_EXPLODED,
		function(payload: any)
			self:onExploded(payload)
		end
	)
	local function applyEquipped(value: any)
		self.isActive = value == Enums.ToolKind.DYNAMITE
	end
	applyEquipped(ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL))
	ClientDataManager:subscribeCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL, applyEquipped)
end

function ClientDynamiteManager.new(): ClientDynamiteManager
	local self = setmetatable({}, ClientDynamiteManager) :: ClientDynamiteManager
	self.isActive = false
	return self
end

return ClientDynamiteManager.new()
