--!strict

-- Pure rules for Towers and Traps on the Defensive Zone grid (GDD
-- "Defenses", "Traps", "Defensive Zones"), M26: how an zone part becomes a
-- grid, which cells a footprint covers, whether they are free, what a
-- Tower's stats are at a level, what the next upgrade costs, what a sale
-- returns, how the loadout names resolve, and the codecs for the catalogue
-- and the per-player state the server publishes. The server owns every
-- decision; the client runs the same maths to snap the preview and colour
-- it before asking. Tuning is passed in from GameData (as the catalogue) so
-- this stays unit testable.
local HttpService = game:GetService("HttpService")

local Constants = require(script.Parent.Constants)
local Enums = require(script.Parent.Enums)

local PlacementRules = {}

-- every kind has damage, range, and HP; the rest depend on the attack
-- shape (GameData/Defenses/Towers explains each)
export type TowerLevelStats = {
	DAMAGE: number,
	RANGE_STUDS: number,
	MAX_HP: number,
	FIRE_INTERVAL_SEC: number?,
	FLAME_SEC: number?,
	SLOW_SHARE: number?,
	SLOW_SEC: number?,
	CHAIN_COUNT: number?,
}

-- how a kind fights, fixed across levels (M27)
export type TowerBehavior = {
	ATTACK: number,
	TARGETS_GROUND: boolean,
	TARGETS_AIR: boolean,
	HAS_TURRET: boolean,
	CONE_ANGLE_DEGREES: number?,
	TICK_INTERVAL_SEC: number?,
	FLAME_SEC: number?,
	REST_SEC: number?,
	CHAIN_JUMP_STUDS: number?,
	STUN_SEC: number?,
}

export type TowerData = {
	BUILD_PRICE_IRON: number,
	-- entry N is the price of reaching level N + 1; the length is the upgrade cap
	UPGRADE_PRICE_IRON_BY_LEVEL: { number },
	-- columns by rows
	FOOTPRINT_CELLS: { number },
	-- the four Enums.TowerStat the Tower Menu lists, in order
	STAT_ROWS: { number }?,
	BEHAVIOR: TowerBehavior?,
	STATS_BY_LEVEL: { TowerLevelStats },
}

export type TrapData = {
	PRICE_IRON: number,
	MAX_HP: number,
	FOOTPRINT_CELLS: { number },
	-- whether the Hammer can repair it, as it can any Tower
	IS_REPAIRABLE: boolean?,
	-- Enums.TrapBehavior and its numbers (GameData/Defenses/Traps), M27
	BEHAVIOR: number?,
	DRAWS_ATTACKS: boolean?,
	DAMAGE: number?,
	UP_SEC: number?,
	RECHARGE_SEC: number?,
	SLOW_SHARE: number?,
	SLOW_SEC: number?,
	RANGE_STUDS: number?,
}

-- what the server publishes as GameMetadata
export type Catalog = {
	cellSizeStuds: number,
	maxActiveTowersCamp: number,
	towerSellShare: number,
	trapSellShare: number,
	towers: { [number]: TowerData },
	traps: { [number]: TrapData },
}

-- an zone part cut into cells: the frame sits on the top face at its
-- centre with the part's rotation, +X along the columns and +Z along the rows
export type Grid = {
	cframe: CFrame,
	columns: number,
	rows: number,
	cellSizeStuds: number,
}

export type Cell = {
	column: number,
	row: number,
}

-- "column,row" -> the placement id standing there
export type Occupancy = { [string]: string }

export type UpgradeOffer = {
	-- the level the buy would reach
	level: number,
	price: number,
}

PlacementRules.STARTING_LEVEL = 1
PlacementRules.NOBODY = 0
PlacementRules.ID_FORMAT = "Placement%d"
-- a placement turns in quarter turns: 0 to 3, the count a footprint's
-- columns are turned toward its rows (2026-10-02)
PlacementRules.ROTATION_COUNT = 4
-- every footprint and every grid is a whole number of these, so a grid
-- can always be tiled by the smallest placement (decided 2026-10-02)
PlacementRules.FOOTPRINT_UNIT_CELLS = 2

-- a count of cells brought down to a whole number of footprint units
local function wholeUnits(count: number): number
	return count - count % PlacementRules.FOOTPRINT_UNIT_CELLS
end

-- the zone is cut from its centre out, and the counts are brought down
-- to even numbers so the smallest footprint can fill the whole grid
function PlacementRules.measureZone(zoneCFrame: CFrame, zoneSize: Vector3, cellSizeStuds: number): Grid
	return {
		cframe = zoneCFrame * CFrame.new(0, zoneSize.Y / 2, 0),
		columns = wholeUnits(math.max(0, math.floor(zoneSize.X / cellSizeStuds + 1e-6))),
		rows = wholeUnits(math.max(0, math.floor(zoneSize.Z / cellSizeStuds + 1e-6))),
		cellSizeStuds = cellSizeStuds,
	}
end

-- whether both sides of a footprint are whole units, so it tiles the grid
function PlacementRules.isFootprintWhole(footprint: { number }): boolean
	return footprint[1] % PlacementRules.FOOTPRINT_UNIT_CELLS == 0 and footprint[2] % PlacementRules.FOOTPRINT_UNIT_CELLS == 0
end

-- any number of quarter turns brought into 0 to 3
function PlacementRules.normalizeRotation(rotation: number): number
	return math.floor(rotation) % PlacementRules.ROTATION_COUNT
end

function PlacementRules.isValidRotation(rotation: any): boolean
	return typeof(rotation) == "number" and rotation == math.floor(rotation) and rotation >= 0 and rotation < PlacementRules.ROTATION_COUNT
end

-- the footprint as it lies on the grid once turned: an odd number of
-- quarter turns swaps columns and rows
function PlacementRules.rotatedFootprint(footprint: { number }, rotation: number): { number }
	if PlacementRules.normalizeRotation(rotation) % 2 == 1 then
		return { footprint[2], footprint[1] }
	end
	return { footprint[1], footprint[2] }
end

-- the yaw a model turned `rotation` quarter turns is drawn at, about the
-- grid-aligned pose of its turned footprint
function PlacementRules.rotationCFrame(rotation: number): CFrame
	return CFrame.Angles(0, math.rad(90 * PlacementRules.normalizeRotation(rotation)), 0)
end

function PlacementRules.isCellInside(grid: Grid, cell: Cell): boolean
	return cell.column >= 1 and cell.column <= grid.columns and cell.row >= 1 and cell.row <= grid.rows
end

-- the world centre of one cell, on the top face
function PlacementRules.cellCenter(grid: Grid, cell: Cell): Vector3
	local x = (cell.column - 0.5 - grid.columns / 2) * grid.cellSizeStuds
	local z = (cell.row - 0.5 - grid.rows / 2) * grid.cellSizeStuds
	return (grid.cframe:PointToWorldSpace(Vector3.new(x, 0, z)))
end

-- the cell under a world position; outside the grid the numbers run past
-- its edges, so callers check isCellInside or clamp
function PlacementRules.cellFromPosition(grid: Grid, position: Vector3): Cell
	local localPosition = grid.cframe:PointToObjectSpace(position)
	return {
		column = math.floor(localPosition.X / grid.cellSizeStuds + grid.columns / 2) + 1,
		row = math.floor(localPosition.Z / grid.cellSizeStuds + grid.rows / 2) + 1,
	}
end

-- every cell a footprint anchored at `cell` (its lowest column and row) covers
function PlacementRules.footprintCells(cell: Cell, footprint: { number }): { Cell }
	local cells = {}
	for columnOffset = 0, footprint[1] - 1 do
		for rowOffset = 0, footprint[2] - 1 do
			table.insert(cells, {
				column = cell.column + columnOffset,
				row = cell.row + rowOffset,
			})
		end
	end
	return cells
end

-- the pose of a footprint anchored at `cell`: the centre of the cells it
-- covers, on the top face, turned with the grid
function PlacementRules.footprintCFrame(grid: Grid, cell: Cell, footprint: { number }): CFrame
	local x = (cell.column - 1 + footprint[1] / 2 - grid.columns / 2) * grid.cellSizeStuds
	local z = (cell.row - 1 + footprint[2] / 2 - grid.rows / 2) * grid.cellSizeStuds
	return grid.cframe * CFrame.new(x, 0, z)
end

-- the anchor cell whose footprint is centred nearest the position: the
-- preview snaps here as the player walks
function PlacementRules.anchorFromPosition(grid: Grid, position: Vector3, footprint: { number }): Cell
	local localPosition = grid.cframe:PointToObjectSpace(position)
	return {
		column = math.floor(localPosition.X / grid.cellSizeStuds + grid.columns / 2 - footprint[1] / 2 + 0.5) + 1,
		row = math.floor(localPosition.Z / grid.cellSizeStuds + grid.rows / 2 - footprint[2] / 2 + 0.5) + 1,
	}
end

-- the nearest anchor that keeps the whole footprint inside the grid; nil
-- when the footprint does not fit at all
function PlacementRules.clampAnchor(grid: Grid, cell: Cell, footprint: { number }): Cell?
	local maxColumn = grid.columns - footprint[1] + 1
	local maxRow = grid.rows - footprint[2] + 1
	if maxColumn < 1 or maxRow < 1 then
		return nil
	end
	return {
		column = math.clamp(cell.column, 1, maxColumn),
		row = math.clamp(cell.row, 1, maxRow),
	}
end

function PlacementRules.occupancyKey(cell: Cell): string
	return `{cell.column},{cell.row}`
end

-- whether every cell of the footprint is inside the grid and free. A
-- placement being moved passes its own id as ignoredId, so the cells it
-- stands on now do not block it from shifting over by one
function PlacementRules.canPlace(grid: Grid, occupancy: Occupancy, cell: Cell, footprint: { number }, ignoredId: string?): boolean
	for _, covered in PlacementRules.footprintCells(cell, footprint) do
		if not PlacementRules.isCellInside(grid, covered) then
			return false
		end
		local occupant = occupancy[PlacementRules.occupancyKey(covered)]
		if occupant ~= nil and occupant ~= ignoredId then
			return false
		end
	end
	return true
end

-- an upright box a fortification stands in (a wall, a post, the gate)
export type Box = {
	cframe: CFrame,
	size: Vector3,
}

-- the occupant of a cell nothing may ever be built on
PlacementRules.RESERVED_OCCUPANT = "Reserved"
local CELL_SEPARATOR = ";"

-- the same box stood upright: a model's bounding box follows its pivot,
-- and a post's pivot lies on its side, so "height" there runs along the
-- ground. Whichever axis points most nearly up becomes the height, the
-- other two the footprint (found 2026-10-01)
local function flattenBox(box: Box): Box
	local cframe = box.cframe
	local axes = {
		{ direction = cframe.RightVector, extent = box.size.X },
		{ direction = cframe.UpVector, extent = box.size.Y },
		{ direction = -cframe.LookVector, extent = box.size.Z },
	}
	table.sort(
		axes,
		function(a, b): boolean
			return math.abs(a.direction.Y) > math.abs(b.direction.Y)
		end
	)
	local flatRight = Vector3.new(axes[2].direction.X, 0, axes[2].direction.Z)
	if flatRight.Magnitude < 1e-6 then
		return box
	end
	flatRight = flatRight.Unit
	return {
		cframe = CFrame.fromMatrix(cframe.Position, flatRight, Vector3.yAxis),
		size = Vector3.new(axes[2].extent, axes[1].extent, axes[3].extent),
	}
end

local function flattenBoxes(boxes: { Box }): { Box }
	local flattened = {}
	for _, box in boxes do
		table.insert(flattened, flattenBox(box))
	end
	return flattened
end

-- how far a point is, across the ground, from the nearest side of an
-- upright box; 0 under it. Height is left out so a low cell beside a tall
-- wall still counts as beside it
local function groundDistanceToBox(position: Vector3, box: Box): number
	local localPosition = box.cframe:PointToObjectSpace(position)
	local half = box.size / 2
	local acrossX = localPosition.X - math.clamp(localPosition.X, -half.X, half.X)
	local acrossZ = localPosition.Z - math.clamp(localPosition.Z, -half.Z, half.Z)
	return math.sqrt(acrossX * acrossX + acrossZ * acrossZ)
end

-- the cells no defense may stand on: every cell whose centre is closer
-- than clearanceStuds to a fortification box, so the grid keeps a gap
-- along the wall whatever shape the wall line takes (decided 2026-09-30)
function PlacementRules.reservedCells(grid: Grid, boxes: { Box }, clearanceStuds: number): { Cell }
	local cells = {}
	local uprightBoxes = flattenBoxes(boxes)
	for column = 1, grid.columns do
		for row = 1, grid.rows do
			local cell = { column = column, row = row }
			local center = PlacementRules.cellCenter(grid, cell)
			for _, box in uprightBoxes do
				if groundDistanceToBox(center, box) < clearanceStuds then
					table.insert(cells, cell)
					break
				end
			end
		end
	end
	return cells
end

-- whether a point on the ground is under the box grown by `marginStuds`
-- on every side
local function isUnderBox(position: Vector3, box: Box, marginStuds: number): boolean
	local localPosition = box.cframe:PointToObjectSpace(position)
	local half = box.size / 2
	return math.abs(localPosition.X) <= half.X + marginStuds and math.abs(localPosition.Z) <= half.Z + marginStuds
end

-- the cells on the camp's side of the fortification line: everything the
-- ground reaches from `insidePoint` (the Refinery) without stepping under
-- a wall, a post, or the gate. A flood fill rather than a line of sight,
-- so a pocket behind a wall that a post hides from the Refinery still
-- counts as inside (decided 2026-10-01). The fill runs on the zone's own
-- cells extended as far as the inside point; each box is grown by half a
-- cell so the line it forms is sealed at cell size
function PlacementRules.cellsInsideCamp(grid: Grid, boxes: { Box }, insidePoint: Vector3): { Cell }
	local uprightBoxes = flattenBoxes(boxes)
	local startCell = PlacementRules.cellFromPosition(grid, insidePoint)
	local columnMin = math.min(1, startCell.column)
	local columnMax = math.max(grid.columns, startCell.column)
	local rowMin = math.min(1, startCell.row)
	local rowMax = math.max(grid.rows, startCell.row)
	local margin = grid.cellSizeStuds / 2
	local function isOpen(cell: Cell): boolean
		if cell.column < columnMin or cell.column > columnMax or cell.row < rowMin or cell.row > rowMax then
			return false
		end
		local center = PlacementRules.cellCenter(grid, cell)
		for _, box in uprightBoxes do
			if isUnderBox(center, box, margin) then
				return false
			end
		end
		return true
	end
	local visited: { [string]: boolean } = {}
	local queue: { Cell } = {}
	if isOpen(startCell) then
		visited[PlacementRules.occupancyKey(startCell)] = true
		table.insert(queue, startCell)
	end
	local cells = {}
	local head = 1
	while head <= #queue do
		local cell = queue[head]
		head += 1
		if PlacementRules.isCellInside(grid, cell) then
			table.insert(cells, cell)
		end
		for _, step in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local neighbour = { column = cell.column + step[1], row = cell.row + step[2] }
			local key = PlacementRules.occupancyKey(neighbour)
			if visited[key] or not isOpen(neighbour) then
				continue
			end
			visited[key] = true
			table.insert(queue, neighbour)
		end
	end
	return cells
end

-- the cells plus their mirror images across the grid's centre line along
-- the rows, so the two halves of a symmetric camp read the same even
-- where the authored walls sit a stud or two apart (decided 2026-10-01)
function PlacementRules.mirrorCells(grid: Grid, cells: { Cell }): { Cell }
	local mirrored = {}
	for _, cell in cells do
		table.insert(mirrored, { column = grid.columns + 1 - cell.column, row = cell.row })
	end
	return PlacementRules.mergeCells(cells, mirrored)
end

-- the reserved cells merged without duplicates, in grid order
function PlacementRules.mergeCells(...: { Cell }): { Cell }
	local seen: { [string]: Cell } = {}
	for _, list in { ... } do
		for _, cell in list do
			seen[PlacementRules.occupancyKey(cell)] = cell
		end
	end
	local merged = {}
	for _, cell in seen do
		table.insert(merged, cell)
	end
	table.sort(
		merged,
		function(a: Cell, b: Cell): boolean
			if a.column ~= b.column then
				return a.column < b.column
			end
			return a.row < b.row
		end
	)
	return merged
end

function PlacementRules.reserve(occupancy: Occupancy, cells: { Cell })
	for _, cell in cells do
		occupancy[PlacementRules.occupancyKey(cell)] = PlacementRules.RESERVED_OCCUPANT
	end
end

-- the reserved cells travel on the zone part as one attribute string
function PlacementRules.encodeCells(cells: { Cell }): string
	local keys = {}
	for _, cell in cells do
		table.insert(keys, PlacementRules.occupancyKey(cell))
	end
	return table.concat(keys, CELL_SEPARATOR)
end

function PlacementRules.decodeCells(encoded: any): { Cell }
	local cells = {}
	if typeof(encoded) ~= "string" then
		return cells
	end
	for key in string.gmatch(encoded, `[^{CELL_SEPARATOR}]+`) do
		local column, row = string.match(key, "^(%d+),(%d+)$")
		if column and row then
			table.insert(cells, { column = tonumber(column) :: number, row = tonumber(row) :: number })
		end
	end
	return cells
end

-- how many footprints out the search for a free spot looks
PlacementRules.NEXT_FREE_MAX_STEPS = 8

-- the nearest free spot beside `cell` for another of the same footprint:
-- one footprint along the columns first (so a row of Walls joins up), then
-- back the other way, then along the rows, stepping further out each
-- round; nil when nothing near is free
function PlacementRules.nextFreeAnchor(grid: Grid, occupancy: Occupancy, cell: Cell, footprint: { number }): Cell?
	for step = 1, PlacementRules.NEXT_FREE_MAX_STEPS do
		local candidates = {
			{ column = cell.column + step * footprint[1], row = cell.row },
			{ column = cell.column - step * footprint[1], row = cell.row },
			{ column = cell.column, row = cell.row + step * footprint[2] },
			{ column = cell.column, row = cell.row - step * footprint[2] },
		}
		for _, candidate in candidates do
			if PlacementRules.canPlace(grid, occupancy, candidate, footprint) then
				return candidate
			end
		end
	end
	return nil
end

function PlacementRules.footprintFor(catalog: Catalog, placementKind: number, typeKind: number): { number }?
	if placementKind == Enums.PlacementKind.TOWER then
		local tower = catalog.towers[typeKind]
		return if tower then tower.FOOTPRINT_CELLS else nil
	end
	local trap = catalog.traps[typeKind]
	return if trap then trap.FOOTPRINT_CELLS else nil
end

function PlacementRules.towerMaxLevel(tower: TowerData): number
	return #tower.STATS_BY_LEVEL
end

function PlacementRules.towerStats(tower: TowerData, level: number): TowerLevelStats
	local clamped = math.clamp(math.floor(level), 1, PlacementRules.towerMaxLevel(tower))
	return tower.STATS_BY_LEVEL[clamped]
end

-- a kind without rows of its own lists the classic four
PlacementRules.DEFAULT_STAT_ROWS = { Enums.TowerStat.FIRE_RATE, Enums.TowerStat.RANGE, Enums.TowerStat.DAMAGE, Enums.TowerStat.HP }

function PlacementRules.towerStatRows(tower: TowerData): { number }
	local rows = tower.STAT_ROWS
	return if rows and #rows > 0 then rows else PlacementRules.DEFAULT_STAT_ROWS
end

-- one stat as a number the menu can compare across levels: shots per
-- second, studs, damage, HP, seconds, a percentage, or a count
function PlacementRules.towerStatValue(stat: number, stats: TowerLevelStats): number
	if stat == Enums.TowerStat.FIRE_RATE then
		local interval = stats.FIRE_INTERVAL_SEC or 0
		return if interval > 0 then 1 / interval else 0
	elseif stat == Enums.TowerStat.RANGE then
		return stats.RANGE_STUDS
	elseif stat == Enums.TowerStat.DAMAGE then
		return stats.DAMAGE
	elseif stat == Enums.TowerStat.FLAME_LENGTH then
		return stats.FLAME_SEC or 0
	elseif stat == Enums.TowerStat.SLOW_RATE then
		return (stats.SLOW_SHARE or 0) * 100
	elseif stat == Enums.TowerStat.FREEZE_LENGTH then
		return stats.SLOW_SEC or 0
	elseif stat == Enums.TowerStat.CHAIN_COUNT then
		return stats.CHAIN_COUNT or 0
	end
	return stats.MAX_HP
end

-- the same number as the menu shows it
function PlacementRules.towerStatText(stat: number, stats: TowerLevelStats): string
	local value = PlacementRules.towerStatValue(stat, stats)
	if stat == Enums.TowerStat.FIRE_RATE then
		return string.format("%.1f/s", value)
	elseif stat == Enums.TowerStat.FLAME_LENGTH or stat == Enums.TowerStat.FREEZE_LENGTH then
		return string.format("%.1fs", value)
	elseif stat == Enums.TowerStat.SLOW_RATE then
		return string.format("%d%%", math.floor(value + 0.5))
	end
	return tostring(math.floor(value + 0.5))
end

-- the next upgrade of a Tower at `level`; nil at the top
function PlacementRules.towerUpgradeOffer(tower: TowerData, level: number): UpgradeOffer?
	local nextLevel = math.floor(level) + 1
	local price = tower.UPGRADE_PRICE_IRON_BY_LEVEL[nextLevel - 1]
	if nextLevel > PlacementRules.towerMaxLevel(tower) or price == nil then
		return nil
	end
	return {
		level = nextLevel,
		price = price,
	}
end

-- everything paid for a Tower standing at `level`: the build and each upgrade so far
function PlacementRules.towerTotalSpent(tower: TowerData, level: number): number
	local spent = tower.BUILD_PRICE_IRON
	for upgrade = 1, math.floor(level) - 1 do
		spent += tower.UPGRADE_PRICE_IRON_BY_LEVEL[upgrade] or 0
	end
	return spent
end

function PlacementRules.sellValue(spent: number, share: number): number
	return math.floor(spent * math.clamp(share, 0, 1))
end

function PlacementRules.maxHpFor(catalog: Catalog, placementKind: number, typeKind: number, level: number): number
	if placementKind == Enums.PlacementKind.TOWER then
		local tower = catalog.towers[typeKind]
		return if tower then PlacementRules.towerStats(tower, level).MAX_HP else 0
	end
	local trap = catalog.traps[typeKind]
	return if trap then trap.MAX_HP else 0
end

-- what a build costs in Iron: a Tower's build price or a Trap's price,
-- both paid when it is placed (2026-09-30)
function PlacementRules.buildPrice(catalog: Catalog, placementKind: number, typeKind: number): number
	if placementKind == Enums.PlacementKind.TOWER then
		local tower = catalog.towers[typeKind]
		return if tower then tower.BUILD_PRICE_IRON else 0
	end
	local trap = catalog.traps[typeKind]
	return if trap then trap.PRICE_IRON else 0
end

-- whether the Hammer can repair a placement: every Tower, and the Traps
-- marked IS_REPAIRABLE (a Trap is otherwise a consumable)
function PlacementRules.isRepairable(catalog: Catalog, placementKind: number, typeKind: number): boolean
	if placementKind == Enums.PlacementKind.TOWER then
		return catalog.towers[typeKind] ~= nil
	end
	local trap = catalog.traps[typeKind]
	return trap ~= nil and trap.IS_REPAIRABLE == true
end

function PlacementRules.sellValueFor(catalog: Catalog, placementKind: number, typeKind: number, level: number): number
	if placementKind == Enums.PlacementKind.TOWER then
		local tower = catalog.towers[typeKind]
		return if tower then PlacementRules.sellValue(PlacementRules.towerTotalSpent(tower, level), catalog.towerSellShare) else 0
	end
	local trap = catalog.traps[typeKind]
	return if trap then PlacementRules.sellValue(trap.PRICE_IRON, catalog.trapSellShare) else 0
end

-- an upgrade keeps the Tower's share of HP at its new size, never a free heal
function PlacementRules.hpAfterUpgrade(hp: number, oldMaxHp: number, newMaxHp: number): number
	if hp <= 0 or oldMaxHp <= 0 then
		return 0
	end
	return math.min(newMaxHp, math.ceil(newMaxHp * math.min(hp, oldMaxHp) / oldMaxHp))
end

function PlacementRules.canAfford(iron: number, price: number): boolean
	return iron >= price
end

function PlacementRules.typeEnumFor(placementKind: number): Enums.EnumTable
	return if placementKind == Enums.PlacementKind.TOWER then Enums.TowerKind else Enums.TrapKind
end

function PlacementRules.publicName(placementKind: number, typeKind: number): string
	return Enums.getPublicName(PlacementRules.typeEnumFor(placementKind), typeKind) or "?"
end

-- "SENTRY_GUN" under GameAssets/Towers, "SPIKE_TRAP" under GameAssets/Traps
function PlacementRules.templateFolderFor(placementKind: number): string
	return if placementKind == Enums.PlacementKind.TOWER then Constants.TOWER_TEMPLATES_FOLDER else Constants.TRAP_TEMPLATES_FOLDER
end

function PlacementRules.templateNameFor(placementKind: number, typeKind: number): string
	return Enums.getName(PlacementRules.typeEnumFor(placementKind), typeKind) or "?"
end

-- the arrows in the Tower Menu step through the priorities and wrap
function PlacementRules.cycleTargetPriority(current: number, direction: number): number
	local values = Enums.getAllValues(Enums.TargetPriority)
	local index = table.find(values, current) or 1
	local count = #values
	return values[(index - 1 + direction) % count + 1]
end

-- the loadout saves unlock names; either the enum key or the public name
-- finds a Tower, anything else is skipped, and an empty result is the
-- default Tower alone. Duplicates collapse to one entry
function PlacementRules.resolveLoadoutTowers(unlockNames: { string? }, defaultKind: number): { number }
	local kinds: { number } = {}
	for _, unlockName in unlockNames do
		if unlockName == nil or unlockName == "" then
			continue
		end
		for _, kind in Enums.getAllValues(Enums.TowerKind) do
			local isMatch = Enums.getName(Enums.TowerKind, kind) == string.upper(unlockName) or Enums.getPublicName(Enums.TowerKind, kind) == unlockName
			if isMatch and not table.find(kinds, kind) then
				table.insert(kinds, kind)
			end
		end
	end
	if #kinds == 0 then
		table.insert(kinds, defaultKind)
	end
	return kinds
end

function PlacementRules.encodeTowerLoadout(kinds: { number }): string
	return HttpService:JSONEncode(kinds)
end

function PlacementRules.decodeTowerLoadout(encoded: any): { number }
	if typeof(encoded) ~= "string" or encoded == "" then
		return {}
	end
	local isSuccess, decoded = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not isSuccess or typeof(decoded) ~= "table" then
		return {}
	end
	local kinds = {}
	for _, kind in decoded do
		if typeof(kind) == "number" and Enums.isValidValue(Enums.TowerKind, kind) then
			table.insert(kinds, kind)
		end
	end
	return kinds
end

-- JSON turns numeric keys into strings; the codecs turn them back
local function encodeNumberKeys(map: { [number]: any }): { [string]: any }
	local encoded = {}
	for key, value in map do
		encoded[tostring(key)] = value
	end
	return encoded
end

local function decodeNumberKeys(map: any): { [number]: any }
	local decoded = {}
	if typeof(map) == "table" then
		for key, value in map do
			local numberKey = tonumber(key)
			if numberKey then
				decoded[numberKey] = value
			end
		end
	end
	return decoded
end

-- the camp's Towers shared out evenly: each player may hold this many
function PlacementRules.towerAllowance(maxActiveTowersCamp: number, crewCount: number): number
	return math.ceil(maxActiveTowersCamp / math.max(crewCount, 1))
end

function PlacementRules.encodeCatalog(catalog: Catalog): string
	return HttpService:JSONEncode({
		cellSizeStuds = catalog.cellSizeStuds,
		maxActiveTowersCamp = catalog.maxActiveTowersCamp,
		towerSellShare = catalog.towerSellShare,
		trapSellShare = catalog.trapSellShare,
		towers = encodeNumberKeys(catalog.towers),
		traps = encodeNumberKeys(catalog.traps),
	})
end

-- nil for anything but a catalogue this module encoded
function PlacementRules.decodeCatalog(json: any): Catalog?
	if typeof(json) ~= "string" or json == "" then
		return nil
	end
	local isSuccess, decoded = pcall(HttpService.JSONDecode, HttpService, json)
	if not isSuccess or typeof(decoded) ~= "table" or typeof(decoded.cellSizeStuds) ~= "number" then
		return nil
	end
	return {
		cellSizeStuds = decoded.cellSizeStuds,
		maxActiveTowersCamp = decoded.maxActiveTowersCamp or 0,
		towerSellShare = decoded.towerSellShare or 0,
		trapSellShare = decoded.trapSellShare or 0,
		towers = decodeNumberKeys(decoded.towers),
		traps = decodeNumberKeys(decoded.traps),
	}
end

return PlacementRules
