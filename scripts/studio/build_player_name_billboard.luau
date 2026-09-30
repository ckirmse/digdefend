-- Rebuilds the "PlayerName" BillboardGui template under
-- ReplicatedStorage/GameAssets/Gui: a crewmate's display name over their
-- head, which ClientPlayerNameManager clones onto every other player and
-- tints with that player's compass dot colour (2026-09-30). It replaces
-- Roblox's own overhead name, which cannot be coloured. Run from the
-- Studio command bar (or the MCP execute_luau tool) in the gameplay place;
-- it replaces any existing copy. Names must match Constants.PLAYER_NAME_*.
-- Sizes are in studs (BillboardGui scale units), so the name reads the
-- same on every screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before PlayerName billboard")

local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
if not gameAssets then
	gameAssets = Instance.new("Folder")
	gameAssets.Name = "GameAssets"
	gameAssets.Parent = ReplicatedStorage
end
local guiFolder = gameAssets:FindFirstChild("Gui")
if not guiFolder then
	guiFolder = Instance.new("Folder")
	guiFolder.Name = "Gui"
	guiFolder.Parent = gameAssets
end
local existing = guiFolder:FindFirstChild("PlayerName")
if existing then
	existing:Destroy()
end

-- 6 studs wide, 1 tall: one line, readable across the camp
local billboard = Instance.new("BillboardGui")
billboard.Name = "PlayerName"
billboard.Size = UDim2.fromScale(6, 1)
-- the distance Roblox's own name shows to
billboard.MaxDistance = 100
-- above the head, clear of Roblox's health bar
billboard.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
billboard.AlwaysOnTop = false
billboard.LightInfluence = 0
billboard.ResetOnSpawn = false
billboard.Enabled = true

local label = Instance.new("TextLabel")
label.Name = "NameLabel"
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.5)
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.Text = "Player"
label.TextColor3 = UiStyle.COMPASS_PLAYER_COLORS[1]
label.TextScaled = true
label.TextTruncate = Enum.TextTruncate.AtEnd
label.FontFace = UiStyle.BODY_BOLD_FONT
local textSize = Instance.new("UITextSizeConstraint")
textSize.MinTextSize = UiStyle.BODY_TEXT_MIN_PX
textSize.MaxTextSize = 40
textSize.Parent = label
local stroke = Instance.new("UIStroke")
stroke.Color = UiStyle.BACKGROUND_COLOR
stroke.Thickness = UiStyle.STROKE_PX
stroke.Parent = label
label.Parent = billboard

billboard.Parent = guiFolder
ChangeHistoryService:SetWaypoint("After PlayerName billboard")
print("build_player_name_billboard: built " .. billboard:GetFullName())
