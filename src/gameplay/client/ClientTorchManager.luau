--!strict

-- Torches on this client (GDD "Mining Tools"): while a torch is held, a tap
-- or click finds the surface at the centre of the screen within reach and
-- asks the server to plant one there (TryPlaceTorch with the hit point and
-- normal). Every placed torch is a server shadow part tagged Tags.TORCH;
-- this client gives each one a stick, a flame, and a PointLight, and the
-- placement sound when it appears nearby.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientHeldToolManager = require(script.Parent.ClientHeldToolManager)

local ClientTorchManager = {}
ClientTorchManager.__index = ClientTorchManager

export type ClientTorchManager = typeof(setmetatable(
	{} :: {
		isActive: boolean,
		reachStuds: number,
		visualByShadow: { [BasePart]: Model },
		folder: Folder?,
	},
	ClientTorchManager
))

local DEFAULT_REACH_STUDS = 12
local SOUND_RANGE_STUDS = 60
local FOLDER_NAME = "TorchVisuals"
-- placeholder look until Phase 9 art
local STICK_SIZE = Vector3.new(0.25, 1.1, 0.25)
local STICK_COLOR = Color3.fromRGB(110, 75, 40)
local FLAME_SIZE = 0.45
local FLAME_COLOR = Color3.fromRGB(255, 150, 40)
local LIGHT_RANGE_STUDS = 24
local LIGHT_BRIGHTNESS = 1.5
-- a wall torch leans this far out from the surface
local WALL_LEAN_RADIANS = math.rad(25)

local function isUseInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.ButtonR2
end

function ClientTorchManager:getFolder(): Folder
	local folder = self.folder
	if folder then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace
	self.folder = folder
	return folder
end

function ClientTorchManager:isNear(position: Vector3): boolean
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - position).Magnitude <= SOUND_RANGE_STUDS
end

-- the surface under the reticle: any solid part except the player and the
-- client-only visual folders
function ClientTorchManager:aim(): RaycastResult?
	local camera = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	if not camera then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded: { Instance } = {}
	if character then
		table.insert(excluded, character)
	end
	if self.folder then
		table.insert(excluded, self.folder)
	end
	params.FilterDescendantsInstances = excluded
	return workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * self.reachStuds, params)
end

function ClientTorchManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if not self.isActive or isGameProcessed or not isUseInput(input) or ClientOverlayManager:isOverlayActive() then
		return
	end
	local result = self:aim()
	if not result then
		return
	end
	ClientHeldToolManager:playSwing()
	ClientNetManager:fireServer(
		NetEventNames.TRY_PLACE_TORCH,
		{
			position = result.Position,
			normal = result.Normal,
		}
	)
end

-- the shadow looks out along the surface normal: on a floor the torch
-- stands up, on a wall it leans out
function ClientTorchManager:torchCFrame(shadow: BasePart): CFrame
	local normal = shadow.CFrame.LookVector
	local position = shadow.Position
	if math.abs(normal.Y) > 0.5 then
		return CFrame.new(position)
	end
	local lean = CFrame.fromAxisAngle(normal:Cross(Vector3.yAxis), -WALL_LEAN_RADIANS)
	return CFrame.new(position) * lean
end

function ClientTorchManager:addVisual(shadow: Instance)
	if not shadow:IsA("BasePart") or self.visualByShadow[shadow] then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Torch"
	local stick = Instance.new("Part")
	stick.Name = Constants.TOOL_HANDLE_PART
	stick.Size = STICK_SIZE
	stick.Color = STICK_COLOR
	stick.Material = Enum.Material.Wood
	stick.Anchored = true
	stick.CanCollide = false
	stick.CanQuery = false
	stick.CanTouch = false
	stick.Parent = model
	local flame = Instance.new("Part")
	flame.Name = "Flame"
	flame.Shape = Enum.PartType.Ball
	flame.Size = Vector3.new(FLAME_SIZE, FLAME_SIZE, FLAME_SIZE)
	flame.Color = FLAME_COLOR
	flame.Material = Enum.Material.Neon
	flame.Anchored = true
	flame.CanCollide = false
	flame.CanQuery = false
	flame.CanTouch = false
	flame.Parent = model
	local light = Instance.new("PointLight")
	light.Range = LIGHT_RANGE_STUDS
	light.Brightness = LIGHT_BRIGHTNESS
	light.Color = FLAME_COLOR
	-- shadowless: point light shadows are the costly kind and a crew can leave dozens of torches
	light.Shadows = false
	light.Parent = flame
	model.PrimaryPart = stick
	local base = self:torchCFrame(shadow)
	stick.CFrame = base * CFrame.new(0, STICK_SIZE.Y / 2, 0)
	flame.CFrame = base * CFrame.new(0, STICK_SIZE.Y + FLAME_SIZE / 2, 0)
	model.Parent = self:getFolder()
	self.visualByShadow[shadow] = model
	if self:isNear(shadow.Position) then
		ClientSoundManager:playSfx(SoundNames.Sfx.TORCH_PLACE)
	end
end

function ClientTorchManager:removeVisual(shadow: Instance)
	local model = self.visualByShadow[shadow :: BasePart]
	if model then
		model:Destroy()
		self.visualByShadow[shadow :: BasePart] = nil
	end
end

function ClientTorchManager:readTuning()
	local reach = ClientDataManager:getGameMetadata(Attributes.PICK_AXE_REACH_STUDS)
	self.reachStuds = if typeof(reach) == "number" then reach else DEFAULT_REACH_STUDS
end

function ClientTorchManager:init()
	self:readTuning()
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.PICK_AXE_REACH_STUDS,
		function()
			self:readTuning()
		end
	)
	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			self:onInputBegan(input, isGameProcessed)
		end
	)
	for _, shadow in CollectionService:GetTagged(Tags.TORCH) do
		self:addVisual(shadow)
	end
	CollectionService:GetInstanceAddedSignal(Tags.TORCH):Connect(
		function(shadow: Instance)
			self:addVisual(shadow)
		end
	)
	CollectionService:GetInstanceRemovedSignal(Tags.TORCH):Connect(
		function(shadow: Instance)
			self:removeVisual(shadow)
		end
	)
	local function applyEquipped(value: any)
		self.isActive = value == Enums.ToolKind.TORCH
	end
	applyEquipped(ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL))
	ClientDataManager:subscribeCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL, applyEquipped)
end

function ClientTorchManager.new(): ClientTorchManager
	local self = setmetatable({}, ClientTorchManager) :: ClientTorchManager
	self.isActive = false
	self.reachStuds = DEFAULT_REACH_STUDS
	self.visualByShadow = {}
	self.folder = nil
	return self
end

return ClientTorchManager.new()
