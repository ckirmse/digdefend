--!strict

-- Ore on the ground (GDD "Collecting Ore"): what did not fit a breaker's
-- backpack lands by the block and any player walking over it with room
-- collects it, partial amounts included. Each pickup is Lua state plus one
-- small invisible anchored shadow part (Tags.ORE_PICKUP) carrying resource
-- and amount attributes; clients draw the visual. Pickups expire, and the
-- oldest go first past a cap.
local CollectionService = game:GetService("CollectionService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local BackpackData = require("@game/ServerScriptService/GameData/Mining/Backpack")
local GameController = require(script.Parent.Parent.Server.GameController)
local BackpackManager = require(script.Parent.BackpackManager)

local OrePickupManager = {}
OrePickupManager.__index = OrePickupManager

type Pickup = {
	part: BasePart,
	resource: number,
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

function OrePickupManager:drop(position: Vector3, resource: number, amount: number)
	if amount <= 0 then
		return
	end
	local scatter = BackpackData.DROP_SCATTER_STUDS
	local part = Instance.new("Part")
	part.Name = "OrePickup"
	part.Size = Vector3.one
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.CFrame = CFrame.new(position + Vector3.new(self.random:NextNumber(-scatter, scatter), 0, self.random:NextNumber(-scatter, scatter)))
	part:SetAttribute(Attributes.PICKUP_RESOURCE, resource)
	part:SetAttribute(Attributes.PICKUP_AMOUNT, amount)
	CollectionService:AddTag(part, Tags.ORE_PICKUP)
	part.Parent = self:getFolder()
	table.insert(self.pickups, {
		part = part,
		resource = resource,
		amount = amount,
		createdAt = workspace:GetServerTimeNow(),
	})
	while #self.pickups > BackpackData.MAX_PICKUPS do
		self:remove(1)
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
		if not BackpackManager:hasRoom(player) then
			continue
		end
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not root or not root:IsA("BasePart") then
			continue
		end
		local index = 1
		while index <= #self.pickups do
			local pickup = self.pickups[index]
			if (pickup.part.Position - root.Position).Magnitude > radius then
				index += 1
				continue
			end
			local added = BackpackManager:add(player, pickup.resource, pickup.amount)
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
