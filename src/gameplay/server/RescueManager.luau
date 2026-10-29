--!strict

-- The rescue (GDD "Gameplay Loop", "Helicopter Pad"), M31: the way a run
-- is won. Once the crew has refined the uranium target (RefineryManager),
-- the designer's radio (Camp.Radio; its authored ProximityPrompt on
-- PromptPart is enabled only then) calls the rescue helicopter: the run
-- holds in its Rescue Wait for FINAL_WAVE_DELAY_SEC (the clock stops, a
-- countdown to the final wave; 2026-10-07), then enters its Rescue state
-- (RunCycleManager: night look, gate shut, a countdown to landing) as
-- MonsterWaveManager spawns the final wave while the helicopter flies in.
-- APPROACH_SEC before the landing the company helicopter is spawned at
-- the far end of the run-start departure, straight out along the pad's
-- facing down the canyon (HelicopterManager), and every client flies it
-- back in along it (M75; designer, 2026-10-27); at the landing time it is
-- set down on the pad, and a standing player who touches it is seated
-- (checked by the server from the model's bounds; a Board prompt before
-- 2026-10-27). It leaves once
-- everyone standing is aboard, BOARDING_TIMEOUT_SEC after landing with
-- someone aboard, or EMPTY_DEPARTURE_SEC after landing with nobody
-- aboard, which loses the run (pure RescueRules; M75). With riders the
-- run ends Won, and every player aboard whose own progression allows it
-- records the completion (PlayerData, replicated so the lobby's Create
-- Party menu unlocks it). Tuning is GameData/Run/Rescue. What clients
-- need is GameMetadata: the landing time and then the departure deadline
-- are the run's phase end, plus whether it has landed and how many are
-- aboard of how many standing (ClientRescueManager draws the radio's
-- billboard and the countdown from these).
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
local DiamondTapManager = require(script.Parent.DiamondTapManager)
local MapManager = require(script.Parent.MapManager)
local MonsterManager = require(script.Parent.MonsterManager)
local MonsterWaveManager = require(script.Parent.MonsterWaveManager)
local RefineryManager = require(script.Parent.RefineryManager)
local ReviveManager = require(script.Parent.ReviveManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunManager = require(script.Parent.RunManager)
local RunPauseManager = require(script.Parent.RunPauseManager)

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
		-- the final wave has been started (the wait is over)
		isWaveStarted: boolean,
		waveStartTime: number,
		-- when the call was made, and whether the mine's monsters have been
		-- faded away at its INCOMING flash (DISPATCH_SEC after it)
		callTime: number,
		isMineCleared: boolean,
		-- when the breather's countdown begins, after the clients' call sequence
		countdownStartTime: number,
		-- the helicopter is in the air on its way in
		isApproaching: boolean,
		isLanded: boolean,
		-- the green ready line goes out once per run
		isReadyAnnounced: boolean?,
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

function RescueManager:getPadPart(name: string): BasePart?
	local pad = self:getPad()
	local part = if pad then pad:FindFirstChild(name) else nil
	return if part and part:IsA("BasePart") then part else nil
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

-- Ready players who are not dead (ReviveManager, M32): who the helicopter waits for
function RescueManager:getLivingPlayers(): { Player }
	return ReviveManager:getLivingPlayers()
end

function RescueManager:replicate()
	SplendidReplicationManager:setGameMetadata(Attributes.RESCUE_COUNTDOWN_START_TIME, self.countdownStartTime)
	SplendidReplicationManager:setGameMetadata(Attributes.RESCUE_SUNSET_START_TIME, self.sunsetStartTime)
	SplendidReplicationManager:setGameMetadata(Attributes.RESCUE_IS_LANDED, self.isLanded)
	SplendidReplicationManager:setGameMetadata(Attributes.RESCUE_ABOARD_COUNT, self:getAboardCount())
	SplendidReplicationManager:setGameMetadata(Attributes.RESCUE_CREW_COUNT, #self:getLivingPlayers())
end

function RescueManager:announce(message: string, isGood: boolean?)
	NetManager:notifyAllClients(NetEventNames.NOTIFY_RESCUE_ANNOUNCEMENT, {
		message = message,
		displaySec = RescueData.ANNOUNCEMENT_DISPLAY_SEC,
		isGood = isGood == true,
	})
end

-- the first time the target is refined in a run, everyone hears it
function RescueManager:announceReadyIfNeeded()
	if self.isReadyAnnounced or not self:isTargetReached() then
		return
	end
	local state = RunCycleManager:getRunState()
	if state ~= Enums.RunState.DAY and state ~= Enums.RunState.NIGHT then
		return
	end
	self.isReadyAnnounced = true
	self:announce(RescueData.READY_MESSAGE, true)
end

-- the radio works only while a run is on and the target is refined; the
-- prompt's Enabled replicates, so clients see it come alive. It stays
-- live through the night so a night call can be answered (the call
-- itself is day-only)
function RescueManager:refreshRadio()
	local prompt = self.radioPrompt
	if not prompt then
		return
	end
	local state = RunCycleManager:getRunState()
	local isRunOn = state == Enums.RunState.DAY or state == Enums.RunState.NIGHT
	prompt.ClickablePrompt = false
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
	-- by day only (designer, 2026-10-27): the prompt stays live at night so
	-- the radio can say why
	if state == Enums.RunState.NIGHT then
		PlayerFeedbackManager:give(player, RescueData.NIGHT_FEEDBACK)
		return
	end
	self.isCalled = true
	self.isWaveStarted = false
	local now = workspace:GetServerTimeNow()
	self.callTime = now
	self.isMineCleared = false
	-- the breather begins once the clients' call sequence has played
	self.countdownStartTime = now + RescueData.CALL_SEQUENCE_SEC
	self.waveStartTime = self.countdownStartTime + RescueData.FINAL_WAVE_DELAY_SEC
	self.landingTime = self.waveStartTime + RescueData.RESCUE_FLIGHT_SEC
	self:refreshRadio()
	print(`[RescueManager] {player.Name} called the rescue helicopter; the final wave in {RescueData.CALL_SEQUENCE_SEC + RescueData.FINAL_WAVE_DELAY_SEC} s, landing {RescueData.RESCUE_FLIGHT_SEC} s after`)
	RunCycleManager:startRescueWait(self.waveStartTime)
	self:replicate()
	-- no announcement: the clients' RESCUE HELICOPTER INCOMING flash is
	-- the word (designer, 2026-10-27)
end

-- the wait is up: night falls, the final wave spawns, the helicopter is
-- in the air with the landing as the phase end
function RescueManager:startWave()
	self.isWaveStarted = true
	RunCycleManager:startRescue(self.landingTime)
	MonsterWaveManager:startFinalWave(RescueRules.finalWaveNight(RunCycleManager:getDay()), RescueData.FINAL_WAVE_MULTIPLIER)
end

-- the approach is in the air for the last APPROACH_SEC of the flight,
-- never longer than the flight itself
function RescueManager:getApproachSec(): number
	return math.min(RescueData.APPROACH_SEC, RescueData.RESCUE_FLIGHT_SEC)
end

-- the helicopter appears far down the canyon and flies in (M75): the
-- clients draw the whole approach from its start time, so it is only
-- spawned here. It comes back the way the run's first helicopter left,
-- along the pad's own facing (designer, 2026-10-27: that path runs
-- straight down the canyon), which spawnApproaching takes for a nil
-- heading; it leaves the same way (a DepartureHeading part gave the
-- rescue its own way out until later that day)
function RescueManager:launchApproach()
	self.isApproaching = true
	local pad = self:getPad()
	local spawnPart = self:getPadPart(Constants.PAD_HELICOPTER_SPAWN_PART)
	if not pad or not spawnPart then
		return
	end
	self.helicopter = HelicopterManager:spawnApproaching(spawnPart, nil, pad, self.landingTime - self:getApproachSec())
	print("[RescueManager] the rescue helicopter is coming in")
end

-- a standing player whose body is within the margin of the landed
-- helicopter's box boards (designer, 2026-10-27: touch, not a prompt);
-- the server judges it from the model's bounds each step, so no touch
-- event from a client is trusted
function RescueManager:boardTouchingPlayers()
	local helicopter = self.helicopter
	if not helicopter or not helicopter.Parent then
		return
	end
	local boxCFrame, boxSize = helicopter:GetBoundingBox()
	local halfSize = boxSize / 2 + Vector3.one * RescueData.BOARD_TOUCH_MARGIN_STUDS
	for _, player in Players:GetPlayers() do
		local seat = self.seatByPlayer[player]
		local character = player.Character
		if seat then
			-- a seat that did not take (a rider holding Jump for the jet
			-- pack as they boarded) is tried again for as long as the
			-- helicopter stands; the client stops the rider jumping once
			-- seated, so the second try holds
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			if humanoid and seat.Occupant == nil and humanoid.Health > 0 and seat.Parent then
				seat:Sit(humanoid)
			end
			continue
		end
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not root or not root:IsA("BasePart") then
			continue
		end
		local localPosition = boxCFrame:PointToObjectSpace(root.Position)
		if math.abs(localPosition.X) <= halfSize.X and math.abs(localPosition.Y) <= halfSize.Y and math.abs(localPosition.Z) <= halfSize.Z then
			self:board(player)
		end
	end
end

-- the deadline the countdown shows: the boarding window once someone is
-- aboard, else the empty window
function RescueManager:getDepartureDeadline(): number
	local windowSec = if self:getAboardCount() > 0 then RescueData.BOARDING_TIMEOUT_SEC else RescueData.EMPTY_DEPARTURE_SEC
	return self.landedTime + windowSec
end

function RescueManager:land()
	local pad = self:getPad()
	local spawnPart = self:getPadPart(Constants.PAD_HELICOPTER_SPAWN_PART)
	if not pad or not spawnPart then
		warn("RescueManager: the camp has no HelicopterPad.HelicopterSpawn to land on")
		return
	end
	self.isLanded = true
	self.landedTime = workspace:GetServerTimeNow()
	local helicopter = self.helicopter
	if helicopter and helicopter.Parent then
		HelicopterManager:land(helicopter, spawnPart)
	else
		helicopter = HelicopterManager:spawnAt(spawnPart, pad, Enums.HelicopterPhase.SPINNING)
		self.helicopter = helicopter
	end
	RunCycleManager:setRescueEnd(self:getDepartureDeadline())
	print("[RescueManager] the rescue helicopter has landed")
	-- no line: the countdown and its alert tell it (designer, 2026-10-27)
	self:replicate()
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
	if not helicopter or not humanoid or humanoid.Health <= 0 or ReviveManager:isDead(player) then
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
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.RESCUE_IS_ABOARD, true)
	-- a rider's body flies 2000 studs off with the helicopter while their
	-- camera stays at the pad, so streaming follows the pad, not the body,
	-- or the camp would vanish behind the shot (designer, 2026-10-27)
	player.ReplicationFocus = self:getPadPart(Constants.PAD_HELICOPTER_SPAWN_PART)
	print(`[RescueManager] {player.Name} is aboard`)
	-- the first rider starts the boarding window; no line for a boarder
	-- (designer, 2026-10-27: the chime and the countdown tell it)
	RunCycleManager:setRescueEnd(self:getDepartureDeadline())
	self:replicate()
	self:departIfNeeded(workspace:GetServerTimeNow())
end

-- every seated flag off, before the seats are forgotten
function RescueManager:clearAboardFlags()
	for player in self.seatByPlayer do
		if player.Parent then
			SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.RESCUE_IS_ABOARD, false)
			player.ReplicationFocus = nil
		end
	end
end

function RescueManager:departIfNeeded(now: number)
	if self.hasDeparted or not self.isLanded then
		return
	end
	local aboardCount = self:getAboardCount()
	if RescueRules.shouldDepart(aboardCount, #self:getLivingPlayers(), self.landedTime, now, RescueData.BOARDING_TIMEOUT_SEC) then
		self:depart()
		return
	end
	if RescueRules.shouldDepartEmpty(aboardCount, self.landedTime, now, RescueData.EMPTY_DEPARTURE_SEC) then
		self:departEmpty()
	end
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

-- the helicopter lifts off on every client along the pad's authored
-- heading (the seated characters ride the model)
function RescueManager:liftOff()
	self.hasDeparted = true
	local prompt = self.boardPrompt
	if prompt then
		prompt.Enabled = false
	end
	local helicopter = self.helicopter
	if not helicopter then
		return
	end
	-- out the way it came and the way the run's first helicopter left: the
	-- pad's own facing (designer, 2026-10-27)
	HelicopterManager:retire(helicopter, RescueData.DEPARTED_HELICOPTER_LIFETIME_SEC)
end

-- everyone aboard wins and the run is over
function RescueManager:depart()
	local aboardNames = {}
	for player in self.seatByPlayer do
		table.insert(aboardNames, player.DisplayName)
		self:recordCompletion(player)
		DiamondTapManager:payRescue(player)
	end
	table.sort(aboardNames)
	-- the sky turns back to a sunset as it leaves (designer, 2026-10-27)
	self.sunsetStartTime = workspace:GetServerTimeNow()
	self:replicate()
	self:liftOff()
	local message = RescueRules.wonMessage(aboardNames, #self:getLivingPlayers(), RescueData.WON_ALL_MESSAGE, RescueData.WON_SOME_FORMAT)
	RunCycleManager:endRun(true, message, Enums.RunEndReason.RESCUED)
end

-- nobody boarded in time: it leaves without them and the run is lost (M75)
function RescueManager:departEmpty()
	self:liftOff()
	print("[RescueManager] the rescue helicopter left empty")
	RunCycleManager:endRun(false, RescueData.LEFT_EMPTY_MESSAGE, Enums.RunEndReason.HELICOPTER_LEFT)
end

-- once the helicopter is on the pad the Refinery no longer matters
-- (designer, 2026-10-28): main.server asks this before a fallen Refinery
-- is allowed to lose the run
function RescueManager:isHelicopterLanded(): boolean
	return self.isLanded and not self.hasDeparted
end

-- the run was lost under it (the Refinery fell before the landing, the
-- crew died): a landed helicopter lifts off empty, one still in the air
-- turns away from where it is, and one not yet in the air never comes
function RescueManager:leaveOnLoss()
	if not self.isCalled or self.hasDeparted then
		return
	end
	local helicopter = self.helicopter
	if not helicopter or not helicopter.Parent then
		return
	end
	if self.isLanded then
		self:liftOff()
		return
	end
	self.hasDeparted = true
	HelicopterManager:abortApproach(helicopter, RescueData.DEPARTED_HELICOPTER_LIFETIME_SEC)
	print("[RescueManager] the rescue helicopter turns away; the run is lost")
end

function RescueManager:step()
	if RunPauseManager:isPaused() then
		return
	end
	if not self.isCalled or self.hasDeparted then
		return
	end
	-- a run lost while the helicopter was on its way gets no landing
	if RunCycleRules.isRunOver(RunCycleManager:getRunState()) then
		return
	end
	local now = workspace:GetServerTimeNow()
	if not self.isWaveStarted then
		-- the INCOMING flash is going up on the clients: the mine empties
		if not self.isMineCleared and now >= self.callTime + RescueData.DISPATCH_SEC then
			self.isMineCleared = true
			MonsterManager:fadeOutCrawlers()
			print("[RescueManager] the mine's monsters fade away")
		end
		if now >= self.waveStartTime then
			self:startWave()
		end
		return
	end
	if not self.isLanded then
		if not self.isApproaching and now >= self.landingTime - self:getApproachSec() then
			self:launchApproach()
		end
		if now >= self.landingTime then
			self:land()
		end
		return
	end
	self:boardTouchingPlayers()
	self:departIfNeeded(now)
end

-- the dev tool's pause lifted: the wave, the landing, and a flight in
-- the air are as far off as they were, like the run's own phase end
function RescueManager:onResumed(pausedSec: number)
	if not self.isCalled or self.hasDeparted then
		return
	end
	if not self.isWaveStarted then
		self.waveStartTime += pausedSec
		self.countdownStartTime += pausedSec
		self:replicate()
	end
	if not self.isLanded then
		self.landingTime += pausedSec
		local helicopter = self.helicopter
		if self.isApproaching and helicopter then
			HelicopterManager:shiftFlightStart(helicopter, pausedSec)
		end
	end
end

function RescueManager:dropBoardPrompt()
	local connection = self.boardConnection
	if connection then
		connection:Disconnect()
		self.boardConnection = nil
	end
	local prompt = self.boardPrompt
	if prompt then
		-- the template's own prompt goes with the model; one made here is dropped
		if prompt.Name == Constants.HELICOPTER_BOARD_PROMPT then
			prompt.Enabled = false
		else
			prompt:Destroy()
		end
		self.boardPrompt = nil
	end
end

-- the Team Revive (M32) starts the day over: a rescue under way is called
-- off, the helicopter goes, and the radio can be used again once the
-- crew is ready
function RescueManager:cancel()
	if not self.isCalled or self.hasDeparted then
		return
	end
	self:dropBoardPrompt()
	local helicopter = self.helicopter
	if helicopter then
		helicopter:Destroy()
		self.helicopter = nil
	end
	self.isCalled = false
	self.isWaveStarted = false
	self.waveStartTime = 0
	self.countdownStartTime = 0
	self.callTime = 0
	self.isMineCleared = false
	self.isApproaching = false
	self.isLanded = false
	self.landingTime = 0
	self.landedTime = 0
	self:clearAboardFlags()
	self.seatByPlayer = {}
	self.sunsetStartTime = 0
	print("[RescueManager] the rescue is called off; the day starts over")
	self:refreshRadio()
	self:replicate()
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
	self.isReadyAnnounced = false
	local connection = self.boardConnection
	if connection then
		connection:Disconnect()
		self.boardConnection = nil
	end
	self.boardPrompt = nil
	self.helicopter = nil
	self.isCalled = false
	self.isWaveStarted = false
	self.waveStartTime = 0
	self.countdownStartTime = 0
	self.callTime = 0
	self.isMineCleared = false
	self.isApproaching = false
	self.isLanded = false
	self.landingTime = 0
	self.landedTime = 0
	self:clearAboardFlags()
	self.seatByPlayer = {}
	self.sunsetStartTime = 0
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
	SplendidReplicationManager:setGameMetadata(Attributes.RESCUE_APPROACH_SEC, self:getApproachSec())
	SplendidReplicationManager:setGameMetadata(Attributes.RESCUE_RIDE_SEC, RescueData.RIDE_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.RESCUE_SUNSET_TO_DAY_END_SEC, RescueData.SUNSET_TO_DAY_END_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.RESCUE_SUNSET_TO_DAY_START_SEC, RescueData.SUNSET_TO_DAY_START_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.RESCUE_SUNSET_FINAL_TO_DAY_START_SEC, RescueData.SUNSET_FINAL_TO_DAY_START_SEC)
	RunPauseManager:subscribeResumed(
		function(pausedSec: number)
			self:onResumed(pausedSec)
		end
	)
	RefineryManager:subscribeUraniumChanged(
		function()
			self:refreshRadio()
			self:announceReadyIfNeeded()
		end
	)
	RunCycleManager:subscribeRunEnded(
		function(isWon: boolean)
			self:refreshRadio()
			if not isWon then
				self:leaveOnLoss()
			end
		end
	)
	-- a restarted day (the Team Revive) is a day again, so the radio wakes
	RunCycleManager:subscribeDayStarted(
		function()
			self:refreshRadio()
		end
	)
	-- someone aboard who dies gives up their seat, and the helicopter
	-- stops waiting for anyone who is dead
	ReviveManager:subscribeDied(
		function(player: Player)
			self.seatByPlayer[player] = nil
			self:replicate()
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
	self.sunsetStartTime = 0
	self.radioPrompt = nil
	self.radioConnection = nil
	self.boardPrompt = nil
	self.boardConnection = nil
	self.helicopter = nil
	self.isCalled = false
	self.isWaveStarted = false
	self.waveStartTime = 0
	self.countdownStartTime = 0
	self.callTime = 0
	self.isMineCleared = false
	self.isApproaching = false
	self.isLanded = false
	self.landingTime = 0
	self.landedTime = 0
	self.seatByPlayer = {}
	self.hasDeparted = false
	return self
end

return RescueManager.new()
