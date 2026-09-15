--!strict

-- Torches (GDD "Mining Tools"): a TryPlaceTorch request names the surface
-- point and normal the player is looking at; the server checks reach,
-- spends one torch, and plants a shadow part (Tags.TORCH) there. Clients
-- draw the torch, flame, and light. A torch on a mine block is remembered by
-- that block's cell, and when the block is cleared (a swing or a blast) the
-- torch falls to the ground as a tool pickup anyone can walk over.
local CollectionService = game:GetService("CollectionService")

local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MineGenerator = require("@game/ReplicatedStorage/Shared/MineGenerator")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local PickAxeData = require("@game/ServerScriptService/GameData/Mining/PickAxe")
local TorchData = require("@game/ServerScriptService/GameData/Mining/Torch")
local GameController = require(script.Parent.Parent.Server.GameController)
local MineManager = require(script.Parent.MineManager)
local OrePickupManager = require(script.Parent.OrePickupManager)
local ToolManager = require(script.Parent.ToolManager)

local TorchManager = {}
TorchManager.__index = TorchManager

type Torch = {
	part: BasePart,
	-- the mine cell it is attached to, nil on any other surface
	cellIndex: number?,
}

export type TorchManager = typeof(setmetatable(
	{} :: {
		torches: { Torch },
		lastPlaceTimeByPlayer: { [Player]: number },
		folder: Folder?,
	},
	TorchManager
))

local TRY_PLACE_TORCH_SHAPE = {
	position = "vector3",
	normal = "vector3",
}

local FOLDER_NAME = "Torches"

function TorchManager:getFolder(): Folder
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

function TorchManager:removeAt(index: number)
	local torch = table.remove(self.torches, index)
	if torch then
		torch.part:Destroy()
	end
end

function TorchManager:clearAll()
	for _, torch in self.torches do
		torch.part:Destroy()
	end
	self.torches = {}
end

-- the mine cell just behind the surface point, if it holds rock
function TorchManager:findAttachedCell(position: Vector3, normal: Vector3): number?
	local space = MineManager:getSpace()
	local grid = MineManager:getGrid()
	if not space or not grid then
		return nil
	end
	local depth, height, width = MineSpace.worldToCell(space, position - normal * 0.5)
	local rock = MineManager:getRockAt(depth, height, width)
	if not rock or rock == MineGenerator.AIR then
		return nil
	end
	return MineGenerator.cellIndex(grid, depth, height, width)
end

function TorchManager:handlePlace(player: Player, position: Vector3, normal: Vector3)
	if ToolManager:getEquippedTool(player) ~= Enums.ToolKind.TORCH then
		return
	end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	if normal.Magnitude < 0.5 or not MiningRules.isWithinReach(root.Position, position, PickAxeData.REACH_STUDS, TorchData.REACH_TOLERANCE_STUDS) then
		return
	end
	local now = workspace:GetServerTimeNow()
	if not MiningRules.canHit(self.lastPlaceTimeByPlayer[player], now, TorchData.PLACE_COOLDOWN_SEC) then
		return
	end
	if not ToolManager:consume(player, Enums.ToolKind.TORCH) then
		return
	end
	self.lastPlaceTimeByPlayer[player] = now

	local unitNormal = normal.Unit
	local part = Instance.new("Part")
	part.Name = "Torch"
	part.Size = Vector3.one
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	-- the part faces out of the surface so the client can lean the torch
	part.CFrame = CFrame.lookAlong(position + unitNormal * TorchData.SURFACE_OFFSET_STUDS, unitNormal)
	CollectionService:AddTag(part, Tags.TORCH)
	part.Parent = self:getFolder()
	table.insert(self.torches, {
		part = part,
		cellIndex = self:findAttachedCell(position, unitNormal),
	})
	while #self.torches > TorchData.MAX_TORCHES do
		self:removeAt(1)
	end
end

-- a block went: every torch on it falls off as a pickup
function TorchManager:onCellCleared(depth: number, height: number, width: number)
	local grid = MineManager:getGrid()
	if not grid then
		return
	end
	local cellIndex = MineGenerator.cellIndex(grid, depth, height, width)
	local index = 1
	while index <= #self.torches do
		local torch = self.torches[index]
		if torch.cellIndex ~= cellIndex then
			index += 1
			continue
		end
		OrePickupManager:dropTool(torch.part.Position, Enums.ToolKind.TORCH, 1)
		self:removeAt(index)
	end
end

function TorchManager:getNetHandlers()
	return {
		[NetEventNames.TRY_PLACE_TORCH] = {
			shape = TRY_PLACE_TORCH_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:handlePlace(player, payload.position, payload.normal)
			end,
		},
	}
end

-- a new mine (a run or a regenerate) leaves no old torches hanging in the air
function TorchManager:onRunStarted()
	self:clearAll()
end

function TorchManager:onPlayerRemoved(player: Player)
	self.lastPlaceTimeByPlayer[player] = nil
end

function TorchManager:init()
	GameController:registerPlaceManager(self)
	MineManager:subscribeCellCleared(
		function(depth: number, height: number, width: number)
			self:onCellCleared(depth, height, width)
		end
	)
end

function TorchManager.new(): TorchManager
	local self = setmetatable({}, TorchManager) :: TorchManager
	self.torches = {}
	self.lastPlaceTimeByPlayer = {}
	self.folder = nil
	return self
end

return TorchManager.new()
