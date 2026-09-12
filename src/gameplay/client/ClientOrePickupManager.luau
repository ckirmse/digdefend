--!strict

-- Draws ore lying on the ground: every part tagged Tags.ORE_PICKUP is a
-- server shadow carrying the resource and amount; this client gives it a
-- small cube in the ore's colour (borrowed from the tier-1 rock template)
-- that bobs and turns. One Heartbeat drives every caster and runs only
-- while there is something to animate.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")

local ClientOrePickupManager = {}
ClientOrePickupManager.__index = ClientOrePickupManager

type Caster = {
	shadow: BasePart,
	part: BasePart,
	phase: number,
}

export type ClientOrePickupManager = typeof(setmetatable(
	{} :: {
		casters: { [BasePart]: Caster },
		folder: Folder?,
		heartbeat: RBXScriptConnection?,
		elapsed: number,
		random: Random,
	},
	ClientOrePickupManager
))

local CASTERS_FOLDER_NAME = "OrePickupCasters"
local CUBE_SIZE = 0.8
local BOB_STUDS = 0.25
local BOB_PER_SEC = 2
local TURN_RAD_PER_SEC = 1.5
local FALLBACK_COLOR = Color3.fromRGB(200, 200, 200)

-- the rock whose template colour stands in for each ore until ore art exists
local ROCK_FOR_RESOURCE: { [number]: number } = {
	[Enums.RawResource.IRON_ORE] = Enums.RockName.IRON_1,
	[Enums.RawResource.GOLD_ORE] = Enums.RockName.GOLD_1,
	[Enums.RawResource.CRYSTAL] = Enums.RockName.CRYSTAL_1,
	[Enums.RawResource.URANIUM_ORE] = Enums.RockName.URANIUM,
}

local function colorForResource(resource: number): (Color3, Enum.Material)
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local rocks = if gameAssets then gameAssets:FindFirstChild(Constants.ROCK_TEMPLATES_FOLDER) else nil
	local rockName = ROCK_FOR_RESOURCE[resource]
	local key = if rockName then Enums.getName(Enums.RockName, rockName) else nil
	local template = if rocks and key then rocks:FindFirstChild(key) else nil
	if template and template:IsA("BasePart") then
		return template.Color, template.Material
	end
	return FALLBACK_COLOR, Enum.Material.SmoothPlastic
end

function ClientOrePickupManager:getFolder(): Folder
	local folder = self.folder
	if folder then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = CASTERS_FOLDER_NAME
	folder.Parent = workspace
	self.folder = folder
	return folder
end

function ClientOrePickupManager:ensureHeartbeat()
	if self.heartbeat then
		return
	end
	self.heartbeat = RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self:step(deltaSec)
		end
	)
end

function ClientOrePickupManager:stopHeartbeatIfIdle()
	if next(self.casters) == nil and self.heartbeat then
		self.heartbeat:Disconnect()
		self.heartbeat = nil
	end
end

function ClientOrePickupManager:step(deltaSec: number)
	self.elapsed += deltaSec
	for _, caster in self.casters do
		local bob = math.sin((self.elapsed + caster.phase) * BOB_PER_SEC) * BOB_STUDS
		caster.part.CFrame = CFrame.new(caster.shadow.Position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, (self.elapsed + caster.phase) * TURN_RAD_PER_SEC, 0)
	end
end

function ClientOrePickupManager:addCaster(shadow: Instance)
	if not shadow:IsA("BasePart") or self.casters[shadow] then
		return
	end
	local resource = shadow:GetAttribute(Attributes.PICKUP_RESOURCE)
	local color, material = colorForResource(if typeof(resource) == "number" then resource else 0)
	local part = Instance.new("Part")
	part.Name = "OrePickup"
	part.Size = Vector3.new(CUBE_SIZE, CUBE_SIZE, CUBE_SIZE)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Color = color
	part.Material = material
	part.CFrame = shadow.CFrame
	part.Parent = self:getFolder()
	self.casters[shadow] = { shadow = shadow, part = part, phase = self.random:NextNumber(0, math.pi * 2) }
	self:ensureHeartbeat()
end

function ClientOrePickupManager:removeCaster(shadow: Instance)
	local caster = self.casters[shadow :: BasePart]
	if not caster then
		return
	end
	caster.part:Destroy()
	self.casters[shadow :: BasePart] = nil
	self:stopHeartbeatIfIdle()
end

function ClientOrePickupManager:init()
	for _, shadow in CollectionService:GetTagged(Tags.ORE_PICKUP) do
		self:addCaster(shadow)
	end
	CollectionService:GetInstanceAddedSignal(Tags.ORE_PICKUP):Connect(
		function(shadow: Instance)
			self:addCaster(shadow)
		end
	)
	CollectionService:GetInstanceRemovedSignal(Tags.ORE_PICKUP):Connect(
		function(shadow: Instance)
			self:removeCaster(shadow)
		end
	)
end

function ClientOrePickupManager.new(): ClientOrePickupManager
	local self = setmetatable({}, ClientOrePickupManager) :: ClientOrePickupManager
	self.casters = {}
	self.folder = nil
	self.heartbeat = nil
	self.elapsed = 0
	self.random = Random.new()
	return self
end

return ClientOrePickupManager.new()
