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
	end
)

describe(
	"WeaponRules upgrades",
	function()
		local catalog: WeaponRules.Catalog = {
			upgradePriceByLevel = { 15, 90, 270, 800 },
			bonusPerLevelByAttribute = {
				[Enums.WeaponAttribute.DAMAGE] = 0.25,
				[Enums.WeaponAttribute.AMMO] = 0.2,
				[Enums.WeaponAttribute.RANGE] = 0.2,
			},
			kinds = {
				[Enums.WeaponKind.RIFLE] = {
					DAMAGE = 60,
					FIRE_INTERVAL_SEC = 0.6,
					FIRE_COOLDOWN_SEC = 0.5,
					RANGE_STUDS = 300,
					MAGAZINE_SIZE = 5,
					RELOAD_SEC = 2.5,
				},
			},
		}

		it(
			"starts at the base stats and scales each one by its own levels",
			function()
				local base = WeaponRules.statsFor(catalog, Enums.WeaponKind.RIFLE, {})
				expect(base).toEqual({ damage = 60, magazineSize = 5, rangeStuds = 300 })
				local upgraded = WeaponRules.statsFor(catalog, Enums.WeaponKind.RIFLE, {
					[Enums.WeaponAttribute.DAMAGE] = 2,
					[Enums.WeaponAttribute.AMMO] = 3,
					[Enums.WeaponAttribute.RANGE] = 1,
				})
				expect(upgraded).toEqual({ damage = 90, magazineSize = 8, rangeStuds = 360 })
				expect(WeaponRules.statsFor(catalog, 99, {})).toBeNil()
			end
		)

		it(
			"offers the next level at its price and maxes at the cap, never locked",
			function()
				local first = WeaponRules.getUpgradeOffer(catalog, {}, Enums.WeaponAttribute.DAMAGE)
				expect(first.status).toBe(Enums.StoreOffer.AVAILABLE)
				expect(first.level).toBe(1)
				expect(first.price).toBe(15)
				local last = WeaponRules.getUpgradeOffer(catalog, { [Enums.WeaponAttribute.DAMAGE] = 3 }, Enums.WeaponAttribute.DAMAGE)
				expect(last.price).toBe(800)
				local maxed = WeaponRules.getUpgradeOffer(catalog, { [Enums.WeaponAttribute.DAMAGE] = 4 }, Enums.WeaponAttribute.DAMAGE)
				expect(maxed.status).toBe(Enums.StoreOffer.MAXED)
				expect(maxed.price).toBeNil()
				expect(WeaponRules.canAfford(15, 15)).toBe(true)
				expect(WeaponRules.canAfford(14, 15)).toBe(false)
			end
		)

		it(
			"round-trips the catalogue through JSON with numeric keys intact",
			function()
				local decoded = WeaponRules.decodeCatalog(WeaponRules.encodeCatalog(catalog))
				expect(decoded).never.toBeNil()
				if decoded then
					expect(decoded.upgradePriceByLevel).toEqual(catalog.upgradePriceByLevel)
					expect(decoded.bonusPerLevelByAttribute[Enums.WeaponAttribute.AMMO]).toBe(0.2)
					expect(decoded.kinds[Enums.WeaponKind.RIFLE].MAGAZINE_SIZE).toBe(5)
				end
				expect(WeaponRules.decodeCatalog("nope")).toBeNil()
				expect(WeaponRules.decodeCatalog(nil)).toBeNil()
			end
		)
	end
)

describe(
	"WeaponRules cone and pierce hits (the class weapons)",
	function()
		local function box(id, x, z)
			return { id = id, cframe = CFrame.new(x, 0, z), size = Vector3.new(2, 2, 2) }
		end

		it(
			"finds what a cone reaches, nearest first, and nothing outside its angle or range",
			function()
				local boxes = { box("far", 0, 50), box("side", 20, 5), box("near", 1, 10), box("mid", 0, 20), box("ontop", 0, 0.5) }
				expect(WeaponRules.findConeHits(Vector3.zero, Vector3.zAxis, 30, 30, boxes)).toEqual({ "ontop", "near", "mid" })
			end
		)

		it(
			"pierces through boxes along the ray in order, up to the count",
			function()
				local boxes = { box("third", 0, 30), box("first", 0, 10), box("second", 0, 20), box("miss", 10, 15) }
				expect((WeaponRules.findPierceHits(Vector3.zero, Vector3.zAxis, 100, boxes, 2))).toEqual({ "first", "second" })
				expect((WeaponRules.findPierceHits(Vector3.zero, Vector3.zAxis, 100, boxes, 10))).toEqual({ "first", "second", "third" })
				expect((WeaponRules.findPierceHits(Vector3.zero, Vector3.zAxis, 15, boxes, 10))).toEqual({ "first" })
				local _ids, distances = WeaponRules.findPierceHits(Vector3.zero, Vector3.zAxis, 100, boxes, 2)
				expect(#distances).toBe(2)
				expect(distances[1] < distances[2]).toBe(true)
			end
		)
	end
)

describe(
	"WeaponRules.isHeadshot",
	function()
		it(
			"calls the top slice of a box the head, in the box's own frame",
			function()
				local box = CFrame.new(10, 5, 0) * CFrame.Angles(0, math.rad(90), 0)
				local size = Vector3.new(4, 10, 4)
				-- the box runs from y 0 to y 10; the top 30% starts at y 7
				expect(WeaponRules.isHeadshot(Vector3.new(10, 9, 0), box, size, 0.3)).toBe(true)
				expect(WeaponRules.isHeadshot(Vector3.new(10, 7, 0), box, size, 0.3)).toBe(true)
				expect(WeaponRules.isHeadshot(Vector3.new(10, 6.9, 0), box, size, 0.3)).toBe(false)
				expect(WeaponRules.isHeadshot(Vector3.new(10, 1, 0), box, size, 0.3)).toBe(false)
				expect(WeaponRules.isHeadshot(Vector3.new(10, 1, 0), box, size, 1)).toBe(true)
			end
		)
	end
)
