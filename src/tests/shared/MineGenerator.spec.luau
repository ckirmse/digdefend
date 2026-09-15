-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local MineGenerator = require(game:GetService("ReplicatedStorage").Shared.MineGenerator)

local RockName = Enums.RockName
local RawResource = Enums.RawResource
local RockKind = Enums.RockKind
local AIR = MineGenerator.AIR

local function makeResource(resource: number, tier: number, hp: number, yield: number, radiusMin: number, radiusMax: number)
	return {
		kind = RockKind.RESOURCE,
		resource = resource,
		tier = tier,
		hp = hp,
		yield = yield,
		clusterRadiusMin = radiusMin,
		clusterRadiusMax = radiusMax,
	}
end

-- mirrors GameData/Rocks/RockDefinitions; GameData cannot load under jest
-- because it requires through the @game alias
local function makeRockTable()
	return {
		FILLER_ORDER = { RockName.STONE_1, RockName.STONE_2, RockName.STONE_3, RockName.STONE_4, RockName.STONE_5 },
		RESOURCE_TIERS = {
			[RawResource.IRON_ORE] = { RockName.IRON_1, RockName.IRON_2, RockName.IRON_3, RockName.IRON_4 },
			[RawResource.GOLD_ORE] = { RockName.GOLD_1, RockName.GOLD_2, RockName.GOLD_3, RockName.GOLD_4 },
			[RawResource.CRYSTAL] = { RockName.CRYSTAL_1, RockName.CRYSTAL_2, RockName.CRYSTAL_3, RockName.CRYSTAL_4 },
			[RawResource.URANIUM_ORE] = { RockName.URANIUM },
		},
		ROCKS = {
			[RockName.STONE_1] = { kind = RockKind.FILLER, hp = 10 },
			[RockName.STONE_2] = { kind = RockKind.FILLER, hp = 20 },
			[RockName.STONE_3] = { kind = RockKind.FILLER, hp = 40 },
			[RockName.STONE_4] = { kind = RockKind.FILLER, hp = 80 },
			[RockName.STONE_5] = { kind = RockKind.FILLER, hp = 160 },
			[RockName.IRON_1] = makeResource(RawResource.IRON_ORE, 1, 15, 3, 1, 2),
			[RockName.IRON_2] = makeResource(RawResource.IRON_ORE, 2, 30, 10, 1, 2),
			[RockName.IRON_3] = makeResource(RawResource.IRON_ORE, 3, 60, 29, 1, 2),
			[RockName.IRON_4] = makeResource(RawResource.IRON_ORE, 4, 110, 78, 0, 1),
			[RockName.GOLD_1] = makeResource(RawResource.GOLD_ORE, 1, 20, 3, 1, 2),
			[RockName.GOLD_2] = makeResource(RawResource.GOLD_ORE, 2, 40, 10, 1, 2),
			[RockName.GOLD_3] = makeResource(RawResource.GOLD_ORE, 3, 75, 30, 1, 1),
			[RockName.GOLD_4] = makeResource(RawResource.GOLD_ORE, 4, 140, 87, 0, 1),
			[RockName.CRYSTAL_1] = makeResource(RawResource.CRYSTAL, 1, 30, 2, 1, 1),
			[RockName.CRYSTAL_2] = makeResource(RawResource.CRYSTAL, 2, 60, 5, 1, 1),
			[RockName.CRYSTAL_3] = makeResource(RawResource.CRYSTAL, 3, 110, 14, 0, 1),
			[RockName.CRYSTAL_4] = makeResource(RawResource.CRYSTAL, 4, 200, 39, 0, 1),
			[RockName.URANIUM] = makeResource(RawResource.URANIUM_ORE, 1, 100, 1, 0, 0),
			[RockName.BEDROCK] = { kind = RockKind.BEDROCK },
		},
	}
end

-- mirrors GameData/Rocks/Weights, GameData/Control/Difficulty (Normal), and
-- GameData/Mines/Generation
local function makeConfig(overrides: { [string]: any }?)
	local config = {
		rockTable = makeRockTable(),
		spread = 1.2,
		minCenter = 1.0,
		maxCenter = 4.0,
		hardnessShift = 0.0,
		difficultyValue = 1.0,
		veinDivisor = 1.0,
		pickaxeReachBlocks = 3,
		isClimbingEnabled = false,
		maxPartyUraniumTargetMultiplier = 1.25,
	}
	for key, value in overrides or {} do
		config[key] = value
	end
	return config
end

-- mirrors GameData/Mines/DeadmansCanyon (the GDD worked example)
local function makeMine()
	return {
		mineId = "canyon_default",
		seed = nil,
		origin = Vector3.new(-359.259, -6, -20.911),
		facing = Enums.MineFacing.NEGATIVE_X,
		bedrockThickness = 1,
		entranceWidth = 3,
		entranceHeight = 3,
		entranceDepth = 3,
		veinEntranceClearance = 0,
		pocketRadiusMin = 1,
		pocketRadiusMax = 2,
		uraniumTarget = 20,
		defaultZoneHeight = 8,
		defaultZoneWidth = 24,
		zones = {
			{
				depth = 20,
				hardness = 1.0,
				tierBias = 1.0,
				iron = 34,
				gold = 12,
				crystal = 2,
				uranium = 2,
				pockets = 2,
				handPlaced = {
					{ rock = RockName.CRYSTAL_3, depth = 6, height = 1, widthOffset = 2 },
				},
			},
			{ depth = 24, hardness = 2.0, tierBias = 2.0, iron = 30, gold = 18, crystal = 6, uranium = 4, pockets = 3 },
			{ depth = 24, height = 12, hardness = 3.0, tierBias = 3.0, iron = 22, gold = 22, crystal = 12, uranium = 8, pockets = 4 },
			{ depth = 28, height = 16, hardness = 4.0, tierBias = 4.0, iron = 16, gold = 20, crystal = 18, uranium = 14, pockets = 5 },
		},
	}
end

local SEED = 12345

local function generateOrFail(mine, config, seed)
	local result, errors, warnings = MineGenerator.generate(mine, config or makeConfig(), seed or SEED)
	expect(errors).toEqual({})
	expect(result).never.toBeNil()
	return result, warnings
end

local function countRock(grid, box, rock)
	local count = 0
	for depth = box.depthStart, box.depthEnd do
		for height = box.heightStart, box.heightEnd do
			for width = box.widthStart, box.widthEnd do
				if MineGenerator.getCell(grid, depth, height, width) == rock then
					count += 1
				end
			end
		end
	end
	return count
end

local function boxOf(zone)
	return {
		depthStart = zone.depthStart,
		depthEnd = zone.depthStart + zone.depth - 1,
		heightStart = zone.heightStart,
		heightEnd = zone.heightStart + zone.height - 1,
		widthStart = zone.widthStart,
		widthEnd = zone.widthStart + zone.width - 1,
	}
end

-- the entrance is 3 wide centred on width 12 (centreline of 24 leaning positive)
local ENTRANCE_WIDTHS = { 11, 12, 13 }

describe(
	"MineGenerator.generate on the worked example",
	function()
		it(
			"sizes the grid from the zone list and bedrock, with no dividers",
			function()
				local result = generateOrFail(makeMine())
				expect(result.grid.depth).toBe(1 + 20 + 24 + 24 + 28 + 1)
				expect(result.grid.height).toBe(16 + 1 + 1)
				expect(result.grid.width).toBe(24 + 2)
				expect(#result.grid.cells).toBe(result.grid.depth * result.grid.height * result.grid.width)
				expect(result.report.gridDepth).toBe(result.grid.depth)
			end
		)

		it(
			"resolves inheritance and lays zones end to end",
			function()
				local result = generateOrFail(makeMine())
				local zones = result.zones
				expect(#zones).toBe(4)
				expect(zones[2].height).toBe(8)
				expect(zones[2].width).toBe(24)
				expect(zones[2].veins[RawResource.URANIUM_ORE]).toBe(4)
				expect(zones[2].pockets).toBe(3)
				expect(zones[4].height).toBe(16)
				expect(zones[1].depthStart).toBe(1)
				expect(zones[2].depthStart).toBe(1 + 20)
				expect(zones[4].depthStart).toBe(1 + 20 + 24 + 24)
				expect(zones[1].heightStart).toBe(1)
				expect(zones[1].widthStart).toBe(1)
			end
		)

		it(
			"wraps the whole mine in a bedrock shell with only the mouth open",
			function()
				local result = generateOrFail(makeMine())
				local grid = result.grid
				-- floor, ceiling, and both side walls are solid along the whole grid
				for depth = 0, grid.depth - 1 do
					for width = 0, grid.width - 1 do
						expect(MineGenerator.getCell(grid, depth, 0, width)).toBe(RockName.BEDROCK)
						expect(MineGenerator.getCell(grid, depth, grid.height - 1, width)).toBe(RockName.BEDROCK)
					end
					for height = 0, grid.height - 1 do
						expect(MineGenerator.getCell(grid, depth, height, 0)).toBe(RockName.BEDROCK)
						expect(MineGenerator.getCell(grid, depth, height, grid.width - 1)).toBe(RockName.BEDROCK)
					end
				end
				-- the far wall is solid
				for height = 0, grid.height - 1 do
					for width = 0, grid.width - 1 do
						expect(MineGenerator.getCell(grid, grid.depth - 1, height, width)).toBe(RockName.BEDROCK)
					end
				end
				-- the front face is bedrock everywhere except the mouth
				local mouth = 0
				for height = 0, grid.height - 1 do
					for width = 0, grid.width - 1 do
						local cell = MineGenerator.getCell(grid, 0, height, width)
						if cell == AIR then
							mouth += 1
						else
							expect(cell).toBe(RockName.BEDROCK)
						end
					end
				end
				expect(mouth).toBe(3 * 3)
				-- zone 1 is 8 tall inside an 18-tall grid, so everything above it is bedrock
				local zone1 = result.zones[1]
				for depth = zone1.depthStart, zone1.depthStart + zone1.depth - 1 do
					for height = zone1.heightStart + zone1.height, grid.height - 1 do
						for width = 0, grid.width - 1 do
							expect(MineGenerator.getCell(grid, depth, height, width)).toBe(RockName.BEDROCK)
						end
					end
				end
			end
		)

		it(
			"carves the entrance tunnel through the front face and entranceDepth blocks in",
			function()
				local result = generateOrFail(makeMine())
				local grid = result.grid
				for _, width in ENTRANCE_WIDTHS do
					for height = 1, 3 do
						for depth = 0, 3 do
							expect(MineGenerator.getCell(grid, depth, height, width)).toBe(AIR)
						end
					end
					-- above the tunnel the mouth stays bedrock
					expect(MineGenerator.getCell(grid, 0, 4, width)).toBe(RockName.BEDROCK)
				end
				-- beside the tunnel the front face is bedrock
				expect(MineGenerator.getCell(grid, 0, 1, 10)).toBe(RockName.BEDROCK)
				expect(MineGenerator.getCell(grid, 0, 1, 14)).toBe(RockName.BEDROCK)
			end
		)

		it(
			"leaves no walls between zones, so a player can dig straight through",
			function()
				local result = generateOrFail(makeMine())
				local grid = result.grid
				local rocks = makeRockTable().ROCKS
				for zoneIndex = 1, 3 do
					local boundary = result.zones[zoneIndex + 1].depthStart
					for height = 1, 8 do
						for width = 1, 24 do
							local cell = MineGenerator.getCell(grid, boundary, height, width)
							expect(cell == AIR or rocks[cell].kind ~= RockKind.BEDROCK).toBe(true)
						end
					end
				end
			end
		)

		it(
			"fills zone interiors with filler, resource rock, and pocket air",
			function()
				local result = generateOrFail(makeMine())
				local rocks = makeRockTable().ROCKS
				local zone2 = result.zones[2]
				local box = boxOf(zone2)
				local air = 0
				local seenHardStone = false
				for depth = box.depthStart, box.depthEnd do
					for height = box.heightStart, box.heightEnd do
						for width = box.widthStart, box.widthEnd do
							local cell = MineGenerator.getCell(result.grid, depth, height, width)
							if cell == AIR then
								air += 1
								continue
							end
							local kind = rocks[cell].kind
							expect(kind == RockKind.FILLER or kind == RockKind.RESOURCE).toBe(true)
							if cell == RockName.STONE_4 or cell == RockName.STONE_5 then
								seenHardStone = true
							end
						end
					end
				end
				-- three pockets of radius 1 to 2: at least 3 cells, at most 3 x 33
				expect(air).toBeGreaterThan(2)
				expect(air).toBeLessThan(100)
				expect(result.report.zones[2].pocketVolume).toBe(air)
				-- hardness 2.0 never reaches stone 4 or 5 at spread 1.2
				expect(seenHardStone).toBe(false)
			end
		)

		it(
			"carves no pockets when a zone asks for none",
			function()
				local mine = makeMine()
				for _, zone in mine.zones do
					zone.pockets = 0
				end
				local result = generateOrFail(mine)
				for index, zone in result.zones do
					local expectedAir = if index == 1 then 3 * 3 * 3 else 0
					expect(countRock(result.grid, boxOf(zone), AIR)).toBe(expectedAir)
				end
			end
		)

		it(
			"never places a vein inside a pocket",
			function()
				-- with every cell a pocket candidate, veins must still land on rock:
				-- generate, then check no resource rock sits where the same seed's
				-- pocket-only pass carved air
				local pocketsOnly = makeMine()
				for _, zone in pocketsOnly.zones do
					zone.iron = 0
					zone.gold = 0
					zone.crystal = 0
					zone.handPlaced = {}
				end
				pocketsOnly.uraniumTarget = 1
				local bare = generateOrFail(pocketsOnly)
				local full = generateOrFail(makeMine())
				for index, cell in bare.grid.cells do
					if cell == AIR then
						expect(full.grid.cells[index]).toBe(AIR)
					end
				end
			end
		)

		it(
			"stamps the hand-placed Crystal 3 where the designer put it",
			function()
				local mine = makeMine()
				mine.zones[1].handPlaced[1].cluster = 0
				local result = generateOrFail(mine)
				local zone1 = result.zones[1]
				-- depth 6 from the front face, height 1 up from the floor, 2 right of the centreline (12)
				expect(MineGenerator.getCell(result.grid, zone1.depthStart + 6, zone1.heightStart + 1, 14)).toBe(RockName.CRYSTAL_3)
			end
		)

		it(
			"is reproducible from a seed and differs between seeds",
			function()
				local first = generateOrFail(makeMine(), nil, 777)
				local second = generateOrFail(makeMine(), nil, 777)
				local third = generateOrFail(makeMine(), nil, 778)
				expect(second.grid.cells).toEqual(first.grid.cells)
				expect(third.grid.cells).never.toEqual(first.grid.cells)
				expect(first.report.seed).toBe(777)
			end
		)

		it(
			"draws and reports a fresh seed when none is given",
			function()
				local result, errors = MineGenerator.generate(makeMine(), makeConfig(), nil)
				expect(errors).toEqual({})
				expect(result.report.seed).toBeGreaterThan(0)
			end
		)

		it(
			"leaves zone 1 untouched when zone 2 is edited",
			function()
				local before = generateOrFail(makeMine())
				local edited = makeMine()
				edited.zones[2].iron = 5
				edited.zones[2].hardness = 3.5
				edited.zones[2].pockets = 0
				local after = generateOrFail(edited)
				local box = boxOf(before.zones[1])
				for depth = box.depthStart, box.depthEnd do
					for height = box.heightStart, box.heightEnd do
						for width = box.widthStart, box.widthEnd do
							expect(MineGenerator.getCell(after.grid, depth, height, width)).toBe(MineGenerator.getCell(before.grid, depth, height, width))
						end
					end
				end
			end
		)

		it(
			"keeps veins clear of the entrance when clearance is set",
			function()
				local mine = makeMine()
				mine.veinEntranceClearance = 2
				mine.zones[1].handPlaced = {}
				mine.zones[1].pockets = 0
				local result = generateOrFail(mine)
				local rocks = makeRockTable().ROCKS
				-- every cell within 2 blocks of the tunnel volume must be filler or air
				for depth = 1, 3 + 2 do
					for height = 1, 3 + 2 do
						for width = 11 - 2, 13 + 2 do
							local cell = MineGenerator.getCell(result.grid, depth, height, width)
							if cell ~= AIR then
								expect(rocks[cell].kind).toBe(RockKind.FILLER)
							end
						end
					end
				end
			end
		)

		it(
			"reports diggable volume, reach, pockets, and placed versus requested ore",
			function()
				local result = generateOrFail(makeMine())
				local report = result.report
				expect(#report.zones).toBe(4)
				local zone1 = report.zones[1]
				expect(zone1.diggableVolume + zone1.pocketVolume).toBe(20 * 8 * 24)
				expect(zone1.pocketVolume).toBeGreaterThan(3 * 3 * 3 - 1)
				expect(zone1.reachableShare).toBeGreaterThan(0.3)
				expect(zone1.reachableShare).toBeLessThan(0.45)
				expect(zone1.placedOre[RawResource.IRON_ORE]).toBeGreaterThan(0)
				expect(zone1.requestedOre[RawResource.IRON_ORE]).toBeGreaterThan(0)
				expect(zone1.placedOre[RawResource.URANIUM_ORE]).toBe(2)
				expect(zone1.placedHp).toBeGreaterThan(0)
				-- uranium clusters are single blocks that yield one, so placed matches requested
				local zone4 = report.zones[4]
				expect(zone4.requestedOre[RawResource.URANIUM_ORE]).toBe(14)
				expect(zone4.placedOre[RawResource.URANIUM_ORE]).toBe(14)
				-- the counter climbs through every zone
				expect(report.zones[1].uraniumSoFar).toBe(2)
				expect(report.zones[2].uraniumSoFar).toBe(6)
				expect(report.zones[3].uraniumSoFar).toBe(14)
				expect(zone4.uraniumSoFar).toBe(28)
				-- the cathedral is mostly out of reach from a standing start
				expect(zone4.reachableShare).toBeLessThan(0.25)
				expect(MineGenerator.formatReport(report)).toContain("zone 4")
			end
		)

		it(
			"counts hand-placed rock in requested ore",
			function()
				local mine = makeMine()
				mine.zones[1].handPlaced[1].cluster = 1
				local result = generateOrFail(mine)
				-- 2 crystal 1 clusters (7 cells x 2) plus one 7-cell Crystal 3 at 14 yield
				expect(result.report.zones[1].requestedOre[RawResource.CRYSTAL]).toBeCloseTo(2 * 7 * 2 + 7 * 14, 6)
			end
		)

		it(
			"applies the vein divisor to every ore except uranium",
			function()
				local result = generateOrFail(makeMine(), makeConfig({ veinDivisor = 1.4, difficultyValue = 1.9 }))
				local zone2 = result.zones[2]
				expect(zone2.hardness).toBeCloseTo(2.0, 9)
				expect(zone2.veins[RawResource.IRON_ORE]).toBe(21)
				expect(zone2.veins[RawResource.GOLD_ORE]).toBe(13)
				expect(zone2.veins[RawResource.CRYSTAL]).toBe(4)
				expect(result.zones[4].veins[RawResource.URANIUM_ORE]).toBe(14)
			end
		)

		it(
			"places every uranium rock within pickaxe reach of the floor",
			function()
				local result = generateOrFail(makeMine())
				local grid = result.grid
				local found = 0
				for depth = 0, grid.depth - 1 do
					for height = 0, grid.height - 1 do
						for width = 0, grid.width - 1 do
							if MineGenerator.getCell(grid, depth, height, width) == RockName.URANIUM then
								found += 1
								-- the floor sits on the 1-block bedrock floor
								expect(height - 1).toBeLessThan(3)
							end
						end
					end
				end
				expect(found).toBe(result.report.zones[4].uraniumSoFar)
			end
		)
	end
)

describe(
	"MineGenerator validation",
	function()
		local function expectFatal(mine, fragment: string, config)
			local result, errors = MineGenerator.generate(mine, config or makeConfig(), SEED)
			expect(result).toBeNil()
			expect(#errors).toBeGreaterThan(0)
			expect(table.concat(errors, "\n")).toContain(fragment)
		end

		it(
			"refuses a mine whose uranium cannot cover the target for the largest party",
			function()
				local mine = makeMine()
				mine.zones[4].uranium = 6
				expectFatal(mine, "uranium")
			end
		)

		it(
			"refuses a zone dimension below 1, naming the zone",
			function()
				local mine = makeMine()
				mine.zones[3].height = 0
				expectFatal(mine, "zone 3: height")
			end
		)

		it(
			"refuses a negative pocket count, naming the zone",
			function()
				local mine = makeMine()
				mine.zones[2].pockets = -1
				expectFatal(mine, "zone 2: pockets")
			end
		)

		it(
			"refuses an entrance wider or taller than zone 1, or deeper than it",
			function()
				local wide = makeMine()
				wide.entranceWidth = 25
				expectFatal(wide, "entranceWidth")
				local tall = makeMine()
				tall.entranceHeight = 9
				expectFatal(tall, "entranceHeight")
				local deep = makeMine()
				deep.entranceDepth = 21
				expectFatal(deep, "entranceDepth")
			end
		)

		it(
			"refuses pocket radii that are negative or inverted",
			function()
				local negative = makeMine()
				negative.pocketRadiusMin = -1
				expectFatal(negative, "pocketRadiusMin")
				local inverted = makeMine()
				inverted.pocketRadiusMax = 0
				expectFatal(inverted, "pocketRadiusMax")
			end
		)

		it(
			"refuses an invalid facing",
			function()
				local mine = makeMine()
				mine.facing = 99
				expectFatal(mine, "facing")
			end
		)

		it(
			"refuses a first zone missing its depth",
			function()
				local mine = makeMine()
				mine.zones[1].depth = nil
				expectFatal(mine, "zone 1: depth")
			end
		)

		it(
			"refuses an empty zone list",
			function()
				local mine = makeMine()
				mine.zones = {}
				expectFatal(mine, "zones")
			end
		)

		it(
			"warns about an entrance above reach without climbing",
			function()
				local mine = makeMine()
				mine.entranceHeight = 5
				local _, warnings = generateOrFail(mine)
				expect(table.concat(warnings, "\n")).toContain("entranceHeight 5 is above pickaxe reach")
				local _, climbingWarnings = generateOrFail(mine, makeConfig({ isClimbingEnabled = true }))
				expect(table.concat(climbingWarnings, "\n")).never.toContain("above pickaxe reach")
			end
		)

		it(
			"warns and clamps hardness and tierBias outside the range",
			function()
				local mine = makeMine()
				mine.zones[2].hardness = 7
				mine.zones[2].tierBias = 0.2
				local result, warnings = generateOrFail(mine)
				expect(result.zones[2].hardness).toBe(5)
				expect(result.zones[2].tierBias).toBe(1)
				local joined = table.concat(warnings, "\n")
				expect(joined).toContain("zone 2: hardness")
				expect(joined).toContain("zone 2: tierBias")
			end
		)

		it(
			"warns when hand-placed rock is outside its zone or inside the entrance",
			function()
				local mine = makeMine()
				mine.zones[1].handPlaced = {
					{ rock = RockName.GOLD_4, depth = 1, height = 1, widthOffset = 0 },
					{ rock = RockName.GOLD_4, depth = 99, height = 1, widthOffset = 0 },
				}
				local _, warnings = generateOrFail(mine)
				local joined = table.concat(warnings, "\n")
				expect(joined).toContain("handPlaced[1]: falls inside the entrance")
				expect(joined).toContain("handPlaced[2]: falls outside the zone")
			end
		)

		it(
			"applies bedrock overrides per face",
			function()
				local mine = makeMine()
				mine.bedrockOverrides = { far = 3, side = 2 }
				local result = generateOrFail(mine)
				expect(result.grid.depth).toBe(1 + 96 + 3)
				expect(result.grid.width).toBe(24 + 4)
				expect(result.zones[1].widthStart).toBe(2)
			end
		)
	end
)

describe(
	"MineGenerator.preview",
	function()
		it(
			"matches the report's requested ore without building a grid",
			function()
				local previews, errors = MineGenerator.preview(makeMine(), makeConfig())
				expect(errors).toEqual({})
				local result = generateOrFail(makeMine())
				for index, preview in previews do
					for _, resource in Enums.getAllValues(RawResource) do
						expect(preview.requestedOre[resource]).toBeCloseTo(result.report.zones[index].requestedOre[resource], 6)
					end
					expect(preview.expectedHp).toBeGreaterThan(0)
				end
				-- zone 4 is bigger and harder than zone 1, so it costs more hp
				expect(previews[4].expectedHp).toBeGreaterThan(previews[1].expectedHp)
			end
		)

		it(
			"reports the same fatal errors as generate",
			function()
				local mine = makeMine()
				mine.zones[4].uranium = 0
				mine.zones[3].uranium = 0
				local previews, errors = MineGenerator.preview(mine, makeConfig())
				expect(previews).toBeNil()
				expect(table.concat(errors, "\n")).toContain("uranium")
			end
		)
	end
)

describe(
	"MineGenerator filler on the wire",
	function()
		it(
			"collapses filler to a placeholder and expands it back to the identical grid",
			function()
				local result = generateOrFail(makeMine())
				local fillerOrder = makeRockTable().FILLER_ORDER
				local collapsed = MineGenerator.collapseFiller(result.grid.cells, fillerOrder)
				local placeholders = 0
				for _, rock in collapsed do
					if rock == MineGenerator.FILLER_PLACEHOLDER then
						placeholders += 1
					end
					expect(rock < RockName.STONE_1 or rock > RockName.STONE_5).toBe(true)
				end
				expect(placeholders).toBeGreaterThan(10000)

				local fills = {}
				for _, zone in result.zones do
					table.insert(fills, {
						index = zone.index,
						depthStart = zone.depthStart,
						depth = zone.depth,
						heightStart = zone.heightStart,
						height = zone.height,
						widthStart = zone.widthStart,
						width = zone.width,
						fillerWeights = zone.fillerWeights,
					})
				end
				local rebuilt = {
					depth = result.grid.depth,
					height = result.grid.height,
					width = result.grid.width,
					centrelineWidth = result.grid.centrelineWidth,
					floorHeight = result.grid.floorHeight,
					cells = collapsed,
				}
				MineGenerator.expandFiller(rebuilt, fills, result.report.seed, fillerOrder)
				expect(rebuilt.cells).toEqual(result.grid.cells)
			end
		)
	end
)

describe(
	"MineGenerator.clusterCellCount",
	function()
		it(
			"counts discrete spheres",
			function()
				expect(MineGenerator.clusterCellCount(0)).toBe(1)
				expect(MineGenerator.clusterCellCount(1)).toBe(7)
				expect(MineGenerator.clusterCellCount(2)).toBe(33)
			end
		)
	end
)
