-- Fills out the Mining Supplies Store in the map that is loaded in
-- Workspace (GDD "Mining Supplies Store"): PickAxeStand, authored by hand,
-- is the template; this script clones it into one "<Item>Stand" per
-- Enums.StoreItem that is missing, spaced along the store's back wall, and
-- normalises every stand's SurfaceGui to the names in Constants
-- (NameLabel, PriceBox, Price, ResourceIcon) and the UiStyle fonts. The
-- price pair stays centred through a UIListLayout with an auto-width
-- price. Run in the gameplay place with the map loaded (map_tools.luau
-- "load"), then save the map.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums = require(ReplicatedStorage.Shared.Enums)
local StoreRules = require(ReplicatedStorage.Shared.StoreRules)
local UiStyle = require(ReplicatedStorage.Shared.UiStyle)

local MAP_NAME = "DEADMANS_CANYON"
local TEMPLATE_ITEM = Enums.StoreItem.PICK_AXE
-- studs between stand centres along the wall
local STAND_SPACING_STUDS = 4.5

ChangeHistoryService:SetWaypoint("Before mining store stands")

local map = workspace:FindFirstChild(MAP_NAME)
assert(map, MAP_NAME .. " is not loaded in Workspace; run map_tools.luau with ACTION = \"load\" first")
local store = map:FindFirstChild(Constants.CAMP_MINING_STORE_MODEL)
assert(store, MAP_NAME .. " has no " .. Constants.CAMP_MINING_STORE_MODEL .. " model")
local template = store:FindFirstChild(StoreRules.standNameForItem(TEMPLATE_ITEM))
assert(template, "the store has no " .. StoreRules.standNameForItem(TEMPLATE_ITEM) .. " to clone")

local function normaliseGui(stand)
	local base = stand:FindFirstChild(Constants.STAND_BASE_PART)
	local gui = base and base:FindFirstChild(Constants.STAND_GUI)
	if not gui then
		warn("stand " .. stand.Name .. " has no Base.SurfaceGui")
		return
	end
	base.Anchored = true
	local nameLabel = gui:FindFirstChild(Constants.STAND_NAME_LABEL) or gui:FindFirstChild("Name")
	if nameLabel then
		nameLabel.Name = Constants.STAND_NAME_LABEL
		nameLabel.FontFace = UiStyle.TITLE_FONT
		nameLabel.TextColor3 = UiStyle.TEXT_COLOR
		nameLabel.TextScaled = true
	end
	local campLevel = gui:FindFirstChild(Constants.STAND_CAMP_LEVEL_LABEL)
	if campLevel then
		campLevel.FontFace = UiStyle.BODY_BOLD_FONT
		campLevel.TextScaled = true
	end
	local priceBox = gui:FindFirstChild(Constants.STAND_PRICE_BOX)
	if not priceBox then
		return
	end
	local layout = priceBox:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.04, 0)
	layout.Parent = priceBox
	local icon = priceBox:FindFirstChild(Constants.STAND_RESOURCE_ICON)
	if icon then
		icon.LayoutOrder = 1
		icon.AnchorPoint = Vector2.new(0, 0)
		icon.Position = UDim2.fromScale(0, 0)
		icon.Size = UDim2.fromScale(0.8, 0.8)
		icon.ScaleType = Enum.ScaleType.Fit
		local aspect = icon:FindFirstChildOfClass("UIAspectRatioConstraint") or Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1
		aspect.Parent = icon
	end
	local price = priceBox:FindFirstChild(Constants.STAND_PRICE_LABEL)
	if price then
		price.LayoutOrder = 2
		price.AnchorPoint = Vector2.new(0, 0)
		price.Position = UDim2.fromScale(0, 0)
		price.Size = UDim2.fromScale(0, 1)
		price.AutomaticSize = Enum.AutomaticSize.X
		price.TextScaled = false
		price.TextSize = math.max(12, math.floor(priceBox.AbsoluteSize.Y * 0.8))
		price.FontFace = UiStyle.BODY_BOLD_FONT
		price.TextColor3 = UiStyle.TEXT_COLOR
		price.TextXAlignment = Enum.TextXAlignment.Center
	end
end

-- new stands step sideways from the template along the store's right axis
local templateCFrame = template:GetPivot()
local right = templateCFrame.RightVector
local built = 0
local index = 0
for _, item in Enums.getAllValues(Enums.StoreItem) do
	local standName = StoreRules.standNameForItem(item)
	local stand = store:FindFirstChild(standName)
	if not stand then
		stand = template:Clone()
		stand.Name = standName
		stand:PivotTo(templateCFrame + right * (STAND_SPACING_STUDS * index))
		stand.Parent = store
		built += 1
	else
		-- an existing stand takes the template's slab and gui, keeping its own spot
		local base = stand:FindFirstChild(Constants.STAND_BASE_PART)
		local templateBase = template:FindFirstChild(Constants.STAND_BASE_PART)
		if base and templateBase and stand ~= template then
			base.Size = templateBase.Size
			base.CFrame = base.CFrame * CFrame.new(0, templateBase.Position.Y - base.Position.Y, 0)
			local oldGui = base:FindFirstChild(Constants.STAND_GUI)
			if oldGui then
				oldGui:Destroy()
			end
			local gui = templateBase:FindFirstChild(Constants.STAND_GUI)
			if gui then
				gui:Clone().Parent = base
			end
		end
	end
	normaliseGui(stand)
	local itemSpawn = stand:FindFirstChild(Constants.STAND_ITEM_SPAWN_PART)
	if itemSpawn then
		itemSpawn.Anchored = true
		itemSpawn.Transparency = 1
		itemSpawn.CanCollide = false
	end
	index += 1
end

ChangeHistoryService:SetWaypoint("After mining store stands")
print("build_mining_store_stands: built " .. built .. " new stand(s); " .. index .. " stands normalised under " .. store:GetFullName())
