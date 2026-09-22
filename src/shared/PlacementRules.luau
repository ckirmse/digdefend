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
	REQUIRED_CAMP_LEVEL: number,
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
	previewDistanceStuds: number,
	maxActiveTowersPerPlayer: number,
	maxTrapKindsCarried: number,
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

function PlacementRules.measureZone(zoneCFrame: CFrame, zoneSize: Vector3, cellSizeStuds: number): Grid
	return {
		cframe = zoneCFrame * CFrame.new(0, zoneSize.Y / 2, 0),
		columns = math.max(0, math.floor(zoneSize.X / cellSizeStuds + 1e-6)),
		rows = math.max(0, math.floor(zoneSize.Z / cellSizeStuds + 1e-6)),
		cellSizeStuds = cellSizeStuds,
	}
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

-- whether every cell of the footprint is inside the grid and free
function PlacementRules.canPlace(grid: Grid, occupancy: Occupancy, cell: Cell, footprint: { number }): boolean
	for _, covered in PlacementRules.footprintCells(cell, footprint) do
		if not PlacementRules.isCellInside(grid, covered) or occupancy[PlacementRules.occupancyKey(covered)] ~= nil then
			return false
		end
	end
	return true
end

-- the server's distance check: the placement's centre against the
-- player's root, so a preview 10 studs out with a big footprint passes
function PlacementRules.isWithinBuildReach(playerPosition: Vector3, placementPosition: Vector3, maxDistanceStuds: number): boolean
	return (placementPosition - playerPosition).Magnitude <= maxDistanceStuds
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

-- what a build costs: a Tower's price, 0 for a Trap (it is consumed instead)
function PlacementRules.buildPrice(catalog: Catalog, placementKind: number, typeKind: number): number
	if placementKind == Enums.PlacementKind.TOWER then
		local tower = catalog.towers[typeKind]
		return if tower then tower.BUILD_PRICE_IRON else 0
	end
	return 0
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

-- how many different kinds a trap inventory holds
function PlacementRules.countTrapKinds(counts: { [number]: number }): number
	local kinds = 0
	for _, count in counts do
		if count > 0 then
			kinds += 1
		end
	end
	return kinds
end

-- whether a buy of `kind` fits the carried-kinds limit
function PlacementRules.canCarryTrap(counts: { [number]: number }, kind: number, maxKinds: number): boolean
	if (counts[kind] or 0) > 0 then
		return true
	end
	return PlacementRules.countTrapKinds(counts) < maxKinds
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

function PlacementRules.encodeTrapCounts(counts: { [number]: number }): string
	return HttpService:JSONEncode(encodeNumberKeys(counts))
end

function PlacementRules.decodeTrapCounts(encoded: any): { [number]: number }
	if typeof(encoded) ~= "string" or encoded == "" then
		return {}
	end
	local isSuccess, decoded = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not isSuccess then
		return {}
	end
	local counts = {}
	for kind, count in decodeNumberKeys(decoded) do
		if typeof(count) == "number" and count > 0 and Enums.isValidValue(Enums.TrapKind, kind) then
			counts[kind] = count
		end
	end
	return counts
end

function PlacementRules.encodeCatalog(catalog: Catalog): string
	return HttpService:JSONEncode({
		cellSizeStuds = catalog.cellSizeStuds,
		previewDistanceStuds = catalog.previewDistanceStuds,
		maxActiveTowersPerPlayer = catalog.maxActiveTowersPerPlayer,
		maxTrapKindsCarried = catalog.maxTrapKindsCarried,
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
		previewDistanceStuds = decoded.previewDistanceStuds or 10,
		maxActiveTowersPerPlayer = decoded.maxActiveTowersPerPlayer or 0,
		maxTrapKindsCarried = decoded.maxTrapKindsCarried or 0,
		towerSellShare = decoded.towerSellShare or 0,
		trapSellShare = decoded.trapSellShare or 0,
		towers = decodeNumberKeys(decoded.towers),
		traps = decodeNumberKeys(decoded.traps),
	}
end

return PlacementRules
