-- Rebuilds the "PostHud" ScreenGui under StarterGui: what Post Weapon Mode
-- adds to the screen (GDD "Using a Post Weapon"). A Fire button for touch
-- players (bottom right above the jump button) and an Exit button in the
-- jump button's place, the weapon's reticle, and a "how to exit" hint near
-- the bottom edge for keyboard and gamepad (Spacebar, A, or Cross).
-- ClientPostManager shows them only while mounted. Run from the Studio
-- command bar (or the MCP execute_luau tool) in the gameplay place; it
-- replaces any existing copy. Names must match Constants.POST_HUD_*. Layout
-- follows the GUI standard in CLAUDE.md; fonts and colours from Shared/UiStyle.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Icons = require(game.ReplicatedStorage.Shared.Icons)
local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before PostHud gui")

local existing = StarterGui:FindFirstChild("PostHud")
if existing then
	existing:Destroy()
end

local function addCorner(parent)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UiStyle.CORNER_RADIUS_PX)
	corner.Parent = parent
end

local function addTouchTarget(button, maxSize)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(UiStyle.TOUCH_TARGET_MIN_PX, UiStyle.TOUCH_TARGET_MIN_PX)
	constraint.MaxSize = maxSize
	constraint.Parent = button
end

local function addTextSizeBounds(label, minPx, maxPx)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minPx
	constraint.MaxTextSize = maxPx
	constraint.Parent = label
end

local function makeButton(name, text, anchor, position, size, aspect, maxSize)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = anchor
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = UiStyle.PANEL_COLOR
	button.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = true
	button.Visible = false
	local aspectConstraint = Instance.new("UIAspectRatioConstraint")
	aspectConstraint.AspectRatio = aspect
	aspectConstraint.Parent = button
	addTouchTarget(button, maxSize)
	addCorner(button)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = UiStyle.STROKE_PX
	stroke.Color = UiStyle.ACCENT_COLOR
	stroke.Parent = button
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.8, 0.5)
	label.BackgroundTransparency = 1
	label.Text = UiStyle.formatTitle(text)
	label.TextColor3 = UiStyle.TEXT_COLOR
	label.TextScaled = true
	label.FontFace = UiStyle.TITLE_FONT
	addTextSizeBounds(label, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
	label.Parent = button
	return button
end

local gui = Instance.new("ScreenGui")
gui.Name = "PostHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = true

-- above the jump button (bottom-right corner), clear of it
local fireButton = makeButton("FireButton", "Fire", Vector2.new(1, 1), UDim2.fromScale(0.97, 0.6), UDim2.fromScale(0.13, 0.13), 1, Vector2.new(120, 120))
fireButton.Parent = gui

-- touch only: stands where Roblox's jump button was (ClientPostManager
-- hides the jump button and copies its exact rectangle while mounted);
-- this scale placement is only the fallback when no jump button is found
local exitButton = makeButton("ExitButton", "Exit", Vector2.new(1, 1), UDim2.fromScale(0.97, 0.9), UDim2.fromScale(0.1, 0.1), 1, Vector2.new(110, 110))
exitButton.Parent = gui

local hint = Instance.new("TextLabel")
hint.Name = "ExitHint"
hint.AnchorPoint = Vector2.new(0.5, 1)
-- near the bottom edge: the tool bar is hidden while mounted, so the space
-- is free (decided 2026-09-18); white and large enough to read at a glance
hint.Position = UDim2.fromScale(0.5, 0.95)
hint.Size = UDim2.fromScale(0.3, 0.05)
hint.BackgroundTransparency = 1
hint.Text = UiStyle.formatTitle("Spacebar to exit")
hint.TextColor3 = UiStyle.TEXT_COLOR
hint.TextScaled = true
hint.FontFace = UiStyle.TITLE_FONT
hint.Visible = false
addTextSizeBounds(hint, UiStyle.LABEL_TEXT_MIN_PX, 32)
local hintStroke = Instance.new("UIStroke")
hintStroke.Thickness = UiStyle.STROKE_PX
hintStroke.Color = UiStyle.BACKGROUND_COLOR
hintStroke.Parent = hint
local hintSize = Instance.new("UISizeConstraint")
hintSize.MaxSize = Vector2.new(480, 56)
hintSize.Parent = hint
hint.Parent = gui

-- the weapon's reticle image at the true screen centre (the gui ignores the
-- top bar inset for this reason); ClientPostManager sets the image per kind
gui.IgnoreGuiInset = true
local reticle = Instance.new("ImageLabel")
reticle.Name = "Reticle"
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.Position = UDim2.fromScale(0.5, 0.5)
reticle.Size = UDim2.fromScale(0.12, 0.12)
reticle.BackgroundTransparency = 1
reticle.ScaleType = Enum.ScaleType.Fit
reticle.Visible = false
local reticleAspect = Instance.new("UIAspectRatioConstraint")
reticleAspect.AspectRatio = 1
reticleAspect.Parent = reticle
local reticleSize = Instance.new("UISizeConstraint")
reticleSize.MaxSize = Vector2.new(160, 160)
reticleSize.Parent = reticle
reticle.Parent = gui

-- the status bar just above the exit hint: heat (green to red) for a gun
-- that overheats, the reload (red filling, green when loaded) for one that
-- reloads; ClientPostManager sizes and colours the Fill every frame, and
-- shows the label above it only while OVERHEATED or RELOADING
local statusBar = Instance.new("Frame")
statusBar.Name = "StatusBar"
statusBar.AnchorPoint = Vector2.new(0.5, 1)
statusBar.Position = UDim2.fromScale(0.5, 0.89)
statusBar.Size = UDim2.fromScale(0.2, 0.02)
statusBar.BackgroundColor3 = UiStyle.PANEL_COLOR
statusBar.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
statusBar.BorderSizePixel = 0
statusBar.Visible = false
local statusSize = Instance.new("UISizeConstraint")
statusSize.MaxSize = Vector2.new(320, 20)
statusSize.Parent = statusBar
addCorner(statusBar)
local statusStroke = Instance.new("UIStroke")
statusStroke.Thickness = 1
statusStroke.Color = UiStyle.BACKGROUND_COLOR
statusStroke.Parent = statusBar
local statusFill = Instance.new("Frame")
statusFill.Name = "Fill"
statusFill.Size = UDim2.fromScale(0, 1)
statusFill.BackgroundColor3 = UiStyle.POSITIVE_COLOR
statusFill.BorderSizePixel = 0
addCorner(statusFill)
statusFill.Parent = statusBar
statusBar.Parent = gui

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.AnchorPoint = Vector2.new(0.5, 1)
statusLabel.Position = UDim2.fromScale(0.5, 0.865)
statusLabel.Size = UDim2.fromScale(0.3, 0.045)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = UiStyle.formatTitle("Overheated")
statusLabel.TextColor3 = UiStyle.NEGATIVE_COLOR
statusLabel.TextScaled = true
statusLabel.FontFace = UiStyle.TITLE_FONT
statusLabel.Visible = false
addTextSizeBounds(statusLabel, UiStyle.LABEL_TEXT_MIN_PX, 30)
local statusLabelStroke = Instance.new("UIStroke")
statusLabelStroke.Thickness = UiStyle.STROKE_PX
statusLabelStroke.Color = UiStyle.BACKGROUND_COLOR
statusLabelStroke.Parent = statusLabel
local statusLabelSize = Instance.new("UISizeConstraint")
statusLabelSize.MaxSize = Vector2.new(480, 50)
statusLabelSize.Parent = statusLabel
statusLabel.Parent = gui

-- the Binoculars' tag hint (2026-10-19), against the right edge at the
-- screen's vertical centre: the tag icon on a panel, a grey sheet that
-- ClientBinocularsManager shrinks down it while the cooldown runs, and
-- the button under it ("RIGHT CLICK TO TAG", "LT TO TAG", "RECHARGING").
-- The outline is green when ready and red while recharging, the icon
-- half transparent while recharging (ClientBinocularsManager). Shown
-- only to a mounted Sniper on keyboard or gamepad
local tagHint = Instance.new("Frame")
tagHint.Name = "TagHint"
tagHint.AnchorPoint = Vector2.new(1, 0.5)
tagHint.Position = UDim2.fromScale(0.96, 0.5)
tagHint.Size = UDim2.fromScale(0.13, 0.13)
tagHint.BackgroundColor3 = UiStyle.PANEL_COLOR
tagHint.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
tagHint.BorderSizePixel = 0
tagHint.Visible = false
local tagAspect = Instance.new("UIAspectRatioConstraint")
tagAspect.AspectRatio = 1
tagAspect.DominantAxis = Enum.DominantAxis.Height
tagAspect.Parent = tagHint
local tagSize = Instance.new("UISizeConstraint")
tagSize.MaxSize = Vector2.new(144, 144)
tagSize.Parent = tagHint
addCorner(tagHint)
local tagStroke = Instance.new("UIStroke")
tagStroke.Thickness = UiStyle.STROKE_PX
tagStroke.Color = UiStyle.POSITIVE_COLOR
tagStroke.Parent = tagHint
local tagIcon = Instance.new("ImageLabel")
tagIcon.Name = "Icon"
tagIcon.AnchorPoint = Vector2.new(0.5, 0.5)
tagIcon.Position = UDim2.fromScale(0.5, 0.5)
tagIcon.Size = UDim2.fromScale(0.8, 0.8)
tagIcon.BackgroundTransparency = 1
tagIcon.Image = Icons.TAG_RETICLE
tagIcon.ScaleType = Enum.ScaleType.Fit
tagIcon.Parent = tagHint
local tagCooldown = Instance.new("Frame")
tagCooldown.Name = "Cooldown"
tagCooldown.AnchorPoint = Vector2.new(0, 1)
tagCooldown.Position = UDim2.fromScale(0, 1)
tagCooldown.Size = UDim2.fromScale(1, 0)
tagCooldown.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
tagCooldown.BackgroundTransparency = 0.35
tagCooldown.BorderSizePixel = 0
tagCooldown.ZIndex = 2
tagCooldown.Visible = false
addCorner(tagCooldown)
tagCooldown.Parent = tagHint
local tagLabel = Instance.new("TextLabel")
tagLabel.Name = "Label"
-- centred under the panel on two lines, no wider than the panel itself
tagLabel.AnchorPoint = Vector2.new(0.5, 0)
tagLabel.Position = UDim2.fromScale(0.5, 1.08)
tagLabel.Size = UDim2.fromScale(1.2, 0.45)
tagLabel.BackgroundTransparency = 1
tagLabel.TextWrapped = true
tagLabel.Text = UiStyle.formatTitle("Right click\nto tag")
tagLabel.TextColor3 = UiStyle.TEXT_COLOR
tagLabel.TextScaled = true
tagLabel.FontFace = UiStyle.TITLE_FONT
addTextSizeBounds(tagLabel, UiStyle.LABEL_TEXT_MIN_PX, 18)
local tagLabelStroke = Instance.new("UIStroke")
tagLabelStroke.Thickness = UiStyle.STROKE_PX
tagLabelStroke.Color = UiStyle.BACKGROUND_COLOR
tagLabelStroke.Parent = tagLabel
tagLabel.Parent = tagHint
tagHint.Parent = gui

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After PostHud gui")
print("build_post_hud_gui: built StarterGui.PostHud")
