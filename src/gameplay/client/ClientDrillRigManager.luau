--!strict

-- The Drill Rig as the client sees it (2026-10-22). The rig's body and
-- its name, HP, and owner billboard are ClientPlacementManager's, like
-- any Tower's; this adds what the rig alone has: the DrillRigStock
-- billboard hung over it (GameAssets/Gui/DrillRigStock, a row per raw
-- resource with the icon and the count, from the shadow's DrillRigStock
-- attribute the server keeps current) and a Collect prompt anyone may
-- use (made here, never on the server; TryCollectDrillRig names the rig).
-- A placement shadow is found by its tag and told apart by its type kind.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local DrillRigRules = require("@game/ReplicatedStorage/Shared/DrillRigRules")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)

local ClientDrillRigManager = {}
ClientDrillRigManager.__index = ClientDrillRigManager

type RigView = {
	billboard: BillboardGui?,
	prompt: ProximityPrompt?,
	connection: RBXScriptConnection?,
}

export type ClientDrillRigManager = typeof(setmetatable(
	{} :: {
		viewsByShadow: { [BasePart]: RigView },
		hasWarnedTemplate: boolean,
	},
	ClientDrillRigManager
))

local PROMPT_HOLD_SEC = 0.5
local PROMPT_MAX_DISTANCE_STUDS = 10
-- the stock reads above the placement's own billboard
local BILLBOARD_LIFT_STUDS = 8

function ClientDrillRigManager:findTemplate(): BillboardGui?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.DRILL_RIG_STOCK_BILLBOARD) else nil
	if template and template:IsA("BillboardGui") then
		return template
	end
	if not self.hasWarnedTemplate then
		self.hasWarnedTemplate = true
		warn(`ClientDrillRigManager: no {Constants.DRILL_RIG_STOCK_BILLBOARD} BillboardGui under GameAssets.{Constants.GUI_TEMPLATES_FOLDER}; run scripts/studio/build_drill_rig_billboard.luau`)
	end
	return nil
end

function ClientDrillRigManager:isRig(shadow: BasePart): boolean
	return shadow:GetAttribute(Attributes.PLACEMENT_KIND) == Enums.PlacementKind.TOWER
		and shadow:GetAttribute(Attributes.PLACEMENT_TYPE_KIND) == Enums.TowerKind.DRILL_RIG
end

-- one row per resource held, hidden when it holds none
function ClientDrillRigManager:refresh(shadow: BasePart, view: RigView)
	local billboard = view.billboard
	local root = if billboard then billboard:FindFirstChild(Constants.DRILL_RIG_STOCK_ROOT_FRAME) else nil
	if not root then
		return
	end
	local stock = DrillRigRules.decodeStock(shadow:GetAttribute(Attributes.DRILL_RIG_STOCK))
	for _, resource in Enums.getAllValues(Enums.RawResource) do
		local row = root:FindFirstChild(Constants.DRILL_RIG_STOCK_ROW_PREFIX .. tostring(Enums.getName(Enums.RawResource, resource)))
		if not row or not row:IsA("Frame") then
			continue
		end
		local amount = stock[resource] or 0
		row.Visible = amount > 0
		local count = row:FindFirstChild(Constants.DRILL_RIG_STOCK_ROW_COUNT)
		if count and count:IsA("TextLabel") then
			count.Text = tostring(amount)
		end
		local icon = row:FindFirstChild(Constants.DRILL_RIG_STOCK_ROW_ICON)
		if icon and icon:IsA("ImageLabel") then
			icon.Image = Icons.RAW_RESOURCE[resource] or ""
		end
	end
end

function ClientDrillRigManager:track(shadow: Instance)
	if not shadow:IsA("BasePart") or self.viewsByShadow[shadow] or not self:isRig(shadow) then
		return
	end
	local view: RigView = {
		billboard = nil,
		prompt = nil,
		connection = nil,
	}
	local template = self:findTemplate()
	if template then
		local billboard = template:Clone()
		billboard.Adornee = shadow
		billboard.StudsOffsetWorldSpace = Vector3.new(0, BILLBOARD_LIFT_STUDS, 0)
		billboard.Parent = shadow
		view.billboard = billboard
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = Constants.DRILL_RIG_COLLECT_ACTION_TEXT
	prompt.ObjectText = Enums.getPublicName(Enums.TowerKind, Enums.TowerKind.DRILL_RIG) or ""
	prompt.HoldDuration = PROMPT_HOLD_SEC
	prompt.MaxActivationDistance = PROMPT_MAX_DISTANCE_STUDS
	prompt.RequiresLineOfSight = false
	-- a clickable prompt frees the mouse when hovered, which sticks the cursor in first person
	prompt.ClickablePrompt = false
	prompt.Parent = shadow
	prompt.Triggered:Connect(
		function()
			ClientNetManager:fireServer(NetEventNames.TRY_COLLECT_DRILL_RIG, { id = shadow.Name })
		end
	)
	view.prompt = prompt
	view.connection = shadow:GetAttributeChangedSignal(Attributes.DRILL_RIG_STOCK):Connect(
		function()
			self:refresh(shadow, view)
		end
	)
	self.viewsByShadow[shadow] = view
	self:refresh(shadow, view)
end

function ClientDrillRigManager:untrack(shadow: Instance)
	local view = self.viewsByShadow[shadow :: BasePart]
	if not view then
		return
	end
	self.viewsByShadow[shadow :: BasePart] = nil
	if view.connection then
		view.connection:Disconnect()
	end
	if view.billboard then
		view.billboard:Destroy()
	end
	if view.prompt then
		view.prompt:Destroy()
	end
end

function ClientDrillRigManager:init()
	for _, shadow in CollectionService:GetTagged(Tags.PLACEMENT) do
		self:track(shadow)
	end
	CollectionService:GetInstanceAddedSignal(Tags.PLACEMENT):Connect(
		function(shadow: Instance)
			-- the type kind lands with the shadow's other attributes
			task.defer(
				function()
					self:track(shadow)
				end
			)
		end
	)
	CollectionService:GetInstanceRemovedSignal(Tags.PLACEMENT):Connect(
		function(shadow: Instance)
			self:untrack(shadow)
		end
	)
end

function ClientDrillRigManager.new(): ClientDrillRigManager
	local self = setmetatable({}, ClientDrillRigManager) :: ClientDrillRigManager
	self.viewsByShadow = {}
	self.hasWarnedTemplate = false
	return self
end

return ClientDrillRigManager.new()
