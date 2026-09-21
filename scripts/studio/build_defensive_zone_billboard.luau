-- Rebuilds the "DefensiveZone" BillboardGui template under
-- ReplicatedStorage/GameAssets/Gui: the always-on-top "DEFENSIVE ZONE"
-- sign ClientPlacementToolManager floats over every zone part while Build
-- Mode is on (GDD "Defensive Zones"). Run from the Studio command bar (or
-- the MCP execute_luau tool) in the gameplay place; it replaces any
-- existing copy. Names must match Constants.DEFENSIVE_ZONE_*. Sizes are
-- in studs so the sign reads the same on every screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before DefensiveZone billboard")

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
local existing = guiFolder:FindFirstChild(Constants.DEFENSIVE_ZONE_BILLBOARD)
if existing then
	existing:Destroy()
end

-- 24 studs wide, 4 tall, floating 10 studs over the zone's centre
local billboard = Instance.new("BillboardGui")
billboard.Name = Constants.DEFENSIVE_ZONE_BILLBOARD
billboard.Size = UDim2.fromScale(24, 4)
billboard.StudsOffsetWorldSpace = Vector3.new(0, 10, 0)
billboard.MaxDistance = 250
billboard.AlwaysOnTop = true
billboard.LightInfluence = 0
billboard.ResetOnSpawn = false
billboard.Enabled = true

local label = Instance.new("TextLabel")
label.Name = Constants.DEFENSIVE_ZONE_LABEL
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.Text = UiStyle.formatTitle("Defensive Zone")
label.TextColor3 = UiStyle.ACCENT_COLOR
label.TextScaled = true
label.FontFace = UiStyle.TITLE_FONT
local bounds = Instance.new("UITextSizeConstraint")
bounds.MinTextSize = UiStyle.TITLE_TEXT_MIN_PX
bounds.MaxTextSize = 64
bounds.Parent = label
local stroke = Instance.new("UIStroke")
stroke.Color = UiStyle.BACKGROUND_COLOR
stroke.Thickness = UiStyle.STROKE_PX * 2
stroke.Parent = label
label.Parent = billboard

billboard.Parent = guiFolder
ChangeHistoryService:SetWaypoint("After DefensiveZone billboard")
print("build_defensive_zone_billboard: built " .. billboard:GetFullName())
