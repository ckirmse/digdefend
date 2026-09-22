--!strict

-- Pure rules for what a Trap does (GDD "Trap Types"), M27: when an enemy
-- touches a Trap (its footprint overlaps the Trap's cells, seen from
-- above), which barrier stands in a walker's way, and a Spike Trap's
-- Down, Up, Recharging clock. The server (TrapBehaviorManager) decides
-- with these; the client draws from the state the server publishes.
local Enums = require(script.Parent.Enums)

local TrapRules = {}

export type Box = {
	id: string,
	cframe: CFrame,
	size: Vector3,
}

-- seen from above, the target is a circle of its wider half-extent and
-- the Trap a rectangle in its own frame; touching is their overlap
function TrapRules.isTouching(targetPosition: Vector3, targetSize: Vector3, trapCFrame: CFrame, trapSize: Vector3): boolean
	local radius = math.max(targetSize.X, targetSize.Z) / 2
	local localPosition = trapCFrame:PointToObjectSpace(targetPosition)
	local dx = math.max(math.abs(localPosition.X) - trapSize.X / 2, 0)
	local dz = math.max(math.abs(localPosition.Z) - trapSize.Z / 2, 0)
	return dx * dx + dz * dz <= radius * radius
end

-- the first barrier the target would stand on, or nil; the caller keeps
-- flyers out of this
function TrapRules.findBlocker(targetPosition: Vector3, targetSize: Vector3, barriers: { Box }): string?
	for _, barrier in barriers do
		if TrapRules.isTouching(targetPosition, targetSize, barrier.cframe, barrier.size) then
			return barrier.id
		end
	end
	return nil
end

-- every target whose centre is within the radius of a point
function TrapRules.targetsWithin(point: Vector3, radiusStuds: number, targets: { { id: string, position: Vector3 } }): { string }
	local ids = {}
	for _, target in targets do
		if (target.position - point).Magnitude <= radiusStuds then
			table.insert(ids, target.id)
		end
	end
	return ids
end

-- where a Spike Trap's clock stands: Up for upSec after the trigger, then
-- Recharging for rechargeSec, then Down and ready again
function TrapRules.spikeState(triggeredTime: number?, upSec: number, rechargeSec: number, now: number): number
	if triggeredTime == nil then
		return Enums.TrapState.DOWN
	end
	local elapsed = now - triggeredTime
	if elapsed < upSec then
		return Enums.TrapState.UP
	elseif elapsed < upSec + rechargeSec then
		return Enums.TrapState.RECHARGING
	end
	return Enums.TrapState.DOWN
end

return TrapRules
