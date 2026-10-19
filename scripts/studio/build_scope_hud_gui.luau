-- Rebuilds the "ScopeHud" ScreenGui under StarterGui: the Sniper Rifle's
-- scope view (2026-10-19). A full-screen overlay that ignores the top bar
-- inset: a centre square sized by the screen height carrying the scope
-- reticle image (ClientWeaponManager sets the picture from Icons by weapon
-- kind), with four black bars hung off its edges and running past the
-- screen on every side, so all a scoped player sees is what the reticle's
-- glass shows. Hidden until the scope is raised. Run from the Studio
-- command bar (or the MCP execute_luau tool) in the gameplay place; it
-- replaces any existing copy. Names must match Constants.SCOPE_HUD_*.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

ChangeHistoryService:SetWaypoint("Before ScopeHud gui")

local existing = StarterGui:FindFirstChild("ScopeHud")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "ScopeHud"
gui.ResetOnSpawn = false
-- under every HUD gui (which sit at 0), so the Refinery HP bar, the Camp
-- Map, and the post's charge bar still show over the glass (2026-10-19)
gui.DisplayOrder = -1
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

-- the glass: a square 0.72 of the screen's height (designer, 2026-10-19,
-- after a full-height and a half-height pass), its width from the aspect
-- constraint; the bars below cover everything round it
local reticle = Instance.new("ImageLabel")
reticle.Name = "Reticle"
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.Position = UDim2.fromScale(0.5, 0.5)
reticle.Size = UDim2.fromScale(1, 0.72)
reticle.BackgroundTransparency = 1
reticle.Image = ""
-- the reticle picture at half strength over the world (designer, 2026-10-19)
reticle.ImageTransparency = 0.5
reticle.ScaleType = Enum.ScaleType.Fit
reticle.Parent = gui
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = 1
aspect.DominantAxis = Enum.DominantAxis.Height
aspect.Parent = reticle

-- the bars: children of the glass, so each hangs off one of its edges in
-- scale and reaches well past the screen. The side bars run the full
-- height and the top and bottom bars only the glass's width, so no two
-- overlap: at half transparency a corner under two bars read darker
-- (seen 2026-10-19)
local BAR_REACH = 6
local function addBar(name, anchor, position, size)
	local bar = Instance.new("Frame")
	bar.Name = name
	bar.AnchorPoint = anchor
	bar.Position = position
	bar.Size = size
	bar.BackgroundColor3 = Color3.new(0, 0, 0)
	-- half strength, like the reticle picture (designer, 2026-10-19)
	bar.BackgroundTransparency = 0.5
	bar.BorderSizePixel = 0
	bar.ZIndex = 0
	bar.Parent = reticle
end
addBar("LeftBar", Vector2.new(1, 0.5), UDim2.fromScale(0, 0.5), UDim2.fromScale(BAR_REACH, BAR_REACH))
addBar("RightBar", Vector2.new(0, 0.5), UDim2.fromScale(1, 0.5), UDim2.fromScale(BAR_REACH, BAR_REACH))
addBar("TopBar", Vector2.new(0.5, 1), UDim2.fromScale(0.5, 0), UDim2.fromScale(1, BAR_REACH))
addBar("BottomBar", Vector2.new(0.5, 0), UDim2.fromScale(0.5, 1), UDim2.fromScale(1, BAR_REACH))

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After ScopeHud gui")
print("build_scope_hud_gui: built StarterGui.ScopeHud")
