-- Rebuilds the "ScreenFade" ScreenGui under StarterGui: one full-screen
-- black frame, invisible until ClientReviveManager fades it in over the
-- Game Over screen and out again over the Results Menu (GDD "Health and
-- Revives", M32). It covers the whole screen, notch and home-bar areas
-- included, and sits above the menus and below the feedback text. Run
-- from the Studio command bar (or the MCP execute_luau tool) in the
-- gameplay place; it replaces any existing copy. Names must match
-- Constants.SCREEN_FADE_*.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

ChangeHistoryService:SetWaypoint("Before ScreenFade gui")

local existing = StarterGui:FindFirstChild("ScreenFade")
if existing then
	existing:Destroy()
end

-- above the menus (ClientOverlayManager.MENU_DISPLAY_ORDER is 5), below
-- the PlayerFeedback text (500)
local FADE_DISPLAY_ORDER = 100

local gui = Instance.new("ScreenGui")
gui.Name = "ScreenFade"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.DisplayOrder = FADE_DISPLAY_ORDER
gui.Enabled = false

local black = Instance.new("Frame")
black.Name = "Black"
black.Size = UDim2.fromScale(1, 1)
black.BackgroundColor3 = Color3.new(0, 0, 0)
black.BackgroundTransparency = 1
black.BorderSizePixel = 0
black.Parent = gui

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After ScreenFade gui")
print("build_screen_fade_gui: built StarterGui.ScreenFade")
