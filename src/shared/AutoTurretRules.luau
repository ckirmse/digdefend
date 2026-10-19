--!strict

-- Pure rules for the Auto Turret, the Gunner's gadget (GDD "Classes",
-- M66): where it may stand and how far from the player it is placed. A
-- destroyed turret is simply lost until dawn, which needs no rule. The
-- server decides with these and the
-- client previews with the same maths, so the ghost turns red exactly
-- where the server would refuse. Numbers come from GameData/Gadgets/AutoTurret
-- through the caller; nothing here reads GameData.
local AutoTurretRules = {}

-- why a spot is refused; the client shows one line for all of them
AutoTurretRules.Problem = {
	NOT_GROUND = "notGround",
	TOO_STEEP = "tooSteep",
	UNREACHABLE = "unreachable",
	ELEVATED = "elevated",
	TOO_FAR = "tooFar",
}

-- a surface under one of these is a building, not ground (Tags.* names,
-- resolved by the caller's hasTag); a turret sits only on the ground
-- monsters walk, never on a wall, a tower, a post, or another turret
AutoTurretRules.BLOCKING_TAGS = {
	"Structure",
	"Placement",
	"Damageable",
	"Post",
	"PostWeapon",
	"Tombstone",
	"AutoTurret",
	"Helicopter",
}

-- the first blocking tag on the instance or any ancestor, or nil for
-- plain ground; hasTag answers whether one instance carries one tag
function AutoTurretRules.findBlockingTag(instance: Instance?, hasTag: (instance: Instance, tag: string) -> boolean): string?
	local current = instance
	while current and current ~= game do
		for _, tag in AutoTurretRules.BLOCKING_TAGS do
			if hasTag(current, tag) then
				return tag
			end
		end
		current = current.Parent
	end
	return nil
end

-- the one answer the placement needs: nil for a sound spot, else the
-- problem. isGround is whether the ray met plain ground (not a building,
-- not a body); isReachable is whether monsters can walk there; isAtGroundLevel
-- is whether the spot is the ground itself and not a roof over it
function AutoTurretRules.placementProblem(isGround: boolean, groundNormalY: number, minGroundNormalY: number, isReachable: boolean, isAtGroundLevel: boolean): string?
	if not isGround then
		return AutoTurretRules.Problem.NOT_GROUND
	end
	if groundNormalY < minGroundNormalY then
		return AutoTurretRules.Problem.TOO_STEEP
	end
	if not isReachable then
		return AutoTurretRules.Problem.UNREACHABLE
	end
	if not isAtGroundLevel then
		return AutoTurretRules.Problem.ELEVATED
	end
	return nil
end

-- the server's roof test: the spot's height against the path grid's
-- ground height for that cell, within a tolerance for steps and slopes
function AutoTurretRules.isAtGroundLevel(spotY: number, groundY: number?, toleranceStuds: number): boolean
	if groundY == nil then
		return false
	end
	return math.abs(spotY - groundY) <= toleranceStuds
end

-- the spot the ghost hangs over: a fixed distance ahead of the player,
-- flat, so looking up or down never moves it
function AutoTurretRules.ghostOrigin(rootCFrame: CFrame, distanceStuds: number): Vector3
	local forward = Vector3.new(rootCFrame.LookVector.X, 0, rootCFrame.LookVector.Z)
	if forward.Magnitude < 1e-6 then
		forward = Vector3.new(0, 0, -1)
	end
	return rootCFrame.Position + forward.Unit * distanceStuds
end

-- the server's reach check, flat, with slack for a step taken since the
-- client measured
function AutoTurretRules.isWithinPlaceDistance(rootPosition: Vector3, position: Vector3, distanceStuds: number, toleranceStuds: number): boolean
	local flat = Vector3.new(position.X - rootPosition.X, 0, position.Z - rootPosition.Z)
	return flat.Magnitude <= distanceStuds + toleranceStuds
end

-- the turret's facing: the player's own, so it starts looking where they look
function AutoTurretRules.yawDegreesOf(rootCFrame: CFrame): number
	local look = rootCFrame.LookVector
	return math.deg(math.atan2(-look.X, -look.Z))
end

-- the HP a picked-up turret brings to the next one placed: what it had,
-- never below one point, never above the maximum
function AutoTurretRules.carriedHp(hp: number, maxHp: number): number
	return math.clamp(math.floor(hp + 0.5), 1, maxHp)
end

return AutoTurretRules
