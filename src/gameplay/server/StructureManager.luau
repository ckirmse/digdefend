--!strict

-- Camp structures with HP (GDD "Walls", "Gate", "Refinery", "Wall Repair"):
-- the six wall segments, the gate, and the Refinery. HP and the shared
-- fortification tier live in Lua here. Each structure has one shadow part (the
-- shadow system: a small invisible anchored server part carrying attributes)
-- that publishes its HP; clients hang the Repair Mode HP bar on it while the
-- Hammer is equipped. Repair works like mining: every Hammer swing is a
-- TryRepairStructure request validated here (equipped, damaged, reach,
-- cooldown, Iron) that adds one chunk of HP.
--
-- The map's Wall / Gate / Post / Refinery models are placement markers: at
-- run start each is swapped for the tier's template from
-- GameAssets/Structures at the marker's pivot, and swapped again on an
-- upgrade, on destruction (rubble; the Refinery has none), and on a
-- rebuild. A wall named "Wall0" is decoration that joins the line
-- to the terrain (StructureRules.isDecorativeWall, 2026-09-30): filled and
-- upgraded like a wall, but it has no HP, no shadow, no repair, and the
-- monsters never target it; it only blocks their way. The gate, the walls,
-- and the look of the posts share one
-- tier, paid for by the whole crew at the Workbench: each prompt press
-- donates a little Iron into a shared pool and the tier goes up by itself
-- when the pool fills. Every segment is repaired on its own. The Refinery
-- keeps its authored model.
--
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PlacementRules = require("@game/ReplicatedStorage/Shared/PlacementRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local RunCycleRules = require("@game/ReplicatedStorage/Shared/RunCycleRules")
local StructureRules = require("@game/ReplicatedStorage/Shared/StructureRules")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local StructuresData = require("@game/ServerScriptService/GameData/Camp/Structures")
local PartyScalingData = require("@game/ServerScriptService/GameData/Control/PartyScaling")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SpatialSoundManager = require(script.Parent.Parent.Server.SpatialSoundManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local MapManager = require(script.Parent.MapManager)
local RefineryManager = require(script.Parent.RefineryManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local ToolManager = require(script.Parent.ToolManager)

local StructureManager = {}
StructureManager.__index = StructureManager

type Structure = {
	id: string,
	kind: number,
	hp: number,
	-- rubble: set by the blow that empties it, cleared once rebuilt to
	-- REBUILD_STAND_SHARE, so a half-rebuilt wall is still a breach
	isDestroyed: boolean,
	-- the size HP was last measured against, so a tier change can carry
	-- the share over
	maxHp: number,
	shadow: BasePart,
	-- what a swing must be in reach of; measured once from the map's model
	boundsCFrame: CFrame,
	boundsSize: Vector3,
	-- nil for the Refinery, whose authored model is never swapped
	slot: Slot?,
}

-- what the monsters (M29) see of a structure: its box and whether it stands
export type StructureBox = {
	id: string,
	kind: number,
	cframe: CFrame,
	size: Vector3,
	hp: number,
	isDestroyed: boolean,
}

-- where a template goes: the marker's pivot, parent, and name, kept after
-- the marker itself is gone
export type Slot = {
	name: string,
	templateKey: string,
	pivot: CFrame,
	parent: Instance,
	model: Model?,
}

export type StructureManager = typeof(setmetatable(
	{} :: {
		structuresById: { [string]: Structure },
		postSlots: { Slot },
		-- the map's Wall0 models, kept only so their look follows the tier
		decorativeSlots: { Slot },
		fortificationTier: number,
		-- Iron the crew has donated toward the next tier
		fortificationPool: number,
		isNight: boolean,
		isGateOpen: boolean,
		gateLeaves: { BasePart },
		lastSwingTimeByPlayer: { [Player]: number },
		workbenchPrompt: ProximityPrompt?,
		connections: { RBXScriptConnection },
		refineryDestroyedHandlers: { () -> () },
		postModelsFilledHandlers: { () -> () },
		-- fired when what blocks the monsters' way changes: a structure
		-- falls or is rebuilt, the gate opens or shuts, a run starts
		barriersChangedHandlers: { () -> () },
		-- damage landed on a structure, and a Hammer swing that put HP back
		-- (the run report, M34)
		structureDamagedHandlers: { (id: string, kind: number, amount: number, isDestroyed: boolean, attackerKind: number?) -> () },
		structureRepairedHandlers: { (player: Player, id: string, gained: number, cost: number) -> () },
		warnedTemplates: { [string]: boolean },
		-- a live monster is within the attack radius of the Refinery
		isRefineryUnderAttack: boolean,
	},
	StructureManager
))

local SHADOW_FOLDER = "StructureShadows"
local SHADOW_SIZE = Vector3.new(1, 1, 1)
-- the HP bar hangs at chest height, whatever the model's height
local SHADOW_HEIGHT_ABOVE_FLOOR_STUDS = 4
local STARTING_TIER = 1
local WALL_TEMPLATE_KEY = Constants.WALL_TEMPLATE_PREFIX
local GATE_TEMPLATE_KEY = Constants.GATE_TEMPLATE_PREFIX
local REFINERY_TEMPLATE_KEY = Constants.REFINERY_TEMPLATE_PREFIX
local GATE_ID = Constants.CAMP_GATE_MODEL
local REFINERY_ID = Constants.CAMP_REFINERY_MODEL

local TRY_REPAIR_STRUCTURE_SHAPE = {
	-- a structure id ("Wall3", "Gate", "Refinery")
	id = "string",
}

local POST_SIGN_FORMAT = "DEFENSE POST #%s"

local FEEDBACK_MAXED = "Fortifications are fully upgraded"
local FEEDBACK_NOT_ENOUGH_IRON = "Not enough Iron"

function StructureManager:getStructure(id: string): Structure?
	return self.structuresById[id]
end

function StructureManager:getStructureIds(): { string }
	local ids = {}
	for id in self.structuresById do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

function StructureManager:getFortificationTier(): number
	return self.fortificationTier
end

function StructureManager:isDestroyed(id: string): boolean
	local structure = self.structuresById[id]
	return structure ~= nil and structure.isDestroyed
end

-- the run state machine (M28) ends the run from here
function StructureManager:subscribeRefineryDestroyed(handler: () -> ())
	table.insert(self.refineryDestroyedHandlers, handler)
end

function StructureManager:subscribeStructureDamaged(handler: (id: string, kind: number, amount: number, isDestroyed: boolean, attackerKind: number?) -> ())
	table.insert(self.structureDamagedHandlers, handler)
end

function StructureManager:subscribeStructureRepaired(handler: (player: Player, id: string, gained: number, cost: number) -> ())
	table.insert(self.structureRepairedHandlers, handler)
end

-- the monsters' way through the camp is recomputed from here (M29)
function StructureManager:subscribeBarriersChanged(handler: () -> ())
	table.insert(self.barriersChangedHandlers, handler)
end

function StructureManager:fireBarriersChanged()
	for _, handler in self.barriersChangedHandlers do
		handler()
	end
end

-- every structure's box in id order; a snapshot, never the live entry
function StructureManager:getStructureBoxes(): { StructureBox }
	local boxes = {}
	for _, id in self:getStructureIds() do
		local structure = self.structuresById[id]
		table.insert(boxes, {
			id = structure.id,
			kind = structure.kind,
			cframe = structure.boundsCFrame,
			size = structure.boundsSize,
			hp = structure.hp,
			isDestroyed = structure.isDestroyed,
		})
	end
	return boxes
end

function StructureManager:isGateOpenNow(): boolean
	return self.isGateOpen
end

-- every fortification's box as it stands at run start (walls, decorative
-- walls, posts, the gate): what the Defensive Zone grid keeps clear of
function StructureManager:getFortificationBoxes(): { PlacementRules.Box }
	local boxes = {}
	for _, slot in self.decorativeSlots do
		if slot.model then
			local cframe, size = slot.model:GetBoundingBox()
			table.insert(boxes, { cframe = cframe, size = size })
		end
	end
	for _, structure in self.structuresById do
		if structure.kind ~= Enums.StructureKind.REFINERY then
			table.insert(boxes, { cframe = structure.boundsCFrame, size = structure.boundsSize })
		end
	end
	for _, slot in self.postSlots do
		if slot.model then
			local cframe, size = slot.model:GetBoundingBox()
			table.insert(boxes, { cframe = cframe, size = size })
		end
	end
	return boxes
end

function StructureManager:getPostSlots(): { Slot }
	return self.postSlots
end

-- fired whenever the post models are swapped (run start, a fortification
-- tier), since a new model carries a fresh sign and no prompt
function StructureManager:subscribePostModelsFilled(handler: () -> ())
	table.insert(self.postModelsFilledHandlers, handler)
end

function StructureManager:firePostModelsFilled()
	for _, handler in self.postModelsFilledHandlers do
		handler()
	end
end

function StructureManager:getKindData(kind: number): StructureRules.KindData
	return StructuresData.BY_KIND[kind]
end

-- every structure shares the fortification tier, the Refinery included
function StructureManager:getTier(structure: Structure): number
	return self.fortificationTier
end

function StructureManager:getMaxHp(structure: Structure): number
	return StructureRules.maxHp(self:getKindData(structure.kind), self:getTier(structure))
end

-- Iron the next tier costs the crew that is here (the dawn count, as the
-- tower cap uses); nil at the top tier
function StructureManager:getNextTierCost(): number?
	local soloCost = StructureRules.upgradeCost(StructuresData.FORTIFICATION_UPGRADE_IRON_TO_TIER, self.fortificationTier)
	local multiplier = RunCycleRules.multiplierFor(PartyScalingData.WAVE_DIFFICULTY_MULTIPLIER_BY_PLAYER_COUNT, RunCycleManager:getScalingCount())
	return StructureRules.scaledUpgradeCost(soloCost, multiplier, self:getDonationIron())
end

-- what one press moves at the current tier (doubles a tier, 2026-10-08)
function StructureManager:getDonationIron(): number
	return StructureRules.donationForTier(StructuresData.FORTIFICATION_DONATION_IRON, self.fortificationTier)
end

-- what one swing adds and costs on this structure, by its tier
function StructureManager:getRepairChunk(structure: Structure): (number, number)
	return StructureRules.repairChunkForTier(StructuresData.REPAIR_CHUNK_HP_BY_TIER, StructuresData.REPAIR_CHUNK_IRON_BY_TIER, self:getTier(structure))
end

function StructureManager:findTemplate(templateName: string): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local folder = if gameAssets then gameAssets:FindFirstChild(Constants.STRUCTURE_TEMPLATES_FOLDER) else nil
	local template = if folder then folder:FindFirstChild(templateName) else nil
	if template and template:IsA("Model") then
		return template
	end
	if not self.warnedTemplates[templateName] then
		self.warnedTemplates[templateName] = true
		warn(`StructureManager: no Model named {templateName} under GameAssets.{Constants.STRUCTURE_TEMPLATES_FOLDER}; run scripts/studio/build_structure_templates.luau`)
	end
	return nil
end

-- puts the named template in the slot; a missing template leaves whatever
-- is there, so a camp without templates still plays with its authored walls
function StructureManager:fillSlot(slot: Slot, templateName: string): Model?
	local template = self:findTemplate(templateName)
	if not template then
		return slot.model
	end
	local previous = slot.model
	local model = template:Clone()
	model.Name = slot.name
	model:PivotTo(slot.pivot)
	model.Parent = slot.parent
	slot.model = model
	if previous then
		previous:Destroy()
	end
	return model
end

-- every post template carries the same sign; the slot it lands in names it
-- ("Post4" reads "DEFENSE POST #4"). A template without the sign is fine.
-- The model is also tagged and numbered for the clients and PostManager
function StructureManager:labelPost(slot: Slot)
	local model = slot.model
	if model then
		CollectionService:AddTag(model, Tags.POST)
		model:SetAttribute(Attributes.POST_MODEL_INDEX, tonumber(slot.name:sub(#Constants.POST_NAME_PREFIX + 1)) or 0)
	end
	local signModel = if model then model:FindFirstChild(Constants.POST_SIGN_MODEL) else nil
	local signPart = if signModel then signModel:FindFirstChild(Constants.POST_SIGN_PART) else nil
	local gui = if signPart then signPart:FindFirstChildWhichIsA("SurfaceGui") else nil
	local label = if gui then gui:FindFirstChild(Constants.POST_SIGN_NUMBER_LABEL) else nil
	if label and label:IsA("TextLabel") then
		label.Text = string.format(POST_SIGN_FORMAT, slot.name:sub(#Constants.POST_NAME_PREFIX + 1))
	end
end

-- a post has no HP of its own (claiming and weapons are M25): its slot only
-- follows the fortification tier's look
function StructureManager:fillPostSlot(slot: Slot)
	self:fillSlot(slot, `{slot.templateKey}_{self.fortificationTier}`)
	self:labelPost(slot)
end

function StructureManager:templateNameFor(structure: Structure, slot: Slot): string
	-- the Refinery has no rubble: its fall is the run's end, so the tier's
	-- model stands through the loss
	if structure.isDestroyed and structure.kind ~= Enums.StructureKind.REFINERY then
		return `{slot.templateKey}_{Constants.STRUCTURE_RUBBLE_SUFFIX}`
	end
	return `{slot.templateKey}_{self.fortificationTier}`
end

-- finds the two leaves in the live gate model; the marker parts are the
-- designer's guides and never show in play
function StructureManager:bindGateDoor(gateModel: Model?)
	self.gateLeaves = {}
	local door = if gateModel then gateModel:FindFirstChild(Constants.GATE_DOOR_MODEL) else nil
	if not door then
		return
	end
	for _, leafName in { Constants.GATE_DOOR_LEFT_PART, Constants.GATE_DOOR_RIGHT_PART } do
		local leaf = door:FindFirstChild(leafName)
		local closed = door:FindFirstChild(leafName .. Constants.GATE_DOOR_CLOSED_SUFFIX)
		local open = door:FindFirstChild(leafName .. Constants.GATE_DOOR_OPEN_SUFFIX)
		if not (leaf and leaf:IsA("BasePart") and open and open:IsA("BasePart")) then
			warn(`StructureManager: {door:GetFullName()} needs {leafName} with its {leafName}{Constants.GATE_DOOR_OPEN_SUFFIX} marker part; that leaf will not move`)
			continue
		end
		-- the Closed marker is optional: a leaf is authored shut, so without
		-- one its own pose is the closed pose
		for _, marker in { closed, open } do
			if marker and marker:IsA("BasePart") then
				marker.Transparency = 1
				marker.CanCollide = false
				marker.CanQuery = false
				marker.CanTouch = false
			end
		end
		table.insert(self.gateLeaves, leaf)
	end
	self:applyGateCollision()
end

-- the server never moves the leaves (clients tween them between the markers,
-- and a server move would snap over the tween); it only decides whether
-- they block, which is what replication carries
function StructureManager:applyGateCollision()
	for _, leaf in self.gateLeaves do
		for _, part in { leaf, table.unpack(leaf:GetChildren()) } do
			if part:IsA("BasePart") then
				part.CanCollide = not self.isGateOpen
			end
		end
	end
end

function StructureManager:setGateOpen(isOpen: boolean)
	if self.isGateOpen == isOpen then
		return
	end
	self.isGateOpen = isOpen
	self:applyGateCollision()
	local gate = self.structuresById[GATE_ID]
	if gate then
		gate.shadow:SetAttribute(Attributes.GATE_IS_OPEN, isOpen)
	end
	self:fireBarriersChanged()
end

-- the doors stand open all day and shut all night (decided 2026-09-17,
-- replacing doors that opened for a nearby player); rubble has no doors
function StructureManager:updateGate()
	local gate = self.structuresById[GATE_ID]
	self:setGateOpen(gate ~= nil and not gate.isDestroyed and not self.isNight)
end

-- the day clock is M28; until then a dev tool flips this
function StructureManager:setNight(isNight: boolean)
	self.isNight = isNight
	SplendidReplicationManager:setGameMetadata(Attributes.IS_NIGHT, isNight)
	self:updateGate()
end

function StructureManager:getIsNight(): boolean
	return self.isNight
end

function StructureManager:replicateStructure(structure: Structure)
	local shadow = structure.shadow
	shadow:SetAttribute(Attributes.STRUCTURE_HP, structure.hp)
	shadow:SetAttribute(Attributes.STRUCTURE_IS_DESTROYED, structure.isDestroyed)
	shadow:SetAttribute(Attributes.STRUCTURE_MAX_HP, self:getMaxHp(structure))
end

-- the Workbench sign: tier, pool, what the next tier costs and needs; and
-- the swing chunk the walls take at this tier, for the repair HUD
function StructureManager:replicateFortification()
	local nextTierCost = self:getNextTierCost()
	local chunkHp, chunkIron = StructureRules.repairChunkForTier(StructuresData.REPAIR_CHUNK_HP_BY_TIER, StructuresData.REPAIR_CHUNK_IRON_BY_TIER, self.fortificationTier)
	SplendidReplicationManager:setGameMetadata(Attributes.REPAIR_CHUNK_HP, chunkHp)
	SplendidReplicationManager:setGameMetadata(Attributes.REPAIR_CHUNK_IRON, chunkIron)
	SplendidReplicationManager:setGameMetadata(Attributes.FORTIFICATION_TIER, self.fortificationTier)
	SplendidReplicationManager:setGameMetadata(Attributes.FORTIFICATION_POOL, self.fortificationPool)
	SplendidReplicationManager:setGameMetadata(Attributes.FORTIFICATION_POOL_REQUIRED, nextTierCost or 0)
	local prompt = self.workbenchPrompt
	if prompt then
		prompt.Enabled = nextTierCost ~= nil
		prompt.ActionText = string.format(StructuresData.WALLS_TABLE_PROMPT_ACTION_FORMAT, self:getDonationIron())
	end
end

function StructureManager:replicateAll()
	self:replicateFortification()
	for _, structure in self.structuresById do
		self:replicateStructure(structure)
	end
end

-- swaps the structure's model for what its state calls for (tier or rubble)
function StructureManager:syncModel(structure: Structure)
	local slot = structure.slot
	if not slot then
		return
	end
	local model = self:fillSlot(slot, self:templateNameFor(structure, slot))
	if structure.kind == Enums.StructureKind.GATE then
		self:bindGateDoor(if structure.isDestroyed then nil else model)
		self:updateGate()
	end
end

-- everyone hears a wall or the gate go: the red alert naming it, and its
-- collapse from where it stood (2026-09-25; the gate since 2026-10-07)
function StructureManager:announceWallDestroyed(structure: Structure)
	local number = StructureRules.numberFromId(structure.id)
	local message = if structure.kind == Enums.StructureKind.GATE
		then StructuresData.GATE_DESTROYED_MESSAGE
		elseif number then string.format(StructuresData.WALL_DESTROYED_MESSAGE_FORMAT, number)
		else nil
	if message then
		NetManager:notifyAllClients(NetEventNames.NOTIFY_WALL_DESTROYED, {
			message = message,
			displaySec = StructuresData.ALERT_DISPLAY_SEC,
		})
	end
	SpatialSoundManager:playAt(structure.boundsCFrame.Position, SoundNames.Sfx.WALL_COLLAPSE, StructuresData.WALL_COLLAPSE_FULL_VOLUME_STUDS, StructuresData.WALL_COLLAPSE_SILENT_STUDS)
end

-- MonsterManager reports whether any live monster is within the attack
-- radius; the alert goes out once as it becomes true, and the flag every
-- client loops the siren on follows it (2026-09-25)
function StructureManager:setRefineryUnderAttack(isUnderAttack: boolean)
	if isUnderAttack == self.isRefineryUnderAttack then
		return
	end
	self.isRefineryUnderAttack = isUnderAttack
	SplendidReplicationManager:setGameMetadata(Attributes.REFINERY_UNDER_ATTACK, isUnderAttack)
	if isUnderAttack then
		NetManager:notifyAllClients(NetEventNames.NOTIFY_REFINERY_ATTACKED, {
			message = StructuresData.REFINERY_ATTACKED_MESSAGE,
			displaySec = StructuresData.ALERT_DISPLAY_SEC,
		})
	end
end

-- the one way HP goes down; enemies (M29) and the dev tool both come
-- through here. attackerKind is the Enums.MonsterKind that dealt it, nil
-- from the dev tool
function StructureManager:damageStructure(id: string, amount: number, attackerKind: number?)
	local structure = self.structuresById[id]
	if not structure or amount <= 0 or structure.hp <= 0 then
		return
	end
	local applied = math.min(amount, structure.hp)
	structure.hp = math.max(0, structure.hp - amount)
	local isNewlyDestroyed = structure.hp <= 0 and not structure.isDestroyed
	for _, handler in self.structureDamagedHandlers do
		handler(id, structure.kind, applied, isNewlyDestroyed, attackerKind)
	end
	if isNewlyDestroyed then
		structure.isDestroyed = true
		print(`[StructureManager] {id} destroyed`)
		self:syncModel(structure)
		if structure.kind == Enums.StructureKind.WALL then
			self:announceWallDestroyed(structure)
		end
		if structure.kind == Enums.StructureKind.REFINERY then
			for _, handler in self.refineryDestroyedHandlers do
				handler()
			end
		end
		self:fireBarriersChanged()
	end
	self:replicateStructure(structure)
end

-- one Hammer swing. Silent refusals are the cases an honest client never
-- sends (wrong tool, out of reach, too fast, nothing missing)
function StructureManager:handleRepair(player: Player, id: string)
	local structure = self.structuresById[id]
	if not structure or ToolManager:getEquippedTool(player) ~= Enums.ToolKind.HAMMER then
		return
	end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	if not StructureRules.isWithinReach(root.Position, structure.boundsCFrame, structure.boundsSize, StructuresData.HAMMER_REACH_STUDS, StructuresData.HAMMER_REACH_TOLERANCE_STUDS) then
		return
	end
	local now = workspace:GetServerTimeNow()
	if not StructureRules.canSwing(self.lastSwingTimeByPlayer[player], now, StructuresData.HAMMER_HIT_COOLDOWN_SEC) then
		return
	end
	local chunkHp, chunkIron = self:getRepairChunk(structure)
	local gained, cost = StructureRules.repairChunk(self:getMaxHp(structure), structure.hp, chunkHp, chunkIron)
	if gained <= 0 then
		return
	end
	self.lastSwingTimeByPlayer[player] = now
	if not RefineryManager:spendIronBars(player, cost) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_ENOUGH_IRON)
		return
	end
	structure.hp += gained
	for _, handler in self.structureRepairedHandlers do
		handler(player, id, gained, cost)
	end
	if structure.isDestroyed and StructureRules.isRebuilt(structure.hp, self:getMaxHp(structure), StructuresData.REBUILD_STAND_SHARE) then
		structure.isDestroyed = false
		self:syncModel(structure)
		print(`[StructureManager] {player.Name} rebuilt {structure.id}`)
		self:fireBarriersChanged()
	end
	self:replicateStructure(structure)
	NetManager:notifyAllClients(NetEventNames.NOTIFY_STRUCTURE_REPAIRED, {
		id = id,
		userId = player.UserId,
	})
end

-- one press at the Workbench: a little of the player's Iron goes into the
-- crew's pool, and the press that fills it lifts the gate, every wall, and
-- the look of the posts a tier
function StructureManager:donate(player: Player)
	if not GameController:isPlayerReady(player) then
		return
	end
	local nextTierCost = self:getNextTierCost()
	if not nextTierCost then
		PlayerFeedbackManager:give(player, FEEDBACK_MAXED)
		return
	end
	local amount, isFilled = StructureRules.donate(self.fortificationPool, nextTierCost, self:getDonationIron())
	if amount <= 0 then
		return
	end
	if not RefineryManager:spendIronBars(player, amount, "fortifications") then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_ENOUGH_IRON)
		return
	end
	self.fortificationPool += amount
	NetManager:notifyClient(player, NetEventNames.NOTIFY_FORTIFICATION_DONATED, { amount = amount })
	if isFilled then
		local nextTier = self.fortificationTier + 1
		print(`[StructureManager] the crew upgraded the fortifications to tier {nextTier} ({player.Name} gave the last Iron)`)
		-- replicates the emptied pool along with the new tier
		self:setFortificationTier(nextTier)
		NetManager:notifyAllClients(NetEventNames.NOTIFY_FORTIFICATION_UPGRADED, { tier = nextTier })
	else
		self:replicateFortification()
	end
end

-- the structure's tier changed under it: keep its share of HP
function StructureManager:rescaleHp(structure: Structure)
	local newMaxHp = self:getMaxHp(structure)
	structure.hp = StructureRules.hpAfterUpgrade(structure.hp, structure.maxHp, newMaxHp)
	structure.maxHp = newMaxHp
end

function StructureManager:setFortificationTier(tier: number)
	local topTier = StructureRules.topTier(self:getKindData(Enums.StructureKind.GATE))
	local newTier = math.clamp(math.floor(tier), STARTING_TIER, topTier)
	self.fortificationTier = newTier
	-- a donation pool belongs to the tier it was filling
	self.fortificationPool = 0
	for _, structure in self.structuresById do
		-- every structure, the Refinery included since 2026-10-09, swaps to
		-- the tier's model and keeps its share of HP
		self:rescaleHp(structure)
		if structure.slot then
			self:syncModel(structure)
		else
			self:replicateStructure(structure)
		end
	end
	for _, slot in self.postSlots do
		self:fillPostSlot(slot)
	end
	for _, slot in self.decorativeSlots do
		self:fillSlot(slot, `{WALL_TEMPLATE_KEY}_{newTier}`)
	end
	self:firePostModelsFilled()
	self:replicateAll()
end

-- binds the loaded camp's Walls Table in the defense building (2026-10-01,
-- where the Workbench by the gate used to be); the prompt is created here
-- so a table authored in Studio needs only its Prompt part
function StructureManager:bindWallsTable()
	self.workbenchPrompt = nil
	local promptPart = MapManager:findDefenseTablePart(Constants.WALLS_TABLE_MODEL, Constants.DEFENSE_TABLE_PROMPT_PART)
	if not promptPart then
		warn(`StructureManager: the loaded camp has no {Constants.WALLS_TABLE_MODEL}.{Constants.DEFENSE_TABLE_PROMPT_PART} in its {Constants.CAMP_DEFENSE_STORE_MODEL}; the fortifications cannot be upgraded`)
		return
	end
	local prompt = promptPart:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		-- a clickable prompt frees the mouse when hovered, which sticks the cursor in first person (2026-09-29)
		prompt.ClickablePrompt = false
		prompt.Parent = promptPart
	end
	local livePrompt = prompt :: ProximityPrompt
	livePrompt.ActionText = string.format(StructuresData.WALLS_TABLE_PROMPT_ACTION_FORMAT, self:getDonationIron())
	livePrompt.ObjectText = StructuresData.WALLS_TABLE_PROMPT_OBJECT_TEXT
	livePrompt.MaxActivationDistance = StructuresData.WALLS_TABLE_PROMPT_MAX_DISTANCE_STUDS
	livePrompt.HoldDuration = 0
	livePrompt.RequiresLineOfSight = false
	self.workbenchPrompt = livePrompt
	table.insert(
		self.connections,
		livePrompt.Triggered:Connect(
			function(player: Player)
				self:donate(player)
			end
		)
	)
end

function StructureManager:getNetHandlers()
	return {
		[NetEventNames.TRY_REPAIR_STRUCTURE] = {
			shape = TRY_REPAIR_STRUCTURE_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:handleRepair(player, payload.id)
			end,
		},
	}
end

function StructureManager:addStructure(id: string, kind: number, model: Model, shadowFolder: Instance, slot: Slot?)
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local shadow = Instance.new("Part")
	shadow.Name = id
	shadow.Size = SHADOW_SIZE
	shadow.Transparency = 1
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.CanTouch = false
	-- chest height above the structure's floor, at its centre
	shadow.Position = Vector3.new(boundsCFrame.Position.X, boundsCFrame.Position.Y - boundsSize.Y / 2 + SHADOW_HEIGHT_ABOVE_FLOOR_STUDS, boundsCFrame.Position.Z)
	shadow:SetAttribute(Attributes.STRUCTURE_ID, id)
	shadow:SetAttribute(Attributes.STRUCTURE_KIND, kind)
	shadow:SetAttribute(Attributes.STRUCTURE_BOUNDS_CFRAME, boundsCFrame)
	shadow:SetAttribute(Attributes.STRUCTURE_BOUNDS_SIZE, boundsSize)
	if kind == Enums.StructureKind.GATE then
		shadow:SetAttribute(Attributes.GATE_IS_OPEN, false)
	end

	local structure: Structure = {
		id = id,
		kind = kind,
		hp = 0,
		isDestroyed = false,
		maxHp = 0,
		shadow = shadow,
		boundsCFrame = boundsCFrame,
		boundsSize = boundsSize,
		slot = slot,
	}
	structure.maxHp = self:getMaxHp(structure)
	structure.hp = structure.maxHp
	self.structuresById[id] = structure
	CollectionService:AddTag(shadow, Tags.STRUCTURE)
	shadow.Parent = shadowFolder
end

-- turns a marker model into a slot and fills it with the starting tier
function StructureManager:claimSlot(marker: Model, templateKey: string): Slot
	local slot: Slot = {
		name = marker.Name,
		templateKey = templateKey,
		pivot = marker:GetPivot(),
		parent = marker.Parent :: Instance,
		model = marker,
	}
	self:fillSlot(slot, `{templateKey}_{self.fortificationTier}`)
	return slot
end

-- a run (or a dev-tool restart) rebuilds everything from the fresh map
function StructureManager:onRunStarted()
	self:setRefineryUnderAttack(false)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.connections = {}
	self.structuresById = {}
	self.postSlots = {}
	self.decorativeSlots = {}
	self.gateLeaves = {}
	self.fortificationTier = STARTING_TIER
	self.fortificationPool = 0
	self.workbenchPrompt = nil
	self.isNight = false
	self.isGateOpen = false
	self.lastSwingTimeByPlayer = {}

	local camp = MapManager:getCamp()
	if not camp then
		warn("StructureManager: no camp is loaded; there are no structures")
		return
	end
	local shadowFolder = Instance.new("Folder")
	shadowFolder.Name = SHADOW_FOLDER
	shadowFolder.Parent = camp

	local walls = camp:FindFirstChild(Constants.CAMP_WALLS_FOLDER)
	for _, marker in if walls then walls:GetChildren() else {} do
		if not marker:IsA("Model") then
			continue
		end
		local slot = self:claimSlot(marker, WALL_TEMPLATE_KEY)
		if StructureRules.isDecorativeWall(slot.name) then
			table.insert(self.decorativeSlots, slot)
			continue
		end
		self:addStructure(slot.name, Enums.StructureKind.WALL, slot.model :: Model, shadowFolder, slot)
	end
	local posts = camp:FindFirstChild(Constants.CAMP_POSTS_FOLDER)
	for _, marker in if posts then posts:GetChildren() else {} do
		if marker:IsA("Model") then
			local slot = self:claimSlot(marker, Constants.POST_TEMPLATE_PREFIX)
			self:labelPost(slot)
			table.insert(self.postSlots, slot)
		end
	end
	local gate = camp:FindFirstChild(Constants.CAMP_GATE_MODEL)
	if gate and gate:IsA("Model") then
		local slot = self:claimSlot(gate, GATE_TEMPLATE_KEY)
		self:addStructure(GATE_ID, Enums.StructureKind.GATE, slot.model :: Model, shadowFolder, slot)
		self:bindGateDoor(slot.model)
	end
	-- the map's Refinery is a marker like the walls: its pivot and name
	-- stay, the tier's template from GameAssets stands there (2026-10-09)
	local refinery = camp:FindFirstChild(Constants.CAMP_REFINERY_MODEL)
	if refinery and refinery:IsA("Model") then
		local slot = self:claimSlot(refinery, REFINERY_TEMPLATE_KEY)
		self:addStructure(REFINERY_ID, Enums.StructureKind.REFINERY, slot.model :: Model, shadowFolder, slot)
	end

	self:bindWallsTable()

	SplendidReplicationManager:setGameMetadata(Attributes.IS_NIGHT, false)
	self:replicateAll()
	self:updateGate()
	self:firePostModelsFilled()
	self:fireBarriersChanged()
end

-- ready-sequence entry: everyone carries a Hammer from the start
function StructureManager:onPlayerReady(player: Player)
	ToolManager:grantTool(player, Enums.ToolKind.HAMMER)
end

function StructureManager:init()
	SplendidReplicationManager:setGameMetadata(Attributes.GATE_DOOR_TWEEN_SEC, StructuresData.GATE_DOOR_TWEEN_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.FORTIFICATION_TIER, STARTING_TIER)
	SplendidReplicationManager:setGameMetadata(Attributes.IS_NIGHT, false)
	SplendidReplicationManager:setGameMetadata(Attributes.REFINERY_UNDER_ATTACK, false)
	SplendidReplicationManager:setGameMetadata(Attributes.REPAIR_CHUNK_HP, StructuresData.REPAIR_CHUNK_HP_BY_TIER[STARTING_TIER])
	SplendidReplicationManager:setGameMetadata(Attributes.REPAIR_CHUNK_IRON, StructuresData.REPAIR_CHUNK_IRON_BY_TIER[STARTING_TIER])
	SplendidReplicationManager:setGameMetadata(Attributes.HAMMER_HIT_INTERVAL_SEC, StructuresData.HAMMER_HIT_INTERVAL_SEC)
	-- the crew is counted at dawn, and the next tier's price follows it
	RunCycleManager:subscribeDayStarted(
		function()
			self:replicateFortification()
		end
	)
	SplendidReplicationManager:setGameMetadata(Attributes.HAMMER_REACH_STUDS, StructuresData.HAMMER_REACH_STUDS)
	GameController:registerPlaceManager(self)
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self.lastSwingTimeByPlayer[player] = nil
		end
	)
end

function StructureManager.new(): StructureManager
	local self = setmetatable({}, StructureManager) :: StructureManager
	self.structuresById = {}
	self.postSlots = {}
	self.decorativeSlots = {}
	self.fortificationTier = STARTING_TIER
	self.fortificationPool = 0
	self.workbenchPrompt = nil
	self.isNight = false
	self.isGateOpen = false
	self.gateLeaves = {}
	self.lastSwingTimeByPlayer = {}
	self.connections = {}
	self.refineryDestroyedHandlers = {}
	self.postModelsFilledHandlers = {}
	self.barriersChangedHandlers = {}
	self.structureDamagedHandlers = {}
	self.structureRepairedHandlers = {}
	self.warnedTemplates = {}
	self.isRefineryUnderAttack = false
	return self
end

return StructureManager.new()
