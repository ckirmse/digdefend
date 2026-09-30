-- Rebuilds the "OrePickupFace" SurfaceGui template under
-- ReplicatedStorage/GameAssets/Gui: the ore icon on one face of the plate
-- ClientOrePickupManager draws for ore lying on the ground (GDD "Mining",
-- overflow pickups). A SurfaceGui with LightInfluence 0 instead of a Decal
-- (decided 2026-09-29): a Decal takes the mine's lighting and read dark
-- underground, a lit GUI does not. The client clones it twice per plate,
-- front and back, and sets the image. Run from the Studio command bar (or
-- the MCP execute_luau tool) in the gameplay place; it replaces any
-- existing copy. Names must match Constants.ORE_PICKUP_FACE_*.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

ChangeHistoryService:SetWaypoint("Before OrePickupFace gui")

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
local existing = guiFolder:FindFirstChild(Constants.ORE_PICKUP_FACE_GUI)
if existing then
	existing:Destroy()
end

local gui = Instance.new("SurfaceGui")
gui.Name = Constants.ORE_PICKUP_FACE_GUI
gui.Face = Enum.NormalId.Front
gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
gui.PixelsPerStud = 100
gui.LightInfluence = 0
gui.AlwaysOnTop = false
gui.ResetOnSpawn = false
gui.Enabled = true

local icon = Instance.new("ImageLabel")
icon.Name = Constants.ORE_PICKUP_FACE_IMAGE
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.fromScale(0.5, 0.5)
icon.Size = UDim2.fromScale(1, 1)
icon.ScaleType = Enum.ScaleType.Fit
icon.BackgroundTransparency = 1
icon.BorderSizePixel = 0
icon.Parent = gui
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = 1
aspect.Parent = icon

gui.Parent = guiFolder

ChangeHistoryService:SetWaypoint("After OrePickupFace gui")
print("Built GameAssets.Gui." .. Constants.ORE_PICKUP_FACE_GUI)
