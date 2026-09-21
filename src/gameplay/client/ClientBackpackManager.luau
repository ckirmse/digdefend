--!strict

-- The backpack on this client (GDD "Mining Rock", "Collecting Ore"): the HUD
-- button with "taken/total", red and "Backpack full" when there is no room,
-- always shown (decided 2026-09-15); the pop sound when ore is collected;
-- and the contents menu (an overlay) listing only the ores carried. All
-- numbers come from the CurrentPlayer attributes BackpackManager writes.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local BackpackRules = require("@game/ReplicatedStorage/Shared/BackpackRules")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientIconFlightManager = require(script.Parent.ClientIconFlightManager)

local ClientBackpackManager = {}
ClientBackpackManager.__index = ClientBackpackManager

export type ClientBackpackManager = typeof(setmetatable(
	{} :: {
		hudGui: ScreenGui?,
		button: GuiButton?,
		countLabel: TextLabel?,
		fullLabel: TextLabel?,
		buttonBasePosition: UDim2?,
		-- the total shown while icons are in flight; nil shows the attributes
		heldTotal: number?,
		flightsInProgress: number,
		menuGui: ScreenGui?,
		menuDialog: Frame?,
		list: Frame?,
		rowTemplate: Frame?,
		emptyLabel: TextLabel?,
		rows: { Frame },
		overlay: ClientOverlayManager.Overlay?,
		isMenuOpen: boolean,
		-- so the fail sound plays once, on the change to full
		wasFull: boolean,
	},
	ClientBackpackManager
))

local NOTIFY_ORE_COLLECTED_SHAPE = {
	resource = { type = "enum", name = "RawResource" },
	amount = "positiveInteger",
	-- where the ore came from: the broken block's centre or the pickup
	position = "vector3",
}

-- icons per collection, so a rich block does not spawn fifty
local MAX_ICONS_PER_COLLECTION = 6
local ICON_STAGGER_SEC = 0.08
-- fallback disc colours for any resource whose Icons entry is still the placeholder
local COLOR_BY_RAW: { [number]: Color3 } = {
	[Enums.RawResource.IRON_ORE] = Color3.fromRGB(120, 125, 135),
	[Enums.RawResource.GOLD_ORE] = Color3.fromRGB(200, 160, 40),
	[Enums.RawResource.CRYSTAL] = Color3.fromRGB(150, 220, 255),
	[Enums.RawResource.URANIUM_ORE] = Color3.fromRGB(90, 200, 70),
}

local COUNT_FORMAT = "%d/%d"
-- listed in a fixed order so the menu does not reshuffle as ore arrives
local RESOURCE_ORDER = {
	Enums.RawResource.IRON_ORE,
	Enums.RawResource.GOLD_ORE,
	Enums.RawResource.CRYSTAL,
	Enums.RawResource.URANIUM_ORE,
}

local function readNumber(key: string): number
	local value = ClientDataManager:getCurrentPlayerAttribute(key)
	return if typeof(value) == "number" then value else 0
end

function ClientBackpackManager:readContents(): BackpackRules.Contents
	local contents = {}
	for _, resource in RESOURCE_ORDER do
		local attribute = BackpackRules.attributeForResource(resource) :: string
		local amount = readNumber(attribute)
		if amount > 0 then
			contents[resource] = amount
		end
	end
	return contents
end

function ClientBackpackManager:renderHud()
	local countLabel = self.countLabel
	local fullLabel = self.fullLabel
	if not countLabel then
		return
	end
	local capacity = readNumber(Attributes.BACKPACK_CAPACITY)
	local total = self.heldTotal or BackpackRules.getTotal(self:readContents())
	local isFull = capacity > 0 and total >= capacity
	if isFull and not self.wasFull then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
	end
	self.wasFull = isFull
	countLabel.Text = string.format(COUNT_FORMAT, total, capacity)
	countLabel.TextColor3 = if isFull then UiStyle.NEGATIVE_COLOR else UiStyle.TEXT_COLOR
	if fullLabel then
		fullLabel.Visible = isFull
	end
end

function ClientBackpackManager:renderMenu()
	local list = self.list
	local template = self.rowTemplate
	if not list or not template then
		return
	end
	for _, row in self.rows do
		row:Destroy()
	end
	self.rows = {}
	local contents = self:readContents()
	local order = 0
	for _, resource in RESOURCE_ORDER do
		local amount = contents[resource]
		if not amount then
			continue
		end
		order += 1
		local row = template:Clone()
		row.Name = "Row" .. order
		row.LayoutOrder = order
		row.Visible = true
		local icon = row:FindFirstChild(Constants.BACKPACK_ROW_ICON)
		if icon and icon:IsA("ImageLabel") then
			local imageId = Icons.RAW_RESOURCE[resource]
			local imageLabel = icon :: ImageLabel
			imageLabel.Image = if Icons.isPlaceholder(imageId) then "" else imageId
		end
		local nameLabel = row:FindFirstChild(Constants.BACKPACK_ROW_NAME_LABEL)
		if nameLabel and nameLabel:IsA("TextLabel") then
			(nameLabel :: TextLabel).Text = Enums.getPublicName(Enums.RawResource, resource) or "?"
		end
		local amountLabel = row:FindFirstChild(Constants.BACKPACK_ROW_AMOUNT_LABEL)
		if amountLabel and amountLabel:IsA("TextLabel") then
			(amountLabel :: TextLabel).Text = tostring(amount)
		end
		row.Parent = list
		table.insert(self.rows, row)
	end
	local emptyLabel = self.emptyLabel
	if emptyLabel then
		emptyLabel.Visible = order == 0
	end
end

-- screen centre of the HUD button while shown, for the refinery's suck-in
function ClientBackpackManager:getButtonScreenCenter(): Vector2?
	local button = self.button
	if not button or not button.Visible then
		return nil
	end
	return button.AbsolutePosition + button.AbsoluteSize / 2
end

function ClientBackpackManager:setHudVisible()
	local button = self.button
	if not button then
		return
	end
	button.Visible = not self.isMenuOpen
end

function ClientBackpackManager:closeMenu()
	if not self.isMenuOpen then
		return
	end
	self.isMenuOpen = false
	local menuGui = self.menuGui
	if menuGui then
		menuGui.Enabled = false
	end
	self:setHudVisible()
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

function ClientBackpackManager:openMenu()
	local menuGui = self.menuGui
	local overlay = self.overlay
	if not menuGui or not overlay or self.isMenuOpen then
		return
	end
	self.isMenuOpen = true
	self:renderMenu()
	menuGui.Enabled = true
	self:setHudVisible()
	ClientOverlayManager:notifyBeginOverlay(overlay)
end

function ClientBackpackManager:onOreCollected(payload: any)
	local isValid = Validate.isTableShape(payload, NOTIFY_ORE_COLLECTED_SHAPE)
	if not isValid then
		warn("ClientBackpackManager: malformed NotifyOreCollected")
		return
	end
	local button = self.button
	-- ore at the player's feet is off screen in first person; it still flies
	-- in from the nearest edge
	local from = ClientIconFlightManager:worldToScreenOrEdge(payload.position)
	if not button or not button.Visible or not from then
		-- nothing to fly to (or from): one pop still confirms the pickup
		ClientSoundManager:playSfx(SoundNames.Sfx.ORE_PICKUP)
		return
	end
	local to = ClientIconFlightManager:screenCenterOf(button)
	local imageId = Icons.RAW_RESOURCE[payload.resource]
	local color = COLOR_BY_RAW[payload.resource] or UiStyle.TEXT_MUTED_COLOR
	local count = math.clamp(payload.amount, 1, MAX_ICONS_PER_COLLECTION)
	-- the attributes already hold the new total; show the old one until the
	-- icons land, then step up with each
	local shares = ClientIconFlightManager.splitAmount(payload.amount, count)
	self:holdTotal(BackpackRules.getTotal(self:readContents()) - payload.amount, count)
	local delaySec = 0
	for index = 1, count do
		ClientIconFlightManager:fly(
			imageId,
			color,
			from,
			to,
			delaySec,
			function()
				ClientSoundManager:playSfx(SoundNames.Sfx.ORE_PICKUP)
				local landedOn = self.button
				if landedOn and landedOn.Visible then
					ClientIconFlightManager:bump(landedOn)
				end
				self:stepHeldTotal(shares[index])
			end
		)
		delaySec += ICON_STAGGER_SEC
	end
end

-- freezes the HUD total at a value while iconCount icons are in flight; the
-- refinery uses this too while ore is being sucked out
function ClientBackpackManager:holdTotal(total: number, iconCount: number)
	if self.heldTotal == nil then
		self.heldTotal = total
	end
	self.flightsInProgress += iconCount
	self:renderHud()
end

-- one icon arrived or left: move the shown total by its share; the last one
-- releases the hold so the attributes show again
function ClientBackpackManager:stepHeldTotal(delta: number)
	local held = self.heldTotal
	if held == nil then
		return
	end
	self.heldTotal = math.max(held + delta, 0)
	self.flightsInProgress = math.max(self.flightsInProgress - 1, 0)
	if self.flightsInProgress == 0 then
		self.heldTotal = nil
	end
	self:renderHud()
end

function ClientBackpackManager:findHud()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.GAMEPLAY_HUD_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientBackpackManager: no GameplayHud ScreenGui; run scripts/studio/build_gameplay_hud_gui.luau")
		return
	end
	self.hudGui = gui
	local button = gui:FindFirstChild(Constants.HUD_BACKPACK_BUTTON, true)
	if not button or not button:IsA("GuiButton") then
		warn("ClientBackpackManager: GameplayHud is missing BackpackButton")
		return
	end
	self.button = button
	self.buttonBasePosition = button.Position
	local icon = button:FindFirstChild(Constants.HUD_BACKPACK_ICON)
	if icon and icon:IsA("ImageLabel") then
		icon.Image = if Icons.isPlaceholder(Icons.UI.BACKPACK) then "" else Icons.UI.BACKPACK
	end
	local countLabel = button:FindFirstChild(Constants.HUD_BACKPACK_COUNT_LABEL)
	self.countLabel = if countLabel and countLabel:IsA("TextLabel") then countLabel else nil
	local fullLabel = button:FindFirstChild(Constants.HUD_BACKPACK_FULL_LABEL)
	self.fullLabel = if fullLabel and fullLabel:IsA("TextLabel") then fullLabel else nil
	button.Activated:Connect(
		function()
			self:openMenu()
		end
	)
end

function ClientBackpackManager:findMenu()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.BACKPACK_MENU_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientBackpackManager: no Backpack ScreenGui; run scripts/studio/build_backpack_menu_gui.luau")
		return
	end
	gui.Enabled = false
	self.menuGui = gui
	local dialog = gui:FindFirstChild(Constants.MENU_DIALOG_FRAME)
	self.menuDialog = if dialog and dialog:IsA("Frame") then dialog else nil
	local list = if dialog then dialog:FindFirstChild(Constants.BACKPACK_MENU_LIST) else nil
	self.list = if list and list:IsA("Frame") then list else nil
	local template = if list then list:FindFirstChild(Constants.BACKPACK_MENU_ROW_TEMPLATE) else nil
	self.rowTemplate = if template and template:IsA("Frame") then template else nil
	if self.rowTemplate then
		self.rowTemplate.Visible = false
	end
	local emptyLabel = if dialog then dialog:FindFirstChild(Constants.BACKPACK_MENU_EMPTY_LABEL) else nil
	self.emptyLabel = if emptyLabel and emptyLabel:IsA("TextLabel") then emptyLabel else nil
	local closeButton = if dialog then dialog:FindFirstChild(Constants.BACKPACK_MENU_CLOSE_BUTTON) else nil
	if closeButton and closeButton:IsA("GuiButton") then
		closeButton.Activated:Connect(
			function()
				self:closeMenu()
			end
		)
	end

	local overlay: ClientOverlayManager.Overlay
	overlay = {
		getGuiRoot = function(_overlay)
			return self.menuDialog
		end,
		notifyForceEnd = function(_overlay)
			self:closeMenu()
		end,
		notifyClickOutside = function(_overlay)
			self:closeMenu()
		end,
	}
	self.overlay = overlay
end

function ClientBackpackManager:init()
	self:findHud()
	self:findMenu()

	self:setHudVisible()

	local watched = { Attributes.BACKPACK_CAPACITY }
	for _, resource in RESOURCE_ORDER do
		table.insert(watched, BackpackRules.attributeForResource(resource) :: string)
	end
	for _, key in watched do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			key,
			function()
				-- deferred so a NotifyOreCollected in the same step can hold
				-- the old total before this render runs
				task.defer(
					function()
						self:renderHud()
					end
				)
				if self.isMenuOpen then
					self:renderMenu()
				end
			end
		)
	end
	self:renderHud()

	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_ORE_COLLECTED,
		function(payload: any)
			self:onOreCollected(payload)
		end
	)
end

function ClientBackpackManager.new(): ClientBackpackManager
	local self = setmetatable({}, ClientBackpackManager) :: ClientBackpackManager
	self.hudGui = nil
	self.button = nil
	self.countLabel = nil
	self.fullLabel = nil
	self.buttonBasePosition = nil
	self.heldTotal = nil
	self.flightsInProgress = 0
	self.menuGui = nil
	self.menuDialog = nil
	self.list = nil
	self.rowTemplate = nil
	self.emptyLabel = nil
	self.rows = {}
	self.overlay = nil
	self.isMenuOpen = false
	self.wasFull = false
	return self
end

return ClientBackpackManager.new()
