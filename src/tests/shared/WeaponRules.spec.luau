-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local SoundNames = require(game:GetService("ReplicatedStorage").Shared.SoundNames)
local WeaponRules = require(game:GetService("ReplicatedStorage").Shared.WeaponRules)

local FORWARD = Vector3.new(0, 0, -1)
local BOX_SIZE = Vector3.new(4, 6, 2)

describe(
	"WeaponRules firing and the magazine",
	function()
		it(
			"enforces the cooldown from the last shot",
			function()
				expect(WeaponRules.canFire(nil, 100, 0.13)).toBe(true)
				-- halves and quarters are exact in floating point; 100.13 - 100 is not 0.13
				expect(WeaponRules.canFire(100, 100.25, 0.5)).toBe(false)
				expect(WeaponRules.canFire(100, 100.5, 0.5)).toBe(true)
				expect(WeaponRules.canFire(100, 100.75, 0.5)).toBe(true)
			end
		)

		it(
			"is reloading only between the start and the end time",
			function()
				expect(WeaponRules.isReloading(0, 50)).toBe(false)
				expect(WeaponRules.isReloading(51.8, 50)).toBe(true)
				expect(WeaponRules.isReloading(51.8, 51.8)).toBe(false)
			end
		)

		it(
			"reloads a short magazine, never a full one or one already reloading",
			function()
				expect(WeaponRules.canReload(5, 20, 0, 50)).toBe(true)
				expect(WeaponRules.canReload(0, 20, 0, 50)).toBe(true)
				expect(WeaponRules.canReload(20, 20, 0, 50)).toBe(false)
				expect(WeaponRules.canReload(5, 20, 51, 50)).toBe(false)
				expect(WeaponRules.canReload(5, 20, 49, 50)).toBe(true)
			end
		)

		it(
			"accepts a ray that starts near the head and rejects one that does not",
			function()
				local head = Vector3.new(10, 5, 10)
				expect(WeaponRules.isOriginPlausible(head, Vector3.new(10, 5.5, 10), 12)).toBe(true)
				expect(WeaponRules.isOriginPlausible(head, Vector3.new(22, 5, 10), 12)).toBe(true)
				expect(WeaponRules.isOriginPlausible(head, Vector3.new(10, 5, 60), 12)).toBe(false)
			end
		)
	end
)

describe(
	"WeaponRules.rayBoxDistance",
	function()
		it(
			"hits a box straight ahead at its near face",
			function()
				local box = CFrame.new(0, 0, -20)
				expect(WeaponRules.rayBoxDistance(Vector3.zero, FORWARD, box, BOX_SIZE, 300)).toBeCloseTo(19, 5)
			end
		)

		it(
			"misses a box off to the side, behind the shooter, or past the range",
			function()
				expect(WeaponRules.rayBoxDistance(Vector3.zero, FORWARD, CFrame.new(10, 0, -20), BOX_SIZE, 300)).toBeNil()
				expect(WeaponRules.rayBoxDistance(Vector3.zero, FORWARD, CFrame.new(0, 0, 20), BOX_SIZE, 300)).toBeNil()
				expect(WeaponRules.rayBoxDistance(Vector3.zero, FORWARD, CFrame.new(0, 0, -20), BOX_SIZE, 10)).toBeNil()
			end
		)

		it(
			"respects the box's rotation",
			function()
				-- turned a quarter, the 4 wide by 2 deep box is 2 wide by 4 deep
				local turned = CFrame.new(0, 0, -20) * CFrame.Angles(0, math.rad(90), 0)
				expect(WeaponRules.rayBoxDistance(Vector3.zero, FORWARD, turned, BOX_SIZE, 300)).toBeCloseTo(18, 5)
				expect(WeaponRules.rayBoxDistance(Vector3.new(1.5, 0, 0), FORWARD, turned, BOX_SIZE, 300)).toBeNil()
				expect(WeaponRules.rayBoxDistance(Vector3.new(1.5, 0, 0), FORWARD, CFrame.new(0, 0, -20), BOX_SIZE, 300)).toBeCloseTo(19, 5)
			end
		)

		it(
			"hits at zero from inside the box and handles an axis-parallel ray",
			function()
				expect(WeaponRules.rayBoxDistance(Vector3.zero, FORWARD, CFrame.new(0, 0, 0), BOX_SIZE, 300)).toBe(0)
				expect(WeaponRules.rayBoxDistance(Vector3.new(0, 3.5, 0), FORWARD, CFrame.new(0, 0, -20), BOX_SIZE, 300)).toBeNil()
			end
		)
	end
)

describe(
	"WeaponRules.findClosestHit",
	function()
		local boxes = {
			{ id = "far", cframe = CFrame.new(0, 0, -50), size = BOX_SIZE },
			{ id = "near", cframe = CFrame.new(0, 0, -20), size = BOX_SIZE },
			{ id = "aside", cframe = CFrame.new(30, 0, -10), size = BOX_SIZE },
		}

		it(
			"returns the first box along the ray",
			function()
				local id, distance = WeaponRules.findClosestHit(Vector3.zero, FORWARD, 300, boxes)
				expect(id).toBe("near")
				expect(distance).toBeCloseTo(19, 5)
			end
		)

		it(
			"returns nothing when the world stops the ray first or nothing is in line",
			function()
				expect((WeaponRules.findClosestHit(Vector3.zero, FORWARD, 15, boxes))).toBeNil()
				expect((WeaponRules.findClosestHit(Vector3.zero, Vector3.new(0, 1, 0), 300, boxes))).toBeNil()
				expect((WeaponRules.findClosestHit(Vector3.zero, FORWARD, 300, {}))).toBeNil()
			end
		)
	end
)

describe(
	"WeaponRules names",
	function()
		it(
			"names the held template after the weapon's enum key",
			function()
				expect(WeaponRules.templateNameFor(Enums.WeaponKind.RIFLE)).toBe("WEAPON_RIFLE")
			end
		)

		it(
			"gives every weapon kind its own full sound set",
			function()
				local seen: { [string]: boolean } = {}
				for _, kind in Enums.getAllValues(Enums.WeaponKind) do
					local kindName = Enums.getName(Enums.WeaponKind, kind) :: string
					local weaponSfx = SoundNames.WeaponSfxByKindName[kindName]
					expect(weaponSfx).never.toBeNil()
					for _, key in { "FIRE", "RELOAD", "EMPTY", "HIT" } do
						local name = (weaponSfx :: any)[key]
						expect(typeof(name)).toBe("string")
						-- no two weapons, and no two events, share a sound
						expect(seen[name]).toBeNil()
						seen[name] = true
					end
				end
			end
		)

		it(
			"resolves a loadout name by key or public name and falls back to the default",
			function()
				local rifle = Enums.WeaponKind.RIFLE
				expect(WeaponRules.resolveLoadoutWeapon("Rifle", rifle)).toBe(rifle)
				expect(WeaponRules.resolveLoadoutWeapon("RIFLE", rifle)).toBe(rifle)
				expect(WeaponRules.resolveLoadoutWeapon(nil, rifle)).toBe(rifle)
				expect(WeaponRules.resolveLoadoutWeapon("", rifle)).toBe(rifle)
				expect(WeaponRules.resolveLoadoutWeapon("Pistol", rifle)).toBe(rifle)
			end
		)
	end
)
