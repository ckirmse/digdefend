--!strict

-- Ore on the ground (GDD "Collecting Ore"): what did not fit a breaker's
-- backpack lands by the block and any player walking over it with room
-- collects it, partial amounts included. Each pickup is Lua state plus one
-- small invisible anchored shadow part (Tags.ORE_PICKUP) carrying resource
-- and amount attributes; clients draw the visual. Pickups expire, and the
-- oldest go first past a cap. A torch knocked off a broken block is the same
-- thing with a tool attribute instead of a resource; anyone can take those.
local CollectionService = game:GetService("CollectionService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local BackpackData = require("@game/ServerScriptService/GameData/Mining/Backpack")
local GameController = require(script.Parent.Parent.Server.GameController)
local BackpackManager = require(script.Parent.BackpackManager)
local MineManager = require(script.Parent.MineManager)
local ToolManager = require(script.Parent.ToolManager)

local OrePickupManager = {}
OrePickupManager.__index = OrePickupManager

type Pickup = {
	part: BasePart,
	-- exactly one of these is set
	resource: number?,
	tool: number?,
	amount: number,
	createdAt: number,
}

export type OrePickupManager = typeof(setmetatable(
	{} :: {
		pickups: { Pickup },
		folder: Folder?,
		random: Random,
	},
	OrePickupManager
))

function OrePickupManager:getFolder(): Folder
	local folder = self.folder
	if folder then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = Constants.ORE_PICKUPS_FOLDER
	folder.Parent = workspace
	self.folder = folder
	return folder
end

function OrePickupManager:remove(index: number)
	local pickup = table.remove(self.pickups, index)
	if pickup then
		pickup.part:Destroy()
	end
end

function OrePickupManager:clearAll()
	for _, pickup in self.pickups do
		pickup.part:Destroy()
	end
	self.pickups = {}
end

-- how high above the floor the shadow sits; the client's bob and plate
-- swing around it
local REST_HEIGHT_STUDS = 1.2
-- how far down to look for camp ground outside the mine
local GROUND_RAY_STUDS = 200

-- a drop lands on the ground under it rather than hanging where the block
-- was: inside the mine the grid says where the next rock down is (the
-- server has no block parts), outside it the camp's real parts do
function OrePickupManager:settle(position: Vector3): Vector3
	local floorY = MineManager:findFloorBelow(position)
	if floorY == nil then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { self:getFolder() }
		local hit = workspace:Raycast(position, Vector3.new(0, -GROUND_RAY_STUDS, 0), params)
		if hit then
			floorY = hit.Position.Y
		end
	end
	if floorY == nil then
		return position
	end
	return Vector3.new(position.X, floorY + REST_HEIGHT_STUDS, position.Z)
end

function OrePickupManager:makePart(position: Vector3): BasePart
	local scatter = BackpackData.DROP_SCATTER_STUDS
	local part = Instance.new("Part")
	part.Name = "OrePickup"
	part.Size = Vector3.one
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	local scattered = position + Vector3.new(self.random:NextNumber(-scatter, scatter), 0, self.random:NextNumber(-scatter, scatter))
	part.CFrame = CFrame.new(self:settle(scattered))
	return part
end

function OrePickupManager:addPickup(pickup: Pickup)
	pickup.part:SetAttribute(Attributes.PICKUP_AMOUNT, pickup.amount)
	CollectionService:AddTag(pickup.part, Tags.ORE_PICKUP)
	pickup.part.Parent = self:getFolder()
	table.insert(self.pickups, pickup)
	while #self.pickups > BackpackData.MAX_PICKUPS do
		self:remove(1)
	end
end

function OrePickupManager:drop(position: Vector3, resource: number, amount: number)
	if amount <= 0 then
		return
	end
	local part = self:makePart(position)
	part:SetAttribute(Attributes.PICKUP_RESOURCE, resource)
	self:addPickup({
		part = part,
		resource = resource,
		tool = nil,
		amount = amount,
		createdAt = workspace:GetServerTimeNow(),
	})
end

-- a consumable on the ground (a torch off a broken block)
function OrePickupManager:dropTool(position: Vector3, tool: number, amount: number)
	if amount <= 0 then
		return
	end
	local part = self:makePart(position)
	part:SetAttribute(Attributes.PICKUP_TOOL, tool)
	self:addPickup({
		part = part,
		resource = nil,
		tool = tool,
		amount = amount,
		createdAt = workspace:GetServerTimeNow(),
	})
end

-- tool pickups need no backpack room, so they are taken by anyone passing
function OrePickupManager:pollTools(player: Player, rootPosition: Vector3, radius: number)
	local index = 1
	while index <= #self.pickups do
		local pickup = self.pickups[index]
		local tool = pickup.tool
		if not tool or (pickup.part.Position - rootPosition).Magnitude > radius then
			index += 1
			continue
		end
		ToolManager:addConsumable(player, tool, pickup.amount)
		self:remove(index)
	end
end

function OrePickupManager:poll()
	local now = workspace:GetServerTimeNow()
	-- expire first, oldest are at the front
	while #self.pickups > 0 and now - self.pickups[1].createdAt >= BackpackData.PICKUP_LIFETIME_SEC do
		self:remove(1)
	end
	if #self.pickups == 0 then
		return
	end
	local radius = BackpackData.PICKUP_RADIUS_STUDS
	for _, player in GameController:getReadyPlayers() do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not root or not root:IsA("BasePart") then
			continue
		end
		self:pollTools(player, root.Position, radius)
		if not BackpackManager:hasRoom(player) then
			continue
		end
		local index = 1
		while index <= #self.pickups do
			local pickup = self.pickups[index]
			local resource = pickup.resource
			if not resource or (pickup.part.Position - root.Position).Magnitude > radius then
				index += 1
				continue
			end
			local added = BackpackManager:add(player, resource, pickup.amount, pickup.part.Position)
			if added >= pickup.amount then
				self:remove(index)
			else
				if added > 0 then
					pickup.amount -= added
					pickup.part:SetAttribute(Attributes.PICKUP_AMOUNT, pickup.amount)
				end
				index += 1
			end
			if not BackpackManager:hasRoom(player) then
				break
			end
		end
	end
end

function OrePickupManager:init()
	task.spawn(
		function()
			while true do
				task.wait(BackpackData.PICKUP_POLL_SEC)
				self:poll()
			end
		end
	)
end

function OrePickupManager.new(): OrePickupManager
	local self = setmetatable({}, OrePickupManager) :: OrePickupManager
	self.pickups = {}
	self.folder = nil
	self.random = Random.new()
	return self
end

return OrePickupManager.new()
