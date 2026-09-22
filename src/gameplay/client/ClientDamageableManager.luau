--!strict

-- Damageable targets on this client (M24). Each is a server shadow part
-- tagged Tags.DAMAGEABLE carrying its id, name, hit box size, and HP
-- (DamageableManager); everything visible is built here: a placeholder body
-- the size of the hit box and an HP bar, the same GameAssets/Gui StructureHp
-- billboard the structures use, shown always since a target only exists to
-- be shot. The body flashes when a shot lands, turns blue while slowed
-- (bluer the slower, white when stunned), and orange while burning; a
-- flying target's body simply sits where its shadow is. Only the dev-tool
-- dummies exist until enemies take this over at M29.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")

local ClientDamageableManager = {}
ClientDamageableManager.__index = ClientDamageableManager

type Tracked = {
	body: Part,
	billboard: BillboardGui?,
	connections: { RBXScriptConnection },
}

export type ClientDamageableManager = typeof(setmetatable(
	{} :: {
		trackedByShadow: { [BasePart]: Tracked },
		bodyFolder: Folder?,
		hasWarnedTemplate: boolean,
	},
	ClientDamageableManager
))

local BODY_COLOR = Color3.fromRGB(200, 170, 110)
local BODY_HIT_COLOR = Color3.fromRGB(255, 80, 60)
local BODY_SLOWED_COLOR = Color3.fromRGB(120, 170, 255)
local BODY_STUNNED_COLOR = Color3.fromRGB(230, 240, 255)
local BODY_BURNING_COLOR = Color3.fromRGB(255, 140, 40)
local BODY_FLASH_SEC = 0.2
local BILLBOARD_LIFT_STUDS = 1.5
local HP_FILL_TWEEN_SEC = 0.15
local HP_FULL_COLOR = Color3.fromRGB(90, 200, 110)
local HP_EMPTY_COLOR = Color3.fromRGB(220, 70, 60)
local DEFAULT_SIZE = Vector3.new(4, 6, 2)

function ClientDamageableManager:findBillboardTemplate(): BillboardGui?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.STRUCTURE_HP_BILLBOARD) else nil
	if template and template:IsA("BillboardGui") then
		return template
	end
	if not self.hasWarnedTemplate then
		self.hasWarnedTemplate = true
		warn(`ClientDamageableManager: no {Constants.STRUCTURE_HP_BILLBOARD} BillboardGui under GameAssets.{Constants.GUI_TEMPLATES_FOLDER}; run scripts/studio/build_structure_hp_billboard.luau`)
	end
	return nil
end

function ClientDamageableManager:refreshBillboard(shadow: BasePart, billboard: BillboardGui, isInstant: boolean)
	local root = billboard:FindFirstChild(Constants.STRUCTURE_HP_ROOT_FRAME)
	local nameLabel = if root then root:FindFirstChild(Constants.STRUCTURE_HP_NAME_LABEL) else nil
	local bar = if root then root:FindFirstChild(Constants.STRUCTURE_HP_BAR) else nil
	local fill = if bar then bar:FindFirstChild(Constants.STRUCTURE_HP_FILL) else nil
	local valueLabel = if bar then bar:FindFirstChild(Constants.STRUCTURE_HP_VALUE_LABEL) else nil
	local costRow = if root then root:FindFirstChild(Constants.STRUCTURE_HP_COST_ROW) else nil
	local hp = shadow:GetAttribute(Attributes.DAMAGEABLE_HP)
	local maxHp = shadow:GetAttribute(Attributes.DAMAGEABLE_MAX_HP)
	local name = shadow:GetAttribute(Attributes.DAMAGEABLE_NAME)
	if typeof(hp) ~= "number" or typeof(maxHp) ~= "number" or maxHp <= 0 then
		return
	end
	local share = math.clamp(hp / maxHp, 0, 1)
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = UiStyle.formatTitle(if typeof(name) == "string" then name else "")
	end
	if valueLabel and valueLabel:IsA("TextLabel") then
		valueLabel.Text = `{math.ceil(hp)} / {maxHp}`
	end
	-- the repair price row belongs to Repair Mode only
	if costRow and costRow:IsA("GuiObject") then
		costRow.Visible = false
	end
	if fill and fill:IsA("Frame") then
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

function ClientDamageableManager:getBodyFolder(): Folder
	local folder = self.bodyFolder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = Constants.DAMAGEABLE_BODIES_FOLDER
	created.Parent = workspace
	self.bodyFolder = created
	return created
end

-- the body's resting colour given its status effects
function ClientDamageableManager:restingColor(shadow: BasePart): Color3
	if shadow:GetAttribute(Attributes.DAMAGEABLE_IS_BURNING) == true then
		return BODY_BURNING_COLOR
	end
	local multiplier = shadow:GetAttribute(Attributes.DAMAGEABLE_SPEED_MULTIPLIER)
	if typeof(multiplier) ~= "number" or multiplier >= 1 then
		return BODY_COLOR
	end
	if multiplier <= 0 then
		return BODY_STUNNED_COLOR
	end
	return BODY_COLOR:Lerp(BODY_SLOWED_COLOR, 1 - multiplier)
end

function ClientDamageableManager:refreshColor(shadow: BasePart, tracked: Tracked)
	tracked.body.Color = self:restingColor(shadow)
end

-- where a target's body is, for a tracer or a bolt to end
function ClientDamageableManager:getBodyPosition(id: string): Vector3?
	for shadow, tracked in self.trackedByShadow do
		if shadow:GetAttribute(Attributes.DAMAGEABLE_ID) == id then
			return tracked.body.Position
		end
	end
	return nil
end

-- the shot landed on this target: a short red flash on its body
function ClientDamageableManager:flashHit(id: string)
	for shadow, tracked in self.trackedByShadow do
		if shadow:GetAttribute(Attributes.DAMAGEABLE_ID) == id then
			tracked.body.Color = BODY_HIT_COLOR
			TweenService:Create(tracked.body, TweenInfo.new(BODY_FLASH_SEC), { Color = self:restingColor(shadow) }):Play()
			return
		end
	end
end

function ClientDamageableManager:track(shadow: Instance)
	if not shadow:IsA("BasePart") or self.trackedByShadow[shadow] then
		return
	end
	local size = shadow:GetAttribute(Attributes.DAMAGEABLE_SIZE)
	local body = Instance.new("Part")
	body.Name = shadow.Name
	body.Size = if typeof(size) == "Vector3" then size else DEFAULT_SIZE
	body.CFrame = shadow.CFrame
	body.Anchored = true
	body.Color = BODY_COLOR
	body.Material = Enum.Material.Wood
	body.Parent = self:getBodyFolder()

	local tracked: Tracked = {
		body = body,
		billboard = nil,
		connections = {},
	}
	self.trackedByShadow[shadow] = tracked

	local template = self:findBillboardTemplate()
	if template then
		local billboard = template:Clone()
		billboard.StudsOffsetWorldSpace = Vector3.new(0, body.Size.Y / 2 + BILLBOARD_LIFT_STUDS, 0)
		billboard.Adornee = body
		billboard.Parent = body
		tracked.billboard = billboard
		self:refreshBillboard(shadow, billboard, true)
	end
	for _, attribute in { Attributes.DAMAGEABLE_HP, Attributes.DAMAGEABLE_MAX_HP } do
		table.insert(
			tracked.connections,
			shadow:GetAttributeChangedSignal(attribute):Connect(
				function()
					if tracked.billboard then
						self:refreshBillboard(shadow, tracked.billboard, false)
					end
				end
			)
		)
	end
	for _, attribute in { Attributes.DAMAGEABLE_SPEED_MULTIPLIER, Attributes.DAMAGEABLE_IS_BURNING } do
		table.insert(
			tracked.connections,
			shadow:GetAttributeChangedSignal(attribute):Connect(
				function()
					self:refreshColor(shadow, tracked)
				end
			)
		)
	end
	self:refreshColor(shadow, tracked)
	-- enemies will move their shadow; the body follows
	table.insert(
		tracked.connections,
		shadow:GetPropertyChangedSignal("CFrame"):Connect(
			function()
				body.CFrame = shadow.CFrame
			end
		)
	)
end

function ClientDamageableManager:untrack(shadow: Instance)
	local tracked = self.trackedByShadow[shadow :: BasePart]
	if not tracked then
		return
	end
	for _, connection in tracked.connections do
		connection:Disconnect()
	end
	tracked.body:Destroy()
	self.trackedByShadow[shadow :: BasePart] = nil
end

function ClientDamageableManager:init()
	for _, shadow in CollectionService:GetTagged(Tags.DAMAGEABLE) do
		self:track(shadow)
	end
	CollectionService:GetInstanceAddedSignal(Tags.DAMAGEABLE):Connect(
		function(shadow: Instance)
			self:track(shadow)
		end
	)
	CollectionService:GetInstanceRemovedSignal(Tags.DAMAGEABLE):Connect(
		function(shadow: Instance)
			self:untrack(shadow)
		end
	)
end

function ClientDamageableManager.new(): ClientDamageableManager
	local self = setmetatable({}, ClientDamageableManager) :: ClientDamageableManager
	self.trackedByShadow = {}
	self.bodyFolder = nil
	self.hasWarnedTemplate = false
	return self
end

return ClientDamageableManager.new()
