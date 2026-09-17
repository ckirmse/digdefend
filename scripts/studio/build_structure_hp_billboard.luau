-- Rebuilds the "StructureHp" BillboardGui template under
-- ReplicatedStorage/GameAssets/Gui: a structure's name over an HP bar reading
-- "hp / max", over the price of one Hammer swing ("4 [Iron Bar icon] for 10
-- HP", shown only on the structure under the reticle), which
-- ClientStructureManager clones onto every structure shadow while the Hammer
-- is equipped (GDD "Wall Repair": Build Mode shows the HP of everything
-- repairable). Run from the Studio command bar (or the
-- MCP execute_luau tool) in the gameplay place; it replaces any existing
-- copy. Names must match Constants.STRUCTURE_HP_*. Sizes are in studs
-- (BillboardGui scale units), so the bar reads the same on every screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums = require(ReplicatedStorage.Shared.Enums)
local Icons = require(ReplicatedStorage.Shared.Icons)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before StructureHp billboard")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
if not gameAssets then
	gameAssets = Instance.new("Folder")
	gameAssets.Name = Constants.GAME_ASSETS_FOLDER
	gameAssets.Parent = ReplicatedStorage
end
local guiFolder = gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER)
if not guiFolder then
	guiFolder = Instance.new("Folder")
	guiFolder.Name = Constants.GUI_TEMPLATES_FOLDER
	guiFolder.Parent = gameAssets
end
local existing = guiFolder:FindFirstChild(Constants.STRUCTURE_HP_BILLBOARD)
if existing then
	existing:Destroy()
end

local function addCorner(parent)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UiStyle.CORNER_RADIUS_PX)
	corner.Parent = parent
end

local function addTextSizeBounds(label, minPx, maxPx)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minPx
	constraint.MaxTextSize = maxPx
	constraint.Parent = label
end

-- 14 studs wide, 3.84 tall (three rows: name, an 8 stud bar, and the cost
-- row at twice the height of the others, 2026-09-17, which is what needs the width); on top so a bar is never hidden inside its own wall
local billboard = Instance.new("BillboardGui")
billboard.Name = Constants.STRUCTURE_HP_BILLBOARD
billboard.Size = UDim2.fromScale(14, 3.84)
billboard.MaxDistance = 120
billboard.AlwaysOnTop = true
billboard.LightInfluence = 0
billboard.ResetOnSpawn = false
billboard.Enabled = true

local root = Instance.new("Frame")
root.Name = Constants.STRUCTURE_HP_ROOT_FRAME
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = billboard

local nameLabel = Instance.new("TextLabel")
nameLabel.Name = Constants.STRUCTURE_HP_NAME_LABEL
nameLabel.Position = UDim2.fromScale(0, 0)
nameLabel.Size = UDim2.fromScale(1, 0.234)
nameLabel.BackgroundTransparency = 1
nameLabel.Text = UiStyle.formatTitle("Wall")
nameLabel.TextColor3 = UiStyle.TEXT_COLOR
nameLabel.TextScaled = true
nameLabel.FontFace = UiStyle.TITLE_FONT
addTextSizeBounds(nameLabel, UiStyle.BODY_TEXT_MIN_PX, 40)
local nameStroke = Instance.new("UIStroke")
nameStroke.Color = UiStyle.BACKGROUND_COLOR
nameStroke.Thickness = UiStyle.STROKE_PX
nameStroke.Parent = nameLabel
nameLabel.Parent = root

local bar = Instance.new("Frame")
bar.Name = Constants.STRUCTURE_HP_BAR
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = UDim2.fromScale(0.5, 0.25)
bar.Size = UDim2.fromScale(0.571, 0.266)
bar.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
bar.BorderSizePixel = 0
bar.ClipsDescendants = true
addCorner(bar)
local barStroke = Instance.new("UIStroke")
barStroke.Color = UiStyle.BACKGROUND_COLOR
barStroke.Thickness = UiStyle.STROKE_PX
barStroke.Parent = bar
local fill = Instance.new("Frame")
fill.Name = Constants.STRUCTURE_HP_FILL
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Color3.fromRGB(90, 200, 110)
fill.BorderSizePixel = 0
addCorner(fill)
fill.Parent = bar
local value = Instance.new("TextLabel")
value.Name = Constants.STRUCTURE_HP_VALUE_LABEL
value.Size = UDim2.fromScale(1, 1)
value.BackgroundTransparency = 1
value.Text = "200 / 200"
value.TextColor3 = UiStyle.TEXT_COLOR
value.TextScaled = true
value.FontFace = UiStyle.BODY_BOLD_FONT
value.ZIndex = 2
addTextSizeBounds(value, UiStyle.LABEL_TEXT_MIN_PX, 32)
local valueStroke = Instance.new("UIStroke")
valueStroke.Color = UiStyle.BACKGROUND_COLOR
valueStroke.Thickness = 1
valueStroke.Parent = value
value.Parent = bar
bar.Parent = root

-- "4 [icon] for 10 HP": the amount right-aligned against the icon and the
-- gain left-aligned after it, so the icon sits at a fixed spot and the row
-- reads centred for one- and two-digit prices
local costRow = Instance.new("Frame")
costRow.Name = Constants.STRUCTURE_HP_COST_ROW
costRow.AnchorPoint = Vector2.new(0.5, 1)
costRow.Position = UDim2.fromScale(0.5, 1)
costRow.Size = UDim2.fromScale(1, 0.4375)
costRow.BackgroundTransparency = 1
costRow.Visible = false
costRow.Parent = root

local function addCostText(name, text, anchorX, positionX, width, alignment)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(anchorX, 0.5)
	label.Position = UDim2.fromScale(positionX, 0.5)
	label.Size = UDim2.fromScale(width, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = UiStyle.ACCENT_COLOR
	label.TextScaled = true
	label.TextXAlignment = alignment
	label.FontFace = UiStyle.BODY_BOLD_FONT
	addTextSizeBounds(label, UiStyle.LABEL_TEXT_MIN_PX, 64)
	local stroke = Instance.new("UIStroke")
	stroke.Color = UiStyle.BACKGROUND_COLOR
	stroke.Thickness = UiStyle.STROKE_PX
	stroke.Parent = label
	label.Parent = costRow
	return label
end

addCostText(Constants.STRUCTURE_HP_COST_AMOUNT_LABEL, "4", 1, 0.3, 0.3, Enum.TextXAlignment.Right)
local ironIconId = Icons.REFINED_RESOURCE[Enums.RefinedResource.IRON_BAR]
local costIcon = Instance.new("ImageLabel")
costIcon.Name = Constants.STRUCTURE_HP_COST_ICON
costIcon.AnchorPoint = Vector2.new(0.5, 0.5)
costIcon.Position = UDim2.fromScale(0.37, 0.5)
costIcon.Size = UDim2.fromScale(1, 1)
costIcon.BackgroundTransparency = 1
costIcon.Image = if Icons.isPlaceholder(ironIconId) then "" else ironIconId
costIcon.ScaleType = Enum.ScaleType.Fit
local costIconAspect = Instance.new("UIAspectRatioConstraint")
costIconAspect.AspectRatio = 1
costIconAspect.DominantAxis = Enum.DominantAxis.Height
costIconAspect.Parent = costIcon
costIcon.Parent = costRow
addCostText(Constants.STRUCTURE_HP_COST_GAIN_LABEL, "for 10 HP", 0, 0.44, 0.56, Enum.TextXAlignment.Left)

billboard.Parent = guiFolder
ChangeHistoryService:SetWaypoint("After StructureHp billboard")
print("build_structure_hp_billboard: built " .. billboard:GetFullName())
