-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local MonsterRules = require(game:GetService("ReplicatedStorage").Shared.MonsterRules)

local PLAYERS = Enums.MonsterTargetType.PLAYERS
local TOWERS = Enums.MonsterTargetType.TOWERS
local WALLS = Enums.MonsterTargetType.WALLS
local REFINERY = Enums.MonsterTargetType.REFINERY

-- mirrors a GameData/Monsters/Roster entry; GameData cannot load under jest
local function monster(overrides: { [string]: any }?): MonsterRules.MonsterData
	local data: { [string]: any } = {
		DIFFICULTY_VALUE = 2,
		MAX_HP = 100,
		DAMAGE = 10,
		SPEED_STUDS_PER_SEC = 10,
		TARGET_PRIORITIES = { PLAYERS },
		TARGET_DAMAGE_TYPES = {},
		ATTACK_TYPE = Enums.MonsterAttackType.MELEE,
		DETECTION_RANGE_STUDS = 5,
		ATTACK_RANGE_STUDS = 5,
		ATTACK_RADIUS_STUDS = 0,
		DIE_ON_ATTACK = false,
		DAMAGE_ON_DEATH = false,
		TRAVERSAL = Enums.MonsterTraversal.LAND,
		WALK_ANIMATION_ID = "rbxassetid://1",
		ATTACK_ANIMATION_ID = "rbxassetid://2",
		DEATH_ANIMATION_ID = "rbxassetid://3",
	}
	for key, value in overrides or {} do
		data[key] = value
	end
	return data :: any
end

local function point(id: string, targetType: number, position: Vector3): MonsterRules.Candidate
	return {
		id = id,
		targetType = targetType,
		position = position,
	}
end

local function box(id: string, targetType: number, cframe: CFrame, size: Vector3): MonsterRules.Candidate
	return {
		id = id,
		targetType = targetType,
		position = cframe.Position,
		cframe = cframe,
		size = size,
	}
end

describe(
	"MonsterRules.distanceTo",
	function()
		it(
			"measures to a box's surface and to a point's position",
			function()
				local wall = box("Wall1", WALLS, CFrame.new(10, 0, 0), Vector3.new(4, 10, 20))
				expect(MonsterRules.distanceTo(Vector3.new(0, 0, 0), wall)).toBeCloseTo(8, 5)
				expect(MonsterRules.distanceTo(Vector3.new(10, 0, 5), wall)).toBe(0)
				local player = point("Player1", PLAYERS, Vector3.new(3, 0, 4))
				expect(MonsterRules.distanceTo(Vector3.zero, player)).toBeCloseTo(5, 5)
			end
		)
	end
)

describe(
	"MonsterRules.pickTarget",
	function()
		it(
			"always puts the Refinery first when it is in range",
			function()
				local candidates = {
					[REFINERY] = { box("Refinery", REFINERY, CFrame.new(4, 0, 0), Vector3.new(2, 2, 2)) },
					[PLAYERS] = { point("Player1", PLAYERS, Vector3.new(1, 0, 0)) },
				}
				local target = MonsterRules.pickTarget(Vector3.zero, monster(), 0, candidates)
				expect(target and target.id).toBe("Refinery")
			end
		)
		it(
			"follows the priority list in order and picks the nearest of a type",
			function()
				local data = monster({
					TARGET_PRIORITIES = { WALLS, PLAYERS },
				})
				local candidates = {
					[PLAYERS] = { point("Player1", PLAYERS, Vector3.new(1, 0, 0)) },
					[WALLS] = {
						box("Wall2", WALLS, CFrame.new(0, 0, 6), Vector3.new(2, 2, 2)),
						box("Wall1", WALLS, CFrame.new(0, 0, 4), Vector3.new(2, 2, 2)),
					},
				}
				local target = MonsterRules.pickTarget(Vector3.zero, data, 0, candidates)
				expect(target and target.id).toBe("Wall1")
			end
		)
		it(
			"ignores types it does not list and anything out of range",
			function()
				local candidates = {
					[TOWERS] = { point("Tower1", TOWERS, Vector3.new(1, 0, 0)) },
					[PLAYERS] = { point("Player1", PLAYERS, Vector3.new(6, 0, 0)) },
				}
				expect(MonsterRules.pickTarget(Vector3.zero, monster(), 0, candidates)).toBe(nil)
				-- a wider body reaches the player
				local target = MonsterRules.pickTarget(Vector3.zero, monster(), 1.5, candidates)
				expect(target and target.id).toBe("Player1")
			end
		)
		it(
			"detects further than it hits, and never less far than it hits",
			function()
				local candidates = {
					[PLAYERS] = { point("Player1", PLAYERS, Vector3.new(15, 0, 0)) },
				}
				local data = monster({
					DETECTION_RANGE_STUDS = 20,
				})
				local target = MonsterRules.pickTarget(Vector3.zero, data, 0, candidates)
				expect(target and target.id).toBe("Player1")
				expect(MonsterRules.isInAttackRange(Vector3.zero, data, 0, target :: MonsterRules.Candidate)).toBe(false)
				local launcher = monster({
					DETECTION_RANGE_STUDS = 20,
					ATTACK_RANGE_STUDS = 200,
					TARGET_PRIORITIES = { WALLS },
				})
				expect(MonsterRules.detectionRangeStuds(launcher)).toBe(200)
				local wall = box("Wall1", WALLS, CFrame.new(150, 0, 0), Vector3.new(4, 10, 20))
				expect((MonsterRules.pickTarget(Vector3.zero, launcher, 0, { [WALLS] = { wall } }) :: MonsterRules.Candidate).id).toBe("Wall1")
			end
		)
		it(
			"lets a Decoy draw a player hunter from its own range",
			function()
				local decoy = point("Decoy", PLAYERS, Vector3.new(30, 0, 0))
				decoy.drawRangeStuds = 40
				local candidates = {
					[PLAYERS] = { decoy },
				}
				local data = monster()
				local target = MonsterRules.pickTarget(Vector3.zero, data, 0, candidates)
				expect(target and target.id).toBe("Decoy")
				expect(MonsterRules.isInAttackRange(Vector3.zero, data, 0, decoy)).toBe(false)
				expect(MonsterRules.isInAttackRange(Vector3.new(26, 0, 0), data, 0, decoy)).toBe(true)
			end
		)
	end
)

describe(
	"MonsterRules.closestPoint",
	function()
		it(
			"walks to the near face of a box and to a point target itself",
			function()
				local wall = box("Wall1", WALLS, CFrame.new(10, 0, 0), Vector3.new(4, 10, 20))
				local nearest = MonsterRules.closestPoint(Vector3.new(0, 3, 2), wall)
				expect(nearest.X).toBeCloseTo(8, 5)
				expect(nearest.Y).toBeCloseTo(3, 5)
				expect(nearest.Z).toBeCloseTo(2, 5)
				local player = point("Player1", PLAYERS, Vector3.new(3, 1, 4))
				expect(MonsterRules.closestPoint(Vector3.zero, player)).toEqual(Vector3.new(3, 1, 4))
			end
		)
	end
)

describe(
	"MonsterRules.blastVictims",
	function()
		it(
			"hurts the listed types in the radius but never the primary target twice",
			function()
				local candidates = {
					[WALLS] = {
						box("Wall1", WALLS, CFrame.new(3, 0, 0), Vector3.new(2, 2, 2)),
						box("Wall2", WALLS, CFrame.new(30, 0, 0), Vector3.new(2, 2, 2)),
					},
					[TOWERS] = { point("Tower1", TOWERS, Vector3.new(0, 0, 5)) },
					[PLAYERS] = { point("Player1", PLAYERS, Vector3.new(1, 0, 0)) },
				}
				local victims = MonsterRules.blastVictims(Vector3.zero, 10, { WALLS, TOWERS }, candidates, "Tower1")
				expect(#victims).toBe(1)
				expect(victims[1].id).toBe("Wall1")
				expect(#MonsterRules.blastVictims(Vector3.zero, 0, { WALLS }, candidates, nil)).toBe(0)
			end
		)
	end
)

describe(
	"MonsterRules movement and timing",
	function()
		it(
			"steps toward a destination and stops on it",
			function()
				local position, isArrived = MonsterRules.stepToward(Vector3.zero, Vector3.new(10, 0, 0), 10, 0.5)
				expect(position.X).toBeCloseTo(5, 5)
				expect(isArrived).toBe(false)
				position, isArrived = MonsterRules.stepToward(position, Vector3.new(10, 0, 0), 10, 1)
				expect(position.X).toBeCloseTo(10, 5)
				expect(isArrived).toBe(true)
			end
		)
		it(
			"falls back to the default attack interval and times a flight",
			function()
				expect(MonsterRules.attackIntervalSec(monster(), 1.5)).toBe(1.5)
				expect(MonsterRules.attackIntervalSec(monster({ ATTACK_INTERVAL_SEC = 3 }), 1.5)).toBe(3)
				expect(MonsterRules.flightSec(Vector3.zero, Vector3.new(0, 0, 60), 30)).toBeCloseTo(2, 5)
				expect(MonsterRules.flightSec(Vector3.zero, Vector3.new(0, 0, 60), 0)).toBe(0)
			end
		)
	end
)

describe(
	"MonsterRules visual catalogue",
	function()
		it(
			"round-trips what a client needs and rejects junk",
			function()
				local roster = {
					[Enums.MonsterKind.FLYER_1] = monster({
						TRAVERSAL = Enums.MonsterTraversal.AIR,
						IDLE_ANIMATION_ID = "rbxassetid://4",
						PROJECTILE = "Fireball",
					}),
				}
				local catalog = MonsterRules.decodeVisualCatalog(MonsterRules.encodeVisualCatalog(roster))
				local visual = catalog and catalog[Enums.MonsterKind.FLYER_1]
				expect(visual and visual.isAir).toBe(true)
				expect(visual and visual.projectile).toBe("Fireball")
				expect(visual and visual.idleAnimationId).toBe("rbxassetid://4")
				expect(visual and visual.model).toBe("FLYER_1")
				expect(visual and visual.maxHp).toBe(100)
				expect(MonsterRules.decodeVisualCatalog("not json")).toBe(nil)
				expect(MonsterRules.decodeVisualCatalog(5)).toBe(nil)
			end
		)
	end
)
