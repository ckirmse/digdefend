-- Builds the lobby's Starter Pack gui (M79) and its HUD button under Daily
-- Rewards. Run from the Studio command bar (or the MCP execute_luau tool)
-- in the lobby place, after build_daily_rewards_gui (it copies that
-- script's HUD button).
--
-- A FIRST PASS made from the designer's own pieces: the menu is a copy of
-- the DiamondStore gui (dialog, header band, X button, card, buy plate)
-- rearranged into three item cards over one buy button, and the HUD
-- button is a copy of DailyRewardsButton. The designer tunes both in the
-- Explorer afterwards, so this script REFUSES to run over an existing
-- copy: port the live gui's values into it and delete the old copy by
-- hand before any rerun.
--
-- Names must match Constants.STARTER_PACK_* and HUD_STARTER_PACK_BUTTON.
-- ClientStarterPackManager fills each card's Icon and Amount and the buy
-- button's Value (the struck-through worth) and Price.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local GUI_NAME = "StarterPack"
local HUD_BUTTON_NAME = "StarterPackButton"
-- a placeholder picture for the HUD button until it has its own art
local PACK_ICON = "rbxassetid://122502130840031"
local ROBUX_GLYPH = utf8.char(0xE002)
local VALUE_TEXT_COLOR = Color3.fromRGB(60, 52, 40)

local report = {}

local function buildMenu()
	if StarterGui:FindFirstChild(GUI_NAME) then
		table.insert(report, GUI_NAME .. " already exists: left alone (port it into this script and delete it to rebuild)")
		return
	end
	local source = StarterGui:FindFirstChild("DiamondStore")
	if not source then
		error("build_starter_pack_gui: no DiamondStore gui to copy the style from")
	end
	local gui = source:Clone() :: ScreenGui
	gui.Name = GUI_NAME
	gui.Enabled = false
	local dialog = gui:FindFirstChild("Dialog") :: Frame
	local groupReward = dialog:FindFirstChild("GroupReward")
	if groupReward then
		groupReward:Destroy()
	end
	((dialog:FindFirstChild("Header") :: Frame):FindFirstChild("Title") :: TextLabel).Text = "STARTER PACK"

	local items = dialog:FindFirstChild("Packs") :: Frame
	items.Name = "Items"
	items.Position = UDim2.fromScale(0.5, 0.14)
	items.Size = UDim2.fromScale(0.94, 0.62)
	local packTemplate = (items:FindFirstChild("PackTemplate") :: Instance):Clone() :: Frame
	for _, child in items:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local list = items:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder

	local buyButton = (packTemplate:FindFirstChild("EquipButton") :: Instance):Clone() :: ImageButton

	local function buildItem(name: string, order: number, text: string)
		local card = packTemplate:Clone()
		card.Name = name
		card.LayoutOrder = order
		card.Visible = true
		-- sized by the row's height, so three sit in the shorter row
		card.Size = UDim2.fromScale(0.24, 1)
		local aspect = card:FindFirstChildOfClass("UIAspectRatioConstraint") :: UIAspectRatioConstraint
		aspect.AspectRatio = 0.8
		aspect.DominantAxis = Enum.DominantAxis.Height
		aspect.AspectType = Enum.AspectType.FitWithinMaxSize;
		(card:FindFirstChild("Banner") :: Instance):Destroy();
		(card:FindFirstChild("EquipButton") :: Instance):Destroy()
		local icon = card:FindFirstChild("Icon") :: ImageLabel
		icon.Position = UDim2.fromScale(0.5, 0.42)
		icon.Size = UDim2.fromScale(0.7, 0.6)
		icon.ScaleType = Enum.ScaleType.Fit
		local label = card:FindFirstChild("Amount") :: TextLabel
		label.Position = UDim2.fromScale(0.5, 0.77)
		label.Size = UDim2.fromScale(0.9, 0.17)
		label.Text = text
		card.Parent = items
	end
	buildItem("ClassItem", 1, "GUNNER")
	buildItem("DiamondsItem", 2, "300")
	buildItem("CosmeticItem", 3, "PICK AXE SKIN")

	-- the buy plate: BUY, the worth struck through, and the real price
	buyButton.Name = "BuyButton"
	buyButton.AnchorPoint = Vector2.new(0.5, 1)
	buyButton.Position = UDim2.fromScale(0.5, 0.965)
	buyButton.Size = UDim2.fromScale(0.44, 0.15)
	local sizeConstraint = buyButton:FindFirstChildOfClass("UISizeConstraint")
	if sizeConstraint then
		sizeConstraint.MaxSize = Vector2.new(520, 90)
	end
	local buyLabel = buyButton:FindFirstChild("TextLabel") :: TextLabel
	buyLabel.AnchorPoint = Vector2.new(0, 0.5)
	buyLabel.Position = UDim2.fromScale(0.03, 0.5)
	buyLabel.Size = UDim2.fromScale(0.24, 0.8)
	buyLabel.Text = "BUY"
	local price = buyButton:FindFirstChild("Price") :: TextLabel
	price.AnchorPoint = Vector2.new(1, 0.5)
	price.Position = UDim2.fromScale(0.97, 0.5)
	price.Size = UDim2.fromScale(0.34, 0.74)
	price.Text = ROBUX_GLYPH .. "199"
	local value = price:Clone()
	value.Name = "Value"
	value.BackgroundTransparency = 1
	value.RichText = true
	value.TextColor3 = VALUE_TEXT_COLOR
	value.Position = UDim2.fromScale(0.6, 0.5)
	value.Size = UDim2.fromScale(0.3, 0.6)
	value.Text = "<s>" .. ROBUX_GLYPH .. "499</s>"
	value.Parent = buyButton
	buyButton.Parent = dialog

	gui.Parent = StarterGui
	table.insert(report, "built " .. GUI_NAME)
end

local function buildHudButton()
	local hud = StarterGui:FindFirstChild("HUD")
	local leftButtons = hud and hud:FindFirstChild("LeftButtons")
	local daily = leftButtons and leftButtons:FindFirstChild("DailyRewardsButton")
	if not leftButtons or not daily then
		error("build_starter_pack_gui: no HUD.LeftButtons.DailyRewardsButton; run build_daily_rewards_gui first")
	end
	if leftButtons:FindFirstChild(HUD_BUTTON_NAME) then
		table.insert(report, "HUD." .. HUD_BUTTON_NAME .. " already exists: left alone")
		return
	end
	local button = daily:Clone() :: TextButton
	button.Name = HUD_BUTTON_NAME
	local alert = button:FindFirstChild("Alert")
	if alert then
		alert:Destroy()
	end
	(button:FindFirstChild("TextLabel") :: TextLabel).Text = "STARTER"
	local icon = button:FindFirstChild("Icon") :: ImageLabel
	icon.Image = PACK_ICON
	icon.Rotation = 0
	-- under Daily Rewards
	local list = leftButtons:FindFirstChildOfClass("UIListLayout")
	if list then
		list.SortOrder = Enum.SortOrder.LayoutOrder
	end
	(daily :: GuiObject).LayoutOrder = 1
	button.LayoutOrder = 2
	button.Parent = leftButtons
	table.insert(report, "built HUD." .. HUD_BUTTON_NAME)
end

ChangeHistoryService:SetWaypoint("Before StarterPack gui")
buildMenu()
buildHudButton()
ChangeHistoryService:SetWaypoint("StarterPack gui")
return table.concat(report, "; ")
