-- Rebuilds the "DevTestMenu" ScreenGui under StarterGui: the stand-in
-- menu the admin dev panel opens to prove the overlay contract (HUD slides
-- away, world blurs, click outside closes) until the real menus exist
-- (M35+). ClientDevTools only enables and disables it. Run from the Studio
-- command bar (or the MCP execute_luau tool) in BOTH places; it replaces
-- any existing copy. Names must match Constants.DEV_TEST_MENU_*.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

ChangeHistoryService:SetWaypoint("Before DevTestMenu gui")

local existing = StarterGui:FindFirstChild("DevTestMenu")
if existing then
	existing:Destroy()
end

-- menus render above the overlay backdrop (ClientOverlayManager.MENU_DISPLAY_ORDER)
local MENU_DISPLAY_ORDER = 5

local gui = Instance.new("ScreenGui")
gui.Name = "DevTestMenu"
gui.ResetOnSpawn = false
gui.DisplayOrder = MENU_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

local frame = Instance.new("Frame")
frame.Name = "Dialog"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.Size = UDim2.fromScale(0.5, 0.5)
frame.BackgroundColor3 = UiStyle.PANEL_COLOR
frame.BorderSizePixel = 0
frame.Parent = gui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.fromScale(1, 0.3)
title.BackgroundTransparency = 1
title.Text = UiStyle.formatTitle("Test menu")
title.TextColor3 = UiStyle.ACCENT_COLOR
title.TextScaled = true
title.FontFace = UiStyle.TITLE_FONT
title.Parent = frame

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.Position = UDim2.fromScale(0, 0.4)
hint.Size = UDim2.fromScale(1, 0.2)
hint.BackgroundTransparency = 1
hint.Text = "Click outside to close"
hint.TextColor3 = UiStyle.TEXT_COLOR
hint.TextScaled = true
hint.FontFace = UiStyle.BODY_FONT
hint.Parent = frame

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After DevTestMenu gui")
print("build_dev_test_menu_gui: built StarterGui.DevTestMenu")
