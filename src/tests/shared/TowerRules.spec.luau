-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local TowerRules = require(game:GetService("ReplicatedStorage").Shared.TowerRules)

local GROUND_ONLY = {
	ATTACK = Enums.TowerAttack.SINGLE,
	TARGETS_GROUND = true,
	TARGETS_AIR = false,
	HAS_TURRET = true,
}
local AIR_ONLY = {
	ATTACK = Enums.TowerAttack.SINGLE,
	TARGETS_GROUND = false,
	TARGETS_AIR = true,
	HAS_TURRET = true,
}
local BOTH = {
	ATTACK = Enums.TowerAttack.CHAIN,
	TARGETS_GROUND = true,
	TARGETS_AIR = true,
	HAS_TURRET = false,
}

local function target(id, x, z, hp, isAirborne)
	return {
		id = id,
		position = Vector3.new(x, 0, z),
		hp = hp,
		maxHp = 100,
		isAirborne = isAirborne == true,
	}
end

local ORIGIN = Vector3.zero

describe(
	"TowerRules.reachStuds",
	function()
		it(
			"adds half the footprint's longer side to the range",
			function()
				expect(TowerRules.reachStuds(18, { 4, 4 }, 4)).toBe(26)
				expect(TowerRules.reachStuds(10, { 2, 1 }, 4)).toBe(14)
			end
		)
	end
)

describe(
	"TowerRules.pickTarget",
	function()
		local targets = {
			target("near", 0, -10, 80),
			target("far", 0, -30, 20),
			target("out", 0, -60, 5),
			target("flyer", 0, -5, 50, true),
		}
		it(
			"picks by priority within range and skips what it cannot hit",
			function()
				expect(TowerRules.pickTarget(ORIGIN, 40, Enums.TargetPriority.CLOSEST, targets, GROUND_ONLY).id).toBe("near")
				expect(TowerRules.pickTarget(ORIGIN, 40, Enums.TargetPriority.FURTHEST, targets, GROUND_ONLY).id).toBe("far")
				expect(TowerRules.pickTarget(ORIGIN, 40, Enums.TargetPriority.STRONGEST, targets, GROUND_ONLY).id).toBe("near")
				expect(TowerRules.pickTarget(ORIGIN, 40, Enums.TargetPriority.WEAKEST, targets, GROUND_ONLY).id).toBe("far")
				expect(TowerRules.pickTarget(ORIGIN, 40, Enums.TargetPriority.CLOSEST, targets, AIR_ONLY).id).toBe("flyer")
			end
		)
		it(
			"finds nothing out of range",
			function()
				expect(TowerRules.pickTarget(ORIGIN, 5, Enums.TargetPriority.CLOSEST, targets, GROUND_ONLY)).toBeNil()
			end
		)
	end
)

describe(
	"TowerRules.targetsInCone",
	function()
		it(
			"keeps what is inside the half angle and the range",
			function()
				local targets = {
					target("ahead", 0, -10, 1),
					target("edge", 5, -10, 1),
					target("side", 10, 0, 1),
					target("beyond", 0, -30, 1),
				}
				local hits = TowerRules.targetsInCone(ORIGIN, -Vector3.zAxis, 20, 60, targets, GROUND_ONLY)
				expect(#hits).toBe(2)
				expect(hits[1].id).toBe("ahead")
				expect(hits[2].id).toBe("edge")
			end
		)
	end
)

describe(
	"TowerRules.chainTargets",
	function()
		it(
			"jumps to the nearest untouched target within the jump distance",
			function()
				local first = target("a", 0, 0, 1)
				local targets = {
					first,
					target("b", 5, 0, 1),
					target("c", 9, 0, 1),
					target("d", 30, 0, 1),
					target("flyer", 12, 0, 1, true),
				}
				local chain = TowerRules.chainTargets(first, targets, 4, 6, BOTH)
				expect(#chain).toBe(4)
				expect(chain[2].id).toBe("b")
				expect(chain[3].id).toBe("c")
				expect(chain[4].id).toBe("flyer")
			end
		)
		it(
			"stops at the chain count",
			function()
				local first = target("a", 0, 0, 1)
				local chain = TowerRules.chainTargets(first, { first, target("b", 1, 0, 1), target("c", 2, 0, 1) }, 1, 6, BOTH)
				expect(#chain).toBe(2)
			end
		)
	end
)

describe(
	"TowerRules yaw",
	function()
		it(
			"faces the model's -Z at yaw 0 and turns to a target",
			function()
				local pose = CFrame.new(0, 0, 0)
				expect(TowerRules.yawDegreesToward(pose, Vector3.new(0, 0, -10))).toBeCloseTo(0, 5)
				expect(TowerRules.yawDegreesToward(pose, Vector3.new(-10, 0, 0))).toBeCloseTo(90, 5)
				expect(TowerRules.yawDegreesToward(pose, Vector3.new(10, 0, 0))).toBeCloseTo(-90, 5)
				local direction = TowerRules.directionFromYaw(pose, 90)
				expect(direction.X).toBeCloseTo(-1, 5)
				expect(direction.Z).toBeCloseTo(0, 5)
			end
		)
		it(
			"turns with the base",
			function()
				local pose = CFrame.Angles(0, math.rad(90), 0)
				-- the base's -Z now points along world -X
				expect(TowerRules.yawDegreesToward(pose, Vector3.new(-10, 0, 0))).toBeCloseTo(0, 5)
			end
		)
		it(
			"measures the short way round",
			function()
				expect(TowerRules.yawDelta(170, -170)).toBeCloseTo(20, 5)
				expect(TowerRules.yawDelta(-170, 170)).toBeCloseTo(-20, 5)
			end
		)
		it(
			"lifts the muzzle above the base",
			function()
				local muzzle = TowerRules.muzzlePosition(CFrame.new(5, 1, 5), 3)
				expect(muzzle.Y).toBeCloseTo(4, 5)
			end
		)
	end
)
