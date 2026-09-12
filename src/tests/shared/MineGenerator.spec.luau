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
		FILLER_ORDER = { RockName.SHALE, RockName.SANDSTONE, RockName.GRANITE, RockName.BASALT },
		RESOURCE_TIERS = {
			[RawResource.IRON_ORE] = { RockName.IRON_1, RockName.IRON_2, RockName.IRON_3, RockName.IRON_4 },
			[RawResource.GOLD_ORE] = { RockName.GOLD_1, RockName.GOLD_2, RockName.GOLD_3, RockName.GOLD_4 },
			[RawResource.CRYSTAL] = { RockName.CRYSTAL_1, RockName.CRYSTAL_2, RockName.CRYSTAL_3, RockName.CRYSTAL_4 },
			[RawResource.URANIUM_ORE] = { RockName.URANIUM },
		},
		ROCKS = {
			[RockName.SHALE] = { kind = RockKind.FILLER, hp = 10 },
			[RockName.SANDSTONE] = { kind = RockKind.FILLER, hp = 20 },
			[RockName.GRANITE] = { kind = RockKind.FILLER, hp = 40 },
			[RockName.BASALT] = { kind = RockKind.FILLER, hp = 80 },
			[RockName.IRON_1] = makeResource(RawResource.IRON_ORE, 1, 15, 5, 1, 2),
			[RockName.IRON_2] = makeResource(RawResource.IRON_ORE, 2, 30, 16, 1, 2),
			[RockName.IRON_3] = makeResource(RawResource.IRON_ORE, 3, 60, 48, 1, 2),
			[RockName.IRON_4] = makeResource(RawResource.IRON_ORE, 4, 110, 130, 0, 1),
			[RockName.GOLD_1] = makeResource(RawResource.GOLD_ORE, 1, 20, 5, 1, 2),
			[RockName.GOLD_2] = makeResource(RawResource.GOLD_ORE, 2, 40, 17, 1, 2),
			[RockName.GOLD_3] = makeResource(RawResource.GOLD_ORE, 3, 75, 50, 1, 1),
			[RockName.GOLD_4] = makeResource(RawResource.GOLD_ORE, 4, 140, 145, 0, 1),
			[RockName.CRYSTAL_1] = makeResource(RawResource.CRYSTAL, 1, 30, 3, 1, 1),
			[RockName.CRYSTAL_2] = makeResource(RawResource.CRYSTAL, 2, 60, 9, 1, 1),
			[RockName.CRYSTAL_3] = makeResource(RawResource.CRYSTAL, 3, 110, 24, 0, 1),
			[RockName.CRYSTAL_4] = makeResource(RawResource.CRYSTAL, 4, 200, 65, 0, 1),
			[RockName.URANIUM] = makeResource(RawResource.URANIUM_ORE, 1, 100, 1, 0, 0),
			[RockName.BEDROCK] = { kind = RockKind.BEDROCK },
			[RockName.GATE] = { kind = RockKind.GATE },
		},
	}
end

-- mirrors GameData/Rocks/Weights, GameData/Control/Difficulty (Normal), and
-- GameData/Mines/Generation
local function makeConfig(overrides: { [string]: any }?)
	local config = {
		rockTable = makeRockTable(),
		spread = 1.5,
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
		startingCampLevel = 1,
		bedrockThickness = 1,
		veinCorridorClearance = 0,
		uraniumTarget = 20,
		defaultChamberHeight = 8,
		defaultChamberWidth = 24,
		chambers = {
			{
				depth = 20,
				hardness = 1.2,
				tierBias = 1.0,
				iron = 34,
				gold = 12,
				crystal = 2,
				uranium = 2,
				corridorWidth = 3,
				corridorHeight = 3,
				handPlaced = {
					{ rock = RockName.CRYSTAL_3, depth = 6, height = 1, widthOffset = 2 },
				},
			},
			{ depth = 24, hardness = 2.1, tierBias = 2.0, iron = 30, gold = 18, crystal = 6, uranium = 4 },
			{ depth = 24, height = 12, hardness = 3.0, tierBias = 3.0, iron = 22, gold = 22, crystal = 12, uranium = 8, corridorHeight = 5 },
			{ depth = 28, height = 16, hardness = 3.7, tierBias = 4.0, iron = 16, gold = 20, crystal = 18, uranium = 14 },
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

local function boxOf(chamber)
	return {
		depthStart = chamber.depthStart,
		depthEnd = chamber.depthStart + chamber.depth - 1,
		heightStart = chamber.heightStart,
		heightEnd = chamber.heightStart + chamber.height - 1,
		widthStart = chamber.widthStart,
		widthEnd = chamber.widthStart + chamber.width - 1,
	}
end

describe(
	"MineGenerator.generate on the worked example",
	function()
		it(
			"sizes the grid from the chamber list and bedrock",
			function()
				local result = generateOrFail(makeMine())
				expect(result.grid.depth).toBe(1 + 20 + 24 + 24 + 28 + 3 + 1)
				expect(result.grid.height).toBe(16 + 1 + 1)
				expect(result.grid.width).toBe(24 + 2)
				expect(#result.grid.cells).toBe(result.grid.depth * result.grid.height * result.grid.width)
				expect(result.report.gridDepth).toBe(result.grid.depth)
			end
		)

		it(
			"resolves inheritance and derives unlock level and corridor presence",
			function()
				local result = generateOrFail(makeMine())
				local chambers = result.chambers
				expect(#chambers).toBe(4)
				expect(chambers[2].height).toBe(8)
				expect(chambers[2].width).toBe(24)
				expect(chambers[2].corridorWidth).toBe(3)
				expect(chambers[2].corridorHeight).toBe(3)
				expect(chambers[2].veins[RawResource.URANIUM_ORE]).toBe(4)
				expect(chambers[3].corridorHeight).toBe(5)
				expect(chambers[4].height).toBe(16)
				expect(chambers[4].hasCorridor).toBe(false)
				expect(chambers[3].hasCorridor).toBe(true)
				for index, chamber in chambers do
					expect(chamber.unlockCampLevel).toBe(index)
				end
				expect(chambers[1].depthStart).toBe(1)
				expect(chambers[2].depthStart).toBe(1 + 20 + 1)
				expect(chambers[4].depthStart).toBe(1 + 20 + 1 + 24 + 1 + 24 + 1)
				expect(chambers[1].heightStart).toBe(1)
				expect(chambers[1].widthStart).toBe(1)
			end
		)

		it(
			"seals every chamber in bedrock except where the corridor passes",
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
				-- the far wall behind chamber 4 is solid
				for height = 0, grid.height - 1 do
					for width = 0, grid.width - 1 do
						expect(MineGenerator.getCell(grid, grid.depth - 1, height, width)).toBe(RockName.BEDROCK)
					end
				end
				-- chamber 1 is 8 tall inside an 18-tall grid, so everything above it is bedrock
				local chamber1 = result.chambers[1]
				for depth = chamber1.depthStart, chamber1.depthStart + chamber1.depth - 1 do
					for height = chamber1.heightStart + chamber1.height, grid.height - 1 do
						for width = 0, grid.width - 1 do
							expect(MineGenerator.getCell(grid, depth, height, width)).toBe(RockName.BEDROCK)
						end
					end
				end
			end
		)

		it(
			"opens the mine mouth, carves corridors as air, and gates the dividers",
			function()
				local result = generateOrFail(makeMine())
				local grid = result.grid
				local chamber1 = result.chambers[1]
				-- the corridor is 3 wide centred on width 12 (centreline of 24 leaning positive), 3 tall from the floor
				local corridorWidths = { 11, 12, 13 }
				expect(chamber1.corridorWidthStart).toBe(11)
				for _, width in corridorWidths do
					for height = 1, 3 do
						-- mouth through the front bedrock
						expect(MineGenerator.getCell(grid, 0, height, width)).toBe(AIR)
						-- corridor through chamber 1
						expect(MineGenerator.getCell(grid, 10, height, width)).toBe(AIR)
						-- gate in the divider between chambers 1 and 2
						expect(MineGenerator.getCell(grid, 21, height, width)).toBe(RockName.GATE)
					end
					-- above the corridor the mouth stays bedrock and the divider stays bedrock
					expect(MineGenerator.getCell(grid, 0, 4, width)).toBe(RockName.BEDROCK)
					expect(MineGenerator.getCell(grid, 21, 4, width)).toBe(RockName.BEDROCK)
				end
				-- beside the corridor the front face is bedrock
				expect(MineGenerator.getCell(grid, 0, 1, 10)).toBe(RockName.BEDROCK)
				expect(MineGenerator.getCell(grid, 0, 1, 14)).toBe(RockName.BEDROCK)
				-- chamber 3's corridor is 5 tall, so its gate is 5 tall
				local chamber3 = result.chambers[3]
				local divider3 = chamber3.depthStart + chamber3.depth
				expect(MineGenerator.getCell(grid, divider3, 5, 12)).toBe(RockName.GATE)
				expect(MineGenerator.getCell(grid, divider3, 6, 12)).toBe(RockName.BEDROCK)
				-- chamber 4 has no corridor: a player past the last gate faces solid rock
				local chamber4 = result.chambers[4]
				expect(countRock(grid, boxOf(chamber4), AIR)).toBe(0)
				expect(countRock(grid, boxOf(chamber4), RockName.GATE)).toBe(0)
				-- gate count: three dividers, each 3 x 3 except the third which is 3 x 5
				local gates = 0
				for _, cell in grid.cells do
					if cell == RockName.GATE then
						gates += 1
					end
				end
				expect(gates).toBe(9 + 9 + 15)
			end
		)

		it(
			"fills chamber interiors with only filler and resource rock",
			function()
				local result = generateOrFail(makeMine())
				local rocks = makeRockTable().ROCKS
				local chamber2 = result.chambers[2]
				local box = boxOf(chamber2)
				local corridorCells = chamber2.depth * chamber2.corridorHeight * chamber2.corridorWidth
				local air = 0
				local seenBasalt = false
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
							if cell == RockName.BASALT then
								seenBasalt = true
							end
						end
					end
				end
				expect(air).toBe(corridorCells)
				-- hardness 2.1 never reaches basalt at spread 1.5
				expect(seenBasalt).toBe(false)
			end
		)

		it(
			"stamps the hand-placed Crystal 3 where the designer put it",
			function()
				local mine = makeMine()
				mine.chambers[1].handPlaced[1].cluster = 0
				local result = generateOrFail(mine)
				local chamber1 = result.chambers[1]
				-- depth 6 from the front face, height 1 up from the floor, 2 right of the corridor centreline (12)
				expect(MineGenerator.getCell(result.grid, chamber1.depthStart + 6, chamber1.heightStart + 1, 14)).toBe(RockName.CRYSTAL_3)
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
			"leaves chamber 1 untouched when chamber 2 is edited",
			function()
				local before = generateOrFail(makeMine())
				local edited = makeMine()
				edited.chambers[2].iron = 5
				edited.chambers[2].hardness = 3.5
				local after = generateOrFail(edited)
				local box = boxOf(before.chambers[1])
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
			"keeps veins clear of the corridor when clearance is set",
			function()
				local mine = makeMine()
				mine.veinCorridorClearance = 2
				mine.chambers[1].handPlaced = {}
				local result = generateOrFail(mine)
				local rocks = makeRockTable().ROCKS
				local chamber1 = result.chambers[1]
				-- every cell within 2 blocks of the corridor volume must be filler or air
				for depth = chamber1.depthStart, chamber1.depthStart + chamber1.depth - 1 do
					for height = chamber1.heightStart, chamber1.heightStart + chamber1.corridorHeight - 1 + 2 do
						for width = chamber1.corridorWidthStart - 2, chamber1.corridorWidthStart + chamber1.corridorWidth - 1 + 2 do
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
			"reports diggable volume, reach, and placed versus requested ore",
			function()
				local result = generateOrFail(makeMine())
				local report = result.report
				expect(#report.chambers).toBe(4)
				local chamber1 = report.chambers[1]
				expect(chamber1.diggableVolume).toBe(20 * 8 * 24 - 20 * 3 * 3)
				-- 3 of 8 rows are within reach, minus the corridor rows which are air
				expect(chamber1.reachableShare).toBeCloseTo((20 * 3 * 24 - 20 * 3 * 3) / chamber1.diggableVolume, 6)
				expect(chamber1.placedOre[RawResource.IRON_ORE]).toBeGreaterThan(0)
				expect(chamber1.requestedOre[RawResource.IRON_ORE]).toBeGreaterThan(0)
				expect(chamber1.placedOre[RawResource.URANIUM_ORE]).toBe(2)
				expect(chamber1.placedHp).toBeGreaterThan(0)
				-- uranium clusters are single blocks that yield one, so placed matches requested unless overwritten
				local chamber4 = report.chambers[4]
				expect(chamber4.requestedOre[RawResource.URANIUM_ORE]).toBe(14)
				expect(chamber4.placedOre[RawResource.URANIUM_ORE]).toBe(14)
				-- the counter climbs through every chamber and only clears the target at the last
				expect(report.chambers[1].uraniumSoFar).toBe(2)
				expect(report.chambers[2].uraniumSoFar).toBe(6)
				expect(report.chambers[3].uraniumSoFar).toBe(14)
				expect(chamber4.uraniumSoFar).toBe(28)
				-- the cathedral is mostly decoration from a standing start
				expect(chamber4.reachableShare).toBeLessThan(0.25)
				expect(MineGenerator.formatReport(report)).toContain("chamber 4")
			end
		)

		it(
			"counts hand-placed rock in requested ore and never warns about the last chamber's corridor",
			function()
				local mine = makeMine()
				mine.chambers[1].handPlaced[1].cluster = 1
				local result, warnings = generateOrFail(mine)
				-- 2 crystal 1 clusters (1 cell each at radius 1 = 7 cells x 3) plus one 7-cell Crystal 3 at 24 yield
				expect(result.report.chambers[1].requestedOre[RawResource.CRYSTAL]).toBeCloseTo(2 * 7 * 3 + 7 * 24, 6)
				expect(table.concat(warnings, "\n")).never.toContain("chamber 4")
			end
		)

		it(
			"applies the vein divisor to every ore except uranium",
			function()
				local result = generateOrFail(makeMine(), makeConfig({ veinDivisor = 1.4, difficultyValue = 1.9 }))
				local chamber2 = result.chambers[2]
				expect(chamber2.hardness).toBeCloseTo(2.1, 9)
				expect(chamber2.veins[RawResource.IRON_ORE]).toBe(21)
				expect(chamber2.veins[RawResource.GOLD_ORE]).toBe(13)
				expect(chamber2.veins[RawResource.CRYSTAL]).toBe(4)
				expect(result.chambers[4].veins[RawResource.URANIUM_ORE]).toBe(14)
			end
		)

		it(
			"places every uranium rock within pickaxe reach of the chamber floor",
			function()
				local result = generateOrFail(makeMine())
				local grid = result.grid
				local found = 0
				for depth = 0, grid.depth - 1 do
					for height = 0, grid.height - 1 do
						for width = 0, grid.width - 1 do
							if MineGenerator.getCell(grid, depth, height, width) == RockName.URANIUM then
								found += 1
								-- every chamber floor sits on the 1-block bedrock floor
								expect(height - 1).toBeLessThan(3)
							end
						end
					end
				end
				expect(found).toBe(result.report.chambers[4].uraniumSoFar)
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
				mine.chambers[4].uranium = 6
				expectFatal(mine, "uranium")
			end
		)

		it(
			"refuses a mine that can be finished before the last chamber",
			function()
				local mine = makeMine()
				mine.chambers[3].uranium = 14
				expectFatal(mine, "the last chamber must be required")
			end
		)

		it(
			"refuses a chamber dimension below 1, naming the chamber",
			function()
				local mine = makeMine()
				mine.chambers[3].height = 0
				expectFatal(mine, "chamber 3: height")
			end
		)

		it(
			"refuses a corridor as wide as its chamber",
			function()
				local mine = makeMine()
				mine.chambers[2].corridorWidth = 24
				expectFatal(mine, "chamber 2: corridorWidth")
			end
		)

		it(
			"refuses a starting camp level that opens nothing",
			function()
				local mine = makeMine()
				mine.startingCampLevel = 0
				expectFatal(mine, "startingCampLevel")
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
			"refuses a first chamber missing a required field",
			function()
				local mine = makeMine()
				mine.chambers[1].corridorWidth = nil
				expectFatal(mine, "chamber 1: corridorWidth")
			end
		)

		it(
			"refuses an empty chamber list",
			function()
				local mine = makeMine()
				mine.chambers = {}
				expectFatal(mine, "chambers")
			end
		)

		it(
			"warns and clamps a corridor taller than its chamber",
			function()
				local mine = makeMine()
				mine.chambers[2].corridorHeight = 50
				local result, warnings = generateOrFail(mine)
				expect(result.chambers[2].corridorHeight).toBe(8)
				expect(table.concat(warnings, "\n")).toContain("chamber 2: corridorHeight")
			end
		)

		it(
			"warns about a corridor above reach but below full without climbing",
			function()
				local _, warnings = generateOrFail(makeMine())
				expect(table.concat(warnings, "\n")).toContain("chamber 3: corridorHeight 5 is above pickaxe reach")
				local _, climbingWarnings = generateOrFail(makeMine(), makeConfig({ isClimbingEnabled = true }))
				expect(table.concat(climbingWarnings, "\n")).never.toContain("above pickaxe reach")
			end
		)

		it(
			"warns and clamps hardness and tierBias outside the range",
			function()
				local mine = makeMine()
				mine.chambers[2].hardness = 6
				mine.chambers[2].tierBias = 0.2
				local result, warnings = generateOrFail(mine)
				expect(result.chambers[2].hardness).toBe(4)
				expect(result.chambers[2].tierBias).toBe(1)
				local joined = table.concat(warnings, "\n")
				expect(joined).toContain("chamber 2: hardness")
				expect(joined).toContain("chamber 2: tierBias")
			end
		)

		it(
			"warns when hand-placed rock is outside its chamber or inside the corridor",
			function()
				local mine = makeMine()
				mine.chambers[1].handPlaced = {
					{ rock = RockName.GOLD_4, depth = 6, height = 1, widthOffset = 0 },
					{ rock = RockName.GOLD_4, depth = 99, height = 1, widthOffset = 0 },
				}
				local _, warnings = generateOrFail(mine)
				local joined = table.concat(warnings, "\n")
				expect(joined).toContain("handPlaced[1]: falls inside the corridor")
				expect(joined).toContain("handPlaced[2]: falls outside the chamber")
			end
		)

		it(
			"treats a full corridor as the chamber height",
			function()
				local mine = makeMine()
				mine.chambers[2].corridorHeight = MineGenerator.CORRIDOR_HEIGHT_FULL
				local result = generateOrFail(mine)
				expect(result.chambers[2].corridorHeight).toBe(8)
				-- the gate reaches the ceiling
				local divider = result.chambers[2].depthStart + result.chambers[2].depth
				expect(MineGenerator.getCell(result.grid, divider, 8, 12)).toBe(RockName.GATE)
				expect(MineGenerator.getCell(result.grid, divider, 9, 12)).toBe(RockName.BEDROCK)
			end
		)

		it(
			"applies bedrock overrides per face",
			function()
				local mine = makeMine()
				mine.bedrockOverrides = { far = 3, side = 2 }
				local result = generateOrFail(mine)
				expect(result.grid.depth).toBe(1 + 96 + 3 + 3)
				expect(result.grid.width).toBe(24 + 4)
				expect(result.chambers[1].widthStart).toBe(2)
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
						expect(preview.requestedOre[resource]).toBeCloseTo(result.report.chambers[index].requestedOre[resource], 6)
					end
					expect(preview.expectedHp).toBeGreaterThan(0)
				end
				-- chamber 4 is bigger and harder than chamber 1, so it costs more hp
				expect(previews[4].expectedHp).toBeGreaterThan(previews[1].expectedHp)
			end
		)

		it(
			"reports the same fatal errors as generate",
			function()
				local mine = makeMine()
				mine.chambers[4].uranium = 0
				mine.chambers[3].uranium = 0
				local previews, errors = MineGenerator.preview(mine, makeConfig())
				expect(previews).toBeNil()
				expect(table.concat(errors, "\n")).toContain("uranium")
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
