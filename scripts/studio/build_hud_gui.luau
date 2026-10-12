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
	{ name = "LoadoutButton", text = "Loadout" },
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

gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("HUD gui")
return "HUD gui built"
