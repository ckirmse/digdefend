--!strict

-- The controls panel (both places, 2026-11-09): a list in the bottom right
-- of the keys that do something right now, for keyboard and gamepad
-- players (a touch device has its buttons on screen and never shows it).
-- The rows come from pure ControlsRules, judged from the last input used
-- and the CurrentPlayer attributes the server already publishes: the
-- tool in hand, the class gadget, the post manned, Build Mode. The
-- toggle collapses the panel to a tab and the choice is saved
-- (TrySetControlsPanelHidden, SettingsManager), so it comes back the way
-- the player left it. The panel steps aside with the rest of the HUD
-- while a menu is up (an overlay notifier) and goes with it on a death
-- (ClientReviveManager hides every HUD ScreenGui).
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local ControlsRules = require("@game/ReplicatedStorage/Shared/ControlsRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local ClientDataManager = require(script.Parent.ClientDataManager)
local ClientNetManager = require(script.Parent.ClientNetManager)
local ClientOverlayManager = require(script.Parent.ClientOverlayManager)

local ClientControlsPanelManager = {}
ClientControlsPanelManager.__index = ClientControlsPanelManager

type View = {
	gui: ScreenGui,
	root: GuiObject,
	panel: GuiObject,
	title: GuiObject,
	toggleButton: GuiButton,
	rows: GuiObject,
	rowTemplate: GuiObject,
	collapsedTab: GuiButton,
}

export type ClientControlsPanelManager = typeof(setmetatable(
	{} :: {
		view: View?,
		-- a menu is up: the panel stays off until it closes
		isOverlayUp: boolean,
	},
	ClientControlsPanelManager
))

-- the title row and up to this many rows share the Root's height
local MAX_ROWS = 8
local ROW_SHARE = 1 / (MAX_ROWS + 1)

local function setLabel(parent: Instance, name: string, text: string)
	local label = parent:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

function ClientControlsPanelManager:getPlaceKind(): number
	return Constants.getPlaceKind()
end

function ClientControlsPanelManager:readContext(): ControlsRules.Context
	local tool = ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL)
	local gadgetKind = ClientDataManager:getCurrentPlayerAttribute(Attributes.GADGET_KIND)
	local mannedIndex = ClientDataManager:getCurrentPlayerAttribute(Attributes.MANNED_POST_INDEX)
	return {
		place = self:getPlaceKind(),
		tool = if typeof(tool) == "number" then tool else nil,
		gadgetKind = if typeof(gadgetKind) == "number" then gadgetKind else nil,
		isMounted = typeof(mannedIndex) == "number" and mannedIndex > 0,
		isBuildMode = ClientDataManager:getCurrentPlayerAttribute(Attributes.IS_IN_BUILD_MODE) == true,
	}
end

function ClientControlsPanelManager:isHiddenByChoice(): boolean
	return ClientDataManager:getCurrentPlayerAttribute(Attributes.CONTROLS_PANEL_HIDDEN) == true
end

function ClientControlsPanelManager:render()
	local view = self.view
	if not view then
		return
	end
	local scheme = ControlsRules.schemeFor(UserInputService:GetLastInputType(), UserInputService.KeyboardEnabled, UserInputService.GamepadEnabled)
	if not scheme or self.isOverlayUp then
		view.gui.Enabled = false
		return
	end
	view.gui.Enabled = true
	local isHidden = self:isHiddenByChoice()
	view.panel.Visible = not isHidden
	view.collapsedTab.Visible = isHidden
	if isHidden then
		return
	end
	for _, child in view.rows:GetChildren() do
		if child:IsA("GuiObject") and child ~= view.rowTemplate then
			child:Destroy()
		end
	end
	local rows = ControlsRules.rowsFor(self:readContext(), scheme)
	local count = math.min(#rows, MAX_ROWS)
	-- the panel is as tall as its rows and the title, in shares of the
	-- Root, so a short list leaves no empty plate
	view.panel.Size = UDim2.fromScale(1, (count + 1) * ROW_SHARE)
	view.title.Size = UDim2.fromScale(1, 1 / (count + 1))
	view.rows.Size = UDim2.fromScale(1, count / (count + 1))
	for index = 1, count do
		local row = rows[index]
		local frame = view.rowTemplate:Clone()
		frame.Name = "Row" .. index
		frame.LayoutOrder = index
		frame.Size = UDim2.fromScale(1, 1 / count)
		frame.Visible = true
		setLabel(frame, Constants.CONTROLS_PANEL_ROW_KEY_LABEL, row.key)
		setLabel(frame, Constants.CONTROLS_PANEL_ROW_ACTION_LABEL, row.action)
		frame.Parent = view.rows
	end
end

function ClientControlsPanelManager:setHidden(isHidden: boolean)
	ClientNetManager:fireServer(NetEventNames.TRY_SET_CONTROLS_PANEL_HIDDEN, { isHidden = isHidden })
end

-- a menu up: the panel steps aside with the rest of the HUD
function ClientControlsPanelManager:notifyBeginOverlay(_overlay: ClientOverlayManager.Overlay)
	self.isOverlayUp = true
	self:render()
end

function ClientControlsPanelManager:notifyEndOverlay(_overlay: ClientOverlayManager.Overlay)
	self.isOverlayUp = false
	self:render()
end

function ClientControlsPanelManager:findView(): View?
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- waited for, not found: on a live server the client can start before
	-- StarterGui is copied in
	local gui = playerGui:WaitForChild(Constants.CONTROLS_PANEL_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientControlsPanelManager: no ControlsPanel ScreenGui; run scripts/studio/build_controls_panel_gui.luau")
		return nil
	end
	local root = gui:FindFirstChild(Constants.CONTROLS_PANEL_ROOT_FRAME)
	local panel = if root then root:FindFirstChild("Panel") else nil
	local title = if panel then panel:FindFirstChild(Constants.CONTROLS_PANEL_TITLE_LABEL) else nil
	local toggleButton = if title then title:FindFirstChild(Constants.CONTROLS_PANEL_TOGGLE_BUTTON) else nil
	local rows = if panel then panel:FindFirstChild(Constants.CONTROLS_PANEL_ROWS_FRAME) else nil
	local rowTemplate = if rows then rows:FindFirstChild(Constants.CONTROLS_PANEL_ROW_TEMPLATE) else nil
	local collapsedTab = if root then root:FindFirstChild(Constants.CONTROLS_PANEL_COLLAPSED_TAB) else nil
	if
		not root
		or not root:IsA("GuiObject")
		or not panel
		or not panel:IsA("GuiObject")
		or not title
		or not title:IsA("GuiObject")
		or not toggleButton
		or not toggleButton:IsA("GuiButton")
		or not rows
		or not rows:IsA("GuiObject")
		or not rowTemplate
		or not rowTemplate:IsA("GuiObject")
		or not collapsedTab
		or not collapsedTab:IsA("GuiButton")
	then
		warn("ClientControlsPanelManager: the ControlsPanel ScreenGui is missing parts; rebuild it with scripts/studio/build_controls_panel_gui.luau")
		return nil
	end
	rowTemplate.Visible = false
	collapsedTab.Visible = false
	setLabel(title, "Text", UiStyle.formatTitle("Controls"))
	return {
		gui = gui,
		root = root,
		panel = panel,
		title = title,
		toggleButton = toggleButton,
		rows = rows,
		rowTemplate = rowTemplate,
		collapsedTab = collapsedTab,
	}
end

function ClientControlsPanelManager:init()
	local view = self:findView()
	if not view then
		return
	end
	self.view = view
	view.toggleButton.Activated:Connect(
		function()
			self:setHidden(true)
		end
	)
	view.collapsedTab.Activated:Connect(
		function()
			self:setHidden(false)
		end
	)
	for _, key in { Attributes.EQUIPPED_TOOL, Attributes.GADGET_KIND, Attributes.MANNED_POST_INDEX, Attributes.IS_IN_BUILD_MODE, Attributes.CONTROLS_PANEL_HIDDEN } do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			key,
			function()
				self:render()
			end
		)
	end
	UserInputService.LastInputTypeChanged:Connect(
		function()
			self:render()
		end
	)
	ClientOverlayManager:addOverlayNotifier(self)
	self:render()
end

function ClientControlsPanelManager.new(): ClientControlsPanelManager
	local self = setmetatable({}, ClientControlsPanelManager) :: ClientControlsPanelManager
	self.view = nil
	self.isOverlayUp = false
	return self
end

return ClientControlsPanelManager.new()
