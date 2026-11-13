-- Rebuilds the "PlayerName" BillboardGui template under
-- ReplicatedStorage/GameAssets/Gui: a crewmate's display name over their
-- head, which ClientPlayerNameManager clones onto every other player and
-- tints with that player's compass dot colour (2026-09-30). It replaces
-- Roblox's own overhead name, which cannot be coloured. Run from the
-- Studio command bar (or the MCP execute_luau tool) in either place;
-- an existing copy is kept as the designer has tuned it and only gains the
-- ClassIcon when it has none; a place with no copy (the lobby, which shows
-- the same tags since 2026-11-13) gets one built to match the live
-- gameplay template of that day. Names must match Constants.PLAYER_NAME_*.
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
local billboard = guiFolder:FindFirstChild("PlayerName")
if not billboard then
	-- 6 studs wide, 1 tall: one line, readable across the camp
	billboard = Instance.new("BillboardGui")
	billboard.Name = "PlayerName"
	billboard.Size = UDim2.fromScale(6, 1)
	-- the distance Roblox's own name shows to
	billboard.MaxDistance = 100
	-- above the head, clear of Roblox's health bar
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
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
	-- the designer's soft shadow behind the letters (a stroke before;
	-- ported from the live gameplay template, 2026-11-13)
	local shadow = Instance.new("UIShadow")
	shadow.Mode = Enum.ApplyShadowMode.Text
	shadow.BlurRadius = UDim.new(0.1, 0)
	shadow.Color = Color3.new(0, 0, 0)
	shadow.Transparency = 0.5
	shadow.ShowBehindParent = true
	shadow.ZIndex = -1
	shadow.Parent = label
	label.Parent = billboard

	billboard.Parent = guiFolder
end

-- the crewmate's class picture, left of the name: a square 1.5 times the billboard's
-- height whose right edge ClientPlayerNameManager slides to where the drawn
-- text starts; the picture here is only the Explorer's preview
if not billboard:FindFirstChild("ClassIcon") then
	local icon = Instance.new("ImageLabel")
	icon.Name = "ClassIcon"
	icon.AnchorPoint = Vector2.new(1, 0.5)
	icon.Position = UDim2.fromScale(0.3, 0.5)
	-- half as tall again as the name (designer, 2026-11-13)
	icon.Size = UDim2.fromScale(1.5, 1.5)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = "rbxassetid://103204546509022"
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = icon
	icon.Parent = billboard
end

ChangeHistoryService:SetWaypoint("After PlayerName billboard")
print("build_player_name_billboard: built " .. billboard:GetFullName())
