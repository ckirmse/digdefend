--!strict

-- Owns one party record per helicopter pad (GDD "Helicopter Pads – Party
-- Creation/Teleports"). State lives here in Lua; the pad model only carries
-- the attributes clients need to render the billboard and menus, and this
-- manager is their only writer. M11 covers records, transitions, and
-- replication; M12 adds touch handling, seating, timers, and the menus'
-- messages; M13 the launch: takeoff, holding area, one party teleport to a
-- reserved gameplay server, failure recovery, and the pad reset.
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PartyRules = require("@game/ReplicatedStorage/Shared/PartyRules")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local PartyData = require("@game/ServerScriptService/GameData/Pads/Party")
local GameController = require(script.Parent.Parent.Server.GameController)
local HelicopterManager = require(script.Parent.Parent.Server.HelicopterManager)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local PartyManager = {}
PartyManager.__index = PartyManager

export type Party = {
	padIndex: number,
	model: Model,
	state: number,
	-- ordered by join time so host promotion picks the earliest joiner
	members: { Player },
	hostUserId: number,
	map: number?,
	difficulty: number?,
	maxPlayers: number,
	visibility: number,
	-- server time the active timer expires; 0 when no timer runs
	timerEndTime: number,
	-- the helicopter currently on the pad and who sits where
	helicopter: Model?,
	seatByPlayer: { [Player]: Seat },
}

export type PartyManager = typeof(setmetatable(
	{} :: {
		partiesByPadIndex: { [number]: Party },
		lastTouchTimeByPlayer: { [Player]: number },
	},
	PartyManager
))

local NO_HOST = 0
local NO_TIMER = 0
-- lifts a character clear of the ExitSpawn part so it does not spawn inside it
local EXIT_LIFT = Vector3.new(0, 3, 0)
local EXIT_MOVE_DELAY_SEC = 0.1

local EMPTY_SHAPE = {}

function PartyManager:getConfig(): PartyRules.Config
	return PartyData :: PartyRules.Config
end

function PartyManager:getParty(padIndex: number): Party?
	return self.partiesByPadIndex[padIndex]
end

function PartyManager:getParties(): { Party }
	local parties = {}
	for padIndex = 1, Constants.PAD_COUNT do
		local party = self.partiesByPadIndex[padIndex]
		if party then
			table.insert(parties, party)
		end
	end
	return parties
end

function PartyManager:getPartyOfPlayer(player: Player): Party?
	for _, party in self.partiesByPadIndex do
		if table.find(party.members, player) then
			return party
		end
	end
	return nil
end

function PartyManager:getHost(party: Party): Player?
	for _, member in party.members do
		if member.UserId == party.hostUserId then
			return member
		end
	end
	return nil
end

function PartyManager:isHost(party: Party, player: Player): boolean
	return party.hostUserId == player.UserId and table.find(party.members, player) ~= nil
end

function PartyManager:isFull(party: Party): boolean
	return #party.members >= party.maxPlayers
end

-- the one place pad attributes are written
function PartyManager:replicate(party: Party)
	local model = party.model
	model:SetAttribute(Attributes.PAD_STATE, party.state)
	model:SetAttribute(Attributes.PAD_HOST_USER_ID, party.hostUserId)
	model:SetAttribute(Attributes.PAD_MAP, party.map)
	model:SetAttribute(Attributes.PAD_DIFFICULTY, party.difficulty)
	model:SetAttribute(Attributes.PAD_MAX_PLAYERS, party.maxPlayers)
	model:SetAttribute(Attributes.PAD_VISIBILITY, party.visibility)
	model:SetAttribute(Attributes.PAD_PLAYER_COUNT, #party.members)
	model:SetAttribute(Attributes.PAD_TIMER_END_TIME, party.timerEndTime)
end

function PartyManager:setTimer(party: Party, durationSec: number)
	party.timerEndTime = workspace:GetServerTimeNow() + durationSec
	self:replicate(party)
end

function PartyManager:clearTimer(party: Party)
	party.timerEndTime = NO_TIMER
	self:replicate(party)
end

function PartyManager:getTimerRemainingSec(party: Party): number
	if party.timerEndTime == NO_TIMER then
		return 0
	end
	return math.max(0, party.timerEndTime - workspace:GetServerTimeNow())
end

-- Idle: empty pad, no host, no settings
function PartyManager:setIdle(party: Party)
	party.state = Enums.PadState.IDLE
	party.members = {}
	party.hostUserId = NO_HOST
	party.map = nil
	party.difficulty = nil
	-- the billboard always shows count/size, so an empty pad reads "0/MAX"
	party.maxPlayers = self:getConfig().MAX_PARTY_SIZE
	party.visibility = self:getConfig().DEFAULT_VISIBILITY
	party.timerEndTime = NO_TIMER
	party.seatByPlayer = {}
	self:replicate(party)
	self:syncHelicopterPhase(party)
end

-- Configuring: the host holds the pad while on the Create Party menu
function PartyManager:setConfiguring(party: Party, host: Player)
	if party.state ~= Enums.PadState.IDLE then
		warn(`PartyManager: pad {party.padIndex} cannot start configuring from state {party.state}`)
		return
	end
	party.state = Enums.PadState.CONFIGURING
	party.members = { host }
	party.hostUserId = host.UserId
	-- the stepper's ceiling while configuring; the host's real choice arrives with Create
	party.maxPlayers = self:getConfig().MAX_PARTY_SIZE
	party.timerEndTime = workspace:GetServerTimeNow() + self:getConfig().CREATION_TIMEOUT_SEC
	self:replicate(party)
end

-- Boarding: settings committed, accepting joiners until launch
function PartyManager:setBoarding(party: Party, selection: PartyRules.Selection)
	if party.state ~= Enums.PadState.CONFIGURING then
		warn(`PartyManager: pad {party.padIndex} cannot start boarding from state {party.state}`)
		return
	end
	party.state = Enums.PadState.BOARDING
	party.map = selection.map
	party.difficulty = selection.difficulty
	party.maxPlayers = selection.maxPlayers
	party.visibility = selection.visibility
	party.timerEndTime = workspace:GetServerTimeNow() + self:getConfig().BOARDING_TIMEOUT_SEC
	-- a party of one is full the moment it is created
	self:shortenTimerIfFull(party)
	self:replicate(party)
	self:syncHelicopterPhase(party)
end

-- GDD: a full party launches soon; the timer only ever shortens
function PartyManager:shortenTimerIfFull(party: Party)
	if not self:isFull(party) then
		return
	end
	party.timerEndTime = PartyRules.getTimerEndTimeOnFull(
		party.timerEndTime,
		workspace:GetServerTimeNow(),
		self:getConfig().CAPACITY_TIME_SEC
	)
end

-- Departing: teleport in progress; the record is cleared by setIdle afterward
function PartyManager:setDeparting(party: Party)
	if party.state ~= Enums.PadState.BOARDING then
		warn(`PartyManager: pad {party.padIndex} cannot depart from state {party.state}`)
		return
	end
	party.state = Enums.PadState.DEPARTING
	party.timerEndTime = NO_TIMER
	self:replicate(party)
	self:syncHelicopterPhase(party)
end

function PartyManager:addMember(party: Party, player: Player)
	if table.find(party.members, player) then
		return
	end
	table.insert(party.members, player)
	self:shortenTimerIfFull(party)
	self:replicate(party)
end

-- removes the player; promotes the earliest joiner if the host left, idles
-- the pad if nobody is left. Returns the new host when one was promoted.
function PartyManager:removeMember(party: Party, player: Player): Player?
	local index = table.find(party.members, player)
	if not index then
		return nil
	end
	table.remove(party.members, index)
	party.seatByPlayer[player] = nil
	if #party.members == 0 then
		-- a departing pad is reset by the launch flow itself, never underneath it
		if party.state ~= Enums.PadState.DEPARTING then
			self:setIdle(party)
		end
		return nil
	end
	local promotedHost: Player? = nil
	if party.hostUserId == player.UserId then
		promotedHost = party.members[1]
		party.hostUserId = promotedHost.UserId
	end
	self:replicate(party)
	return promotedHost
end

function PartyManager:notifyMenu(player: Player, menu: number, party: Party?)
	NetManager:notifyClient(
		player,
		NetEventNames.NOTIFY_PARTY_MENU,
		{
			menu = menu,
			padIndex = if party then party.padIndex else 0,
			isHost = if party then self:isHost(party, player) else false,
		}
	)
end

function PartyManager:getSeats(party: Party): { Seat }
	local helicopter = party.helicopter
	if not helicopter then
		return {}
	end
	return HelicopterManager:getSeats(helicopter)
end

-- the helicopter's visuals follow the pad: rotor from Create, flight at launch
function PartyManager:syncHelicopterPhase(party: Party)
	local helicopter = party.helicopter
	if not helicopter then
		return
	end
	local phase = Enums.HelicopterPhase.IDLE
	if party.state == Enums.PadState.BOARDING then
		phase = Enums.HelicopterPhase.SPINNING
	elseif party.state == Enums.PadState.DEPARTING then
		phase = Enums.HelicopterPhase.FLYING
	end
	HelicopterManager:setPhase(helicopter, phase)
end

function PartyManager:findFreeSeat(party: Party): Seat?
	local taken: { [Seat]: boolean } = {}
	for _, seat in party.seatByPlayer do
		taken[seat] = true
	end
	for _, seat in self:getSeats(party) do
		if not taken[seat] and seat.Occupant == nil then
			return seat
		end
	end
	return nil
end

function PartyManager:seatPlayer(party: Party, player: Player, seat: Seat): boolean
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not character or not humanoid then
		warn(`PartyManager: {player.Name} has no character to seat`)
		return false
	end
	party.seatByPlayer[player] = seat
	-- Sit needs the character clear of any other seat weld first
	humanoid.Sit = false
	character:PivotTo(seat.CFrame + Vector3.new(0, 2, 0))
	-- seats stay Disabled so a character brushing the helicopter is never
	-- auto-seated by the engine; only this call seats anyone, and the seat is
	-- disabled again once it empties (disabling an occupied seat ejects)
	seat.Disabled = false
	seat:Sit(humanoid)
	return true
end

function PartyManager:moveToExit(party: Party, player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local seat = party.seatByPlayer[player]
	if seat then
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	if humanoid then
		humanoid.Sit = false
	end
	local exitSpawn = party.model:FindFirstChild(Constants.PAD_EXIT_SPAWN_PART)
	if exitSpawn and exitSpawn:IsA("BasePart") then
		-- the engine settles the character at the seat as it stands up; a move
		-- in the same frame is undone, so it waits a beat (still inside the
		-- touch grace window)
		task.delay(
			EXIT_MOVE_DELAY_SEC,
			function()
				character:PivotTo(CFrame.new(exitSpawn.Position + EXIT_LIFT))
			end
		)
	end
end

-- the single leave path: Exit button, leaving the seat, disconnecting,
-- timeouts, and the dev-tool reset all end here. Idempotent.
function PartyManager:leaveParty(player: Player, isDisconnecting: boolean)
	local party = self:getPartyOfPlayer(player)
	if not party then
		return
	end
	-- a Touched event from the seat can still arrive after the character has
	-- been moved out; the debounce window keeps it from re-hosting the leaver
	self.lastTouchTimeByPlayer[player] = workspace:GetServerTimeNow()
	if not isDisconnecting then
		self:moveToExit(party, player)
		self:notifyMenu(player, Enums.PartyMenu.NONE, nil)
	end
	local promotedHost = self:removeMember(party, player)
	if promotedHost then
		PlayerFeedbackManager:give(promotedHost, PartyRules.FEEDBACK_NOW_HOST)
		self:notifyMenu(promotedHost, Enums.PartyMenu.QUEUE, party)
	end
end

function PartyManager:startHosting(party: Party, player: Player)
	local seat = self:findFreeSeat(party)
	if not seat then
		warn(`PartyManager: pad {party.padIndex} has no free seat for a host`)
		return
	end
	self:setConfiguring(party, player)
	if not self:seatPlayer(party, player, seat) then
		self:setIdle(party)
		return
	end
	self:notifyMenu(player, Enums.PartyMenu.CREATE, party)
end

function PartyManager:isFriendOfHost(party: Party, player: Player): boolean
	local isSuccess, isFriend = pcall(
		function()
			return player:IsFriendsWithAsync(party.hostUserId)
		end
	)
	if not isSuccess then
		warn(`PartyManager: IsFriendsWithAsync failed for {player.Name}:`, isFriend)
		return false
	end
	return isFriend == true
end

function PartyManager:tryJoin(party: Party, player: Player)
	local isFriendOfHost = false
	if party.state == Enums.PadState.BOARDING and party.visibility == Enums.PartyVisibility.FRIENDS_ONLY then
		isFriendOfHost = self:isFriendOfHost(party, player)
	end
	local rejection = PartyRules.getJoinRejection({
		padState = party.state,
		memberCount = #party.members,
		maxPlayers = party.maxPlayers,
		visibility = party.visibility,
		isAlreadyInParty = self:getPartyOfPlayer(player) ~= nil,
		isFriendOfHost = isFriendOfHost,
	})
	if rejection then
		PlayerFeedbackManager:give(player, rejection)
		return
	end
	local seat = self:findFreeSeat(party)
	if not seat then
		PlayerFeedbackManager:give(player, PartyRules.FEEDBACK_PARTY_FULL)
		return
	end
	if not self:seatPlayer(party, player, seat) then
		return
	end
	self:addMember(party, player)
	self:notifyMenu(player, Enums.PartyMenu.QUEUE, party)
end

function PartyManager:handleTouch(party: Party, player: Player)
	if not GameController:getPlayerData(player) then
		return
	end
	local now = workspace:GetServerTimeNow()
	local lastTouchTime = self.lastTouchTimeByPlayer[player] or 0
	if now - lastTouchTime < self:getConfig().TOUCH_DEBOUNCE_SEC then
		return
	end
	self.lastTouchTimeByPlayer[player] = now

	local currentParty = self:getPartyOfPlayer(player)
	if currentParty == party then
		return
	end
	if party.state == Enums.PadState.IDLE then
		if currentParty then
			PlayerFeedbackManager:give(player, PartyRules.FEEDBACK_ALREADY_IN_PARTY)
			return
		end
		self:startHosting(party, player)
		return
	end
	self:tryJoin(party, player)
end

function PartyManager:onSeatOccupantChanged(party: Party, seat: Seat)
	if seat.Occupant ~= nil then
		return
	end
	seat.Disabled = true
	-- the launch flow empties every seat itself on the way to the holding area
	if party.state == Enums.PadState.DEPARTING then
		return
	end
	for player, playerSeat in party.seatByPlayer do
		if playerSeat == seat then
			self:leaveParty(player, false)
			return
		end
	end
end

-- GDD: every pad has a helicopter sitting on it when the server starts
function PartyManager:placeHelicopter(party: Party)
	local helicopterSpawn = party.model:FindFirstChild(Constants.PAD_HELICOPTER_SPAWN_PART)
	if not helicopterSpawn or not helicopterSpawn:IsA("BasePart") then
		-- LobbyMapManager already reported what is missing
		return
	end
	local existing = party.model:FindFirstChild(Constants.HELICOPTER_TEMPLATE)
	if existing and existing:IsA("Model") then
		if party.state == Enums.PadState.DEPARTING then
			HelicopterManager:retire(existing, self:getConfig().DEPARTED_HELICOPTER_LIFETIME_SEC)
		else
			existing:Destroy()
		end
	end
	local helicopter = HelicopterManager:spawnAt(helicopterSpawn, party.model, Enums.HelicopterPhase.IDLE)
	party.helicopter = helicopter
	if not helicopter then
		return
	end
	for _, seat in HelicopterManager:getSeats(helicopter) do
		seat:GetPropertyChangedSignal("Occupant"):Connect(
			function()
				self:onSeatOccupantChanged(party, seat)
			end
		)
	end
end

function PartyManager:connectTouch(party: Party)
	local joinCollision = party.model:FindFirstChild(Constants.PAD_JOIN_COLLISION_PART)
	if not joinCollision or not joinCollision:IsA("BasePart") then
		return
	end
	joinCollision.Touched:Connect(
		function(hit: BasePart)
			local character = hit.Parent
			local player = if character and character:IsA("Model") then Players:GetPlayerFromCharacter(character) else nil
			if player then
				self:handleTouch(party, player)
			end
		end
	)
end

function PartyManager:getPresentMembers(party: Party): { Player }
	local present = {}
	for _, member in party.members do
		if member.Parent == Players then
			table.insert(present, member)
		end
	end
	return present
end

function PartyManager:getHoldingSpawns(): { BasePart }
	local spawns: { BasePart } = {}
	local holdingArea = workspace:FindFirstChild(Constants.HOLDING_AREA_FOLDER)
	local folder = if holdingArea then holdingArea:FindFirstChild(Constants.HOLDING_AREA_SPAWNS_FOLDER) else nil
	if not folder then
		return spawns
	end
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(spawns, child)
		end
	end
	return spawns
end

-- GDD: characters wait out the teleport under the map so a slow or failed
-- teleport never leaves avatars sitting in a helicopter that has "left"
function PartyManager:moveToHolding(party: Party, members: { Player })
	local spawns = self:getHoldingSpawns()
	if #spawns == 0 then
		warn("PartyManager: no holding area spawns; characters stay on the pad")
		return
	end
	local random = Random.new()
	for _, member in members do
		local character = member.Character
		if not character then
			continue
		end
		local seat = party.seatByPlayer[member]
		local weld = if seat then seat:FindFirstChild("SeatWeld") else nil
		if weld then
			weld:Destroy()
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Sit = false
		end
		local spawn = spawns[random:NextInteger(1, #spawns)]
		task.delay(
			EXIT_MOVE_DELAY_SEC,
			function()
				character:PivotTo(CFrame.new(spawn.Position + EXIT_LIFT))
			end
		)
	end
end

-- one reserve + one teleport call for the whole party, retried as a pair
function PartyManager:teleportParty(party: Party, members: { Player }): boolean
	local memberUserIds = {}
	for _, member in members do
		table.insert(memberUserIds, member.UserId)
	end
	local joinData = PartyRules.buildJoinData(
		party.map or 0,
		party.difficulty or 0,
		party.hostUserId,
		party.padIndex,
		memberUserIds
	)
	local config = self:getConfig()
	for attempt = 1, config.TELEPORT_RETRY_COUNT do
		local isSuccess, err = pcall(
			function()
				local accessCode = TeleportService:ReserveServer(Constants.GAMEPLAY_PLACE_ID)
				local options = Instance.new("TeleportOptions")
				options.ReservedServerAccessCode = accessCode
				options:SetTeleportData(joinData)
				TeleportService:TeleportAsync(Constants.GAMEPLAY_PLACE_ID, members, options)
			end
		)
		if isSuccess then
			print(`[PartyManager] pad {party.padIndex} teleported {#members} player(s)`)
			return true
		end
		warn(`PartyManager: teleport attempt {attempt} for pad {party.padIndex} failed:`, err)
		if attempt < config.TELEPORT_RETRY_COUNT then
			task.wait(config.TELEPORT_RETRY_DELAY_SEC)
		end
	end
	return false
end

-- GDD: a failed teleport respawns the player in SpawnZone with "Teleport
-- failed" (the one respawn the lobby is allowed to trigger itself)
function PartyManager:failTeleport(party: Party, members: { Player })
	for _, member in members do
		if member.Parent ~= Players then
			continue
		end
		self:notifyMenu(member, Enums.PartyMenu.NONE, nil)
		PlayerFeedbackManager:give(member, PartyRules.FEEDBACK_TELEPORT_FAILED)
		member:LoadCharacterAsync()
	end
end

-- fresh helicopter, cleared record, back to Idle; only the launch flow that
-- set Departing may reset, so an intervening state change is left alone
function PartyManager:resetPad(party: Party)
	if party.state ~= Enums.PadState.DEPARTING then
		return
	end
	self:placeHelicopter(party)
	self:setIdle(party)
end

function PartyManager:runLaunch(party: Party)
	local config = self:getConfig()
	task.wait(config.TAKEOFF_SEC)
	local members = self:getPresentMembers(party)
	if #members == 0 then
		self:resetPad(party)
		return
	end
	self:moveToHolding(party, members)
	task.wait(EXIT_MOVE_DELAY_SEC * 2)

	-- a member who left during takeoff is simply excluded
	members = self:getPresentMembers(party)
	local isSuccess = #members > 0 and self:teleportParty(party, members)
	if not isSuccess then
		self:failTeleport(party, members)
		self:resetPad(party)
		return
	end

	task.wait(config.TELEPORT_SETTLE_SEC)
	local stragglers = self:getPresentMembers(party)
	if #stragglers > 0 then
		warn(`PartyManager: {#stragglers} player(s) never left after the teleport call on pad {party.padIndex}`)
		self:failTeleport(party, stragglers)
	end
	self:resetPad(party)
end

-- launch on Launch press, boarding timeout, or capacity countdown; a party
-- of one launches. Clients see Departing and take over the visuals.
function PartyManager:launch(party: Party)
	if party.state ~= Enums.PadState.BOARDING then
		return
	end
	print(`[PartyManager] pad {party.padIndex} launching with {#party.members} player(s)`)
	self:setDeparting(party)
	task.spawn(
		function()
			self:runLaunch(party)
		end
	)
end

function PartyManager:onCreationTimedOut(party: Party)
	local host = self:getHost(party)
	if host then
		PlayerFeedbackManager:give(host, PartyRules.FEEDBACK_CREATION_TIMED_OUT)
		self:leaveParty(host, false)
	else
		self:setIdle(party)
	end
end

function PartyManager:pollTimers()
	local now = workspace:GetServerTimeNow()
	for _, party in self:getParties() do
		if party.timerEndTime == NO_TIMER or now < party.timerEndTime then
			continue
		end
		if party.state == Enums.PadState.CONFIGURING then
			self:onCreationTimedOut(party)
		elseif party.state == Enums.PadState.BOARDING then
			self:launch(party)
		else
			self:clearTimer(party)
		end
	end
end

function PartyManager:handleTryCreateParty(player: Player, payload: { [string]: any })
	local party = self:getPartyOfPlayer(player)
	if not party or party.state ~= Enums.PadState.CONFIGURING or not self:isHost(party, player) then
		warn(`PartyManager: TryCreateParty from {player.Name} who is not configuring a pad`)
		return
	end
	local playerData = GameController:getPlayerData(player)
	if not playerData then
		return
	end
	-- the host's own record decides what is unlocked, never the client's claim
	local isValid, reason = PartyRules.validateSelection(
		self:getConfig(),
		payload,
		function(completionKey: string)
			return playerData:hasCompletion(completionKey)
		end
	)
	if not isValid then
		PlayerFeedbackManager:give(player, reason or "Invalid party settings")
		return
	end
	self:setBoarding(party, payload :: PartyRules.Selection)
	self:notifyMenu(player, Enums.PartyMenu.QUEUE, party)
end

function PartyManager:handleTryLeaveParty(player: Player)
	self:leaveParty(player, false)
end

function PartyManager:handleTryLaunchParty(player: Player)
	local party = self:getPartyOfPlayer(player)
	if not party or party.state ~= Enums.PadState.BOARDING or not self:isHost(party, player) then
		warn(`PartyManager: TryLaunchParty from {player.Name} who is not hosting a boarding pad`)
		return
	end
	self:launch(party)
end

function PartyManager:getNetHandlers()
	return {
		[NetEventNames.TRY_CREATE_PARTY] = {
			shape = PartyRules.SELECTION_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:handleTryCreateParty(player, payload)
			end,
		},
		[NetEventNames.TRY_LEAVE_PARTY] = {
			shape = EMPTY_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:handleTryLeaveParty(player)
			end,
		},
		[NetEventNames.TRY_LAUNCH_PARTY] = {
			shape = EMPTY_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:handleTryLaunchParty(player)
			end,
		},
	}
end

-- teardown entry (registered through GameController:registerPlaceManager);
-- also the dev-tool reset, which must leave the player in no party
function PartyManager:onPlayerRemoved(player: Player)
	self:leaveParty(player, player.Parent ~= Players)
	self.lastTouchTimeByPlayer[player] = nil
end

function PartyManager:findPadModels(): { [number]: Model }
	local modelsByIndex: { [number]: Model } = {}
	local padsFolder = workspace:FindFirstChild(Constants.HELICOPTER_PADS_FOLDER)
	if not padsFolder then
		return modelsByIndex
	end
	for _, pad in padsFolder:GetChildren() do
		if not pad:IsA("Model") then
			continue
		end
		local padIndex = pad:GetAttribute(Attributes.PAD_INDEX)
		if not Validate.isValueType(padIndex, "positiveInteger") or padIndex > Constants.PAD_COUNT then
			continue
		end
		if modelsByIndex[padIndex] then
			continue
		end
		modelsByIndex[padIndex] = pad
	end
	return modelsByIndex
end

function PartyManager:init()
	-- content errors must name the offending key at startup, never at Create
	local problems = PartyRules.validateConfig(PartyData)
	if #problems > 0 then
		error("PartyManager: GameData/Pads/Party is invalid:\n" .. table.concat(problems, "\n"))
	end

	local modelsByIndex = self:findPadModels()
	for padIndex = 1, Constants.PAD_COUNT do
		local model = modelsByIndex[padIndex]
		if not model then
			-- LobbyMapManager already reported the missing pad
			continue
		end
		local party: Party = {
			padIndex = padIndex,
			model = model,
			state = Enums.PadState.IDLE,
			members = {},
			hostUserId = NO_HOST,
			map = nil,
			difficulty = nil,
			maxPlayers = self:getConfig().MAX_PARTY_SIZE,
			visibility = self:getConfig().DEFAULT_VISIBILITY,
			timerEndTime = NO_TIMER,
			helicopter = nil,
			seatByPlayer = {},
		}
		self.partiesByPadIndex[padIndex] = party
		self:setIdle(party)
		self:placeHelicopter(party)
		self:connectTouch(party)
	end

	-- the Create Party menu needs the map and difficulty lists; the client
	-- never requires GameData, so the config travels as one metadata attribute
	SplendidReplicationManager:setGameMetadata(Attributes.PARTY_CONFIG, PartyRules.encodeConfig(self:getConfig()))
	GameController:registerPlaceManager(self)

	task.spawn(
		function()
			while true do
				task.wait(self:getConfig().TIMER_POLL_SEC)
				self:pollTimers()
			end
		end
	)
	print(`[PartyManager] {#self:getParties()} pads ready`)
end

function PartyManager.new(): PartyManager
	local self = setmetatable({}, PartyManager) :: PartyManager
	self.partiesByPadIndex = {}
	self.lastTouchTimeByPlayer = {}
	return self
end

return PartyManager.new()
