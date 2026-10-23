-- Rebuilds the "DrillRigStock" BillboardGui template under
-- ReplicatedStorage/GameAssets/Gui (2026-10-22): the ore a Drill Rig holds,
-- one row per raw resource (RowIRON_ORE, RowGOLD_ORE, RowURANIUM_ORE), each
-- the resource's icon beside its count, which ClientDrillRigManager clones
-- over every rig and fills from the shadow's DrillRigStock attribute
-- (resources are icons, never words). Run from the Studio command bar (or
-- the MCP execute_luau tool) in the gameplay place; it replaces any
-- existing copy. Names must match Constants.DRILL_RIG_STOCK_*. Sizes are in
-- studs so the rows read the same on every screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums = require(ReplicatedStorage.Shared.Enums)
local Icons = require(ReplicatedStorage.Shared.Icons)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)

local BILLBOARD_SIZE_STUDS = Vector2.new(5, 3.6)
local ROW_HEIGHT_SHARE = 0.3
local ROW_GAP_SHARE = 0.05
local ICON_SHARE = 0.3
local COUNT_TEXT_MAX_PX = 22

ChangeHistoryService:SetWaypoint("Before DrillRigStock billboard")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local guiFolder = gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER)
local existing = guiFolder:FindFirstChild(Constants.DRILL_RIG_STOCK_BILLBOARD)
if existing then
	existing:Destroy()
end

local billboard = Instance.new("BillboardGui")
billboard.Name = Constants.DRILL_RIG_STOCK_BILLBOARD
billboard.Size = UDim2.fromScale(BILLBOARD_SIZE_STUDS.X, BILLBOARD_SIZE_STUDS.Y)
billboard.AlwaysOnTop = true
billboard.MaxDistance = 80
billboard.ResetOnSpawn = false

local root = Instance.new("Frame")
root.Name = Constants.DRILL_RIG_STOCK_ROOT_FRAME
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = billboard

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(ROW_GAP_SHARE, 0)
layout.Parent = root

for order, resource in Enums.getAllValues(Enums.RawResource) do
	local row = Instance.new("Frame")
	row.Name = Constants.DRILL_RIG_STOCK_ROW_PREFIX .. Enums.getName(Enums.RawResource, resource)
	row.Size = UDim2.fromScale(1, ROW_HEIGHT_SHARE)
	row.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
	row.BackgroundTransparency = 0.25
	row.LayoutOrder = order
	row.Visible = false
	row.Parent = root
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UiStyle.CORNER_RADIUS_PX)
	corner.Parent = row

	local icon = Instance.new("ImageLabel")
	icon.Name = Constants.DRILL_RIG_STOCK_ROW_ICON
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromScale(0.05, 0.5)
	icon.Size = UDim2.fromScale(ICON_SHARE, 0.85)
	icon.BackgroundTransparency = 1
	icon.Image = Icons.RAW_RESOURCE[resource] or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = row
	local iconAspect = Instance.new("UIAspectRatioConstraint")
	iconAspect.AspectRatio = 1
	iconAspect.DominantAxis = Enum.DominantAxis.Height
	iconAspect.Parent = icon

	local count = Instance.new("TextLabel")
	count.Name = Constants.DRILL_RIG_STOCK_ROW_COUNT
	count.AnchorPoint = Vector2.new(1, 0.5)
	count.Position = UDim2.fromScale(0.95, 0.5)
	count.Size = UDim2.fromScale(0.55, 0.85)
	count.BackgroundTransparency = 1
	count.FontFace = UiStyle.BODY_FONT
	count.TextColor3 = UiStyle.TEXT_COLOR
	count.TextScaled = true
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.Text = "0"
	count.Parent = row
	local countSize = Instance.new("UITextSizeConstraint")
	countSize.MaxTextSize = COUNT_TEXT_MAX_PX
	countSize.Parent = count
end

billboard.Parent = guiFolder

ChangeHistoryService:SetWaypoint("After DrillRigStock billboard")
print("build_drill_rig_billboard: built GameAssets." .. Constants.GUI_TEMPLATES_FOLDER .. "." .. Constants.DRILL_RIG_STOCK_BILLBOARD)
