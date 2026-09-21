--!strict

-- Placed Towers and Traps on this client (GDD "Building Towers", "Selling
-- Traps"), M26. Every placement is a server shadow part tagged
-- Tags.PLACEMENT at the placement's pose, carrying what it is, whose it
-- is, its level, and its HP. This manager dresses each shadow locally (the
-- shadow system): the GameAssets/Towers or GameAssets/Traps model cloned
-- onto it in the client-only PlacementBodies folder, solid so a player
-- cannot walk through it, the PlacementInfo billboard above it (name, HP
-- bar, owner's display name), and the shadow's prompt enabled only when
-- the placement is the local player's. The sounds for a build and a sale
-- arrive as notifies. Nothing here decides anything.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PlacementRules = require("@game/ReplicatedStorage/Shared/PlacementRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientPlacementManager = {}
ClientPlacementManager.__index = ClientPlacementManager

export type Tracked = {
	shadow: BasePart,
	body: Model?,
	billboard: BillboardGui?,
	prompt: ProximityPrompt?,
	connections: { RBXScriptConnection },
}

export type ClientPlacementManager = typeof(setmetatable(
	{} :: {
		trackedByShadow: { [BasePart]: Tracked },
		bodiesFolder: Folder?,
		warnedTemplates: { [string]: boolean },
		hasWarnedBillboard: boolean,
		changedHandlers: { () -> () },
	},
	ClientPlacementManager
))

local NOTIFY_PLACEMENT_BUILT_SHAPE = {
	id = "string",
}
local NOTIFY_PLACEMENT_SOLD_SHAPE = {
	id = "string",
	value = "nonnegativeInteger",
}

local HP_FILL_TWEEN_SEC = 0.25
local HP_FULL_COLOR = Color3.fromRGB(90, 200, 110)
local HP_EMPTY_COLOR = Color3.fromRGB(220, 70, 60)
-- the billboard floats this far above the body's top
local BILLBOARD_LIFT_STUDS = 1.5
-- a placeholder body when the template is missing: a box of the footprint
local PLACEHOLDER_HEIGHT_STUDS = 4

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

function ClientPlacementManager:getBodiesFolder(): Folder
	local folder = self.bodiesFolder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = Constants.PLACEMENT_BODIES_FOLDER
	created.Parent = workspace
	self.bodiesFolder = created
	return created
end

-- the build bar and the preview ask for the set of placements to mark
-- cells taken; they are told whenever it changes
function ClientPlacementManager:subscribeChanged(handler: () -> ())
	table.insert(self.changedHandlers, handler)
end

function ClientPlacementManager:fireChanged()
	for _, handler in self.changedHandlers do
		handler()
	end
end

function ClientPlacementManager:getTrackedShadows(): { BasePart }
	local shadows = {}
	for shadow in self.trackedByShadow do
		table.insert(shadows, shadow)
	end
	return shadows
end

function ClientPlacementManager:findShadowById(id: string): BasePart?
	for shadow in self.trackedByShadow do
		if shadow:GetAttribute(Attributes.PLACEMENT_ID) == id then
			return shadow
		end
	end
	return nil
end

function ClientPlacementManager:findTemplate(placementKind: number, typeKind: number): Model?
	local folderName = PlacementRules.templateFolderFor(placementKind)
	local templateName = PlacementRules.templateNameFor(placementKind, typeKind)
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local folder = if gameAssets then gameAssets:FindFirstChild(folderName) else nil
	local template = if folder then folder:FindFirstChild(templateName) else nil
	if template and template:IsA("Model") then
		return template
	end
	local key = `{folderName}.{templateName}`
	if not self.warnedTemplates[key] then
		self.warnedTemplates[key] = true
		warn(`ClientPlacementManager: no Model named {templateName} under GameAssets.{folderName}; run scripts/studio/build_tower_templates.luau or build_trap_templates.luau`)
	end
	return nil
end

-- a model for the preview and the body alike: the template at a pose,
-- anchored, or a plain box the size of the shadow when the template is missing
function ClientPlacementManager:buildModel(placementKind: number, typeKind: number, shadowSize: Vector3): Model
	local template = self:findTemplate(placementKind, typeKind)
	local model: Model
	if template then
		model = template:Clone()
	else
		model = Instance.new("Model")
		local box = Instance.new("Part")
		box.Name = "Placeholder"
		box.Size = Vector3.new(shadowSize.X, PLACEHOLDER_HEIGHT_STUDS, shadowSize.Z)
		box.Color = if placementKind == Enums.PlacementKind.TOWER then Color3.fromRGB(120, 130, 150) else Color3.fromRGB(150, 110, 80)
		box.Parent = model
		model.PrimaryPart = box
		model.WorldPivot = box.CFrame * CFrame.new(0, -PLACEHOLDER_HEIGHT_STUDS / 2, 0)
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	return model
end

-- the shadow's centre is half its height above the top face it stands on
function ClientPlacementManager:basePose(shadow: BasePart): CFrame
	return shadow.CFrame * CFrame.new(0, -shadow.Size.Y / 2, 0)
end

function ClientPlacementManager:findBillboardTemplate(): BillboardGui?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.PLACEMENT_INFO_BILLBOARD) else nil
	if template and template:IsA("BillboardGui") then
		return template
	end
	if not self.hasWarnedBillboard then
		self.hasWarnedBillboard = true
		warn(`ClientPlacementManager: no {Constants.PLACEMENT_INFO_BILLBOARD} BillboardGui under GameAssets.{Constants.GUI_TEMPLATES_FOLDER}; run scripts/studio/build_placement_billboard.luau`)
	end
	return nil
end

function ClientPlacementManager:refreshBillboard(tracked: Tracked, isInstant: boolean)
	local billboard = tracked.billboard
	if not billboard then
		return
	end
	local shadow = tracked.shadow
	local root = billboard:FindFirstChild(Constants.PLACEMENT_INFO_ROOT_FRAME)
	local nameLabel = if root then root:FindFirstChild(Constants.PLACEMENT_INFO_NAME_LABEL) else nil
	local bar = if root then root:FindFirstChild(Constants.PLACEMENT_INFO_BAR) else nil
	local fill = if bar then bar:FindFirstChild(Constants.PLACEMENT_INFO_FILL) else nil
	local ownerLabel = if root then root:FindFirstChild(Constants.PLACEMENT_INFO_OWNER_LABEL) else nil
	local placementKind = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_KIND), 0)
	local typeKind = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_TYPE_KIND), 0)
	local level = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_LEVEL), 1)
	local hp = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_HP), 0)
	local maxHp = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_MAX_HP), 1)
	if nameLabel and nameLabel:IsA("TextLabel") then
		local name = PlacementRules.publicName(placementKind, typeKind)
		if placementKind == Enums.PlacementKind.TOWER then
			name = `{name} {level}`
		end
		nameLabel.Text = UiStyle.formatTitle(name)
	end
	if ownerLabel and ownerLabel:IsA("TextLabel") then
		local ownerUserId = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_OWNER_USER_ID), PlacementRules.NOBODY)
		local publicData = ClientDataManager:getPlayerPublicData(ownerUserId)
		ownerLabel.Text = if publicData then publicData.displayName else ""
	end
	if fill and fill:IsA("Frame") then
		local share = math.clamp(hp / math.max(maxHp, 1), 0, 1)
		local goal = {
			Size = UDim2.fromScale(share, 1),
			BackgroundColor3 = HP_EMPTY_COLOR:Lerp(HP_FULL_COLOR, share),
		}
		if isInstant then
			fill.Size = goal.Size
			fill.BackgroundColor3 = goal.BackgroundColor3
		else
			TweenService:Create(fill, TweenInfo.new(HP_FILL_TWEEN_SEC), goal):Play()
		end
	end
end

-- the prompt is the server's; only whether this viewer sees it is decided here
function ClientPlacementManager:refreshPrompt(tracked: Tracked)
	local prompt = tracked.prompt
	if not prompt then
		return
	end
	local ownerUserId = readNumber(tracked.shadow:GetAttribute(Attributes.PLACEMENT_OWNER_USER_ID), PlacementRules.NOBODY)
	prompt.Enabled = ownerUserId == Players.LocalPlayer.UserId
end

function ClientPlacementManager:dress(tracked: Tracked)
	local shadow = tracked.shadow
	local placementKind = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_KIND), 0)
	local typeKind = readNumber(shadow:GetAttribute(Attributes.PLACEMENT_TYPE_KIND), 0)
	if tracked.body then
		tracked.body:Destroy()
	end
	local body = self:buildModel(placementKind, typeKind, shadow.Size)
	body.Name = shadow.Name
	body:PivotTo(self:basePose(shadow))
	body.Parent = self:getBodiesFolder()
	tracked.body = body

	if not tracked.billboard then
		local template = self:findBillboardTemplate()
		if template then
			local billboard = template:Clone()
			local _, size = body:GetBoundingBox()
			billboard.Adornee = shadow
			billboard.StudsOffsetWorldSpace = Vector3.new(0, size.Y + BILLBOARD_LIFT_STUDS - shadow.Size.Y / 2, 0)
			billboard.Parent = shadow
			tracked.billboard = billboard
		end
	end
	self:refreshBillboard(tracked, true)
	self:refreshPrompt(tracked)
end

function ClientPlacementManager:track(shadow: Instance)
	if not shadow:IsA("BasePart") or self.trackedByShadow[shadow] then
		return
	end
	local tracked: Tracked = {
		shadow = shadow,
		body = nil,
		billboard = nil,
		prompt = shadow:FindFirstChildWhichIsA("ProximityPrompt"),
		connections = {},
	}
	self.trackedByShadow[shadow] = tracked
	if not tracked.prompt then
		table.insert(
			tracked.connections,
			shadow.ChildAdded:Connect(
				function(child: Instance)
					if child:IsA("ProximityPrompt") and not tracked.prompt then
						tracked.prompt = child
						self:refreshPrompt(tracked)
					end
				end
			)
		)
	end
	for _, attribute in { Attributes.PLACEMENT_HP, Attributes.PLACEMENT_MAX_HP, Attributes.PLACEMENT_LEVEL } do
		table.insert(
			tracked.connections,
			shadow:GetAttributeChangedSignal(attribute):Connect(
				function()
					self:refreshBillboard(tracked, false)
				end
			)
		)
	end
	table.insert(
		tracked.connections,
		shadow:GetAttributeChangedSignal(Attributes.PLACEMENT_OWNER_USER_ID):Connect(
			function()
				self:refreshBillboard(tracked, true)
				self:refreshPrompt(tracked)
			end
		)
	)
	self:dress(tracked)
	self:fireChanged()
end

function ClientPlacementManager:untrack(shadow: Instance)
	local tracked = self.trackedByShadow[shadow :: BasePart]
	if not tracked then
		return
	end
	for _, connection in tracked.connections do
		connection:Disconnect()
	end
	if tracked.body then
		tracked.body:Destroy()
	end
	if tracked.billboard then
		tracked.billboard:Destroy()
	end
	self.trackedByShadow[shadow :: BasePart] = nil
	self:fireChanged()
end

function ClientPlacementManager:onBuilt(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_PLACEMENT_BUILT_SHAPE) then
		warn("ClientPlacementManager: malformed NotifyPlacementBuilt")
		return
	end
	ClientSoundManager:playSfx(SoundNames.Sfx.PLACEMENT_BUILD)
end

function ClientPlacementManager:onSold(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_PLACEMENT_SOLD_SHAPE) then
		warn("ClientPlacementManager: malformed NotifyPlacementSold")
		return
	end
	ClientSoundManager:playSfx(SoundNames.Sfx.PLACEMENT_SELL)
end

function ClientPlacementManager:init()
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_PLACEMENT_BUILT,
		function(payload: any)
			self:onBuilt(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_PLACEMENT_SOLD,
		function(payload: any)
			self:onSold(payload)
		end
	)
	for _, shadow in CollectionService:GetTagged(Tags.PLACEMENT) do
		self:track(shadow)
	end
	CollectionService:GetInstanceAddedSignal(Tags.PLACEMENT):Connect(
		function(shadow: Instance)
			self:track(shadow)
		end
	)
	CollectionService:GetInstanceRemovedSignal(Tags.PLACEMENT):Connect(
		function(shadow: Instance)
			self:untrack(shadow)
		end
	)
end

function ClientPlacementManager.new(): ClientPlacementManager
	local self = setmetatable({}, ClientPlacementManager) :: ClientPlacementManager
	self.trackedByShadow = {}
	self.bodiesFolder = nil
	self.warnedTemplates = {}
	self.hasWarnedBillboard = false
	self.changedHandlers = {}
	return self
end

return ClientPlacementManager.new()
