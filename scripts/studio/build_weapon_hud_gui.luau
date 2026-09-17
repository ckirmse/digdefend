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
-- the tool bar's top edge is near 0.87
button.Position = UDim2.fromScale(0.5, 0.855)
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

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After WeaponHud gui")
print("build_weapon_hud_gui: built StarterGui.WeaponHud")
