-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local PostRules = require(game:GetService("ReplicatedStorage").Shared.PostRules)
local SoundNames = require(game:GetService("ReplicatedStorage").Shared.SoundNames)

-- mirrors GameData/Posts/PostWeapons and GameData/Camp/Level; GameData
-- cannot load under jest
local MACHINE_GUN = {
	DAMAGE = 12,
	FIRE_INTERVAL_SEC = 0.1,
	FIRE_COOLDOWN_SEC = 0.08,
	TURN_SPEED_DEGREES_PER_SEC = 22,
	RANGE_STUDS = 350,
	FIELD_OF_VIEW = 60,
	PITCH_MIN_DEGREES = -40,
	PITCH_MAX_DEGREES = 45,
}

local function makeCatalog()
	return {
		claimPriceGold = 10,
		upgradePriceByLevel = { 15, 30, 60, 120 },
		requiredCampLevelByLevel = { 1, 2, 3, 4 },
		bonusPerLevelByAttribute = {
			[Enums.PostAttribute.DAMAGE] = 0.25,
			[Enums.PostAttribute.FIRE_RATE] = 0.2,
			[Enums.PostAttribute.TURN_SPEED] = 0.5,
			[Enums.PostAttribute.RANGE] = 0.2,
		},
		kinds = {
			[Enums.PostWeaponKind.MACHINE_GUN] = MACHINE_GUN,
		},
	}
end

-- a gun sitting 2 studs above the Spawn, barrel down its local -X (the
-- Machine Gun's layout), with the camera 1 stud behind the muzzle
local function makeRig()
	return {
		gunOffset = CFrame.new(2, 0, 0),
		cameraOffset = CFrame.new(-3, 0.5, 0),
		muzzleOffset = Vector3.new(-5, 0, 0),
		characterOffset = CFrame.new(3, 0, -1),
		barrel = Vector3.new(-1, 0, 0),
		pitchAxis = Vector3.new(-1, 0, 0):Cross(Vector3.new(0, 1, 0)).Unit,
	}
end

local function expectVectorClose(actual, expected)
	expect((actual - expected).Magnitude).toBeLessThan(0.001)
end

describe(
	"PostRules stats and upgrades",
	function()
		it(
			"is the base stats with no upgrades",
			function()
				local stats = PostRules.statsFor(makeCatalog(), Enums.PostWeaponKind.MACHINE_GUN, {})
				expect(stats.damage).toBe(12)
				expect(stats.fireIntervalSec).toBe(0.1)
				expect(stats.turnSpeedDegreesPerSec).toBe(22)
				expect(stats.rangeStuds).toBe(350)
			end
		)

		it(
			"adds a share of the base per upgrade and shortens the interval for fire rate",
			function()
				local upgrades = {
					[Enums.PostAttribute.DAMAGE] = 4,
					[Enums.PostAttribute.FIRE_RATE] = 1,
					[Enums.PostAttribute.RANGE] = 2,
				}
				local stats = PostRules.statsFor(makeCatalog(), Enums.PostWeaponKind.MACHINE_GUN, upgrades)
				expect(stats.damage).toBe(24)
				expect(stats.fireIntervalSec).toBeCloseTo(0.1 / 1.2, 5)
				expect(stats.fireCooldownSec).toBeCloseTo(0.08 / 1.2, 5)
				expect(stats.turnSpeedDegreesPerSec).toBe(22)
				expect(stats.rangeStuds).toBeCloseTo(490, 5)
			end
		)

		it(
			"shortens a reload with Fire Rate, and has none for a kind that does not reload",
			function()
				local catalog = makeCatalog()
				catalog.kinds[2] = {
					DAMAGE = 150,
					FIRE_INTERVAL_SEC = 6,
					FIRE_COOLDOWN_SEC = 5.8,
					TURN_SPEED_DEGREES_PER_SEC = 12,
					RANGE_STUDS = 500,
					FIELD_OF_VIEW = 40,
					PITCH_MIN_DEGREES = -35,
					PITCH_MAX_DEGREES = 60,
					RELOAD_SEC = 6,
				}
				expect(PostRules.statsFor(catalog, 2, {}).reloadSec).toBe(6)
				expect(PostRules.statsFor(catalog, 2, { [Enums.PostAttribute.FIRE_RATE] = 1 }).reloadSec).toBeCloseTo(5, 5)
				expect(PostRules.statsFor(catalog, Enums.PostWeaponKind.MACHINE_GUN, {}).reloadSec).toBeNil()
			end
		)

		it(
			"is nil for a kind the catalogue does not list",
			function()
				expect(PostRules.statsFor(makeCatalog(), 99, {})).toBeNil()
			end
		)

		it(
			"offers the next upgrade at its price, locked by the Camp Level, until the cap",
			function()
				local catalog = makeCatalog()
				local first = PostRules.getUpgradeOffer(catalog, {}, Enums.PostAttribute.DAMAGE, 1)
				expect(first.status).toBe(Enums.StoreOffer.AVAILABLE)
				expect(first.level).toBe(1)
				expect(first.price).toBe(15)

				local second = PostRules.getUpgradeOffer(catalog, { [Enums.PostAttribute.DAMAGE] = 1 }, Enums.PostAttribute.DAMAGE, 1)
				expect(second.status).toBe(Enums.StoreOffer.LOCKED)
				expect(second.requiredCampLevel).toBe(2)
				expect(second.price).toBe(30)

				local unlocked = PostRules.getUpgradeOffer(catalog, { [Enums.PostAttribute.DAMAGE] = 1 }, Enums.PostAttribute.DAMAGE, 2)
				expect(unlocked.status).toBe(Enums.StoreOffer.AVAILABLE)

				local maxed = PostRules.getUpgradeOffer(catalog, { [Enums.PostAttribute.DAMAGE] = 4 }, Enums.PostAttribute.DAMAGE, 4)
				expect(maxed.status).toBe(Enums.StoreOffer.MAXED)
				expect(maxed.level).toBeNil()
			end
		)

		it(
			"round-trips the catalogue through JSON with number keys intact",
			function()
				local decoded = PostRules.decodeCatalog(PostRules.encodeCatalog(makeCatalog()))
				expect(decoded.claimPriceGold).toBe(10)
				expect(decoded.upgradePriceByLevel[4]).toBe(120)
				expect(decoded.bonusPerLevelByAttribute[Enums.PostAttribute.FIRE_RATE]).toBe(0.2)
				expect(decoded.kinds[Enums.PostWeaponKind.MACHINE_GUN].RANGE_STUDS).toBe(350)
				expect(PostRules.decodeCatalog("")).toBeNil()
				expect(PostRules.decodeCatalog("not json")).toBeNil()
			end
		)
	end
)

describe(
	"PostRules aiming",
	function()
		it(
			"wraps degrees into a half turn either way",
			function()
				expect(PostRules.wrapDegrees(0)).toBe(0)
				expect(PostRules.wrapDegrees(180)).toBe(180)
				expect(PostRules.wrapDegrees(181)).toBe(-179)
				expect(PostRules.wrapDegrees(-190)).toBe(170)
				expect(PostRules.wrapDegrees(720)).toBe(0)
			end
		)

		it(
			"turns no faster than the turn speed",
			function()
				-- 90 degrees per second, a tenth of a second: 9 degrees at most
				expect(PostRules.turnYaw(0, 4, 90, 0.1)).toBe(4)
				expect(PostRules.turnYaw(0, 40, 90, 0.1)).toBe(9)
				expect(PostRules.turnYaw(0, -40, 90, 0.1)).toBe(-9)
				expect(PostRules.turnYaw(178, 40, 90, 0.1)).toBe(-173)
			end
		)

		it(
			"allows a yaw report the turn speed could have reached, plus the tolerance",
			function()
				expect(PostRules.isYawStepAllowed(0, 20, 90, 0.25, 5)).toBe(true)
				expect(PostRules.isYawStepAllowed(0, 30, 90, 0.25, 5)).toBe(false)
				-- through north: 170 to -170 is a 20 degree step, not 340
				expect(PostRules.isYawStepAllowed(170, -170, 90, 0.25, 5)).toBe(true)
			end
		)

		it(
			"clamps the pitch to the kind's range",
			function()
				expect(PostRules.clampPitch(60, MACHINE_GUN)).toBe(45)
				expect(PostRules.clampPitch(-50, MACHINE_GUN)).toBe(-40)
				expect(PostRules.clampPitch(10, MACHINE_GUN)).toBe(10)
			end
		)
	end
)

describe(
	"PostRules frames",
	function()
		it(
			"turns the base about the Spawn's X axis, positive to the right",
			function()
				-- a Spawn whose X points up and +Z forward: +Y is the gunner's
				-- right (look x up), so a 90 degree turn brings +Z round to +Y
				local spawn = CFrame.new(10, 0, 10) * CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 1, 0), Vector3.new(0, 0, 1))
				local turned = PostRules.baseFrame(spawn, 90)
				expectVectorClose(turned.Position, Vector3.new(10, 0, 10))
				expectVectorClose(turned.XVector, spawn.XVector)
				expectVectorClose(turned.ZVector, spawn.YVector)
			end
		)

		it(
			"lifts the barrel with a positive pitch and keeps the muzzle on it",
			function()
				local rig = makeRig()
				local base = CFrame.identity
				local level = PostRules.gunFrame(base, rig, 0)
				expectVectorClose(PostRules.barrelDirection(level, rig), Vector3.new(-1, 0, 0))
				expectVectorClose(PostRules.muzzlePosition(level, rig), Vector3.new(-3, 0, 0))

				local lifted = PostRules.gunFrame(base, rig, 90)
				expectVectorClose(PostRules.barrelDirection(lifted, rig), Vector3.new(0, 1, 0))
				expectVectorClose(PostRules.muzzlePosition(lifted, rig), Vector3.new(2, 5, 0))
				-- the camera looks where the barrel points
				expectVectorClose(PostRules.cameraFrame(lifted, rig).LookVector, Vector3.new(0, 1, 0))
			end
		)

		it(
			"snaps a muzzle offset to the gun axis it lies furthest along",
			function()
				expectVectorClose(PostRules.dominantAxis(Vector3.new(-5.65, 0.01, -1.05)), Vector3.new(-1, 0, 0))
				expectVectorClose(PostRules.dominantAxis(Vector3.new(0.1, 0, 3)), Vector3.new(0, 0, 1))
				expect(PostRules.dominantAxis(Vector3.zero)).toBeNil()
			end
		)

		it(
			"keeps the gunner on the base, turning but never tilting",
			function()
				local rig = makeRig()
				local base = PostRules.baseFrame(CFrame.identity, 0)
				expectVectorClose(PostRules.characterFrame(base, rig).Position, Vector3.new(3, 0, -1))
			end
		)
	end
)

describe(
	"PostRules heat and reload",
	function()
		-- mirrors GameData/Posts/PostWeapons (FULL_SEC cut to 3 in play, 2026-09-18)
		local HEAT = { FULL_SEC = 3, COOL_SEC = 3 }

		it(
			"reaches full heat after FULL_SEC of shots at the interval",
			function()
				local heat = 0
				local isOverheated = false
				local shots = 0
				while not isOverheated and shots < 100 do
					local _isFired, newHeat, overheated = PostRules.heatAfterShot(heat, isOverheated, HEAT, 0.1)
					heat = newHeat
					isOverheated = overheated
					shots += 1
				end
				expect(shots).toBe(30)
				expect(heat).toBe(1)
			end
		)

		it(
			"holds heat while the trigger is held and cools once it rests",
			function()
				-- a shot every 0.1 s: the next shot comes before the rest slack, no cooling
				expect(PostRules.cooledHeat(0.5, 100, 100.1, 0.1, HEAT)).toBe(0.5)
				-- resting 1.65 s: 1.5 s past the slack, half of COOL_SEC
				expect(PostRules.cooledHeat(1, 100, 101.65, 0.1, HEAT)).toBeCloseTo(0.5, 5)
				expect(PostRules.cooledHeat(1, 100, 110, 0.1, HEAT)).toBe(0)
				expect(PostRules.cooledHeat(1, nil, 110, 0.1, HEAT)).toBe(0)
			end
		)

		it(
			"refuses to fire while overheated until fully cool",
			function()
				local isFired, heat, isOverheated = PostRules.heatAfterShot(0.4, true, HEAT, 0.1)
				expect(isFired).toBe(false)
				expect(heat).toBe(0.4)
				expect(isOverheated).toBe(true)
				local isFiredCool, heatCool, isStillOverheated = PostRules.heatAfterShot(0, true, HEAT, 0.1)
				expect(isFiredCool).toBe(true)
				expect(heatCool).toBeCloseTo(0.1 / 3, 5)
				expect(isStillOverheated).toBe(false)
			end
		)

		it(
			"fills the reload bar from the start of the reload to its end",
			function()
				expect(PostRules.reloadProgress(0, 50, 3)).toBe(1)
				expect(PostRules.reloadProgress(53, 50, 3)).toBe(0)
				expect(PostRules.reloadProgress(53, 51.5, 3)).toBe(0.5)
				expect(PostRules.reloadProgress(53, 60, 3)).toBe(1)
			end
		)
	end
)

describe(
	"PostRules rockets",
	function()
		it(
			"measures to the nearest face of a box, zero inside",
			function()
				local box = CFrame.new(0, 0, 0)
				local size = Vector3.new(4, 6, 2)
				expect(PostRules.distanceToBox(Vector3.new(0, 0, 0), box, size)).toBe(0)
				expect(PostRules.distanceToBox(Vector3.new(5, 0, 0), box, size)).toBe(3)
				expect(PostRules.distanceToBox(Vector3.new(0, 0, 5), box, size)).toBe(4)
				-- off a corner: the diagonal
				expect(PostRules.distanceToBox(Vector3.new(5, 0, 4), box, size)).toBeCloseTo(math.sqrt(9 + 9), 5)
			end
		)

		it(
			"hits every box within the splash radius of its surface",
			function()
				local boxes = {
					{ id = "near", cframe = CFrame.new(10, 0, 0), size = Vector3.new(4, 6, 2) },
					{ id = "edge", cframe = CFrame.new(0, 0, 13), size = Vector3.new(2, 2, 2) },
					{ id = "far", cframe = CFrame.new(0, 30, 0), size = Vector3.new(2, 2, 2) },
				}
				local ids = PostRules.findSplashHits(Vector3.zero, 12, boxes)
				table.sort(ids)
				expect(ids).toEqual({ "edge", "near" })
			end
		)

		it(
			"points the rocket's nose along its flight",
			function()
				-- the Rocket mesh: tail at +X, so the nose is -X
				local frame = PostRules.projectileFrame(Vector3.new(1, 2, 3), Vector3.new(0, 0, 1), Vector3.new(1.5, 0, 0))
				expectVectorClose(frame.Position, Vector3.new(1, 2, 3))
				expectVectorClose(frame:VectorToWorldSpace(Vector3.new(-1, 0, 0)), Vector3.new(0, 0, 1))
				local up = PostRules.projectileFrame(Vector3.zero, Vector3.new(0, 1, 0), Vector3.new(1.5, 0, 0))
				expectVectorClose(up:VectorToWorldSpace(Vector3.new(-1, 0, 0)), Vector3.new(0, 1, 0))
			end
		)
	end
)

describe(
	"PostRules names",
	function()
		it(
			"names the template after the enum key",
			function()
				expect(PostRules.templateNameFor(Enums.PostWeaponKind.MACHINE_GUN)).toBe("MACHINE_GUN")
			end
		)

		it(
			"resolves a loadout name by key or public name, else the default",
			function()
				expect(PostRules.resolveLoadoutPost("ROCKET_LAUNCHER", 1)).toBe(Enums.PostWeaponKind.ROCKET_LAUNCHER)
				expect(PostRules.resolveLoadoutPost("Rocket Launcher", 1)).toBe(Enums.PostWeaponKind.ROCKET_LAUNCHER)
				expect(PostRules.resolveLoadoutPost(nil, 1)).toBe(1)
				expect(PostRules.resolveLoadoutPost("Trebuchet", 1)).toBe(1)
			end
		)

		it(
			"reads the post number from its marker name",
			function()
				expect(PostRules.postIndexFromName("Post4")).toBe(4)
				expect(PostRules.postIndexFromName("Wall4")).toBeNil()
			end
		)

		it(
			"has a sound pair for every post weapon kind",
			function()
				for _, kind in Enums.getAllValues(Enums.PostWeaponKind) do
					local kindName = Enums.getName(Enums.PostWeaponKind, kind)
					local set = SoundNames.PostWeaponSfxByKindName[kindName]
					expect(set).never.toBeNil()
					expect(typeof(set.FIRE)).toBe("string")
					expect(typeof(set.HIT)).toBe("string")
				end
			end
		)
	end
)
