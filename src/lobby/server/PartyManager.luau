--!strict

-- Owns one party record per helicopter pad (GDD "Helicopter Pads – Party
-- Creation/Teleports"). State lives here in Lua; the pad model only carries
-- the attributes clients need to render the billboard and menus, and this
-- manager is their only writer. M11 covers records, transitions, and
-- replication; touch handling, timers, and launch arrive in M12 and M13.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local PartyRules = require("@game/ReplicatedStorage/Shared/PartyRules")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local PartyData = require("@game/ServerScriptService/GameData/Pads/Party")

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
}

export type PartyManager = typeof(setmetatable(
	{} :: {
		partiesByPadIndex: { [number]: Party },
	},
	PartyManager
))

local NO_HOST = 0
local NO_TIMER = 0

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
	self:replicate(party)
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
	self:replicate(party)
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
end

function PartyManager:addMember(party: Party, player: Player)
	if table.find(party.members, player) then
		return
	end
	table.insert(party.members, player)
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
	if #party.members == 0 then
		self:setIdle(party)
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
		}
		self.partiesByPadIndex[padIndex] = party
		self:setIdle(party)
	end
	print(`[PartyManager] {#self:getParties()} pads ready`)
end

function PartyManager.new(): PartyManager
	local self = setmetatable({}, PartyManager) :: PartyManager
	self.partiesByPadIndex = {}
	return self
end

return PartyManager.new()
