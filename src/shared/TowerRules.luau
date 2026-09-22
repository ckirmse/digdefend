--!strict

-- Pure rules for how a Tower fights (GDD "Tower Types"), M27: which
-- targets a kind may hit, which one it picks by its Target Priority,
-- what a cone in front of the turret covers, how a bolt chains from
-- target to target, and the turret yaw that faces a target. The server
-- (TowerBehaviorManager) decides with these; the client turns and draws
-- from the yaw the server publishes. Targets are snapshots
-- (DamageableManager.Target shape) so this never touches an instance.
local Enums = require(script.Parent.Enums)
local PlacementRules = require(script.Parent.PlacementRules)

local TowerRules = {}

export type Target = {
	id: string,
	position: Vector3,
	hp: number,
	maxHp: number,
	isAirborne: boolean,
}

-- Range is measured from the edge of the Tower's footprint, not its
-- centre (decided 2026-09-22), so the number in the menu means how far
-- past the Tower it reaches whatever its size; this is the circle the
-- server tests and the build preview draws
function TowerRules.reachStuds(rangeStuds: number, footprintCells: { number }, cellSizeStuds: number): number
	return rangeStuds + math.max(footprintCells[1], footprintCells[2]) * cellSizeStuds / 2
end

function TowerRules.canTarget(behavior: PlacementRules.TowerBehavior, target: Target): boolean
	return if target.isAirborne then behavior.TARGETS_AIR else behavior.TARGETS_GROUND
end

function TowerRules.isInRange(origin: Vector3, target: Target, rangeStuds: number): boolean
	return (target.position - origin).Magnitude <= rangeStuds
end

-- the target the priority prefers; distance ties and HP ties fall to the
-- earlier target, so callers pass a stable order
function TowerRules.pickTarget(origin: Vector3, rangeStuds: number, priority: number, targets: { Target }, behavior: PlacementRules.TowerBehavior): Target?
	local best: Target? = nil
	local bestScore = 0
	for _, target in targets do
		if not TowerRules.canTarget(behavior, target) or not TowerRules.isInRange(origin, target, rangeStuds) then
			continue
		end
		local score: number
		if priority == Enums.TargetPriority.FURTHEST then
			score = (target.position - origin).Magnitude
		elseif priority == Enums.TargetPriority.STRONGEST then
			score = target.hp
		elseif priority == Enums.TargetPriority.WEAKEST then
			score = -target.hp
		else
			score = -(target.position - origin).Magnitude
		end
		if best == nil or score > bestScore then
			best = target
			bestScore = score
		end
	end
	return best
end

-- everything the kind may hit within the range and within half the cone
-- angle of the direction
function TowerRules.targetsInCone(origin: Vector3, unitDirection: Vector3, rangeStuds: number, coneAngleDegrees: number, targets: { Target }, behavior: PlacementRules.TowerBehavior): { Target }
	local hits = {}
	local cosHalfAngle = math.cos(math.rad(coneAngleDegrees / 2))
	for _, target in targets do
		if not TowerRules.canTarget(behavior, target) then
			continue
		end
		local offset = target.position - origin
		local distance = offset.Magnitude
		if distance > rangeStuds or distance < 1e-6 then
			continue
		end
		if offset.Unit:Dot(unitDirection) >= cosHalfAngle then
			table.insert(hits, target)
		end
	end
	return hits
end

-- the bolt's path: the first target, then up to chainCount more, each the
-- nearest untouched target within jumpStuds of the last
function TowerRules.chainTargets(first: Target, targets: { Target }, chainCount: number, jumpStuds: number, behavior: PlacementRules.TowerBehavior): { Target }
	local chain = { first }
	local hitIds = { [first.id] = true }
	local last = first
	for _ = 1, chainCount do
		local nearest: Target? = nil
		local nearestDistance = jumpStuds
		for _, target in targets do
			if hitIds[target.id] or not TowerRules.canTarget(behavior, target) then
				continue
			end
			local distance = (target.position - last.position).Magnitude
			if distance <= nearestDistance and (nearest == nil or distance < nearestDistance) then
				nearest = target
				nearestDistance = distance
			end
		end
		if not nearest then
			break
		end
		table.insert(chain, nearest)
		hitIds[nearest.id] = true
		last = nearest
	end
	return chain
end

-- the turret yaw, in degrees about the base's up axis, that points the
-- model's -Z (the barrel at rest) at a world position
function TowerRules.yawDegreesToward(basePose: CFrame, targetPosition: Vector3): number
	local localPosition = basePose:PointToObjectSpace(targetPosition)
	if math.abs(localPosition.X) < 1e-6 and math.abs(localPosition.Z) < 1e-6 then
		return 0
	end
	return math.deg(math.atan2(-localPosition.X, -localPosition.Z))
end

-- the barrel's world direction at a yaw, flat along the base
function TowerRules.directionFromYaw(basePose: CFrame, yawDegrees: number): Vector3
	return basePose:VectorToWorldSpace((CFrame.Angles(0, math.rad(yawDegrees), 0) * CFrame.new(0, 0, -1)).Position)
end

function TowerRules.muzzlePosition(basePose: CFrame, muzzleHeightStuds: number): Vector3
	return basePose:PointToWorldSpace(Vector3.new(0, muzzleHeightStuds, 0))
end

-- degrees to turn from one yaw to another, the short way round
function TowerRules.yawDelta(fromDegrees: number, toDegrees: number): number
	return (toDegrees - fromDegrees + 180) % 360 - 180
end

return TowerRules
