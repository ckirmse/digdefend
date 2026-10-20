--!strict

-- A placed gadget's ghost (pulled out of ClientAutoTurretManager on
-- 2026-10-20 so the Remote Charge places by the same rules): a translucent
-- copy of the gadget's model hanging a fixed distance ahead of the player
-- on the ground, green where the server would accept it and red where it
-- would not, judged by the same AutoTurretRules the server decides by
-- (ground under the spot, not too steep, inside the camp's monster areas,
-- at ground level rather than on a roof). The owner reads isValid,
-- position, and yawDegrees after each update and sends them with its
-- place request. The distance and the slope limit are the turret's
-- GameMetadata numbers, which the server applies to every placed gadget.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local AutoTurretRules = require("@game/ReplicatedStorage/Shared/AutoTurretRules")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)

local ClientGadgetGhost = {}
ClientGadgetGhost.__index = ClientGadgetGhost

export type ClientGadgetGhost = typeof(setmetatable(
	{} :: {
		template: Model,
		bodiesFolder: Folder,
		-- how far the model's own forward sits from -Z, the base's forward
		modelYawOffsetDegrees: number,
		placeDistanceStuds: number,
		minGroundNormalY: number,
		model: Model?,
		parts: { BasePart },
		isValid: boolean,
		position: Vector3?,
		yawDegrees: number,
	},
	ClientGadgetGhost
))

local GHOST_TRANSPARENCY = 0.5
-- the ghost's ground ray: from above the spot to well below, so a slope
-- or a step still finds a floor
local GHOST_RAY_ABOVE_STUDS = 10
local GHOST_RAY_BELOW_STUDS = 30
-- the roof test the client can make without the server's path grid: a
-- surface with another floor this far beneath it is a roof, not the ground
-- (a ray from just under a surface never meets that surface again)
local ROOF_PROBE_START_BELOW_STUDS = 0.5
local ROOF_PROBE_LENGTH_STUDS = 60
local DEFAULT_PLACE_DISTANCE_STUDS = 15
local DEFAULT_MIN_GROUND_NORMAL_Y = 0.8

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

local function hasTag(instance: Instance, tag: string): boolean
	return CollectionService:HasTag(instance, tag)
end

-- a clone the client owns outright: anchored, touching and hitting nothing
function ClientGadgetGhost.buildModel(template: Model, name: string): Model
	local model = template:Clone()
	model.Name = name
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	return model
end

-- stands a model on a base pose: its bounding box's bottom on the ground
-- point, turned the base's way plus the model's own offset
function ClientGadgetGhost.poseModel(model: Model, base: CFrame, modelYawOffsetDegrees: number)
	local turned = base * CFrame.Angles(0, math.rad(modelYawOffsetDegrees), 0)
	model:PivotTo(turned)
	local boxCFrame, boxSize = model:GetBoundingBox()
	local lift = base.Position.Y - (boxCFrame.Position.Y - boxSize.Y / 2)
	model:PivotTo(turned * CFrame.new(0, lift, 0))
end

-- inside one of the camp's monster areas (WaveAreas, CampArea), flat
function ClientGadgetGhost.isInsideMonsterArea(position: Vector3): boolean
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	if not camp then
		return false
	end
	for _, folderName in { Constants.CAMP_WAVE_AREAS_FOLDER, Constants.CAMP_CAMP_AREA_FOLDER } do
		local folder = camp:FindFirstChild(folderName)
		if not folder then
			continue
		end
		for _, area in folder:GetChildren() do
			if not area:IsA("BasePart") then
				continue
			end
			local localPosition = area.CFrame:PointToObjectSpace(Vector3.new(position.X, area.Position.Y, position.Z))
			if math.abs(localPosition.X) <= area.Size.X / 2 and math.abs(localPosition.Z) <= area.Size.Z / 2 then
				return true
			end
		end
	end
	return false
end

function ClientGadgetGhost:setVisible(isVisible: boolean)
	if not isVisible then
		if self.model then
			self.model:Destroy()
			self.model = nil
			self.parts = {}
		end
		self.position = nil
		self.isValid = false
		return
	end
	if self.model then
		return
	end
	local model = ClientGadgetGhost.buildModel(self.template, self.template.Name .. "Ghost")
	local parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = GHOST_TRANSPARENCY
			descendant.Material = Enum.Material.SmoothPlastic
			descendant.CastShadow = false
			table.insert(parts, descendant)
		elseif descendant:IsA("Light") then
			descendant.Enabled = false
		end
	end
	model.Parent = self.bodiesFolder
	self.model = model
	self.parts = parts
end

-- one frame: the ghost ahead of the player, judged and coloured
function ClientGadgetGhost:update()
	local model = self.model
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not model or not root or not root:IsA("BasePart") then
		self.isValid = false
		self.position = nil
		return
	end
	local origin = AutoTurretRules.ghostOrigin(root.CFrame, self.placeDistanceStuds)
	local excluded: { Instance } = { model, self.bodiesFolder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = excluded
	parameters.RespectCanCollide = true
	local hit = workspace:Raycast(origin + Vector3.new(0, GHOST_RAY_ABOVE_STUDS, 0), Vector3.new(0, -(GHOST_RAY_ABOVE_STUDS + GHOST_RAY_BELOW_STUDS), 0), parameters)
	local isGround = hit ~= nil and AutoTurretRules.findBlockingTag(hit.Instance, hasTag) == nil
	local groundPosition = if hit then hit.Position else origin
	local normalY = if hit then hit.Normal.Y else 0
	local isAtGroundLevel = true
	if hit then
		local beneath = workspace:Raycast(hit.Position - Vector3.new(0, ROOF_PROBE_START_BELOW_STUDS, 0), Vector3.new(0, -ROOF_PROBE_LENGTH_STUDS, 0), parameters)
		isAtGroundLevel = beneath == nil
	end
	local problem = AutoTurretRules.placementProblem(isGround, normalY, self.minGroundNormalY, ClientGadgetGhost.isInsideMonsterArea(groundPosition), isAtGroundLevel)
	self.isValid = problem == nil
	self.position = groundPosition
	self.yawDegrees = AutoTurretRules.yawDegreesOf(root.CFrame)
	ClientGadgetGhost.poseModel(model, CFrame.new(groundPosition) * CFrame.Angles(0, math.rad(self.yawDegrees), 0), self.modelYawOffsetDegrees)
	local color = if self.isValid then UiStyle.POSITIVE_COLOR else UiStyle.NEGATIVE_COLOR
	for _, part in self.parts do
		part.Color = color
	end
end

function ClientGadgetGhost:destroy()
	self:setVisible(false)
end

function ClientGadgetGhost.new(template: Model, bodiesFolder: Folder, modelYawOffsetDegrees: number): ClientGadgetGhost
	local self = setmetatable({}, ClientGadgetGhost) :: ClientGadgetGhost
	self.template = template
	self.bodiesFolder = bodiesFolder
	self.modelYawOffsetDegrees = modelYawOffsetDegrees
	self.placeDistanceStuds = readNumber(ClientDataManager:getGameMetadata(Attributes.AUTO_TURRET_PLACE_DISTANCE_STUDS), DEFAULT_PLACE_DISTANCE_STUDS)
	self.minGroundNormalY = readNumber(ClientDataManager:getGameMetadata(Attributes.AUTO_TURRET_MIN_GROUND_NORMAL_Y), DEFAULT_MIN_GROUND_NORMAL_Y)
	self.model = nil
	self.parts = {}
	self.isValid = false
	self.position = nil
	self.yawDegrees = 0
	return self
end

return ClientGadgetGhost
