-- Rebuilds the "FlightIcon" BillboardGui template under
-- ReplicatedStorage/GameAssets/Gui: one resource icon that
-- ClientIconFlightManager clones onto a throwaway part and flies through the
-- world, ore into the Refinery's hopper and refined bars out of it to the
-- player (GDD "Refining Ore", decided 2026-09-29: the old screen-space
-- flight aimed at a point the camera had already moved away from). As a
-- coloured disc (no image) it shows the corner and hairline, which the code
-- switches off when an image is set. Run from the Studio command bar (or the
-- MCP execute_luau tool) in the gameplay place; it replaces any existing
-- copy. Names must match Constants.FLIGHT_ICON_*. Sizes are in studs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before FlightIcon billboard")

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
local existing = guiFolder:FindFirstChild(Constants.FLIGHT_ICON_BILLBOARD)
if existing then
	existing:Destroy()
end

-- a 2.4 stud square, on top so it is never hidden inside the hopper or the
-- player's own character
local billboard = Instance.new("BillboardGui")
billboard.Name = Constants.FLIGHT_ICON_BILLBOARD
billboard.Size = UDim2.fromScale(2.4, 2.4)
billboard.MaxDistance = 200
billboard.AlwaysOnTop = true
billboard.LightInfluence = 0
billboard.ResetOnSpawn = false
billboard.Enabled = true

local icon = Instance.new("ImageLabel")
icon.Name = Constants.FLIGHT_ICON_IMAGE
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.fromScale(0.5, 0.5)
icon.Size = UDim2.fromScale(1, 1)
icon.ScaleType = Enum.ScaleType.Fit
icon.BackgroundColor3 = UiStyle.ACCENT_COLOR
icon.BackgroundTransparency = 0
icon.BorderSizePixel = 0
icon.Parent = billboard
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = 1
aspect.Parent = icon
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.5, 0)
corner.Parent = icon
local stroke = Instance.new("UIStroke")
stroke.Thickness = UiStyle.STROKE_PX
stroke.Color = UiStyle.ACCENT_STROKE_COLOR
stroke.Parent = icon

billboard.Parent = guiFolder

ChangeHistoryService:SetWaypoint("After FlightIcon billboard")
print("Built GameAssets.Gui." .. Constants.FLIGHT_ICON_BILLBOARD)
