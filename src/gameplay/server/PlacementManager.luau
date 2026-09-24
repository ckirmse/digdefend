--!strict

-- Towers and Traps on the Defensive Zone grid (GDD "Defenses", "Traps",
-- "Defensive Zones", "Building Towers", "Upgrading and Selling Towers",
-- "Selling Traps"), M26. Every placement is Lua state here: what it is,
-- who built it, its level, HP, target priority, and the cells it covers.
-- Each has one shadow part (the shadow system: a small invisible anchored
-- server part at the placement's pose carrying the Placement* attributes
-- and its prompt); clients clone the GameAssets model onto it and hang the
-- info billboard. The Defensive Zones are the map's own parts, numbered
-- and tagged at run start; the grid over each is pure maths
-- (PlacementRules.measureZone) both sides run from the part.
--
-- A build is a TryBuildPlacement request naming the kind, the zone, and
-- the anchor cell; the server checks Build Mode (the Defenses tool
-- is equipped), that the
-- loadout brought the Tower or the inventory holds the Trap, the Tower
-- limit, that every cell is inside and free, the distance from the player,
-- and the Iron, then spawns the shadow. Selling a Tower and upgrading it
-- are requests from the Tower Menu; selling a Trap is its ProximityPrompt,
-- heard here directly. The Tower's own prompt only opens the menu on the
-- owner's client. HP goes down through damagePlacement (walkers held up
-- by a barrier, TrapBehaviorManager; enemies at M29; a dev tool) and a
-- placement at zero is gone. A Tower is repaired with the Hammer exactly
-- like a wall (TryRepairTower, decided 2026-09-22): anyone, one chunk of
-- HP for a few Iron per swing, the wall's reach and cooldown; a Trap is a
-- consumable and never repaired. What a Tower or Trap does once it
-- stands is TowerBehaviorManager and TrapBehaviorManager (M27), which
-- read the placements here and never touch the grid.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PlacementRules = require("@game/ReplicatedStorage/Shared/PlacementRules")
local StructureRules = require("@game/ReplicatedStorage/Shared/StructureRules")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local StructuresData = require("@game/ServerScriptService/GameData/Camp/Structures")
local PlacementData = require("@game/ServerScriptService/GameData/Defenses/Placement")
local TowersData = require("@game/ServerScriptService/GameData/Defenses/Towers")
local TrapsData = require("@game/ServerScriptService/GameData/Defenses/Traps")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local MapManager = require(script.Parent.MapManager)
local RefineryManager = require(script.Parent.RefineryManager)
local ToolManager = require(script.Parent.ToolManager)

local PlacementManager = {}
PlacementManager.__index = PlacementManager

export type Placement = {
	id: string,
	placementKind: number,
	typeKind: number,
	-- the builder; kept as a UserId too so a leaver's Tower keeps standing
	-- with its name on it
	owner: Player?,
	ownerUserId: number,
	level: number,
	hp: number,
	maxHp: number,
	zoneIndex: number,
	cell: PlacementRules.Cell,
	footprint: { number },
	cframe: CFrame,
	targetPriority: number,
	shadow: BasePart,
	promptConnection: RBXScriptConnection?,
}

type Zone = {
	index: number,
	part: BasePart,
	grid: PlacementRules.Grid,
	occupancy: PlacementRules.Occupancy,
}

type PlayerState = {
	trapCounts: { [number]: number },
	-- a dev tool's stand-in for the lobby loadout until the store exists
	loadoutOverride: { number }?,
}

export type PlacementManager = typeof(setmetatable(
	{} :: {
		catalog: PlacementRules.Catalog,
		placementsById: { [string]: Placement },
		zonesByIndex: { [number]: Zone },
		stateByPlayer: { [Player]: PlayerState },
		-- the Hammer's cooldown on Towers, per player
		lastSwingTimeByPlayer: { [Player]: number },
		nextId: number,
		shadowFolder: Folder?,
		placementsChangedHandlers: { () -> () },
	},
	PlacementManager
))

local TRY_BUILD_PLACEMENT_SHAPE = {
	placementKind = { type = "enum", name = "PlacementKind" },
	-- an Enums.TowerKind or Enums.TrapKind, checked against the placement kind
	typeKind = "positiveInteger",
	zoneIndex = "positiveInteger",
	column = "integer",
	row = "integer",
}
local TRY_SELL_PLACEMENT_SHAPE = {
	id = "string",
}
local TRY_UPGRADE_TOWER_SHAPE = {
	id = "string",
}
local TRY_SET_TOWER_TARGET_PRIORITY_SHAPE = {
	id = "string",
	priority = { type = "enum", name = "TargetPriority" },
}
local TRY_REPAIR_TOWER_SHAPE = {
	id = "string",
}

local SHADOW_FOLDER = "PlacementShadows"
local SHADOW_HEIGHT_STUDS = 1
local DEFAULT_TARGET_PRIORITY = Enums.TargetPriority.CLOSEST

local FEEDBACK_NOT_ENOUGH_IRON = "You don't have enough Iron Bars"
local FEEDBACK_TOWER_LIMIT_FORMAT = "You can only have %d Towers at once"
local FEEDBACK_NO_TRAP_FORMAT = "You have no %s left"
local FEEDBACK_SPOT_TAKEN = "That spot is taken"
local FEEDBACK_NOT_IN_LOADOUT = "That Tower is not in your loadout"

function PlacementManager:getCatalog(): PlacementRules.Catalog
	return self.catalog
end

function PlacementManager:getPlacement(id: string): Placement?
	return self.placementsById[id]
end

function PlacementManager:getPlacementIds(): { string }
	local ids = {}
	for id in self.placementsById do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

function PlacementManager:getPlayerState(player: Player): PlayerState
	local state = self.stateByPlayer[player]
	if not state then
		state = {
			trapCounts = {},
			loadoutOverride = nil,
		}
		self.stateByPlayer[player] = state
	end
	return state
end

function PlacementManager:getTrapCount(player: Player, kind: number): number
	return self:getPlayerState(player).trapCounts[kind] or 0
end

function PlacementManager:getTrapCounts(player: Player): { [number]: number }
	return self:getPlayerState(player).trapCounts
end

-- the Defense Store hands Traps over through here
function PlacementManager:addTrap(player: Player, kind: number, amount: number)
	local state = self:getPlayerState(player)
	if amount <= 0 or not Enums.isValidValue(Enums.TrapKind, kind) then
		return
	end
	state.trapCounts[kind] = (state.trapCounts[kind] or 0) + amount
	self:replicatePlayer(player)
end

-- false when none are held, so a build never goes through unpaid
function PlacementManager:consumeTrap(player: Player, kind: number): boolean
	local state = self:getPlayerState(player)
	local count = state.trapCounts[kind] or 0
	if count <= 0 then
		return false
	end
	count -= 1
	state.trapCounts[kind] = if count > 0 then count else nil
	self:replicatePlayer(player)
	return true
end

-- dev tools: stands in for the three Defense loadout slots
function PlacementManager:setLoadoutOverride(player: Player, kinds: { number }?)
	self:getPlayerState(player).loadoutOverride = kinds
	self:replicatePlayer(player)
end

function PlacementManager:resolveTowerLoadout(player: Player): { number }
	local state = self:getPlayerState(player)
	local override = state.loadoutOverride
	if override and #override > 0 then
		return override
	end
	local playerData = GameController:getPlayerData(player)
	local names: { string? } = {}
	for _, slot in { Enums.LoadoutSlot.DEFENSE_1, Enums.LoadoutSlot.DEFENSE_2, Enums.LoadoutSlot.DEFENSE_3 } do
		table.insert(names, if playerData then playerData:getLoadoutSlot(slot) else nil)
	end
	return PlacementRules.resolveLoadoutTowers(names, TowersData.DEFAULT_TOWER)
end

function PlacementManager:countActiveTowers(player: Player): number
	local count = 0
	for _, placement in self.placementsById do
		if placement.placementKind == Enums.PlacementKind.TOWER and placement.owner == player then
			count += 1
		end
	end
	return count
end

function PlacementManager:replicatePlayer(player: Player)
	local state = self:getPlayerState(player)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.TOWER_LOADOUT, PlacementRules.encodeTowerLoadout(self:resolveTowerLoadout(player)))
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.TRAP_COUNTS, PlacementRules.encodeTrapCounts(state.trapCounts))
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.ACTIVE_TOWER_COUNT, self:countActiveTowers(player))
end

function PlacementManager:replicatePlacement(placement: Placement)
	local shadow = placement.shadow
	shadow:SetAttribute(Attributes.PLACEMENT_ID, placement.id)
	shadow:SetAttribute(Attributes.PLACEMENT_KIND, placement.placementKind)
	shadow:SetAttribute(Attributes.PLACEMENT_TYPE_KIND, placement.typeKind)
	shadow:SetAttribute(Attributes.PLACEMENT_OWNER_USER_ID, placement.ownerUserId)
	shadow:SetAttribute(Attributes.PLACEMENT_LEVEL, placement.level)
	shadow:SetAttribute(Attributes.PLACEMENT_HP, placement.hp)
	shadow:SetAttribute(Attributes.PLACEMENT_MAX_HP, placement.maxHp)
	shadow:SetAttribute(Attributes.PLACEMENT_TARGET_PRIORITY, placement.targetPriority)
	shadow:SetAttribute(Attributes.DEFENSIVE_ZONE_INDEX, placement.zoneIndex)
	shadow:SetAttribute(Attributes.PLACEMENT_COLUMN, placement.cell.column)
	shadow:SetAttribute(Attributes.PLACEMENT_ROW, placement.cell.row)
	if placement.placementKind == Enums.PlacementKind.TRAP then
		local trap = self.catalog.traps[placement.typeKind]
		shadow:SetAttribute(Attributes.PLACEMENT_DRAWS_ATTACKS, trap ~= nil and trap.DRAWS_ATTACKS == true)
	end
end

-- the monsters' way round the defenses is recomputed from here (M29)
function PlacementManager:subscribePlacementsChanged(handler: () -> ())
	table.insert(self.placementsChangedHandlers, handler)
end

function PlacementManager:firePlacementsChanged()
	for _, handler in self.placementsChangedHandlers do
		handler()
	end
end

function PlacementManager:getPlacements(): { Placement }
	local placements = {}
	for _, id in self:getPlacementIds() do
		table.insert(placements, self.placementsById[id])
	end
	return placements
end

function PlacementManager:getShadowFolder(): Folder?
	local folder = self.shadowFolder
	if folder and folder.Parent then
		return folder
	end
	local camp = MapManager:getCamp()
	if not camp then
		return nil
	end
	local created = Instance.new("Folder")
	created.Name = SHADOW_FOLDER
	created.Parent = camp
	self.shadowFolder = created
	return created
end

-- the Trap's Sell prompt is heard here; the Tower's Upgrade/Sell prompt is
-- only a signal the owner's client turns into the menu. Both are created
-- here and enabled per viewer by the clients, since a prompt cannot be
-- shown to one player from the server
function PlacementManager:configurePrompt(placement: Placement)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = PlacementRules.publicName(placement.placementKind, placement.typeKind)
	prompt.RequiresLineOfSight = false
	prompt.Enabled = true
	if placement.placementKind == Enums.PlacementKind.TOWER then
		prompt.ActionText = TowersData.MENU_PROMPT_ACTION_TEXT
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = TowersData.PROMPT_MAX_DISTANCE_STUDS
	else
		local value = PlacementRules.sellValueFor(self.catalog, placement.placementKind, placement.typeKind, placement.level)
		prompt.ActionText = string.format(TrapsData.SELL_PROMPT_ACTION_FORMAT, value)
		prompt.HoldDuration = TrapsData.SELL_PROMPT_HOLD_SEC
		prompt.MaxActivationDistance = TrapsData.SELL_PROMPT_MAX_DISTANCE_STUDS
		placement.promptConnection = prompt.Triggered:Connect(
			function(player: Player)
				self:sell(player, placement.id)
			end
		)
	end
	prompt.Parent = placement.shadow
end

function PlacementManager:setOccupied(placement: Placement, isOccupied: boolean)
	local zone = self.zonesByIndex[placement.zoneIndex]
	if not zone then
		return
	end
	for _, cell in PlacementRules.footprintCells(placement.cell, placement.footprint) do
		zone.occupancy[PlacementRules.occupancyKey(cell)] = if isOccupied then placement.id else nil
	end
end

function PlacementManager:spawn(player: Player, placementKind: number, typeKind: number, zone: Zone, cell: PlacementRules.Cell, footprint: { number }): Placement?
	local folder = self:getShadowFolder()
	if not folder then
		return nil
	end
	local id = string.format(PlacementRules.ID_FORMAT, self.nextId)
	self.nextId += 1
	local cframe = PlacementRules.footprintCFrame(zone.grid, cell, footprint)
	local shadow = Instance.new("Part")
	shadow.Name = id
	shadow.Size = Vector3.new(footprint[1] * zone.grid.cellSizeStuds, SHADOW_HEIGHT_STUDS, footprint[2] * zone.grid.cellSizeStuds)
	shadow.Transparency = 1
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.CanTouch = false
	-- the shadow sits on the top face; its centre is half its height up
	shadow.CFrame = cframe * CFrame.new(0, SHADOW_HEIGHT_STUDS / 2, 0)
	local maxHp = PlacementRules.maxHpFor(self.catalog, placementKind, typeKind, PlacementRules.STARTING_LEVEL)
	local placement: Placement = {
		id = id,
		placementKind = placementKind,
		typeKind = typeKind,
		owner = player,
		ownerUserId = player.UserId,
		level = PlacementRules.STARTING_LEVEL,
		hp = maxHp,
		maxHp = maxHp,
		zoneIndex = zone.index,
		cell = cell,
		footprint = footprint,
		cframe = cframe,
		targetPriority = DEFAULT_TARGET_PRIORITY,
		shadow = shadow,
		promptConnection = nil,
	}
	self.placementsById[id] = placement
	self:setOccupied(placement, true)
	self:replicatePlacement(placement)
	self:configurePrompt(placement)
	CollectionService:AddTag(shadow, Tags.PLACEMENT)
	shadow.Parent = folder
	self:firePlacementsChanged()
	return placement
end

function PlacementManager:remove(placement: Placement)
	if self.placementsById[placement.id] ~= placement then
		return
	end
	self.placementsById[placement.id] = nil
	self:setOccupied(placement, false)
	if placement.promptConnection then
		placement.promptConnection:Disconnect()
	end
	placement.shadow:Destroy()
	local owner = placement.owner
	if owner and owner.Parent == Players then
		self:replicatePlayer(owner)
	end
	self:firePlacementsChanged()
end

-- one build. Silent refusals are the cases an honest client never sends
-- (wrong tool, unknown kinds, out of reach); the rest are told, because
-- two players can race for the same cells
function PlacementManager:build(player: Player, placementKind: number, typeKind: number, zoneIndex: number, cell: PlacementRules.Cell)
	if not GameController:isPlayerReady(player) or ToolManager:getEquippedTool(player) ~= Enums.ToolKind.DEFENSES then
		return
	end
	if not Enums.isValidValue(PlacementRules.typeEnumFor(placementKind), typeKind) then
		warn(`PlacementManager: {player.Name} sent unknown kind {typeKind} for placement kind {placementKind}`)
		return
	end
	local footprint = PlacementRules.footprintFor(self.catalog, placementKind, typeKind)
	local zone = self.zonesByIndex[zoneIndex]
	if not footprint or not zone then
		return
	end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	local pose = PlacementRules.footprintCFrame(zone.grid, cell, footprint)
	if not PlacementRules.isWithinBuildReach(root.Position, pose.Position, PlacementData.BUILD_MAX_DISTANCE_STUDS) then
		return
	end
	if not PlacementRules.canPlace(zone.grid, zone.occupancy, cell, footprint) then
		PlayerFeedbackManager:give(player, FEEDBACK_SPOT_TAKEN)
		return
	end
	if placementKind == Enums.PlacementKind.TOWER then
		if not table.find(self:resolveTowerLoadout(player), typeKind) then
			PlayerFeedbackManager:give(player, FEEDBACK_NOT_IN_LOADOUT)
			return
		end
		if self:countActiveTowers(player) >= self.catalog.maxActiveTowersPerPlayer then
			PlayerFeedbackManager:give(player, string.format(FEEDBACK_TOWER_LIMIT_FORMAT, self.catalog.maxActiveTowersPerPlayer))
			return
		end
		local price = PlacementRules.buildPrice(self.catalog, placementKind, typeKind)
		if not PlacementRules.canAfford(RefineryManager:getIronBars(player), price) or not RefineryManager:spendIronBars(player, price) then
			PlayerFeedbackManager:give(player, FEEDBACK_NOT_ENOUGH_IRON)
			return
		end
	else
		if not self:consumeTrap(player, typeKind) then
			PlayerFeedbackManager:give(player, string.format(FEEDBACK_NO_TRAP_FORMAT, PlacementRules.publicName(placementKind, typeKind)))
			return
		end
	end
	local placement = self:spawn(player, placementKind, typeKind, zone, cell, footprint)
	if not placement then
		return
	end
	self:replicatePlayer(player)
	NetManager:notifyClient(player, NetEventNames.NOTIFY_PLACEMENT_BUILT, {
		id = placement.id,
	})
	print(`[PlacementManager] {player.Name} built {PlacementRules.publicName(placementKind, typeKind)} ({placement.id}) in zone {zoneIndex} at {cell.column},{cell.row}`)
end

-- selling returns the share to the owner's Iron; only the builder may
function PlacementManager:sell(player: Player, id: string)
	local placement = self.placementsById[id]
	if not placement or not GameController:isPlayerReady(player) or placement.owner ~= player then
		return
	end
	local value = PlacementRules.sellValueFor(self.catalog, placement.placementKind, placement.typeKind, placement.level)
	self:remove(placement)
	RefineryManager:addIronBars(player, value)
	NetManager:notifyClient(player, NetEventNames.NOTIFY_PLACEMENT_SOLD, {
		id = id,
		value = value,
	})
	print(`[PlacementManager] {player.Name} sold {id} for {value} Iron`)
end

function PlacementManager:upgrade(player: Player, id: string)
	local placement = self.placementsById[id]
	if not placement or not GameController:isPlayerReady(player) or placement.owner ~= player or placement.placementKind ~= Enums.PlacementKind.TOWER then
		return
	end
	local tower = self.catalog.towers[placement.typeKind]
	local offer = if tower then PlacementRules.towerUpgradeOffer(tower, placement.level) else nil
	if not tower or not offer then
		return
	end
	if not PlacementRules.canAfford(RefineryManager:getIronBars(player), offer.price) or not RefineryManager:spendIronBars(player, offer.price) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_ENOUGH_IRON)
		return
	end
	placement.level = offer.level
	local newMaxHp = PlacementRules.towerStats(tower, placement.level).MAX_HP
	placement.hp = PlacementRules.hpAfterUpgrade(placement.hp, placement.maxHp, newMaxHp)
	placement.maxHp = newMaxHp
	self:replicatePlacement(placement)
	NetManager:notifyClient(player, NetEventNames.NOTIFY_TOWER_UPGRADED, {
		id = id,
		level = placement.level,
		price = offer.price,
	})
	print(`[PlacementManager] {player.Name} upgraded {id} to level {placement.level} for {offer.price} Iron`)
end

function PlacementManager:setTargetPriority(player: Player, id: string, priority: number)
	local placement = self.placementsById[id]
	if not placement or placement.owner ~= player or placement.placementKind ~= Enums.PlacementKind.TOWER then
		return
	end
	placement.targetPriority = priority
	self:replicatePlacement(placement)
end

-- one Hammer swing at a Tower: the wall's checks (StructureManager
-- handleRepair) against the Tower's shadow. Silent refusals are the cases
-- an honest client never sends
function PlacementManager:repairTower(player: Player, id: string)
	local placement = self.placementsById[id]
	if not placement or placement.placementKind ~= Enums.PlacementKind.TOWER or ToolManager:getEquippedTool(player) ~= Enums.ToolKind.HAMMER then
		return
	end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	if not StructureRules.isWithinReach(root.Position, placement.shadow.CFrame, placement.shadow.Size, StructuresData.HAMMER_REACH_STUDS, StructuresData.HAMMER_REACH_TOLERANCE_STUDS) then
		return
	end
	local now = workspace:GetServerTimeNow()
	if not StructureRules.canSwing(self.lastSwingTimeByPlayer[player], now, StructuresData.HAMMER_HIT_COOLDOWN_SEC) then
		return
	end
	local gained, cost = StructureRules.repairChunk(placement.maxHp, placement.hp, StructuresData.REPAIR_CHUNK_HP, StructuresData.REPAIR_CHUNK_IRON)
	if gained <= 0 then
		return
	end
	self.lastSwingTimeByPlayer[player] = now
	if not RefineryManager:spendIronBars(player, cost) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_ENOUGH_IRON)
		return
	end
	placement.hp = math.min(placement.maxHp, placement.hp + gained)
	self:replicatePlacement(placement)
	NetManager:notifyAllClients(NetEventNames.NOTIFY_TOWER_REPAIRED, {
		id = id,
		userId = player.UserId,
	})
end

-- the one way HP goes down; enemies (M27, M29) and the dev tool come through here
function PlacementManager:damagePlacement(id: string, amount: number)
	local placement = self.placementsById[id]
	if not placement or amount <= 0 then
		return
	end
	placement.hp = math.max(0, placement.hp - amount)
	if placement.hp <= 0 then
		print(`[PlacementManager] {id} destroyed`)
		self:remove(placement)
		return
	end
	self:replicatePlacement(placement)
end

-- a one-use Trap that went off is simply gone
function PlacementManager:removePlacement(id: string)
	local placement = self.placementsById[id]
	if placement then
		self:remove(placement)
	end
end

function PlacementManager:clearPlacements()
	for _, placement in self.placementsById do
		self:remove(placement)
	end
end

function PlacementManager:getNetHandlers()
	return {
		[NetEventNames.TRY_BUILD_PLACEMENT] = {
			shape = TRY_BUILD_PLACEMENT_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:build(player, payload.placementKind, payload.typeKind, payload.zoneIndex, { column = payload.column, row = payload.row })
			end,
		},
		[NetEventNames.TRY_SELL_PLACEMENT] = {
			shape = TRY_SELL_PLACEMENT_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:sell(player, payload.id)
			end,
		},
		[NetEventNames.TRY_UPGRADE_TOWER] = {
			shape = TRY_UPGRADE_TOWER_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:upgrade(player, payload.id)
			end,
		},
		[NetEventNames.TRY_SET_TOWER_TARGET_PRIORITY] = {
			shape = TRY_SET_TOWER_TARGET_PRIORITY_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:setTargetPriority(player, payload.id, payload.priority)
			end,
		},
		[NetEventNames.TRY_REPAIR_TOWER] = {
			shape = TRY_REPAIR_TOWER_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:repairTower(player, payload.id)
			end,
		},
	}
end

-- the map's zone parts, numbered in name order so the key a client sends
-- means the same part on both sides
function PlacementManager:bindZones()
	self.zonesByIndex = {}
	local camp = MapManager:getCamp()
	local folder = if camp then camp:FindFirstChild(Constants.CAMP_DEFENSIVE_ZONES_FOLDER) else nil
	if not folder then
		warn("PlacementManager: the loaded camp has no DefensiveZones folder; nothing can be built")
		return
	end
	local parts: { BasePart } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	table.sort(
		parts,
		function(a: BasePart, b: BasePart): boolean
			return a.Name < b.Name
		end
	)
	for index, part in parts do
		part:SetAttribute(Attributes.DEFENSIVE_ZONE_INDEX, index)
		CollectionService:AddTag(part, Tags.DEFENSIVE_ZONE)
		self.zonesByIndex[index] = {
			index = index,
			part = part,
			grid = PlacementRules.measureZone(part.CFrame, part.Size, self.catalog.cellSizeStuds),
			occupancy = {},
		}
	end
end

-- a run (or a dev-tool restart) starts with an empty grid on the fresh
-- map; Trap inventories are run state that survives a restart like the balances
function PlacementManager:onRunStarted()
	self:clearPlacements()
	self.shadowFolder = nil
	self:bindZones()
end

-- ready-sequence entry; not replayed on a dev-tool reset, so run state
-- survives. Everyone carries the Defenses tool from the start
function PlacementManager:onPlayerReady(player: Player)
	self:getPlayerState(player)
	ToolManager:grantTool(player, Enums.ToolKind.DEFENSES)
	self:replicatePlayer(player)
end

function PlacementManager:init()
	self.catalog = {
		cellSizeStuds = PlacementData.CELL_SIZE_STUDS,
		previewDistanceStuds = PlacementData.PREVIEW_DISTANCE_STUDS,
		maxActiveTowersPerPlayer = TowersData.MAX_ACTIVE_TOWERS_PER_PLAYER,
		maxTrapKindsCarried = TrapsData.MAX_TRAP_KINDS_CARRIED,
		towerSellShare = TowersData.SELL_SHARE,
		trapSellShare = TrapsData.SELL_SHARE,
		towers = TowersData.BY_KIND,
		traps = TrapsData.BY_KIND,
	}
	SplendidReplicationManager:setGameMetadata(Attributes.DEFENSE_CATALOG, PlacementRules.encodeCatalog(self.catalog))
	GameController:registerPlaceManager(self)
	Players.PlayerRemoving:Connect(
		function(player: Player)
			-- a leaver's placements keep standing; nobody can sell or upgrade them
			for _, placement in self.placementsById do
				if placement.owner == player then
					placement.owner = nil
				end
			end
			self.stateByPlayer[player] = nil
			self.lastSwingTimeByPlayer[player] = nil
		end
	)
end

function PlacementManager.new(): PlacementManager
	local self = setmetatable({}, PlacementManager) :: PlacementManager
	self.catalog = {
		cellSizeStuds = PlacementData.CELL_SIZE_STUDS,
		previewDistanceStuds = PlacementData.PREVIEW_DISTANCE_STUDS,
		maxActiveTowersPerPlayer = 0,
		maxTrapKindsCarried = 0,
		towerSellShare = 0,
		trapSellShare = 0,
		towers = {},
		traps = {},
	}
	self.placementsById = {}
	self.zonesByIndex = {}
	self.stateByPlayer = {}
	self.lastSwingTimeByPlayer = {}
	self.nextId = 1
	self.shadowFolder = nil
	self.placementsChangedHandlers = {}
	return self
end

return PlacementManager.new()
