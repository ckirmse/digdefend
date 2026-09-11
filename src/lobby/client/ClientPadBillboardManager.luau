--!strict

-- Renders every helicopter pad's billboard (GuiPart.PadGui) from the pad
-- attributes PartyManager replicates. Nothing here talks to the server; the
-- countdown is computed locally from the replicated timer end time.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

local ClientPadBillboardManager = {}
ClientPadBillboardManager.__index = ClientPadBillboardManager

type Labels = {
	mapName: TextLabel,
	difficulty: TextLabel,
	status: TextLabel,
	playerCount: TextLabel,
	timer: TextLabel,
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

-- designer rules (milestones M12, 2026-09-10)
local DIFFICULTY_COLORS: { [number]: Color3 } = {
	[Enums.Difficulty.NORMAL] = Color3.fromRGB(0, 130, 0),
	[Enums.Difficulty.HARD] = Color3.fromRGB(215, 120, 0),
	[Enums.Difficulty.NIGHTMARE] = Color3.fromRGB(190, 0, 0),
}
local STATUS_GREEN = Color3.fromRGB(85, 255, 0)
local STATUS_ORANGE = Color3.fromRGB(255, 170, 0)
local STATUS_RED = Color3.fromRGB(255, 60, 60)

local COUNTDOWN_REFRESH_SEC = 0.25

local function findLabel(gui: Instance, name: string): TextLabel?
	local label = gui:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		return label
	end
	return nil
end

local function getAttributeNumber(model: Model, name: string): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

function ClientPadBillboardManager:renderCountdown(view: PadView)
	local state = getAttributeNumber(view.model, Attributes.PAD_STATE)
	local endTime = getAttributeNumber(view.model, Attributes.PAD_TIMER_END_TIME)
	if state ~= Enums.PadState.BOARDING or endTime == 0 then
		view.labels.timer.Visible = false
		return
	end
	local remaining = math.max(0, math.ceil(endTime - workspace:GetServerTimeNow()))
	view.labels.timer.Text = `DEPARTING IN {remaining}`
	view.labels.timer.Visible = true
end

function ClientPadBillboardManager:render(view: PadView)
	local model = view.model
	local labels = view.labels
	local state = getAttributeNumber(model, Attributes.PAD_STATE)

	if state == Enums.PadState.BOARDING or state == Enums.PadState.DEPARTING then
		local map = getAttributeNumber(model, Attributes.PAD_MAP)
		local difficulty = getAttributeNumber(model, Attributes.PAD_DIFFICULTY)
		local visibility = getAttributeNumber(model, Attributes.PAD_VISIBILITY)
		labels.mapName.Text = Enums.getPublicName(Enums.Map, map) or "?"
		labels.difficulty.Text = `DIFFICULTY: {string.upper(Enums.getPublicName(Enums.Difficulty, difficulty) or "?")}`
		labels.difficulty.BackgroundColor3 = DIFFICULTY_COLORS[difficulty] or DIFFICULTY_COLORS[Enums.Difficulty.NORMAL]
		labels.difficulty.Visible = true
		labels.playerCount.Text = `{getAttributeNumber(model, Attributes.PAD_PLAYER_COUNT)}/{getAttributeNumber(model, Attributes.PAD_MAX_PLAYERS)}`
		labels.playerCount.Visible = true
		if state == Enums.PadState.BOARDING then
			local isFriendsOnly = visibility == Enums.PartyVisibility.FRIENDS_ONLY
			labels.status.Text = if isFriendsOnly then "NOW BOARDING (FRIENDS ONLY)" else "NOW BOARDING"
			labels.status.TextColor3 = STATUS_GREEN
		else
			labels.status.Text = "DEPARTING"
			labels.status.TextColor3 = STATUS_RED
		end
	else
		labels.mapName.Text = "Helicopter Pad"
		labels.difficulty.Visible = false
		labels.playerCount.Visible = false
		if state == Enums.PadState.CONFIGURING then
			labels.status.Text = "SETTING UP..."
			labels.status.TextColor3 = STATUS_ORANGE
		else
			labels.status.Text = "OPEN"
			labels.status.TextColor3 = STATUS_GREEN
		end
	end
	self:renderCountdown(view)
end

function ClientPadBillboardManager:watchPad(model: Model)
	local guiPart = model:FindFirstChild(Constants.PAD_GUI_PART)
	local gui = if guiPart then guiPart:FindFirstChild(Constants.PAD_GUI_NAME) else nil
	if not gui then
		warn(`ClientPadBillboardManager: {model:GetFullName()} has no {Constants.PAD_GUI_NAME}`)
		return
	end
	local mapName = findLabel(gui, Constants.PAD_GUI_MAP_NAME_LABEL)
	local difficulty = findLabel(gui, Constants.PAD_GUI_DIFFICULTY_LABEL)
	local status = findLabel(gui, Constants.PAD_GUI_STATUS_LABEL)
	local playerCount = findLabel(gui, Constants.PAD_GUI_PLAYER_COUNT_LABEL)
	local timer = findLabel(gui, Constants.PAD_GUI_TIMER_LABEL)
	if not (mapName and difficulty and status and playerCount and timer) then
		warn(`ClientPadBillboardManager: {gui:GetFullName()} is missing a label`)
		return
	end
	local view: PadView = {
		model = model,
		labels = {
			mapName = mapName,
			difficulty = difficulty,
			status = status,
			playerCount = playerCount,
			timer = timer,
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
					self:renderCountdown(view)
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
