--!strict

-- Camp structures on this client (GDD "Walls", "Gate", "Wall Repair"). Every
-- structure is a server shadow part tagged Tags.STRUCTURE carrying its HP.
-- Equipping the Hammer is Repair Mode, which works like Mining Mode: every
-- shadow gets an HP bar (the GameAssets/Gui StructureHp billboard), the
-- structure under the reticle is highlighted with the price of a swing under
-- its bar ("4 [Iron Bar icon] for 10 HP"), and a press, or each interval while
-- held, swings the Hammer and asks the server for one chunk of repair
-- (TryRepairStructure). All of it is local, so one player's Repair Mode never shows on
-- another's screen. Outside Repair Mode (decided 2026-09-23, M29) the
-- Refinery's bar is always up, so the crew always knows how the thing that
-- loses the run is holding up, and a wall or the gate shows its bar
-- whenever it is below full HP; Towers show theirs in Repair Mode only.
-- The gate's door leaves
-- are tweened here between the template's open and closed marker parts when
-- the server flips GateIsOpen; the server only decides whether they block.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PlacementRules = require("@game/ReplicatedStorage/Shared/PlacementRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local StructureRules = require("@game/ReplicatedStorage/Shared/StructureRules")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientHeldToolManager = require(script.Parent.ClientHeldToolManager)
local ClientHoldInput = require(script.Parent.ClientHoldInput)
local ClientMiningManager = require(script.Parent.ClientMiningManager)
local ClientPlacementManager = require(script.Parent.ClientPlacementManager)

local ClientStructureManager = {}
ClientStructureManager.__index = ClientStructureManager

-- what Repair Mode needs to know about a target, read the same way from a
-- structure shadow and a Tower shadow (Towers repair exactly like walls,
-- decided 2026-09-22)
type Repairable = {
	id: string,
	name: string,
	hp: number,
	maxHp: number,
	isDestroyed: boolean,
	isPlacement: boolean,
}

type Tracked = {
	billboard: BillboardGui?,
	connections: { RBXScriptConnection },
}

export type ClientStructureManager = typeof(setmetatable(
	{} :: {
		isRepairMode: boolean,
		trackedByShadow: { [BasePart]: Tracked },
		-- the structure under the reticle, within reach
		target: BasePart?,
		highlight: Highlight?,
		holdInput: ClientHoldInput.ClientHoldInput?,
		aimConnection: RBXScriptConnection?,
		hitIntervalSec: number,
		reachStuds: number,
		repairChunkHp: number,
		repairChunkIron: number,
		doorTweens: { Tween },
		-- each leaf's authored (closed) pose, read before it first moves. A
		-- strong table pruned by hand: weak keys lose live Instances at the
		-- next garbage collection, and an open leaf would be re-read as closed
		closedCFrameByLeaf: { [BasePart]: CFrame },
		hasWarnedTemplate: boolean,
	},
	ClientStructureManager
))

local RETICLE_BORROWER = "RepairMode"
local DEFAULT_DOOR_TWEEN_SEC = 0.6
local BILLBOARD_LIFT_STUDS = 4
local HP_FILL_TWEEN_SEC = 0.25
local DESTROYED_TEXT = "Destroyed"
local REBUILDING_FORMAT = "Rebuilding %d / %d"
local COST_GAIN_FORMAT = "for %d HP"
local FEEDBACK_NOT_ENOUGH_IRON = "Not enough Iron"
local DEFAULT_HIT_INTERVAL_SEC = 0.45
local DEFAULT_REACH_STUDS = 12
local DEFAULT_REPAIR_CHUNK_HP = 10
local DEFAULT_REPAIR_CHUNK_IRON = 4
-- repairs by other players are heard only nearby
local SOUND_RANGE_STUDS = 60

local NOTIFY_ALERT_SHAPE = {
	message = "string",
	displaySec = "positiveNumber",
}

local NOTIFY_STRUCTURE_REPAIRED_SHAPE = {
	id = "string",
	userId = "integer",
}
-- a Tower's bar floats this far above its body
local TOWER_BILLBOARD_LIFT_STUDS = 1.5
-- a structure's bar shown outside Repair Mode reads from anywhere in the
-- camp and out on the defenses, further than the template's distance, but
-- never from past the mine entrance (2026-10-01): a damaged wall's bar
-- was a compass out of the mine. Each bar's reach is the distance from
-- its structure to Camp.Mine.Entrance, capped here
local STRUCTURE_BILLBOARD_MAX_DISTANCE_STUDS = 300
-- and stacks above the Camp Level sign that already floats over the Refinery
-- the Refinery's bar floats this far above the model's top, the spot the
-- Camp Level billboard had until 2026-09-29
local TOWER_LEVEL_FORMAT = "%s %d"

-- a Tower or a Trap on the grid, as against a camp structure; only the
-- repairable ones are ever tracked here (see trackPlacementIfNeeded)
local function isPlacementShadow(shadow: BasePart): boolean
	return shadow:GetAttribute(Attributes.PLACEMENT_KIND) ~= nil
end

local function isRefineryShadow(shadow: BasePart): boolean
	return shadow:GetAttribute(Attributes.STRUCTURE_KIND) == Enums.StructureKind.REFINERY
end

-- the Refinery has its own template (the home icon beside a bigger name);
-- a place without it falls back to the plain one
function ClientStructureManager:findBillboardTemplate(isRefinery: boolean): BillboardGui?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local refineryTemplate = if guiFolder and isRefinery then guiFolder:FindFirstChild(Constants.STRUCTURE_HP_REFINERY_BILLBOARD) else nil
	if refineryTemplate and refineryTemplate:IsA("BillboardGui") then
		return refineryTemplate
	end
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.STRUCTURE_HP_BILLBOARD) else nil
	if template and template:IsA("BillboardGui") then
		return template
	end
	if not self.hasWarnedTemplate then
		self.hasWarnedTemplate = true
		warn(`ClientStructureManager: no {Constants.STRUCTURE_HP_BILLBOARD} BillboardGui under GameAssets.{Constants.GUI_TEMPLATES_FOLDER}; run scripts/studio/build_structure_hp_billboard.luau`)
	end
	return nil
end

function ClientStructureManager:readRepairable(shadow: BasePart): Repairable?
	if isPlacementShadow(shadow) then
		local id = shadow:GetAttribute(Attributes.PLACEMENT_ID)
		local hp = shadow:GetAttribute(Attributes.PLACEMENT_HP)
		local maxHp = shadow:GetAttribute(Attributes.PLACEMENT_MAX_HP)
		local typeKind = shadow:GetAttribute(Attributes.PLACEMENT_TYPE_KIND)
		local level = shadow:GetAttribute(Attributes.PLACEMENT_LEVEL)
		if typeof(id) ~= "string" or typeof(hp) ~= "number" or typeof(maxHp) ~= "number" or typeof(typeKind) ~= "number" then
			return nil
		end
		return {
			id = id,
			-- a Tower reads with its level; a Trap has none
			name = if shadow:GetAttribute(Attributes.PLACEMENT_KIND) == Enums.PlacementKind.TOWER
				then string.format(TOWER_LEVEL_FORMAT, PlacementRules.publicName(Enums.PlacementKind.TOWER, typeKind), if typeof(level) == "number" then level else 1)
				else PlacementRules.publicName(Enums.PlacementKind.TRAP, typeKind),
			hp = hp,
			maxHp = maxHp,
			isDestroyed = false,
			isPlacement = true,
		}
	end
	local id = shadow:GetAttribute(Attributes.STRUCTURE_ID)
	local hp = shadow:GetAttribute(Attributes.STRUCTURE_HP)
	local maxHp = shadow:GetAttribute(Attributes.STRUCTURE_MAX_HP)
	local kind = shadow:GetAttribute(Attributes.STRUCTURE_KIND)
	if typeof(id) ~= "string" or typeof(hp) ~= "number" or typeof(maxHp) ~= "number" then
		return nil
	end
	-- a numbered structure reads "Wall 3" over its bar, so an alert naming a
	-- wall can be matched to the one in front of you (2026-09-25)
	local name = if typeof(kind) == "number" then Enums.getPublicName(Enums.StructureKind, kind) or "" else ""
	local number = StructureRules.numberFromId(id)
	if number then
		name = `{name} {number}`
	end
	return {
		id = id,
		name = name,
		hp = hp,
		maxHp = maxHp,
		isDestroyed = shadow:GetAttribute(Attributes.STRUCTURE_IS_DESTROYED) == true,
		isPlacement = false,
	}
end

function ClientStructureManager:refreshBillboard(shadow: BasePart, billboard: BillboardGui, isInstant: boolean)
	local root = billboard:FindFirstChild(Constants.STRUCTURE_HP_ROOT_FRAME)
	-- recursive: the Refinery's template keeps the name inside its NameRow
	local nameLabel = if root then root:FindFirstChild(Constants.STRUCTURE_HP_NAME_LABEL, true) else nil
	local bar = if root then root:FindFirstChild(Constants.STRUCTURE_HP_BAR) else nil
	local fill = if bar then bar:FindFirstChild(Constants.STRUCTURE_HP_FILL) else nil
	local valueLabel = if bar then bar:FindFirstChild(Constants.STRUCTURE_HP_VALUE_LABEL) else nil
	local costRow = if root then root:FindFirstChild(Constants.STRUCTURE_HP_COST_ROW) else nil
	local amountLabel = if costRow then costRow:FindFirstChild(Constants.STRUCTURE_HP_COST_AMOUNT_LABEL) else nil
	local gainLabel = if costRow then costRow:FindFirstChild(Constants.STRUCTURE_HP_COST_GAIN_LABEL) else nil
	local repairable = self:readRepairable(shadow)
	if not repairable or repairable.maxHp <= 0 then
		return
	end
	local isDestroyed = repairable.isDestroyed
	local hp = repairable.hp
	local maxHp = repairable.maxHp
	local share = math.clamp(hp / maxHp, 0, 1)
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = UiStyle.formatTitle(repairable.name)
	end
	if valueLabel and valueLabel:IsA("TextLabel") then
		if hp <= 0 then
			valueLabel.Text = DESTROYED_TEXT
		elseif isDestroyed then
			valueLabel.Text = string.format(REBUILDING_FORMAT, math.ceil(hp), maxHp)
		else
			valueLabel.Text = `{math.ceil(hp)} / {maxHp}`
		end
	end
	if costRow and costRow:IsA("GuiObject") then
		-- the price of the next swing, only on the structure being looked at
		local gained, cost = StructureRules.repairChunk(maxHp, hp, self.repairChunkHp, self.repairChunkIron)
		costRow.Visible = shadow == self.target and gained > 0
		if amountLabel and amountLabel:IsA("TextLabel") then
			amountLabel.Text = tostring(cost)
		end
		if gainLabel and gainLabel:IsA("TextLabel") then
			gainLabel.Text = string.format(COST_GAIN_FORMAT, gained)
		end
	end
	if fill and fill:IsA("Frame") then
		local goal = {
			Size = UDim2.fromScale(share, 1),
			BackgroundColor3 = UiStyle.HP_EMPTY_COLOR:Lerp(UiStyle.HP_FULL_COLOR, share),
		}
		if isInstant then
			fill.Size = goal.Size
			fill.BackgroundColor3 = goal.BackgroundColor3
		else
			TweenService:Create(fill, TweenInfo.new(HP_FILL_TWEEN_SEC), goal):Play()
		end
	end
end

-- whether a shadow's HP bar shows: everything in Repair Mode; outside it
-- the Refinery always, and a wall or the gate only while damaged
function ClientStructureManager:isBarShown(shadow: BasePart): boolean
	if self.isRepairMode then
		return true
	end
	if isPlacementShadow(shadow) then
		return false
	end
	if isRefineryShadow(shadow) then
		return true
	end
	local repairable = self:readRepairable(shadow)
	return repairable ~= nil and repairable.hp < repairable.maxHp
end

-- how far away a structure's bar still reads: up to the mine entrance,
-- so a player inside the mine never sees it, and never past the cap
function ClientStructureManager:billboardMaxDistance(shadow: BasePart): number
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	local mine = if camp then camp:FindFirstChild(Constants.CAMP_MINE_FOLDER) else nil
	local entrance = if mine then mine:FindFirstChild(Constants.MINE_ENTRANCE_PART) else nil
	if not entrance or not entrance:IsA("BasePart") then
		return STRUCTURE_BILLBOARD_MAX_DISTANCE_STUDS
	end
	return math.min(STRUCTURE_BILLBOARD_MAX_DISTANCE_STUDS, (shadow.Position - entrance.Position).Magnitude)
end

-- how far above its shadow the Refinery's bar sits: over the model's top
-- by the lift the Camp Level billboard used, so it reads from the whole
-- camp; the shadow's own height when the model cannot be found
function ClientStructureManager:refineryLift(shadow: BasePart): number
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	local refinery = if camp then camp:FindFirstChild(Constants.CAMP_REFINERY_MODEL) else nil
	if not refinery or not refinery:IsA("Model") then
		return shadow.Size.Y / 2 + Constants.REFINERY_HP_BILLBOARD_LIFT_STUDS
	end
	local boundsCFrame, boundsSize = refinery:GetBoundingBox()
	return boundsCFrame.Position.Y + boundsSize.Y / 2 + Constants.REFINERY_HP_BILLBOARD_LIFT_STUDS - shadow.Position.Y
end

-- a bar draws through the world only at night, when the crew is defending;
-- by day it is hidden behind rock like anything else, so a miner cannot
-- steer by the Refinery's bar to find the way out (2026-09-30)
function ClientStructureManager:isNight(): boolean
	return ClientDataManager:getGameMetadata(Attributes.IS_NIGHT) == true
end

-- a wall's or the gate's bar always draws on top (2026-09-30): it hangs
-- at chest height inside the thick wall, and only the Refinery's bar
-- could lead a miner out of the mine, so that one keeps the night rule
function ClientStructureManager:isBarOnTop(shadow: BasePart): boolean
	if isPlacementShadow(shadow) or isRefineryShadow(shadow) then
		return self:isNight()
	end
	return true
end

-- shows or hides a shadow's HP bar by isBarShown; a Tower's everyday info
-- billboard steps aside for the bar so the two never stack
function ClientStructureManager:applyBarVisibility(shadow: BasePart, tracked: Tracked)
	local isPlacement = isPlacementShadow(shadow)
	local isRefinery = isRefineryShadow(shadow)
	if not self:isBarShown(shadow) then
		if tracked.billboard then
			tracked.billboard:Destroy()
			tracked.billboard = nil
		end
		if isPlacement then
			ClientPlacementManager:setInfoVisible(shadow, true)
		end
		return
	end
	local billboard = tracked.billboard
	if not billboard then
		local template = self:findBillboardTemplate(isRefinery)
		if not template then
			return
		end
		billboard = template:Clone()
		local lift = if isPlacement then ClientPlacementManager:getBodyHeight(shadow) + TOWER_BILLBOARD_LIFT_STUDS - shadow.Size.Y / 2 elseif isRefinery then self:refineryLift(shadow) else BILLBOARD_LIFT_STUDS
		if isPlacement then
			ClientPlacementManager:setInfoVisible(shadow, false)
		end
		billboard.StudsOffsetWorldSpace = Vector3.new(0, lift, 0)
		if not isPlacement then
			billboard.MaxDistance = self:billboardMaxDistance(shadow)
		end
		billboard.AlwaysOnTop = self:isBarOnTop(shadow)
		billboard.Adornee = shadow
		billboard.Parent = shadow
		tracked.billboard = billboard
		self:refreshBillboard(shadow, billboard, true)
		return
	end
	billboard.AlwaysOnTop = self:isBarOnTop(shadow)
	self:refreshBillboard(shadow, billboard, false)
end

-- "Wall3", "Gate", "Refinery", or a Tower's body ("Placement4"): which
-- repairable a hit part belongs to, and the model to highlight
function ClientStructureManager:resolveStructure(part: Instance): (BasePart?, Model?)
	local bodies = workspace:FindFirstChild(Constants.PLACEMENT_BODIES_FOLDER)
	if bodies and part:IsDescendantOf(bodies) then
		local current: Instance? = part
		while current and current.Parent ~= bodies do
			current = current.Parent
		end
		local shadow = if current and current:IsA("Model") then ClientPlacementManager:findShadowById(current.Name) else nil
		if shadow and self.trackedByShadow[shadow] and current and current:IsA("Model") then
			return shadow, current
		end
		return nil, nil
	end
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	local walls = if camp then camp:FindFirstChild(Constants.CAMP_WALLS_FOLDER) else nil
	local current: Instance? = part
	while current and current ~= camp do
		local parent = current.Parent
		if current:IsA("Model") and (parent == walls or parent == camp) then
			for shadow in self.trackedByShadow do
				if shadow:GetAttribute(Attributes.STRUCTURE_ID) == current.Name then
					return shadow, current
				end
			end
			return nil, nil
		end
		current = parent
	end
	return nil, nil
end

-- the model standing (or lying) in a wall's or the gate's slot, by its id
function ClientStructureManager:findStructureModel(shadow: BasePart): Model?
	local id = shadow:GetAttribute(Attributes.STRUCTURE_ID)
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	if typeof(id) ~= "string" or not camp then
		return nil
	end
	local walls = camp:FindFirstChild(Constants.CAMP_WALLS_FOLDER)
	local model = (if walls then walls:FindFirstChild(id) else nil) or camp:FindFirstChild(id)
	return if model and model:IsA("Model") then model else nil
end

function ClientStructureManager:setTarget(shadow: BasePart?, model: Model?)
	local highlight = self.highlight
	if highlight then
		-- a rebuilt or upgraded structure is a new model under the same name
		highlight.Adornee = model
		highlight.Enabled = model ~= nil
	end
	local previous = self.target
	if previous == shadow then
		return
	end
	self.target = shadow
	for _, changed in { previous, shadow } do
		local tracked = if changed then self.trackedByShadow[changed] else nil
		if changed and tracked and tracked.billboard then
			self:refreshBillboard(changed, tracked.billboard, true)
		end
	end
end

-- what the camera centre is looking at, within reach, among the structures
function ClientStructureManager:aim()
	local camera = workspace.CurrentCamera
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	if not camera or not camp then
		self:setTarget(nil, nil)
		return
	end
	local included: { Instance } = {}
	for _, name in { Constants.CAMP_WALLS_FOLDER, Constants.CAMP_GATE_MODEL, Constants.CAMP_REFINERY_MODEL } do
		local child = camp:FindFirstChild(name)
		if child then
			table.insert(included, child)
		end
	end
	-- the bodies of Towers and repairable Traps too (their shadows are
	-- tracked here); any other Trap stays out of the ray
	local bodies = workspace:FindFirstChild(Constants.PLACEMENT_BODIES_FOLDER)
	if bodies then
		for _, body in bodies:GetChildren() do
			local shadow = if body:IsA("Model") then ClientPlacementManager:findShadowById(body.Name) else nil
			if shadow and self.trackedByShadow[shadow] then
				table.insert(included, body)
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = included
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector
	local result = workspace:Raycast(origin, direction * self.reachStuds, params)
	local targetShadow: BasePart? = nil
	local targetModel: Model? = nil
	local targetDistance = math.huge
	if result then
		targetShadow, targetModel = self:resolveStructure(result.Instance)
		targetDistance = result.Distance
	end
	-- a wall or gate that is rubble is aimed at where it stood, not at the
	-- pile on the ground (2026-09-30): the nearer of the two wins
	for shadow in self.trackedByShadow do
		if shadow:GetAttribute(Attributes.STRUCTURE_IS_DESTROYED) ~= true then
			continue
		end
		local boundsCFrame = shadow:GetAttribute(Attributes.STRUCTURE_BOUNDS_CFRAME)
		local boundsSize = shadow:GetAttribute(Attributes.STRUCTURE_BOUNDS_SIZE)
		if typeof(boundsCFrame) ~= "CFrame" or typeof(boundsSize) ~= "Vector3" then
			continue
		end
		local distance = StructureRules.rayBoxDistance(origin, direction, boundsCFrame, boundsSize, self.reachStuds)
		if distance and distance < targetDistance then
			targetDistance = distance
			targetShadow = shadow
			targetModel = self:findStructureModel(shadow)
		end
	end
	self:setTarget(targetShadow, targetModel)
end

-- one swing: a request, never a result. False (nothing to repair, or no
-- Iron) leaves the hold free to try again
function ClientStructureManager:swing(isFreshPress: boolean): boolean
	local target = self.target
	if not target then
		return false
	end
	local repairable = self:readRepairable(target)
	if not repairable then
		return false
	end
	local gained, cost = StructureRules.repairChunk(repairable.maxHp, repairable.hp, self.repairChunkHp, self.repairChunkIron)
	if gained <= 0 then
		return false
	end
	local iron = ClientDataManager:getCurrentPlayerAttribute(Attributes.BALANCE_IRON_BARS)
	if typeof(iron) ~= "number" or iron < cost then
		-- said once per press, not once per interval of a hold
		if isFreshPress then
			ClientPlayerFeedbackManager:giveLocal(FEEDBACK_NOT_ENOUGH_IRON)
		end
		return false
	end
	ClientHeldToolManager:playSwing()
	ClientNetManager:fireServer(if repairable.isPlacement then NetEventNames.TRY_REPAIR_TOWER else NetEventNames.TRY_REPAIR_STRUCTURE, { id = repairable.id })
	return true
end

function ClientStructureManager:beginHold()
	if self.holdInput then
		self.holdInput:beginHold()
	end
end

function ClientStructureManager:endHold()
	if self.holdInput then
		self.holdInput:endHold()
	end
end

-- the hammer blow, for everyone close enough to hear it
function ClientStructureManager:onStructureRepaired(payload: any)
	local isValid = Validate.isTableShape(payload, NOTIFY_STRUCTURE_REPAIRED_SHAPE)
	if not isValid then
		warn("ClientStructureManager: malformed NotifyStructureRepaired")
		return
	end
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	for shadow in self.trackedByShadow do
		local repairable = self:readRepairable(shadow)
		if repairable and repairable.id == payload.id then
			if (root.Position - shadow.Position).Magnitude <= SOUND_RANGE_STUDS then
				ClientSoundManager:playSfx(SoundNames.Sfx.HAMMER_HIT)
			end
			return
		end
	end
end

function ClientStructureManager:readTuning()
	local function read(key: string, default: number): number
		local value = ClientDataManager:getGameMetadata(key)
		return if typeof(value) == "number" then value else default
	end
	self.hitIntervalSec = read(Attributes.HAMMER_HIT_INTERVAL_SEC, DEFAULT_HIT_INTERVAL_SEC)
	self.reachStuds = read(Attributes.HAMMER_REACH_STUDS, DEFAULT_REACH_STUDS)
	self.repairChunkHp = read(Attributes.REPAIR_CHUNK_HP, DEFAULT_REPAIR_CHUNK_HP)
	self.repairChunkIron = read(Attributes.REPAIR_CHUNK_IRON, DEFAULT_REPAIR_CHUNK_IRON)
end

function ClientStructureManager:findGateLeaves(): { { leaf: BasePart, open: CFrame, closed: CFrame } }
	local found = {}
	-- leaves of a gate model that was swapped out
	for leaf in self.closedCFrameByLeaf do
		if not leaf:IsDescendantOf(workspace) then
			self.closedCFrameByLeaf[leaf] = nil
		end
	end
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	local gate = if camp then camp:FindFirstChild(Constants.CAMP_GATE_MODEL) else nil
	local door = if gate then gate:FindFirstChild(Constants.GATE_DOOR_MODEL) else nil
	if not door then
		return found
	end
	for _, leafName in { Constants.GATE_DOOR_LEFT_PART, Constants.GATE_DOOR_RIGHT_PART } do
		local leaf = door:FindFirstChild(leafName)
		local open = door:FindFirstChild(leafName .. Constants.GATE_DOOR_OPEN_SUFFIX)
		local closed = door:FindFirstChild(leafName .. Constants.GATE_DOOR_CLOSED_SUFFIX)
		if leaf and leaf:IsA("BasePart") and open and open:IsA("BasePart") then
			-- the Closed marker is optional: the server never moves a leaf, so
			-- the pose it first arrives in is its authored, closed pose
			local closedCFrame: CFrame = self.closedCFrameByLeaf[leaf] or if closed and closed:IsA("BasePart") then closed.CFrame else leaf.CFrame
			self.closedCFrameByLeaf[leaf] = closedCFrame
			table.insert(found, {
				leaf = leaf,
				open = open.CFrame,
				closed = closedCFrame,
			})
		end
	end
	return found
end

-- the leaves are looked up on every change because an upgrade or a rebuild
-- swaps the whole gate model under the same name
function ClientStructureManager:applyGateOpen(isOpen: boolean, isInstant: boolean)
	for _, tween in self.doorTweens do
		tween:Cancel()
	end
	self.doorTweens = {}
	local seconds = ClientDataManager:getGameMetadata(Attributes.GATE_DOOR_TWEEN_SEC)
	local tweenInfo = TweenInfo.new(if typeof(seconds) == "number" then seconds else DEFAULT_DOOR_TWEEN_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	for _, entry in self:findGateLeaves() do
		local goal = if isOpen then entry.open else entry.closed
		if isInstant then
			entry.leaf.CFrame = goal
			continue
		end
		local tween = TweenService:Create(entry.leaf, tweenInfo, { CFrame = goal })
		table.insert(self.doorTweens, tween)
		tween:Play()
	end
end

function ClientStructureManager:track(shadow: Instance)
	if not shadow:IsA("BasePart") or self.trackedByShadow[shadow] then
		return
	end
	local isPlacement = isPlacementShadow(shadow)
	local tracked: Tracked = {
		billboard = nil,
		connections = {},
	}
	self.trackedByShadow[shadow] = tracked
	local watched = if isPlacement then { Attributes.PLACEMENT_HP, Attributes.PLACEMENT_MAX_HP, Attributes.PLACEMENT_LEVEL } else { Attributes.STRUCTURE_HP, Attributes.STRUCTURE_MAX_HP, Attributes.STRUCTURE_IS_DESTROYED }
	for _, attribute in watched do
		table.insert(
			tracked.connections,
			shadow:GetAttributeChangedSignal(attribute):Connect(
				function()
					self:applyBarVisibility(shadow, tracked)
				end
			)
		)
	end
	if shadow:GetAttribute(Attributes.STRUCTURE_KIND) == Enums.StructureKind.GATE then
		table.insert(
			tracked.connections,
			shadow:GetAttributeChangedSignal(Attributes.GATE_IS_OPEN):Connect(
				function()
					self:applyGateOpen(shadow:GetAttribute(Attributes.GATE_IS_OPEN) == true, false)
				end
			)
		)
		-- an upgrade or a rebuild swaps the gate model while GateIsOpen may
		-- not change; the new leaves arrive closed and are put in place
		local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
		if camp then
			table.insert(
				tracked.connections,
				camp.ChildAdded:Connect(
					function(child: Instance)
						if child.Name == Constants.CAMP_GATE_MODEL then
							task.defer(
								function()
									self:applyGateOpen(shadow:GetAttribute(Attributes.GATE_IS_OPEN) == true, true)
								end
							)
						end
					end
				)
			)
		end
		-- a gate met already open (a late join, a streamed-in camp) starts in place
		self:applyGateOpen(shadow:GetAttribute(Attributes.GATE_IS_OPEN) == true, true)
	end
	self:applyBarVisibility(shadow, tracked)
end

function ClientStructureManager:untrack(shadow: Instance)
	local tracked = self.trackedByShadow[shadow :: BasePart]
	if not tracked then
		return
	end
	for _, connection in tracked.connections do
		connection:Disconnect()
	end
	if tracked.billboard then
		tracked.billboard:Destroy()
	end
	self.trackedByShadow[shadow :: BasePart] = nil
	if self.target == shadow then
		self:setTarget(nil, nil)
	end
end

function ClientStructureManager:setRepairMode(isRepairMode: boolean)
	if self.isRepairMode == isRepairMode then
		return
	end
	self.isRepairMode = isRepairMode
	ClientMiningManager:setReticleBorrowed(RETICLE_BORROWER, isRepairMode)
	if isRepairMode then
		self.aimConnection = RunService.RenderStepped:Connect(
			function()
				self:aim()
			end
		)
	else
		if self.aimConnection then
			self.aimConnection:Disconnect()
			self.aimConnection = nil
		end
		if self.holdInput then
			self.holdInput:cancel()
		end
		self:setTarget(nil, nil)
	end
	for shadow, tracked in self.trackedByShadow do
		self:applyBarVisibility(shadow, tracked)
	end
end

function ClientStructureManager:getIsRepairMode(): boolean
	return self.isRepairMode
end


-- the red alert everyone gets when a wall falls, with its sound
function ClientStructureManager:onWallDestroyed(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_ALERT_SHAPE) then
		warn("ClientStructureManager: malformed NotifyWallDestroyed")
		return
	end
	ClientPlayerFeedbackManager:alertLocal(payload.message, payload.displaySec)
	ClientSoundManager:playSfx(SoundNames.Sfx.WALL_DESTROYED)
end

-- the red alert as the Refinery comes under attack; the siren follows the
-- GameMetadata flag, which also ends it once the last monster backs off
function ClientStructureManager:onRefineryAttacked(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_ALERT_SHAPE) then
		warn("ClientStructureManager: malformed NotifyRefineryAttacked")
		return
	end
	ClientPlayerFeedbackManager:alertLocal(payload.message, payload.displaySec)
end

function ClientStructureManager:refreshRefinerySiren()
	local isUnderAttack = ClientDataManager:getGameMetadata(Attributes.REFINERY_UNDER_ATTACK) == true
	if isUnderAttack then
		ClientSoundManager:setSfxLoopLevel(SoundNames.Sfx.REFINERY_UNDER_ATTACK, 1)
	else
		ClientSoundManager:stopSfxLoop(SoundNames.Sfx.REFINERY_UNDER_ATTACK)
	end
end

function ClientStructureManager:init()
	self:readTuning()
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_WALL_DESTROYED,
		function(payload: any)
			self:onWallDestroyed(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_REFINERY_ATTACKED,
		function(payload: any)
			self:onRefineryAttacked(payload)
		end
	)
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.REFINERY_UNDER_ATTACK,
		function()
			self:refreshRefinerySiren()
		end
	)
	self:refreshRefinerySiren()
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.IS_NIGHT,
		function()
			for shadow, tracked in self.trackedByShadow do
				self:applyBarVisibility(shadow, tracked)
			end
		end
	)
	for _, key in { Attributes.HAMMER_HIT_INTERVAL_SEC, Attributes.HAMMER_REACH_STUDS, Attributes.REPAIR_CHUNK_HP, Attributes.REPAIR_CHUNK_IRON } do
		ClientDataManager:subscribeGameMetadataAttribute(
			key,
			function()
				self:readTuning()
			end
		)
	end

	-- the same look as the mining target, so Repair Mode reads as the same verb
	local highlight = Instance.new("Highlight")
	highlight.Name = "RepairTarget"
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.85
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = workspace
	self.highlight = highlight

	local holdInput = ClientHoldInput.new({
		isEnabled = function(): boolean
			return self.isRepairMode
		end,
		getIntervalSec = function(): number
			return self.hitIntervalSec
		end,
		swing = function(isFreshPress: boolean): boolean
			return self:swing(isFreshPress)
		end,
	})
	holdInput:connect()
	self.holdInput = holdInput

	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_STRUCTURE_REPAIRED,
		function(payload: any)
			self:onStructureRepaired(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_TOWER_REPAIRED,
		function(payload: any)
			self:onStructureRepaired(payload)
		end
	)
	-- Towers are repaired like walls; only a Tower shadow is tracked, a Trap
	-- shadow is never a repair target
	local function trackPlacementIfNeeded(shadow: Instance)
		if not shadow:IsA("BasePart") then
			return
		end
		local catalog = ClientPlacementManager:getCatalog()
		local placementKind = shadow:GetAttribute(Attributes.PLACEMENT_KIND)
		local typeKind = shadow:GetAttribute(Attributes.PLACEMENT_TYPE_KIND)
		if catalog and typeof(placementKind) == "number" and typeof(typeKind) == "number" and PlacementRules.isRepairable(catalog, placementKind, typeKind) then
			self:track(shadow)
		end
	end
	for _, shadow in CollectionService:GetTagged(Tags.PLACEMENT) do
		trackPlacementIfNeeded(shadow)
	end
	CollectionService:GetInstanceAddedSignal(Tags.PLACEMENT):Connect(trackPlacementIfNeeded)
	CollectionService:GetInstanceRemovedSignal(Tags.PLACEMENT):Connect(
		function(shadow: Instance)
			self:untrack(shadow)
		end
	)

	for _, shadow in CollectionService:GetTagged(Tags.STRUCTURE) do
		self:track(shadow)
	end
	CollectionService:GetInstanceAddedSignal(Tags.STRUCTURE):Connect(
		function(shadow: Instance)
			self:track(shadow)
		end
	)
	CollectionService:GetInstanceRemovedSignal(Tags.STRUCTURE):Connect(
		function(shadow: Instance)
			self:untrack(shadow)
		end
	)
	local function applyEquipped(value: any)
		self:setRepairMode(value == Enums.ToolKind.HAMMER)
	end
	applyEquipped(ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL))
	ClientDataManager:subscribeCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL, applyEquipped)
end

function ClientStructureManager.new(): ClientStructureManager
	local self = setmetatable({}, ClientStructureManager) :: ClientStructureManager
	self.isRepairMode = false
	self.trackedByShadow = {}
	self.target = nil
	self.highlight = nil
	self.holdInput = nil
	self.aimConnection = nil
	self.hitIntervalSec = DEFAULT_HIT_INTERVAL_SEC
	self.reachStuds = DEFAULT_REACH_STUDS
	self.repairChunkHp = DEFAULT_REPAIR_CHUNK_HP
	self.repairChunkIron = DEFAULT_REPAIR_CHUNK_IRON
	self.doorTweens = {}
	self.closedCFrameByLeaf = {}
	self.hasWarnedTemplate = false
	return self
end

return ClientStructureManager.new()
