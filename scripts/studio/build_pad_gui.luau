-- Rebuilds the "PadGui" BillboardGui on GuiPart of every helicopter pad under
-- Workspace.HelicopterPads. Run from the Studio command bar (or the MCP
-- execute_luau tool) in the lobby place; it replaces any existing copy. Label
-- names must match Constants.PAD_GUI_*; ClientPadBillboardManager fills the
-- text. Three stacked labels: Status (state line), Private (Public/Private,
-- hidden until a party exists), Players (count/size, always shown).
local Workspace = game:GetService("Workspace")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

local BILLBOARD_SIZE_STUDS = Vector2.new(20, 10)
local MAX_DISTANCE_STUDS = 1000

ChangeHistoryService:SetWaypoint("Before PadGui")

local function addLabel(parent: Instance, name: string, positionY: number, sizeY: number, font: Font, sampleText: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, positionY)
	label.Size = UDim2.fromScale(0.94, sizeY)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = sampleText
	label.TextColor3 = UiStyle.TEXT_COLOR
	label.FontFace = font
	label.Parent = parent
	return label
end

local function buildPadGui(guiPart: BasePart)
	local existing = guiPart:FindFirstChild("PadGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "PadGui"
	gui.Size = UDim2.fromScale(BILLBOARD_SIZE_STUDS.X, BILLBOARD_SIZE_STUDS.Y)
	gui.MaxDistance = MAX_DISTANCE_STUDS
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = UiStyle.PANEL_COLOR
	panel.BackgroundTransparency = UiStyle.PANEL_TRANSPARENCY
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UiStyle.CORNER_RADIUS_PX)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = UiStyle.STROKE_PX
	stroke.Color = UiStyle.ACCENT_STROKE_COLOR
	stroke.Parent = panel

	local status = addLabel(panel, "Status", 0.05, 0.25, UiStyle.TITLE_FONT, UiStyle.formatTitle("Waiting for players..."))
	status.TextColor3 = UiStyle.TEXT_MUTED_COLOR

	local private = addLabel(panel, "Private", 0.28, 0.15, UiStyle.BODY_BOLD_FONT, UiStyle.formatTitle("Public"))
	private.TextColor3 = UiStyle.TEXT_MUTED_COLOR
	private.Visible = false

	addLabel(panel, "Players", 0.45, 0.54, UiStyle.TITLE_FONT, "0/6")

	gui.Parent = guiPart
end

local padsFolder = Workspace:FindFirstChild("HelicopterPads")
if not padsFolder then
	error("Workspace.HelicopterPads not found; run this in the lobby place")
end

local builtCount = 0
for _, pad in padsFolder:GetChildren() do
	local guiPart = pad:FindFirstChild("GuiPart")
	if pad:IsA("Model") and guiPart and guiPart:IsA("BasePart") then
		buildPadGui(guiPart)
		builtCount += 1
	end
end

ChangeHistoryService:SetWaypoint("PadGui")
return "PadGui built on " .. builtCount .. " pads"
