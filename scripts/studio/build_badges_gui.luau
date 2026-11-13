-- Builds the lobby's Badges gui (GDD "Earning Diamonds", M69) and its HUD
-- button in the left-hand stack. Run from the Studio command bar (or the
-- MCP execute_luau tool) in the lobby place.
--
-- It is a FIRST PASS made from the designer's own pieces, so it starts in
-- the live style: the dialog, header band, and X button are a copy of the
-- DailyRewards gui; the scrolling list and the info panel are copies of
-- the KeyStore's; the claim button is a copy of the GroupRewardClaim
-- menu's; the HUD button is a copy of DailyRewardsButton. The designer
-- tunes all of it in the Explorer afterwards, so this script REFUSES to
-- run over an existing copy: port the live gui's values into it and delete
-- the old copy by hand before any rerun.
--
-- Names must match Constants.BADGES_* and Constants.HUD_BADGES_BUTTON.
-- ClientBadgeMenuManager clones BadgeTemplate once per badge and sets its
-- Icon, its Stars (Star1 to Star5, gold up to the badge's rating), and
-- which of ClaimBanner and Check shows; the info panel shows either
-- ClaimButton or RewardText in the same spot.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local GUI_NAME = "Badges"
local HUD_BUTTON_NAME = "BadgesButton"
local MAX_STARS = 5
local DIAMONDS_ICON = "rbxassetid://101719152234191"
local PLACEHOLDER_ICON = "rbxassetid://99730165827301"
local GOLD_COLOR = Color3.fromRGB(245, 200, 80)
local STAR_DARK_COLOR = Color3.fromRGB(27, 42, 53)
local CHECK_COLOR = Color3.fromRGB(90, 230, 100)
local TILE_COLOR = Color3.fromRGB(52, 48, 44)
-- five tiles a row: 5 x 0.17 + 4 x 0.02 + the list's 0.03 padding each side
local TILE_WIDTH_SCALE = 0.17
local TILE_GAP_SCALE = 0.02

local report = {}

local function find(parent: Instance, name: string): Instance
	local child = parent:FindFirstChild(name)
	if not child then
		error("build_badges_gui: " .. parent:GetFullName() .. " has no " .. name)
	end
	return child
end

-- a row of five star labels, sized by the row's height
local function buildStars(titleLabel: TextLabel): Frame
	local stars = Instance.new("Frame")
	stars.Name = "Stars"
	stars.BackgroundTransparency = 1
	stars.BorderSizePixel = 0
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = stars
	for index = 1, MAX_STARS do
		local star = titleLabel:Clone()
		star.Name = "Star" .. index
		star.LayoutOrder = index
		star.AnchorPoint = Vector2.zero
		star.Size = UDim2.fromScale(1 / MAX_STARS, 1)
		star.Text = "★"
		star.TextColor3 = if index <= 3 then GOLD_COLOR else STAR_DARK_COLOR
		star.TextXAlignment = Enum.TextXAlignment.Center
		star.Parent = stars
	end
	return stars
end

local function buildTile(itemTemplate: Instance, titleLabel: TextLabel): ImageButton
	local tile = itemTemplate:Clone() :: ImageButton
	tile.Name = "BadgeTemplate"
	tile.Visible = false
	tile.Size = UDim2.fromScale(TILE_WIDTH_SCALE, 0)
	tile.BackgroundColor3 = TILE_COLOR;
	(find(tile, "UIAspectRatioConstraint") :: UIAspectRatioConstraint).AspectRatio = 0.85;
	(find(tile, "Name") :: Instance):Destroy();
	(find(tile, "Owned") :: Instance):Destroy()

	local icon = find(tile, "Icon") :: ImageLabel
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.fromScale(0.5, 0.05)
	icon.Size = UDim2.fromScale(0.74, 0.66)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = PLACEHOLDER_ICON

	local stars = buildStars(titleLabel)
	stars.AnchorPoint = Vector2.new(0.5, 1)
	stars.Position = UDim2.fromScale(0.5, 0.97)
	stars.Size = UDim2.fromScale(0.9, 0.2)
	stars.Parent = tile

	-- earned, the reward waiting: a gold band across the picture
	local banner = Instance.new("Frame")
	banner.Name = "ClaimBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.4)
	banner.Size = UDim2.fromScale(1.04, 0.24)
	banner.Rotation = -8
	banner.BackgroundColor3 = GOLD_COLOR
	banner.BorderSizePixel = 0
	banner.ZIndex = 3
	local bannerText = titleLabel:Clone()
	bannerText.Name = "Text"
	bannerText.AnchorPoint = Vector2.new(0.5, 0.5)
	bannerText.Position = UDim2.fromScale(0.5, 0.5)
	bannerText.Size = UDim2.fromScale(0.9, 0.8)
	bannerText.Text = "CLAIM!"
	bannerText.TextColor3 = Color3.new(0, 0, 0)
	bannerText.ZIndex = 4
	bannerText.Parent = banner
	banner.Parent = tile

	-- claimed: a green disc with a check in the top right corner
	local check = Instance.new("Frame")
	check.Name = "Check"
	check.AnchorPoint = Vector2.new(1, 0)
	check.Position = UDim2.fromScale(0.97, 0.03)
	check.Size = UDim2.fromScale(0.28, 0.28)
	check.BackgroundColor3 = CHECK_COLOR
	check.BorderSizePixel = 0
	check.ZIndex = 3
	local checkAspect = Instance.new("UIAspectRatioConstraint")
	checkAspect.AspectRatio = 1
	checkAspect.Parent = check
	local checkCorner = Instance.new("UICorner")
	checkCorner.CornerRadius = UDim.new(0.5, 0)
	checkCorner.Parent = check
	local checkMark = titleLabel:Clone()
	checkMark.Name = "Mark"
	checkMark.AnchorPoint = Vector2.new(0.5, 0.5)
	checkMark.Position = UDim2.fromScale(0.5, 0.5)
	checkMark.Size = UDim2.fromScale(0.8, 0.8)
	checkMark.Text = "✓"
	checkMark.TextColor3 = Color3.new(0, 0, 0)
	checkMark.ZIndex = 4
	checkMark.Parent = check
	check.Parent = tile

	-- the tile whose details the info panel shows
	local selected = Instance.new("UIStroke")
	selected.Name = "Selected"
	selected.Color = GOLD_COLOR
	selected.Thickness = 3
	selected.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	selected.Enabled = false
	selected.Parent = tile
	return tile
end

local function buildMenu()
	if StarterGui:FindFirstChild(GUI_NAME) then
		table.insert(report, GUI_NAME .. " already exists: left alone (port it into this script and delete it to rebuild)")
		return
	end
	local gui = (find(StarterGui, "DailyRewards") :: ScreenGui):Clone()
	gui.Name = GUI_NAME
	gui.Enabled = false
	local dialog = find(gui, "Dialog") :: Frame
	local header = find(dialog, "Header") :: Frame
	local title = find(header, "Title") :: TextLabel
	title.Text = "BADGES";
	(find(dialog, "TileGrid") :: Instance):Destroy();
	(find(dialog, "NextReward") :: Instance):Destroy()

	local keyStoreDialog = find(find(StarterGui, "KeyStore"), "Dialog")

	local list = (find(keyStoreDialog, "ItemList") :: ScrollingFrame):Clone()
	list.Name = "BadgeList"
	list.AnchorPoint = Vector2.new(0, 1)
	list.Position = UDim2.fromScale(0.03, 0.96)
	list.Size = UDim2.fromScale(0.6, 0.81)
	local itemTemplate = find(list, "ItemTemplate")
	local listLayout = find(list, "UIListLayout") :: UIListLayout
	listLayout.Padding = UDim.new(TILE_GAP_SCALE, 0)
	local tile = buildTile(itemTemplate, title)
	itemTemplate:Destroy()
	tile.Parent = list
	list.Parent = dialog

	local sourcePanel = find(keyStoreDialog, "InfoPanel") :: Frame
	local panel = sourcePanel:Clone()
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.fromScale(0.97, 0.96)
	panel.Size = UDim2.fromScale(0.32, 0.81)
	local nameLabel = find(panel, "Name") :: TextLabel
	local bodyLabel = find(panel, "Slot") :: TextLabel
	local panelIcon = find(panel, "Icon") :: ImageLabel
	for _, child in panel:GetChildren() do
		if child ~= nameLabel and child ~= bodyLabel and child ~= panelIcon and not child:IsA("UICorner") then
			child:Destroy()
		end
	end
	nameLabel.Name = "Title"
	nameLabel.Position = UDim2.fromScale(0.5, 0.03)
	nameLabel.Size = UDim2.fromScale(0.92, 0.11)
	nameLabel.Text = "BADGE NAME"
	panelIcon.Position = UDim2.fromScale(0.5, 0.15)
	panelIcon.Size = UDim2.fromScale(0.5, 0.3)
	panelIcon.ScaleType = Enum.ScaleType.Fit
	panelIcon.Image = PLACEHOLDER_ICON
	local panelStars = buildStars(title)
	panelStars.AnchorPoint = Vector2.new(0.5, 0)
	panelStars.Position = UDim2.fromScale(0.5, 0.46)
	panelStars.Size = UDim2.fromScale(0.6, 0.08)
	panelStars.Parent = panel
	bodyLabel.Name = "Description"
	bodyLabel.Position = UDim2.fromScale(0.5, 0.56)
	bodyLabel.Size = UDim2.fromScale(0.88, 0.2)
	bodyLabel.TextWrapped = true
	bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
	bodyLabel.Text = "What the badge is earned for."

	-- the group reward menu's own button, so the two always match
	local claimButton = (find(find(find(StarterGui, "GroupRewardClaim"), "Frame"), "ClaimButton") :: TextButton):Clone()
	claimButton.AnchorPoint = Vector2.new(0.5, 1)
	claimButton.Position = UDim2.fromScale(0.5, 0.96)
	claimButton.Size = UDim2.fromScale(0.92, 0.15)
	claimButton.Visible = false
	claimButton.Parent = panel

	-- in the button's spot: "REWARD: 10 [diamond]", or COMPLETED with the
	-- picture hidden. The manager seats the picture after the words
	local rewardText = Instance.new("Frame")
	rewardText.Name = "RewardText"
	rewardText.AnchorPoint = Vector2.new(0.5, 1)
	rewardText.Position = UDim2.fromScale(0.5, 0.96)
	rewardText.Size = UDim2.fromScale(0.92, 0.15)
	rewardText.BackgroundTransparency = 1
	rewardText.BorderSizePixel = 0
	local rewardLabel = title:Clone()
	rewardLabel.Name = "Label"
	rewardLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	rewardLabel.Position = UDim2.fromScale(0.5, 0.5)
	rewardLabel.Size = UDim2.fromScale(0.8, 0.55)
	rewardLabel.Text = "REWARD: 10"
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Center
	rewardLabel.Parent = rewardText
	local diamondIcon = Instance.new("ImageLabel")
	diamondIcon.Name = "DiamondIcon"
	diamondIcon.AnchorPoint = Vector2.new(0, 0.5)
	diamondIcon.Position = UDim2.fromScale(0.8, 0.5)
	diamondIcon.Size = UDim2.fromScale(0.2, 0.6)
	diamondIcon.BackgroundTransparency = 1
	diamondIcon.Image = DIAMONDS_ICON
	diamondIcon.ScaleType = Enum.ScaleType.Fit
	local diamondAspect = Instance.new("UIAspectRatioConstraint")
	diamondAspect.AspectRatio = 1
	diamondAspect.Parent = diamondIcon
	diamondIcon.Parent = rewardText
	rewardText.Parent = panel
	panel.Parent = dialog

	gui.Parent = StarterGui
	table.insert(report, "built " .. GUI_NAME)
end

local function buildHudButton()
	local leftButtons = find(find(StarterGui, "HUD"), "LeftButtons")
	if leftButtons:FindFirstChild(HUD_BUTTON_NAME) then
		table.insert(report, "HUD.LeftButtons." .. HUD_BUTTON_NAME .. " already exists: left alone")
		return
	end
	local lastOrder = 0
	for _, child in leftButtons:GetChildren() do
		if child:IsA("GuiObject") then
			lastOrder = math.max(lastOrder, child.LayoutOrder)
		end
	end
	local button = (find(leftButtons, "DailyRewardsButton") :: TextButton):Clone()
	button.Name = HUD_BUTTON_NAME
	button.LayoutOrder = lastOrder + 1
	button.Visible = true;
	(find(button, "TextLabel") :: TextLabel).Text = "BADGES";
	(find(button, "Icon") :: ImageLabel).Rotation = 0;
	(find(button, "Alert") :: Frame).Visible = false
	button.Parent = leftButtons
	table.insert(report, "built HUD.LeftButtons." .. HUD_BUTTON_NAME)
end

ChangeHistoryService:SetWaypoint("Before Badges gui")
buildMenu()
buildHudButton()
ChangeHistoryService:SetWaypoint("Badges gui")
return table.concat(report, "; ")
