-- Rebuilds the "PlacementInfo" BillboardGui template under
-- ReplicatedStorage/GameAssets/Gui: a placement's name over its HP bar over
-- its owner's display name, which ClientPlacementManager clones onto every
-- placement shadow (GDD "Building Towers": every active Tower shows its
-- name, HP, and owner). Run from the Studio command bar (or the MCP
-- execute_luau tool) in the gameplay place; it replaces any existing copy.
-- Names must match Constants.PLACEMENT_INFO_*. Sizes are in studs so the
-- bar reads the same on every screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before PlacementInfo billboard")

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
local existing = guiFolder:FindFirstChild(Constants.PLACEMENT_INFO_BILLBOARD)
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

local function addLabel(parent, name, text, font, positionY, height, maxPx, color)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = UDim2.fromScale(0, positionY)
	label.Size = UDim2.fromScale(1, height)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.FontFace = font
	addTextSizeBounds(label, UiStyle.LABEL_TEXT_MIN_PX, maxPx)
	local stroke = Instance.new("UIStroke")
	stroke.Color = UiStyle.BACKGROUND_COLOR
	stroke.Thickness = UiStyle.STROKE_PX
	stroke.Parent = label
	label.Parent = parent
	return label
end

-- 8 studs wide, 2.6 tall: name, a 5 stud bar, owner; fades with distance
-- so a field of Towers is not a wall of text
local billboard = Instance.new("BillboardGui")
billboard.Name = Constants.PLACEMENT_INFO_BILLBOARD
billboard.Size = UDim2.fromScale(8, 2.6)
billboard.MaxDistance = 90
billboard.AlwaysOnTop = false
billboard.LightInfluence = 0
billboard.ResetOnSpawn = false
billboard.Enabled = true

local root = Instance.new("Frame")
root.Name = Constants.PLACEMENT_INFO_ROOT_FRAME
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = billboard

addLabel(root, Constants.PLACEMENT_INFO_NAME_LABEL, UiStyle.formatTitle("Sentry Gun 1"), UiStyle.TITLE_FONT, 0, 0.38, 36, UiStyle.TEXT_COLOR)

local bar = Instance.new("Frame")
bar.Name = Constants.PLACEMENT_INFO_BAR
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = UDim2.fromScale(0.5, 0.42)
bar.Size = UDim2.fromScale(0.625, 0.22)
bar.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
bar.BorderSizePixel = 0
bar.ClipsDescendants = true
addCorner(bar)
local barStroke = Instance.new("UIStroke")
barStroke.Color = UiStyle.BACKGROUND_COLOR
barStroke.Thickness = UiStyle.STROKE_PX
barStroke.Parent = bar
local fill = Instance.new("Frame")
fill.Name = Constants.PLACEMENT_INFO_FILL
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Color3.fromRGB(90, 200, 110)
fill.BorderSizePixel = 0
addCorner(fill)
fill.Parent = bar
bar.Parent = root

addLabel(root, Constants.PLACEMENT_INFO_OWNER_LABEL, "Owner", UiStyle.BODY_FONT, 0.68, 0.3, 26, UiStyle.TEXT_MUTED_COLOR)

billboard.Parent = guiFolder
ChangeHistoryService:SetWaypoint("After PlacementInfo billboard")
print("build_placement_billboard: built " .. billboard:GetFullName())
