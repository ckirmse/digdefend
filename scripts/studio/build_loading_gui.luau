-- Rebuilds the "Loading" ScreenGui under ReplicatedFirst. Run from the Studio
-- command bar (or the MCP execute_luau tool) in either place; it replaces any
-- existing copy. Names must match Constants.LOADING_* and
-- src/first/loading.client.luau. Layout rule: scale for position and size,
-- UIAspectRatioConstraint where shape matters, UISizeConstraint /
-- UITextSizeConstraint to keep phones readable and 4K sane, offset only for
-- hairlines (strokes, corners, padding). Colours are provisional until M10.
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

ChangeHistoryService:SetWaypoint("Before Loading gui")

local existing = ReplicatedFirst:FindFirstChild("Loading")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "Loading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 10000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.fromScale(1, 1)
main.Position = UDim2.fromScale(0, 0)
main.BackgroundColor3 = Color3.fromRGB(18, 16, 14)
main.BorderSizePixel = 0
main.Parent = gui

local titleImage = Instance.new("ImageLabel")
titleImage.Name = "TitleImage"
titleImage.AnchorPoint = Vector2.new(0.5, 0.5)
titleImage.Position = UDim2.fromScale(0.5, 0.38)
titleImage.Size = UDim2.fromScale(0.5, 0.3)
titleImage.BackgroundTransparency = 1
local titleImageAspect = Instance.new("UIAspectRatioConstraint")
titleImageAspect.AspectRatio = 3
titleImageAspect.Parent = titleImage
titleImage.Image = ""
titleImage.ScaleType = Enum.ScaleType.Fit
titleImage.Visible = false
titleImage.Parent = main

local titleText = Instance.new("TextLabel")
titleText.Name = "TitleText"
titleText.AnchorPoint = Vector2.new(0.5, 0.5)
titleText.Position = UDim2.fromScale(0.5, 0.38)
titleText.Size = UDim2.fromScale(0.8, 0.18)
titleText.BackgroundTransparency = 1
local titleTextSize = Instance.new("UITextSizeConstraint")
titleTextSize.MinTextSize = 32
titleTextSize.MaxTextSize = 110
titleTextSize.Parent = titleText
titleText.Text = "DIG DEFEND"
titleText.TextColor3 = Color3.fromRGB(245, 200, 80)
titleText.TextScaled = true
titleText.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
titleText.Parent = main

local titleStroke = Instance.new("UIStroke")
titleStroke.Thickness = 3
titleStroke.Color = Color3.fromRGB(60, 35, 10)
titleStroke.Parent = titleText

local progressBar = Instance.new("Frame")
progressBar.Name = "ProgressBar"
progressBar.AnchorPoint = Vector2.new(0.5, 0.5)
progressBar.Position = UDim2.fromScale(0.5, 0.64)
progressBar.Size = UDim2.fromScale(0.5, 0.03)
local progressBarSize = Instance.new("UISizeConstraint")
progressBarSize.MinSize = Vector2.new(240, 14)
progressBarSize.MaxSize = Vector2.new(640, 26)
progressBarSize.Parent = progressBar
progressBar.BackgroundColor3 = Color3.fromRGB(50, 46, 42)
progressBar.BorderSizePixel = 0
progressBar.Parent = main

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 8)
barCorner.Parent = progressBar

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.fromRGB(245, 200, 80)
fill.BorderSizePixel = 0
fill.Parent = progressBar

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 8)
fillCorner.Parent = fill

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 0)
status.Position = UDim2.fromScale(0.5, 0.675)
status.Size = UDim2.fromScale(0.5, 0.045)
status.BackgroundTransparency = 1
local statusTextSize = Instance.new("UITextSizeConstraint")
statusTextSize.MinTextSize = 14
statusTextSize.MaxTextSize = 26
statusTextSize.Parent = status
status.Text = "LOADING"
status.TextColor3 = Color3.fromRGB(220, 215, 205)
status.TextScaled = true
status.FontFace = Font.fromEnum(Enum.Font.GothamMedium)
status.Parent = main

gui.Parent = ReplicatedFirst

ChangeHistoryService:SetWaypoint("Loading gui")
return "Loading gui built"
