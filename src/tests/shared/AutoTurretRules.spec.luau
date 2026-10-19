-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local AutoTurretRules = require(game:GetService("ReplicatedStorage").Shared.AutoTurretRules)

describe(
	"AutoTurretRules.placementProblem",
	function()
		it(
			"accepts flat reachable ground and names each refusal",
			function()
				expect(AutoTurretRules.placementProblem(true, 1, 0.8, true, true)).toBeNil()
				expect(AutoTurretRules.placementProblem(true, 0.8, 0.8, true, true)).toBeNil()
				expect(AutoTurretRules.placementProblem(false, 1, 0.8, true, true)).toBe(AutoTurretRules.Problem.NOT_GROUND)
				expect(AutoTurretRules.placementProblem(true, 0.5, 0.8, true, true)).toBe(AutoTurretRules.Problem.TOO_STEEP)
				expect(AutoTurretRules.placementProblem(true, 1, 0.8, false, true)).toBe(AutoTurretRules.Problem.UNREACHABLE)
				expect(AutoTurretRules.placementProblem(true, 1, 0.8, true, false)).toBe(AutoTurretRules.Problem.ELEVATED)
			end
		)

		it(
			"calls a roof over walkable ground elevated, and a step on it ground",
			function()
				expect(AutoTurretRules.isAtGroundLevel(0.5, 0, 3)).toBe(true)
				expect(AutoTurretRules.isAtGroundLevel(12, 0, 3)).toBe(false)
				expect(AutoTurretRules.isAtGroundLevel(0, nil, 3)).toBe(false)
			end
		)
	end
)

describe(
	"AutoTurretRules.findBlockingTag",
	function()
		it(
			"finds a blocking tag on the instance or an ancestor and none on plain ground",
			function()
				local wall = Instance.new("Folder")
				local brick = Instance.new("Part")
				brick.Parent = wall
				local tagsByInstance = { [wall] = "Structure" }
				local function hasTag(instance: Instance, tag: string): boolean
					return tagsByInstance[instance] == tag
				end
				expect(AutoTurretRules.findBlockingTag(brick, hasTag)).toBe("Structure")
				expect(AutoTurretRules.findBlockingTag(Instance.new("Part"), hasTag)).toBeNil()
				expect(AutoTurretRules.findBlockingTag(nil, hasTag)).toBeNil()
				wall:Destroy()
			end
		)
	end
)

describe(
	"AutoTurretRules placement geometry",
	function()
		it(
			"hangs the ghost a flat distance ahead whatever the pitch",
			function()
				local root = CFrame.new(Vector3.new(10, 5, 10)) * CFrame.Angles(math.rad(-60), 0, 0)
				local origin = AutoTurretRules.ghostOrigin(root, 15)
				expect(origin.Y).toBeCloseTo(5, 5)
				expect((Vector3.new(origin.X, 0, origin.Z) - Vector3.new(10, 0, 10)).Magnitude).toBeCloseTo(15, 5)
				-- facing -Z (CFrame's forward), the ghost lands 15 studs down -Z
				expect(origin.Z).toBeCloseTo(-5, 5)
			end
		)

		it(
			"measures the place distance flat and allows the tolerance",
			function()
				local root = Vector3.new(0, 0, 0)
				expect(AutoTurretRules.isWithinPlaceDistance(root, Vector3.new(15, 40, 0), 15, 6)).toBe(true)
				expect(AutoTurretRules.isWithinPlaceDistance(root, Vector3.new(21, 0, 0), 15, 6)).toBe(true)
				expect(AutoTurretRules.isWithinPlaceDistance(root, Vector3.new(21.5, 0, 0), 15, 6)).toBe(false)
			end
		)

		it(
			"reads the player's yaw from their facing",
			function()
				expect(AutoTurretRules.yawDegreesOf(CFrame.new())).toBeCloseTo(0, 5)
				expect(AutoTurretRules.yawDegreesOf(CFrame.Angles(0, math.rad(90), 0))).toBeCloseTo(90, 4)
			end
		)
	end
)

describe(
	"AutoTurretRules carried HP",
	function()
		it(
			"carries whole HP between one point and the maximum",
			function()
				expect(AutoTurretRules.carriedHp(37.6, 100)).toBe(38)
				expect(AutoTurretRules.carriedHp(0.2, 100)).toBe(1)
				expect(AutoTurretRules.carriedHp(250, 100)).toBe(100)
			end
		)
	end
)
