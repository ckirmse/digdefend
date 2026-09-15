--!strict

-- Draws ore lying on the ground: every part tagged Tags.ORE_PICKUP is a
-- server shadow carrying the resource and amount; this client gives it a
-- thin plate showing the ore's 2D icon (from Icons, both faces) that bobs
-- and spins like a coin. A resource with no icon yet falls back to a cube in
-- its rock colour. A dropped tool (a torch off a broken block) shows as a
-- small cube in the tool template's colour. One Heartbeat drives every
-- caster and runs only while there is something to animate.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
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
-- the icon plate: a coin-thin square showing the ore on both faces
local PLATE_SIZE = 1.8
local PLATE_THICKNESS = 0.05
local CUBE_SIZE = 0.8
local BOB_STUDS = 0.25
local BOB_PER_SEC = 2
local TURN_RAD_PER_SEC = 1.5
local FALLBACK_COLOR = Color3.fromRGB(200, 200, 200)

-- the rock whose template colour stands in for an ore with no icon
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

local function addFaceDecal(part: BasePart, face: Enum.NormalId, imageId: string)
	local decal = Instance.new("Decal")
	decal.Name = face.Name
	decal.Face = face
	decal.Texture = imageId
	decal.Parent = part
end

local function colorForTool(tool: number): (Color3, Enum.Material)
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local tools = if gameAssets then gameAssets:FindFirstChild(Constants.TOOL_TEMPLATES_FOLDER) else nil
	local key = Enums.getName(Enums.ToolKind, tool)
	local template = if tools and key then tools:FindFirstChild(key) else nil
	local handle = if template then template:FindFirstChild(Constants.TOOL_HANDLE_PART) else nil
	if handle and handle:IsA("BasePart") then
		return handle.Color, handle.Material
	end
	return FALLBACK_COLOR, Enum.Material.SmoothPlastic
end

local function makeToolCasterPart(tool: number): BasePart
	local part = Instance.new("Part")
	part.Name = "ToolPickup"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local color, material = colorForTool(tool)
	part.Size = Vector3.new(CUBE_SIZE, CUBE_SIZE, CUBE_SIZE)
	part.Color = color
	part.Material = material
	return part
end

-- an invisible plate carrying the icon on its front and back faces, or the
-- old coloured cube when the icon is still a placeholder
local function makeCasterPart(resource: number): BasePart
	local part = Instance.new("Part")
	part.Name = "OrePickup"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local imageId = Icons.RAW_RESOURCE[resource]
	if Icons.isPlaceholder(imageId) then
		local color, material = colorForResource(resource)
		part.Size = Vector3.new(CUBE_SIZE, CUBE_SIZE, CUBE_SIZE)
		part.Color = color
		part.Material = material
		return part
	end
	part.Size = Vector3.new(PLATE_SIZE, PLATE_SIZE, PLATE_THICKNESS)
	part.Transparency = 1
	addFaceDecal(part, Enum.NormalId.Front, imageId :: string)
	addFaceDecal(part, Enum.NormalId.Back, imageId :: string)
	return part
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
	local tool = shadow:GetAttribute(Attributes.PICKUP_TOOL)
	local part = if typeof(tool) == "number"
		then makeToolCasterPart(tool)
		else makeCasterPart(if typeof(resource) == "number" then resource else 0)
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
