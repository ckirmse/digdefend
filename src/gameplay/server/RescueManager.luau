--!strict

-- The rescue (GDD "Gameplay Loop", "Helicopter Pad"), M31: the way a run
-- is won. Once the crew has refined the uranium target (RefineryManager),
-- the designer's radio (Camp.Radio; its authored ProximityPrompt on
-- PromptPart is enabled only then) calls the rescue helicopter: the
-- run enters its Rescue state (RunCycleManager: night look, gate shut, a
-- countdown to landing), and MonsterWaveManager spawns the final wave
-- while it flies in. At landing the company helicopter (HelicopterManager)
-- appears on the pad with a Board prompt that seats a player. It leaves
-- once everyone standing is aboard, or BOARDING_TIMEOUT_SEC after landing
-- with someone aboard (pure RescueRules): the run ends Won, and every
-- player aboard whose own progression allows it records the completion
-- (PlayerData, replicated so the lobby's Create Party menu unlocks it).
-- Tuning is GameData/Run/Rescue. What clients need is GameMetadata: the
-- landing time is the run's phase end, plus whether it has landed and
-- how many are aboard of how many standing (ClientRescueManager draws
-- the radio's billboard from these).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local CompletionKeys = require("@game/ReplicatedStorage/Shared/CompletionKeys")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PartyRules = require("@game/ReplicatedStorage/Shared/PartyRules")
local RescueRules = require("@game/ReplicatedStorage/Shared/RescueRules")
local RunCycleRules = require("@game/ReplicatedStorage/Shared/RunCycleRules")
local PartyData = require("@game/ServerScriptService/GameData/Pads/Party")
local RescueData = require("@game/ServerScriptService/GameData/Run/Rescue")
local GameController = require(script.Parent.Parent.Server.GameController)
local HelicopterManager = require(script.Parent.Parent.Server.HelicopterManager)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local MapManager = require(script.Parent.MapManager)
local MonsterWaveManager = require(script.Parent.MonsterWaveManager)
local RefineryManager = require(script.Parent.RefineryManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunManager = require(script.Parent.RunManager)

local RescueManager = {}
RescueManager.__index = RescueManager

export type RescueManager = typeof(setmetatable(
	{} :: {
		radioPrompt: ProximityPrompt?,
		radioConnection: RBXScriptConnection?,
		boardPrompt: ProximityPrompt?,
		boardConnection: RBXScriptConnection?,
		helicopter: Model?,
		isCalled: boolean,
		isLanded: boolean,
		landingTime: number,
		landedTime: number,
		seatByPlayer: { [Player]: Seat },
		hasDeparted: boolean,
	},
	RescueManager
))

local function partyConfig(): PartyRules.Config
	return PartyData :: any
end

function RescueManager:getPad(): Model?
	local camp = MapManager:getCamp()
	local pad = if camp then camp:FindFirstChild(Constants.CAMP_HELICOPTER_PAD_MODEL) else nil
	return if pad and pad:IsA("Model") then pad else nil
end

-- the radio's authored prompt, on Camp.Radio.PromptPart
function RescueManager:getRadioPrompt(): ProximityPrompt?
	local camp = MapManager:getCamp()
	local radio = if camp then camp:FindFirstChild(Constants.CAMP_RADIO_MODEL) else nil
	local promptPart = if radio then radio:FindFirstChild(Constants.RADIO_PROMPT_PART) else nil
	return if promptPart then promptPart:FindFirstChildWhichIsA("ProximityPrompt") else nil
end

function RescueManager:isTargetReached(): boolean
	return RescueRules.isTargetReached(RefineryManager:getUraniumTotal(), RefineryManager:getUraniumTarget())
end

function RescueManager:getAboardCount(): number
	local count = 0
	for _ in self.seatByPlayer do
		count += 1
	end
	return count
end

-- Ready players whose character is up; until Revives (M32) that is everyone Ready
function RescueManager:getLivingPlayers(): { Player }
	local living = {}
	for _, player in GameController:getReadyPlayers() do
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid and humanoid.Health > 0 then
			table.insert(living, player)
		end
	end
	return living
end

function RescueManager:replicate()
	SplendidReplicationManager:setGameMetadata(Attributes.RESCUE_IS_LANDED, self.isLanded)
	SplendidReplicationManager:setGameMetadata(Attributes.RESCUE_ABOARD_COUNT, self:getAboardCount())
	SplendidReplicationManager:setGameMetadata(Attributes.RESCUE_CREW_COUNT, #self:getLivingPlayers())
end

function RescueManager:announce(message: string)
	NetManager:notifyAllClients(NetEventNames.NOTIFY_RESCUE_ANNOUNCEMENT, {
		message = message,
		displaySec = RescueData.ANNOUNCEMENT_DISPLAY_SEC,
	})
end

-- the radio works only while a run is on and the target is refined; the
-- prompt's Enabled replicates, so clients see it come alive
function RescueManager:refreshRadio()
	local prompt = self.radioPrompt
	if not prompt then
		return
	end
	local state = RunCycleManager:getRunState()
	local isRunOn = state == Enums.RunState.DAY or state == Enums.RunState.NIGHT
	prompt.Enabled = isRunOn and not self.isCalled and self:isTargetReached()
end

function RescueManager:call(player: Player)
	if not GameController:isPlayerReady(player) or self.isCalled then
		return
	end
	if not self:isTargetReached() then
		PlayerFeedbackManager:give(player, RescueData.NOT_READY_FEEDBACK)
		return
	end
	local state = RunCycleManager:getRunState()
	if state ~= Enums.RunState.DAY and state ~= Enums.RunState.NIGHT then
		return
	end
	self.isCalled = true
	local now = workspace:GetServerTimeNow()
	self.landingTime = now + RescueData.RESCUE_FLIGHT_SEC
	self:refreshRadio()
	print(`[RescueManager] {player.Name} called the rescue helicopter; landing in {RescueData.RESCUE_FLIGHT_SEC} s`)
	RunCycleManager:startRescue(self.landingTime)
	MonsterWaveManager:startFinalWave(RescueRules.finalWaveNight(RunCycleManager:getDay()), RescueData.FINAL_WAVE_MULTIPLIER)
	self:replicate()
	self:announce(RescueData.CALLED_MESSAGE)
end

function RescueManager:land()
	local pad = self:getPad()
	local spawnPart = if pad then pad:FindFirstChild(Constants.PAD_HELICOPTER_SPAWN_PART) else nil
	if not pad or not spawnPart or not spawnPart:IsA("BasePart") then
		warn("RescueManager: the camp has no HelicopterPad.HelicopterSpawn to land on")
		return
	end
	self.isLanded = true
	self.landedTime = workspace:GetServerTimeNow()
	RunCycleManager:setRescueEnd(self.landedTime + RescueData.BOARDING_TIMEOUT_SEC)
	self.helicopter = HelicopterManager:spawnAt(spawnPart, pad, Enums.HelicopterPhase.SPINNING)
	-- the prompt sits on the pad's spawn part, which the helicopter stands
	-- on, so it is where the helicopter is without depending on the model
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = RescueData.BOARD_PROMPT_ACTION_TEXT
	prompt.ObjectText = RescueData.BOARD_PROMPT_OBJECT_TEXT
	prompt.MaxActivationDistance = RescueData.BOARD_PROMPT_MAX_DISTANCE_STUDS
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = spawnPart
	self.boardPrompt = prompt
	self.boardConnection = prompt.Triggered:Connect(
		function(player: Player)
			self:board(player)
		end
	)
	print("[RescueManager] the rescue helicopter has landed")
	self:replicate()
	self:announce(RescueData.LANDED_MESSAGE)
end

-- the lobby's seating: the seat is enabled only for this Sit, so the
-- engine never seats a passer-by, and Sit brings the character to it
function RescueManager:board(player: Player)
	if not GameController:isPlayerReady(player) or not self.isLanded or self.hasDeparted then
		return
	end
	if self.seatByPlayer[player] then
		PlayerFeedbackManager:give(player, RescueData.ALREADY_ABOARD_FEEDBACK)
		return
	end
	local helicopter = self.helicopter
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not helicopter or not humanoid or humanoid.Health <= 0 then
		return
	end
	local taken: { [Seat]: boolean } = {}
	for _, seat in self.seatByPlayer do
		taken[seat] = true
	end
	local free: Seat? = nil
	for _, seat in HelicopterManager:getSeats(helicopter) do
		if not taken[seat] and seat.Occupant == nil then
			free = seat
			break
		end
	end
	if not free then
		PlayerFeedbackManager:give(player, RescueData.NO_SEAT_FEEDBACK)
		return
	end
	free.Disabled = false
	free:Sit(humanoid)
	self.seatByPlayer[player] = free
	print(`[RescueManager] {player.Name} is aboard`)
	self:replicate()
	self:departIfNeeded(workspace:GetServerTimeNow())
end

function RescueManager:departIfNeeded(now: number)
	if self.hasDeparted or not self.isLanded then
		return
	end
	if not RescueRules.shouldDepart(self:getAboardCount(), #self:getLivingPlayers(), self.landedTime, now, RescueData.BOARDING_TIMEOUT_SEC) then
		return
	end
	self:depart()
end

-- a completion is one string key; a player records it only when they hold
-- the map's and the difficulty's prerequisites themselves
function RescueManager:recordCompletion(player: Player)
	local map = RunManager:getMap()
	local difficulty = RunManager:getDifficulty()
	local playerData = GameController:getPlayerData(player)
	if not map or not difficulty or not playerData then
		return
	end
	local key = CompletionKeys.make(map, difficulty)
	if not key then
		return
	end
	local config = partyConfig()
	local requirementKeys = {}
	for _, requirementKey in { PartyRules.getMapRequirementKey(config, map), PartyRules.getDifficultyRequirementKey(config, map, difficulty) } do
		if requirementKey then
			table.insert(requirementKeys, requirementKey)
		end
	end
	local isAllowed = RescueRules.canRecordCompletion(
		function(completionKey: string): boolean
			return playerData:hasCompletion(completionKey)
		end,
		requirementKeys
	)
	if not isAllowed then
		print(`[RescueManager] {player.Name} made it out but has not completed the prerequisite; {key} not recorded`)
		return
	end
	playerData:addCompletion(key)
	SplendidReplicationManager:replicateCompletions(player)
	print(`[RescueManager] {player.Name} completed {key}`)
end

-- everyone aboard wins; the helicopter flies off on every client (the
-- seated characters ride the model there) and the run is over. The trip
-- back to the lobby is M33
function RescueManager:depart()
	self.hasDeparted = true
	local prompt = self.boardPrompt
	if prompt then
		prompt.Enabled = false
	end
	local aboardNames = {}
	for player in self.seatByPlayer do
		table.insert(aboardNames, player.DisplayName)
		self:recordCompletion(player)
	end
	table.sort(aboardNames)
	local helicopter = self.helicopter
	if helicopter then
		HelicopterManager:retire(helicopter, RescueData.DEPARTED_HELICOPTER_LIFETIME_SEC)
	end
	local message = RescueRules.wonMessage(aboardNames, #self:getLivingPlayers(), RescueData.WON_ALL_MESSAGE, RescueData.WON_SOME_FORMAT)
	RunCycleManager:endRun(true, message)
end

function RescueManager:step()
	if not self.isCalled or self.hasDeparted then
		return
	end
	-- a run lost while the helicopter was on its way gets no landing
	if RunCycleRules.isRunOver(RunCycleManager:getRunState()) then
		return
	end
	local now = workspace:GetServerTimeNow()
	if not self.isLanded then
		if now >= self.landingTime then
			self:land()
		end
		return
	end
	self:departIfNeeded(now)
end

-- binds the loaded camp's radio prompt (the designer's words and reach
-- stay); the previous camp's connection dies with its instance but is
-- dropped here so a restart never hears two radios
function RescueManager:bindRadio()
	local previous = self.radioConnection
	if previous then
		previous:Disconnect()
		self.radioConnection = nil
	end
	self.radioPrompt = nil
	local prompt = self:getRadioPrompt()
	if not prompt then
		warn(`RescueManager: the loaded camp has no {Constants.CAMP_RADIO_MODEL}.{Constants.RADIO_PROMPT_PART} with a ProximityPrompt; the rescue cannot be called`)
		return
	end
	prompt.Enabled = false
	self.radioPrompt = prompt
	self.radioConnection = prompt.Triggered:Connect(
		function(player: Player)
			self:call(player)
		end
	)
	self:refreshRadio()
end

function RescueManager:onRunStarted()
	local connection = self.boardConnection
	if connection then
		connection:Disconnect()
		self.boardConnection = nil
	end
	self.boardPrompt = nil
	self.helicopter = nil
	self.isCalled = false
	self.isLanded = false
	self.landingTime = 0
	self.landedTime = 0
	self.seatByPlayer = {}
	self.hasDeparted = false
	self:bindRadio()
	self:replicate()
end

-- teardown-sequence entry (registered through GameController:registerPlaceManager)
function RescueManager:onPlayerRemoved(player: Player)
	if self.seatByPlayer[player] then
		self.seatByPlayer[player] = nil
		self:replicate()
	end
end

function RescueManager:init()
	RefineryManager:subscribeUraniumChanged(
		function()
			self:refreshRadio()
		end
	)
	RunCycleManager:subscribeRunEnded(
		function(_isWon: boolean)
			self:refreshRadio()
		end
	)
	GameController:registerPlaceManager(self)
	RunService.Heartbeat:Connect(
		function()
			self:step()
		end
	)
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self:onPlayerRemoved(player)
		end
	)
end

function RescueManager.new(): RescueManager
	local self = setmetatable({}, RescueManager) :: RescueManager
	self.radioPrompt = nil
	self.radioConnection = nil
	self.boardPrompt = nil
	self.boardConnection = nil
	self.helicopter = nil
	self.isCalled = false
	self.isLanded = false
	self.landingTime = 0
	self.landedTime = 0
	self.seatByPlayer = {}
	self.hasDeparted = false
	return self
end

return RescueManager.new()
