-- Rebuilds the "WeaponHud" ScreenGui under StarterGui: the Weapon Mode ammo
-- readout ("12 / 20", or RELOADING), a button so a tap reloads, sitting just
-- above the tool bar at the bottom centre (clear of the thumbstick, the jump
-- button, and the chat window). ClientWeaponManager shows it only while the
-- weapon is equipped. Run from the Studio command bar (or the MCP
-- execute_luau tool) in the gameplay place; it replaces any existing copy.
-- Names must match Constants.WEAPON_HUD_*. Layout follows the GUI standard
-- in CLAUDE.md; fonts and colours come from Shared/UiStyle.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Icons = require(game.ReplicatedStorage.Shared.Icons)
local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before WeaponHud gui")

local existing = StarterGui:FindFirstChild("WeaponHud")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "WeaponHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = true

local button = Instance.new("TextButton")
button.Name = "AmmoButton"
button.AnchorPoint = Vector2.new(0.5, 1)
-- the tool bar's slots now end at 0.93 with a caption under each, so their
-- top edge is near 0.83 (2026-09-25); the button sits just above it
button.Position = UDim2.fromScale(0.5, 0.815)
button.Size = UDim2.fromScale(0.16, 0.05)
button.BackgroundColor3 = UiStyle.PANEL_COLOR
button.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
button.BorderSizePixel = 0
button.Text = ""
button.AutoButtonColor = true
button.Visible = false
button.Parent = gui
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = 4
aspect.Parent = button
local buttonSize = Instance.new("UISizeConstraint")
buttonSize.MinSize = Vector2.new(UiStyle.TOUCH_TARGET_MIN_PX, UiStyle.TOUCH_TARGET_MIN_PX)
buttonSize.MaxSize = Vector2.new(240, 60)
buttonSize.Parent = button
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, UiStyle.CORNER_RADIUS_PX)
corner.Parent = button

local label = Instance.new("TextLabel")
label.Name = "AmmoLabel"
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.5)
label.Size = UDim2.fromScale(0.86, 0.7)
label.BackgroundTransparency = 1
label.Text = "20 / 20"
label.TextColor3 = UiStyle.TEXT_COLOR
label.TextScaled = true
label.FontFace = UiStyle.BODY_BOLD_FONT
label.Parent = button
local textSize = Instance.new("UITextSizeConstraint")
textSize.MinTextSize = UiStyle.LABEL_TEXT_MIN_PX
textSize.MaxTextSize = UiStyle.LABEL_TEXT_MAX_PX
textSize.Parent = label

-- the secondary's bar (2026-10-19), a child of the ammo button so it takes
-- the button's width and sits just above it on every screen (the button's
-- touch-target floor would otherwise leave a sibling smaller than it): the
-- launcher icon on the left, "GRENADE LAUNCHER" over a track whose Fill
-- ClientWeaponManager sizes every frame, full when ready, empty on the
-- shot, refilling red over the cooldown
local secondaryBar = Instance.new("Frame")
secondaryBar.Name = "SecondaryBar"
secondaryBar.AnchorPoint = Vector2.new(0.5, 1)
secondaryBar.Position = UDim2.fromScale(0.5, -0.1)
secondaryBar.Size = UDim2.fromScale(0.7, 0.81)
secondaryBar.BackgroundColor3 = UiStyle.PANEL_COLOR
secondaryBar.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
secondaryBar.BorderSizePixel = 0
secondaryBar.Visible = false
secondaryBar.Parent = button
local secondaryCorner = Instance.new("UICorner")
secondaryCorner.CornerRadius = UDim.new(0, UiStyle.CORNER_RADIUS_PX)
secondaryCorner.Parent = secondaryBar

local secondaryIcon = Instance.new("ImageLabel")
secondaryIcon.Name = "Icon"
secondaryIcon.AnchorPoint = Vector2.new(0, 0.5)
secondaryIcon.Position = UDim2.fromScale(0.03, 0.5)
secondaryIcon.Size = UDim2.fromScale(0.8, 0.8)
secondaryIcon.BackgroundTransparency = 1
secondaryIcon.Image = Icons.UI.GRENADE_LAUNCHER
secondaryIcon.ScaleType = Enum.ScaleType.Fit
secondaryIcon.Parent = secondaryBar
local secondaryIconAspect = Instance.new("UIAspectRatioConstraint")
secondaryIconAspect.AspectRatio = 1
secondaryIconAspect.DominantAxis = Enum.DominantAxis.Height
secondaryIconAspect.Parent = secondaryIcon

local secondaryLabel = Instance.new("TextLabel")
secondaryLabel.Name = "Label"
secondaryLabel.AnchorPoint = Vector2.new(0, 0)
secondaryLabel.Position = UDim2.fromScale(0.26, 0.1)
secondaryLabel.Size = UDim2.fromScale(0.7, 0.4)
secondaryLabel.BackgroundTransparency = 1
secondaryLabel.Text = UiStyle.formatTitle("Grenade Launcher")
secondaryLabel.TextColor3 = UiStyle.TEXT_COLOR
secondaryLabel.TextScaled = true
secondaryLabel.TextXAlignment = Enum.TextXAlignment.Left
secondaryLabel.FontFace = UiStyle.TITLE_FONT
secondaryLabel.Parent = secondaryBar
local secondaryTextSize = Instance.new("UITextSizeConstraint")
secondaryTextSize.MinTextSize = UiStyle.LABEL_TEXT_MIN_PX
secondaryTextSize.MaxTextSize = 14
secondaryTextSize.Parent = secondaryLabel

local secondaryTrack = Instance.new("Frame")
secondaryTrack.Name = "Track"
secondaryTrack.AnchorPoint = Vector2.new(0, 1)
secondaryTrack.Position = UDim2.fromScale(0.26, 0.86)
secondaryTrack.Size = UDim2.fromScale(0.7, 0.26)
secondaryTrack.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
secondaryTrack.BorderSizePixel = 0
secondaryTrack.Parent = secondaryBar
local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(0.5, 0)
trackCorner.Parent = secondaryTrack
local secondaryFill = Instance.new("Frame")
secondaryFill.Name = "Fill"
secondaryFill.Size = UDim2.fromScale(1, 1)
secondaryFill.BackgroundColor3 = UiStyle.POSITIVE_COLOR
secondaryFill.BorderSizePixel = 0
secondaryFill.Parent = secondaryTrack
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0.5, 0)
fillCorner.Parent = secondaryFill

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After WeaponHud gui")
print("build_weapon_hud_gui: built StarterGui.WeaponHud")
