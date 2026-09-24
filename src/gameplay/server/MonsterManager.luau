--!strict

-- Every monster (GDD "Monsters", "Monster Performance"), M29. A monster is
-- a row in a Lua table here, never a model on the server: its kind, root
-- position, facing, what it is doing, and its target. Its HP, hit box, and
-- status effects live in DamageableManager (registered without a shadow),
-- so weapons, posts, Towers, and Traps hurt, slow, and stun it exactly as
-- they did the dummies. All monsters step together TICK_RATE_HZ times a
-- second (GameData/Monsters/Behavior):
--   a target: the Refinery in range first, then the kind's priorities in
--     order, each within its AttackRange (pure MonsterRules); a barrier on
--     the path ahead is a target too, so a blocked monster breaks through;
--   a move: otherwise one step along the shared flow field
--     (MonsterPathManager), then a push apart from its neighbours;
--   an attack: melee hurts the target (and a blast its radius), ranged
--     launches a projectile that lands after its flight.
-- Clients get the positions as packed snapshots (MonsterSnapshotCodec) on
-- one UnreliableRemoteEvent: each player every tick for the monsters near
-- them, the rest every FAR_EVERY_TICKS ticks, so nothing is ever streamed
-- out. Spawns, deaths, projectiles, and blasts go on the reliable event,
-- batched per tick. Until Revives (M32) a player is never brought below
-- PLAYER_MIN_HEALTH.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local FlowField = require("@game/ReplicatedStorage/Shared/FlowField")
local MonsterRules = require("@game/ReplicatedStorage/Shared/MonsterRules")
local MonsterSnapshotCodec = require("@game/ReplicatedStorage/Shared/MonsterSnapshotCodec")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local BehaviorData = require("@game/ServerScriptService/GameData/Monsters/Behavior")
local RosterData = require("@game/ServerScriptService/GameData/Monsters/Roster")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local DamageableManager = require(script.Parent.DamageableManager)
local MonsterPathManager = require(script.Parent.MonsterPathManager)
local PlacementManager = require(script.Parent.PlacementManager)
local StructureManager = require(script.Parent.StructureManager)

local MonsterManager = {}
MonsterManager.__index = MonsterManager

-- typed once here so every roster read is checked against MonsterData
local ROSTER_BY_KIND: { [number]: MonsterRules.MonsterData } = RosterData.BY_KIND

-- the template measures a kind's body is built from
type ModelMetrics = {
	rootHeightStuds: number,
	boxSize: Vector3,
	-- the hit box centre's height above the root
	boxOffsetY: number,
}

type Monster = {
	-- the network id in every snapshot (1 to 65535, reused after death)
	id: number,
	damageableId: string,
	kind: number,
	data: MonsterRules.MonsterData,
	isAir: boolean,
	-- the root part's position, as the client places the model
	position: Vector3,
	groundY: number,
	yawDegrees: number,
	rootHeightStuds: number,
	boxSize: Vector3,
	boxOffsetY: number,
	-- half its width: how far its body reaches past its range
	reachStuds: number,
	-- its own lane: how far to the side of the shared route it walks
	laneOffsetStuds: number,
	action: number,
	attackCounter: number,
	lastAttackTime: number,
	isDead: boolean,
	-- reused every tick so building a snapshot allocates nothing per monster
	record: MonsterSnapshotCodec.Record,
	-- whether the record changed this tick or the one before; a monster
	-- standing at its target is only sent at the far cadence, and the tick
	-- after it stops still goes out so no client carries it past the stop
	isChanged: boolean,
	wasChangedLastTick: boolean,
	-- where the tick began and where it was heading, to tell a jammed
	-- monster from a walking one
	tickStartPosition: Vector3,
	tickDestination: Vector3?,
	-- how long it has made no headway, and until when it follows the route
	-- rather than a target it could not get to
	jammedSec: number,
	ignoreTargetUntil: number,
	-- the route point last worked out, good while the monster stays in the
	-- same cell and the path field is the same version
	waypoint: Vector3?,
	waypointBarrierId: string?,
	waypointCellIndex: number?,
	waypointPathVersion: number,
}

type Projectile = {
	data: MonsterRules.MonsterData,
	targetId: string,
	targetType: number,
	landPosition: Vector3,
	landTime: number,
}

export type MonsterManager = typeof(setmetatable(
	{} :: {
		monsters: { Monster },
		monsterById: { [number]: Monster },
		monsterByDamageableId: { [string]: Monster },
		nextNetworkId: number,
		projectiles: { Projectile },
		tickAccumulatorSec: number,
		tickCount: number,
		-- batched for the next tick's notifies
		pendingSpawnIds: { number },
		pendingDeathIds: { number },
		metricsByModel: { [string]: ModelMetrics },
		warnedModels: { [string]: boolean },
		snapshotEvent: UnreliableRemoteEvent?,
		-- the tick's candidates, and the players behind the player candidates
		candidatesByType: MonsterRules.CandidatesByType,
		candidateById: { [string]: MonsterRules.Candidate },
		playerByCandidateId: { [string]: Player },
		lastStatsTime: number,
		stepSecTotal: number,
		stepCount: number,
		lastDownWarnTime: number,
		killedHandlers: { (kind: number) -> () },
		random: Random,
		-- per kind, so a tick allocates no priority list per monster
		priorityOrderByKind: { [number]: { number } },
		-- the push-apart buckets, kept between ticks and cleared, not rebuilt
		separationBuckets: { [number]: { Monster } },
		separationUsedKeys: { number },
	},
	MonsterManager
))

local DEFAULT_METRICS: ModelMetrics = {
	rootHeightStuds = 3,
	boxSize = Vector3.new(4, 5, 1),
	boxOffsetY = -0.5,
}
local PLAYER_CANDIDATE_PREFIX = "Player"
local STATS_INTERVAL_SEC = 1
local DOWN_WARN_INTERVAL_SEC = 2
-- a projectile at a player lands on them only if they are still this close
-- to where it was aimed (or inside its radius)
local PROJECTILE_PLAYER_HIT_STUDS = 3
-- a monster pushed off the grid looks this many rings of cells for a way back
local NEAREST_CELL_RINGS = 8
-- a walker that got less than this share of its step closer to where it
-- is going (after the crowd pushed back or slid it sideways) is jammed and
-- stays put, so a stalled crowd stands still instead of churning, and
-- costs no bandwidth
local JAMMED_STEP_SHARE = 0.3

-- the bucket a flat point falls in for the push-apart hash
local function separationKey(x: number, z: number, spacing: number): number
	return (math.floor(x / spacing) + 32768) * 65536 + (math.floor(z / spacing) + 32768)
end
-- a lane that does not fit is halved this many times before giving up
local LANE_SHRINK_TRIES = 3

function MonsterManager:getAliveCount(): number
	local count = 0
	for _, monster in self.monsters do
		if not monster.isDead then
			count += 1
		end
	end
	return count
end

function MonsterManager:subscribeKilled(handler: (kind: number) -> ())
	table.insert(self.killedHandlers, handler)
end

function MonsterManager:getRosterData(kind: number): MonsterRules.MonsterData?
	return ROSTER_BY_KIND[kind]
end

function MonsterManager:getModelMetrics(modelName: string): ModelMetrics
	local cached = self.metricsByModel[modelName]
	if cached then
		return cached
	end
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local folder = if gameAssets then gameAssets:FindFirstChild(Constants.MONSTER_TEMPLATES_FOLDER) else nil
	local template = if folder then folder:FindFirstChild(modelName) else nil
	local root = if template and template:IsA("Model") then template.PrimaryPart else nil
	local proxy = if template then template:FindFirstChild(Constants.MONSTER_PROXY_PART) else nil
	local metrics = DEFAULT_METRICS
	if template and root and proxy and proxy:IsA("BasePart") then
		-- the Proxy's bottom is the feet, so a model scaled in Studio still
		-- stands on the ground
		metrics = {
			rootHeightStuds = root.Position.Y - (proxy.Position.Y - proxy.Size.Y / 2),
			boxSize = proxy.Size,
			boxOffsetY = proxy.Position.Y - root.Position.Y,
		}
	elseif not self.warnedModels[modelName] then
		self.warnedModels[modelName] = true
		warn(`MonsterManager: no monster template {modelName} with a PrimaryPart and a {Constants.MONSTER_PROXY_PART} under GameAssets.{Constants.MONSTER_TEMPLATES_FOLDER}; run scripts/studio/build_monster_templates.luau`)
	end
	self.metricsByModel[modelName] = metrics
	return metrics
end

function MonsterManager:allocateNetworkId(): number?
	for _ = 1, MonsterSnapshotCodec.MAX_ID do
		local id = self.nextNetworkId
		self.nextNetworkId = if id >= MonsterSnapshotCodec.MAX_ID then 1 else id + 1
		if not self.monsterById[id] then
			return id
		end
	end
	return nil
end

function MonsterManager:hitBoxCFrame(monster: Monster): CFrame
	return CFrame.new(monster.position + Vector3.new(0, monster.boxOffsetY, 0)) * CFrame.Angles(0, math.rad(monster.yawDegrees), 0)
end

-- the root's height over ground at a flat position: the grid's ground
-- plus the body, plus a flier's own FLIGHT_HEIGHT_STUDS
function MonsterManager:rootY(monster: Monster, groundY: number): number
	local flyHeight = if monster.isAir then monster.data.FLIGHT_HEIGHT_STUDS or 0 else 0
	return groundY + monster.rootHeightStuds + flyHeight
end

-- one monster of a kind at a flat position; nil at the alive limit or for
-- an unknown kind
function MonsterManager:spawnMonster(kind: number, flatPosition: Vector3): number?
	local data = self:getRosterData(kind)
	if not data then
		warn("MonsterManager: no Roster entry for monster kind", kind)
		return nil
	end
	-- the alive count, not the list: the dead stay listed until the sweep
	if self:getAliveCount() >= BehaviorData.MAX_ALIVE then
		return nil
	end
	local networkId = self:allocateNetworkId()
	if not networkId then
		return nil
	end
	local metrics = self:getModelMetrics(MonsterRules.modelNameFor(kind))
	local groundY = MonsterPathManager:getGroundHeight(flatPosition.X, flatPosition.Z) or flatPosition.Y
	local refinery = MonsterPathManager:getRefineryPosition()
	local facing = if refinery then refinery - flatPosition else Vector3.new(-1, 0, 0)
	local monster: Monster = {
		id = networkId,
		damageableId = "",
		kind = kind,
		data = data,
		isAir = MonsterRules.isAir(data),
		position = flatPosition,
		groundY = groundY,
		yawDegrees = math.deg(math.atan2(-facing.X, -facing.Z)),
		rootHeightStuds = metrics.rootHeightStuds,
		boxSize = metrics.boxSize,
		boxOffsetY = metrics.boxOffsetY,
		reachStuds = math.max(metrics.boxSize.X, metrics.boxSize.Z) / 2,
		laneOffsetStuds = self.random:NextNumber(-BehaviorData.LANE_SPREAD_STUDS, BehaviorData.LANE_SPREAD_STUDS),
		action = Enums.MonsterAction.MOVING,
		attackCounter = 0,
		lastAttackTime = 0,
		isDead = false,
		record = {
			id = networkId,
			position = Vector3.zero,
			yawDegrees = 0,
			hpShare = 1,
			action = Enums.MonsterAction.MOVING,
			attackCounter = 0,
			isSlowed = false,
			isBurning = false,
		},
		isChanged = true,
		wasChangedLastTick = true,
		tickStartPosition = Vector3.zero,
		tickDestination = nil,
		jammedSec = 0,
		ignoreTargetUntil = 0,
		waypoint = nil,
		waypointBarrierId = nil,
		waypointCellIndex = nil,
		waypointPathVersion = -1,
	}
	monster.position = Vector3.new(flatPosition.X, self:rootY(monster, groundY), flatPosition.Z)
	monster.damageableId = DamageableManager:register({
		name = Enums.getPublicName(Enums.MonsterKind, kind) or "Monster",
		cframe = self:hitBoxCFrame(monster),
		size = monster.boxSize,
		maxHp = data.MAX_HP,
		isAirborne = monster.isAir,
		hasShadow = false,
		onDestroyed = function(_attacker: Player?)
			self:onMonsterKilled(monster)
		end,
	})
	table.insert(self.monsters, monster)
	self.monsterById[networkId] = monster
	self.monsterByDamageableId[monster.damageableId] = monster
	table.insert(self.pendingSpawnIds, networkId)
	return networkId
end

-- takes a monster out of play; the dead are swept from the list at the
-- end of the tick
function MonsterManager:removeMonster(monster: Monster)
	if monster.isDead then
		return
	end
	monster.isDead = true
	self.monsterById[monster.id] = nil
	self.monsterByDamageableId[monster.damageableId] = nil
	table.insert(self.pendingDeathIds, monster.id)
end

function MonsterManager:sweepDead()
	local alive = table.create(#self.monsters)
	for _, monster in self.monsters do
		if not monster.isDead then
			table.insert(alive, monster)
		end
	end
	self.monsters = alive
end

-- HP reached zero (DamageableManager already let the entry go)
function MonsterManager:onMonsterKilled(monster: Monster)
	if monster.isDead then
		return
	end
	local data = monster.data
	if data.DAMAGE_ON_DEATH and data.ATTACK_RADIUS_STUDS > 0 then
		self:blast(data, monster.position, nil)
	end
	self:removeMonster(monster)
	for _, handler in self.killedHandlers do
		handler(monster.kind)
	end
end

-- a monster that dies by its own attack (a Bomber)
function MonsterManager:expire(monster: Monster)
	DamageableManager:unregister(monster.damageableId)
	self:removeMonster(monster)
end

function MonsterManager:killAll()
	for _, monster in self.monsters do
		DamageableManager:unregister(monster.damageableId)
		self:removeMonster(monster)
	end
	self.projectiles = {}
	self:sweepDead()
end

-- everything a monster could attack this tick, by target type
function MonsterManager:buildCandidates()
	local candidatesByType = MonsterRules.emptyCandidates()
	local candidateById: { [string]: MonsterRules.Candidate } = {}
	local playerByCandidateId: { [string]: Player } = {}
	local function add(candidate: MonsterRules.Candidate)
		table.insert(candidatesByType[candidate.targetType], candidate)
		candidateById[candidate.id] = candidate
	end
	for _, player in GameController:getReadyPlayers() do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
			continue
		end
		local id = PLAYER_CANDIDATE_PREFIX .. player.UserId
		playerByCandidateId[id] = player
		add({
			id = id,
			targetType = Enums.MonsterTargetType.PLAYERS,
			position = root.Position,
		})
	end
	for _, box in StructureManager:getStructureBoxes() do
		if box.isDestroyed then
			continue
		end
		add({
			id = box.id,
			targetType = if box.kind == Enums.StructureKind.REFINERY then Enums.MonsterTargetType.REFINERY else Enums.MonsterTargetType.WALLS,
			position = box.cframe.Position,
			cframe = box.cframe,
			size = box.size,
			radiusStuds = MonsterRules.boxRadius(box.size),
		})
	end
	local catalog = PlacementManager:getCatalog()
	for _, placement in PlacementManager:getPlacements() do
		local shadow = placement.shadow
		local isTower = placement.placementKind == Enums.PlacementKind.TOWER
		add({
			id = placement.id,
			targetType = if isTower then Enums.MonsterTargetType.TOWERS else Enums.MonsterTargetType.TRAPS,
			position = shadow.Position,
			cframe = shadow.CFrame,
			size = shadow.Size,
			radiusStuds = MonsterRules.boxRadius(shadow.Size),
		})
		-- a Decoy also stands in for a player, drawing hunters from its range
		local trap = if isTower then nil else catalog.traps[placement.typeKind]
		if trap and trap.DRAWS_ATTACKS then
			table.insert(candidatesByType[Enums.MonsterTargetType.PLAYERS], {
				id = placement.id,
				targetType = Enums.MonsterTargetType.TRAPS,
				position = shadow.Position,
				cframe = shadow.CFrame,
				size = shadow.Size,
				radiusStuds = MonsterRules.boxRadius(shadow.Size),
				drawRangeStuds = trap.RANGE_STUDS or 0,
			})
		end
	end
	self.candidatesByType = candidatesByType
	self.candidateById = candidateById
	self.playerByCandidateId = playerByCandidateId
end

-- hurts one candidate by whatever owns it
function MonsterManager:hurt(candidate: MonsterRules.Candidate, amount: number)
	if amount <= 0 then
		return
	end
	local targetType = candidate.targetType
	if targetType == Enums.MonsterTargetType.PLAYERS then
		local player = self.playerByCandidateId[candidate.id]
		local character = if player then player.Character else nil
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if not player or not humanoid then
			return
		end
		local health = humanoid.Health - amount
		if health < BehaviorData.PLAYER_MIN_HEALTH then
			local now = workspace:GetServerTimeNow()
			if now - self.lastDownWarnTime >= DOWN_WARN_INTERVAL_SEC then
				self.lastDownWarnTime = now
				warn(`MonsterManager: {player.Name} would be down (held at {BehaviorData.PLAYER_MIN_HEALTH} HP until Revives, M32)`)
			end
			health = BehaviorData.PLAYER_MIN_HEALTH
		end
		humanoid.Health = health
	elseif targetType == Enums.MonsterTargetType.TOWERS or targetType == Enums.MonsterTargetType.TRAPS then
		PlacementManager:damagePlacement(candidate.id, amount)
	else
		StructureManager:damageStructure(candidate.id, amount)
	end
end

-- a blast at a point: everything of the kind's damage types in its radius
function MonsterManager:blast(data: MonsterRules.MonsterData, center: Vector3, primaryId: string?)
	local radius = data.ATTACK_RADIUS_STUDS
	if radius <= 0 then
		return
	end
	for _, victim in MonsterRules.blastVictims(center, radius, data.TARGET_DAMAGE_TYPES, self.candidatesByType, primaryId) do
		self:hurt(victim, data.DAMAGE)
	end
	NetManager:notifyAllClients(NetEventNames.NOTIFY_MONSTER_BLAST, {
		position = center,
		radius = radius,
	})
end

function MonsterManager:attack(monster: Monster, target: MonsterRules.Candidate, now: number)
	local data = monster.data
	monster.lastAttackTime = now
	monster.attackCounter = (monster.attackCounter + 1) % MonsterSnapshotCodec.ATTACK_COUNTER_WRAP
	if MonsterRules.isRanged(data) then
		local from = monster.position + Vector3.new(0, monster.boxOffsetY + monster.boxSize.Y / 2, 0)
		local to = target.position
		local flightSec = MonsterRules.flightSec(from, to, BehaviorData.PROJECTILE_SPEED_STUDS_PER_SEC)
		table.insert(self.projectiles, {
			data = data,
			targetId = target.id,
			targetType = target.targetType,
			landPosition = to,
			landTime = now + flightSec,
		})
		NetManager:notifyAllClients(NetEventNames.NOTIFY_MONSTER_PROJECTILE, {
			monsterId = monster.id,
			projectile = data.PROJECTILE or "",
			from = from,
			to = to,
			flightSec = flightSec,
		})
		return
	end
	self:hurt(target, data.DAMAGE)
	if data.ATTACK_RADIUS_STUDS > 0 then
		self:blast(data, monster.position, target.id)
	end
	if data.DIE_ON_ATTACK then
		self:expire(monster)
	end
end

-- projectiles whose flight is over land now: the target if it is still
-- there, and everything in the radius
function MonsterManager:landProjectiles(now: number)
	if #self.projectiles == 0 then
		return
	end
	local flying = {}
	for _, projectile in self.projectiles do
		if now < projectile.landTime then
			table.insert(flying, projectile)
			continue
		end
		local target = self.candidateById[projectile.targetId]
		if target then
			local isHit = true
			if projectile.targetType == Enums.MonsterTargetType.PLAYERS then
				local reach = math.max(projectile.data.ATTACK_RADIUS_STUDS, PROJECTILE_PLAYER_HIT_STUDS)
				isHit = (target.position - projectile.landPosition).Magnitude <= reach
			end
			if isHit then
				self:hurt(target, projectile.data.DAMAGE)
			end
		end
		self:blast(projectile.data, projectile.landPosition, projectile.targetId)
	end
	self.projectiles = flying
end

-- a point beside the route on the monster's lane, halved and halved again
-- where the ground there is blocked, a barrier, or not in a straight line
-- from the monster; nil when even a small offset does not fit
function MonsterManager:lanePoint(monster: Monster, grid: FlowField.Grid, field: FlowField.Field, baseX: number, baseZ: number): Vector3?
	local offset = monster.laneOffsetStuds
	local headingX = baseX - monster.position.X
	local headingZ = baseZ - monster.position.Z
	local length = math.sqrt(headingX * headingX + headingZ * headingZ)
	if length < 1e-3 or math.abs(offset) < 0.5 then
		return nil
	end
	-- to the side of the heading, flat
	local sideX = -headingZ / length
	local sideZ = headingX / length
	for _ = 1, LANE_SHRINK_TRIES do
		local x = baseX + sideX * offset
		local z = baseZ + sideZ * offset
		local index = FlowField.indexAt(grid, x, z)
		if index and field.costs[index] < math.huge and FlowField.isLineClear(grid, monster.position.X, monster.position.Z, x, z, monster.isAir) then
			return Vector3.new(x, 0, z)
		end
		offset /= 2
	end
	return nil
end

-- where the monster walks next. Along the shared route: the farthest of
-- the next LOOKAHEAD_CELLS cells it can walk to in a straight line, moved
-- onto its own lane; the way back onto the grid when it is off it; the
-- Refinery once at the goal. Also returns the barrier standing in the
-- very next cell, if any, which is what a blocked monster attacks
function MonsterManager:nextWaypoint(monster: Monster): (Vector3?, string?)
	local grid = MonsterPathManager:getGrid()
	local field = MonsterPathManager:getField(monster.isAir)
	local refinery = MonsterPathManager:getRefineryPosition()
	if not grid or not field then
		return refinery, nil
	end
	local x = monster.position.X
	local z = monster.position.Z
	local index = FlowField.indexAt(grid, x, z)
	if not index or not FlowField.isEnterable(grid, index, monster.isAir) or field.costs[index] == math.huge then
		local nearest = FlowField.nearestEnterable(grid, x, z, monster.isAir, NEAREST_CELL_RINGS)
		if not nearest then
			return refinery, nil
		end
		local nearestX, nearestZ = FlowField.centerOf(grid, nearest)
		return Vector3.new(nearestX, 0, nearestZ), nil
	end
	local nextIndex = field.nextIndex[index]
	if nextIndex == 0 then
		return refinery, nil
	end
	local nextX, nextZ = FlowField.centerOf(grid, nextIndex)
	local barrier = if monster.isAir then nil else grid.barriers[nextIndex]
	if barrier then
		return Vector3.new(nextX, 0, nextZ), barrier
	end
	-- the route ahead, stopping short of any barrier on it
	local chain = { nextIndex }
	local current = nextIndex
	for _ = 2, BehaviorData.LOOKAHEAD_CELLS do
		local following = field.nextIndex[current]
		if following == 0 or (not monster.isAir and grid.barriers[following]) then
			break
		end
		table.insert(chain, following)
		current = following
	end
	-- the farthest point it can see, else the one a couple of cells on,
	-- else the next cell, which is always a straight step
	local baseX, baseZ = nextX, nextZ
	for _, candidate in { chain[#chain], chain[math.min(2, #chain)] } do
		local candidateX, candidateZ = FlowField.centerOf(grid, candidate)
		if FlowField.isLineClear(grid, monster.position.X, monster.position.Z, candidateX, candidateZ, monster.isAir) then
			baseX, baseZ = candidateX, candidateZ
			break
		end
	end
	local lane = self:lanePoint(monster, grid, field, baseX, baseZ)
	return lane or Vector3.new(baseX, 0, baseZ), nil
end

-- the route point is worked out once per cell per path version, not
-- every tick: with hundreds of monsters the line checks were the tick's
-- biggest cost. It is redone early when the monster is about to reach it
function MonsterManager:cachedWaypoint(monster: Monster): (Vector3?, string?)
	local grid = MonsterPathManager:getGrid()
	local version = MonsterPathManager:getVersion()
	local cellIndex = if grid then FlowField.indexAt(grid, monster.position.X, monster.position.Z) else nil
	local cached = monster.waypoint
	local isFresh = cached ~= nil and cellIndex ~= nil and cellIndex == monster.waypointCellIndex and version == monster.waypointPathVersion
	if isFresh and cached and grid then
		local deltaX = cached.X - monster.position.X
		local deltaZ = cached.Z - monster.position.Z
		isFresh = deltaX * deltaX + deltaZ * deltaZ > grid.cellSizeStuds * grid.cellSizeStuds
	end
	if not isFresh then
		local waypoint, barrierId = self:nextWaypoint(monster)
		monster.waypoint = waypoint
		monster.waypointBarrierId = barrierId
		monster.waypointCellIndex = cellIndex
		monster.waypointPathVersion = version
	end
	return monster.waypoint, monster.waypointBarrierId
end

function MonsterManager:face(monster: Monster, toward: Vector3)
	local offset = toward - monster.position
	if offset.X * offset.X + offset.Z * offset.Z > 1e-4 then
		monster.yawDegrees = math.deg(math.atan2(-offset.X, -offset.Z))
	end
end

-- a flat step toward a point at the monster's speed (a slow and a stun
-- come from DamageableManager), landing on the ground under the new spot
function MonsterManager:moveToward(monster: Monster, destination: Vector3, deltaSec: number)
	local speed = monster.data.SPEED_STUDS_PER_SEC * DamageableManager:getSpeedMultiplier(monster.damageableId)
	if speed <= 0 then
		return
	end
	local flatFrom = Vector3.new(monster.position.X, 0, monster.position.Z)
	local flatTo = Vector3.new(destination.X, 0, destination.Z)
	monster.tickDestination = flatTo
	local flatNew = MonsterRules.stepToward(flatFrom, flatTo, speed, deltaSec)
	self:face(monster, Vector3.new(destination.X, monster.position.Y, destination.Z))
	local groundY = MonsterPathManager:getGroundHeight(flatNew.X, flatNew.Z) or monster.groundY
	monster.groundY = groundY
	monster.position = Vector3.new(flatNew.X, self:rootY(monster, groundY), flatNew.Z)
end

-- whether a monster can walk straight to a point: the grid between them
-- is ground it may enter, with no barrier or building in the way. The last
-- cell is not checked, since a target box (a wall, a Tower) stands on it
function MonsterManager:canWalkTo(monster: Monster, point: Vector3): boolean
	local grid = MonsterPathManager:getGrid()
	if not grid then
		return true
	end
	local fromX = monster.position.X
	local fromZ = monster.position.Z
	local deltaX = point.X - fromX
	local deltaZ = point.Z - fromZ
	local distance = math.sqrt(deltaX * deltaX + deltaZ * deltaZ)
	if distance <= grid.cellSizeStuds then
		return true
	end
	local share = (distance - grid.cellSizeStuds) / distance
	return FlowField.isLineClear(grid, fromX, fromZ, fromX + deltaX * share, fromZ + deltaZ * share, monster.isAir)
end

-- one monster's tick: go for the highest-priority target it detects,
-- walking to it while out of reach (only where it can walk straight to
-- it, so nothing is chased through a wall), attacking once in reach;
-- with no target, follow its lane of the route, attacking any barrier
-- that stands in the way
function MonsterManager:stepMonster(monster: Monster, now: number, deltaSec: number)
	local data = monster.data
	local priorityOrder = self.priorityOrderByKind[monster.kind]
	if not priorityOrder then
		priorityOrder = MonsterRules.priorityOrder(data)
		self.priorityOrderByKind[monster.kind] = priorityOrder
	end
	local target = MonsterRules.pickTarget(monster.position, data, monster.reachStuds, self.candidatesByType, priorityOrder)
	if target and not MonsterRules.isInAttackRange(monster.position, data, monster.reachStuds, target) then
		-- a target it cannot walk straight to, or one it was stuck behind a
		-- crowd trying to reach, is left alone; the route goes round
		if now < monster.ignoreTargetUntil or not self:canWalkTo(monster, MonsterRules.closestPoint(monster.position, target)) then
			target = nil
		end
	end
	local waypoint: Vector3? = nil
	if not target then
		local barrierId
		waypoint, barrierId = self:cachedWaypoint(monster)
		if barrierId then
			target = self.candidateById[barrierId]
		end
	end
	if target and MonsterRules.isInAttackRange(monster.position, data, monster.reachStuds, target) then
		monster.action = Enums.MonsterAction.ENGAGED
		self:face(monster, target.position)
		if now - monster.lastAttackTime >= MonsterRules.attackIntervalSec(data, BehaviorData.DEFAULT_ATTACK_INTERVAL_SEC) then
			self:attack(monster, target, now)
		end
		return
	end
	monster.action = Enums.MonsterAction.MOVING
	local destination = waypoint
	if target and not destination then
		-- detected (or drawn by a Decoy) from further than it can hit
		destination = MonsterRules.closestPoint(monster.position, target)
	end
	if destination then
		self:moveToward(monster, destination, deltaSec)
	end
end

-- ground monsters within SEPARATION_STUDS push each other apart, found
-- through a hash of cells that size, and never onto a cell they may not enter
function MonsterManager:separate()
	local spacing = BehaviorData.SEPARATION_STUDS
	local buckets = self.separationBuckets
	local usedKeys = self.separationUsedKeys
	for _, bucketKey in usedKeys do
		table.clear(buckets[bucketKey])
	end
	table.clear(usedKeys)
	for _, monster in self.monsters do
		if monster.isDead or monster.isAir then
			continue
		end
		local bucketKey = separationKey(monster.position.X, monster.position.Z, spacing)
		local bucket = buckets[bucketKey]
		if not bucket then
			bucket = {}
			buckets[bucketKey] = bucket
		end
		if #bucket == 0 then
			table.insert(usedKeys, bucketKey)
		end
		table.insert(bucket, monster)
	end
	local grid = MonsterPathManager:getGrid()
	for _, monster in self.monsters do
		-- a monster at its target holds its ground; the crowd behind it gives
		if monster.isDead or monster.isAir or monster.action == Enums.MonsterAction.ENGAGED then
			continue
		end
		local x = monster.position.X
		local z = monster.position.Z
		local pushX = 0
		local pushZ = 0
		local column = math.floor(x / spacing)
		local row = math.floor(z / spacing)
		for columnOffset = -1, 1 do
			for rowOffset = -1, 1 do
				local bucket = buckets[(column + columnOffset + 32768) * 65536 + (row + rowOffset + 32768)]
				if not bucket then
					continue
				end
				for _, other in bucket do
					if other == monster then
						continue
					end
					local deltaX = x - other.position.X
					local deltaZ = z - other.position.Z
					local distanceSquared = deltaX * deltaX + deltaZ * deltaZ
					local minimum = math.max(spacing, (monster.reachStuds + other.reachStuds) * 0.5)
					if distanceSquared >= minimum * minimum then
						continue
					end
					if distanceSquared < 1e-6 then
						-- stacked exactly: split them by id so they part the same way every time
						deltaX = if monster.id < other.id then 1 else -1
						deltaZ = 0
						distanceSquared = 1
					end
					local distance = math.sqrt(distanceSquared)
					local overlap = (minimum - distance) / 2
					pushX += deltaX / distance * overlap
					pushZ += deltaZ / distance * overlap
				end
			end
		end
		if pushX == 0 and pushZ == 0 then
			continue
		end
		local newX = x + pushX
		local newZ = z + pushZ
		if grid then
			local index = FlowField.indexAt(grid, newX, newZ)
			if not index or not grid.walkable[index] then
				continue
			end
		end
		monster.position = Vector3.new(newX, monster.position.Y, newZ)
	end
end

-- a jammed walker stands still; one jammed JAMMED_REROUTE_SEC running
-- moves its lane to the far side of the route and follows the route for
-- a while, so a crowd stalled at a wall is walked round, not into
function MonsterManager:holdJammed(now: number, deltaSec: number)
	for _, monster in self.monsters do
		if monster.action ~= Enums.MonsterAction.MOVING or monster.isAir then
			monster.jammedSec = 0
			continue
		end
		-- the step it was allowed, so a slowed monster is not taken for a jammed one
		local destination = monster.tickDestination
		if not destination then
			continue
		end
		local stepStuds = monster.data.SPEED_STUDS_PER_SEC * DamageableManager:getSpeedMultiplier(monster.damageableId) * deltaSec
		local startOffset = destination - Vector3.new(monster.tickStartPosition.X, 0, monster.tickStartPosition.Z)
		local endOffset = destination - Vector3.new(monster.position.X, 0, monster.position.Z)
		local progress = startOffset.Magnitude - endOffset.Magnitude
		-- the last sliver onto a cell centre is short but it arrived
		local isArrived = endOffset.Magnitude < 0.05
		if isArrived or progress >= stepStuds * JAMMED_STEP_SHARE then
			monster.jammedSec = 0
			continue
		end
		monster.position = monster.tickStartPosition
		monster.jammedSec += deltaSec
		if monster.jammedSec >= BehaviorData.JAMMED_REROUTE_SEC then
			self:reroute(monster, now)
		end
	end
end

-- a new lane on the other side of the route, the target it was stuck on
-- ignored for a while, and the cached route point thrown away
function MonsterManager:reroute(monster: Monster, now: number)
	local spread = BehaviorData.LANE_SPREAD_STUDS
	local side = if monster.laneOffsetStuds >= 0 then -1 else 1
	monster.laneOffsetStuds = side * self.random:NextNumber(spread * 0.25, spread)
	monster.ignoreTargetUntil = now + BehaviorData.JAMMED_TARGET_IGNORE_SEC
	monster.jammedSec = 0
	monster.waypointCellIndex = nil
end

-- the tick's snapshot record for each monster, written in place, noting
-- whether anything a client draws changed; a move smaller than the
-- snapshot's precision is not a change
function MonsterManager:refreshRecords()
	local step = MonsterSnapshotCodec.POSITION_STEP_STUDS
	for _, monster in self.monsters do
		local record = monster.record
		local hpShare = DamageableManager:getHpShare(monster.damageableId)
		local isSlowed = DamageableManager:getSpeedMultiplier(monster.damageableId) < 1
		local isBurning = DamageableManager:isBurning(monster.damageableId)
		local moved = monster.position - record.position
		local isChanged = math.abs(moved.X) >= step
			or math.abs(moved.Y) >= step
			or math.abs(moved.Z) >= step
			or math.abs((monster.yawDegrees - record.yawDegrees + 180) % 360 - 180) >= 2
			or record.hpShare ~= hpShare
			or record.action ~= monster.action
			or record.attackCounter ~= monster.attackCounter
			or record.isSlowed ~= isSlowed
			or record.isBurning ~= isBurning
		monster.wasChangedLastTick = monster.isChanged
		monster.isChanged = isChanged
		if not isChanged then
			continue
		end
		record.position = monster.position
		record.yawDegrees = monster.yawDegrees
		record.hpShare = hpShare
		record.action = monster.action
		record.attackCounter = monster.attackCounter
		record.isSlowed = isSlowed
		record.isBurning = isBurning
		DamageableManager:setCFrame(monster.damageableId, self:hitBoxCFrame(monster))
	end
end

-- each player gets a moving monster every tick when it is near them,
-- every MID_EVERY_TICKS ticks at middle distance, and otherwise (far, or
-- standing still) every FAR_EVERY_TICKS ticks, picked by id so the load
-- spreads evenly over the ticks
function MonsterManager:sendSnapshots(now: number)
	local event = self.snapshotEvent
	if not event or #self.monsters == 0 then
		return
	end
	local nearSquared = BehaviorData.NEAR_DISTANCE_STUDS * BehaviorData.NEAR_DISTANCE_STUDS
	local midSquared = BehaviorData.MID_DISTANCE_STUDS * BehaviorData.MID_DISTANCE_STUDS
	local midEvery = BehaviorData.MID_EVERY_TICKS
	local midPhase = self.tickCount % midEvery
	local farEvery = BehaviorData.FAR_EVERY_TICKS
	local farPhase = self.tickCount % farEvery
	for _, player in GameController:getReadyPlayers() do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local viewer = if root and root:IsA("BasePart") then root.Position else nil
		local records = {}
		for _, monster in self.monsters do
			local isDue = monster.id % farEvery == farPhase
			if not isDue and viewer and (monster.isChanged or monster.wasChangedLastTick) then
				local deltaX = monster.position.X - viewer.X
				local deltaZ = monster.position.Z - viewer.Z
				local distanceSquared = deltaX * deltaX + deltaZ * deltaZ
				isDue = distanceSquared <= nearSquared or (distanceSquared <= midSquared and monster.id % midEvery == midPhase)
			end
			if isDue then
				table.insert(records, monster.record)
			end
		end
		for _, packet in MonsterSnapshotCodec.encode(records, now, BehaviorData.SNAPSHOT_MAX_BYTES) do
			event:FireClient(player, packet)
		end
	end
end

function MonsterManager:flushNotifies()
	if #self.pendingSpawnIds > 0 then
		local ids = {}
		local kinds = {}
		local damageableIds = {}
		for _, id in self.pendingSpawnIds do
			local monster = self.monsterById[id]
			if monster then
				table.insert(ids, id)
				table.insert(kinds, monster.kind)
				table.insert(damageableIds, monster.damageableId)
			end
		end
		self.pendingSpawnIds = {}
		if #ids > 0 then
			NetManager:notifyAllClients(NetEventNames.NOTIFY_MONSTERS_SPAWNED, {
				ids = ids,
				kinds = kinds,
				damageableIds = damageableIds,
			})
		end
	end
	if #self.pendingDeathIds > 0 then
		NetManager:notifyAllClients(NetEventNames.NOTIFY_MONSTERS_DIED, {
			ids = self.pendingDeathIds,
		})
		self.pendingDeathIds = {}
	end
end

function MonsterManager:publishStats(now: number, stepSec: number)
	self.stepSecTotal += stepSec
	self.stepCount += 1
	if now - self.lastStatsTime < STATS_INTERVAL_SEC then
		return
	end
	local averageMs = if self.stepCount > 0 then self.stepSecTotal / self.stepCount * 1000 else 0
	SplendidReplicationManager:setGameMetadata(Attributes.MONSTER_ALIVE_COUNT, #self.monsters)
	SplendidReplicationManager:setGameMetadata(Attributes.MONSTER_STEP_MS, math.floor(averageMs * 100 + 0.5) / 100)
	self.lastStatsTime = now
	self.stepSecTotal = 0
	self.stepCount = 0
end

function MonsterManager:tick(deltaSec: number)
	local startTime = workspace:GetServerTimeNow()
	self.tickCount += 1
	-- a Tower may have killed some since the last tick
	self:sweepDead()
	MonsterPathManager:recomputeIfNeeded(startTime)
	self:buildCandidates()
	for _, monster in self.monsters do
		if not monster.isDead then
			monster.tickStartPosition = monster.position
			monster.tickDestination = nil
			self:stepMonster(monster, startTime, deltaSec)
		end
	end
	self:landProjectiles(startTime)
	self:sweepDead()
	self:separate()
	self:holdJammed(startTime, deltaSec)
	self:refreshRecords()
	self:flushNotifies()
	self:sendSnapshots(startTime)
	local endTime = workspace:GetServerTimeNow()
	self:publishStats(endTime, endTime - startTime)
end

-- a late joiner (or a reset) learns every live monster at once
function MonsterManager:onPlayerReady(player: Player)
	if #self.monsters == 0 then
		return
	end
	local ids = {}
	local kinds = {}
	local damageableIds = {}
	for _, monster in self.monsters do
		table.insert(ids, monster.id)
		table.insert(kinds, monster.kind)
		table.insert(damageableIds, monster.damageableId)
	end
	NetManager:notifyClient(player, NetEventNames.NOTIFY_MONSTERS_SPAWNED, {
		ids = ids,
		kinds = kinds,
		damageableIds = damageableIds,
	})
end

function MonsterManager:onRunStarted()
	self:killAll()
	self:flushNotifies()
end

function MonsterManager:init()
	-- a flier without a height would walk the ground, so say so at startup
	for kind, data in ROSTER_BY_KIND do
		if MonsterRules.isAir(data) and typeof(data.FLIGHT_HEIGHT_STUDS) ~= "number" then
			warn(`MonsterManager: {Enums.getName(Enums.MonsterKind, kind)} is an AIR monster with no FLIGHT_HEIGHT_STUDS in GameData/Monsters/Roster`)
		end
	end
	local snapshotEvent = Instance.new("UnreliableRemoteEvent")
	snapshotEvent.Name = Constants.MONSTER_SNAPSHOT_EVENT_NAME
	snapshotEvent.Parent = ReplicatedStorage
	self.snapshotEvent = snapshotEvent
	SplendidReplicationManager:setGameMetadata(Attributes.MONSTER_VISUAL_CATALOG, MonsterRules.encodeVisualCatalog(ROSTER_BY_KIND))
	SplendidReplicationManager:setGameMetadata(Attributes.MONSTER_INTERPOLATION_DELAY_SEC, BehaviorData.INTERPOLATION_DELAY_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.MONSTER_DRAW_BUDGETS, MonsterRules.encodeDrawBudgets(BehaviorData.DRAW_BUDGETS, BehaviorData.LOW_BUDGET_MAX_QUALITY_LEVEL))
	SplendidReplicationManager:setGameMetadata(Attributes.MONSTER_ALIVE_COUNT, 0)
	SplendidReplicationManager:setGameMetadata(Attributes.MONSTER_STEP_MS, 0)
	GameController:registerPlaceManager(self)
	local tickSec = 1 / BehaviorData.TICK_RATE_HZ
	RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self.tickAccumulatorSec += deltaSec
			if self.tickAccumulatorSec < tickSec then
				return
			end
			-- a long frame runs one longer tick, never a burst of ticks
			local stepSec = math.min(self.tickAccumulatorSec, tickSec * 3)
			self.tickAccumulatorSec = 0
			self:tick(stepSec)
		end
	)
end

function MonsterManager.new(): MonsterManager
	local self = setmetatable({}, MonsterManager) :: MonsterManager
	self.monsters = {}
	self.monsterById = {}
	self.monsterByDamageableId = {}
	self.nextNetworkId = 1
	self.projectiles = {}
	self.tickAccumulatorSec = 0
	self.tickCount = 0
	self.pendingSpawnIds = {}
	self.pendingDeathIds = {}
	self.metricsByModel = {}
	self.warnedModels = {}
	self.snapshotEvent = nil
	self.candidatesByType = MonsterRules.emptyCandidates()
	self.candidateById = {}
	self.playerByCandidateId = {}
	self.lastStatsTime = 0
	self.stepSecTotal = 0
	self.stepCount = 0
	self.lastDownWarnTime = 0
	self.killedHandlers = {}
	self.random = Random.new()
	self.priorityOrderByKind = {}
	self.separationBuckets = {}
	self.separationUsedKeys = {}
	return self
end

return MonsterManager.new()
