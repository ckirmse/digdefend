--!strict

-- Renders every helicopter pad's billboard (GuiPart.PadGui) from the pad
-- attributes PartyManager replicates. Nothing here talks to the server; the
-- countdown is computed locally from the replicated timer end time.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")

local ClientPadBillboardManager = {}
ClientPadBillboardManager.__index = ClientPadBillboardManager

type Labels = {
	status: TextLabel,
	private: TextLabel,
	players: TextLabel,
	-- the designer's full-panel line shown alone while a host sets a run up
	configuring: TextLabel,
}

type PadView = {
	model: Model,
	gui: BillboardGui,
	labels: Labels,
}

export type ClientPadBillboardManager = typeof(setmetatable(
	{} :: {
		views: { PadView },
	},
	ClientPadBillboardManager
))

-- designer copy (2026-09-11, revised 2026-10-09): every label ALL CAPS.
-- While a host configures, the Configuring label alone fills the panel
-- and names them; once the run is configured the status reads
-- "<map> (<difficulty>)", Private shows PRIVATE in red or PUBLIC in
-- green, and Players counts waiting / max
local STATUS_WAITING = "Waiting for players..."
local CONFIGURING_FORMAT = "%s is setting up a run"
local STATUS_CONFIGURING_UNKNOWN_HOST = "A player"
local STATUS_RUN_FORMAT = "%s (%s)"
local STATUS_DEPARTING = "Departing"
local PRIVATE_PUBLIC = "Public"
local PRIVATE_PRIVATE = "Private"
local PLAYERS_FORMAT = "%d/%d"

local COUNTDOWN_REFRESH_SEC = 0.25

local function findLabel(gui: Instance, name: string): TextLabel?
	local label = gui:FindFirstChild(name, true)
	if label and label:IsA("TextLabel") then
		return label
	end
	return nil
end

local function getAttributeNumber(model: Model, name: string): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

-- the party menus hide every billboard so they do not float over the dialog
function ClientPadBillboardManager:setBillboardsVisible(isVisible: boolean)
	for _, view in self.views do
		view.gui.Enabled = isVisible
	end
end

-- the host's display name, read from the lobby's player list; the host is
-- always in this place while they configure
local function hostDisplayName(model: Model): string
	local hostUserId = getAttributeNumber(model, Attributes.PAD_HOST_USER_ID)
	local host = if hostUserId ~= 0 then Players:GetPlayerByUserId(hostUserId) else nil
	return if host then host.DisplayName else STATUS_CONFIGURING_UNKNOWN_HOST
end

function ClientPadBillboardManager:renderStatus(view: PadView)
	local model = view.model
	local status = view.labels.status
	local state = getAttributeNumber(model, Attributes.PAD_STATE)
	if state == Enums.PadState.BOARDING then
		-- the map and difficulty attributes land with the state; a value not
		-- yet set reads as a blank rather than a warning
		local map = getAttributeNumber(model, Attributes.PAD_MAP)
		local difficulty = getAttributeNumber(model, Attributes.PAD_DIFFICULTY)
		local mapName = if Enums.isValidValue(Enums.Map, map) then Enums.getPublicName(Enums.Map, map) or "" else ""
		local difficultyName = if Enums.isValidValue(Enums.Difficulty, difficulty) then Enums.getPublicName(Enums.Difficulty, difficulty) or "" else ""
		status.Text = UiStyle.formatTitle(string.format(STATUS_RUN_FORMAT, mapName, difficultyName))
		status.TextColor3 = UiStyle.TEXT_COLOR
	elseif state == Enums.PadState.DEPARTING then
		status.Text = UiStyle.formatTitle(STATUS_DEPARTING)
		status.TextColor3 = UiStyle.NEGATIVE_COLOR
	elseif state == Enums.PadState.CONFIGURING then
		-- the status is hidden under the Configuring label; it keeps the
		-- waiting line for the moment it shows again
		status.Text = UiStyle.formatTitle(STATUS_WAITING)
		status.TextColor3 = UiStyle.TEXT_MUTED_COLOR
	else
		status.Text = UiStyle.formatTitle(STATUS_WAITING)
		status.TextColor3 = UiStyle.TEXT_MUTED_COLOR
	end
end

function ClientPadBillboardManager:render(view: PadView)
	local model = view.model
	local labels = view.labels
	local state = getAttributeNumber(model, Attributes.PAD_STATE)

	-- while the host sets the run up, their line alone fills the panel
	local isConfiguring = state == Enums.PadState.CONFIGURING
	if isConfiguring then
		labels.configuring.Text = UiStyle.formatTitle(string.format(CONFIGURING_FORMAT, hostDisplayName(model)))
	end
	labels.configuring.Visible = isConfiguring
	labels.status.Visible = not isConfiguring
	labels.players.Visible = not isConfiguring

	local hasParty = state == Enums.PadState.BOARDING or state == Enums.PadState.DEPARTING
	if hasParty then
		local visibility = getAttributeNumber(model, Attributes.PAD_VISIBILITY)
		local isPrivate = visibility == Enums.PartyVisibility.FRIENDS_ONLY
		labels.private.Text = UiStyle.formatTitle(if isPrivate then PRIVATE_PRIVATE else PRIVATE_PUBLIC)
		labels.private.TextColor3 = if isPrivate then UiStyle.NEGATIVE_COLOR else UiStyle.POSITIVE_COLOR
	end
	labels.private.Visible = hasParty and not isConfiguring

	local playerCount = getAttributeNumber(model, Attributes.PAD_PLAYER_COUNT)
	local maxPlayers = getAttributeNumber(model, Attributes.PAD_MAX_PLAYERS)
	labels.players.Text = string.format(PLAYERS_FORMAT, playerCount, maxPlayers)
	self:renderStatus(view)
end

function ClientPadBillboardManager:watchPad(model: Model)
	local guiPart = model:FindFirstChild(Constants.PAD_GUI_PART)
	local gui = if guiPart then guiPart:FindFirstChild(Constants.PAD_GUI_NAME) else nil
	if not gui or not gui:IsA("BillboardGui") then
		warn(`ClientPadBillboardManager: {model:GetFullName()} has no {Constants.PAD_GUI_NAME}`)
		return
	end
	local status = findLabel(gui, Constants.PAD_GUI_STATUS_LABEL)
	local private = findLabel(gui, Constants.PAD_GUI_PRIVATE_LABEL)
	local players = findLabel(gui, Constants.PAD_GUI_PLAYERS_LABEL)
	local configuring = findLabel(gui, Constants.PAD_GUI_CONFIGURING_LABEL)
	if not (status and private and players and configuring) then
		warn(`ClientPadBillboardManager: {gui:GetFullName()} is missing a label; run scripts/studio/build_pad_gui.luau`)
		return
	end
	local view: PadView = {
		model = model,
		gui = gui,
		labels = {
			status = status,
			private = private,
			players = players,
			configuring = configuring,
		},
	}
	table.insert(self.views, view)
	model.AttributeChanged:Connect(
		function()
			self:render(view)
		end
	)
	self:render(view)
end

function ClientPadBillboardManager:init()
	local padsFolder = workspace:WaitForChild(Constants.HELICOPTER_PADS_FOLDER)
	for _, pad in padsFolder:GetChildren() do
		if pad:IsA("Model") and pad:GetAttribute(Attributes.PAD_INDEX) ~= nil then
			self:watchPad(pad)
		end
	end
	task.spawn(
		function()
			while true do
				task.wait(COUNTDOWN_REFRESH_SEC)
				for _, view in self.views do
					self:renderStatus(view)
				end
			end
		end
	)
end

function ClientPadBillboardManager.new(): ClientPadBillboardManager
	local self = setmetatable({}, ClientPadBillboardManager) :: ClientPadBillboardManager
	self.views = {}
	return self
end

return ClientPadBillboardManager.new()
