-- Rebuilds the "ResultsMenu" ScreenGui under StarterGui (GDD "Results
-- Menu", M32): a dialog with a title ("YOU DIED", "RUN WON", "RUN LOST"),
-- six stat rows (Uranium refined, Cash earned, Gold refined, Iron refined,
-- enemies killed, damage given; the resource rows carry the icon after
-- their words; nights survived is on the grave, not here), each with its
-- number and, under a "GROUP RANK" header, the player's place in the crew
-- for it (the header and the places are hidden for a solo player, and the
-- numbers move to the right edge), a countdown line, and three buttons that
-- ClientReviveManager shows as needed: Revive (its label and Robux price),
-- Spectate, and Close. The dialog fills the left of the screen from its
-- edge: a dead player's camera stands at their grave (the Grave
-- template's CameraLocation), the stone shows to the right of the menu,
-- and the HUD is hidden while they are dead. Run
-- from the Studio command bar (or the MCP
-- execute_luau tool) in the gameplay place; it replaces any existing copy.
-- Names must match Constants.RESULTS_MENU_*. Layout follows the GUI
-- standard in CLAUDE.md; fonts and colours come from Shared/UiStyle.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before ResultsMenu gui")

local existing = StarterGui:FindFirstChild("ResultsMenu")
if existing then
	existing:Destroy()
end

-- menus render above the overlay backdrop (ClientOverlayManager.MENU_DISPLAY_ORDER)
local MENU_DISPLAY_ORDER = 5

local STAT_ROWS = {
	{ name = "UraniumRefined", text = "Uranium refined", hasIcon = true },
	{ name = "CashEarned", text = "Cash earned", hasIcon = true },
	{ name = "GoldRefined", text = "Gold refined", hasIcon = true },
	{ name = "IronRefined", text = "Iron refined", hasIcon = true },
	{ name = "EnemiesKilled", text = "Enemies killed", hasIcon = false },
	{ name = "DamageGiven", text = "Damage given", hasIcon = false },
}

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

local function makeLabel(name, text, font, color, minPx, maxPx)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.FontFace = font
	label.TextTruncate = Enum.TextTruncate.AtEnd
	addTextSizeBounds(label, minPx, maxPx)
	return label
end

local function makeButton(name, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = true
	addCorner(button)
	return button
end

local gui = Instance.new("ScreenGui")
gui.Name = "ResultsMenu"
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

local dialog = Instance.new("Frame")
dialog.Name = "Dialog"
dialog.AnchorPoint = Vector2.new(0, 0.5)
dialog.Position = UDim2.fromScale(0.035, 0.5)
-- taller since the sixth row (2026-10-05): every part below is sized so
-- the rows and their text are as big as they were with five
dialog.Size = UDim2.fromScale(0.415, 0.875)
addMaxSize(dialog, Vector2.new(900, 1000))
dialog.BackgroundColor3 = UiStyle.PANEL_COLOR
dialog.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
dialog.BorderSizePixel = 0
dialog.Parent = gui
addCorner(dialog)
local dialogStroke = Instance.new("UIStroke")
dialogStroke.Thickness = UiStyle.STROKE_PX
dialogStroke.Color = UiStyle.ACCENT_STROKE_COLOR
dialogStroke.Parent = dialog

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0.06, 0)
padding.PaddingRight = UDim.new(0.06, 0)
padding.PaddingTop = UDim.new(0.03, 0)
padding.PaddingBottom = UDim.new(0.04, 0)
padding.Parent = dialog

-- the menu is read at a glance by someone who has just died, so its text
-- runs larger than the body sizes in UiStyle
local STAT_TEXT_MAX_PX = 56
local title = makeLabel("Title", UiStyle.formatTitle("You died"), UiStyle.TITLE_FONT, UiStyle.ACCENT_COLOR, UiStyle.TITLE_TEXT_MIN_PX, 64)
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.fromScale(0.5, 0)
title.Size = UDim2.fromScale(1, 0.091)
title.Parent = dialog

-- the crew column's header, over the right end of the rows
local rankHeader = makeLabel("RankHeader", UiStyle.formatTitle("Group Rank"), UiStyle.TITLE_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.LABEL_TEXT_MIN_PX, 28)
rankHeader.AnchorPoint = Vector2.new(1, 0)
rankHeader.Position = UDim2.fromScale(1, 0.091)
rankHeader.Size = UDim2.fromScale(0.3, 0.037)
rankHeader.TextXAlignment = Enum.TextXAlignment.Center
rankHeader.Parent = dialog

local stats = Instance.new("Frame")
stats.Name = "Stats"
stats.AnchorPoint = Vector2.new(0.5, 0)
stats.Position = UDim2.fromScale(0.5, 0.133)
stats.Size = UDim2.fromScale(1, 0.51)
stats.BackgroundTransparency = 1
stats.Parent = dialog

local statsLayout = Instance.new("UIListLayout")
statsLayout.FillDirection = Enum.FillDirection.Vertical
statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
statsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
statsLayout.Padding = UDim.new(0.02, 0)
statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
statsLayout.Parent = stats

for order, definition in STAT_ROWS do
	local row = Instance.new("Frame")
	row.Name = definition.name
	row.LayoutOrder = order
	-- six rows and five gaps fill the stats frame
	row.Size = UDim2.fromScale(1, 0.15)
	row.BackgroundColor3 = UiStyle.EMPTY_SLOT_COLOR
	row.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
	row.BorderSizePixel = 0
	row.Parent = stats
	addCorner(row)
	local rowPadding = Instance.new("UIPadding")
	rowPadding.PaddingLeft = UDim.new(0.04, 0)
	rowPadding.PaddingRight = UDim.new(0.04, 0)
	rowPadding.Parent = row

	local name = makeLabel("Name", definition.text, UiStyle.BODY_FONT, UiStyle.TEXT_MUTED_COLOR, UiStyle.BODY_TEXT_MIN_PX, STAT_TEXT_MAX_PX)
	name.AnchorPoint = Vector2.new(0, 0.5)
	name.Position = UDim2.fromScale(0, 0.5)
	name.Size = UDim2.fromScale(0.5, 0.84)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local value = makeLabel("Value", "0", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MIN_PX, STAT_TEXT_MAX_PX)
	-- left of the crew column; ClientReviveManager moves it to the right
	-- edge for a solo player, who has no crew column
	value.AnchorPoint = Vector2.new(1, 0.5)
	value.Position = UDim2.fromScale(0.72, 0.5)
	value.Size = UDim2.fromScale(0.22, 0.84)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Parent = row

	local rank = makeLabel("Rank", "1st", UiStyle.BODY_BOLD_FONT, UiStyle.ACCENT_COLOR, UiStyle.BODY_TEXT_MIN_PX, STAT_TEXT_MAX_PX)
	rank.AnchorPoint = Vector2.new(1, 0.5)
	rank.Position = UDim2.fromScale(1, 0.5)
	rank.Size = UDim2.fromScale(0.24, 0.84)
	rank.TextXAlignment = Enum.TextXAlignment.Center
	rank.Parent = row

	if definition.hasIcon then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		-- right after the row's name; ClientReviveManager moves it to the
		-- end of the words, wherever they end at this screen size
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.fromScale(0.45, 0.5)
		icon.Size = UDim2.fromScale(0.1, 0.8)
		local iconAspect = Instance.new("UIAspectRatioConstraint")
		iconAspect.AspectRatio = 1
		iconAspect.Parent = icon
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = row
	end
end

local countdown = makeLabel("Countdown", "Revive available for 60 s", UiStyle.BODY_BOLD_FONT, UiStyle.TEXT_COLOR, UiStyle.BODY_TEXT_MIN_PX, STAT_TEXT_MAX_PX)
countdown.AnchorPoint = Vector2.new(0.5, 0)
countdown.Position = UDim2.fromScale(0.5, 0.652)
countdown.Size = UDim2.fromScale(1, 0.073)
countdown.TextTruncate = Enum.TextTruncate.None
countdown.Parent = dialog

local reviveButton = makeButton("ReviveButton", UiStyle.POSITIVE_COLOR)
reviveButton.AnchorPoint = Vector2.new(0.5, 0)
reviveButton.Position = UDim2.fromScale(0.5, 0.743)
reviveButton.Size = UDim2.fromScale(1, 0.119)
addTouchTarget(reviveButton, Vector2.new(860, 200))
reviveButton.Parent = dialog

local reviveLabel = makeLabel("Label", UiStyle.formatTitle("Revive"), UiStyle.TITLE_FONT, UiStyle.ACCENT_STROKE_COLOR, UiStyle.LABEL_TEXT_MIN_PX, 44)
reviveLabel.AnchorPoint = Vector2.new(0, 0.5)
reviveLabel.Position = UDim2.fromScale(0.04, 0.5)
reviveLabel.Size = UDim2.fromScale(0.66, 0.7)
reviveLabel.TextXAlignment = Enum.TextXAlignment.Left
reviveLabel.TextTruncate = Enum.TextTruncate.None
reviveLabel.Parent = reviveButton

-- the Robux mark is a glyph in Roblox's own fonts, so the price is one label
local revivePrice = makeLabel("Price", "\u{E002} 0", UiStyle.BODY_BOLD_FONT, UiStyle.ACCENT_STROKE_COLOR, UiStyle.LABEL_TEXT_MIN_PX, 44)
revivePrice.AnchorPoint = Vector2.new(1, 0.5)
revivePrice.Position = UDim2.fromScale(0.96, 0.5)
revivePrice.Size = UDim2.fromScale(0.26, 0.7)
revivePrice.TextXAlignment = Enum.TextXAlignment.Right
revivePrice.Parent = reviveButton

local spectateButton = makeButton("SpectateButton", UiStyle.ACCENT_COLOR)
spectateButton.AnchorPoint = Vector2.new(0.5, 1)
spectateButton.Position = UDim2.fromScale(0.5, 1)
spectateButton.Size = UDim2.fromScale(1, 0.1)
addTouchTarget(spectateButton, Vector2.new(860, 100))
spectateButton.Parent = dialog

local spectateLabel = makeLabel("Label", UiStyle.formatTitle("Spectate"), UiStyle.TITLE_FONT, UiStyle.ACCENT_STROKE_COLOR, UiStyle.LABEL_TEXT_MIN_PX, 40)
spectateLabel.AnchorPoint = Vector2.new(0.5, 0.5)
spectateLabel.Position = UDim2.fromScale(0.5, 0.5)
spectateLabel.Size = UDim2.fromScale(0.9, 0.7)
spectateLabel.Parent = spectateButton

-- the end of a run: the same place as Spectate, one or the other is shown
local closeButton = makeButton("CloseButton", UiStyle.ACCENT_COLOR)
closeButton.AnchorPoint = Vector2.new(0.5, 1)
closeButton.Position = UDim2.fromScale(0.5, 1)
closeButton.Size = UDim2.fromScale(1, 0.1)
addTouchTarget(closeButton, Vector2.new(860, 100))
closeButton.Visible = false
closeButton.Parent = dialog

local closeLabel = makeLabel("Label", UiStyle.formatTitle("Return to Lobby"), UiStyle.TITLE_FONT, UiStyle.ACCENT_STROKE_COLOR, UiStyle.LABEL_TEXT_MIN_PX, 40)
closeLabel.AnchorPoint = Vector2.new(0.5, 0.5)
closeLabel.Position = UDim2.fromScale(0.5, 0.5)
closeLabel.Size = UDim2.fromScale(0.9, 0.7)
closeLabel.Parent = closeButton

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After ResultsMenu gui")
print("build_results_menu_gui: built StarterGui.ResultsMenu")
