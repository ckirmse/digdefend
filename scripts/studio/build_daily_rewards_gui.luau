-- Builds the lobby's Daily Rewards gui (GDD "Daily Rewards Menu", M39) and
-- the HUD's left-hand button stack. Run from the Studio command bar (or the
-- MCP execute_luau tool) in the lobby place.
--
-- It is a FIRST PASS made from the designer's own pieces, so it starts in
-- the live style: the menu is a copy of the DiamondStore gui (dialog,
-- header band, X button, card) rearranged into a grid of day tiles, and
-- the HUD stack is a copy of MenuButtons mirrored to the left edge. The
-- designer tunes both in the Explorer afterwards, so this script REFUSES
-- to run over an existing copy: port the live gui's values into it and
-- delete the old copy by hand before any rerun.
--
-- Names must match Constants.DAILY_REWARDS_* and Constants.HUD_LEFT_BUTTONS,
-- HUD_DAILY_REWARDS_BUTTON, HUD_BUTTON_ALERT. ClientDailyRewardManager
-- clones one of the three tile templates per day (locked, ready, claimed)
-- and fills DayLabel, Icon, and Amount; the templates stay hidden.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local GUI_NAME = "DailyRewards"
local LEFT_BUTTONS_NAME = "LeftButtons"
local DIAMONDS_ICON = "rbxassetid://101719152234191"
local LOCK_ICON = "rbxassetid://87535225906474"
-- two rows of four: 4 x 0.235 + 3 x 0.02 = 1 of the grid's width
local CELL_SIZE = UDim2.fromScale(0.235, 0.47)
local CELL_PADDING = UDim2.fromScale(0.02, 0.06)
local GREY_BAND_COLOR = Color3.fromRGB(70, 66, 61)
local MUTED_TEXT_COLOR = Color3.fromRGB(170, 165, 158)
local ALERT_COLOR = Color3.fromRGB(220, 60, 50)
-- below the chat window's reserved top-left region (GUI standard)
local LEFT_BUTTONS_POSITION = UDim2.fromScale(0.02, 0.3)

local report = {}

local function buildTile(packTemplate: Instance, name: string): Frame
	local tile = packTemplate:Clone() :: Frame
	tile.Name = name
	tile.Visible = false
	local aspect = tile:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspect then
		-- the grid sizes the tile
		aspect:Destroy()
	end
	local band = tile:FindFirstChild("Banner") :: Frame
	band.Name = "DayBand"
	band.Visible = true
	band.Size = UDim2.fromScale(1, 0.2)
	local dayLabel = band:FindFirstChild("Text") :: TextLabel
	dayLabel.Name = "DayLabel"
	dayLabel.Text = "DAY 1"
	local icon = tile:FindFirstChild("Icon") :: ImageLabel
	icon.Position = UDim2.fromScale(0.5, 0.43)
	icon.Size = UDim2.fromScale(0.5, 0.36)
	icon.ScaleType = Enum.ScaleType.Fit
	local amount = tile:FindFirstChild("Amount") :: TextLabel
	amount.Position = UDim2.fromScale(0.5, 0.61)
	amount.Size = UDim2.fromScale(0.9, 0.15)
	amount.Text = "10"
	local button = tile:FindFirstChild("EquipButton") :: ImageButton
	button.Name = "ClaimButton"
	button.Position = UDim2.fromScale(0.5, 0.97)
	button.Size = UDim2.fromScale(0.86, 0.19)
	local price = button:FindFirstChild("Price")
	if price then
		price:Destroy()
	end
	local buttonLabel = button:FindFirstChild("TextLabel") :: TextLabel
	buttonLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	buttonLabel.Position = UDim2.fromScale(0.5, 0.5)
	buttonLabel.Size = UDim2.fromScale(0.9, 0.8)
	buttonLabel.TextXAlignment = Enum.TextXAlignment.Center
	buttonLabel.Text = "CLAIM"
	return tile
end

-- the bottom line of a tile that has no button: a word or a picture
local function addStatus(tile: Frame, text: string): TextLabel
	local amount = tile:FindFirstChild("Amount") :: TextLabel
	local status = amount:Clone()
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.fromScale(0.5, 0.95)
	status.Size = UDim2.fromScale(0.86, 0.14)
	status.Text = text
	status.TextColor3 = MUTED_TEXT_COLOR
	status.Parent = tile
	return status
end

local function buildMenu()
	if StarterGui:FindFirstChild(GUI_NAME) then
		table.insert(report, GUI_NAME .. " already exists: left alone (port it into this script and delete it to rebuild)")
		return
	end
	local source = StarterGui:FindFirstChild("DiamondStore")
	if not source then
		error("build_daily_rewards_gui: no DiamondStore gui to copy the style from")
	end
	local gui = source:Clone() :: ScreenGui
	gui.Name = GUI_NAME
	gui.Enabled = false
	local dialog = gui:FindFirstChild("Dialog") :: Frame
	local groupReward = dialog:FindFirstChild("GroupReward")
	if groupReward then
		groupReward:Destroy()
	end
	local header = dialog:FindFirstChild("Header") :: Frame
	local title = header:FindFirstChild("Title") :: TextLabel
	title.Text = "DAILY REWARDS"

	local grid = dialog:FindFirstChild("Packs") :: Frame
	grid.Name = "TileGrid"
	grid.Position = UDim2.fromScale(0.5, 0.135)
	grid.Size = UDim2.fromScale(0.94, 0.72)
	local packTemplate = (grid:FindFirstChild("PackTemplate") :: Instance):Clone()
	grid:ClearAllChildren()
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = CELL_SIZE
	layout.CellPadding = CELL_PADDING
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.FillDirectionMaxCells = 4
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	-- ready: the designer's gold band and the CLAIM button, ringed in gold
	local ready = buildTile(packTemplate, "TileTemplateReady")
	local goldColor = (ready:FindFirstChild("DayBand") :: Frame).BackgroundColor3
	local stroke = Instance.new("UIStroke")
	stroke.Color = goldColor
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = ready
	ready.Parent = grid

	-- locked: a grey band and a lock where the button would be
	local locked = buildTile(packTemplate, "TileTemplate")
	local lockedBand = locked:FindFirstChild("DayBand") :: Frame
	lockedBand.BackgroundColor3 = GREY_BAND_COLOR;
	(lockedBand:FindFirstChild("DayLabel") :: TextLabel).TextColor3 = Color3.new(1, 1, 1);
	(locked:FindFirstChild("ClaimButton") :: Instance):Destroy()
	local lock = (locked:FindFirstChild("Icon") :: ImageLabel):Clone()
	lock.Name = "Lock"
	lock.Image = LOCK_ICON
	lock.AnchorPoint = Vector2.new(0.5, 1)
	lock.Position = UDim2.fromScale(0.5, 0.96)
	lock.Size = UDim2.fromScale(0.3, 0.16)
	lock.ImageColor3 = MUTED_TEXT_COLOR
	lock.Parent = locked
	locked.Parent = grid

	-- claimed: the same grey band, the reward faded, and the word
	local claimed = buildTile(packTemplate, "TileTemplateClaimed")
	local claimedBand = claimed:FindFirstChild("DayBand") :: Frame
	claimedBand.BackgroundColor3 = GREY_BAND_COLOR;
	(claimedBand:FindFirstChild("DayLabel") :: TextLabel).TextColor3 = MUTED_TEXT_COLOR;
	(claimed:FindFirstChild("ClaimButton") :: Instance):Destroy();
	(claimed:FindFirstChild("Icon") :: ImageLabel).ImageTransparency = 0.5;
	(claimed:FindFirstChild("Amount") :: TextLabel).TextTransparency = 0.5
	addStatus(claimed, "CLAIMED")
	claimed.Parent = grid

	-- the countdown line under the grid
	local nextReward = title:Clone()
	nextReward.Name = "NextReward"
	nextReward.AnchorPoint = Vector2.new(0.5, 1)
	nextReward.Position = UDim2.fromScale(0.5, 0.985)
	nextReward.Size = UDim2.fromScale(0.9, 0.07)
	nextReward.Text = "NEXT REWARD IN 23:59:59"
	nextReward.Parent = dialog

	gui.Parent = StarterGui
	table.insert(report, "built " .. GUI_NAME)
end

local function buildHudStack()
	local hud = StarterGui:FindFirstChild("HUD")
	if not hud then
		error("build_daily_rewards_gui: no HUD gui")
	end
	if hud:FindFirstChild(LEFT_BUTTONS_NAME) then
		table.insert(report, "HUD." .. LEFT_BUTTONS_NAME .. " already exists: left alone")
		return
	end
	local menuButtons = hud:FindFirstChild("MenuButtons") :: Frame
	local stack = menuButtons:Clone()
	stack.Name = LEFT_BUTTONS_NAME
	stack.AnchorPoint = Vector2.new(0, 0)
	stack.Position = LEFT_BUTTONS_POSITION
	local button: TextButton? = nil
	for _, child in stack:GetChildren() do
		if child:IsA("UIListLayout") then
			child.HorizontalAlignment = Enum.HorizontalAlignment.Left
		elseif child:IsA("GuiButton") then
			if child.Name == "StoreButton" then
				button = child :: TextButton
			else
				child:Destroy()
			end
		end
	end
	if not button then
		error("build_daily_rewards_gui: MenuButtons has no StoreButton to copy")
	end
	button.Name = "DailyRewardsButton"
	button.Visible = true;
	(button:FindFirstChild("TextLabel") :: TextLabel).Text = "DAILY";
	-- a placeholder picture until the button has its own art
	(button:FindFirstChild("Icon") :: ImageLabel).Image = DIAMONDS_ICON
	local glyph = button:FindFirstChild("GamepadGlyph")
	if glyph then
		glyph:Destroy()
	end

	-- the red mark shown while a reward is ready
	local alert = Instance.new("Frame")
	alert.Name = "Alert"
	alert.AnchorPoint = Vector2.new(1, 0)
	alert.Position = UDim2.fromScale(1.05, -0.05)
	alert.Size = UDim2.fromScale(0.34, 0.34)
	alert.BackgroundColor3 = ALERT_COLOR
	alert.BorderSizePixel = 0
	alert.ZIndex = 3
	alert.Visible = false
	local alertAspect = Instance.new("UIAspectRatioConstraint")
	alertAspect.AspectRatio = 1
	alertAspect.Parent = alert
	local alertCorner = Instance.new("UICorner")
	alertCorner.CornerRadius = UDim.new(0.5, 0)
	alertCorner.Parent = alert
	local mark = (button:FindFirstChild("TextLabel") :: TextLabel):Clone()
	mark.Name = "Mark"
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)
	mark.Size = UDim2.fromScale(0.8, 0.8)
	mark.Text = "!"
	mark.TextColor3 = Color3.new(1, 1, 1)
	mark.ZIndex = 4
	mark.Parent = alert
	alert.Parent = button

	stack.Parent = hud
	table.insert(report, "built HUD." .. LEFT_BUTTONS_NAME)
end

ChangeHistoryService:SetWaypoint("Before DailyRewards gui")
buildMenu()
buildHudStack()
ChangeHistoryService:SetWaypoint("DailyRewards gui")
return table.concat(report, "; ")
