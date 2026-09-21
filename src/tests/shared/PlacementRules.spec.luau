-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local PlacementRules = require(game:GetService("ReplicatedStorage").Shared.PlacementRules)

local CELL = 4
-- a 40 by 24 stud slab, 1 stud thick, centred at the origin: 10 columns by 6 rows
local ZONE_CFRAME = CFrame.new(0, 0, 0)
local ZONE_SIZE = Vector3.new(40, 1, 24)

local SENTRY = {
	BUILD_PRICE_IRON = 20,
	UPGRADE_PRICE_IRON_BY_LEVEL = { 15, 30, 60, 120 },
	FOOTPRINT_CELLS = { 1, 1 },
	STATS_BY_LEVEL = {
		{ DAMAGE = 6, FIRE_INTERVAL_SEC = 0.5, RANGE_STUDS = 40, MAX_HP = 150 },
		{ DAMAGE = 8, FIRE_INTERVAL_SEC = 0.45, RANGE_STUDS = 44, MAX_HP = 180 },
		{ DAMAGE = 10, FIRE_INTERVAL_SEC = 0.4, RANGE_STUDS = 48, MAX_HP = 220 },
		{ DAMAGE = 13, FIRE_INTERVAL_SEC = 0.35, RANGE_STUDS = 52, MAX_HP = 270 },
		{ DAMAGE = 16, FIRE_INTERVAL_SEC = 0.3, RANGE_STUDS = 60, MAX_HP = 330 },
	},
}
local SPIKES = {
	PRICE_IRON = 15,
	MAX_HP = 120,
	FOOTPRINT_CELLS = { 2, 1 },
	REQUIRED_CAMP_LEVEL = 1,
}

local function makeCatalog()
	return {
		cellSizeStuds = CELL,
		previewDistanceStuds = 10,
		maxActiveTowersPerPlayer = 5,
		maxTrapKindsCarried = 3,
		towerSellShare = 0.5,
		trapSellShare = 0.5,
		towers = { [Enums.TowerKind.SENTRY_GUN] = SENTRY },
		traps = { [Enums.TrapKind.SPIKE_TRAP] = SPIKES },
	}
end

describe(
	"PlacementRules.measureZone",
	function()
		it(
			"cuts the part into whole cells and sits the frame on the top face",
			function()
				local grid = PlacementRules.measureZone(ZONE_CFRAME, ZONE_SIZE, CELL)
				expect(grid.columns).toBe(10)
				expect(grid.rows).toBe(6)
				expect(grid.cframe.Position.Y).toBeCloseTo(0.5, 5)
			end
		)
		it(
			"drops a partial cell at the edge",
			function()
				local grid = PlacementRules.measureZone(ZONE_CFRAME, Vector3.new(43, 1, 25), CELL)
				expect(grid.columns).toBe(10)
				expect(grid.rows).toBe(6)
			end
		)
	end
)

describe(
	"PlacementRules cells",
	function()
		local grid = PlacementRules.measureZone(ZONE_CFRAME, ZONE_SIZE, CELL)
		it(
			"centres cell 1,1 in the -X -Z corner and the last cell opposite",
			function()
				local first = PlacementRules.cellCenter(grid, { column = 1, row = 1 })
				expect(first.X).toBeCloseTo(-18, 5)
				expect(first.Z).toBeCloseTo(-10, 5)
				local last = PlacementRules.cellCenter(grid, { column = 10, row = 6 })
				expect(last.X).toBeCloseTo(18, 5)
				expect(last.Z).toBeCloseTo(10, 5)
			end
		)
		it(
			"finds the cell under a position and runs past the edges outside",
			function()
				local inside = PlacementRules.cellFromPosition(grid, Vector3.new(-17, 3, -9))
				expect(inside.column).toBe(1)
				expect(inside.row).toBe(1)
				local outside = PlacementRules.cellFromPosition(grid, Vector3.new(30, 0, 0))
				expect(outside.column).toBe(13)
				expect(PlacementRules.isCellInside(grid, outside)).toBe(false)
			end
		)
		it(
			"follows the part's rotation",
			function()
				local turned = PlacementRules.measureZone(CFrame.Angles(0, math.rad(90), 0), ZONE_SIZE, CELL)
				local first = PlacementRules.cellCenter(turned, { column = 1, row = 1 })
				-- +X of the grid now points along world -Z
				expect(first.Z).toBeCloseTo(18, 5)
				expect(first.X).toBeCloseTo(-10, 5)
			end
		)
		it(
			"lists every cell a footprint covers from its anchor",
			function()
				local cells = PlacementRules.footprintCells({ column = 3, row = 2 }, { 2, 2 })
				expect(#cells).toBe(4)
				expect(cells[4].column).toBe(4)
				expect(cells[4].row).toBe(3)
			end
		)
		it(
			"centres a footprint between its cells",
			function()
				local pose = PlacementRules.footprintCFrame(grid, { column = 1, row = 1 }, { 2, 1 })
				expect(pose.Position.X).toBeCloseTo(-16, 5)
				expect(pose.Position.Z).toBeCloseTo(-10, 5)
			end
		)
		it(
			"snaps a position to the anchor whose footprint is nearest",
			function()
				local single = PlacementRules.anchorFromPosition(grid, Vector3.new(-17, 0, -9), { 1, 1 })
				expect(single.column).toBe(1)
				expect(single.row).toBe(1)
				-- a 2-wide footprint centred at x = -16 anchors at column 1
				local wide = PlacementRules.anchorFromPosition(grid, Vector3.new(-16, 0, -9), { 2, 1 })
				expect(wide.column).toBe(1)
				expect(wide.row).toBe(1)
			end
		)
		it(
			"clamps an anchor so the whole footprint stays inside",
			function()
				local clamped = PlacementRules.clampAnchor(grid, { column = 12, row = -3 }, { 2, 2 })
				expect(clamped.column).toBe(9)
				expect(clamped.row).toBe(1)
				expect(PlacementRules.clampAnchor(grid, { column = 1, row = 1 }, { 11, 1 })).toBeNil()
			end
		)
	end
)

describe(
	"PlacementRules.canPlace",
	function()
		local grid = PlacementRules.measureZone(ZONE_CFRAME, ZONE_SIZE, CELL)
		it(
			"refuses cells outside the grid or already taken",
			function()
				local occupancy = {}
				expect(PlacementRules.canPlace(grid, occupancy, { column = 1, row = 1 }, { 1, 1 })).toBe(true)
				expect(PlacementRules.canPlace(grid, occupancy, { column = 10, row = 6 }, { 2, 1 })).toBe(false)
				occupancy[PlacementRules.occupancyKey({ column = 2, row = 1 })] = "Placement1"
				expect(PlacementRules.canPlace(grid, occupancy, { column = 1, row = 1 }, { 2, 1 })).toBe(false)
				expect(PlacementRules.canPlace(grid, occupancy, { column = 3, row = 1 }, { 2, 1 })).toBe(true)
			end
		)
		it(
			"measures build reach from the placement's centre",
			function()
				expect(PlacementRules.isWithinBuildReach(Vector3.zero, Vector3.new(0, 0, 20), 28)).toBe(true)
				expect(PlacementRules.isWithinBuildReach(Vector3.zero, Vector3.new(0, 0, 30), 28)).toBe(false)
			end
		)
	end
)

describe(
	"PlacementRules towers",
	function()
		it(
			"reads stats by level and clamps",
			function()
				expect(PlacementRules.towerStats(SENTRY, 1).DAMAGE).toBe(6)
				expect(PlacementRules.towerStats(SENTRY, 5).MAX_HP).toBe(330)
				expect(PlacementRules.towerStats(SENTRY, 9).MAX_HP).toBe(330)
			end
		)
		it(
			"offers the next level at its price until the top",
			function()
				local offer = PlacementRules.towerUpgradeOffer(SENTRY, 1)
				expect(offer.level).toBe(2)
				expect(offer.price).toBe(15)
				expect(PlacementRules.towerUpgradeOffer(SENTRY, 4).price).toBe(120)
				expect(PlacementRules.towerUpgradeOffer(SENTRY, 5)).toBeNil()
			end
		)
		it(
			"sells for half of everything spent",
			function()
				local catalog = makeCatalog()
				expect(PlacementRules.towerTotalSpent(SENTRY, 1)).toBe(20)
				expect(PlacementRules.towerTotalSpent(SENTRY, 3)).toBe(65)
				expect(PlacementRules.sellValueFor(catalog, Enums.PlacementKind.TOWER, Enums.TowerKind.SENTRY_GUN, 3)).toBe(32)
				expect(PlacementRules.sellValueFor(catalog, Enums.PlacementKind.TRAP, Enums.TrapKind.SPIKE_TRAP, 1)).toBe(7)
			end
		)
		it(
			"keeps the share of HP through an upgrade",
			function()
				expect(PlacementRules.hpAfterUpgrade(75, 150, 180)).toBe(90)
				expect(PlacementRules.hpAfterUpgrade(0, 150, 180)).toBe(0)
			end
		)
		it(
			"prices a build and a trap consumes instead",
			function()
				local catalog = makeCatalog()
				expect(PlacementRules.buildPrice(catalog, Enums.PlacementKind.TOWER, Enums.TowerKind.SENTRY_GUN)).toBe(20)
				expect(PlacementRules.buildPrice(catalog, Enums.PlacementKind.TRAP, Enums.TrapKind.SPIKE_TRAP)).toBe(0)
				expect(PlacementRules.maxHpFor(catalog, Enums.PlacementKind.TRAP, Enums.TrapKind.SPIKE_TRAP, 1)).toBe(120)
				expect(PlacementRules.footprintFor(catalog, Enums.PlacementKind.TRAP, Enums.TrapKind.SPIKE_TRAP)[1]).toBe(2)
				expect(PlacementRules.footprintFor(catalog, Enums.PlacementKind.TOWER, 99)).toBeNil()
			end
		)
		it(
			"cycles the target priority and wraps",
			function()
				expect(PlacementRules.cycleTargetPriority(Enums.TargetPriority.CLOSEST, 1)).toBe(Enums.TargetPriority.FURTHEST)
				expect(PlacementRules.cycleTargetPriority(Enums.TargetPriority.CLOSEST, -1)).toBe(Enums.TargetPriority.WEAKEST)
				expect(PlacementRules.cycleTargetPriority(Enums.TargetPriority.WEAKEST, 1)).toBe(Enums.TargetPriority.CLOSEST)
			end
		)
		it(
			"names templates by kind",
			function()
				expect(PlacementRules.templateNameFor(Enums.PlacementKind.TOWER, Enums.TowerKind.SENTRY_GUN)).toBe("SENTRY_GUN")
				expect(PlacementRules.templateNameFor(Enums.PlacementKind.TRAP, Enums.TrapKind.GOO_PIT)).toBe("GOO_PIT")
				expect(PlacementRules.publicName(Enums.PlacementKind.TRAP, Enums.TrapKind.GOO_PIT)).toBe("Goo Pit")
			end
		)
	end
)

describe(
	"PlacementRules.resolveLoadoutTowers",
	function()
		it(
			"reads keys and public names, drops unknowns and duplicates, and defaults when empty",
			function()
				local kinds = PlacementRules.resolveLoadoutTowers({ "SENTRY_GUN", "Flamethrower", "Bogus", "sentry_gun" }, Enums.TowerKind.SENTRY_GUN)
				expect(kinds).toEqual({ Enums.TowerKind.SENTRY_GUN, Enums.TowerKind.FLAMETHROWER })
				expect(PlacementRules.resolveLoadoutTowers({ nil, "" }, Enums.TowerKind.SENTRY_GUN)).toEqual({ Enums.TowerKind.SENTRY_GUN })
			end
		)
	end
)

describe(
	"PlacementRules traps carried",
	function()
		it(
			"counts kinds and allows a fourth of a carried kind only",
			function()
				local counts = { [Enums.TrapKind.SPIKE_TRAP] = 2, [Enums.TrapKind.GOO_PIT] = 1, [Enums.TrapKind.DECOY] = 1 }
				expect(PlacementRules.countTrapKinds(counts)).toBe(3)
				expect(PlacementRules.canCarryTrap(counts, Enums.TrapKind.SPIKE_TRAP, 3)).toBe(true)
				expect(PlacementRules.canCarryTrap(counts, Enums.TrapKind.LAND_MINE, 3)).toBe(false)
				expect(PlacementRules.canCarryTrap({}, Enums.TrapKind.LAND_MINE, 3)).toBe(true)
			end
		)
	end
)

describe(
	"PlacementRules codecs",
	function()
		it(
			"round-trips the tower loadout and drops junk",
			function()
				local encoded = PlacementRules.encodeTowerLoadout({ Enums.TowerKind.SENTRY_GUN, Enums.TowerKind.AA_TURRET })
				expect(PlacementRules.decodeTowerLoadout(encoded)).toEqual({ Enums.TowerKind.SENTRY_GUN, Enums.TowerKind.AA_TURRET })
				expect(PlacementRules.decodeTowerLoadout("[99, \"x\"]")).toEqual({})
				expect(PlacementRules.decodeTowerLoadout(nil)).toEqual({})
			end
		)
		it(
			"round-trips trap counts with numeric keys",
			function()
				local counts = { [Enums.TrapKind.SPIKE_TRAP] = 2, [Enums.TrapKind.BEAR_TRAP] = 1 }
				local decoded = PlacementRules.decodeTrapCounts(PlacementRules.encodeTrapCounts(counts))
				expect(decoded[Enums.TrapKind.SPIKE_TRAP]).toBe(2)
				expect(decoded[Enums.TrapKind.BEAR_TRAP]).toBe(1)
				expect(PlacementRules.decodeTrapCounts("")).toEqual({})
			end
		)
		it(
			"round-trips the catalogue",
			function()
				local catalog = makeCatalog()
				local decoded = PlacementRules.decodeCatalog(PlacementRules.encodeCatalog(catalog))
				expect(decoded.cellSizeStuds).toBe(CELL)
				expect(decoded.maxActiveTowersPerPlayer).toBe(5)
				expect(decoded.towers[Enums.TowerKind.SENTRY_GUN].STATS_BY_LEVEL[2].DAMAGE).toBe(8)
				expect(decoded.traps[Enums.TrapKind.SPIKE_TRAP].PRICE_IRON).toBe(15)
				expect(PlacementRules.decodeCatalog("nope")).toBeNil()
			end
		)
	end
)
