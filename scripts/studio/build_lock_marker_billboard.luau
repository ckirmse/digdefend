-- Rebuilds the "LockMarker" BillboardGui template under
-- ReplicatedStorage/GameAssets/Gui (2026-10-20): the reticle the Missile
-- Launcher's gunner sees over every monster the post has locked (the
-- Machine Gun's reticle picture, green). ClientLockMarkerManager clones
-- it onto an anchor that follows the body. Run from the Studio command
-- bar (or the MCP execute_luau tool) in the gameplay place; it replaces
-- any existing copy. Names must match Constants.LOCK_MARKER_*. Sizes are
-- in studs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Icons = require(ReplicatedStorage.Shared.Icons)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before LockMarker billboard")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local guiFolder = gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER)
local existing = guiFolder:FindFirstChild(Constants.LOCK_MARKER_BILLBOARD)
if existing then
	existing:Destroy()
end

local billboard = Instance.new("BillboardGui")
billboard.Name = Constants.LOCK_MARKER_BILLBOARD
billboard.Size = UDim2.fromScale(4, 4)
billboard.MaxDistance = 600
billboard.AlwaysOnTop = true
billboard.LightInfluence = 0
billboard.ResetOnSpawn = false
billboard.Enabled = true

local icon = Instance.new("ImageLabel")
icon.Name = Constants.LOCK_MARKER_ICON
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.fromScale(0.5, 0.5)
icon.Size = UDim2.fromScale(1, 1)
icon.BackgroundTransparency = 1
icon.Image = Icons.LOCK_MARKER
icon.ImageColor3 = UiStyle.POSITIVE_COLOR
icon.ScaleType = Enum.ScaleType.Fit
icon.Parent = billboard
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = 1
aspect.Parent = icon

billboard.Parent = guiFolder

ChangeHistoryService:SetWaypoint("After LockMarker billboard")
print("build_lock_marker_billboard: built GameAssets." .. Constants.GUI_TEMPLATES_FOLDER .. "." .. Constants.LOCK_MARKER_BILLBOARD)
