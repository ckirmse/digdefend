--!strict

-- Dynamite (GDD "Mining Tools"; the Demolitionist's gadget since
-- 2026-10-20, GDD "Classes"): the class whose kit names it holds the
-- DYNAMITE tool slot with one stick, and the next is in hand RESPAWN_SEC
-- after a throw, day or night (DynamiteReadyTime on CurrentPlayer for
-- the slot's draining sheet); every other class has no slot (the dev
-- give-consumables command excepted). A TryThrowDynamite
-- request spends one stick and releases a server-owned physics part ahead
-- of the player. After the fuse it clears every breakable rock within the
-- blast radius through MineManager, tells every client which cells broke
-- (the same NotifyRockBroken a swing sends) and where the blast was,
-- drops all the ore on the ground rather than into anyone's backpack
-- (decided 2026-09-15), and hurts every monster within the blast with the
-- thrower credited (2026-10-20). The stick is one real part, but the mine's blocks exist only
-- on clients, so the thrower's client simulates it (it can land on what it
-- sees) and the server reads where it ended up, refusing a blast further
-- from the thrower than a throw can reach. The fuse hiss rides on the stick
-- and the bang plays where it went off, both as 3D emitters every player
-- hears in place; clients draw the sparks and smoke from its tag and the message.
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local BackpackRules = require("@game/ReplicatedStorage/Shared/BackpackRules")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local DynamiteRules = require("@game/ReplicatedStorage/Shared/DynamiteRules")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PostRules = require("@game/ReplicatedStorage/Shared/PostRules")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local PartyScalingData = require("@game/ServerScriptService/GameData/Control/PartyScaling")
local DynamiteData = require("@game/ServerScriptService/GameData/Mining/Dynamite")
local RockDefinitionsData = require("@game/ServerScriptService/GameData/Rocks/RockDefinitions")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local utils = require("@game/ReplicatedStorage/Shared/utils")
local CharacterManager = require(script.Parent.Parent.Server.CharacterManager)
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local SpatialSoundManager = require(script.Parent.Parent.Server.SpatialSoundManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local DamageableManager = require(script.Parent.DamageableManager)
local MineManager = require(script.Parent.MineManager)
local OrePickupManager = require(script.Parent.OrePickupManager)
local ToolManager = require(script.Parent.ToolManager)

local DynamiteManager = {}
DynamiteManager.__index = DynamiteManager

export type DynamiteManager = typeof(setmetatable(
	{} :: {
		lastThrowTimeByPlayer: { [Player]: number },
		-- when a player's next stick is in hand; nil when it is. The token
		-- lets a run restart or a class change cancel a wait in flight
		readyTimeByPlayer: { [Player]: number },
		respawnTokenByPlayer: { [Player]: number },
		-- each player's character group-ing, dropped when they leave
		characterConnectionsByPlayer: { [Player]: { RBXScriptConnection } },
		folder: Folder?,
	},
	DynamiteManager
))

local TRY_THROW_DYNAMITE_SHAPE = {}

-- the thrown stick is the physics body only, invisible; each client
-- dresses it with the TntStick mesh (2026-10-20)
local STICK_SIZE = Vector3.new(0.5, 1.2, 0.5)
-- how often the server samples the stick's position while it flies
local TRACK_INTERVAL_SEC = 0.1
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

function DynamiteManager:hasDynamiteGadget(player: Player): boolean
	return CharacterManager:getGadgetKind(player) == Enums.GadgetKind.DYNAMITE
end

function DynamiteManager:replicate(player: Player)
	if not player.Parent then
		return
	end
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.DYNAMITE_READY_TIME, self.readyTimeByPlayer[player] or 0)
end

-- the wait for the next stick is over, or cancelled
function DynamiteManager:clearRespawn(player: Player)
	self.respawnTokenByPlayer[player] = (self.respawnTokenByPlayer[player] or 0) + 1
	self.readyTimeByPlayer[player] = nil
	self:replicate(player)
end

-- the next stick is in hand RESPAWN_SEC from now, if the player is still
-- the Demolitionist in the same run when it comes round
function DynamiteManager:startRespawn(player: Player)
	local token = (self.respawnTokenByPlayer[player] or 0) + 1
	self.respawnTokenByPlayer[player] = token
	self.readyTimeByPlayer[player] = workspace:GetServerTimeNow() + DynamiteData.RESPAWN_SEC
	self:replicate(player)
	task.delay(
		DynamiteData.RESPAWN_SEC,
		function()
			if self.respawnTokenByPlayer[player] ~= token or not player.Parent then
				return
			end
			self.readyTimeByPlayer[player] = nil
			self:replicate(player)
			if self:hasDynamiteGadget(player) then
				ToolManager:setConsumableCount(player, Enums.ToolKind.DYNAMITE, 1)
			end
		end
	)
end

-- the slot follows the class (at Ready, at a run's start, and on a
-- dev-tool class change): the Demolitionist holds one stick, every other
-- class none; a wait in flight is dropped either way
function DynamiteManager:applyGadget(player: Player)
	local isDemolitionist = self:hasDynamiteGadget(player)
	self:clearRespawn(player)
	-- the class's slot stays in the bar at x0, greyed, while the next stick comes
	ToolManager:setKeptWhenEmpty(player, Enums.ToolKind.DYNAMITE, isDemolitionist)
	ToolManager:setConsumableCount(player, Enums.ToolKind.DYNAMITE, if isDemolitionist then 1 else 0)
end

-- every blast, with its centre and the radius it hurt monsters in
function DynamiteManager:subscribeBlast(handler: (position: Vector3, radiusStuds: number) -> ())
	table.insert(self.blastHandlers, handler)
end

function DynamiteManager:explode(stick: BasePart, position: Vector3, thrower: Player)
	stick:Destroy()
	SpatialSoundManager:playAt(position, SoundNames.Sfx.DYNAMITE_EXPLODE)
	NetManager:notifyAllClients(NetEventNames.NOTIFY_DYNAMITE_EXPLODED, {
		position = position,
	})
	-- the monsters within the blast, wherever it went off
	for _, hitId in PostRules.findSplashHits(position, DynamiteData.MONSTER_BLAST_RADIUS_STUDS, DamageableManager:getHitBoxes()) do
		DamageableManager:damage(hitId, DynamiteData.MONSTER_DAMAGE, thrower)
	end
	-- whoever else cares where a stick went off (the Drag's stagger, M68)
	for _, handler in self.blastHandlers do
		handler(position, DynamiteData.MONSTER_BLAST_RADIUS_STUDS)
	end
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
			breakerUserId = thrower.UserId,
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
	-- the Demolitionist's next stick starts its way the moment this one leaves
	if self:hasDynamiteGadget(player) then
		self:startRespawn(player)
	end

	local look = root.CFrame.LookVector
	-- the throw rides on the thrower's own motion, so a running throw
	-- still lands ahead (2026-10-20)
	local rootVelocity = root.AssemblyLinearVelocity
	local launchVelocity = look * DynamiteData.THROW_SPEED_STUDS_PER_SEC + Vector3.new(rootVelocity.X, DynamiteData.THROW_UPWARD_SPEED_STUDS_PER_SEC, rootVelocity.Z)
	local stick = Instance.new("Part")
	stick.Name = "Dynamite"
	stick.Shape = Enum.PartType.Cylinder
	stick.Size = STICK_SIZE
	stick.Transparency = 1
	stick.CanQuery = false
	stick.CanTouch = false
	stick.CollisionGroup = Constants.COLLISION_GROUP_DYNAMITE
	stick.CFrame = CFrame.new(root.Position + look * DynamiteData.THROW_OFFSET_STUDS + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	stick.AssemblyLinearVelocity = launchVelocity
	stick:SetAttribute(Attributes.DYNAMITE_EXPLODE_TIME, now + DynamiteData.FUSE_SEC)
	-- the thrower's client launches it again once it owns it (see Attributes)
	stick:SetAttribute(Attributes.DYNAMITE_THROWER_USER_ID, player.UserId)
	stick:SetAttribute(Attributes.DYNAMITE_LAUNCH_VELOCITY, launchVelocity)
	CollectionService:AddTag(stick, Tags.DYNAMITE)
	stick.Parent = self:getFolder()
	-- the thrower simulates it: only their client has the mine's blocks to land on
	stick:SetNetworkOwner(player)
	SpatialSoundManager:attach(stick, SoundNames.Sfx.DYNAMITE_FUSE, true)

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
			self:explode(stick, position, player)
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

-- a character's parts join the Character group as they arrive (limbs
-- and accessories stream in after CharacterAdded), so a thrown stick
-- never catches on its thrower
function DynamiteManager:groupCharacter(player: Player, character: Model)
	utils.addTreeToCollisionGroup(character, Constants.COLLISION_GROUP_CHARACTER)
	local connections = self.characterConnectionsByPlayer[player]
	if not connections then
		return
	end
	table.insert(
		connections,
		character.DescendantAdded:Connect(
			function(descendant: Instance)
				if descendant:IsA("BasePart") then
					descendant.CollisionGroup = Constants.COLLISION_GROUP_CHARACTER
				end
			end
		)
	)
end

function DynamiteManager:watchCharacter(player: Player)
	local connections = {}
	self.characterConnectionsByPlayer[player] = connections
	table.insert(
		connections,
		player.CharacterAdded:Connect(
			function(character: Model)
				self:groupCharacter(player, character)
			end
		)
	)
	if player.Character then
		self:groupCharacter(player, player.Character)
	end
end

-- a new run: the Demolitionist's stick is in hand, any wait dropped
function DynamiteManager:onRunStarted()
	for _, player in GameController:getReadyPlayers() do
		self:applyGadget(player)
	end
end

function DynamiteManager:onPlayerReady(player: Player)
	self:watchCharacter(player)
	self:replicate(player)
	self:applyGadget(player)
end

function DynamiteManager:onPlayerRemoved(player: Player)
	self.lastThrowTimeByPlayer[player] = nil
	self.readyTimeByPlayer[player] = nil
	self.respawnTokenByPlayer[player] = nil
	local connections = self.characterConnectionsByPlayer[player]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
		self.characterConnectionsByPlayer[player] = nil
	end
end

function DynamiteManager:init()
	-- a thrown stick passes through every character (2026-10-20)
	PhysicsService:RegisterCollisionGroup(Constants.COLLISION_GROUP_CHARACTER)
	PhysicsService:RegisterCollisionGroup(Constants.COLLISION_GROUP_DYNAMITE)
	PhysicsService:CollisionGroupSetCollidable(Constants.COLLISION_GROUP_CHARACTER, Constants.COLLISION_GROUP_DYNAMITE, false)
	-- the slot drains its sheet over the same wait the server keeps
	SplendidReplicationManager:setGameMetadata(Attributes.DYNAMITE_RESPAWN_SEC, DynamiteData.RESPAWN_SEC)
	GameController:registerPlaceManager(self)
	CharacterManager:subscribeClassChanged(
		function(player: Player, _classKind: number)
			if GameController:isPlayerReady(player) then
				self:applyGadget(player)
			end
		end
	)
end

function DynamiteManager.new(): DynamiteManager
	local self = setmetatable({}, DynamiteManager) :: DynamiteManager
	self.blastHandlers = {}
	self.lastThrowTimeByPlayer = {}
	self.readyTimeByPlayer = {}
	self.respawnTokenByPlayer = {}
	self.characterConnectionsByPlayer = {}
	self.folder = nil
	return self
end

return DynamiteManager.new()
