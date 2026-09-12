--!strict

-- Arrival at the camp (GDD "Helicopter Pad": players spawn in here after the
-- teleport). The door check: only members of the party this server was
-- reserved for may stay (reserved servers already keep outsiders away; this
-- is the second lock). Players are placed on the pad's spawn parts in arrival
-- order (first to arrive on 1). The camp helicopter sits on the pad with its
-- rotor turning and flies off once every expected member is Ready, or after
-- the arrival timeout. The camp only exists once the run has started and
-- MapManager has loaded the map, so placement waits for run start.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local PartyRules = require("@game/ReplicatedStorage/Shared/PartyRules")
local ArrivalData = require("@game/ServerScriptService/GameData/Run/Arrival")
local GameController = require(script.Parent.Parent.Server.GameController)
local HelicopterManager = require(script.Parent.Parent.Server.HelicopterManager)
local RunManager = require(script.Parent.RunManager)

local ArrivalManager = {}
ArrivalManager.__index = ArrivalManager

export type ArrivalManager = typeof(setmetatable(
	{} :: {
		helicopter: Model?,
		arrivalIndexByUserId: { [number]: number },
		nextArrivalIndex: number,
		firstArrivalTime: number?,
		hasLaunched: boolean,
	},
	ArrivalManager
))

local TIMEOUT_POLL_SEC = 1

function ArrivalManager:getPadModel(): Model?
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	local pad = if camp then camp:FindFirstChild(Constants.CAMP_HELICOPTER_PAD_MODEL) else nil
	if pad and pad:IsA("Model") then
		return pad
	end
	return nil
end

-- spawn parts by their numeric name, so "1" is first
function ArrivalManager:getSpawnParts(): { BasePart }
	local parts: { BasePart } = {}
	local pad = self:getPadModel()
	local spawns = if pad then pad:FindFirstChild(Constants.CAMP_SPAWNS_FOLDER) else nil
	if not spawns then
		return parts
	end
	for _, child in spawns:GetChildren() do
		if child:IsA("BasePart") and tonumber(child.Name) then
			table.insert(parts, child)
		end
	end
	table.sort(
		parts,
		function(a: BasePart, b: BasePart)
			return (tonumber(a.Name) :: number) < (tonumber(b.Name) :: number)
		end
	)
	return parts
end

function ArrivalManager:placeAtSpawn(player: Player, character: Model)
	local parts = self:getSpawnParts()
	if #parts == 0 then
		-- GameplayMapManager already reported the missing spawns
		return
	end
	local index = self.arrivalIndexByUserId[player.UserId] or #parts
	local spawn = parts[math.min(index, #parts)]
	-- the character's parts stream in after CharacterAdded; wait for the root
	local rootPart = character:WaitForChild("HumanoidRootPart", 5)
	if not rootPart then
		return
	end
	character:PivotTo(CFrame.new(spawn.Position + Vector3.new(0, ArrivalData.SPAWN_LIFT_STUDS, 0)) * spawn.CFrame.Rotation)
end

function ArrivalManager:checkGate(player: Player): boolean
	local joinData = player:GetJoinData()
	local teleportData = if joinData then joinData.TeleportData else nil
	local rejection = PartyRules.getArrivalRejection(teleportData, player.UserId)
	if not rejection then
		return true
	end
	-- a Play session in Studio has no teleport data; keep it usable
	if RunService:IsStudio() then
		warn(`ArrivalManager: {player.Name} has no valid party join data (allowed in Studio)`)
		return true
	end
	warn(`ArrivalManager: kicking {player.Name}: {rejection}`)
	player:Kick(rejection)
	return false
end

function ArrivalManager:onPlayerAdded(player: Player)
	if not self:checkGate(player) then
		return
	end
	-- starts the run (and loads the map) on the first arrival, before the
	-- character exists, so placeAtSpawn finds the camp
	RunManager:recordFromPlayer(player)
	if not self.firstArrivalTime then
		self.firstArrivalTime = workspace:GetServerTimeNow()
	end
	self.arrivalIndexByUserId[player.UserId] = self.nextArrivalIndex
	self.nextArrivalIndex += 1
	player.CharacterAdded:Connect(
		function(character: Model)
			self:placeAtSpawn(player, character)
		end
	)
	local character = player.Character
	if character then
		self:placeAtSpawn(player, character)
	end
end

-- everyone the lobby sent is Ready (or, with no run data, everyone here is)
function ArrivalManager:isPartyReady(): boolean
	local readyByUserId: { [number]: boolean } = {}
	for _, player in GameController:getReadyPlayers() do
		readyByUserId[player.UserId] = true
	end
	local run = RunManager:getRun()
	if not run then
		return #Players:GetPlayers() > 0 and #GameController:getReadyPlayers() == #Players:GetPlayers()
	end
	for _, userId in run.memberUserIds do
		if not readyByUserId[userId] then
			return false
		end
	end
	return true
end

function ArrivalManager:launchHelicopter()
	if self.hasLaunched then
		return
	end
	self.hasLaunched = true
	local helicopter = self.helicopter
	if not helicopter then
		return
	end
	print("[ArrivalManager] party aboard; helicopter leaving")
	task.delay(
		ArrivalData.TAKEOFF_DELAY_SEC,
		function()
			HelicopterManager:retire(helicopter, ArrivalData.DEPARTED_HELICOPTER_LIFETIME_SEC)
		end
	)
end

function ArrivalManager:launchIfPartyReady()
	if self.hasLaunched then
		return
	end
	if self:isPartyReady() then
		self:launchHelicopter()
	end
end

-- ready-sequence entry (registered through GameController:registerPlaceManager)
function ArrivalManager:onPlayerReady(player: Player)
	self:launchIfPartyReady()
end

function ArrivalManager:hasArrivalTimedOut(): boolean
	local firstArrivalTime = self.firstArrivalTime
	return firstArrivalTime ~= nil and workspace:GetServerTimeNow() - firstArrivalTime >= ArrivalData.ARRIVAL_TIMEOUT_SEC
end

function ArrivalManager:placeHelicopter()
	local pad = self:getPadModel()
	local spawnPart = if pad then pad:FindFirstChild(Constants.PAD_HELICOPTER_SPAWN_PART) else nil
	if not pad or not spawnPart or not spawnPart:IsA("BasePart") then
		-- GameplayMapManager already reported what is missing
		return
	end
	-- rotor already turning when the party loads in: it just landed
	self.helicopter = HelicopterManager:spawnAt(spawnPart, pad, Enums.HelicopterPhase.SPINNING)
end

-- the map is loaded now (a fresh one on a dev-tool restart, so the old
-- helicopter went with the old camp); place the helicopter and put every
-- present character on its spawn
function ArrivalManager:onRunStarted(_map: number, _difficulty: number)
	if not self.hasLaunched then
		self:placeHelicopter()
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			self:placeAtSpawn(player, character)
		end
	end
end

function ArrivalManager:init()
	RunManager:subscribeRunStarted(
		function(map: number, difficulty: number)
			self:onRunStarted(map, difficulty)
		end
	)
	GameController:registerPlaceManager(self)

	Players.PlayerAdded:Connect(
		function(player: Player)
			self:onPlayerAdded(player)
		end
	)
	for _, player in Players:GetPlayers() do
		self:onPlayerAdded(player)
	end

	task.spawn(
		function()
			while not self.hasLaunched do
				task.wait(TIMEOUT_POLL_SEC)
				if self:hasArrivalTimedOut() then
					warn("ArrivalManager: not every party member arrived in time; leaving without them")
					self:launchHelicopter()
				end
			end
		end
	)
end

function ArrivalManager.new(): ArrivalManager
	local self = setmetatable({}, ArrivalManager) :: ArrivalManager
	self.helicopter = nil
	self.arrivalIndexByUserId = {}
	self.nextArrivalIndex = 1
	self.firstArrivalTime = nil
	self.hasLaunched = false
	return self
end

return ArrivalManager.new()
