--!strict

-- What a standing Tower does (GDD "Tower Types"), M27. Every Heartbeat,
-- each Tower PlacementManager holds picks a target from DamageableManager
-- by its Target Priority (pure TowerRules), turns its turret to face it,
-- and attacks in its kind's shape: a single shot every fire interval, a
-- cone that breathes for the flame length and rests, or a bolt that
-- chains from target to target. Damage, slows, and stuns go through
-- DamageableManager; the Tower's owner is the attacker so a kill credits
-- them. Nothing here is an instance: the yaw and whether a cone is
-- breathing are published on the placement's shadow for the clients to
-- turn and draw from, and a shot or bolt is a NotifyTowerFired broadcast
-- naming the targets it hit, so every client can draw the tracer or the
-- lightning between the right points. Numbers come from
-- GameData/Defenses/Towers through the placement catalogue.
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PlacementRules = require("@game/ReplicatedStorage/Shared/PlacementRules")
local TowerRules = require("@game/ReplicatedStorage/Shared/TowerRules")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")
local TowersData = require("@game/ServerScriptService/GameData/Defenses/Towers")
local NetManager = require(script.Parent.Parent.Server.NetManager)
local DamageableManager = require(script.Parent.DamageableManager)
local PlacementManager = require(script.Parent.PlacementManager)

local TowerBehaviorManager = {}
TowerBehaviorManager.__index = TowerBehaviorManager

type TowerState = {
	yawDegrees: number,
	publishedYawDegrees: number,
	lastFireTime: number?,
	-- a cone: breathing until activeUntil, then resting until restUntil
	activeUntil: number,
	restUntil: number,
	lastTickTime: number,
	isAttacking: boolean,
}

export type TowerBehaviorManager = typeof(setmetatable(
	{} :: {
		stateById: { [string]: TowerState },
	},
	TowerBehaviorManager
))

local DEFAULT_CONE_ANGLE_DEGREES = 60
local DEFAULT_TICK_INTERVAL_SEC = 0.25

function TowerBehaviorManager:getState(id: string): TowerState
	local state = self.stateById[id]
	if not state then
		state = {
			yawDegrees = 0,
			publishedYawDegrees = 0,
			lastFireTime = nil,
			activeUntil = 0,
			restUntil = 0,
			lastTickTime = 0,
			isAttacking = false,
		}
		self.stateById[id] = state
	end
	return state
end

-- the turret snaps to face the target here; the client eases it over
function TowerBehaviorManager:face(placement: PlacementManager.Placement, state: TowerState, targetPosition: Vector3)
	state.yawDegrees = TowerRules.yawDegreesToward(placement.cframe, targetPosition)
	local rounded = math.floor(state.yawDegrees + 0.5)
	if rounded ~= state.publishedYawDegrees then
		state.publishedYawDegrees = rounded
		placement.shadow:SetAttribute(Attributes.PLACEMENT_YAW_DEGREES, rounded)
	end
end

function TowerBehaviorManager:setAttacking(placement: PlacementManager.Placement, state: TowerState, isAttacking: boolean)
	if state.isAttacking == isAttacking then
		return
	end
	state.isAttacking = isAttacking
	placement.shadow:SetAttribute(Attributes.PLACEMENT_IS_ATTACKING, isAttacking)
end

function TowerBehaviorManager:notifyFired(placement: PlacementManager.Placement, hitIds: { string })
	NetManager:notifyAllClients(NetEventNames.NOTIFY_TOWER_FIRED, {
		id = placement.id,
		hitIds = hitIds,
	})
end

function TowerBehaviorManager:stepSingle(placement: PlacementManager.Placement, state: TowerState, stats: PlacementRules.TowerLevelStats, behavior: PlacementRules.TowerBehavior, origin: Vector3, reach: number, targets: { DamageableManager.Target }, now: number)
	local target = TowerRules.pickTarget(origin, reach, placement.targetPriority, targets, behavior)
	if not target then
		return
	end
	self:face(placement, state, target.position)
	if not WeaponRules.canFire(state.lastFireTime, now, stats.FIRE_INTERVAL_SEC or 1) then
		return
	end
	state.lastFireTime = now
	DamageableManager:damage(target.id, stats.DAMAGE, placement.owner)
	self:notifyFired(placement, { target.id })
end

-- a cone breathes for the flame length at whatever it faces, ticking
-- damage and slow onto everything inside, then rests
function TowerBehaviorManager:stepCone(placement: PlacementManager.Placement, state: TowerState, stats: PlacementRules.TowerLevelStats, behavior: PlacementRules.TowerBehavior, origin: Vector3, reach: number, targets: { DamageableManager.Target }, now: number)
	local target = TowerRules.pickTarget(origin, reach, placement.targetPriority, targets, behavior)
	if target then
		self:face(placement, state, target.position)
	end
	if now < state.activeUntil then
		local tickInterval = behavior.TICK_INTERVAL_SEC or DEFAULT_TICK_INTERVAL_SEC
		if now - state.lastTickTime < tickInterval then
			return
		end
		state.lastTickTime = now
		local direction = TowerRules.directionFromYaw(placement.cframe, state.yawDegrees)
		local coneAngle = behavior.CONE_ANGLE_DEGREES or DEFAULT_CONE_ANGLE_DEGREES
		for _, hit in TowerRules.targetsInCone(origin, direction, reach, coneAngle, targets, behavior) do
			if stats.DAMAGE > 0 then
				DamageableManager:damage(hit.id, stats.DAMAGE, placement.owner)
			end
			local slowShare = stats.SLOW_SHARE
			if slowShare and slowShare > 0 then
				DamageableManager:applySlow(hit.id, slowShare, stats.SLOW_SEC or 0)
			end
		end
		return
	end
	self:setAttacking(placement, state, false)
	if not target or now < state.restUntil then
		return
	end
	local flameSec = stats.FLAME_SEC or behavior.FLAME_SEC or 0
	if flameSec <= 0 then
		return
	end
	state.activeUntil = now + flameSec
	state.restUntil = state.activeUntil + (behavior.REST_SEC or 0)
	-- the first tick lands at once
	state.lastTickTime = 0
	self:setAttacking(placement, state, true)
end

function TowerBehaviorManager:stepChain(placement: PlacementManager.Placement, state: TowerState, stats: PlacementRules.TowerLevelStats, behavior: PlacementRules.TowerBehavior, origin: Vector3, reach: number, targets: { DamageableManager.Target }, now: number)
	if not WeaponRules.canFire(state.lastFireTime, now, stats.FIRE_INTERVAL_SEC or 1) then
		return
	end
	local target = TowerRules.pickTarget(origin, reach, placement.targetPriority, targets, behavior)
	if not target then
		return
	end
	state.lastFireTime = now
	local chain = TowerRules.chainTargets(target, targets, stats.CHAIN_COUNT or 0, behavior.CHAIN_JUMP_STUDS or 0, behavior)
	local hitIds = {}
	for _, hit in chain do
		table.insert(hitIds, hit.id)
		local stunSec = behavior.STUN_SEC or 0
		if stunSec > 0 then
			DamageableManager:applyStun(hit.id, stunSec)
		end
		DamageableManager:damage(hit.id, stats.DAMAGE, placement.owner)
	end
	self:notifyFired(placement, hitIds)
end

function TowerBehaviorManager:step()
	local now = workspace:GetServerTimeNow()
	local catalog = PlacementManager:getCatalog()
	local targets: { DamageableManager.Target }? = nil
	local seen = {}
	for _, placement in PlacementManager:getPlacements() do
		if placement.placementKind ~= Enums.PlacementKind.TOWER then
			continue
		end
		local tower = catalog.towers[placement.typeKind]
		local behavior = if tower then tower.BEHAVIOR else nil
		if not tower or not behavior then
			continue
		end
		seen[placement.id] = true
		-- one snapshot a frame, taken only when a Tower stands to use it
		if not targets then
			targets = DamageableManager:getTargets()
		end
		local state = self:getState(placement.id)
		local stats = PlacementRules.towerStats(tower, placement.level)
		-- the range the kind fights at, measured from its edge (TowerRules.reachStuds)
		local reach = TowerRules.reachStuds(stats.RANGE_STUDS, tower.FOOTPRINT_CELLS, catalog.cellSizeStuds)
		local origin = TowerRules.muzzlePosition(placement.cframe, TowersData.MUZZLE_HEIGHT_STUDS)
		if behavior.ATTACK == Enums.TowerAttack.CONE then
			self:stepCone(placement, state, stats, behavior, origin, reach, targets :: { DamageableManager.Target }, now)
		elseif behavior.ATTACK == Enums.TowerAttack.CHAIN then
			self:stepChain(placement, state, stats, behavior, origin, reach, targets :: { DamageableManager.Target }, now)
		else
			self:stepSingle(placement, state, stats, behavior, origin, reach, targets :: { DamageableManager.Target }, now)
		end
	end
	-- a sold or destroyed Tower takes its state with it
	for id in self.stateById do
		if not seen[id] then
			self.stateById[id] = nil
		end
	end
end

function TowerBehaviorManager:init()
	RunService.Heartbeat:Connect(
		function()
			self:step()
		end
	)
end

function TowerBehaviorManager.new(): TowerBehaviorManager
	local self = setmetatable({}, TowerBehaviorManager) :: TowerBehaviorManager
	self.stateById = {}
	return self
end

return TowerBehaviorManager.new()
