-- Rebuilds the lobby "HUD" ScreenGui under StarterGui. Run from the Studio
-- command bar (or the MCP execute_luau tool) in the lobby place; it replaces
-- any existing copy. Names must match Constants.HUD_*. The loadout strip
-- along the bottom was removed on 2026-10-12 (the character brings its
-- gear; see the Character Menu). Layout follows the GUI
-- standard in CLAUDE.md; fonts and colours come from Shared/UiStyle.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)
local Icons = require(game.ReplicatedStorage.Shared.Icons)

ChangeHistoryService:SetWaypoint("Before HUD gui")

local existing = StarterGui:FindFirstChild("HUD")
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

-- max only: a pixel minimum would override scale on small screens (GUI
-- standard, 2026-09-16); touch targets alone keep a floor, via addTouchTarget
local function addMaxSize(frame, maxSize)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = maxSize
	constraint.Parent = frame
end

local function addTouchTarget(button, maxSize)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(UiStyle.TOUCH_TARGET_MIN_PX, UiStyle.TOUCH_TARGET_MIN_PX)
	constraint.MaxSize = maxSize
	constraint.Parent = button
end

local function addAspect(frame, ratio)
	local constraint = Instance.new("UIAspectRatioConstraint")
	constraint.AspectRatio = ratio
	constraint.Parent = frame
end

local gui = Instance.new("ScreenGui")
gui.Name = "HUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = true

-- Diamonds wallet, top center (designer decision 2026-09-11); a button because
-- tapping it opens the store later
local diamondWallet = Instance.new("TextButton")
diamondWallet.Name = "DiamondWallet"
diamondWallet.AnchorPoint = Vector2.new(0.5, 0)
diamondWallet.Position = UDim2.fromScale(0.5, 0.03)
diamondWallet.Size = UDim2.fromScale(0.16, 0.07)
addTouchTarget(diamondWallet, Vector2.new(320, 72))
diamondWallet.BackgroundColor3 = UiStyle.PANEL_COLOR
diamondWallet.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
diamondWallet.BorderSizePixel = 0
diamondWallet.Text = ""
diamondWallet.AutoButtonColor = true
diamondWallet.Parent = gui
addCorner(diamondWallet)

-- the resource is its icon, never a word or a symbol (UI standard, 2026-09-24)
local diamondIcon = Instance.new("ImageLabel")
diamondIcon.Name = "Icon"
diamondIcon.Position = UDim2.fromScale(0.04, 0.1)
diamondIcon.Size = UDim2.fromScale(0.2, 0.8)
diamondIcon.BackgroundTransparency = 1
diamondIcon.Image = Icons.UI.DIAMONDS
diamondIcon.ScaleType = Enum.ScaleType.Fit
local diamondIconAspect = Instance.new("UIAspectRatioConstraint")
diamondIconAspect.AspectRatio = 1
diamondIconAspect.Parent = diamondIcon
diamondIcon.Parent = diamondWallet

local diamondsAmount = Instance.new("TextLabel")
diamondsAmount.Name = "DiamondAmount"
diamondsAmount.Position = UDim2.fromScale(0.26, 0.1)
diamondsAmount.Size = UDim2.fromScale(0.7, 0.8)
diamondsAmount.BackgroundTransparency = 1
diamondsAmount.Text = "0"
diamondsAmount.TextColor3 = UiStyle.TEXT_COLOR
diamondsAmount.TextXAlignment = Enum.TextXAlignment.Left
diamondsAmount.TextScaled = true
diamondsAmount.FontFace = UiStyle.BODY_BOLD_FONT
addTextSizeBounds(diamondsAmount, UiStyle.BODY_TEXT_MIN_PX, 32)
diamondsAmount.Parent = diamondWallet

-- Menu buttons, right edge, stacked
local menuButtons = Instance.new("Frame")
menuButtons.Name = "MenuButtons"
menuButtons.AnchorPoint = Vector2.new(1, 0.5)
menuButtons.Position = UDim2.fromScale(0.98, 0.5)
menuButtons.Size = UDim2.fromScale(0.12, 0.3)
addMaxSize(menuButtons, Vector2.new(220, 330))
menuButtons.BackgroundTransparency = 1
menuButtons.Parent = gui

local menuLayout = Instance.new("UIListLayout")
menuLayout.FillDirection = Enum.FillDirection.Vertical
menuLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
menuLayout.VerticalAlignment = Enum.VerticalAlignment.Center
menuLayout.Padding = UDim.new(0.05, 0)
menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
menuLayout.Parent = menuButtons

local menuButtonNames = {
	{ name = "StoreButton", text = "Store" },
	{ name = "CharacterButton", text = "Character" },
	{ name = "DailyRewardsButton", text = "Daily Rewards" },
}
for order, entry in menuButtonNames do
	local button = Instance.new("TextButton")
	button.Name = entry.name
	button.LayoutOrder = order
	button.Size = UDim2.fromScale(1, 0.3)
	addAspect(button, 2.4)
	button.BackgroundColor3 = UiStyle.PANEL_COLOR
	button.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
	button.BorderSizePixel = 0
	button.Text = UiStyle.formatTitle(entry.text)
	button.TextColor3 = UiStyle.ACCENT_COLOR
	button.TextScaled = true
	button.FontFace = UiStyle.TITLE_FONT
	addTextSizeBounds(button, UiStyle.BODY_TEXT_MIN_PX, 28)
	button.Parent = menuButtons
	addCorner(button)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.08, 0)
	padding.PaddingRight = UDim.new(0.08, 0)
	padding.PaddingTop = UDim.new(0.15, 0)
	padding.PaddingBottom = UDim.new(0.15, 0)
	padding.Parent = button
end

-- the jet pack fuel bar and touch button (the pack flies in the lobby as in
-- a run, designer 2026-10-12; ClientJetPackManager drives both). The bar
-- sits under the menu buttons on the right edge, level with where the
-- gameplay HUD keeps it; the button above Roblox's jump button, touch only
local jetBar = Instance.new("Frame")
jetBar.Name = "JetPackBar"
jetBar.AnchorPoint = Vector2.new(1, 0)
jetBar.Position = UDim2.fromScale(0.98, 0.68)
jetBar.Size = UDim2.fromScale(0.12, 0.05)
addAspect(jetBar, 4.4)
addMaxSize(jetBar, Vector2.new(260, 59))
jetBar.BackgroundColor3 = UiStyle.PANEL_COLOR
jetBar.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
jetBar.BorderSizePixel = 0
jetBar.Parent = gui
addCorner(jetBar)
local jetIcon = Instance.new("ImageLabel")
jetIcon.Name = "Icon"
jetIcon.Position = UDim2.fromScale(0.05, 0.1)
jetIcon.Size = UDim2.fromScale(0.2, 0.8)
jetIcon.BackgroundTransparency = 1
jetIcon.Image = ""
jetIcon.ScaleType = Enum.ScaleType.Fit
addAspect(jetIcon, 1)
jetIcon.Parent = jetBar
local jetTrack = Instance.new("Frame")
jetTrack.Name = "Track"
jetTrack.AnchorPoint = Vector2.new(0, 0.5)
jetTrack.Position = UDim2.fromScale(0.3, 0.5)
jetTrack.Size = UDim2.fromScale(0.65, 0.4)
jetTrack.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
jetTrack.BorderSizePixel = 0
jetTrack.Parent = jetBar
addCorner(jetTrack)
local jetFill = Instance.new("Frame")
jetFill.Name = "Fill"
jetFill.Size = UDim2.fromScale(1, 1)
jetFill.BackgroundColor3 = UiStyle.ACCENT_COLOR
jetFill.BorderSizePixel = 0
jetFill.Parent = jetTrack
addCorner(jetFill)

local jetButton = Instance.new("TextButton")
jetButton.Name = "JetPackButton"
jetButton.AnchorPoint = Vector2.new(1, 1)
jetButton.Position = UDim2.fromScale(0.98, 0.76)
jetButton.Size = UDim2.fromScale(0.08, 0.08)
addAspect(jetButton, 1)
addTouchTarget(jetButton, Vector2.new(130, 130))
jetButton.BackgroundColor3 = UiStyle.PANEL_COLOR
jetButton.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
jetButton.BorderSizePixel = 0
jetButton.Text = "JET"
jetButton.TextColor3 = UiStyle.TEXT_COLOR
jetButton.TextScaled = true
jetButton.FontFace = UiStyle.TITLE_FONT
jetButton.AutoButtonColor = true
jetButton.Visible = false
addTextSizeBounds(jetButton, UiStyle.LABEL_TEXT_MIN_PX, UiStyle.BODY_TEXT_MAX_PX)
jetButton.Parent = gui
local jetCorner = Instance.new("UICorner")
jetCorner.CornerRadius = UDim.new(0.5, 0)
jetCorner.Parent = jetButton

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("HUD gui")
return "HUD gui built"
