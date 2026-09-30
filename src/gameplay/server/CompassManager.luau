--!strict

-- The Compass (GDD "Compass"): bought once in the Mining Supplies Store.
-- Owning it is run state held here (level 1 = not owned, 2 = owned, the
-- shape every store track has) and published privately so the client shows
-- the bar. What the bar draws is published for everyone, owner or not: the
-- Refinery's position once per run, and each player's position a few times
-- a second with the dot colour they keep for the run. Positions go through
-- the replication folders because streaming hides far characters (and the
-- Refinery) from a client deep in the mine.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local CompassRules = require("@game/ReplicatedStorage/Shared/CompassRules")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local CompassData = require("@game/ServerScriptService/GameData/Mining/Compass")
local GameController = require(script.Parent.Parent.Server.GameController)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local MapManager = require(script.Parent.MapManager)

local CompassManager = {}
CompassManager.__index = CompassManager

export type CompassManager = typeof(setmetatable(
	{} :: {
		levelByPlayer: { [Player]: number },
		colorIndexByPlayer: { [Player]: number },
		publishedPositionByPlayer: { [Player]: Vector3 },
		sincePublishSec: number,
	},
	CompassManager
))

local STARTING_LEVEL = 1

function CompassManager:getLevel(player: Player): number
	return self.levelByPlayer[player] or STARTING_LEVEL
end

function CompassManager:replicate(player: Player)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.COMPASS_LEVEL, self:getLevel(player))
end

function CompassManager:setLevel(player: Player, level: number)
	if not self.levelByPlayer[player] then
		return
	end
	self.levelByPlayer[player] = level
	self:replicate(player)
end

function CompassManager:assignColorIndex(player: Player): number
	local takenIndexes: { [number]: boolean } = {}
	for _, index in self.colorIndexByPlayer do
		takenIndexes[index] = true
	end
	local index = CompassRules.lowestFreeIndex(takenIndexes, CompassData.PLAYER_COLOR_COUNT)
	self.colorIndexByPlayer[player] = index
	return index
end

-- whole studs, so a player standing still publishes nothing
function CompassManager:publishPosition(player: Player)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	local position = root.Position
	local rounded = Vector3.new(math.round(position.X), math.round(position.Y), math.round(position.Z))
	if self.publishedPositionByPlayer[player] == rounded then
		return
	end
	self.publishedPositionByPlayer[player] = rounded
	SplendidReplicationManager:setPublicAttribute(player, Attributes.COMPASS_POSITION, rounded)
end

function CompassManager:step(deltaSec: number)
	self.sincePublishSec += deltaSec
	if self.sincePublishSec < CompassData.POSITION_PUBLISH_INTERVAL_SEC then
		return
	end
	self.sincePublishSec = 0
	for _, player in GameController:getReadyPlayers() do
		if self.levelByPlayer[player] then
			self:publishPosition(player)
		end
	end
end

-- the home icon points at the fresh camp's Refinery
function CompassManager:onRunStarted()
	local camp = MapManager:getCamp()
	local refinery = if camp then camp:FindFirstChild(Constants.CAMP_REFINERY_MODEL) else nil
	if not refinery or not refinery:IsA("PVInstance") then
		warn("CompassManager: the loaded camp has no Refinery; the compass has no home")
		return
	end
	SplendidReplicationManager:setGameMetadata(Attributes.COMPASS_HOME_POSITION, refinery:GetPivot().Position)
end

-- ready-sequence entry; not replayed on a dev-tool reset, so run state survives
function CompassManager:onPlayerReady(player: Player)
	if not self.levelByPlayer[player] then
		self.levelByPlayer[player] = STARTING_LEVEL
		self:assignColorIndex(player)
	end
	self:replicate(player)
	SplendidReplicationManager:setPublicAttribute(player, Attributes.COMPASS_COLOR_INDEX, self.colorIndexByPlayer[player])
	self.publishedPositionByPlayer[player] = nil
	self:publishPosition(player)
end

function CompassManager:init()
	GameController:registerPlaceManager(self)
	SplendidReplicationManager:setGameMetadata(Attributes.COMPASS_FIELD_OF_VIEW_DEGREES, CompassData.FIELD_OF_VIEW_DEGREES)
	SplendidReplicationManager:setGameMetadata(Attributes.COMPASS_DOT_FULL_SIZE_STUDS, CompassData.DOT_FULL_SIZE_STUDS)
	SplendidReplicationManager:setGameMetadata(Attributes.COMPASS_DOT_SMALLEST_STUDS, CompassData.DOT_SMALLEST_STUDS)
	SplendidReplicationManager:setGameMetadata(Attributes.COMPASS_DOT_SMALLEST_SCALE, CompassData.DOT_SMALLEST_SCALE)
	SplendidReplicationManager:setGameMetadata(Attributes.COMPASS_VERTICAL_HINT_STUDS, CompassData.VERTICAL_HINT_STUDS)
	-- not a teardown entry: a dev-tool reset must not strip the run's purchases
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self.levelByPlayer[player] = nil
			self.colorIndexByPlayer[player] = nil
			self.publishedPositionByPlayer[player] = nil
		end
	)
	RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self:step(deltaSec)
		end
	)
end

function CompassManager.new(): CompassManager
	local self = setmetatable({}, CompassManager) :: CompassManager
	self.levelByPlayer = {}
	self.colorIndexByPlayer = {}
	self.publishedPositionByPlayer = {}
	self.sincePublishSec = 0
	return self
end

return CompassManager.new()
