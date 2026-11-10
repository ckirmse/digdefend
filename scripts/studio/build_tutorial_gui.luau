-- Rebuilds the "Tutorial" ScreenGui under StarterGui (M76, 2026-11-09): the
-- guide's dialogue box, the HUD arrow, and the Tasks panel of the
-- first-run walkthrough. The Dialog (the designer's layout of 2026-11-09:
-- centred under the day clock, the rough-edged panel backing picture
-- turned upside down behind it, no corner or stroke) holds the guide's
-- head on the left (a ViewportFrame ClientTutorialManager fills with the
-- GameAssets/Tutorial/GuideHead model), the line on the right, and a read
-- bar that drains while a line is up; there is no NEXT and no SKIP
-- (designer, 2026-11-09). The Tasks panel (designer, 2026-11-09) sits top
-- right under the same backing with a TRAINING TASKS header and the one
-- Task line, shown while a step waits on something the player must do.
-- The Arrow is one picture the manager parks beside whichever HUD
-- element the line points at, turned to face it and bobbing.
--
-- THE DESIGNER TUNES THIS GUI IN THE EXPLORER. Before running this
-- script on a place that already has the gui, dump the live instance and
-- port every difference here first (CLAUDE.md "GUI standard"); the
-- script destroys the old copy and an undo cannot bring it back.
--
-- Run from the Studio command bar (or the MCP execute_luau tool) in the
-- gameplay place; it replaces any existing copy. Names must match
-- Constants.TUTORIAL_*.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)
local Icons = require(game.ReplicatedStorage.Shared.Icons)

ChangeHistoryService:SetWaypoint("Before Tutorial gui")

local existing = StarterGui:FindFirstChild("Tutorial")
if existing then
	existing:Destroy()
end

-- above the HUD and the vignettes, below the menus (MENU_DISPLAY_ORDER is 5)
local TUTORIAL_DISPLAY_ORDER = 3
-- centred under the clock (which ends at 0.114 of the height)
local DIALOG_POSITION = UDim2.fromScale(0.5, 0.13)
local DIALOG_SIZE = UDim2.fromScale(0.6, 0.13)
local DIALOG_ASPECT_RATIO = 7.1
local DIALOG_MAX_SIZE = Vector2.new(720, 164)
-- the designer's backing picture: black at this transparency, turned
-- upside down so its rough edge sits along the bottom
local BACKING_TRANSPARENCY = 0.45
local BACKING_SLICE_CENTER = Rect.new(238, 207, 284, 278)
local BACKING_ROTATION = 180
local TASKS_POSITION = UDim2.fromScale(0.985, 0.03)
local TASKS_SIZE = UDim2.fromScale(0.2, 0.2)
-- the designer's font for the task line (GothamSSm, 2026-11-09)
local TASK_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular)
local ARROW_SIZE = UDim2.fromScale(0.05, 0.05)
local ARROW_MAX_PX = 72

local function addCorner(parent)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UiStyle.CORNER_RADIUS_PX)
	corner.Parent = parent
end

local function addTextSizeBounds(label, maxPx)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = UiStyle.BODY_TEXT_MIN_PX
	constraint.MaxTextSize = maxPx
	constraint.Parent = label
end

-- the panel backing picture filling its parent, behind the other children
local function addBacking(parent)
	local backing = Instance.new("ImageLabel")
	backing.Name = "Background"
	backing.Size = UDim2.fromScale(1, 1)
	backing.BackgroundTransparency = 1
	backing.BorderSizePixel = 0
	backing.Image = Icons.UI.PANEL_BACKING
	backing.ImageColor3 = Color3.new(0, 0, 0)
	backing.ImageTransparency = BACKING_TRANSPARENCY
	backing.ScaleType = Enum.ScaleType.Slice
	backing.SliceCenter = BACKING_SLICE_CENTER
	backing.Rotation = BACKING_ROTATION
	backing.ZIndex = 1
	backing.Parent = parent
	return backing
end

local gui = Instance.new("ScreenGui")
gui.Name = "Tutorial"
gui.ResetOnSpawn = false
gui.DisplayOrder = TUTORIAL_DISPLAY_ORDER
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- the whole screen, like the day clock's gui: the arrow must reach the
-- clock's badge, which sits in the top bar's band, and a gui that respects
-- the inset cannot draw there (its AbsolutePosition space starts under it)
gui.IgnoreGuiInset = true
gui.Enabled = false

local dialog = Instance.new("Frame")
dialog.Name = "Dialog"
dialog.AnchorPoint = Vector2.new(0.5, 0)
dialog.Position = DIALOG_POSITION
dialog.Size = DIALOG_SIZE
dialog.BackgroundColor3 = UiStyle.PANEL_COLOR
dialog.BackgroundTransparency = 1
dialog.BorderSizePixel = 0
dialog.Visible = false
local dialogAspect = Instance.new("UIAspectRatioConstraint")
dialogAspect.AspectRatio = DIALOG_ASPECT_RATIO
dialogAspect.DominantAxis = Enum.DominantAxis.Width
dialogAspect.Parent = dialog
local dialogSize = Instance.new("UISizeConstraint")
dialogSize.MaxSize = DIALOG_MAX_SIZE
dialogSize.Parent = dialog
addBacking(dialog)
dialog.Parent = gui

-- the guide's head, square, on the left
local portrait = Instance.new("ViewportFrame")
portrait.Name = "Portrait"
portrait.AnchorPoint = Vector2.new(0, 0.5)
portrait.Position = UDim2.fromScale(0.02, 0.5)
portrait.Size = UDim2.fromScale(0.3, 0.8)
portrait.BackgroundColor3 = UiStyle.BACKGROUND_COLOR
portrait.BackgroundTransparency = 0.3
portrait.BorderSizePixel = 0
portrait.ZIndex = 2
portrait.Ambient = Color3.fromRGB(160, 160, 160)
portrait.LightColor = Color3.fromRGB(255, 245, 225)
portrait.LightDirection = Vector3.new(-0.4, -1, 0.6)
local portraitAspect = Instance.new("UIAspectRatioConstraint")
portraitAspect.AspectRatio = 1
portraitAspect.DominantAxis = Enum.DominantAxis.Height
portraitAspect.Parent = portrait
portrait.Parent = dialog

local message = Instance.new("TextLabel")
message.Name = "Message"
message.AnchorPoint = Vector2.new(0, 0)
message.Position = UDim2.fromScale(0.145, 0.08)
message.Size = UDim2.fromScale(0.83, 0.78)
message.BackgroundTransparency = 1
message.ZIndex = 2
message.FontFace = UiStyle.BODY_FONT
message.Text = "Hello Miner!"
message.TextColor3 = UiStyle.TEXT_COLOR
message.TextScaled = true
message.TextWrapped = true
message.TextXAlignment = Enum.TextXAlignment.Left
message.TextYAlignment = Enum.TextYAlignment.Top
addTextSizeBounds(message, UiStyle.BODY_TEXT_MAX_PX)
message.Parent = dialog

-- drains left to right while a line is up for its reading time
local readBar = Instance.new("Frame")
readBar.Name = "ReadBar"
readBar.AnchorPoint = Vector2.new(0, 1)
readBar.Position = UDim2.fromScale(0.145, 0.9)
readBar.Size = UDim2.fromScale(0.83, 0.05)
readBar.BackgroundColor3 = UiStyle.ACCENT_COLOR
readBar.BackgroundTransparency = 0.3
readBar.BorderSizePixel = 0
readBar.ZIndex = 2
addCorner(readBar)
readBar.Parent = dialog

-- the one arrow, parked and turned by the manager; the picture points down
local arrow = Instance.new("ImageLabel")
arrow.Name = "Arrow"
arrow.AnchorPoint = Vector2.new(0.5, 0.5)
arrow.Position = UDim2.fromScale(0.5, 0.5)
arrow.Size = ARROW_SIZE
arrow.BackgroundTransparency = 1
arrow.Image = Icons.UI.TUTORIAL_ARROW
arrow.ImageColor3 = UiStyle.ACCENT_COLOR
arrow.ScaleType = Enum.ScaleType.Fit
arrow.Visible = false
local arrowAspect = Instance.new("UIAspectRatioConstraint")
arrowAspect.AspectRatio = 1
-- the width sets the height, so the square never shrinks to the height's share
arrowAspect.AspectType = Enum.AspectType.ScaleWithParentSize
arrowAspect.DominantAxis = Enum.DominantAxis.Width
arrowAspect.Parent = arrow
local arrowSize = Instance.new("UISizeConstraint")
arrowSize.MaxSize = Vector2.new(ARROW_MAX_PX, ARROW_MAX_PX)
arrowSize.Parent = arrow
arrow.Parent = gui

-- the Tasks panel, top right: the header and the one task line
local tasks = Instance.new("Frame")
tasks.Name = "Tasks"
tasks.AnchorPoint = Vector2.new(1, 0)
tasks.Position = TASKS_POSITION
tasks.Size = TASKS_SIZE
tasks.BackgroundColor3 = Color3.new(0, 0, 0)
tasks.BackgroundTransparency = 1
tasks.BorderSizePixel = 0
tasks.Visible = false
addBacking(tasks)

local header = Instance.new("TextLabel")
header.Name = "Header"
header.AnchorPoint = Vector2.new(0.5, 0)
header.Position = UDim2.fromScale(0.5, 0.05)
header.Size = UDim2.fromScale(0.95, 0.2)
header.BackgroundTransparency = 1
header.ZIndex = 2
header.FontFace = UiStyle.TITLE_FONT
header.Text = UiStyle.formatTitle("Training Tasks")
header.TextColor3 = UiStyle.ACCENT_COLOR
header.TextScaled = true
header.TextWrapped = true
header.Parent = tasks

local taskLabel = Instance.new("TextLabel")
taskLabel.Name = "Task"
taskLabel.AnchorPoint = Vector2.new(0.5, 0)
taskLabel.Position = UDim2.fromScale(0.5, 0.3)
taskLabel.Size = UDim2.fromScale(0.9, 0.6)
taskLabel.BackgroundTransparency = 1
taskLabel.ZIndex = 2
taskLabel.FontFace = TASK_FONT
taskLabel.Text = "- Mine ore until your backpack is full"
taskLabel.TextColor3 = UiStyle.TEXT_COLOR
taskLabel.TextScaled = true
taskLabel.TextWrapped = true
taskLabel.TextXAlignment = Enum.TextXAlignment.Center
taskLabel.TextYAlignment = Enum.TextYAlignment.Top
taskLabel.Parent = tasks
tasks.Parent = gui

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After Tutorial gui")
print("build_tutorial_gui: built StarterGui.Tutorial")
