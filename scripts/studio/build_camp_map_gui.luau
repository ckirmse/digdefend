-- Builds the "CampMap" ScreenGui under StarterGui (GDD "HUD", M33): a
-- square panel top right, shown at night, in which ClientCampMapManager
-- draws the camp from above: one clone of StructureTemplate per wall,
-- gate, and Refinery (coloured by health; black with a DestroyedMarkTemplate
-- clone, a red X, over it once rubble), one PlayerDotTemplate per crewmate (the local player's UIStroke
-- ring switched on), and a pool of MonsterDotTemplate clones. Run from the
-- Studio command bar (or the MCP execute_luau tool) in the gameplay place;
-- it replaces any existing copy. Names must match Constants.CAMP_MAP_*.
-- Scale only, constraints for the max, no pixel minimums (GUI standard).
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)
local Enums = require(game.ReplicatedStorage.Shared.Enums)

-- the square's side as a share of the screen HEIGHT, so it is the same
-- square at every aspect (designer, 2026-10-06, after a wide screen shrank
-- a width-sized map); it ends well above the right-edge stack
local ROOT_SIZE_SHARE = 0.285
local ROOT_MAX_PX = 320
-- the dots, as a share of the canvas height; raised 2026-10-06 so a
-- monster dot is 5 px on a phone's 106 px map, not 3
local PLAYER_DOT_SHARE = 0.09
local MONSTER_DOT_SHARE = 0.05

ChangeHistoryService:SetWaypoint("Before CampMap gui")

local existing = StarterGui:FindFirstChild("CampMap")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "CampMap"
gui.ResetOnSpawn = false
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- up to the very top of the screen, level with the day clock (designer, 2026-10-06)
gui.IgnoreGuiInset = true
gui.Enabled = false

local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(1, 0)
-- its top level with the top of the Refinery HP bar's track (designer,
-- 2026-10-06): that track sits 0.16 of the way down a box 0.012 from the
-- top, which lands between 0.034 and 0.040 of the height from phone to
-- ultrawide, so one scale value is within a hairline everywhere
root.Position = UDim2.fromScale(0.985, 0.036)
root.Size = UDim2.fromScale(ROOT_SIZE_SHARE, ROOT_SIZE_SHARE)
root.BackgroundColor3 = UiStyle.PANEL_COLOR
root.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
root.BorderSizePixel = 0
-- the client slides it in from the right edge at night
root.Visible = false
local rootAspect = Instance.new("UIAspectRatioConstraint")
rootAspect.AspectRatio = 1
rootAspect.DominantAxis = Enum.DominantAxis.Height
rootAspect.Parent = root
local rootSize = Instance.new("UISizeConstraint")
rootSize.MaxSize = Vector2.new(ROOT_MAX_PX, ROOT_MAX_PX)
rootSize.Parent = root
local rootCorner = Instance.new("UICorner")
rootCorner.CornerRadius = UDim.new(0, UiStyle.CORNER_RADIUS_PX)
rootCorner.Parent = root
local rootStroke = Instance.new("UIStroke")
rootStroke.Thickness = UiStyle.STROKE_PX
rootStroke.Color = UiStyle.ACCENT_STROKE_COLOR
rootStroke.Parent = root
root.Parent = gui

-- everything is drawn inside the canvas, which clips what falls off the map
local canvas = Instance.new("Frame")
canvas.Name = "Canvas"
canvas.AnchorPoint = Vector2.new(0.5, 0.5)
canvas.Position = UDim2.fromScale(0.5, 0.5)
canvas.Size = UDim2.fromScale(1, 1)
canvas.BackgroundTransparency = 1
canvas.BorderSizePixel = 0
canvas.ClipsDescendants = true
canvas.Parent = root

-- a structure: a plain box the client positions, sizes, turns, and colours
local structure = Instance.new("Frame")
structure.Name = "StructureTemplate"
structure.AnchorPoint = Vector2.new(0.5, 0.5)
structure.Position = UDim2.fromScale(0.5, 0.5)
structure.Size = UDim2.fromScale(0.2, 0.05)
structure.BackgroundColor3 = UiStyle.CAMP_MAP_BAND_COLORS[Enums.StructureHealthBand.FULL]
structure.BorderSizePixel = 0
structure.ZIndex = 1
structure.Visible = false
local structureStroke = Instance.new("UIStroke")
structureStroke.Thickness = UiStyle.STROKE_PX
structureStroke.Color = UiStyle.BACKGROUND_COLOR
structureStroke.Parent = structure
structure.Parent = canvas

-- "REFINERY" under the Refinery's box (designer, 2026-10-07): the one word
-- on the map, so which end is the camp is clear; the client places it
-- under the Refinery's box and shows it
local refineryLabel = Instance.new("TextLabel")
refineryLabel.Name = "RefineryLabel"
refineryLabel.AnchorPoint = Vector2.new(0.5, 0)
refineryLabel.Position = UDim2.fromScale(0.5, 0.9)
refineryLabel.Size = UDim2.fromScale(0.5, 0.075)
refineryLabel.BackgroundTransparency = 1
refineryLabel.FontFace = UiStyle.TITLE_FONT
refineryLabel.Text = UiStyle.formatTitle("Refinery")
refineryLabel.TextColor3 = UiStyle.TEXT_COLOR
refineryLabel.TextScaled = true
refineryLabel.ZIndex = 4
refineryLabel.Visible = false
local refineryTextSize = Instance.new("UITextSizeConstraint")
refineryTextSize.MinTextSize = UiStyle.LABEL_TEXT_MIN_PX
refineryTextSize.MaxTextSize = UiStyle.LABEL_TEXT_MAX_PX
refineryTextSize.Parent = refineryLabel
local refineryStroke = Instance.new("UIStroke")
refineryStroke.Thickness = UiStyle.STROKE_PX
refineryStroke.Color = UiStyle.BACKGROUND_COLOR
refineryStroke.Parent = refineryLabel
refineryLabel.Parent = canvas

-- the red X laid over a destroyed structure, unturned; the client clones
-- one per structure and shows it only then
local destroyed = Instance.new("TextLabel")
destroyed.Name = "DestroyedMarkTemplate"
destroyed.AnchorPoint = Vector2.new(0.5, 0.5)
destroyed.Position = UDim2.fromScale(0.5, 0.5)
destroyed.Size = UDim2.fromScale(0.09, 0.09)
destroyed.SizeConstraint = Enum.SizeConstraint.RelativeYY
destroyed.BackgroundTransparency = 1
destroyed.FontFace = UiStyle.TITLE_FONT
destroyed.Text = "X"
destroyed.TextColor3 = UiStyle.NEGATIVE_COLOR
destroyed.TextScaled = true
destroyed.ZIndex = 5
destroyed.Visible = false
local destroyedTextSize = Instance.new("UITextSizeConstraint")
destroyedTextSize.MinTextSize = UiStyle.LABEL_TEXT_MIN_PX
destroyedTextSize.MaxTextSize = UiStyle.TITLE_TEXT_MAX_PX
destroyedTextSize.Parent = destroyed
local destroyedStroke = Instance.new("UIStroke")
destroyedStroke.Thickness = UiStyle.STROKE_PX
destroyedStroke.Color = UiStyle.BACKGROUND_COLOR
destroyedStroke.Parent = destroyed
destroyed.Parent = canvas

local function makeDot(name, share, color, zIndex)
	local dot = Instance.new("Frame")
	dot.Name = name
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromScale(share, share)
	dot.SizeConstraint = Enum.SizeConstraint.RelativeYY
	dot.BackgroundColor3 = color
	dot.BorderSizePixel = 0
	dot.ZIndex = zIndex
	dot.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = dot
	return dot
end

-- a crewmate; the ring is enabled only on the local player's dot
-- every dot draws over the structures (1) and the destroyed marks (5)
local playerDot = makeDot("PlayerDotTemplate", PLAYER_DOT_SHARE, UiStyle.COMPASS_PLAYER_COLORS[1], 7)
local ring = Instance.new("UIStroke")
ring.Thickness = UiStyle.STROKE_PX
ring.Color = UiStyle.CAMP_MAP_LOCAL_PLAYER_RING_COLOR
ring.Enabled = false
ring.Parent = playerDot
playerDot.Parent = canvas

local monsterDot = makeDot("MonsterDotTemplate", MONSTER_DOT_SHARE, UiStyle.CAMP_MAP_MONSTER_COLOR, 6)
monsterDot.Parent = canvas

gui.Parent = StarterGui
ChangeHistoryService:SetWaypoint("After CampMap gui")
print("build_camp_map_gui: built " .. gui:GetFullName())
