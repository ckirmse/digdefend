--!strict

-- Dynamite (GDD "Mining Tools"): a TryThrowDynamite request spends one stick
-- and releases a server-owned physics part ahead of the player. After the
-- fuse it clears every breakable rock within the blast radius through
-- MineManager, tells every client which cells broke (the same
-- NotifyRockBroken a swing sends) and where the blast was, and drops all
-- the ore on the ground rather than into anyone's backpack (decided
-- 2026-09-15). The stick is one real part, but the mine's blocks exist only
-- on clients, so the thrower's client simulates it (it can land on what it
-- sees) and the server reads where it ended up, refusing a blast further
-- from the thrower than a throw can reach. The fuse hiss rides on the stick
-- and the bang plays where it went off, both as 3D emitters every player
-- hears in place; clients draw the sparks and smoke from its tag and the message.
local CollectionService = game:GetService("CollectionService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local BackpackRules = require("@game/ReplicatedStorage/Shared/BackpackRules")
local DynamiteRules = require("@game/ReplicatedStorage/Shared/DynamiteRules")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local PartyScalingData = require("@game/ServerScriptService/GameData/Control/PartyScaling")
local DynamiteData = require("@game/ServerScriptService/GameData/Mining/Dynamite")
local RockDefinitionsData = require("@game/ServerScriptService/GameData/Rocks/RockDefinitions")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local SpatialSoundManager = require(script.Parent.Parent.Server.SpatialSoundManager)
local MineManager = require(script.Parent.MineManager)
local OrePickupManager = require(script.Parent.OrePickupManager)
local ToolManager = require(script.Parent.ToolManager)

local DynamiteManager = {}
DynamiteManager.__index = DynamiteManager

export type DynamiteManager = typeof(setmetatable(
	{} :: {
		lastThrowTimeByPlayer: { [Player]: number },
		folder: Folder?,
	},
	DynamiteManager
))

local TRY_THROW_DYNAMITE_SHAPE = {}

local STICK_SIZE = Vector3.new(0.5, 1.2, 0.5)
-- how often the server samples the stick's position while it flies
local TRACK_INTERVAL_SEC = 0.1
local STICK_COLOR = Color3.fromRGB(190, 40, 40)
local FOLDER_NAME = "Dynamite"

function DynamiteManager:getFolder(): Folder
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

-- the ore of every resource rock in the blast lands on the ground; party
-- scaling applies as it would to a swing
function DynamiteManager:dropOre(rock: number, blockCenter: Vector3)
	local definition = RockDefinitionsData.ROCKS[rock]
	if not definition or definition.kind ~= Enums.RockKind.RESOURCE or not definition.resource or not definition.yield then
		return
	end
	local playerCount = #GameController:getReadyPlayers()
	local amount = BackpackRules.yieldForBreak(definition.yield, definition.resource, playerCount, PartyScalingData.ORE_YIELD_MULTIPLIER_BY_PLAYER_COUNT)
	OrePickupManager:drop(blockCenter, definition.resource, amount)
end

function DynamiteManager:explode(stick: BasePart, position: Vector3, throwerUserId: number)
	stick:Destroy()
	SpatialSoundManager:playAt(position, SoundNames.Sfx.DYNAMITE_EXPLODE)
	NetManager:notifyAllClients(NetEventNames.NOTIFY_DYNAMITE_EXPLODED, {
		position = position,
	})
	local space = MineManager:getSpace()
	local grid = MineManager:getGrid()
	if not space or not grid then
		return
	end
	local centreDepth, centreHeight, centreWidth = MineSpace.worldToCell(space, position)
	local cells = DynamiteRules.cellsInBlast(centreDepth, centreHeight, centreWidth, DynamiteData.BLAST_RADIUS_BLOCKS, grid.depth, grid.height, grid.width)
	for _, cell in cells do
		local rock = MineManager:getRockAt(cell.depth, cell.height, cell.width)
		if not rock or not MineManager:clearCell(cell.depth, cell.height, cell.width) then
			continue
		end
		NetManager:notifyAllClients(NetEventNames.NOTIFY_ROCK_BROKEN, {
			depth = cell.depth,
			height = cell.height,
			width = cell.width,
			rock = rock,
			breakerUserId = throwerUserId,
		})
		self:dropOre(rock, MineSpace.cellToWorld(space, cell.depth, cell.height, cell.width))
	end
end

function DynamiteManager:handleThrow(player: Player)
	if ToolManager:getEquippedTool(player) ~= Enums.ToolKind.DYNAMITE then
		return
	end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	local now = workspace:GetServerTimeNow()
	if not MiningRules.canHit(self.lastThrowTimeByPlayer[player], now, DynamiteData.THROW_COOLDOWN_SEC) then
		return
	end
	if not ToolManager:consume(player, Enums.ToolKind.DYNAMITE) then
		return
	end
	self.lastThrowTimeByPlayer[player] = now

	local look = root.CFrame.LookVector
	local stick = Instance.new("Part")
	stick.Name = "Dynamite"
	stick.Shape = Enum.PartType.Cylinder
	stick.Size = STICK_SIZE
	stick.Color = STICK_COLOR
	stick.Material = Enum.Material.SmoothPlastic
	stick.CanQuery = false
	stick.CanTouch = false
	stick.CFrame = CFrame.new(root.Position + look * DynamiteData.THROW_OFFSET_STUDS + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	stick.AssemblyLinearVelocity = look * DynamiteData.THROW_SPEED_STUDS_PER_SEC + Vector3.new(0, DynamiteData.THROW_UPWARD_SPEED_STUDS_PER_SEC, 0)
	stick:SetAttribute(Attributes.DYNAMITE_EXPLODE_TIME, now + DynamiteData.FUSE_SEC)
	CollectionService:AddTag(stick, Tags.DYNAMITE)
	stick.Parent = self:getFolder()
	-- the thrower simulates it: only their client has the mine's blocks to land on
	stick:SetNetworkOwner(player)
	SpatialSoundManager:attach(stick, SoundNames.Sfx.DYNAMITE_FUSE, true)

	local throwerUserId = player.UserId
	local throwOrigin = root.Position
	local lastPosition = stick.Position
	task.spawn(
		function()
			-- the last sampled position stands in if the stick falls out of the world
			while stick.Parent do
				lastPosition = stick.Position
				task.wait(TRACK_INTERVAL_SEC)
			end
		end
	)
	task.delay(
		DynamiteData.FUSE_SEC,
		function()
			local position = if stick.Parent then stick.Position else lastPosition
			if (position - throwOrigin).Magnitude > DynamiteData.MAX_BLAST_DISTANCE_STUDS then
				warn(`DynamiteManager: {player.Name}'s dynamite ended up too far from the throw; no blast`)
				stick:Destroy()
				return
			end
			self:explode(stick, position, throwerUserId)
		end
	)
	task.delay(
		DynamiteData.MAX_LIFETIME_SEC,
		function()
			if stick.Parent then
				stick:Destroy()
			end
		end
	)
end

function DynamiteManager:getNetHandlers()
	return {
		[NetEventNames.TRY_THROW_DYNAMITE] = {
			shape = TRY_THROW_DYNAMITE_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:handleThrow(player)
			end,
		},
	}
end

function DynamiteManager:onPlayerRemoved(player: Player)
	self.lastThrowTimeByPlayer[player] = nil
end

function DynamiteManager:init()
	GameController:registerPlaceManager(self)
end

function DynamiteManager.new(): DynamiteManager
	local self = setmetatable({}, DynamiteManager) :: DynamiteManager
	self.lastThrowTimeByPlayer = {}
	self.folder = nil
	return self
end

return DynamiteManager.new()
