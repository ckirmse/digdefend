--!strict

-- Renders every helicopter pad's billboard (GuiPart.PadGui) from the pad
-- attributes PartyManager replicates. Nothing here talks to the server; the
-- countdown is computed locally from the replicated timer end time.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local ClientGuiFade = require(script.Parent.Parent.Client.ClientGuiFade)

local ClientPadBillboardManager = {}
ClientPadBillboardManager.__index = ClientPadBillboardManager

type Labels = {
	status: TextLabel,
	private: TextLabel,
	players: TextLabel,
	-- the designer's full-panel line shown alone while a host sets a run up
	configuring: TextLabel,
	-- "LEAVING IN: Xs" under the rest while a party boards (2026-10-30);
	-- optional, since an older copy of the gui has none
	timer: TextLabel?,
}

type PadView = {
	model: Model,
	gui: BillboardGui,
	labels: Labels,
	-- the pad state drawn last, so a launch and the next helicopter are
	-- each seen once
	lastState: number,
	-- faded out for a departure; the party menus' hide leaves it off
	isFaded: boolean,
	-- the menus' hide, kept so the fade-in after a departure honours it
	isHiddenByMenu: boolean,
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
-- "is setting up a run" until 2026-10-30
local CONFIGURING_FORMAT = "%s is creating a party"
local STATUS_CONFIGURING_UNKNOWN_HOST = "A player"
local STATUS_RUN_FORMAT = "%s (%s)"
local STATUS_DEPARTING = "Departing"
-- the words are a title (caps); the seconds keep their small "s"
local TIMER_WORDS = "Leaving in:"
local TIMER_FORMAT = "%s %ds"
local PRIVATE_PUBLIC = "Public"
local PRIVATE_PRIVATE = "Private"
local PLAYERS_FORMAT = "%d/%d"

local COUNTDOWN_REFRESH_SEC = 0.25
-- the sign fades out as the helicopter lifts off and back in, reset, with
-- the next one (designer, 2026-10-30)
local DEPARTURE_FADE_SEC = 1

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
		view.isHiddenByMenu = not isVisible
		view.gui.Enabled = isVisible and not view.isFaded
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
		-- the run's name in the accent gold, like the waiting line (designer,
		-- 2026-10-30; white before)
		status.Text = UiStyle.formatTitle(string.format(STATUS_RUN_FORMAT, mapName, difficultyName))
		status.TextColor3 = UiStyle.ACCENT_COLOR
	elseif state == Enums.PadState.DEPARTING then
		status.Text = UiStyle.formatTitle(STATUS_DEPARTING)
		status.TextColor3 = UiStyle.NEGATIVE_COLOR
	elseif state == Enums.PadState.CONFIGURING then
		-- the status is hidden under the Configuring label; it keeps the
		-- waiting line for the moment it shows again
		status.Text = UiStyle.formatTitle(STATUS_WAITING)
		status.TextColor3 = UiStyle.ACCENT_COLOR
	else
		-- the accent gold (designer, 2026-10-30; muted grey before)
		status.Text = UiStyle.formatTitle(STATUS_WAITING)
		status.TextColor3 = UiStyle.ACCENT_COLOR
	end
	self:renderTimer(view, state)
end

-- the boarding countdown, from the replicated timer end time, shown only
-- while a party boards with a timer running; this runs on the same refresh
-- as the status so it counts down on its own
function ClientPadBillboardManager:renderTimer(view: PadView, state: number)
	local timer = view.labels.timer
	if not timer then
		return
	end
	local endTime = getAttributeNumber(view.model, Attributes.PAD_TIMER_END_TIME)
	local isCounting = state == Enums.PadState.BOARDING and endTime > 0
	if isCounting then
		local remaining = math.max(0, math.ceil(endTime - workspace:GetServerTimeNow()))
		timer.Text = string.format(TIMER_FORMAT, UiStyle.formatTitle(TIMER_WORDS), remaining)
	end
	timer.Visible = isCounting
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
	self:stepDepartureFade(view, state)
end

-- the sign fades out as the helicopter lifts off (the pad going Departing)
-- and fades back in, already redrawn for the fresh pad, when the next
-- helicopter stands there (the pad leaving Departing). A hide by the party
-- menus in between keeps it off; the fade only ever moves the designer's
-- transparencies, and ClientGuiFade puts them back
function ClientPadBillboardManager:stepDepartureFade(view: PadView, state: number)
	local wasDeparting = view.lastState == Enums.PadState.DEPARTING
	view.lastState = state
	local isDeparting = state == Enums.PadState.DEPARTING
	if isDeparting and not wasDeparting and not view.isFaded then
		view.isFaded = true
		ClientGuiFade.fadeOut(
			view.gui,
			DEPARTURE_FADE_SEC,
			function()
				-- a new helicopter that arrived mid-fade has already asked for
				-- the sign back
				if view.isFaded then
					view.gui.Enabled = false
				end
			end
		)
	elseif wasDeparting and not isDeparting and view.isFaded then
		view.isFaded = false
		if not view.isHiddenByMenu then
			view.gui.Enabled = true
			ClientGuiFade.fadeIn(view.gui, DEPARTURE_FADE_SEC)
		end
	end
end

function ClientPadBillboardManager:watchPad(model: Model)
	-- the pad's parts stream in after the client starts on a live server
	-- (2026-10-13: every pad warned and drew nothing for a tester), so the
	-- billboard is waited for rather than found
	local guiPart = model:WaitForChild(Constants.PAD_GUI_PART, Constants.GUI_WAIT_SEC)
	local gui = if guiPart then guiPart:WaitForChild(Constants.PAD_GUI_NAME, Constants.GUI_WAIT_SEC) else nil
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
	local timer = findLabel(gui, Constants.PAD_GUI_TIMER_LABEL)
	local view: PadView = {
		model = model,
		gui = gui,
		labels = {
			status = status,
			private = private,
			players = players,
			configuring = configuring,
			timer = timer,
		},
		-- a pad first seen departing fades in with its next helicopter
		lastState = getAttributeNumber(model, Attributes.PAD_STATE),
		isFaded = false,
		isHiddenByMenu = false,
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
	-- each pad waits on its own thread, so one slow pad never holds the rest
	local function watchIfPad(pad: Instance)
		if pad:IsA("Model") and pad:GetAttribute(Attributes.PAD_INDEX) ~= nil then
			task.spawn(
				function()
					self:watchPad(pad)
				end
			)
		end
	end
	for _, pad in padsFolder:GetChildren() do
		watchIfPad(pad)
	end
	padsFolder.ChildAdded:Connect(watchIfPad)
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
