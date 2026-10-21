--!strict

-- The Flare, Air Defense's gadget (GDD "Classes", 2026-10-20). The GADGET
-- slot is the flare while the class says so (granted here; the Auto
-- Turret manager, which runs first, takes the slot from any class
-- without a turret, so this only ever gives). With it in hand the use
-- input throws it (TryThrowFlare) the dynamite's way: a server-owned
-- physics stick ahead of the player, launched again by the thrower's own
-- client once it owns it, passing through characters. LIGHT_DELAY_SEC
-- later the flare lights where it lies as one invisible anchored part
-- (the shadow system: Tags.FLARE, the owner and the end time) that every
-- client dresses with the flare's model and fire, and MonsterManager
-- lists it among every target type with the level's draw radius, so
-- every monster within it, air or ground, goes for it and stands over it
-- (a hit on it hurts nothing) until it burns out. The throw starts the
-- cooldown (GadgetReadyTime on CurrentPlayer, shared with the Remote
-- Charge's slot logic). Numbers: GameData/Gadgets/Flare.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local GadgetRules = require("@game/ReplicatedStorage/Shared/GadgetRules")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local FlareData = require("@game/ServerScriptService/GameData/Gadgets/Flare")
local CharacterManager = require(script.Parent.Parent.Server.CharacterManager)
local GameController = require(script.Parent.Parent.Server.GameController)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local GadgetUpgradeManager = require(script.Parent.GadgetUpgradeManager)
local ReviveManager = require(script.Parent.ReviveManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local ToolManager = require(script.Parent.ToolManager)

local FlareManager = {}
FlareManager.__index = FlareManager

export type Flare = {
	id: string,
	owner: Player,
	position: Vector3,
	shadow: BasePart,
	endTime: number,
	drawRadiusStuds: number,
}

export type LevelStats = {
	BURN_SEC: number,
	DRAW_RADIUS_STUDS: number,
}

export type FlareManager = typeof(setmetatable(
	{} :: {
		flaresById: { [string]: Flare },
		-- when a player's next flare is in hand; nil when it is
		readyTimeByPlayer: { [Player]: number },
		nextId: number,
		shadowFolder: Folder?,
		stickFolder: Folder?,
	},
	FlareManager
))

local ID_FORMAT = "Flare%d"
local TRY_THROW_FLARE_SHAPE = {}
local FEEDBACK_COOLING = "Next flare in %d s"
local FEEDBACK_NOT_YET = "Not until the day starts."
-- how often the server samples a thrown stick's position while it flies
local TRACK_INTERVAL_SEC = 0.1

function FlareManager:getShadowFolder(): Folder
	local folder = self.shadowFolder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = Constants.FLARE_SHADOW_FOLDER
	folder.Parent = workspace
	self.shadowFolder = folder
	return folder
end

function FlareManager:getStickFolder(): Folder
	local folder = self.stickFolder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = Constants.FLARE_STICK_FOLDER
	folder.Parent = workspace
	self.stickFolder = folder
	return folder
end

function FlareManager:hasFlareGadget(player: Player): boolean
	return CharacterManager:getGadgetKind(player) == Enums.GadgetKind.FLARE
end

function FlareManager:hasFlare(id: string): boolean
	return self.flaresById[id] ~= nil
end

-- every lit flare, for the monsters' target lists
function FlareManager:getFlares(): { Flare }
	local flares = {}
	for _, flare in self.flaresById do
		table.insert(flares, flare)
	end
	return flares
end

function FlareManager:statsFor(player: Player): LevelStats
	return GadgetRules.statsFor(FlareData.STATS_BY_LEVEL, GadgetUpgradeManager:getLevel(player))
end

-- seconds until the next flare is in hand; 0 when it is
function FlareManager:getCooldownLeft(player: Player): number
	local readyTime = self.readyTimeByPlayer[player]
	if not readyTime then
		return 0
	end
	return math.max(0, readyTime - workspace:GetServerTimeNow())
end

function FlareManager:replicate(player: Player)
	if not player.Parent then
		return
	end
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.GADGET_READY_TIME, self.readyTimeByPlayer[player] or 0)
end

function FlareManager:setReadyTime(player: Player, readyTime: number?)
	self.readyTimeByPlayer[player] = readyTime
	self:replicate(player)
end

function FlareManager:removeFlare(flare: Flare)
	if self.flaresById[flare.id] ~= flare then
		return
	end
	self.flaresById[flare.id] = nil
	flare.shadow:Destroy()
end

-- the flare lights where the stick came to rest
function FlareManager:light(player: Player, position: Vector3, stats: LevelStats)
	local id = string.format(ID_FORMAT, self.nextId)
	self.nextId += 1
	local now = workspace:GetServerTimeNow()
	local size: Vector3 = FlareData.BODY_SIZE
	local shadow = Instance.new("Part")
	shadow.Name = id
	shadow.Size = size
	shadow.Transparency = 1
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.CanTouch = false
	shadow.CFrame = CFrame.new(position + Vector3.new(0, size.Y / 2, 0))
	shadow:SetAttribute(Attributes.FLARE_OWNER_USER_ID, player.UserId)
	shadow:SetAttribute(Attributes.FLARE_END_TIME, now + stats.BURN_SEC)
	CollectionService:AddTag(shadow, Tags.FLARE)
	shadow.Parent = self:getShadowFolder()
	self.flaresById[id] = {
		id = id,
		owner = player,
		position = position,
		shadow = shadow,
		endTime = now + stats.BURN_SEC,
		drawRadiusStuds = stats.DRAW_RADIUS_STUDS,
	}
	print(`[FlareManager] {player.Name} lit {id} for {stats.BURN_SEC} s, drawing {stats.DRAW_RADIUS_STUDS} studs`)
end

function FlareManager:throw(player: Player)
	if not GameController:isPlayerReady(player) or ReviveManager:isDead(player) then
		return
	end
	if not self:hasFlareGadget(player) or ToolManager:getEquippedTool(player) ~= Enums.ToolKind.GADGET then
		return
	end
	local cooldownLeft = self:getCooldownLeft(player)
	if cooldownLeft > 0 then
		PlayerFeedbackManager:give(player, string.format(FEEDBACK_COOLING, math.ceil(cooldownLeft)))
		return
	end
	-- not in the arrival: there is nothing to draw yet
	if not RunCycleManager:isRunOn() then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_YET)
		return
	end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	local now = workspace:GetServerTimeNow()
	local stats = self:statsFor(player)
	local look = root.CFrame.LookVector
	local rootVelocity = root.AssemblyLinearVelocity
	local launchVelocity = look * FlareData.THROW_SPEED_STUDS_PER_SEC + Vector3.new(rootVelocity.X, FlareData.THROW_UPWARD_SPEED_STUDS_PER_SEC, rootVelocity.Z)
	local stick = Instance.new("Part")
	stick.Name = "Flare"
	stick.Shape = Enum.PartType.Cylinder
	stick.Size = FlareData.STICK_SIZE
	stick.Transparency = 1
	stick.CanQuery = false
	stick.CanTouch = false
	stick.CollisionGroup = Constants.COLLISION_GROUP_DYNAMITE
	stick.CFrame = CFrame.new(root.Position + look * FlareData.THROW_OFFSET_STUDS + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	stick.AssemblyLinearVelocity = launchVelocity
	stick:SetAttribute(Attributes.FLARE_THROWER_USER_ID, player.UserId)
	stick:SetAttribute(Attributes.FLARE_LAUNCH_VELOCITY, launchVelocity)
	CollectionService:AddTag(stick, Tags.FLARE_STICK)
	stick.Parent = self:getStickFolder()
	-- the thrower simulates it: only their client has the mine's blocks to land on
	stick:SetNetworkOwner(player)
	-- the throw is the spend: the hand is empty and the next flare comes
	self:setReadyTime(player, now + FlareData.COOLDOWN_SEC)
	ToolManager:setEquippedTool(player, MiningRules.NO_TOOL)

	local throwOrigin = root.Position
	local lastPosition = stick.Position
	task.spawn(
		function()
			while stick.Parent do
				lastPosition = stick.Position
				task.wait(TRACK_INTERVAL_SEC)
			end
		end
	)
	task.delay(
		FlareData.LIGHT_DELAY_SEC,
		function()
			local position = if stick.Parent then stick.Position else lastPosition
			stick:Destroy()
			if (position - throwOrigin).Magnitude > FlareData.MAX_LAND_DISTANCE_STUDS then
				warn(`FlareManager: {player.Name}'s flare ended up too far from the throw; it is lost`)
				return
			end
			if not player.Parent or not RunCycleManager:isRunOn() then
				return
			end
			self:light(player, position, stats)
		end
	)
end

-- the slot is the flare's while the class says so (see the header)
function FlareManager:applyGadget(player: Player)
	if self:hasFlareGadget(player) then
		ToolManager:grantTool(player, Enums.ToolKind.GADGET)
	end
end

function FlareManager:getNetHandlers()
	return {
		[NetEventNames.TRY_THROW_FLARE] = {
			shape = TRY_THROW_FLARE_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:throw(player)
			end,
		},
	}
end

-- every Heartbeat a burnt-out flare goes
function FlareManager:step()
	if next(self.flaresById) == nil then
		return
	end
	local now = workspace:GetServerTimeNow()
	for _, flare in self:getFlares() do
		if now >= flare.endTime then
			self:removeFlare(flare)
		end
	end
end

-- a new run: every flare is out and every cooldown over
function FlareManager:onRunStarted()
	for _, flare in self:getFlares() do
		self:removeFlare(flare)
	end
	for player in self.readyTimeByPlayer do
		if player.Parent then
			self:setReadyTime(player, nil)
		end
	end
	for _, player in GameController:getReadyPlayers() do
		self:applyGadget(player)
	end
end

function FlareManager:onPlayerReady(player: Player)
	self:replicate(player)
	self:applyGadget(player)
end

function FlareManager:onPlayerRemoved(player: Player)
	self.readyTimeByPlayer[player] = nil
end

function FlareManager:init()
	-- the slot drains its sheet over the same wait the server keeps
	SplendidReplicationManager:setGameMetadata(Attributes.FLARE_COOLDOWN_SEC, FlareData.COOLDOWN_SEC)
	GameController:registerPlaceManager(self)
	CharacterManager:subscribeClassChanged(
		function(player: Player, _classKind: number)
			if GameController:isPlayerReady(player) then
				self:applyGadget(player)
			end
		end
	)
	RunService.Heartbeat:Connect(
		function()
			self:step()
		end
	)
end

function FlareManager.new(): FlareManager
	local self = setmetatable({}, FlareManager) :: FlareManager
	self.flaresById = {}
	self.readyTimeByPlayer = {}
	self.nextId = 1
	self.shadowFolder = nil
	self.stickFolder = nil
	return self
end

return FlareManager.new()
