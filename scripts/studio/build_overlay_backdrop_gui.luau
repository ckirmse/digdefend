-- Rebuilds the "OverlayBackdrop" ScreenGui under StarterGui: the invisible
-- full-screen button ClientOverlayManager enables under every menu. It
-- sinks input (world click handlers see it as gameProcessed), reports a
-- click outside the menu, and, being Modal, frees the first-person mouse
-- while a menu is up. Run from the Studio command bar (or the MCP
-- execute_luau tool) in BOTH places; it replaces any existing copy. Names
-- must match Constants.OVERLAY_BACKDROP_*. Invisible by design: the
-- designer may tint it (BackgroundTransparency) to dim the world under menus.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

ChangeHistoryService:SetWaypoint("Before OverlayBackdrop gui")

local existing = StarterGui:FindFirstChild("OverlayBackdrop")
if existing then
	existing:Destroy()
end

-- under the menus (ClientOverlayManager.MENU_DISPLAY_ORDER is 5), above the HUD (0)
local BACKDROP_DISPLAY_ORDER = 1

local gui = Instance.new("ScreenGui")
gui.Name = "OverlayBackdrop"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.DisplayOrder = BACKDROP_DISPLAY_ORDER
gui.Enabled = false

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 1
backdrop.BorderSizePixel = 0
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.Selectable = false
backdrop.Active = true
backdrop.Modal = true
backdrop.Parent = gui

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After OverlayBackdrop gui")
print("build_overlay_backdrop_gui: built StarterGui.OverlayBackdrop")
