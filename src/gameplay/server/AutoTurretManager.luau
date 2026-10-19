--!strict

-- The Auto Turret, the Gunner's gadget (GDD "Classes", M66). A class
-- whose kit names it gets the GADGET tool slot; placing spends the slot
-- and the turret stands as one invisible server part (the shadow system:
-- Tags.AUTO_TURRET, the AutoTurret* attributes) that every client dresses
-- with the designer's model. It is not a placement: it stands off the
-- defensive grid on any ground monsters can walk (the flow field says
-- which), one per player, free, picked up and moved at will through a
-- prompt only its owner sees. Every Heartbeat it fires at the nearest
-- ground target like a Sentry Gun, its owner credited, and it is a
-- player to the monsters (MonsterManager lists it among their PLAYERS
-- targets and hurts it here), so hunters chew on it and tower destroyers
-- walk past. Its HP travels with its owner: a pick-up carries what was
-- left to the next one placed, and a loss keeps the slot greyed until the
-- next dawn. Numbers: GameData/Gadgets/AutoTurret; rules: AutoTurretRules.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local AutoTurretRules = require("@game/ReplicatedStorage/Shared/AutoTurretRules")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local FlowField = require("@game/ReplicatedStorage/Shared/FlowField")
local GadgetRules = require("@game/ReplicatedStorage/Shared/GadgetRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PlacementRules = require("@game/ReplicatedStorage/Shared/PlacementRules")
local RunCycleRules = require("@game/ReplicatedStorage/Shared/RunCycleRules")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local TowerRules = require("@game/ReplicatedStorage/Shared/TowerRules")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")
local AutoTurretData = require("@game/ServerScriptService/GameData/Gadgets/AutoTurret")
local CharacterManager = require(script.Parent.Parent.Server.CharacterManager)
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local DamageableManager = require(script.Parent.DamageableManager)
local GadgetUpgradeManager = require(script.Parent.GadgetUpgradeManager)
local MonsterPathManager = require(script.Parent.MonsterPathManager)
local ReviveManager = require(script.Parent.ReviveManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunPauseManager = require(script.Parent.RunPauseManager)
local ToolManager = require(script.Parent.ToolManager)

local AutoTurretManager = {}
AutoTurretManager.__index = AutoTurretManager

export type Turret = {
	id: string,
	owner: Player,
	ownerUserId: number,
	hp: number,
	maxHp: number,
	-- the owner's gadget level when placed, kept current while it stands (M67)
	level: number,
	-- the base pose: on the ground, turned the way the player faced
	cframe: CFrame,
	shadow: BasePart,
	yawDegrees: number,
	publishedYawDegrees: number,
	lastFireTime: number?,
}

type PlayerState = {
	-- true from a loss until the next dawn: no placement, the slot greyed
	isLostUntilDawn: boolean,
	-- the HP the next turret starts with: carried from a pick-up, held to
	-- the level's maximum at placement; FULL_HP after a loss or a new run
	carriedHp: number,
}

export type LevelStats = {
	DAMAGE: number,
	FIRE_INTERVAL_SEC: number,
	RANGE_STUDS: number,
	MAX_HP: number,
}

export type AutoTurretManager = typeof(setmetatable(
	{} :: {
		turretsById: { [string]: Turret },
		turretByPlayer: { [Player]: Turret },
		stateByPlayer: { [Player]: PlayerState },
		nextId: number,
		shadowFolder: Folder?,
	},
	AutoTurretManager
))

local ID_FORMAT = "AutoTurret%d"
-- more than any level's maximum, so the placement clamps it to full
local FULL_HP = math.huge
local FEEDBACK_CANNOT_BUILD = "Can't build here"
local FEEDBACK_NOT_AVAILABLE = "Auto Turret not available yet."
local FEEDBACK_DESTROYED = "Auto Turret destroyed"

local TRY_PLACE_AUTO_TURRET_SHAPE = {
	position = "vector3",
	yawDegrees = "number",
}
local TRY_PICK_UP_AUTO_TURRET_SHAPE = {}

-- a Sentry Gun's shape: one shot at a time, ground only
local BEHAVIOR: PlacementRules.TowerBehavior = {
	ATTACK = Enums.TowerAttack.SINGLE,
	TARGETS_GROUND = true,
	TARGETS_AIR = false,
	HAS_TURRET = true,
}

function AutoTurretManager:getShadowFolder(): Folder
	local folder = self.shadowFolder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = Constants.AUTO_TURRET_SHADOW_FOLDER
	folder.Parent = workspace
	self.shadowFolder = folder
	return folder
end

function AutoTurretManager:getPlayerState(player: Player): PlayerState
	local state = self.stateByPlayer[player]
	if not state then
		state = {
			isLostUntilDawn = false,
			carriedHp = FULL_HP,
		}
		self.stateByPlayer[player] = state
	end
	return state
end

function AutoTurretManager:getTurret(id: string): Turret?
	return self.turretsById[id]
end

function AutoTurretManager:hasTurret(id: string): boolean
	return self.turretsById[id] ~= nil
end

function AutoTurretManager:getPlayerTurret(player: Player): Turret?
	return self.turretByPlayer[player]
end

-- a lost turret comes back: at dawn for everyone, or from the dev tool
function AutoTurretManager:restore(player: Player)
	local state = self:getPlayerState(player)
	if not state.isLostUntilDawn then
		return
	end
	state.isLostUntilDawn = false
	self:replicatePlayer(player)
end

-- every standing turret, for the monsters' target list
function AutoTurretManager:getTurrets(): { Turret }
	local turrets = {}
	for _, turret in self.turretsById do
		table.insert(turrets, turret)
	end
	return turrets
end

function AutoTurretManager:hasAutoTurretGadget(player: Player): boolean
	return CharacterManager:getGadgetKind(player) == Enums.GadgetKind.AUTO_TURRET
end

function AutoTurretManager:getDrawRangeStuds(): number
	return AutoTurretData.DRAW_RANGE_STUDS
end

-- whether a turret stands close enough to the Refinery to be weighed
-- against it by the monsters (MonsterManager lists it among their
-- REFINERY candidates too); false with no Refinery on the map
function AutoTurretManager:isGuardingRefinery(turret: Turret): boolean
	local refineryPosition = MonsterPathManager:getRefineryPosition()
	if not refineryPosition then
		return false
	end
	local offset = turret.cframe.Position - refineryPosition
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= AutoTurretData.REFINERY_GUARD_RADIUS_STUDS
end

function AutoTurretManager:statsForLevel(level: number): LevelStats
	return GadgetRules.statsFor(AutoTurretData.STATS_BY_LEVEL, level)
end

function AutoTurretManager:replicatePlayer(player: Player)
	if not player.Parent then
		return
	end
	local state = self:getPlayerState(player)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.AUTO_TURRET_IS_LOST, state.isLostUntilDawn)
end

function AutoTurretManager:replicateTurret(turret: Turret)
	local shadow = turret.shadow
	shadow:SetAttribute(Attributes.AUTO_TURRET_OWNER_USER_ID, turret.ownerUserId)
	shadow:SetAttribute(Attributes.AUTO_TURRET_HP, turret.hp)
	shadow:SetAttribute(Attributes.AUTO_TURRET_MAX_HP, turret.maxHp)
	shadow:SetAttribute(Attributes.AUTO_TURRET_LEVEL, turret.level)
end

-- the owner bought a level while a turret stands (M67): it grows in place,
-- the new maximum's gain added to what it has left
function AutoTurretManager:applyLevel(player: Player, level: number)
	local turret = self.turretByPlayer[player]
	if not turret then
		return
	end
	local stats = self:statsForLevel(level)
	turret.hp = math.min(stats.MAX_HP, turret.hp + math.max(0, stats.MAX_HP - turret.maxHp))
	turret.maxHp = stats.MAX_HP
	turret.level = level
	self:replicateTurret(turret)
end

-- the GADGET slot follows the class (at Ready and on a dev-tool class
-- change): the Gunner holds the turret button while none stands, every
-- other class has no gadget slot yet
function AutoTurretManager:applyGadget(player: Player)
	local gadgetKind = CharacterManager:getGadgetKind(player)
	ToolManager:setGadgetKind(player, gadgetKind)
	if gadgetKind ~= Enums.GadgetKind.AUTO_TURRET then
		local standing = self.turretByPlayer[player]
		if standing then
			self:destroyTurret(standing)
		end
		ToolManager:revokeTool(player, Enums.ToolKind.GADGET)
		return
	end
	if self.turretByPlayer[player] then
		ToolManager:revokeTool(player, Enums.ToolKind.GADGET)
	else
		ToolManager:grantTool(player, Enums.ToolKind.GADGET)
	end
end

-- the ground under a requested spot, cast past every character so a
-- player standing there is not mistaken for a floor
function AutoTurretManager:findGround(position: Vector3): RaycastResult?
	local excluded: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = excluded
	parameters.RespectCanCollide = true
	local origin = position + Vector3.new(0, AutoTurretData.GROUND_RAY_ABOVE_STUDS, 0)
	local length = AutoTurretData.GROUND_RAY_ABOVE_STUDS + AutoTurretData.GROUND_RAY_BELOW_STUDS
	return workspace:Raycast(origin, Vector3.new(0, -length, 0), parameters)
end

-- monsters can walk there: inside the path grid and not blocked
function AutoTurretManager:isReachable(x: number, z: number): boolean
	local grid = MonsterPathManager:getGrid()
	if not grid then
		return false
	end
	local index = FlowField.indexAt(grid, x, z)
	if not index then
		return false
	end
	return grid.inside[index] == true and grid.walkable[index] == true
end

function AutoTurretManager:place(player: Player, position: Vector3, yawDegrees: number)
	if not GameController:isPlayerReady(player) or ReviveManager:isDead(player) then
		return
	end
	if not self:hasAutoTurretGadget(player) or ToolManager:getEquippedTool(player) ~= Enums.ToolKind.GADGET then
		return
	end
	if self.turretByPlayer[player] then
		return
	end
	local state = self:getPlayerState(player)
	if state.isLostUntilDawn then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_AVAILABLE)
		return
	end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	if not AutoTurretRules.isWithinPlaceDistance(root.Position, position, AutoTurretData.PLACE_DISTANCE_STUDS, AutoTurretData.PLACE_TOLERANCE_STUDS) then
		PlayerFeedbackManager:give(player, FEEDBACK_CANNOT_BUILD)
		return
	end
	local hit = self:findGround(position)
	local isGround = hit ~= nil and AutoTurretRules.findBlockingTag(hit.Instance, function(instance: Instance, tag: string): boolean
		return CollectionService:HasTag(instance, tag)
	end) == nil
	local normalY = if hit then hit.Normal.Y else 0
	local groundPosition = if hit then hit.Position else position
	local isAtGroundLevel = AutoTurretRules.isAtGroundLevel(groundPosition.Y, MonsterPathManager:getGroundHeight(groundPosition.X, groundPosition.Z), AutoTurretData.GROUND_LEVEL_TOLERANCE_STUDS)
	local problem = AutoTurretRules.placementProblem(isGround, normalY, AutoTurretData.MIN_GROUND_NORMAL_Y, self:isReachable(groundPosition.X, groundPosition.Z), isAtGroundLevel)
	if problem then
		PlayerFeedbackManager:give(player, FEEDBACK_CANNOT_BUILD)
		return
	end

	local id = string.format(ID_FORMAT, self.nextId)
	self.nextId += 1
	local level = GadgetUpgradeManager:getLevel(player)
	local stats = self:statsForLevel(level)
	local cframe = CFrame.new(groundPosition) * CFrame.Angles(0, math.rad(yawDegrees), 0)
	local size: Vector3 = AutoTurretData.HIT_BOX_SIZE
	local shadow = Instance.new("Part")
	shadow.Name = id
	shadow.Size = size
	shadow.Transparency = 1
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.CanTouch = false
	shadow.CFrame = cframe * CFrame.new(0, size.Y / 2, 0)
	local turret: Turret = {
		id = id,
		owner = player,
		ownerUserId = player.UserId,
		hp = AutoTurretRules.carriedHp(state.carriedHp, stats.MAX_HP),
		maxHp = stats.MAX_HP,
		level = level,
		cframe = cframe,
		shadow = shadow,
		yawDegrees = 0,
		publishedYawDegrees = 0,
		lastFireTime = nil,
	}
	self.turretsById[id] = turret
	self.turretByPlayer[player] = turret
	self:replicateTurret(turret)
	shadow:SetAttribute(Attributes.AUTO_TURRET_YAW_DEGREES, 0)
	CollectionService:AddTag(shadow, Tags.AUTO_TURRET)
	shadow.Parent = self:getShadowFolder()
	-- the button leaves the bar until the turret comes back
	ToolManager:revokeTool(player, Enums.ToolKind.GADGET)
	print(`[AutoTurretManager] {player.Name} placed {id} with {turret.hp} HP`)
end

function AutoTurretManager:destroyTurret(turret: Turret)
	if self.turretsById[turret.id] ~= turret then
		return
	end
	self.turretsById[turret.id] = nil
	if self.turretByPlayer[turret.owner] == turret then
		self.turretByPlayer[turret.owner] = nil
	end
	turret.shadow:Destroy()
end

-- the owner's prompt: the turret comes back to the bar with its HP
function AutoTurretManager:pickUp(player: Player)
	local turret = self.turretByPlayer[player]
	if not turret or not GameController:isPlayerReady(player) then
		return
	end
	local state = self:getPlayerState(player)
	state.carriedHp = AutoTurretRules.carriedHp(turret.hp, turret.maxHp)
	self:destroyTurret(turret)
	if self:hasAutoTurretGadget(player) then
		ToolManager:grantTool(player, Enums.ToolKind.GADGET)
	end
	print(`[AutoTurretManager] {player.Name} picked up {turret.id} at {state.carriedHp} HP`)
end

-- a monster's hit (MonsterManager:hurt); true when the id was a turret.
-- A loss hands the owner a full turret at the next dawn
function AutoTurretManager:damage(id: string, amount: number, attackerKind: number?): boolean
	local turret = self.turretsById[id]
	if not turret then
		return false
	end
	if amount <= 0 then
		return true
	end
	turret.hp = math.max(0, turret.hp - amount)
	if turret.hp > 0 then
		turret.shadow:SetAttribute(Attributes.AUTO_TURRET_HP, turret.hp)
		return true
	end
	local owner = turret.owner
	self:destroyTurret(turret)
	local state = self:getPlayerState(owner)
	state.isLostUntilDawn = true
	state.carriedHp = FULL_HP
	if owner.Parent then
		self:replicatePlayer(owner)
		if self:hasAutoTurretGadget(owner) then
			-- the button returns greyed out; the client reads the lost flag
			ToolManager:grantTool(owner, Enums.ToolKind.GADGET)
		end
		PlayerFeedbackManager:give(owner, FEEDBACK_DESTROYED)
	end
	print(`[AutoTurretManager] {id} destroyed by monster kind {tostring(attackerKind)}; {owner.Name} may place again at dawn`)
	return true
end

-- every Heartbeat each turret turns to the nearest ground target in
-- range and fires on its interval; the owner is the attacker
function AutoTurretManager:step()
	if next(self.turretsById) == nil then
		return
	end
	if RunPauseManager:isPaused() or RunCycleRules.isRunOver(RunCycleManager:getRunState()) then
		return
	end
	local now = workspace:GetServerTimeNow()
	local targets = DamageableManager:getTargets()
	for _, turret in self.turretsById do
		local stats = self:statsForLevel(turret.level)
		local origin = TowerRules.muzzlePosition(turret.cframe, AutoTurretData.MUZZLE_HEIGHT_STUDS)
		local target = TowerRules.pickTarget(origin, stats.RANGE_STUDS, Enums.TargetPriority.CLOSEST, targets, BEHAVIOR)
		if not target then
			continue
		end
		turret.yawDegrees = TowerRules.yawDegreesToward(turret.cframe, target.position)
		local rounded = math.floor(turret.yawDegrees + 0.5)
		if rounded ~= turret.publishedYawDegrees then
			turret.publishedYawDegrees = rounded
			turret.shadow:SetAttribute(Attributes.AUTO_TURRET_YAW_DEGREES, rounded)
		end
		if not WeaponRules.canFire(turret.lastFireTime, now, stats.FIRE_INTERVAL_SEC) then
			continue
		end
		turret.lastFireTime = now
		DamageableManager:damage(target.id, stats.DAMAGE, turret.owner)
		NetManager:notifyAllClients(NetEventNames.NOTIFY_AUTO_TURRET_FIRED, {
			id = turret.id,
			hitId = target.id,
		})
	end
end

function AutoTurretManager:getNetHandlers()
	return {
		[NetEventNames.TRY_PLACE_AUTO_TURRET] = {
			shape = TRY_PLACE_AUTO_TURRET_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:place(player, payload.position, payload.yawDegrees)
			end,
		},
		[NetEventNames.TRY_PICK_UP_AUTO_TURRET] = {
			shape = TRY_PICK_UP_AUTO_TURRET_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:pickUp(player)
			end,
		},
	}
end

-- dawn: every lost turret is back in the bar
function AutoTurretManager:onDayStarted()
	for player in self.stateByPlayer do
		if player.Parent then
			self:restore(player)
		end
	end
end

-- a new run: every turret is gone and every loss forgiven
function AutoTurretManager:onRunStarted()
	for _, turret in self:getTurrets() do
		self:destroyTurret(turret)
	end
	for player, state in self.stateByPlayer do
		state.isLostUntilDawn = false
		state.carriedHp = FULL_HP
		if player.Parent then
			self:replicatePlayer(player)
		end
	end
	for _, player in GameController:getReadyPlayers() do
		self:applyGadget(player)
	end
end

-- ready-sequence entry: the slot and the lost flag; a dev-tool reset
-- replays it, which is right, since a reset player is a new arrival
function AutoTurretManager:onPlayerReady(player: Player)
	self:replicatePlayer(player)
	self:applyGadget(player)
end

-- a leaver's turret goes with them: it was a player, not a structure
function AutoTurretManager:onPlayerRemoved(player: Player)
	local turret = self.turretByPlayer[player]
	if turret then
		self:destroyTurret(turret)
	end
	self.stateByPlayer[player] = nil
end

function AutoTurretManager:init()
	-- the client previews with the same numbers the server refuses by
	SplendidReplicationManager:setGameMetadata(Attributes.AUTO_TURRET_PLACE_DISTANCE_STUDS, AutoTurretData.PLACE_DISTANCE_STUDS)
	SplendidReplicationManager:setGameMetadata(Attributes.AUTO_TURRET_MIN_GROUND_NORMAL_Y, AutoTurretData.MIN_GROUND_NORMAL_Y)
	GameController:registerPlaceManager(self)
	RunCycleManager:subscribeDayStarted(
		function(_day: number, _scalingCount: number)
			self:onDayStarted()
		end
	)
	CharacterManager:subscribeClassChanged(
		function(player: Player, _classKind: number)
			if GameController:isPlayerReady(player) then
				self:applyGadget(player)
			end
		end
	)
	GadgetUpgradeManager:subscribeUpgraded(
		function(player: Player, level: number)
			self:applyLevel(player, level)
		end
	)
	RunService.Heartbeat:Connect(
		function()
			self:step()
		end
	)
end

function AutoTurretManager.new(): AutoTurretManager
	local self = setmetatable({}, AutoTurretManager) :: AutoTurretManager
	self.turretsById = {}
	self.turretByPlayer = {}
	self.stateByPlayer = {}
	self.nextId = 1
	self.shadowFolder = nil
	return self
end

return AutoTurretManager.new()
