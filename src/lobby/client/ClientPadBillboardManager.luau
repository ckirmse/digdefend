--!strict

-- Renders every helicopter pad's billboard (GuiPart.PadGui) from the pad
-- attributes PartyManager replicates. Nothing here talks to the server; the
-- countdown is computed locally from the replicated timer end time.
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
}

type PadView = {
	model: Model,
	labels: Labels,
}

export type ClientPadBillboardManager = typeof(setmetatable(
	{} :: {
		views: { PadView },
	},
	ClientPadBillboardManager
))

-- designer copy (2026-09-11): three labels, Private hidden until a party exists
local STATUS_WAITING = "Waiting for players..."
local STATUS_CONFIGURING = "Player configuring"
local STATUS_STARTS_IN = "Starts in: %d"
local STATUS_DEPARTING = "Departing"
local PRIVATE_PUBLIC = "Public"
local PRIVATE_PRIVATE = "Private"

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

function ClientPadBillboardManager:renderStatus(view: PadView)
	local model = view.model
	local status = view.labels.status
	local state = getAttributeNumber(model, Attributes.PAD_STATE)
	if state == Enums.PadState.BOARDING then
		local endTime = getAttributeNumber(model, Attributes.PAD_TIMER_END_TIME)
		local remaining = math.max(0, math.ceil(endTime - workspace:GetServerTimeNow()))
		status.Text = UiStyle.formatTitle(string.format(STATUS_STARTS_IN, remaining))
		status.TextColor3 = UiStyle.POSITIVE_COLOR
	elseif state == Enums.PadState.DEPARTING then
		status.Text = UiStyle.formatTitle(STATUS_DEPARTING)
		status.TextColor3 = UiStyle.NEGATIVE_COLOR
	elseif state == Enums.PadState.CONFIGURING then
		status.Text = UiStyle.formatTitle(STATUS_CONFIGURING)
		status.TextColor3 = UiStyle.ACCENT_COLOR
	else
		status.Text = UiStyle.formatTitle(STATUS_WAITING)
		status.TextColor3 = UiStyle.TEXT_MUTED_COLOR
	end
end

function ClientPadBillboardManager:render(view: PadView)
	local model = view.model
	local labels = view.labels
	local state = getAttributeNumber(model, Attributes.PAD_STATE)

	local hasParty = state == Enums.PadState.BOARDING or state == Enums.PadState.DEPARTING
	if hasParty then
		local visibility = getAttributeNumber(model, Attributes.PAD_VISIBILITY)
		local isPrivate = visibility == Enums.PartyVisibility.FRIENDS_ONLY
		labels.private.Text = UiStyle.formatTitle(if isPrivate then PRIVATE_PRIVATE else PRIVATE_PUBLIC)
		labels.private.TextColor3 = if isPrivate then UiStyle.ACCENT_COLOR else UiStyle.TEXT_MUTED_COLOR
	end
	labels.private.Visible = hasParty

	local playerCount = getAttributeNumber(model, Attributes.PAD_PLAYER_COUNT)
	local maxPlayers = getAttributeNumber(model, Attributes.PAD_MAX_PLAYERS)
	labels.players.Text = `{playerCount}/{maxPlayers}`
	self:renderStatus(view)
end

function ClientPadBillboardManager:watchPad(model: Model)
	local guiPart = model:FindFirstChild(Constants.PAD_GUI_PART)
	local gui = if guiPart then guiPart:FindFirstChild(Constants.PAD_GUI_NAME) else nil
	if not gui then
		warn(`ClientPadBillboardManager: {model:GetFullName()} has no {Constants.PAD_GUI_NAME}`)
		return
	end
	local status = findLabel(gui, Constants.PAD_GUI_STATUS_LABEL)
	local private = findLabel(gui, Constants.PAD_GUI_PRIVATE_LABEL)
	local players = findLabel(gui, Constants.PAD_GUI_PLAYERS_LABEL)
	if not (status and private and players) then
		warn(`ClientPadBillboardManager: {gui:GetFullName()} is missing a label`)
		return
	end
	local view: PadView = {
		model = model,
		labels = {
			status = status,
			private = private,
			players = players,
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
